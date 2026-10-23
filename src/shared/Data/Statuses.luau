--[[
	Status effects. Each status is stacks on a unit (one entry per status per
	unit) with one decay rule and a set of hooks. The same table works for the
	hero and enemies. Block is kept as a plain number on the unit rather than a
	status, because every unit has it and it never decays by rounds.

	decay
		Round     -1 at round end
		Halve     halved (rounded down) at round end
		Tick      the status's own hook removes stacks when it triggers
		Clear     the status's own hook removes it after it triggers
		Permanent lasts the whole combat

	Hooks run in priority order (lower first, ties by id), so results are
	deterministic.
		ModifyDamageDealt(stacks, value, ctx) -> value
		ModifyDamageTaken(stacks, value, ctx) -> value
		ModifyBlockGained(stacks, value, ctx) -> value
		ModifyQteWindow(stacks, value, ctx)   -> value   (window multiplier)
		ModifyAttackerQteWindow(stacks, value, ctx) -> value  (the hero's
		                  defensive window against this unit's attacks)
		OnTurnStart(ctx), OnTurnEnd(ctx), OnRoundEnd(ctx)
		OnHit(ctx)        ctx.attacker is the unit that hit the owner
		OnApplied(ctx)    ctx.added is the number of stacks just added
		OnQteGraded(ctx)  ctx.grade, ctx.request

	kind (Buff, Debuff, DoT, Control) is what class rules count: Catalyst
	counts DoTs, Malice counts Debuffs, Siphon steals Buffs and Transfer moves
	Debuffs.

	ctx always has: combat, owner (the unit), stacks, statusId.
]]

local Statuses = {}

Statuses.Strength = {
	name = "Strength",
	kind = "Buff",
	decay = "Permanent",
	priority = 10,
	text = "+1 damage on attacks per stack.",
	ModifyDamageDealt = function(stacks, value)
		return value + stacks
	end,
}

Statuses.Dexterity = {
	name = "Dexterity",
	kind = "Buff",
	decay = "Permanent",
	priority = 10,
	text = "+1 Block from cards per stack.",
	ModifyBlockGained = function(stacks, value)
		return value + stacks
	end,
}

Statuses.Fortify = {
	name = "Fortify",
	kind = "Buff",
	decay = "Round",
	priority = 20,
	keepsBlock = true,
	text = "Block is not removed at turn start.",
}

Statuses.Thorns = {
	name = "Thorns",
	kind = "Buff",
	decay = "Permanent",
	priority = 30,
	text = "Deal 1 damage back to each attacker per hit, per stack.",
	OnHit = function(ctx)
		if ctx.attacker and ctx.attacker.alive then
			ctx.combat:applyDamage(ctx.attacker, ctx.stacks, { source = ctx.owner, isAttack = false })
		end
	end,
}

Statuses.Regen = {
	name = "Regen",
	kind = "Buff",
	decay = "Round",
	priority = 40,
	text = "Heal 1 HP per stack at turn start.",
	OnTurnStart = function(ctx)
		ctx.combat:heal(ctx.owner, ctx.stacks)
	end,
}

Statuses.Vulnerable = {
	name = "Vulnerable",
	kind = "Debuff",
	decay = "Round",
	priority = 50,
	text = "Takes 50% more attack damage.",
	ModifyDamageTaken = function(_, value)
		return value * 1.5
	end,
}

Statuses.Weak = {
	name = "Weak",
	kind = "Debuff",
	decay = "Round",
	priority = 50,
	text = "Deals 25% less attack damage.",
	ModifyDamageDealt = function(_, value)
		return value * 0.75
	end,
}

Statuses.Frail = {
	name = "Frail",
	kind = "Debuff",
	decay = "Round",
	priority = 50,
	text = "Gains 25% less Block.",
	ModifyBlockGained = function(_, value)
		return value * 0.75
	end,
}

Statuses.Poison = {
	name = "Poison",
	kind = "DoT",
	decay = "Tick",
	priority = 60,
	text = "Lose 1 HP per stack at turn start, ignoring Block. Then -1 stack.",
	OnTurnStart = function(ctx)
		ctx.combat:dotDamage(ctx.owner, ctx.stacks, true)
		ctx.combat:addStatus(ctx.owner, "Poison", -1)
	end,
}

Statuses.Bleed = {
	name = "Bleed",
	kind = "DoT",
	decay = "Halve",
	priority = 60,
	text = "Lose 1 HP per stack each time it is hit by an attack.",
	OnHit = function(ctx)
		ctx.combat:dotDamage(ctx.owner, ctx.stacks, true)
	end,
}

Statuses.Burn = {
	name = "Burn",
	kind = "DoT",
	decay = "Clear",
	priority = 60,
	text = "Take 1 damage per stack at turn end (hits Block). Then removed.",
	OnTurnEnd = function(ctx)
		ctx.combat:dotDamage(ctx.owner, ctx.stacks, false)
		ctx.combat:removeStatus(ctx.owner, "Burn")
	end,
}

Statuses.Stun = {
	name = "Stun",
	kind = "Control",
	decay = "Tick",
	priority = 70,
	text = "Skips its next action. Removed after use.",
}

-- QTE statuses (design doc: Difficulty) ---------------------------------------

Statuses.Focus = {
	name = "Focus",
	kind = "Buff",
	decay = "Round",
	priority = 80,
	text = "QTE windows are 20% wider per stack.",
	ModifyQteWindow = function(stacks, value)
		return value + 0.2 * stacks
	end,
}

Statuses.Dazed = {
	name = "Dazed",
	kind = "Debuff",
	decay = "Round",
	priority = 80,
	text = "On you: QTE windows are 20% narrower per stack. On an enemy: your QTEs against its attacks are 20% wider per stack.",
	ModifyQteWindow = function(stacks, value)
		return value - 0.2 * stacks
	end,
	ModifyAttackerQteWindow = function(stacks, value)
		return value + 0.2 * stacks
	end,
}

-- Class powers (a Power card applies one to the hero) ---------------------------

Statuses.Miasma = {
	name = "Miasma",
	kind = "Buff",
	decay = "Permanent",
	priority = 90,
	text = "At the start of your turn, apply 1 Poison to all enemies per stack.",
	OnTurnStart = function(ctx)
		for _, enemy in ctx.combat:opponentsOf(ctx.owner) do
			ctx.combat:applyStatus(enemy, "Poison", ctx.stacks, ctx.owner)
		end
	end,
}

Statuses.Gloom = {
	name = "Gloom",
	kind = "Buff",
	decay = "Permanent",
	priority = 90,
	text = "At the start of your turn, apply 1 Vulnerable to all enemies per stack.",
	OnTurnStart = function(ctx)
		for _, enemy in ctx.combat:opponentsOf(ctx.owner) do
			ctx.combat:applyStatus(enemy, "Vulnerable", ctx.stacks, ctx.owner)
		end
	end,
}

for id, status in Statuses do
	status.id = id
end

return Statuses
