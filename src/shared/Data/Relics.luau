--[[
	Relics: passive items that last the whole run. All data, no code.

	Fields
		name, rarity (Common/Uncommon/Rare/Boss), text
		combatStart   combat effects run once when a fight starts (source: hero)
		turnStart     combat effects run at the start of each player turn
		energy        added to energy per turn
		onPickup      run effects applied once when the relic is gained
		              (the same ops as event outcomes, e.g. GainMaxHp)
		cardRewardSize  added to the number of card choices on reward screens
		restHealMult    multiplies Rest healing (0 means Rest cannot heal)

	Boss relics are strong with a drawback and only come from the boss.
]]

local Relics = {}

-- Common --------------------------------------------------------------------

Relics.IronBuckle = {
	name = "Iron Buckle",
	rarity = "Common",
	text = "Start each combat with 6 Block.",
	combatStart = { { op = "Block", amount = 6 } },
}

Relics.VigorFlask = {
	name = "Vigor Flask",
	rarity = "Common",
	text = "Raise your max HP by 8.",
	onPickup = { { op = "GainMaxHp", amount = 8 } },
}

Relics.FocusLens = {
	name = "Focus Lens",
	rarity = "Common",
	text = "Start each combat with 2 Focus (wider QTE windows).",
	combatStart = { { op = "ApplyStatus", status = "Focus", stacks = 2, target = "Self" } },
}

-- Uncommon ------------------------------------------------------------------

Relics.EmberCharm = {
	name = "Ember Charm",
	rarity = "Uncommon",
	text = "Start each combat with 1 Strength.",
	combatStart = { { op = "ApplyStatus", status = "Strength", stacks = 1, target = "Self" } },
}

Relics.ThornMail = {
	name = "Thorn Mail",
	rarity = "Uncommon",
	text = "Start each combat with 3 Thorns.",
	combatStart = { { op = "ApplyStatus", status = "Thorns", stacks = 3, target = "Self" } },
}

-- Rare ------------------------------------------------------------------------

Relics.WardensOath = {
	name = "Warden's Oath",
	rarity = "Rare",
	text = "At the start of each turn, gain 2 Block.",
	turnStart = { { op = "Block", amount = 2 } },
}

Relics.BloodChalice = {
	name = "Blood Chalice",
	rarity = "Rare",
	text = "At the start of each turn, heal 1 HP.",
	turnStart = { { op = "Heal", amount = 1 } },
}

-- Boss --------------------------------------------------------------------------

Relics.HeavyCrown = {
	name = "Heavy Crown",
	rarity = "Boss",
	text = "+1 energy each turn. Card rewards offer 2 cards instead of 3.",
	energy = 1,
	cardRewardSize = -1,
}

Relics.BloodOath = {
	name = "Blood Oath",
	rarity = "Boss",
	text = "+1 energy each turn. Resting no longer heals.",
	energy = 1,
	restHealMult = 0,
}

Relics.CrackedWard = {
	name = "Cracked Ward",
	rarity = "Boss",
	text = "+1 energy each turn. Start each combat with a Wound in your draw pile.",
	energy = 1,
	combatStart = { { op = "AddCard", card = "Wound", count = 1, pile = "Draw" } },
}

for id, relic in Relics do
	relic.id = id
end

return Relics
