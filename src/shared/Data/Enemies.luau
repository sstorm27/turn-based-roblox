--[[
	Enemy definitions. Behaviour is a move table plus one AI pattern, so no
	enemy needs custom code. Moves reuse the card effect ops; effect targets are
	relative to the enemy ("Hero" or "Target" is the hero, "Self" the enemy).

	Move fields
		intent      Attack, Defend, Buff, Debuff, AttackDebuff, Pollute, ...
		effects     ordered effect list
		defenseQte  optional { kind, difficulty, good, perfect }: the hero gets a
		            defensive QTE before each hit lands. good / perfect are damage
		            multipliers (default 0.5 and 0). Debuffs still apply.

	Patterns
		Cycle        { kind = "Cycle", order = { ... }, loopFrom = n }
		Weighted     { kind = "Weighted", moves = { { move, weight } }, maxRepeat = n }
		Conditional  { kind = "Conditional", rules = { { when, move, once } }, fallback = <pattern> }
		             when: { kind = "HpBelow", ratio } | { kind = "Turn", turn }
]]

local Enemies = {}

Enemies.Cultist = {
	name = "Cultist",
	hp = { 48, 54 },
	moves = {
		Incantation = {
			intent = "Buff",
			effects = { { op = "ApplyStatus", status = "Strength", stacks = 3, target = "Self" } },
		},
		DarkStrike = {
			intent = "Attack",
			effects = { { op = "Damage", amount = 6 } },
			defenseQte = { kind = "Timing", difficulty = 1 },
		},
	},
	pattern = { kind = "Cycle", order = { "Incantation", "DarkStrike" }, loopFrom = 2 },
}

Enemies.AcidSlime = {
	name = "Acid Slime",
	hp = { 28, 32 },
	moves = {
		Tackle = {
			intent = "Attack",
			effects = { { op = "Damage", amount = 10 } },
			defenseQte = { kind = "Timing", difficulty = 1 },
		},
		Lick = {
			intent = "Debuff",
			effects = { { op = "ApplyStatus", status = "Weak", stacks = 1 } },
		},
		Spit = {
			intent = "Pollute",
			effects = { { op = "AddCard", card = "Wound", count = 2, pile = "Discard" } },
		},
	},
	pattern = {
		kind = "Weighted",
		moves = { { "Tackle", 40 }, { "Lick", 30 }, { "Spit", 30 } },
		maxRepeat = 2,
	},
}

Enemies.Bandit = {
	name = "Bandit",
	hp = { 40, 44 },
	moves = {
		Slash = {
			intent = "Attack",
			effects = { { op = "Damage", amount = 8 } },
			defenseQte = { kind = "Timing", difficulty = 2 },
		},
		Flurry = {
			intent = "Attack",
			effects = { { op = "Damage", amount = 3, hits = 3 } },
			-- One QTE per hit, with shorter windows (see Qte.MultiHitWindowMult).
			defenseQte = { kind = "Timing", difficulty = 1 },
		},
		Stab = {
			intent = "AttackDebuff",
			effects = {
				{ op = "Damage", amount = 5 },
				{ op = "ApplyStatus", status = "Vulnerable", stacks = 1 },
			},
			defenseQte = { kind = "Sequence", difficulty = 1 },
		},
		Hunker = {
			intent = "Defend",
			effects = { { op = "Block", amount = 8, target = "Self" } },
		},
		Enrage = {
			intent = "Buff",
			effects = {
				{ op = "ApplyStatus", status = "Strength", stacks = 3, target = "Self" },
				{ op = "Block", amount = 6, target = "Self" },
			},
		},
	},
	pattern = {
		kind = "Conditional",
		rules = {
			{ when = { kind = "HpBelow", ratio = 0.5 }, move = "Enrage", once = true },
		},
		fallback = {
			kind = "Weighted",
			moves = { { "Slash", 35 }, { "Flurry", 25 }, { "Stab", 25 }, { "Hunker", 15 } },
			maxRepeat = 2,
		},
	},
}

for id, enemy in Enemies do
	enemy.id = id
	for moveId, move in enemy.moves do
		move.id = moveId
	end
end

return Enemies
