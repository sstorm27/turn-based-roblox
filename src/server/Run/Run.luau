--[[
	One roguelike run for one hero: acts of seeded maps, the encounters on
	them, rewards, shops, rests and events. Server-authoritative and pure Luau
	(no Roblox instances), like the combat engine it drives.

	A run is always on one screen:
		Map          pick a path card (chooseNode)
		Combat       run.combat is a live Combat; the server drives it and
		             calls run:checkCombat() after each action
		Reward       gold (and an elite's relic) already granted; pick 1 card
		             or skip
		RelicChoice  the boss's pick 1 of 3 relics, or skip
		Event        pick an option; EventResult shows the outcome, then proceed
		Shop         buy cards, relics, a removal or an upgrade; proceed to leave
		Rest         heal, upgrade a card, or remove one (once per act)
		Treasure     a relic chest; proceed
		SelectCard   pick a deck card to upgrade (with path A or B) or remove
		Won, Lost    the run is over; one death ends it

	Screens that follow another (a reward after a fight, an event's fight, the
	shop after a removal) wait on a stack. When the stack empties the player
	is back on the map, or in the next act after a boss.

	Public API (every action returns ok, err)
		Run.new(content, config)
		run:chooseNode(nodeId)
		run:chooseOption(index)      Event, Rest, Reward (card), RelicChoice
		run:skip()                   Reward, RelicChoice
		run:proceed()                EventResult, Treasure, Shop (leave)
		run:buy(item, index?)        Shop: "Card", "Relic", "Remove", "Upgrade"
		run:selectCard(uid, path?)   SelectCard
		run:cancel()                 SelectCard, when it came from a shop or rest
		run:perform(action)          one table-shaped action from the client
		run:checkCombat()            -> true once a finished fight was handled
		run:getSnapshot()            what the player can see

	config
		seed, hero (default "Warden")
		qteHandler, wideQteWindows    passed to each Combat
]]

local Combat = require("../Combat/Combat")
local Rng = require("../Combat/Rng")
local EventRunner = require("./EventRunner")
local MapGenerator = require("./MapGenerator")
local Rewards = require("./Rewards")
local RunEffects = require("./RunEffects")

local Run = {}
Run.__index = Run

local SALT_MAP = 0x4D415053
local SALT_COMBAT = 0x46494754
local SALT_REWARDS = 0x52574453
local SALT_EVENTS = 0x45564E54
local SALT_SHOP = 0x53484F50

function Run.new(content, config)
	local self = setmetatable({}, Run)
	self.content = content
	self.config = config
	self.seed = config.seed or 1

	local root = Rng.new(self.seed)
	self.rng = {
		map = root:fork(SALT_MAP),
		combat = root:fork(SALT_COMBAT),
		rewards = root:fork(SALT_REWARDS),
		events = root:fork(SALT_EVENTS),
		shop = root:fork(SALT_SHOP),
	}

	self.heroId = config.hero or "Warden"
	self.heroDef = content.Heroes[self.heroId]
	assert(self.heroDef, `unknown hero {self.heroId}`)
	self.maxHp = self.heroDef.maxHp
	self.hp = self.maxHp
	self.gold = content.RunRules.startingGold

	self.nextUid = 0
	self.deck = {}
	for _, cardId in self.heroDef.starterDeck do
		self:addCard(cardId)
	end
	self.relics = {}
	self.relicSet = {}

	self.seenEvents = {}
	self.shopRemovals = 0
	self.stats = { rows = 0, elites = 0, bosses = 0, fights = 0 }
	self.stack = {}
	self.combat = nil
	self.over = false

	self:_startAct(1)
	return self
end

-- Deck, HP, gold, relics ------------------------------------------------------

function Run:addCard(cardId: string, upgrade: string?)
	assert(self.content.Cards[cardId], `unknown card {cardId}`)
	self.nextUid += 1
	local card = { uid = `d{self.nextUid}`, id = cardId, upgrade = upgrade }
	table.insert(self.deck, card)
	return card
end

function Run:findCard(uid: string)
	for index, card in self.deck do
		if card.uid == uid then
			return index, card
		end
	end
	return nil, nil
end

function Run:removeCard(uid: string): boolean
	local index = self:findCard(uid)
	if not index then
		return false
	end
	table.remove(self.deck, index)
	return true
end

function Run:isUpgradable(card): boolean
	local def = self.content.Cards[card.id]
	return card.upgrade == nil and def.upgrades ~= nil and next(def.upgrades) ~= nil
end

function Run:upgradeCard(uid: string, path: string): boolean
	local _, card = self:findCard(uid)
	if not card or not self:isUpgradable(card) then
		return false
	end
	if not self.content.Cards[card.id].upgrades[path] then
		return false
	end
	card.upgrade = path
	return true
end

-- Deck cards a SelectCard screen may pick for a purpose.
function Run:cardsFor(purpose: string): { string }
	local uids = {}
	for _, card in self.deck do
		if purpose == "Upgrade" and not self:isUpgradable(card) then
			continue
		end
		table.insert(uids, card.uid)
	end
	-- Never remove the last card.
	if purpose == "Remove" and #uids < 2 then
		return {}
	end
	return uids
end

function Run:gainGold(amount: number)
	self.gold = math.max(0, self.gold + amount)
end

function Run:heal(amount: number)
	self.hp = math.clamp(self.hp + math.max(0, amount), 0, self.maxHp)
end

function Run:loseHp(amount: number)
	self.hp = math.max(0, self.hp - amount)
end

function Run:changeMaxHp(delta: number)
	self.maxHp = math.max(1, self.maxHp + delta)
	if delta > 0 then
		self.hp += delta
	end
	self.hp = math.min(self.hp, self.maxHp)
end

function Run:hasRelic(relicId: string): boolean
	return self.relicSet[relicId] == true
end

-- Gains a relic (a random one if relicId is nil). With none left, pays 50 gold
-- instead. Returns the relic id, or nil.
function Run:gainRelic(relicId: string?): string?
	if relicId == nil then
		relicId = Rewards.rollRelic(self.content, self.rng.rewards, self.relicSet, self.content.RunRules.relicOdds)
	end
	if relicId == nil or self.relicSet[relicId] then
		self:gainGold(50)
		return nil
	end
	local relic = self.content.Relics[relicId]
	assert(relic, `unknown relic {relicId}`)
	table.insert(self.relics, relicId)
	self.relicSet[relicId] = true
	if relic.onPickup then
		RunEffects.apply(self, relic.onPickup)
	end
	return relicId
end

function Run:_relicSum(field: string): number
	local total = 0
	for _, id in self.relics do
		total += self.content.Relics[id][field] or 0
	end
	return total
end

function Run:_restHealMult(): number
	local mult = 1
	for _, id in self.relics do
		local relicMult = self.content.Relics[id].restHealMult
		if relicMult then
			mult *= relicMult
		end
	end
	return mult
end

function Run:renown(): number
	local rules = self.content.RunRules.renown
	local total = self.stats.rows * rules.perRow + self.stats.elites * rules.elite + self.stats.bosses * rules.boss
	if self.screen and self.screen.kind == "Won" then
		total += rules.win
	end
	return total
end

-- Acts and the map ------------------------------------------------------------

function Run:_startAct(index: number)
	self.actIndex = index
	self.act = self.content.Acts[index]
	assert(self.act, `unknown act {index}`)
	self.map = MapGenerator.generate(self.act.map, self.rng.map)
	self.currentNodeId = nil
	self.visited = {}
	self.actFights = 0
	self.restRemoveUsed = false
	self.lastEncounter = nil
	self.screen = { kind = "Map" }
end

function Run:pathChoices(): { string }
	return MapGenerator.choices(self.map, self.currentNodeId)
end

function Run:chooseNode(nodeId: string)
	if self.screen.kind ~= "Map" then
		return false, "not on the map"
	end
	if not table.find(self:pathChoices(), nodeId) then
		return false, "node not reachable"
	end
	local node = self.map.nodes[nodeId]
	self.currentNodeId = nodeId
	self.visited[nodeId] = true
	self.stats.rows += 1

	local kind = node.type
	if kind == "Combat" or kind == "Elite" or kind == "Boss" then
		self:_show({ kind = "Combat", fightKind = kind })
	else
		self:_show({ kind = kind })
	end
	return true
end

-- Screen flow -------------------------------------------------------------------

function Run:_push(step)
	table.insert(self.stack, step)
end

-- Queues steps to show in the given order once the current screen is done.
function Run:_queue(steps: { any })
	for i = #steps, 1, -1 do
		self:_push(steps[i])
	end
end

-- Moves to the next screen: a waiting one, else the map or the next act.
function Run:_next()
	if self.hp <= 0 then
		self:_lose()
		return
	end
	local step = table.remove(self.stack)
	if step then
		self:_show(step)
		return
	end
	local node = self.currentNodeId and self.map.nodes[self.currentNodeId]
	if node and node.type == "Boss" then
		if self.content.Acts[self.actIndex + 1] then
			self:_startAct(self.actIndex + 1)
		else
			self.screen = { kind = "Won" }
			self.over = true
		end
		return
	end
	self.screen = { kind = "Map" }
end

function Run:_lose()
	self.hp = 0
	self.combat = nil
	self.stack = {}
	self.screen = { kind = "Lost" }
	self.over = true
end

-- Builds a screen from a step and makes it current. Steps that turn out to
-- have nothing to show skip ahead.
function Run:_show(step)
	local kind = step.kind
	if step.ready then
		self.screen = step
	elseif kind == "Combat" then
		self:_startCombat(step)
	elseif kind == "Reward" then
		self:_showReward(step)
	elseif kind == "Event" then
		self:_showEvent()
	elseif kind == "Shop" then
		local shop = Rewards.rollShop(self.content, self.heroId, self.rng.shop, self.relicSet, self.shopRemovals)
		shop.kind = "Shop"
		shop.ready = true
		self.screen = shop
	elseif kind == "Rest" then
		self.screen = { kind = "Rest", ready = true }
	elseif kind == "Treasure" then
		self.screen = { kind = "Treasure", ready = true, relicId = self:gainRelic(nil) }
	elseif kind == "RelicChoice" then
		local relics = Rewards.rollRelics(self.content, self.rng.rewards, self.relicSet, {}, step.count or 3, true)
		if #relics == 0 then
			self:_next()
			return
		end
		self.screen = { kind = "RelicChoice", ready = true, relics = relics }
	elseif kind == "SelectCard" then
		local candidates = self:cardsFor(step.purpose)
		if #candidates == 0 then
			if step.cancelTo then
				self.screen = step.cancelTo
			else
				self:_next()
			end
			return
		end
		step.candidates = candidates
		step.ready = true
		self.screen = step
	else
		error(`unknown screen {kind}`)
	end
end

-- Combat ---------------------------------------------------------------------------

function Run:_pickEncounter(fightKind: string): string
	local pools = self.act.encounters
	local pool
	if fightKind == "Boss" then
		pool = pools.boss
	elseif fightKind == "Elite" then
		pool = pools.elite
	elseif self.actFights < (self.act.easyFights or 0) then
		pool = pools.easy
	else
		pool = pools.normal
	end
	local options = {}
	for _, id in pool do
		if id ~= self.lastEncounter or #pool == 1 then
			table.insert(options, id)
		end
	end
	return options[self.rng.combat:int(1, #options)]
end

function Run:_startCombat(step)
	local fightKind = step.fightKind
	local encounterId = step.encounterId or self:_pickEncounter(fightKind)
	if fightKind == "Combat" then
		self.actFights += 1
	end
	self.lastEncounter = encounterId

	local deck = {}
	for _, card in self.deck do
		table.insert(deck, { id = card.id, upgrade = card.upgrade })
	end
	self.combat = Combat.new(self.content, {
		seed = self.rng.combat:nextU32(),
		hero = self.heroId,
		enemies = self.content.Encounters[encounterId].enemies,
		deck = deck,
		heroHp = self.hp,
		heroMaxHp = self.maxHp,
		relics = table.clone(self.relics),
		qteHandler = self.config.qteHandler,
		wideQteWindows = self.config.wideQteWindows,
		qteDifficultyBonus = self.actIndex - 1,
	})
	self.screen = {
		kind = "Combat",
		ready = true,
		fightKind = fightKind,
		encounterId = encounterId,
		gold = step.gold,
	}
	self.combat:start()
	self:checkCombat()
end

-- Call after every combat action. Once the fight is over it hands out the
-- rewards (or ends the run) and returns true.
function Run:checkCombat(): boolean
	local combat = self.combat
	if not combat or not combat:isOver() or self.screen.kind ~= "Combat" then
		return false
	end
	local screen = self.screen
	self.combat = nil
	if combat.phase == "Lost" then
		self:_lose()
		return true
	end
	self.hp = math.clamp(combat.hero.hp, 1, self.maxHp)
	self.stats.fights += 1
	if screen.fightKind == "Elite" then
		self.stats.elites += 1
	elseif screen.fightKind == "Boss" then
		self.stats.bosses += 1
	end
	self:_show({ kind = "Reward", source = screen.fightKind, gold = screen.gold })
	return true
end

-- Rewards ------------------------------------------------------------------------

function Run:_showReward(step)
	local rules = self.content.RunRules.rewards
	local source = step.source
	local fight = rules[source] or rules.Combat
	local screen = { kind = "Reward", ready = true, source = source, gold = 0 }

	if source ~= "Event" then
		local gold = step.gold or self.rng.rewards:int(fight.gold[1], fight.gold[2])
		self:gainGold(gold)
		screen.gold = gold
		if fight.relic then
			screen.relicId = self:gainRelic(nil)
		end
		if fight.fullHeal then
			self:heal(self.maxHp)
		end
		if fight.bossRelics then
			self:_push({ kind = "RelicChoice", count = fight.bossRelics })
		end
	end

	local odds = if step.rarity then { [step.rarity] = 1 } else fight.odds
	local count = math.max(1, fight.cards + self:_relicSum("cardRewardSize"))
	screen.cards = Rewards.rollCards(self.content, self.heroId, self.rng.rewards, odds, count)
	if #screen.cards == 0 then
		self:_next()
		return
	end
	self.screen = screen
end

-- Events -------------------------------------------------------------------------

function Run:_showEvent()
	local options = {}
	for _, id in self.act.events do
		if not self.seenEvents[id] then
			table.insert(options, id)
		end
	end
	if #options == 0 then
		-- Out of events: the node plays as a normal fight.
		self:_show({ kind = "Combat", fightKind = "Combat" })
		return
	end
	local eventId = options[self.rng.events:int(1, #options)]
	self.seenEvents[eventId] = true
	self.screen = { kind = "Event", ready = true, eventId = eventId }
end

-- Actions --------------------------------------------------------------------------

function Run:chooseOption(index: number)
	local screen = self.screen
	local kind = screen.kind
	if type(index) ~= "number" then
		return false, "bad option"
	end
	if kind == "Event" then
		local event = self.content.Events[screen.eventId]
		local result, err = EventRunner.choose(self, event, index)
		if not result then
			return false, err
		end
		self.screen = {
			kind = "EventResult",
			ready = true,
			eventId = screen.eventId,
			label = result.label,
			text = result.text,
			success = result.success,
			revealed = result.revealed,
			steps = result.steps,
		}
		if self.hp <= 0 then
			self:_lose()
		end
		return true
	elseif kind == "Rest" then
		local options = self:_restOptions()
		local option = options[index]
		if not option then
			return false, "no such option"
		end
		if not option.available then
			return false, "option not available"
		end
		if option.id == "Heal" then
			self:heal(option.amount)
			self:_next()
		elseif option.id == "Upgrade" then
			self:_show({ kind = "SelectCard", purpose = "Upgrade", cancelTo = screen })
		elseif option.id == "Remove" then
			self:_show({ kind = "SelectCard", purpose = "Remove", cancelTo = screen, fromRest = true })
		end
		return true
	elseif kind == "Reward" then
		local cardId = screen.cards[index]
		if not cardId then
			return false, "no such card"
		end
		self:addCard(cardId)
		self:_next()
		return true
	elseif kind == "RelicChoice" then
		local relicId = screen.relics[index]
		if not relicId then
			return false, "no such relic"
		end
		self:gainRelic(relicId)
		self:_next()
		return true
	end
	return false, "nothing to choose"
end

function Run:skip()
	local kind = self.screen.kind
	if kind ~= "Reward" and kind ~= "RelicChoice" then
		return false, "nothing to skip"
	end
	self:_next()
	return true
end

function Run:proceed()
	local screen = self.screen
	if screen.kind == "EventResult" then
		self:_queue(screen.steps)
		self:_next()
		return true
	elseif screen.kind == "Treasure" or screen.kind == "Shop" then
		self:_next()
		return true
	end
	return false, "can't proceed from here"
end

function Run:_restOptions()
	local healAmount = math.floor(self.maxHp * self.content.RunRules.rest.healPercent * self:_restHealMult())
	return {
		{ id = "Heal", amount = healAmount, available = healAmount > 0 },
		{ id = "Upgrade", available = #self:cardsFor("Upgrade") > 0 },
		{ id = "Remove", available = not self.restRemoveUsed and #self:cardsFor("Remove") > 0 },
	}
end

function Run:buy(item: string, index: number?)
	local shop = self.screen
	if shop.kind ~= "Shop" then
		return false, "not in a shop"
	end
	if item == "Card" or item == "Relic" then
		local list = if item == "Card" then shop.cards else shop.relics
		local entry = type(index) == "number" and list[index]
		if not entry then
			return false, "no such item"
		end
		if entry.sold then
			return false, "sold out"
		end
		if self.gold < entry.price then
			return false, "not enough gold"
		end
		self:gainGold(-entry.price)
		entry.sold = true
		if item == "Card" then
			self:addCard(entry.cardId)
		else
			self:gainRelic(entry.relicId)
		end
		return true
	elseif item == "Remove" or item == "Upgrade" then
		local service = if item == "Remove" then shop.remove else shop.upgrade
		if service.used then
			return false, "already used here"
		end
		if self.gold < service.price then
			return false, "not enough gold"
		end
		if #self:cardsFor(item) == 0 then
			return false, "no card to pick"
		end
		-- Paid when the card is picked; the shop comes back afterwards.
		self:_push(shop)
		self:_show({ kind = "SelectCard", purpose = item, price = service.price, service = service, cancellable = true })
		return true
	end
	return false, "unknown item"
end

function Run:selectCard(uid: string, path: string?)
	local screen = self.screen
	if screen.kind ~= "SelectCard" then
		return false, "not picking a card"
	end
	if type(uid) ~= "string" or not table.find(screen.candidates, uid) then
		return false, "card can't be picked"
	end
	if screen.purpose == "Upgrade" then
		if type(path) ~= "string" or not self:upgradeCard(uid, path) then
			return false, "bad upgrade path"
		end
	else
		self:removeCard(uid)
	end
	if screen.price then
		self:gainGold(-screen.price)
	end
	if screen.service then
		screen.service.used = true
		if screen.purpose == "Remove" then
			self.shopRemovals += 1
		end
	end
	if screen.fromRest then
		self.restRemoveUsed = true
	end
	self:_next()
	return true
end

function Run:cancel()
	local screen = self.screen
	if screen.kind ~= "SelectCard" then
		return false, "nothing to cancel"
	end
	if screen.cancelTo then
		self.screen = screen.cancelTo
	elseif screen.cancellable then
		self:_next()
	else
		return false, "this pick can't be cancelled"
	end
	return true
end

-- One action from the client, as a table: { kind = "Option", index } and so
-- on. Unknown or badly shaped actions are rejected.
function Run:perform(action)
	if type(action) ~= "table" then
		return false, "bad action"
	end
	if self.over then
		return false, "the run is over"
	end
	local kind = action.kind
	if kind == "Option" then
		return self:chooseOption(action.index)
	elseif kind == "Skip" then
		return self:skip()
	elseif kind == "Proceed" then
		return self:proceed()
	elseif kind == "Buy" then
		return self:buy(action.item, action.index)
	elseif kind == "Select" then
		return self:selectCard(action.uid, action.path)
	elseif kind == "Cancel" then
		return self:cancel()
	end
	return false, "unknown action"
end

-- Snapshot -------------------------------------------------------------------------

function Run:cardView(card)
	local def = self.content.getCard(card.id, card.upgrade)
	return {
		uid = card.uid,
		id = card.id,
		upgrade = card.upgrade,
		name = def.name,
		cost = def.cost,
		type = def.type,
		rarity = def.rarity,
		text = def.text,
		qte = def.qte and def.qte.kind or nil,
		upgradable = card.uid ~= nil and self:isUpgradable(card),
	}
end

function Run:_relicView(relicId: string)
	local relic = self.content.Relics[relicId]
	return { id = relicId, name = relic.name, rarity = relic.rarity, text = relic.text }
end

function Run:_nodeTypeView(nodeType: string)
	local info = self.content.RunRules.nodeTypes[nodeType] or { name = nodeType, hint = "" }
	return info.name, info.hint
end

-- The map as the player sees it: an act progress bar, the 2 or 3 path cards,
-- and the full graph for the "View full map" button.
function Run:_mapView()
	local map = self.map
	local currentRow = self.currentNodeId and map.nodes[self.currentNodeId].row or 0
	local stops = {}
	local fixed = self.act.map.fixed or {}
	for row = 2, map.rowCount do
		if fixed[row] then
			table.insert(stops, { row = row, type = fixed[row] })
		end
	end

	local pathCards = {}
	if self.screen.kind == "Map" then
		for _, id in self:pathChoices() do
			local node = map.nodes[id]
			local name, hint = self:_nodeTypeView(node.type)
			local leadsTo, seen = {}, {}
			for _, nextId in node.next do
				local nextType = map.nodes[nextId].type
				if not seen[nextType] then
					seen[nextType] = true
					table.insert(leadsTo, nextType)
				end
			end
			table.insert(pathCards, { nodeId = id, type = node.type, name = name, hint = hint, leadsTo = leadsTo })
		end
	end

	local nodes = {}
	for row = 1, map.rowCount do
		for _, id in map.rows[row] do
			local node = map.nodes[id]
			table.insert(nodes, {
				id = id,
				row = node.row,
				col = node.col,
				type = node.type,
				next = table.clone(node.next),
				visited = self.visited[id] == true,
			})
		end
	end

	return {
		progress = { act = self.actIndex, actName = self.act.name, row = currentRow, rows = map.rowCount, stops = stops },
		pathCards = pathCards,
		currentNodeId = self.currentNodeId,
		columns = map.columns,
		nodes = nodes,
	}
end

function Run:_screenView()
	local screen = self.screen
	local kind = screen.kind
	local view: { [string]: any } = { kind = kind }
	if kind == "Combat" then
		view.fightKind = screen.fightKind
		view.encounter = self.content.Encounters[screen.encounterId].name
	elseif kind == "Reward" then
		view.source = screen.source
		view.gold = screen.gold
		view.relic = screen.relicId and self:_relicView(screen.relicId)
		view.cards = {}
		for _, cardId in screen.cards do
			table.insert(view.cards, self:cardView({ id = cardId }))
		end
	elseif kind == "RelicChoice" then
		view.relics = {}
		for _, relicId in screen.relics do
			table.insert(view.relics, self:_relicView(relicId))
		end
	elseif kind == "Event" then
		view.event = EventRunner.view(self, self.content.Events[screen.eventId])
	elseif kind == "EventResult" then
		local event = self.content.Events[screen.eventId]
		view.name = event.name
		view.label = screen.label
		view.text = screen.text
		view.success = screen.success
		view.revealed = screen.revealed
	elseif kind == "Shop" then
		view.cards = {}
		for _, entry in screen.cards do
			local card = self:cardView({ id = entry.cardId })
			table.insert(view.cards, { card = card, price = entry.price, sold = entry.sold, onSale = entry.onSale == true })
		end
		view.relics = {}
		for _, entry in screen.relics do
			table.insert(view.relics, { relic = self:_relicView(entry.relicId), price = entry.price, sold = entry.sold })
		end
		view.remove = { price = screen.remove.price, used = screen.remove.used }
		view.upgrade = { price = screen.upgrade.price, used = screen.upgrade.used }
	elseif kind == "Rest" then
		view.options = self:_restOptions()
	elseif kind == "Treasure" then
		view.relic = screen.relicId and self:_relicView(screen.relicId)
	elseif kind == "SelectCard" then
		view.purpose = screen.purpose
		view.price = screen.price
		view.cancellable = screen.cancellable == true or screen.cancelTo ~= nil
		view.candidates = table.clone(screen.candidates)
	elseif kind == "Won" or kind == "Lost" then
		view.renown = self:renown()
		view.stats = table.clone(self.stats)
	end
	return view
end

function Run:getSnapshot()
	local deck = {}
	for _, card in self.deck do
		table.insert(deck, self:cardView(card))
	end
	local relics = {}
	for _, id in self.relics do
		table.insert(relics, self:_relicView(id))
	end
	return {
		seed = self.seed,
		phase = self.screen.kind,
		over = self.over,
		hero = { id = self.heroId, name = self.heroDef.name, hp = self.hp, maxHp = self.maxHp },
		gold = self.gold,
		act = self.actIndex,
		actCount = #self.content.Acts,
		deck = deck,
		relics = relics,
		map = self:_mapView(),
		screen = self:_screenView(),
		renown = self:renown(),
	}
end

return Run
