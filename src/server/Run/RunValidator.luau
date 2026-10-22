--[[
	Checks the run content: acts (map rules, encounter pools, event lists),
	events (requirements, checks, effect ops) and relic pickups. The combat
	side is ContentValidator's job; the tests and the server run both.
]]

local RunEffects = require("./RunEffects")

local RunValidator = {}

local REQUIREMENTS = { Gold = true, MinHp = true, CardType = true, Relic = true, Hero = true, Upgradable = true, Removable = true }
local CHECKS = { CountType = true, TotalCost = true, CountQte = true, CountUpgraded = true }
local NODE_TYPES = { Combat = true, Elite = true, Event = true, Rest = true, Shop = true, Treasure = true, Boss = true }

local function checkEffects(content, effects, where: string, errors)
	if type(effects) ~= "table" then
		table.insert(errors, `{where}: effects must be a list`)
		return
	end
	for i, effect in effects do
		local at = `{where}[{i}]`
		if not RunEffects.ops[effect.op] then
			table.insert(errors, `{at}: unknown run op {tostring(effect.op)}`)
		elseif effect.op == "AddCard" and not content.Cards[effect.card] then
			table.insert(errors, `{at}: unknown card {tostring(effect.card)}`)
		elseif effect.op == "GainRelic" and effect.relic and not content.Relics[effect.relic] then
			table.insert(errors, `{at}: unknown relic {tostring(effect.relic)}`)
		elseif effect.op == "Fight" and not content.Encounters[effect.encounter] then
			table.insert(errors, `{at}: unknown encounter {tostring(effect.encounter)}`)
		end
	end
end

function RunValidator.validate(content): { string }
	local errors = {}

	for id, event in content.Events do
		local canLeave = false
		for index, option in event.options do
			local where = `Events.{id}.options[{index}]`
			if not option.requires or #option.requires == 0 then
				canLeave = true
			end
			for _, req in option.requires or {} do
				if not REQUIREMENTS[req.kind] then
					table.insert(errors, `{where}: unknown requirement {tostring(req.kind)}`)
				elseif req.kind == "Relic" and not content.Relics[req.relic] then
					table.insert(errors, `{where}: unknown relic {tostring(req.relic)}`)
				elseif req.kind == "Hero" and not content.Heroes[req.hero] then
					table.insert(errors, `{where}: unknown hero {tostring(req.hero)}`)
				end
			end
			checkEffects(content, option.cost or {}, `{where}.cost`, errors)
			if option.check then
				if not CHECKS[option.check.kind] then
					table.insert(errors, `{where}: unknown card check {tostring(option.check.kind)}`)
				end
				if not option.success or not option.failure then
					table.insert(errors, `{where}: a card check needs success and failure`)
				end
				checkEffects(content, option.success and option.success.effects or {}, `{where}.success`, errors)
				checkEffects(content, option.failure and option.failure.effects or {}, `{where}.failure`, errors)
			elseif not option.outcome then
				table.insert(errors, `{where}: needs an outcome`)
			else
				checkEffects(content, option.outcome.effects or {}, `{where}.outcome`, errors)
			end
		end
		if not canLeave then
			table.insert(errors, `Events.{id}: needs an option with no requirement`)
		end
	end

	for id, relic in content.Relics do
		checkEffects(content, relic.onPickup or {}, `Relics.{id}.onPickup`, errors)
	end

	for index, act in content.Acts do
		local where = `Acts[{index}]`
		for row, nodeType in act.map.fixed or {} do
			if not NODE_TYPES[nodeType] then
				table.insert(errors, `{where}.map.fixed[{row}]: unknown node type {nodeType}`)
			end
		end
		for nodeType in act.map.weights do
			if not NODE_TYPES[nodeType] then
				table.insert(errors, `{where}.map.weights: unknown node type {nodeType}`)
			end
		end
		for pool, ids in act.encounters do
			if #ids == 0 then
				table.insert(errors, `{where}.encounters.{pool}: empty`)
			end
			for _, encounterId in ids do
				if not content.Encounters[encounterId] then
					table.insert(errors, `{where}.encounters.{pool}: unknown encounter {encounterId}`)
				end
			end
		end
		for _, eventId in act.events do
			if not content.Events[eventId] then
				table.insert(errors, `{where}.events: unknown event {eventId}`)
			end
		end
	end

	table.sort(errors)
	return errors
end

return RunValidator
