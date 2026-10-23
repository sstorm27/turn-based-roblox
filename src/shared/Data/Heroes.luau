--[[
	Hero classes. The player picks one when a run starts. The design doc
	unlocks the Alchemist and Hexxer with Renown; for now all three are open.

	Fields
		name, order (place on the class select), blurb (one line), maxHp,
		energy, drawPerTurn, maxHand, starterDeck
		passive           { name, text } for the class select and tooltips
		qteStyle          the QTE kind the class's cards lean on
		onPerfectDefense  effects the hero gets on a Perfect defensive QTE.
		                  "Target" is the enemy whose hit was defended.

	Passive knobs (read by Combat)
		blockRetain   share of unspent Block kept at turn start (Warden)
		dotAmp        { kind = "DoT", minKinds, mult }: DoT and Detonate
		              damage on an enemy with that many different DoTs
		              (Alchemist's Catalyst)
		debuffExtend  extra stacks on Round debuffs the hero applies to
		              enemies, so they last that many more rounds (Hexxer)
		debuffAmp     { kind = "Debuff", minKinds, mult }: attack damage on
		              an enemy with that many different debuffs (Hexxer's
		              Malice)
]]

local Heroes = {}

Heroes.Warden = {
	name = "Warden",
	order = 1,
	blurb = "Shield knight who turns Block into damage.",
	maxHp = 70,
	energy = 3,
	drawPerTurn = 5,
	maxHand = 10,
	passive = { name = "Steadfast", text = "Keep 25% of your unspent Block at the start of your turn." },
	qteStyle = "Hold",
	blockRetain = 0.25,
	starterDeck = {
		"Strike", "Strike", "Strike", "Strike",
		"Guard", "Guard", "Guard", "Guard",
		"ShieldBash", "Brace",
	},
	onPerfectDefense = { { op = "Block", amount = 3 } },
}

Heroes.Alchemist = {
	name = "Alchemist",
	order = 2,
	blurb = "Brewer who stacks damage over time and detonates it.",
	maxHp = 70,
	energy = 3,
	drawPerTurn = 5,
	maxHand = 10,
	passive = {
		name = "Catalyst",
		text = "An enemy with 2 or more different DoTs (Poison, Burn, Bleed) takes 25% more DoT damage.",
	},
	qteStyle = "Sequence",
	dotAmp = { kind = "DoT", minKinds = 2, mult = 1.25 },
	starterDeck = {
		"Strike", "Strike", "Strike", "Strike",
		"Guard", "Guard", "Guard", "Guard",
		"ToxicFlask", "VolatileMix",
	},
	onPerfectDefense = { { op = "ApplyStatus", status = "Poison", stacks = 2, target = "Target" } },
}

Heroes.Hexxer = {
	name = "Hexxer",
	order = 3,
	blurb = "Witch who weakens enemies and strengthens herself.",
	maxHp = 70,
	energy = 3,
	drawPerTurn = 5,
	maxHand = 10,
	passive = {
		name = "Malice",
		text = "Debuffs you apply last 1 extra round. An enemy with 3 or more different debuffs takes 25% more attack damage.",
	},
	qteStyle = "Trace",
	debuffExtend = 1,
	debuffAmp = { kind = "Debuff", minKinds = 3, mult = 1.25 },
	starterDeck = {
		"Strike", "Strike", "Strike", "Strike",
		"Guard", "Guard", "Guard", "Guard",
		"EvilEye", "Siphon",
	},
	onPerfectDefense = { { op = "ApplyStatus", status = "Weak", stacks = 1, target = "Target" } },
}

for id, hero in Heroes do
	hero.id = id
end

return Heroes
