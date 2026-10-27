--[[
	Server-authoritative turn combat for one hero against 1 to 3 enemies.

	Pure Luau: no Roblox instances, so it runs in tests and can be replayed
	from a seed. The server's CombatService wraps it with remotes.

	Public API
		Combat.new(content, config)
		combat:start()
		combat:playCard(uid, targetId)        -> ok, err
		combat:endTurn()                      -> ok, err
		combat:resolveQte(qteId, grade)       -> ok, err
		combat:getSnapshot()                  -> what the player can see
		combat:takeEvents()                   -> ordered events to animate

	QTEs
		A card with a `qte` field, or an enemy move with a `defenseQte` field,
		pauses the combat in the "AwaitingQte" phase with `pendingQte` set. The
		server runs the QTE with the client, grades it (QteJudge) and calls
		resolveQte, which resumes exactly where it stopped. Turn logic runs in
		a coroutine so a pause can happen in the middle of a card or an enemy
		turn. Pass config.qteHandler (request -> grade) to resolve QTEs
		synchronously instead, as tests and bots do.

	config
		seed          number
		encounter     id in Content.Encounters (enemies, hero and deck)
		hero          hero class id (overrides the encounter's)
		deck          list of card ids or { id, upgrade } (overrides)
		heroHp        starting HP carried in from the run (defaults to max)
		heroMaxHp     max HP carried in from the run (defaults to the class's)
		relics        relic ids the hero carries (Data/Relics): energy, and
		              combatStart / turnStart effects
		qteHandler    optional synchronous QTE resolver
		qteDifficultyBonus  added to enemy QTE difficulty (acts 2 and 3)
		wideQteWindows      accessibility: +50% QTE windows
]]

local EffectResolver = require("./EffectResolver")
local EnemyAI = require("./EnemyAI")
local Rng = require("./Rng")
local StatusSystem = require("./StatusSystem")

local Combat = {}
Combat.__index = Combat

local SALT_SHUFFLE = 0x1F2E3D4C
local SALT_AI = 0x5A6B7C8D
local SALT_COMBAT = 0x0BADF00D
local SALT_SETUP = 0x13579BDF

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Layers a QTE bonus onto a card's effects (see Data/Cards for the rule).
function Combat.applyQteBonus(baseEffects, qte, grade: string?)
	local bonus = nil
	if grade == "Perfect" then
		bonus = qte.perfect
	elseif grade == "Good" then
		bonus = qte.good
	end
	local effects = deepCopy(baseEffects)
	if not bonus then
		return effects
	end
	for _, extra in bonus do
		local merged = false
		if extra.op == "Damage" or extra.op == "Block" then
			for _, effect in effects do
				if effect.op == extra.op and effect.target == extra.target then
					effect.amount = (effect.amount or 0) + (extra.amount or 0)
					merged = true
					break
				end
			end
		end
		if not merged then
			table.insert(effects, deepCopy(extra))
		end
	end
	return effects
end

function Combat.new(content, config)
	local self = setmetatable({}, Combat)
	self.content = content
	self.config = config
	self.qteHandler = config.qteHandler

	local root = Rng.new(config.seed or 1)
	self.rng = {
		shuffle = root:fork(SALT_SHUFFLE),
		ai = root:fork(SALT_AI),
		combat = root:fork(SALT_COMBAT),
		setup = root:fork(SALT_SETUP),
	}

	local encounter = config.encounter and content.Encounters[config.encounter]
	if config.encounter and not encounter then
		error(`unknown encounter {config.encounter}`)
	end
	local heroId = config.hero or (encounter and encounter.hero) or "Warden"
	local heroDef = content.Heroes[heroId]
	assert(heroDef, `unknown hero {heroId}`)
	self.heroDef = heroDef

	self.hero = {
		id = "hero",
		side = "Hero",
		defId = heroId,
		name = heroDef.name,
		maxHp = config.heroMaxHp or heroDef.maxHp,
		hp = config.heroHp or config.heroMaxHp or heroDef.maxHp,
		block = 0,
		statuses = {},
		freshStatuses = {},
		alive = true,
	}

	self.enemies = {}
	local enemyIds = config.enemies or (encounter and encounter.enemies) or {}
	for index, enemyId in enemyIds do
		local def = content.Enemies[enemyId]
		assert(def, `unknown enemy {enemyId}`)
		local hp = self.rng.setup:int(def.hp[1], def.hp[2])
		table.insert(self.enemies, {
			id = `e{index}`,
			side = "Enemy",
			defId = enemyId,
			name = def.name,
			maxHp = hp,
			hp = hp,
			block = 0,
			statuses = {},
			freshStatuses = {},
			alive = true,
			ai = EnemyAI.newState(),
			intent = nil,
		})
	end

	self.nextUid = 0
	self.drawPile = {}
	self.hand = {}
	self.discardPile = {}
	self.exhaustPile = {}
	self.powers = {}
	self.resolving = nil -- the card being played, between hand and its pile

	local deck = config.deck or (encounter and encounter.deck) or heroDef.starterDeck
	for _, entry in deck do
		local card = if type(entry) == "string" then { id = entry } else { id = entry.id, upgrade = entry.upgrade }
		assert(content.getCard(card.id, card.upgrade), `unknown card {card.id}`)
		table.insert(self.drawPile, self:_newCard(card.id, card.upgrade))
	end

	self.relics = {}
	for _, relicId in config.relics or {} do
		local relic = content.Relics[relicId]
		assert(relic, `unknown relic {relicId}`)
		table.insert(self.relics, relic)
	end

	self.energy = 0
	self.maxEnergy = heroDef.energy
	for _, relic in self.relics do
		self.maxEnergy += relic.energy or 0
	end
	self.conserve = false
	self.turn = 0
	self.phase = "NotStarted"
	self.events = {}
	self.nextQteId = 0
	self.pendingQte = nil
	self._co = nil
	return self
end

-- Events ----------------------------------------------------------------------

function Combat:emit(eventType: string, data: { [string]: any }?)
	local event = data or {}
	event.type = eventType
	table.insert(self.events, event)
end

function Combat:takeEvents()
	local events = self.events
	self.events = {}
	return events
end

-- Queries ---------------------------------------------------------------------

function Combat:isOver(): boolean
	return self.phase == "Won" or self.phase == "Lost"
end

function Combat:livingEnemies()
	local list = {}
	for _, enemy in self.enemies do
		if enemy.alive then
			table.insert(list, enemy)
		end
	end
	return list
end

function Combat:opponentsOf(unit)
	if unit.side == "Hero" then
		return self:livingEnemies()
	end
	return self.hero.alive and { self.hero } or {}
end

-- How many different statuses of one kind (Buff, Debuff, DoT) a unit has.
function Combat:countStatusKinds(unit, kind: string): number
	local count = 0
	for id in unit.statuses do
		if self.content.Statuses[id].kind == kind then
			count += 1
		end
	end
	return count
end

-- A class passive's damage multiplier on an enemy: `amp` is
-- { kind, minKinds, mult } from the hero def (Catalyst, Malice).
function Combat:_passiveMult(unit, amp): number
	if amp and unit.side == "Enemy" and self:countStatusKinds(unit, amp.kind) >= amp.minKinds then
		return amp.mult
	end
	return 1
end

function Combat:getUnit(id: string)
	if id == "hero" then
		return self.hero
	end
	for _, enemy in self.enemies do
		if enemy.id == id then
			return enemy
		end
	end
	return nil
end

function Combat:getCardDef(card)
	return self.content.getCard(card.id, card.upgrade)
end

function Combat:_newCard(id: string, upgrade: string?)
	self.nextUid += 1
	return { uid = `c{self.nextUid}`, id = id, upgrade = upgrade }
end

local function findCard(pile, uid: string)
	for index, card in pile do
		if card.uid == uid then
			return index, card
		end
	end
	return nil, nil
end

function Combat:_checkEnd()
	if self:isOver() then
		return
	end
	if not self.hero.alive then
		self.phase = "Lost"
		self.pendingQte = nil
		self:emit("CombatEnded", { result = "Lost" })
	elseif #self:livingEnemies() == 0 then
		self.phase = "Won"
		self.pendingQte = nil
		self:emit("CombatEnded", { result = "Won", heroHp = self.hero.hp })
	end
end

-- Damage, Block, HP -----------------------------------------------------------

-- Attack damage before Block: base + Strength, x1.5 Vulnerable, x0.75 Weak,
-- rounded down.
function Combat:computeAttackDamage(source, target, base: number): number
	local value = base
	if source then
		value = StatusSystem.modify(self, source, "ModifyDamageDealt", value)
	end
	if target then
		value = StatusSystem.modify(self, target, "ModifyDamageTaken", value)
		value *= self:_passiveMult(target, self.heroDef.debuffAmp)
	end
	return math.max(0, math.floor(value + 1e-9))
end

-- One hit of an attack, including the hero's defensive QTE when the enemy
-- move has a defenseQte.
function Combat:attack(source, target, base: number, ctx, hit: number, hits: number)
	local amount = self:computeAttackDamage(source, target, base)
	local defense = ctx.defenseQte
	if defense and target.side == "Hero" and source.side == "Enemy" then
		local qte = self.content.Qte
		local windowMult = self:qteWindowMult()
		if hits > 1 then
			windowMult *= qte.MultiHitWindowMult
		end
		-- Dazed on the attacker makes its hits easier to read.
		windowMult *= StatusSystem.modify(self, source, "ModifyAttackerQteWindow", 1)
		local grade = self:_requestQte({
			source = "Defense",
			kind = defense.kind,
			difficulty = (defense.difficulty or 1) + (self.config.qteDifficultyBonus or 0),
			windowMult = windowMult,
			enemyId = source.id,
			moveId = ctx.moveId,
			hit = hit,
			hits = hits,
			incoming = amount,
		})
		if self:isOver() then
			return
		end
		local mult
		if grade == "Perfect" then
			mult = defense.perfect or qte.DefenseDefaults.perfect
			self:_onPerfectDefense(source)
		elseif grade == "Good" then
			mult = defense.good or qte.DefenseDefaults.good
		else
			mult = 1
		end
		if mult <= 0 then
			self:emit("Dodged", { targetId = target.id, sourceId = source.id, grade = grade, prevented = amount })
			return
		end
		amount = math.floor(amount * mult + 1e-9)
	end
	self:applyDamage(target, amount, { source = source, isAttack = true })
end

-- `attacker` is the enemy whose hit was defended: class hooks can target it.
function Combat:_onPerfectDefense(attacker)
	local effects = self.heroDef.onPerfectDefense
	if effects then
		EffectResolver.run(self, effects, { source = self.hero, target = attacker, defaultTarget = "Self" })
	end
end

-- Damage that hits Block first, then HP. opts: { source, isAttack }.
function Combat:applyDamage(target, amount: number, opts)
	if not target.alive or amount < 0 then
		return
	end
	local blocked = math.min(target.block, amount)
	target.block -= blocked
	local hpLoss = amount - blocked
	target.hp -= hpLoss
	self:emit("Damage", {
		targetId = target.id,
		sourceId = opts.source and opts.source.id,
		amount = amount,
		blocked = blocked,
		hpLoss = hpLoss,
		isAttack = opts.isAttack == true,
	})
	if opts.isAttack and opts.source then
		StatusSystem.trigger(self, target, "OnHit", { attacker = opts.source })
	end
	self:_checkDeath(target)
end

-- HP loss that ignores Block (Poison, Bleed, card costs).
function Combat:loseHp(target, amount: number)
	if not target.alive or amount <= 0 then
		return
	end
	target.hp -= amount
	self:emit("LoseHp", { targetId = target.id, amount = amount })
	self:_checkDeath(target)
end

-- DoT damage after the Alchemist's Catalyst, rounded to the nearest whole
-- number (Poison 2 with Catalyst deals 3, not 2).
function Combat:_catalyst(target, amount: number): number
	return math.floor(amount * self:_passiveMult(target, self.heroDef.dotAmp) + 0.5)
end

-- Damage from a DoT status (Poison and Bleed ignore Block, Burn hits it),
-- raised by the Alchemist's Catalyst.
function Combat:dotDamage(target, amount: number, ignoreBlock: boolean)
	amount = self:_catalyst(target, amount)
	if ignoreBlock then
		self:loseHp(target, amount)
	else
		self:applyDamage(target, amount, { isAttack = false })
	end
end

-- Consumes every stack of a status on `target` for `mult` damage per stack
-- (Detonate cards). Hits Block; Catalyst counts the status being consumed.
function Combat:detonate(source, target, statusId: string, mult: number)
	local stacks = target.statuses[statusId] or 0
	if not target.alive or stacks <= 0 then
		return
	end
	local amount = self:_catalyst(target, stacks * mult)
	self:removeStatus(target, statusId)
	self:emit("Detonated", { targetId = target.id, sourceId = source.id, status = statusId, stacks = stacks })
	self:applyDamage(target, amount, { source = source, isAttack = false })
end

-- Takes `count` random buffs off `target` and gives them, with all their
-- stacks, to `source` (Siphon cards).
function Combat:siphon(source, target, count: number)
	for _ = 1, count do
		if not target.alive or not source.alive then
			return
		end
		local buffs = {}
		for _, id in StatusSystem.sortedIds(self.content, target) do
			if self.content.Statuses[id].kind == "Buff" then
				table.insert(buffs, id)
			end
		end
		if #buffs == 0 then
			return
		end
		local id = buffs[self.rng.combat:int(1, #buffs)]
		local stacks = target.statuses[id]
		self:removeStatus(target, id)
		self:emit("Siphoned", { targetId = target.id, sourceId = source.id, status = id, stacks = stacks })
		self:applyStatus(source, id, stacks, source)
	end
end

-- Moves every debuff and DoT on `source` onto `target` (Transfer cards).
function Combat:transferDebuffs(source, target)
	if not target.alive then
		return
	end
	for _, id in StatusSystem.sortedIds(self.content, source) do
		local kind = self.content.Statuses[id].kind
		if kind == "Debuff" or kind == "DoT" then
			local stacks = source.statuses[id]
			self:removeStatus(source, id)
			self:emit("Transferred", { targetId = target.id, sourceId = source.id, status = id, stacks = stacks })
			self:applyStatus(target, id, stacks, source)
		end
	end
end

function Combat:_checkDeath(unit)
	if unit.alive and unit.hp <= 0 then
		unit.hp = 0
		unit.alive = false
		unit.block = 0
		self:emit("Died", { unitId = unit.id })
		self:_checkEnd()
	end
end

function Combat:heal(target, amount: number)
	if not target.alive or amount <= 0 then
		return
	end
	local healed = math.min(amount, target.maxHp - target.hp)
	target.hp += healed
	self:emit("Heal", { targetId = target.id, amount = healed })
end

function Combat:gainBlock(unit, base: number)
	if not unit.alive then
		return
	end
	local amount = StatusSystem.modify(self, unit, "ModifyBlockGained", base)
	amount = math.max(0, math.floor(amount + 1e-9))
	unit.block += amount
	self:emit("Block", { targetId = unit.id, amount = amount, total = unit.block })
end

function Combat:gainEnergy(amount: number)
	self.energy += amount
	self:emit("Energy", { amount = amount, total = self.energy })
end

-- Statuses --------------------------------------------------------------------

-- Adds (or with a negative number removes) stacks, without hooks or events.
function Combat:addStatus(unit, id: string, delta: number)
	local stacks = (unit.statuses[id] or 0) + delta
	if stacks <= 0 then
		unit.statuses[id] = nil
		unit.freshStatuses[id] = nil
	else
		unit.statuses[id] = stacks
	end
end

function Combat:removeStatus(unit, id: string)
	unit.statuses[id] = nil
	unit.freshStatuses[id] = nil
end

function Combat:applyStatus(unit, id: string, stacks: number, source)
	if not unit.alive or stacks == 0 then
		return
	end
	local def = self.content.Statuses[id]
	assert(def, `unknown status {id}`)
	-- Malice: the hero's debuffs on enemies last extra rounds.
	local extend = self.heroDef.debuffExtend
	if extend and stacks > 0 and def.kind == "Debuff" and def.decay == "Round"
		and source and source.side == "Hero" and unit.side == "Enemy" then
		stacks += extend
	end
	self:addStatus(unit, id, stacks)
	if unit.side == "Hero" and self:_actingSide() == "Enemy" then
		unit.freshStatuses[id] = true
	end
	self:emit("StatusApplied", {
		targetId = unit.id,
		sourceId = source and source.id,
		status = id,
		stacks = stacks,
		total = unit.statuses[id] or 0,
	})
	local hook = def.OnApplied
	if hook and unit.statuses[id] then
		hook({ combat = self, owner = unit, stacks = unit.statuses[id], statusId = id, added = stacks })
	end
end

function Combat:_actingSide()
	local phase = self.resumePhase or self.phase
	return phase == "EnemyTurn" and "Enemy" or "Hero"
end

-- QTE window multiplier from Focus / Dazed and accessibility.
function Combat:qteWindowMult(): number
	local qte = self.content.Qte
	local mult = StatusSystem.modify(self, self.hero, "ModifyQteWindow", 1)
	mult = math.max(qte.MinWindowMult, mult)
	if self.config.wideQteWindows then
		mult *= qte.WideWindowMult
	end
	return mult
end

-- Piles -----------------------------------------------------------------------

function Combat:draw(count: number)
	for _ = 1, count do
		if #self.hand >= self.heroDef.maxHand then
			self:emit("HandFull", {})
			return
		end
		if #self.drawPile == 0 then
			if #self.discardPile == 0 then
				return
			end
			self.drawPile = self.discardPile
			self.discardPile = {}
			self.rng.shuffle:shuffle(self.drawPile)
			self:emit("Reshuffled", { count = #self.drawPile })
		end
		local card = table.remove(self.drawPile)
		table.insert(self.hand, card)
		self:emit("CardDrawn", { uid = card.uid, cardId = card.id })
	end
end

function Combat:addCardToPile(cardId: string, pile: string, count: number, upgrade: string?)
	for _ = 1, count do
		local card = self:_newCard(cardId, upgrade)
		if pile == "Hand" and #self.hand < self.heroDef.maxHand then
			table.insert(self.hand, card)
		elseif pile == "Draw" then
			table.insert(self.drawPile, self.rng.shuffle:int(1, #self.drawPile + 1), card)
		else
			pile = "Discard"
			table.insert(self.discardPile, card)
		end
		self:emit("CardAdded", { uid = card.uid, cardId = cardId, pile = pile })
	end
end

function Combat:exhaustRandomFromHand(count: number)
	for _ = 1, count do
		if #self.hand == 0 then
			return
		end
		local card = table.remove(self.hand, self.rng.combat:int(1, #self.hand))
		self:_exhaust(card)
	end
end

function Combat:_exhaust(card)
	table.insert(self.exhaustPile, card)
	self:emit("CardExhausted", { uid = card.uid, cardId = card.id })
end

-- Coroutine plumbing ----------------------------------------------------------

function Combat:_resume(co, ...)
	local ok, result = coroutine.resume(co, ...)
	if not ok then
		self._co = nil
		error(debug.traceback(co, tostring(result)), 0)
	end
	if coroutine.status(co) == "dead" then
		self._co = nil
	else
		self._co = co
	end
end

function Combat:_run(fn, ...)
	assert(self._co == nil, "combat is already running a step")
	self:_resume(coroutine.create(fn), self, ...)
end

-- Pauses the running step until resolveQte, or asks qteHandler directly.
function Combat:_requestQte(request)
	self.nextQteId += 1
	request.qteId = `q{self.nextQteId}`
	request.difficulty = math.clamp(request.difficulty or 1, 1, 5)

	local grade
	if self.qteHandler then
		self:emit("QteStarted", { qteId = request.qteId, source = request.source, kind = request.kind })
		grade = self.qteHandler(request)
	else
		assert(coroutine.isyieldable(), "a QTE needs to run inside a combat step")
		self.resumePhase = self.phase
		self.phase = "AwaitingQte"
		self.pendingQte = request
		self:emit("QteStarted", { qteId = request.qteId, source = request.source, kind = request.kind })
		grade = coroutine.yield(request)
		self.phase = self.resumePhase
		self.resumePhase = nil
		self.pendingQte = nil
	end
	if self.content.Qte.GradeRank[grade] == nil then
		grade = "Miss"
	end
	self:emit("QteGraded", { qteId = request.qteId, source = request.source, grade = grade })
	StatusSystem.trigger(self, self.hero, "OnQteGraded", { grade = grade, request = request })
	return grade
end

function Combat:resolveQte(qteId: string, grade: string)
	local pending = self.pendingQte
	if not pending or self.phase ~= "AwaitingQte" then
		return false, "no QTE is pending"
	end
	if pending.qteId ~= qteId then
		return false, "wrong QTE id"
	end
	if self.content.Qte.GradeRank[grade] == nil then
		return false, "invalid grade"
	end
	self:_resume(self._co, grade)
	return true
end

-- Turn flow -------------------------------------------------------------------

function Combat:start()
	assert(self.phase == "NotStarted", "combat already started")
	self.rng.shuffle:shuffle(self.drawPile)
	-- Innate cards go on top so they are in the opening hand.
	local innate, rest = {}, {}
	for _, card in self.drawPile do
		local def = self:getCardDef(card)
		if def.keywords and def.keywords.Innate then
			table.insert(innate, card)
		else
			table.insert(rest, card)
		end
	end
	for _, card in innate do
		table.insert(rest, card)
	end
	self.drawPile = rest

	self.phase = "Starting"
	self:emit("CombatStarted", { heroId = self.hero.defId, enemies = #self.enemies })
	self:_run(Combat._startCombatStep)
end

function Combat:_startCombatStep()
	self:_triggerRelics("combatStart")
	if self:isOver() then
		return
	end
	self:_startPlayerTurn()
end

function Combat:_triggerRelics(hook: string)
	for _, relic in self.relics do
		local effects = relic[hook]
		if effects then
			self:emit("RelicTriggered", { relicId = relic.id, hook = hook })
			EffectResolver.run(self, effects, { source = self.hero, defaultTarget = "Self" })
		end
	end
end

function Combat:_rollIntents()
	for _, enemy in self:livingEnemies() do
		local def = self.content.Enemies[enemy.defId]
		local moveId = EnemyAI.choose(def, enemy, self.rng.ai, self)
		enemy.intent = { moveId = moveId }
	end
end

function Combat:_startPlayerTurn()
	self.turn += 1
	self:_rollIntents()

	local hero = self.hero
	if self.turn > 1 and hero.block > 0 then
		if (hero.statuses.Fortify or 0) == 0 then
			hero.block = math.floor(hero.block * (self.heroDef.blockRetain or 0))
		end
	end
	self.phase = "PlayerTurn"
	StatusSystem.trigger(self, hero, "OnTurnStart")
	if self:isOver() then
		return
	end

	local carry = self.conserve and math.min(self.energy, 2) or 0
	self.conserve = false
	self.energy = self.maxEnergy + carry
	self:emit("TurnStarted", { turn = self.turn, energy = self.energy })
	self:_triggerRelics("turnStart")
	if self:isOver() then
		return
	end
	self:draw(self.heroDef.drawPerTurn)
end

function Combat:canPlay(card): (boolean, string?)
	local def = self:getCardDef(card)
	if def.keywords and def.keywords.Unplayable then
		return false, "card is unplayable"
	end
	if def.type == "Curse" or def.type == "Wound" then
		return false, "card is unplayable"
	end
	if def.cost ~= "X" and def.cost > self.energy then
		return false, "not enough energy"
	end
	return true
end

function Combat:playCard(uid: string, targetId: string?)
	if self.phase ~= "PlayerTurn" or self._co then
		return false, "not your turn"
	end
	local index, card = findCard(self.hand, uid)
	if not card then
		return false, "card not in hand"
	end
	local ok, err = self:canPlay(card)
	if not ok then
		return false, err
	end
	local def = self:getCardDef(card)
	local target = nil
	if def.target == "Enemy" then
		target = targetId and self:getUnit(targetId)
		if not target or target.side ~= "Enemy" or not target.alive then
			return false, "invalid target"
		end
	end
	table.remove(self.hand, index)
	self:_run(Combat._playCardStep, card, def, target)
	return true
end

function Combat:_playCardStep(card, def, target)
	local cost = if def.cost == "X" then self.energy else def.cost
	self.energy -= cost
	self.resolving = card
	self:emit("CardPlayed", { uid = card.uid, cardId = card.id, targetId = target and target.id, cost = cost })

	local effects = def.effects
	local grade = nil
	if def.qte then
		grade = self:_requestQte({
			source = "Card",
			kind = def.qte.kind,
			difficulty = def.qte.difficulty or 1,
			windowMult = self:qteWindowMult(),
			uid = card.uid,
			cardId = card.id,
			targetId = target and target.id,
		})
		effects = Combat.applyQteBonus(def.effects, def.qte, grade)
	end

	local defaultTarget = "Self"
	if def.target == "Enemy" then
		defaultTarget = "Target"
	elseif def.target == "AllEnemies" then
		defaultTarget = "AllEnemies"
	end
	EffectResolver.run(self, effects, {
		source = self.hero,
		target = target,
		defaultTarget = defaultTarget,
		x = cost,
		card = card,
		qteGrade = grade,
	})

	if def.keywords and def.keywords.Conserve then
		self.conserve = true
	end
	self.resolving = nil
	if def.type == "Power" then
		table.insert(self.powers, card)
		self:emit("PowerPlayed", { uid = card.uid, cardId = card.id })
	elseif def.keywords and (def.keywords.Exhaust or def.keywords.Vanish) then
		self:_exhaust(card)
	else
		table.insert(self.discardPile, card)
	end
end

function Combat:endTurn()
	if self.phase ~= "PlayerTurn" or self._co then
		return false, "not your turn"
	end
	self:_run(Combat._endTurnStep)
	return true
end

function Combat:_endTurnStep()
	local hero = self.hero
	-- Player turn end.
	local kept = {}
	for _, card in self.hand do
		local keywords = self:getCardDef(card).keywords or {}
		if keywords.Retain then
			table.insert(kept, card)
		elseif keywords.Ethereal then
			self:_exhaust(card)
		else
			table.insert(self.discardPile, card)
		end
	end
	self.hand = kept
	self:emit("TurnEnded", { turn = self.turn })
	StatusSystem.trigger(self, hero, "OnTurnEnd")
	if self:isOver() then
		return
	end

	-- Enemy turn, left to right.
	self.phase = "EnemyTurn"
	for _, enemy in self.enemies do
		if not enemy.alive then
			continue
		end
		if (enemy.statuses.Fortify or 0) == 0 then
			enemy.block = 0
		end
		StatusSystem.trigger(self, enemy, "OnTurnStart")
		if self:isOver() then
			return
		end
		if enemy.alive then
			self:_enemyAct(enemy)
			if self:isOver() then
				return
			end
		end
		if enemy.alive then
			StatusSystem.trigger(self, enemy, "OnTurnEnd")
			if self:isOver() then
				return
			end
		end
	end

	-- Round end.
	for _, unit in { hero, table.unpack(self.enemies) } do
		if unit.alive then
			StatusSystem.trigger(self, unit, "OnRoundEnd")
			StatusSystem.decayRound(self, unit)
		end
	end
	if self:isOver() then
		return
	end
	self:_startPlayerTurn()
end

function Combat:_enemyAct(enemy)
	local moveId = enemy.intent and enemy.intent.moveId
	if not moveId then
		return
	end
	if (enemy.statuses.Stun or 0) > 0 then
		self:addStatus(enemy, "Stun", -1)
		self:emit("Stunned", { unitId = enemy.id, moveId = moveId })
		return
	end
	local move = self.content.Enemies[enemy.defId].moves[moveId]
	self:emit("EnemyMove", { unitId = enemy.id, moveId = moveId, intent = move.intent })
	EffectResolver.run(self, move.effects, {
		source = enemy,
		target = self.hero,
		defaultTarget = "Hero",
		defenseQte = move.defenseQte,
		moveId = moveId,
	})
end

-- Snapshot --------------------------------------------------------------------

local function publicUnit(unit)
	return {
		id = unit.id,
		defId = unit.defId,
		name = unit.name,
		hp = unit.hp,
		maxHp = unit.maxHp,
		block = unit.block,
		statuses = table.clone(unit.statuses),
		alive = unit.alive,
	}
end

-- The intent the player sees, with damage already including the enemy's
-- Strength and Weak and the hero's Vulnerable.
function Combat:describeIntent(enemy)
	if not enemy.alive or not enemy.intent then
		return nil
	end
	local move = self.content.Enemies[enemy.defId].moves[enemy.intent.moveId]
	local intent = { moveId = move.id, type = move.intent }
	for _, effect in move.effects do
		if effect.op == "Damage" then
			intent.damage = self:computeAttackDamage(enemy, self.hero, effect.amount or 0)
			intent.hits = effect.hits or 1
			break
		end
	end
	if move.defenseQte then
		intent.defenseQte = { kind = move.defenseQte.kind, difficulty = move.defenseQte.difficulty or 1 }
	end
	return intent
end

function Combat:getSnapshot()
	local enemies = {}
	for _, enemy in self.enemies do
		local view = publicUnit(enemy)
		view.intent = self:describeIntent(enemy)
		table.insert(enemies, view)
	end
	local hand = {}
	for _, card in self.hand do
		local def = self:getCardDef(card)
		table.insert(hand, {
			uid = card.uid,
			id = card.id,
			upgrade = card.upgrade,
			name = def.name,
			cost = def.cost,
			type = def.type,
			target = def.target,
			text = def.text,
			qte = def.qte and { kind = def.qte.kind, difficulty = def.qte.difficulty or 1 } or nil,
			playable = self.phase == "PlayerTurn" and (self:canPlay(card)),
		})
	end
	local relicIds = {}
	for _, relic in self.relics do
		table.insert(relicIds, relic.id)
	end
	local pending = self.pendingQte
	return {
		turn = self.turn,
		phase = self.phase,
		energy = self.energy,
		maxEnergy = self.maxEnergy,
		hero = publicUnit(self.hero),
		enemies = enemies,
		hand = hand,
		drawCount = #self.drawPile,
		discardCount = #self.discardPile,
		exhaustCount = #self.exhaustPile,
		powers = #self.powers,
		relics = relicIds,
		pendingQte = pending and {
			qteId = pending.qteId,
			source = pending.source,
			kind = pending.kind,
			difficulty = pending.difficulty,
		} or nil,
	}
end

return Combat
