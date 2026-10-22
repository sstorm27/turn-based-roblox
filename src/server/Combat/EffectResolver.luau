--[[
	Runs effect ops in order. One resolver drives cards, enemy moves, class
	hooks and (later) relics and potions.

	ctx fields
		source         the acting unit
		target         the chosen target unit (cards with target = "Enemy")
		defaultTarget  where Damage / ApplyStatus go when the effect names none
		x              energy spent on an X-cost card
		qteGrade       the card's QTE grade, if it had one
		defenseQte     the enemy move's defenseQte, if it has one
		moveId         the enemy move being performed

	Targets are relative to the source: "Self", "Target", "Hero",
	"AllEnemies" (the source's opponents), "RandomEnemy", "AllAllies".
]]

local EffectResolver = {}

local DEFAULTS_TO_TARGET = { Damage = true, ApplyStatus = true }

local function opponentsOf(combat, unit)
	if unit.side == "Hero" then
		return combat:livingEnemies()
	end
	return combat.hero.alive and { combat.hero } or {}
end

local function alliesOf(combat, unit)
	if unit.side == "Hero" then
		return { combat.hero }
	end
	return combat:livingEnemies()
end

function EffectResolver.resolveTargets(combat, effect, ctx): { any }
	local rule = effect.target
	if rule == nil then
		rule = DEFAULTS_TO_TARGET[effect.op] and ctx.defaultTarget or "Self"
	end
	local source = ctx.source

	if rule == "Self" then
		return source.alive and { source } or {}
	elseif rule == "Target" or rule == "Hero" then
		if source.side == "Enemy" or rule == "Hero" then
			return combat.hero.alive and { combat.hero } or {}
		end
		return (ctx.target and ctx.target.alive) and { ctx.target } or {}
	elseif rule == "AllEnemies" then
		return opponentsOf(combat, source)
	elseif rule == "RandomEnemy" then
		local pool = opponentsOf(combat, source)
		if #pool == 0 then
			return {}
		end
		return { pool[combat.rng.combat:int(1, #pool)] }
	elseif rule == "AllAllies" then
		return alliesOf(combat, source)
	end
	error(`unknown effect target {rule}`)
end

local function countOf(value, ctx): number
	if value == "X" then
		return ctx.x or 0
	end
	return value or 1
end

local function conditionMet(combat, cond, ctx): boolean
	if cond.kind == "TargetHasStatus" then
		local target = ctx.target
		return target ~= nil and (target.statuses[cond.status] or 0) >= (cond.stacks or 1)
	elseif cond.kind == "SelfHasStatus" then
		return (ctx.source.statuses[cond.status] or 0) >= (cond.stacks or 1)
	elseif cond.kind == "SelfHpBelow" then
		return ctx.source.hp < ctx.source.maxHp * cond.ratio
	elseif cond.kind == "QteGrade" then
		local rank = combat.content.Qte.GradeRank
		return ctx.qteGrade ~= nil and rank[ctx.qteGrade] >= rank[cond.atLeast or "Good"]
	end
	error(`unknown If condition {cond.kind}`)
end

local ops = {}

function ops.Damage(combat, effect, ctx)
	local hits = countOf(effect.hits, ctx)
	for _, target in EffectResolver.resolveTargets(combat, effect, ctx) do
		for hit = 1, hits do
			if not target.alive or not ctx.source.alive or combat:isOver() then
				break
			end
			local base = effect.amount or 0
			if effect.amountFrom == "Block" then
				base += ctx.source.block
			end
			combat:attack(ctx.source, target, base, ctx, hit, hits)
		end
	end
end

function ops.Block(combat, effect, ctx)
	for _, unit in EffectResolver.resolveTargets(combat, effect, ctx) do
		combat:gainBlock(unit, effect.amount)
	end
end

function ops.ApplyStatus(combat, effect, ctx)
	for _, unit in EffectResolver.resolveTargets(combat, effect, ctx) do
		combat:applyStatus(unit, effect.status, countOf(effect.stacks, ctx), ctx.source)
	end
end

function ops.Draw(combat, effect, ctx)
	combat:draw(countOf(effect.count, ctx))
end

function ops.GainEnergy(combat, effect, ctx)
	combat:gainEnergy(effect.amount)
end

function ops.AddCard(combat, effect, ctx)
	combat:addCardToPile(effect.card, effect.pile or "Discard", countOf(effect.count, ctx), effect.upgrade)
end

function ops.Exhaust(combat, effect, ctx)
	combat:exhaustRandomFromHand(countOf(effect.count, ctx))
end

function ops.Heal(combat, effect, ctx)
	for _, unit in EffectResolver.resolveTargets(combat, effect, ctx) do
		combat:heal(unit, effect.amount)
	end
end

function ops.Repeat(combat, effect, ctx)
	for _ = 1, countOf(effect.times, ctx) do
		if combat:isOver() then
			return
		end
		EffectResolver.run(combat, effect.effects, ctx)
	end
end

ops["If"] = function(combat, effect, ctx)
	if conditionMet(combat, effect.cond, ctx) then
		EffectResolver.run(combat, effect["then"] or {}, ctx)
	elseif effect["else"] then
		EffectResolver.run(combat, effect["else"], ctx)
	end
end

EffectResolver.ops = ops

function EffectResolver.run(combat, effects: { any }, ctx)
	for _, effect in effects do
		if combat:isOver() then
			return
		end
		local op = ops[effect.op]
		if not op then
			error(`unknown effect op {effect.op}`)
		end
		op(combat, effect, ctx)
	end
end

return EffectResolver
