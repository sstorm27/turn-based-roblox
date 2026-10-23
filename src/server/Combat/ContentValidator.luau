--[[
	Checks that content tables only reference things that exist: effect ops,
	statuses, cards, QTE kinds, enemy moves and encounters. Run by the tests and
	once at server start, so a typo in data fails loudly instead of mid-fight.
]]

local EffectResolver = require("./EffectResolver")

local ContentValidator = {}

local TARGETS = {
	Self = true,
	Target = true,
	Hero = true,
	AllEnemies = true,
	RandomEnemy = true,
	AllAllies = true,
}
local CARD_TARGETS = { Enemy = true, AllEnemies = true, Self = true, None = true }
local CARD_TYPES = { Attack = true, Skill = true, Power = true, Curse = true, Wound = true }

local function checkEffects(content, effects, where: string, errors)
	if type(effects) ~= "table" then
		table.insert(errors, `{where}: effects must be a list`)
		return
	end
	for i, effect in effects do
		local at = `{where}[{i}]`
		if not EffectResolver.ops[effect.op] then
			table.insert(errors, `{at}: unknown op {tostring(effect.op)}`)
		end
		if effect.target ~= nil and not TARGETS[effect.target] then
			table.insert(errors, `{at}: unknown target {tostring(effect.target)}`)
		end
		if effect.op == "ApplyStatus" and not content.Statuses[effect.status] then
			table.insert(errors, `{at}: unknown status {tostring(effect.status)}`)
		end
		if effect.op == "Detonate" and not content.Statuses[effect.status] then
			table.insert(errors, `{at}: unknown status {tostring(effect.status)}`)
		end
		if effect.op == "AddCard" and not content.Cards[effect.card] then
			table.insert(errors, `{at}: unknown card {tostring(effect.card)}`)
		end
		if effect.op == "Repeat" then
			checkEffects(content, effect.effects, `{at}.effects`, errors)
		elseif effect.op == "If" then
			checkEffects(content, effect["then"] or {}, `{at}.then`, errors)
			checkEffects(content, effect["else"] or {}, `{at}.else`, errors)
		end
	end
end

local function checkQte(content, qte, where: string, errors)
	if not content.Qte.Kinds[qte.kind] then
		table.insert(errors, `{where}: unknown QTE kind {tostring(qte.kind)}`)
	end
	local d = qte.difficulty or 1
	if type(d) ~= "number" or d < 1 or d > 5 then
		table.insert(errors, `{where}: difficulty must be 1 to 5`)
	end
end

local function checkPattern(enemy, pattern, where: string, errors)
	local function hasMove(id)
		if not enemy.moves[id] then
			table.insert(errors, `{where}: unknown move {tostring(id)}`)
		end
	end
	if pattern.kind == "Cycle" then
		for _, id in pattern.order do
			hasMove(id)
		end
	elseif pattern.kind == "Weighted" then
		for _, entry in pattern.moves do
			hasMove(entry[1])
		end
	elseif pattern.kind == "Conditional" then
		for _, rule in pattern.rules do
			hasMove(rule.move)
		end
		checkPattern(enemy, pattern.fallback, `{where}.fallback`, errors)
	else
		table.insert(errors, `{where}: unknown pattern {tostring(pattern.kind)}`)
	end
end

function ContentValidator.validate(content): { string }
	local errors = {}

	for id, card in content.Cards do
		local variants = { [""] = card }
		for path in card.upgrades or {} do
			variants["+" .. path] = content.getCard(id, path)
		end
		for suffix, def in variants do
			local where = `Cards.{id}{suffix}`
			if not CARD_TYPES[def.type] then
				table.insert(errors, `{where}: unknown type {tostring(def.type)}`)
			end
			if not CARD_TARGETS[def.target] then
				table.insert(errors, `{where}: unknown target rule {tostring(def.target)}`)
			end
			if def.cost ~= "X" and type(def.cost) ~= "number" then
				table.insert(errors, `{where}: cost must be a number or "X"`)
			end
			checkEffects(content, def.effects, `{where}.effects`, errors)
			if def.qte then
				checkQte(content, def.qte, `{where}.qte`, errors)
				checkEffects(content, def.qte.good or {}, `{where}.qte.good`, errors)
				checkEffects(content, def.qte.perfect or {}, `{where}.qte.perfect`, errors)
			end
		end
	end

	for id, status in content.Statuses do
		local decay = status.decay
		if decay ~= "Round" and decay ~= "Halve" and decay ~= "Tick" and decay ~= "Clear" and decay ~= "Permanent" then
			table.insert(errors, `Statuses.{id}: unknown decay {tostring(decay)}`)
		end
	end

	for id, enemy in content.Enemies do
		for moveId, move in enemy.moves do
			local where = `Enemies.{id}.moves.{moveId}`
			checkEffects(content, move.effects, where, errors)
			if move.defenseQte then
				checkQte(content, move.defenseQte, `{where}.defenseQte`, errors)
			end
		end
		checkPattern(enemy, enemy.pattern, `Enemies.{id}.pattern`, errors)
	end

	for id, hero in content.Heroes do
		for _, cardId in hero.starterDeck do
			if not content.Cards[cardId] then
				table.insert(errors, `Heroes.{id}.starterDeck: unknown card {cardId}`)
			end
		end
		checkEffects(content, hero.onPerfectDefense or {}, `Heroes.{id}.onPerfectDefense`, errors)
	end

	for id, relic in content.Relics or {} do
		checkEffects(content, relic.combatStart or {}, `Relics.{id}.combatStart`, errors)
		checkEffects(content, relic.turnStart or {}, `Relics.{id}.turnStart`, errors)
	end

	for id, encounter in content.Encounters do
		for _, enemyId in encounter.enemies do
			if not content.Enemies[enemyId] then
				table.insert(errors, `Encounters.{id}: unknown enemy {enemyId}`)
			end
		end
		if encounter.hero and not content.Heroes[encounter.hero] then
			table.insert(errors, `Encounters.{id}: unknown hero {encounter.hero}`)
		end
		for _, entry in encounter.deck or {} do
			local cardId = if type(entry) == "string" then entry else entry.id
			if not content.Cards[cardId] then
				table.insert(errors, `Encounters.{id}.deck: unknown card {tostring(cardId)}`)
			end
		end
	end

	table.sort(errors)
	return errors
end

return ContentValidator
