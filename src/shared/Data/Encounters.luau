--[[
	Fights the prototype can start. `deck` overrides the hero's starter deck
	(a card id, or { id = "Strike", upgrade = "A" }).
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

for id, encounter in Encounters do
	encounter.id = id
end

return Encounters
