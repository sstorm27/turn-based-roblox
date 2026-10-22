--[[
	Picks each enemy's next move from its data pattern: Cycle, Weighted or
	Conditional. Every enemy keeps a small AI state (history, cycle step, which
	`once` rules have fired) on its unit.
]]

local EnemyAI = {}

function EnemyAI.newState()
	return { history = {}, step = 1, used = {} }
end

local function repeatCount(history: { string }, moveId: string): number
	local count = 0
	for i = #history, 1, -1 do
		if history[i] ~= moveId then
			break
		end
		count += 1
	end
	return count
end

local function conditionMet(when, unit, combat): boolean
	if when.kind == "HpBelow" then
		return unit.hp < unit.maxHp * when.ratio
	elseif when.kind == "Turn" then
		return combat.turn == when.turn
	elseif when.kind == "Always" then
		return true
	end
	error(`unknown AI condition {when.kind}`)
end

local pick

local function pickCycle(pattern, ai)
	local order = pattern.order
	if ai.step > #order then
		ai.step = pattern.loopFrom or 1
	end
	local moveId = order[ai.step]
	ai.step += 1
	return moveId
end

local function pickWeighted(pattern, ai, rng)
	local candidates = {}
	local total = 0
	for _, entry in pattern.moves do
		local moveId, weight = entry[1], entry[2]
		if not pattern.maxRepeat or repeatCount(ai.history, moveId) < pattern.maxRepeat then
			table.insert(candidates, entry)
			total += weight
		end
	end
	if #candidates == 0 then
		return pattern.moves[1][1]
	end
	local roll = rng:float() * total
	for _, entry in candidates do
		roll -= entry[2]
		if roll < 0 then
			return entry[1]
		end
	end
	return candidates[#candidates][1]
end

local function pickConditional(pattern, ai, rng, unit, combat)
	for index, rule in pattern.rules do
		local key = `rule{index}`
		if not (rule.once and ai.used[key]) and conditionMet(rule.when, unit, combat) then
			if rule.once then
				ai.used[key] = true
			end
			return rule.move
		end
	end
	return pick(pattern.fallback, ai, rng, unit, combat)
end

function pick(pattern, ai, rng, unit, combat)
	if pattern.kind == "Cycle" then
		return pickCycle(pattern, ai)
	elseif pattern.kind == "Weighted" then
		return pickWeighted(pattern, ai, rng)
	elseif pattern.kind == "Conditional" then
		return pickConditional(pattern, ai, rng, unit, combat)
	end
	error(`unknown AI pattern {pattern.kind}`)
end

-- Returns the id of the move the enemy will use next, and records it.
function EnemyAI.choose(def, unit, rng, combat): string
	local moveId = pick(def.pattern, unit.ai, rng, unit, combat)
	table.insert(unit.ai.history, moveId)
	return moveId
end

return EnemyAI
