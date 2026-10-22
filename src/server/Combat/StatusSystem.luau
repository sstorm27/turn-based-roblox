--[[
	Status stacks, decay and hook dispatch. Units keep `statuses` as
	{ [statusId] = stacks }. Hooks are looked up in Content.Statuses and run in
	priority order (lower first, ties by id) so results never depend on table
	iteration order.
]]

local StatusSystem = {}

function StatusSystem.sortedIds(content, unit): { string }
	local ids = {}
	for id in unit.statuses do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local pa = content.Statuses[a].priority or 100
		local pb = content.Statuses[b].priority or 100
		if pa ~= pb then
			return pa < pb
		end
		return a < b
	end)
	return ids
end

function StatusSystem.get(unit, id: string): number
	return unit.statuses[id] or 0
end

-- Pipes `value` through every Modify* hook on the unit.
function StatusSystem.modify(combat, unit, hookName: string, value: number, extra: { [string]: any }?): number
	local content = combat.content
	for _, id in StatusSystem.sortedIds(content, unit) do
		local hook = content.Statuses[id][hookName]
		if hook then
			local ctx = { combat = combat, owner = unit, stacks = unit.statuses[id], statusId = id }
			if extra then
				for k, v in extra do
					ctx[k] = v
				end
			end
			value = hook(unit.statuses[id], value, ctx)
		end
	end
	return value
end

-- Fires an On* hook on every status the unit has.
function StatusSystem.trigger(combat, unit, hookName: string, extra: { [string]: any }?)
	local content = combat.content
	for _, id in StatusSystem.sortedIds(content, unit) do
		local stacks = unit.statuses[id]
		local hook = content.Statuses[id][hookName]
		-- A status can be removed by an earlier hook in the same pass.
		if hook and stacks and stacks > 0 then
			local ctx = { combat = combat, owner = unit, stacks = stacks, statusId = id }
			if extra then
				for k, v in extra do
					ctx[k] = v
				end
			end
			hook(ctx)
		end
		if not unit.alive then
			return
		end
	end
end

-- Round-end decay. Statuses applied to the hero during the enemy phase skip
-- this round's decay, so a 1-stack debuff lasts through the hero's next turn.
function StatusSystem.decayRound(combat, unit)
	local content = combat.content
	for _, id in StatusSystem.sortedIds(content, unit) do
		local def = content.Statuses[id]
		if unit.freshStatuses[id] then
			continue
		end
		if def.decay == "Round" then
			combat:addStatus(unit, id, -1)
		elseif def.decay == "Halve" then
			local stacks = unit.statuses[id]
			combat:addStatus(unit, id, math.floor(stacks / 2) - stacks)
		end
	end
	table.clear(unit.freshStatuses)
end

return StatusSystem
