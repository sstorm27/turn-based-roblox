--[[
	Card definitions. Every card is data: a cost, a type, a rarity, a target rule
	and an ordered list of effects built from the fixed op set in EffectResolver
	(Damage, Block, ApplyStatus, Draw, GainEnergy, AddCard, Exhaust, Heal,
	Repeat, If, and the class ops Detonate, Siphon and Transfer).

	Fields
		id, name, cost (number or "X"), type (Attack/Skill/Power/Curse/Wound),
		rarity (Starter/Common/Uncommon/Rare/Special), class (a hero id or
		"Neutral": which reward pool the card is in), target ("Enemy", "AllEnemies", "Self", "None"), text, effects,
		keywords ({ Exhaust = true, ... }), upgrades ({ A = {...}, B = {...} }).

	Effect targets default from the card: Damage and ApplyStatus hit the
	card's target, everything else applies to the hero.

	QTE cards add a `qte` field: { kind, difficulty, good, perfect }.
	`good` / `perfect` are bonus effects layered on top of `effects` when the
	QTE grades that well (Perfect replaces Good, it does not stack). A bonus
	Damage or Block merges into the first base effect with the same op and
	target, so `{ op = "Damage", amount = 4 }` reads as "+4 damage". Any
	other bonus effect is appended. A Miss always plays the printed card.

	Upgrades are shallow overrides of the base card, picked as path A or B.
]]

local Cards = {}

-- Shared starter cards (every class starts with 4 of each) --------------------

Cards.Strike = {
	name = "Strike",
	cost = 1,
	type = "Attack",
	rarity = "Starter",
	class = "Neutral",
	target = "Enemy",
	text = "Deal 6 damage.",
	effects = { { op = "Damage", amount = 6 } },
	upgrades = {
		A = { text = "Deal 9 damage.", effects = { { op = "Damage", amount = 9 } } },
		B = {
			text = "Deal 6 damage. Apply 1 Vulnerable.",
			effects = {
				{ op = "Damage", amount = 6 },
				{ op = "ApplyStatus", status = "Vulnerable", stacks = 1 },
			},
		},
	},
}

Cards.Guard = {
	name = "Guard",
	cost = 1,
	type = "Skill",
	rarity = "Starter",
	class = "Neutral",
	target = "Self",
	text = "Gain 5 Block.",
	effects = { { op = "Block", amount = 5 } },
	upgrades = {
		A = { text = "Gain 8 Block.", effects = { { op = "Block", amount = 8 } } },
		B = {
			text = "Gain 5 Block. Gain 1 Fortify.",
			effects = { { op = "Block", amount = 5 }, { op = "ApplyStatus", status = "Fortify", stacks = 1 } },
		},
	},
}

-- Warden starter cards -------------------------------------------------------

Cards.ShieldBash = {
	name = "Shield Bash",
	cost = 1,
	type = "Attack",
	rarity = "Starter",
	class = "Warden",
	target = "Enemy",
	text = "Deal damage equal to your Block.",
	effects = { { op = "Damage", amountFrom = "Block", amount = 0 } },
	upgrades = {
		A = {
			name = "Heavy Shield Bash",
			text = "Deal damage equal to your Block + 4.",
			effects = { { op = "Damage", amountFrom = "Block", amount = 4 } },
		},
		B = {
			name = "Light Shield Bash",
			cost = 0,
			text = "Deal damage equal to your Block. Exhaust.",
			keywords = { Exhaust = true },
		},
	},
}

Cards.Brace = {
	name = "Brace",
	cost = 0,
	type = "Skill",
	rarity = "Starter",
	class = "Warden",
	target = "Self",
	text = "Gain 3 Block. Draw 1 card.",
	effects = { { op = "Block", amount = 3 }, { op = "Draw", count = 1 } },
	upgrades = {
		A = { text = "Gain 5 Block. Draw 1 card.", effects = { { op = "Block", amount = 5 }, { op = "Draw", count = 1 } } },
		B = { text = "Gain 3 Block. Draw 2 cards.", effects = { { op = "Block", amount = 3 }, { op = "Draw", count = 2 } } },
	},
}

-- Warden QTE cards -----------------------------------------------------------

-- The design doc's reference QTE card.
Cards.Smite = {
	name = "Smite",
	cost = 2,
	type = "Attack",
	rarity = "Uncommon",
	class = "Warden",
	target = "Enemy",
	text = "Deal 12 damage. QTE Timing: Good +4, Perfect +8 and 2 Vulnerable.",
	effects = { { op = "Damage", amount = 12 } },
	qte = {
		kind = "Timing",
		difficulty = 2,
		good = { { op = "Damage", amount = 4 } },
		perfect = { { op = "Damage", amount = 8 }, { op = "ApplyStatus", status = "Vulnerable", stacks = 2 } },
	},
	upgrades = {
		A = {
			text = "Deal 16 damage. QTE Timing: Good +4, Perfect +8 and 2 Vulnerable.",
			effects = { { op = "Damage", amount = 16 } },
		},
		B = {
			-- Path B makes the QTE easier instead of raising the numbers.
			text = "Deal 12 damage. Easy QTE Timing: Good +4, Perfect +8 and 2 Vulnerable.",
			qte = {
				kind = "Timing",
				difficulty = 1,
				good = { { op = "Damage", amount = 4 } },
				perfect = { { op = "Damage", amount = 8 }, { op = "ApplyStatus", status = "Vulnerable", stacks = 2 } },
			},
		},
	},
}

Cards.Bulwark = {
	name = "Bulwark",
	cost = 2,
	type = "Skill",
	rarity = "Uncommon",
	class = "Warden",
	target = "Self",
	text = "Gain 12 Block. QTE Hold: Good +4 Block, Perfect +6 Block and 1 Fortify.",
	effects = { { op = "Block", amount = 12 } },
	qte = {
		kind = "Hold",
		difficulty = 2,
		good = { { op = "Block", amount = 4 } },
		perfect = { { op = "Block", amount = 6 }, { op = "ApplyStatus", status = "Fortify", stacks = 1 } },
	},
}

Cards.ShieldStorm = {
	name = "Shield Storm",
	cost = 1,
	type = "Attack",
	rarity = "Uncommon",
	class = "Warden",
	target = "AllEnemies",
	text = "Deal 5 damage to all enemies. QTE Mash: Good +2, Perfect +4 and 1 Weak to all.",
	effects = { { op = "Damage", amount = 5 } },
	qte = {
		kind = "Mash",
		difficulty = 2,
		good = { { op = "Damage", amount = 2 } },
		perfect = { { op = "Damage", amount = 4 }, { op = "ApplyStatus", status = "Weak", stacks = 1 } },
	},
}

Cards.Riposte = {
	name = "Riposte",
	cost = 1,
	type = "Skill",
	rarity = "Uncommon",
	class = "Warden",
	target = "Self",
	text = "Gain 6 Block and 2 Thorns. QTE Sequence: Good +3 Block, Perfect +3 Block and 2 Thorns.",
	effects = { { op = "Block", amount = 6 }, { op = "ApplyStatus", status = "Thorns", stacks = 2 } },
	qte = {
		kind = "Sequence",
		difficulty = 2,
		good = { { op = "Block", amount = 3 } },
		perfect = { { op = "Block", amount = 3 }, { op = "ApplyStatus", status = "Thorns", stacks = 2 } },
	},
}

Cards.Judgement = {
	name = "Judgement",
	cost = 3,
	type = "Attack",
	rarity = "Rare",
	class = "Warden",
	target = "Enemy",
	text = "Deal 20 damage. Exhaust. QTE Trace: Good +8, Perfect +16 and Stun.",
	keywords = { Exhaust = true },
	effects = { { op = "Damage", amount = 20 } },
	qte = {
		kind = "Trace",
		difficulty = 3,
		good = { { op = "Damage", amount = 8 } },
		perfect = { { op = "Damage", amount = 16 }, { op = "ApplyStatus", status = "Stun", stacks = 1 } },
	},
}

-- Warden non-QTE cards --------------------------------------------------------

Cards.IronWill = {
	name = "Iron Will",
	cost = 1,
	type = "Power",
	rarity = "Uncommon",
	class = "Warden",
	target = "Self",
	text = "Gain 2 Dexterity.",
	effects = { { op = "ApplyStatus", status = "Dexterity", stacks = 2 } },
}

Cards.Steady = {
	name = "Steady",
	cost = 0,
	type = "Skill",
	rarity = "Common",
	class = "Warden",
	target = "Self",
	text = "Gain 2 Focus (QTE windows +20% each). Draw 1 card. Exhaust.",
	keywords = { Exhaust = true },
	effects = { { op = "ApplyStatus", status = "Focus", stacks = 2 }, { op = "Draw", count = 1 } },
}

-- Warden reward pool -----------------------------------------------------------

Cards.Cleave = {
	name = "Cleave",
	cost = 1,
	type = "Attack",
	rarity = "Common",
	class = "Warden",
	target = "AllEnemies",
	text = "Deal 7 damage to all enemies.",
	effects = { { op = "Damage", amount = 7 } },
	upgrades = {
		A = { text = "Deal 10 damage to all enemies.", effects = { { op = "Damage", amount = 10 } } },
		B = {
			text = "Deal 7 damage to all enemies. Apply 1 Weak to all.",
			effects = { { op = "Damage", amount = 7 }, { op = "ApplyStatus", status = "Weak", stacks = 1 } },
		},
	},
}

Cards.PommelStrike = {
	name = "Pommel Strike",
	cost = 1,
	type = "Attack",
	rarity = "Common",
	class = "Warden",
	target = "Enemy",
	text = "Deal 8 damage. Draw 1 card.",
	effects = { { op = "Damage", amount = 8 }, { op = "Draw", count = 1 } },
	upgrades = {
		A = { text = "Deal 11 damage. Draw 1 card.", effects = { { op = "Damage", amount = 11 }, { op = "Draw", count = 1 } } },
		B = { text = "Deal 8 damage. Draw 2 cards.", effects = { { op = "Damage", amount = 8 }, { op = "Draw", count = 2 } } },
	},
}

Cards.SpikedGuard = {
	name = "Spiked Guard",
	cost = 1,
	type = "Skill",
	rarity = "Common",
	class = "Warden",
	target = "Self",
	text = "Gain 7 Block. Gain 1 Thorns.",
	effects = { { op = "Block", amount = 7 }, { op = "ApplyStatus", status = "Thorns", stacks = 1 } },
	upgrades = {
		A = {
			text = "Gain 10 Block. Gain 1 Thorns.",
			effects = { { op = "Block", amount = 10 }, { op = "ApplyStatus", status = "Thorns", stacks = 1 } },
		},
		B = {
			text = "Gain 7 Block. Gain 3 Thorns.",
			effects = { { op = "Block", amount = 7 }, { op = "ApplyStatus", status = "Thorns", stacks = 3 } },
		},
	},
}

Cards.Taunt = {
	name = "Taunt",
	cost = 1,
	type = "Skill",
	rarity = "Common",
	class = "Warden",
	target = "Enemy",
	text = "Apply 2 Weak. Gain 4 Block.",
	effects = { { op = "ApplyStatus", status = "Weak", stacks = 2 }, { op = "Block", amount = 4 } },
	upgrades = {
		A = {
			text = "Apply 3 Weak. Gain 6 Block.",
			effects = { { op = "ApplyStatus", status = "Weak", stacks = 3 }, { op = "Block", amount = 6 } },
		},
		B = {
			cost = 0,
			text = "Apply 2 Weak. Gain 4 Block.",
		},
	},
}

Cards.HoldTheLine = {
	name = "Hold the Line",
	cost = 2,
	type = "Skill",
	rarity = "Common",
	class = "Warden",
	target = "Self",
	text = "Gain 14 Block.",
	effects = { { op = "Block", amount = 14 } },
	upgrades = {
		A = { text = "Gain 19 Block.", effects = { { op = "Block", amount = 19 } } },
		B = {
			text = "Gain 14 Block. Gain 1 Fortify.",
			effects = { { op = "Block", amount = 14 }, { op = "ApplyStatus", status = "Fortify", stacks = 1 } },
		},
	},
}

Cards.CrushingBlow = {
	name = "Crushing Blow",
	cost = 2,
	type = "Attack",
	rarity = "Uncommon",
	class = "Warden",
	target = "Enemy",
	text = "Deal 10 damage. Apply 2 Vulnerable.",
	effects = { { op = "Damage", amount = 10 }, { op = "ApplyStatus", status = "Vulnerable", stacks = 2 } },
	upgrades = {
		A = {
			text = "Deal 14 damage. Apply 2 Vulnerable.",
			effects = { { op = "Damage", amount = 14 }, { op = "ApplyStatus", status = "Vulnerable", stacks = 2 } },
		},
		B = {
			text = "Deal 10 damage. Apply 3 Vulnerable.",
			effects = { { op = "Damage", amount = 10 }, { op = "ApplyStatus", status = "Vulnerable", stacks = 3 } },
		},
	},
}

Cards.Unbreakable = {
	name = "Unbreakable",
	cost = 2,
	type = "Power",
	rarity = "Rare",
	class = "Warden",
	target = "Self",
	text = "Gain 2 Dexterity and 2 Thorns.",
	effects = {
		{ op = "ApplyStatus", status = "Dexterity", stacks = 2 },
		{ op = "ApplyStatus", status = "Thorns", stacks = 2 },
	},
	upgrades = {
		A = {
			text = "Gain 3 Dexterity and 3 Thorns.",
			effects = {
				{ op = "ApplyStatus", status = "Dexterity", stacks = 3 },
				{ op = "ApplyStatus", status = "Thorns", stacks = 3 },
			},
		},
		B = { cost = 1, text = "Gain 2 Dexterity and 2 Thorns." },
	},
}

Cards.LastStand = {
	name = "Last Stand",
	cost = 1,
	type = "Skill",
	rarity = "Rare",
	class = "Warden",
	target = "Self",
	text = "Gain 10 Block. If you are below 50% HP, gain 20 instead.",
	effects = {
		{
			op = "If",
			cond = { kind = "SelfHpBelow", ratio = 0.5 },
			["then"] = { { op = "Block", amount = 20 } },
			["else"] = { { op = "Block", amount = 10 } },
		},
	},
}

Cards.Bastion = {
	name = "Bastion",
	cost = 3,
	type = "Skill",
	rarity = "Rare",
	class = "Warden",
	target = "Self",
	text = "Gain 30 Block. Exhaust.",
	keywords = { Exhaust = true },
	effects = { { op = "Block", amount = 30 } },
	upgrades = {
		A = { text = "Gain 40 Block. Exhaust.", effects = { { op = "Block", amount = 40 } } },
		B = { cost = 2, text = "Gain 30 Block. Exhaust." },
	},
}

-- Alchemist: DoTs (Poison, Burn, Bleed), Detonate, Sequence QTEs ----------------

Cards.ToxicFlask = {
	name = "Toxic Flask",
	cost = 1,
	type = "Skill",
	rarity = "Starter",
	class = "Alchemist",
	target = "Enemy",
	text = "Apply 4 Poison.",
	effects = { { op = "ApplyStatus", status = "Poison", stacks = 4 } },
	upgrades = {
		A = { text = "Apply 6 Poison.", effects = { { op = "ApplyStatus", status = "Poison", stacks = 6 } } },
		B = {
			text = "Apply 4 Poison. Draw 1 card.",
			effects = { { op = "ApplyStatus", status = "Poison", stacks = 4 }, { op = "Draw", count = 1 } },
		},
	},
}

-- Detonate: if the enemy has no Burn, light it first.
local function volatileMix(burn: number, mult: number)
	return {
		{
			op = "If",
			cond = { kind = "TargetHasStatus", status = "Burn" },
			["else"] = { { op = "ApplyStatus", status = "Burn", stacks = burn } },
		},
		{ op = "Detonate", status = "Burn", mult = mult },
	}
end

Cards.VolatileMix = {
	name = "Volatile Mix",
	cost = 1,
	type = "Attack",
	rarity = "Starter",
	class = "Alchemist",
	target = "Enemy",
	text = "Detonate Burn: consume all Burn on an enemy, deal 2x its stacks. If it has none, apply 3 Burn first.",
	effects = volatileMix(3, 2),
	upgrades = {
		A = {
			text = "Detonate Burn: consume all Burn on an enemy, deal 3x its stacks. If it has none, apply 3 Burn first.",
			effects = volatileMix(3, 3),
		},
		B = {
			text = "Detonate Burn: consume all Burn on an enemy, deal 2x its stacks. If it has none, apply 5 Burn first.",
			effects = volatileMix(5, 2),
		},
	},
}

Cards.Firebomb = {
	name = "Firebomb",
	cost = 1,
	type = "Attack",
	rarity = "Common",
	class = "Alchemist",
	target = "Enemy",
	text = "Deal 5 damage. Apply 3 Burn.",
	effects = { { op = "Damage", amount = 5 }, { op = "ApplyStatus", status = "Burn", stacks = 3 } },
	upgrades = {
		A = {
			text = "Deal 7 damage. Apply 4 Burn.",
			effects = { { op = "Damage", amount = 7 }, { op = "ApplyStatus", status = "Burn", stacks = 4 } },
		},
		B = { cost = 2, target = "AllEnemies", text = "Deal 5 damage and apply 3 Burn to all enemies." },
	},
}

Cards.Lacerate = {
	name = "Lacerate",
	cost = 1,
	type = "Attack",
	rarity = "Common",
	class = "Alchemist",
	target = "Enemy",
	text = "Apply 2 Bleed. Deal 3 damage twice.",
	effects = { { op = "ApplyStatus", status = "Bleed", stacks = 2 }, { op = "Damage", amount = 3, hits = 2 } },
	upgrades = {
		A = {
			text = "Apply 3 Bleed. Deal 3 damage twice.",
			effects = { { op = "ApplyStatus", status = "Bleed", stacks = 3 }, { op = "Damage", amount = 3, hits = 2 } },
		},
		B = {
			text = "Apply 2 Bleed. Deal 3 damage 3 times.",
			effects = { { op = "ApplyStatus", status = "Bleed", stacks = 2 }, { op = "Damage", amount = 3, hits = 3 } },
		},
	},
}

Cards.CausticSplash = {
	name = "Caustic Splash",
	cost = 0,
	type = "Attack",
	rarity = "Common",
	class = "Alchemist",
	target = "Enemy",
	text = "Deal 3 damage. Apply 2 Poison.",
	effects = { { op = "Damage", amount = 3 }, { op = "ApplyStatus", status = "Poison", stacks = 2 } },
	upgrades = {
		A = {
			text = "Deal 4 damage. Apply 3 Poison.",
			effects = { { op = "Damage", amount = 4 }, { op = "ApplyStatus", status = "Poison", stacks = 3 } },
		},
		B = {
			text = "Deal 3 damage. Apply 2 Poison. Draw 1 card.",
			effects = {
				{ op = "Damage", amount = 3 },
				{ op = "ApplyStatus", status = "Poison", stacks = 2 },
				{ op = "Draw", count = 1 },
			},
		},
	},
}

Cards.NoxiousCloud = {
	name = "Noxious Cloud",
	cost = 2,
	type = "Skill",
	rarity = "Common",
	class = "Alchemist",
	target = "AllEnemies",
	text = "Apply 4 Poison to all enemies.",
	effects = { { op = "ApplyStatus", status = "Poison", stacks = 4 } },
	upgrades = {
		A = { text = "Apply 6 Poison to all enemies.", effects = { { op = "ApplyStatus", status = "Poison", stacks = 6 } } },
		B = { cost = 1, text = "Apply 4 Poison to all enemies." },
	},
}

Cards.SmokeBomb = {
	name = "Smoke Bomb",
	cost = 1,
	type = "Skill",
	rarity = "Common",
	class = "Alchemist",
	target = "AllEnemies",
	text = "Gain 7 Block. Apply 1 Weak to all enemies.",
	effects = { { op = "Block", amount = 7 }, { op = "ApplyStatus", status = "Weak", stacks = 1 } },
	upgrades = {
		A = {
			text = "Gain 10 Block. Apply 1 Weak to all enemies.",
			effects = { { op = "Block", amount = 10 }, { op = "ApplyStatus", status = "Weak", stacks = 1 } },
		},
		B = {
			text = "Gain 7 Block. Apply 2 Weak to all enemies.",
			effects = { { op = "Block", amount = 7 }, { op = "ApplyStatus", status = "Weak", stacks = 2 } },
		},
	},
}

Cards.Rupture = {
	name = "Rupture",
	cost = 1,
	type = "Attack",
	rarity = "Uncommon",
	class = "Alchemist",
	target = "Enemy",
	text = "Detonate Bleed: consume all Bleed on an enemy, deal 3x its stacks.",
	effects = { { op = "Detonate", status = "Bleed", mult = 3 } },
	upgrades = {
		A = {
			text = "Detonate Bleed: consume all Bleed on an enemy, deal 4x its stacks.",
			effects = { { op = "Detonate", status = "Bleed", mult = 4 } },
		},
		B = {
			text = "Apply 2 Bleed. Detonate Bleed: consume all Bleed on an enemy, deal 3x its stacks.",
			effects = {
				{ op = "ApplyStatus", status = "Bleed", stacks = 2 },
				{ op = "Detonate", status = "Bleed", mult = 3 },
			},
		},
	},
}

Cards.Distill = {
	name = "Distill",
	cost = 1,
	type = "Attack",
	rarity = "Uncommon",
	class = "Alchemist",
	target = "Enemy",
	text = "Detonate Poison: consume all Poison on an enemy, deal 2x its stacks.",
	effects = { { op = "Detonate", status = "Poison", mult = 2 } },
	upgrades = {
		A = {
			text = "Detonate Poison: consume all Poison on an enemy, deal 3x its stacks.",
			effects = { { op = "Detonate", status = "Poison", mult = 3 } },
		},
		B = { cost = 0, text = "Detonate Poison: consume all Poison on an enemy, deal 2x its stacks." },
	},
}

Cards.Accelerant = {
	name = "Accelerant",
	cost = 1,
	type = "Skill",
	rarity = "Uncommon",
	class = "Alchemist",
	target = "Enemy",
	text = "Apply 2 Poison, 2 Burn and 2 Bleed.",
	effects = {
		{ op = "ApplyStatus", status = "Poison", stacks = 2 },
		{ op = "ApplyStatus", status = "Burn", stacks = 2 },
		{ op = "ApplyStatus", status = "Bleed", stacks = 2 },
	},
	upgrades = {
		A = {
			text = "Apply 3 Poison, 3 Burn and 3 Bleed.",
			effects = {
				{ op = "ApplyStatus", status = "Poison", stacks = 3 },
				{ op = "ApplyStatus", status = "Burn", stacks = 3 },
				{ op = "ApplyStatus", status = "Bleed", stacks = 3 },
			},
		},
		B = { cost = 0, text = "Apply 2 Poison, 2 Burn and 2 Bleed." },
	},
}

-- Sequence QTEs: mixing ingredients in the right order.
Cards.BrewPoison = {
	name = "Brew Poison",
	cost = 1,
	type = "Skill",
	rarity = "Uncommon",
	class = "Alchemist",
	target = "Enemy",
	text = "Apply 5 Poison. QTE Sequence: Good +2 Poison, Perfect +4 Poison and 2 Burn.",
	effects = { { op = "ApplyStatus", status = "Poison", stacks = 5 } },
	qte = {
		kind = "Sequence",
		difficulty = 2,
		good = { { op = "ApplyStatus", status = "Poison", stacks = 2 } },
		perfect = {
			{ op = "ApplyStatus", status = "Poison", stacks = 4 },
			{ op = "ApplyStatus", status = "Burn", stacks = 2 },
		},
	},
}

Cards.Elixir = {
	name = "Elixir",
	cost = 1,
	type = "Skill",
	rarity = "Uncommon",
	class = "Alchemist",
	target = "Self",
	text = "Gain 7 Block. QTE Sequence: Good +3 Block, Perfect +3 Block and 2 Regen.",
	effects = { { op = "Block", amount = 7 } },
	qte = {
		kind = "Sequence",
		difficulty = 2,
		good = { { op = "Block", amount = 3 } },
		perfect = { { op = "Block", amount = 3 }, { op = "ApplyStatus", status = "Regen", stacks = 2 } },
	},
}

Cards.GrandConcoction = {
	name = "Grand Concoction",
	cost = 2,
	type = "Skill",
	rarity = "Rare",
	class = "Alchemist",
	target = "Enemy",
	text = "Apply 6 Poison and 6 Burn. Exhaust. QTE Sequence: Good +3 Poison, Perfect +3 Poison and 4 Bleed.",
	keywords = { Exhaust = true },
	effects = {
		{ op = "ApplyStatus", status = "Poison", stacks = 6 },
		{ op = "ApplyStatus", status = "Burn", stacks = 6 },
	},
	qte = {
		kind = "Sequence",
		difficulty = 3,
		good = { { op = "ApplyStatus", status = "Poison", stacks = 3 } },
		perfect = {
			{ op = "ApplyStatus", status = "Poison", stacks = 3 },
			{ op = "ApplyStatus", status = "Bleed", stacks = 4 },
		},
	},
}

Cards.ChainReaction = {
	name = "Chain Reaction",
	cost = 2,
	type = "Attack",
	rarity = "Rare",
	class = "Alchemist",
	target = "AllEnemies",
	text = "Detonate Burn, then Poison, on all enemies: deal 2x their stacks. Exhaust.",
	keywords = { Exhaust = true },
	effects = {
		{ op = "Detonate", status = "Burn", mult = 2 },
		{ op = "Detonate", status = "Poison", mult = 2 },
	},
	upgrades = {
		A = { keywords = {}, text = "Detonate Burn, then Poison, on all enemies: deal 2x their stacks." },
		B = {
			text = "Detonate Burn, then Poison, on all enemies: deal 3x their stacks. Exhaust.",
			effects = {
				{ op = "Detonate", status = "Burn", mult = 3 },
				{ op = "Detonate", status = "Poison", mult = 3 },
			},
		},
	},
}

Cards.ToxicFumes = {
	name = "Toxic Fumes",
	cost = 2,
	type = "Power",
	rarity = "Rare",
	class = "Alchemist",
	target = "Self",
	text = "At the start of your turn, apply 2 Poison to all enemies.",
	effects = { { op = "ApplyStatus", status = "Miasma", stacks = 2 } },
	upgrades = {
		A = { text = "At the start of your turn, apply 3 Poison to all enemies.", effects = { { op = "ApplyStatus", status = "Miasma", stacks = 3 } } },
		B = { cost = 1, text = "At the start of your turn, apply 2 Poison to all enemies." },
	},
}

-- Hexxer: debuffs, Siphon and Transfer, Trace QTEs --------------------------------

Cards.EvilEye = {
	name = "Evil Eye",
	cost = 1,
	type = "Skill",
	rarity = "Starter",
	class = "Hexxer",
	target = "Enemy",
	text = "Apply 2 Weak and 2 Vulnerable.",
	effects = {
		{ op = "ApplyStatus", status = "Weak", stacks = 2 },
		{ op = "ApplyStatus", status = "Vulnerable", stacks = 2 },
	},
	upgrades = {
		A = {
			text = "Apply 3 Weak and 3 Vulnerable.",
			effects = {
				{ op = "ApplyStatus", status = "Weak", stacks = 3 },
				{ op = "ApplyStatus", status = "Vulnerable", stacks = 3 },
			},
		},
		B = {
			text = "Apply 2 Weak and 2 Vulnerable. Draw 1 card.",
			effects = {
				{ op = "ApplyStatus", status = "Weak", stacks = 2 },
				{ op = "ApplyStatus", status = "Vulnerable", stacks = 2 },
				{ op = "Draw", count = 1 },
			},
		},
	},
}

-- Siphon: steal buffs; an enemy with none is cursed instead.
local function siphon(count: number, extra: { any }?): { any }
	local effects: { any } = {
		{
			op = "If",
			cond = { kind = "TargetHasKind", statusKind = "Buff" },
			["then"] = { { op = "Siphon", count = count } },
			["else"] = { { op = "ApplyStatus", status = "Weak", stacks = 1 } },
		},
	}
	for _, effect in extra or {} :: { any } do
		table.insert(effects, effect)
	end
	return effects
end

Cards.Siphon = {
	name = "Siphon",
	cost = 1,
	type = "Skill",
	rarity = "Starter",
	class = "Hexxer",
	target = "Enemy",
	text = "Siphon: steal 1 random buff from an enemy. If it has none, apply 1 Weak.",
	effects = siphon(1),
	upgrades = {
		A = {
			text = "Siphon: steal 1 random buff from an enemy. If it has none, apply 1 Weak. Gain 5 Block.",
			effects = siphon(1, { { op = "Block", amount = 5 } }),
		},
		B = {
			text = "Siphon: steal 2 random buffs from an enemy. If it has none, apply 1 Weak.",
			effects = siphon(2),
		},
	},
}

Cards.Wither = {
	name = "Wither",
	cost = 1,
	type = "Attack",
	rarity = "Common",
	class = "Hexxer",
	target = "Enemy",
	text = "Deal 7 damage. Apply 1 Frail.",
	effects = { { op = "Damage", amount = 7 }, { op = "ApplyStatus", status = "Frail", stacks = 1 } },
	upgrades = {
		A = {
			text = "Deal 10 damage. Apply 1 Frail.",
			effects = { { op = "Damage", amount = 10 }, { op = "ApplyStatus", status = "Frail", stacks = 1 } },
		},
		B = {
			text = "Deal 7 damage. Apply 2 Frail.",
			effects = { { op = "Damage", amount = 7 }, { op = "ApplyStatus", status = "Frail", stacks = 2 } },
		},
	},
}

Cards.Spite = {
	name = "Spite",
	cost = 1,
	type = "Attack",
	rarity = "Common",
	class = "Hexxer",
	target = "Enemy",
	text = "Deal 4 damage, +3 for each different debuff on the enemy.",
	effects = { { op = "Damage", amount = 4, perDebuff = 3 } },
	upgrades = {
		A = {
			text = "Deal 4 damage, +4 for each different debuff on the enemy.",
			effects = { { op = "Damage", amount = 4, perDebuff = 4 } },
		},
		B = {
			text = "Deal 7 damage, +3 for each different debuff on the enemy.",
			effects = { { op = "Damage", amount = 7, perDebuff = 3 } },
		},
	},
}

Cards.Befuddle = {
	name = "Befuddle",
	cost = 0,
	type = "Skill",
	rarity = "Common",
	class = "Hexxer",
	target = "Enemy",
	text = "Apply 1 Dazed (your QTEs against it are wider). Draw 1 card.",
	effects = { { op = "ApplyStatus", status = "Dazed", stacks = 1 }, { op = "Draw", count = 1 } },
	upgrades = {
		A = {
			text = "Apply 2 Dazed (your QTEs against it are wider). Draw 1 card.",
			effects = { { op = "ApplyStatus", status = "Dazed", stacks = 2 }, { op = "Draw", count = 1 } },
		},
		B = {
			text = "Apply 1 Dazed and 1 Frail. Draw 1 card.",
			effects = {
				{ op = "ApplyStatus", status = "Dazed", stacks = 1 },
				{ op = "ApplyStatus", status = "Frail", stacks = 1 },
				{ op = "Draw", count = 1 },
			},
		},
	},
}

Cards.HexWard = {
	name = "Hex Ward",
	cost = 1,
	type = "Skill",
	rarity = "Common",
	class = "Hexxer",
	target = "Self",
	text = "Gain 6 Block. Apply 1 Weak to all enemies.",
	effects = { { op = "Block", amount = 6 }, { op = "ApplyStatus", status = "Weak", stacks = 1, target = "AllEnemies" } },
	upgrades = {
		A = {
			text = "Gain 9 Block. Apply 1 Weak to all enemies.",
			effects = { { op = "Block", amount = 9 }, { op = "ApplyStatus", status = "Weak", stacks = 1, target = "AllEnemies" } },
		},
		B = {
			text = "Gain 6 Block. Apply 1 Weak and 1 Frail to all enemies.",
			effects = {
				{ op = "Block", amount = 6 },
				{ op = "ApplyStatus", status = "Weak", stacks = 1, target = "AllEnemies" },
				{ op = "ApplyStatus", status = "Frail", stacks = 1, target = "AllEnemies" },
			},
		},
	},
}

Cards.DarkPact = {
	name = "Dark Pact",
	cost = 0,
	type = "Skill",
	rarity = "Common",
	class = "Hexxer",
	target = "Self",
	text = "Gain 2 Strength. Gain 2 Weak.",
	effects = {
		{ op = "ApplyStatus", status = "Strength", stacks = 2 },
		{ op = "ApplyStatus", status = "Weak", stacks = 2 },
	},
	upgrades = {
		A = {
			text = "Gain 3 Strength. Gain 2 Weak.",
			effects = {
				{ op = "ApplyStatus", status = "Strength", stacks = 3 },
				{ op = "ApplyStatus", status = "Weak", stacks = 2 },
			},
		},
		B = {
			text = "Gain 2 Strength. Gain 1 Weak.",
			effects = {
				{ op = "ApplyStatus", status = "Strength", stacks = 2 },
				{ op = "ApplyStatus", status = "Weak", stacks = 1 },
			},
		},
	},
}

Cards.MirrorCurse = {
	name = "Mirror Curse",
	cost = 1,
	type = "Skill",
	rarity = "Uncommon",
	class = "Hexxer",
	target = "Enemy",
	text = "Transfer: move all your debuffs onto an enemy. Gain 6 Block.",
	effects = { { op = "Transfer" }, { op = "Block", amount = 6 } },
	upgrades = {
		A = {
			text = "Transfer: move all your debuffs onto an enemy. Gain 9 Block.",
			effects = { { op = "Transfer" }, { op = "Block", amount = 9 } },
		},
		B = { cost = 0, text = "Transfer: move all your debuffs onto an enemy. Gain 6 Block." },
	},
}

Cards.Malediction = {
	name = "Malediction",
	cost = 2,
	type = "Attack",
	rarity = "Uncommon",
	class = "Hexxer",
	target = "Enemy",
	text = "Deal 8 damage. Apply 1 Weak, 1 Vulnerable and 1 Frail.",
	effects = {
		{ op = "Damage", amount = 8 },
		{ op = "ApplyStatus", status = "Weak", stacks = 1 },
		{ op = "ApplyStatus", status = "Vulnerable", stacks = 1 },
		{ op = "ApplyStatus", status = "Frail", stacks = 1 },
	},
	upgrades = {
		A = {
			text = "Deal 12 damage. Apply 1 Weak, 1 Vulnerable and 1 Frail.",
			effects = {
				{ op = "Damage", amount = 12 },
				{ op = "ApplyStatus", status = "Weak", stacks = 1 },
				{ op = "ApplyStatus", status = "Vulnerable", stacks = 1 },
				{ op = "ApplyStatus", status = "Frail", stacks = 1 },
			},
		},
		B = { cost = 1, text = "Deal 8 damage. Apply 1 Weak, 1 Vulnerable and 1 Frail." },
	},
}

-- Trace QTEs: drawing sigils.
Cards.SigilOfRuin = {
	name = "Sigil of Ruin",
	cost = 1,
	type = "Skill",
	rarity = "Uncommon",
	class = "Hexxer",
	target = "Enemy",
	text = "Apply 2 Vulnerable. QTE Trace: Good +2 Weak, Perfect +2 Weak, 2 Frail and 1 Dazed.",
	effects = { { op = "ApplyStatus", status = "Vulnerable", stacks = 2 } },
	qte = {
		kind = "Trace",
		difficulty = 2,
		good = { { op = "ApplyStatus", status = "Weak", stacks = 2 } },
		perfect = {
			{ op = "ApplyStatus", status = "Weak", stacks = 2 },
			{ op = "ApplyStatus", status = "Frail", stacks = 2 },
			{ op = "ApplyStatus", status = "Dazed", stacks = 1 },
		},
	},
}

Cards.SoulDrain = {
	name = "Soul Drain",
	cost = 1,
	type = "Attack",
	rarity = "Uncommon",
	class = "Hexxer",
	target = "Enemy",
	text = "Deal 7 damage. QTE Trace: Good +3, Perfect +5 and steal 1 buff.",
	effects = { { op = "Damage", amount = 7 } },
	qte = {
		kind = "Trace",
		difficulty = 2,
		good = { { op = "Damage", amount = 3 } },
		perfect = { { op = "Damage", amount = 5 }, { op = "Siphon", count = 1 } },
	},
}

Cards.Doom = {
	name = "Doom",
	cost = 2,
	type = "Attack",
	rarity = "Rare",
	class = "Hexxer",
	target = "Enemy",
	text = "Deal 8 damage, +5 for each different debuff on the enemy. QTE Trace: Good +5, Perfect +10 and Stun.",
	effects = { { op = "Damage", amount = 8, perDebuff = 5 } },
	qte = {
		kind = "Trace",
		difficulty = 3,
		good = { { op = "Damage", amount = 5 } },
		perfect = { { op = "Damage", amount = 10 }, { op = "ApplyStatus", status = "Stun", stacks = 1 } },
	},
}

Cards.HexAura = {
	name = "Hex Aura",
	cost = 2,
	type = "Power",
	rarity = "Rare",
	class = "Hexxer",
	target = "Self",
	text = "At the start of your turn, apply 1 Vulnerable to all enemies.",
	effects = { { op = "ApplyStatus", status = "Gloom", stacks = 1 } },
	upgrades = {
		A = { cost = 1, text = "At the start of your turn, apply 1 Vulnerable to all enemies." },
		B = {
			keywords = { Innate = true },
			text = "Innate. At the start of your turn, apply 1 Vulnerable to all enemies.",
		},
	},
}

-- Curses (from events) ---------------------------------------------------------

Cards.Doubt = {
	name = "Doubt",
	cost = 0,
	type = "Curse",
	rarity = "Special",
	class = "Neutral",
	target = "None",
	text = "Unplayable. Clogs your hand.",
	keywords = { Unplayable = true },
	effects = {},
}

-- Junk ---------------------------------------------------------------------

Cards.Wound = {
	name = "Wound",
	cost = 0,
	type = "Wound",
	rarity = "Special",
	target = "None",
	text = "Unplayable.",
	keywords = { Unplayable = true },
	effects = {},
}

for id, card in Cards do
	card.id = id
end

return Cards
