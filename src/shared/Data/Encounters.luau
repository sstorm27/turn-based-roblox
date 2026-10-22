--[[
	Fights. `deck` overrides the hero's starter deck (a card id, or
	{ id = "Strike", upgrade = "A" }); the debug fights set one, run fights
	don't because a run passes its own deck. Data/Acts says which fights each
	act's map nodes draw from.
]]

local Encounters = {}

-- Design doc milestone 1: Warden starter deck vs Cultist, plus a few QTE
-- cards so both offensive and defensive QTEs show up in the first fight.
local PROTOTYPE_DECK = {
	"Strike", "Strike", "Strike", "Strike",
	"Guard", "Guard", "Guard", "Guard",
	"ShieldBash", "Brace",
	"Smite", "Bulwark", "ShieldStorm", "Riposte",
}

Encounters.Prototype = {
	name = "Cultist",
	hero = "Warden",
	enemies = { "Cultist" },
	deck = PROTOTYPE_DECK,
}

Encounters.Slimes = {
	name = "Slime pit",
	hero = "Warden",
	enemies = { "AcidSlime", "AcidSlime" },
	deck = PROTOTYPE_DECK,
}

Encounters.Ambush = {
	name = "Ambush",
	hero = "Warden",
	enemies = { "Bandit", "AcidSlime" },
	deck = PROTOTYPE_DECK,
}

-- Act 1 run fights. These use the run's deck, so they set no hero or deck.

Encounters.LoneCultist = { name = "Cultist", enemies = { "Cultist" } }
Encounters.LoneWolf = { name = "Dire Wolf", enemies = { "DireWolf" } }
Encounters.SporeTrio = { name = "Sporelings", enemies = { "Sporeling", "Sporeling", "Sporeling" } }
Encounters.SlimePit = { name = "Slime pit", enemies = { "AcidSlime", "AcidSlime" } }
Encounters.Highwayman = { name = "Bandit", enemies = { "Bandit" } }
Encounters.WolfAndSlime = { name = "Wolf and slime", enemies = { "DireWolf", "AcidSlime" } }
Encounters.CultAndSpores = { name = "Cult garden", enemies = { "Sporeling", "Cultist" } }
Encounters.BanditAmbush = { name = "Ambush", enemies = { "Bandit", "Sporeling" } }

Encounters.GraveKnight = { name = "Grave Knight", enemies = { "GraveKnight" } }
Encounters.HexerCoven = { name = "Hexer", enemies = { "Hexer", "Sporeling" } }

Encounters.HollowKing = { name = "The Hollow King", enemies = { "HollowKing" } }

for id, encounter in Encounters do
	encounter.id = id
end

return Encounters
