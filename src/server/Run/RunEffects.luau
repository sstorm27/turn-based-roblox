--[[
	Run effect ops: what event outcomes, event costs and relic pickups do to
	the run (gold, HP, deck, relics). Most apply at once. The interactive ones
	(ChooseUpgrade, ChooseRemove, CardReward, Fight) return a screen step that
	the run shows after the current screen, in order.
]]

local Rewards = require("./Rewards")

local RunEffects = {}

local ops = {}

function ops.GainGold(run, effect)
	run:gainGold(effect.amount)
end

function ops.LoseGold(run, effect)
	run:gainGold(-effect.amount)
end

function ops.Heal(run, effect)
	local amount = effect.amount or math.floor(run.maxHp * (effect.percent or 0))
	run:heal(amount)
end

function ops.LoseHp(run, effect)
	run:loseHp(effect.amount)
end

function ops.GainMaxHp(run, effect)
	run:changeMaxHp(effect.amount)
end

function ops.LoseMaxHp(run, effect)
	run:changeMaxHp(-effect.amount)
end

function ops.AddCard(run, effect)
	run:addCard(effect.card, effect.upgrade)
end

function ops.AddRandomCard(run, effect)
	local odds = if effect.rarity then { [effect.rarity] = 1 } else run.content.RunRules.rewards.Combat.odds
	local ids = Rewards.rollCards(run.content, run.heroId, run.rng.rewards, odds, 1)
	if ids[1] then
		run:addCard(ids[1])
	end
end

local function randomCards(run, filter, count: number)
	local candidates = {}
	for _, card in run.deck do
		if filter(card) then
			table.insert(candidates, card)
		end
	end
	local picked = {}
	for _ = 1, count do
		if #candidates == 0 then
			break
		end
		table.insert(picked, table.remove(candidates, run.rng.events:int(1, #candidates)))
	end
	return picked
end

local function ofType(run, cardType: string?)
	return function(card)
		return cardType == nil or run.content.getCard(card.id, card.upgrade).type == cardType
	end
end

function ops.UpgradeRandom(run, effect)
	local isType = ofType(run, effect.type)
	local cards = randomCards(run, function(card)
		return run:isUpgradable(card) and isType(card)
	end, effect.count or 1)
	for _, card in cards do
		local paths = {}
		for path in run.content.Cards[card.id].upgrades do
			table.insert(paths, path)
		end
		table.sort(paths)
		run:upgradeCard(card.uid, paths[run.rng.events:int(1, #paths)])
	end
end

function ops.RemoveRandom(run, effect)
	for _, card in randomCards(run, ofType(run, effect.type), effect.count or 1) do
		run:removeCard(card.uid)
	end
end

function ops.GainRelic(run, effect)
	run:gainRelic(effect.relic)
end

function ops.ChooseUpgrade(_run, _effect)
	return { kind = "SelectCard", purpose = "Upgrade" }
end

function ops.ChooseRemove(_run, _effect)
	return { kind = "SelectCard", purpose = "Remove" }
end

function ops.CardReward(_run, effect)
	return { kind = "Reward", source = "Event", rarity = effect.rarity }
end

function ops.Fight(_run, effect)
	return { kind = "Combat", fightKind = "Combat", encounterId = effect.encounter, gold = effect.gold }
end

RunEffects.ops = ops

-- Applies effects in order and returns the screen steps they asked for.
function RunEffects.apply(run, effects: { any }): { any }
	local steps = {}
	for _, effect in effects do
		local op = ops[effect.op]
		if not op then
			error(`unknown run effect op {effect.op}`)
		end
		local step = op(run, effect)
		if step then
			table.insert(steps, step)
		end
	end
	return steps
end

-- Short tag text for a cost or effect, for option buttons.
function RunEffects.describe(effect): string
	local op = effect.op
	if op == "LoseGold" then
		return `-{effect.amount} gold`
	elseif op == "GainGold" then
		return `+{effect.amount} gold`
	elseif op == "LoseHp" then
		return `-{effect.amount} HP`
	elseif op == "LoseMaxHp" then
		return `-{effect.amount} max HP`
	elseif op == "GainMaxHp" then
		return `+{effect.amount} max HP`
	elseif op == "Heal" then
		return if effect.amount then `heal {effect.amount}` else `heal {math.floor((effect.percent or 0) * 100)}%`
	end
	return op
end

return RunEffects
