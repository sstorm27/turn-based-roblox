--[[
	Runs map events (Data/Events): option requirements, costs, card checks and
	outcomes. A card check reveals the top cards of a shuffled copy of the deck
	(RunRules.cardCheckReveal, 3) and tests them, so building toward a plan
	pays off in events too.

	EventRunner.view(run, event)            what the event screen shows
	EventRunner.choose(run, event, index)   -> result or nil, err
		result { label, text, success (nil without a check), revealed, steps }
]]

local RunEffects = require("./RunEffects")

local EventRunner = {}

local function countDeck(run, predicate): number
	local count = 0
	for _, card in run.deck do
		if predicate(run.content.getCard(card.id, card.upgrade), card) then
			count += 1
		end
	end
	return count
end

function EventRunner.requirementMet(run, req): boolean
	local kind = req.kind
	if kind == "Gold" then
		return run.gold >= req.amount
	elseif kind == "MinHp" then
		return run.hp >= req.amount
	elseif kind == "CardType" then
		return countDeck(run, function(def)
			return def.type == req.type
		end) >= (req.count or 1)
	elseif kind == "Relic" then
		return run:hasRelic(req.relic)
	elseif kind == "Hero" then
		return run.heroId == req.hero
	elseif kind == "Upgradable" then
		return #run:cardsFor("Upgrade") > 0
	elseif kind == "Removable" then
		return #run:cardsFor("Remove") > 0
	end
	error(`unknown event requirement {kind}`)
end

function EventRunner.describeRequirement(req): string
	local kind = req.kind
	if kind == "Gold" then
		return `Needs {req.amount} gold`
	elseif kind == "MinHp" then
		return `Needs {req.amount} HP`
	elseif kind == "CardType" then
		return `Needs {req.count or 1} {req.type}`
	elseif kind == "Relic" then
		return `Needs relic {req.relic}`
	elseif kind == "Hero" then
		return `{req.hero} only`
	elseif kind == "Upgradable" then
		return "Needs an upgradable card"
	elseif kind == "Removable" then
		return "Needs a card to remove"
	end
	return kind
end

function EventRunner.describeCheck(check, reveal: number): string
	local kind = check.kind
	local what
	if kind == "CountType" then
		what = `{check.count} {check.type}{if check.count == 1 then "" else "s"}`
	elseif kind == "TotalCost" then
		what = `total cost {check.atLeast}+`
	elseif kind == "CountQte" then
		what = `{check.count} QTE card{if check.count == 1 then "" else "s"}`
	elseif kind == "CountUpgraded" then
		what = `{check.count} upgraded card{if check.count == 1 then "" else "s"}`
	else
		what = kind
	end
	return `Reveal {reveal}: show {what}`
end

-- Tests revealed cards (definitions with upgrades applied) against a check.
function EventRunner.passes(check, defs: { any }): boolean
	local kind = check.kind
	if kind == "CountType" then
		local n = 0
		for _, def in defs do
			if def.type == check.type then
				n += 1
			end
		end
		return n >= check.count
	elseif kind == "TotalCost" then
		local total = 0
		for _, def in defs do
			-- X costs count as 0; they cost whatever energy you have.
			total += if type(def.cost) == "number" then def.cost else 0
		end
		return total >= check.atLeast
	elseif kind == "CountQte" then
		local n = 0
		for _, def in defs do
			if def.qte then
				n += 1
			end
		end
		return n >= check.count
	elseif kind == "CountUpgraded" then
		local n = 0
		for _, def in defs do
			if def.upgrade then
				n += 1
			end
		end
		return n >= check.count
	end
	error(`unknown card check {kind}`)
end

function EventRunner.optionAvailable(run, option): boolean
	for _, req in option.requires or {} do
		if not EventRunner.requirementMet(run, req) then
			return false
		end
	end
	return true
end

function EventRunner.view(run, event)
	local reveal = run.content.RunRules.cardCheckReveal
	local options = {}
	for index, option in event.options do
		local tags = {}
		for _, req in option.requires or {} do
			table.insert(tags, EventRunner.describeRequirement(req))
		end
		for _, cost in option.cost or {} do
			table.insert(tags, RunEffects.describe(cost))
		end
		if option.check then
			table.insert(tags, EventRunner.describeCheck(option.check, reveal))
		end
		options[index] = { index = index, label = option.label, tags = tags, available = EventRunner.optionAvailable(run, option) }
	end
	return { eventId = event.id, name = event.name, text = event.text, options = options }
end

function EventRunner.choose(run, event, index: number)
	local option = event.options[index]
	if not option then
		return nil, "no such option"
	end
	if not EventRunner.optionAvailable(run, option) then
		return nil, "option requirements not met"
	end

	local steps = RunEffects.apply(run, option.cost or {})
	local branch = option.outcome
	local success = nil
	local revealed = {}
	if option.check then
		local deck = table.clone(run.deck)
		run.rng.events:shuffle(deck)
		local defs = {}
		for i = 1, math.min(run.content.RunRules.cardCheckReveal, #deck) do
			local card = deck[i]
			table.insert(revealed, run:cardView(card))
			table.insert(defs, run.content.getCard(card.id, card.upgrade))
		end
		success = EventRunner.passes(option.check, defs)
		branch = if success then option.success else option.failure
	end

	local text = ""
	if branch then
		text = branch.text or ""
		for _, step in RunEffects.apply(run, branch.effects or {}) do
			table.insert(steps, step)
		end
	end
	return {
		label = option.label,
		text = text,
		success = success,
		revealed = revealed,
		steps = steps,
	}
end

return EventRunner
