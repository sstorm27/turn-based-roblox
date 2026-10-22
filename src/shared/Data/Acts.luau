--[[
	Acts of a run. Each act is one generated map plus the fights and events its
	nodes draw from. A run plays the acts in order; beating the last act's boss
	wins it. The MVP ships act 1.

	map
		rows, columns   the grid (row 1 at the bottom, the boss row at the top)
		paths           paths drawn upward from row 1; they merge where they meet
		starts          { min, max } distinct start columns in row 1
		branchChance    chance a one-exit node gets a second exit
		fixed           node type forced on a row
		weights         chance of each type on the other rows
		minRow          the first row a type may appear on
		noRepeat        types that can't follow themselves on a path
	encounters
		easy            the first `easyFights` normal fights come from here
		normal, elite, boss
	events            event ids this act's Event nodes draw from (no repeats
	                  in a run)
]]

local Acts = {}

Acts[1] = {
	name = "The Sunken Road",
	map = {
		rows = 15,
		columns = 7,
		paths = 6,
		starts = { 2, 3 },
		branchChance = 1,
		fixed = { [1] = "Combat", [8] = "Treasure", [14] = "Rest", [15] = "Boss" },
		weights = { Combat = 45, Event = 22, Elite = 8, Rest = 12, Shop = 5 },
		minRow = { Elite = 5, Rest = 5 },
		noRepeat = { Elite = true, Rest = true, Shop = true },
	},
	easyFights = 3,
	encounters = {
		easy = { "LoneCultist", "LoneWolf", "SporeTrio", "SlimePit" },
		normal = { "Highwayman", "WolfAndSlime", "CultAndSpores", "BanditAmbush", "SlimePit", "SporeTrio" },
		elite = { "GraveKnight", "HexerCoven" },
		boss = { "HollowKing" },
	},
	events = {
		"ShrineOfBlades",
		"WanderingSmith",
		"GamblersDen",
		"OldWell",
		"HermitsLibrary",
		"BanditToll",
		"TrainingYard",
		"MirrorPool",
		"FallenKnight",
		"MerchantCaravan",
		"CollapsedMine",
		"BloodAltar",
	},
}

return Acts
