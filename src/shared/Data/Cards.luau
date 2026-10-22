--[[
	Card definitions. Every card is data: a cost, a type, a rarity, a target rule
	and an ordered list of effects built from the fixed op set in EffectResolver
	(Damage, Block, ApplyStatus, Draw, GainEnergy, AddCard, Exhaust, Heal,
	Repeat, If).

	Fields
		id, name, cost (number or "X"), type (Attack/Skill/Power/Curse/Wound),
		rarity, target ("Enemy", "AllEnemies", "Self", "None"), text, effects,
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

-- Warden starter cards -------------------------------------------------------

Cards.Strike = {
	name = "Strike",
	cost = 1,
	type = "Attack",
	rarity = "Starter",
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

Cards.ShieldBash = {
	name = "Shield Bash",
	cost = 1,
	type = "Attack",
	rarity = "Starter",
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
	target = "Self",
	text = "Gain 2 Dexterity.",
	effects = { { op = "ApplyStatus", status = "Dexterity", stacks = 2 } },
}

Cards.Steady = {
	name = "Steady",
	cost = 0,
	type = "Skill",
	rarity = "Common",
	target = "Self",
	text = "Gain 2 Focus (QTE windows +20% each). Draw 1 card. Exhaust.",
	keywords = { Exhaust = true },
	effects = { { op = "ApplyStatus", status = "Focus", stacks = 2 }, { op = "Draw", count = 1 } },
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
