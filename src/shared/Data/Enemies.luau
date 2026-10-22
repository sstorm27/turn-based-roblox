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

	Flags
		elite, boss  shown on the map and used by the reward rules

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

Enemies.DireWolf = {
	name = "Dire Wolf",
	hp = { 34, 38 },
	moves = {
		Bite = {
			intent = "Attack",
			effects = { { op = "Damage", amount = 9 } },
			defenseQte = { kind = "Timing", difficulty = 2 },
		},
		Howl = {
			intent = "Buff",
			effects = { { op = "ApplyStatus", status = "Strength", stacks = 2, target = "Self" } },
		},
		Maul = {
			intent = "AttackDebuff",
			effects = { { op = "Damage", amount = 5 }, { op = "ApplyStatus", status = "Bleed", stacks = 2 } },
			defenseQte = { kind = "Timing", difficulty = 1 },
		},
	},
	pattern = { kind = "Cycle", order = { "Howl", "Bite", "Maul", "Bite" }, loopFrom = 2 },
}

Enemies.Sporeling = {
	name = "Sporeling",
	hp = { 14, 18 },
	moves = {
		Spores = {
			intent = "Debuff",
			effects = { { op = "ApplyStatus", status = "Poison", stacks = 3 } },
		},
		Headbutt = {
			intent = "Attack",
			effects = { { op = "Damage", amount = 5 } },
			defenseQte = { kind = "Timing", difficulty = 1 },
		},
	},
	pattern = { kind = "Weighted", moves = { { "Spores", 40 }, { "Headbutt", 60 } }, maxRepeat = 2 },
}

-- Elites --------------------------------------------------------------------

Enemies.GraveKnight = {
	name = "Grave Knight",
	elite = true,
	hp = { 82, 88 },
	moves = {
		Cleave = {
			intent = "Attack",
			effects = { { op = "Damage", amount = 14 } },
			defenseQte = { kind = "Timing", difficulty = 3 },
		},
		RaiseShield = {
			intent = "Defend",
			effects = {
				{ op = "Block", amount = 12, target = "Self" },
				{ op = "ApplyStatus", status = "Strength", stacks = 1, target = "Self" },
			},
		},
		Rend = {
			intent = "AttackDebuff",
			effects = { { op = "Damage", amount = 7 }, { op = "ApplyStatus", status = "Frail", stacks = 2 } },
			defenseQte = { kind = "Sequence", difficulty = 2 },
		},
		DeathMarch = {
			intent = "Buff",
			effects = {
				{ op = "ApplyStatus", status = "Strength", stacks = 4, target = "Self" },
				{ op = "Block", amount = 10, target = "Self" },
			},
		},
	},
	pattern = {
		kind = "Conditional",
		rules = { { when = { kind = "HpBelow", ratio = 0.5 }, move = "DeathMarch", once = true } },
		fallback = { kind = "Cycle", order = { "Cleave", "RaiseShield", "Rend" } },
	},
}

Enemies.Hexer = {
	name = "Hexer",
	elite = true,
	hp = { 62, 66 },
	moves = {
		Hex = {
			intent = "Debuff",
			effects = {
				{ op = "ApplyStatus", status = "Weak", stacks = 2 },
				{ op = "ApplyStatus", status = "Dazed", stacks = 1 },
			},
		},
		Curse = {
			intent = "Pollute",
			effects = { { op = "AddCard", card = "Wound", count = 2, pile = "Draw" } },
		},
		Bolt = {
			intent = "Attack",
			effects = { { op = "Damage", amount = 4, hits = 3 } },
			defenseQte = { kind = "Timing", difficulty = 2 },
		},
		DrainLife = {
			intent = "Attack",
			effects = {
				{ op = "Damage", amount = 9 },
				{ op = "Heal", amount = 6, target = "Self" },
			},
			defenseQte = { kind = "Hold", difficulty = 2 },
		},
	},
	pattern = {
		kind = "Weighted",
		moves = { { "Hex", 25 }, { "Curse", 15 }, { "Bolt", 35 }, { "DrainLife", 25 } },
		maxRepeat = 1,
	},
}

-- Boss ----------------------------------------------------------------------

-- Two phases: the Conditional rule fires once at half HP, after which the
-- fallback pattern's heavier moves take over.
Enemies.HollowKing = {
	name = "The Hollow King",
	boss = true,
	hp = { 150, 150 },
	moves = {
		Decree = {
			intent = "Debuff",
			effects = {
				{ op = "ApplyStatus", status = "Weak", stacks = 2 },
				{ op = "ApplyStatus", status = "Vulnerable", stacks = 2 },
			},
		},
		CrownStrike = {
			intent = "Attack",
			effects = { { op = "Damage", amount = 16 } },
			defenseQte = { kind = "Timing", difficulty = 3 },
		},
		Scepter = {
			intent = "Attack",
			effects = { { op = "Damage", amount = 5, hits = 3 } },
			defenseQte = { kind = "Sequence", difficulty = 2 },
		},
		Rally = {
			intent = "Defend",
			effects = {
				{ op = "Block", amount = 18, target = "Self" },
				{ op = "ApplyStatus", status = "Strength", stacks = 2, target = "Self" },
			},
		},
		Shatter = {
			intent = "Buff",
			effects = {
				{ op = "ApplyStatus", status = "Strength", stacks = 5, target = "Self" },
				{ op = "AddCard", card = "Wound", count = 2, pile = "Discard" },
			},
		},
	},
	pattern = {
		kind = "Conditional",
		rules = {
			{ when = { kind = "Turn", turn = 1 }, move = "Decree", once = true },
			{ when = { kind = "HpBelow", ratio = 0.5 }, move = "Shatter", once = true },
		},
		fallback = {
			kind = "Weighted",
			moves = { { "CrownStrike", 35 }, { "Scepter", 30 }, { "Rally", 20 }, { "Decree", 15 } },
			maxRepeat = 1,
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
