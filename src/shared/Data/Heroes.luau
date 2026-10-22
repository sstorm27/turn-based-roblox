--[[
	Hero classes. The MVP ships the Warden; the shape leaves room for more.

	onPerfectDefense: effects the hero gets on a Perfect defensive QTE (a class
	hook from the design doc; the Warden gains 3 Block).
]]

local Heroes = {}

Heroes.Warden = {
	name = "Warden",
	maxHp = 70,
	energy = 3,
	drawPerTurn = 5,
	maxHand = 10,
	-- Passive trait: keep 25% of unspent Block at turn start.
	blockRetain = 0.25,
	starterDeck = {
		"Strike", "Strike", "Strike", "Strike",
		"Guard", "Guard", "Guard", "Guard",
		"ShieldBash", "Brace",
	},
	onPerfectDefense = { { op = "Block", amount = 3 } },
}

for id, hero in Heroes do
	hero.id = id
end

return Heroes
