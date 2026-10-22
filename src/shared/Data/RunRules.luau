--[[
	Run economy and map presentation, all in one place for tuning. Numbers
	follow the design doc's "Rewards, economy and relics" section.
]]

local RunRules = {}

RunRules.startingGold = 99

-- What each map node looks like on a path card: a type name and one line.
RunRules.nodeTypes = {
	Combat = { name = "Fight", hint = "A normal fight, then a card reward." },
	Elite = { name = "Elite", hint = "A hard fight with a guaranteed relic." },
	Event = { name = "Mystery", hint = "A story with choices. Your deck may be tested." },
	Rest = { name = "Camp", hint = "Heal, upgrade a card, or remove one." },
	Shop = { name = "Shop", hint = "Spend gold on cards, relics and services." },
	Treasure = { name = "Treasure", hint = "A relic chest." },
	Boss = { name = "Boss", hint = "The act boss." },
}

-- Rewards after a fight, by fight kind.
RunRules.rewards = {
	Combat = { gold = { 10, 20 }, cards = 3, odds = { Common = 60, Uncommon = 35, Rare = 5 } },
	Elite = { gold = { 25, 35 }, cards = 3, odds = { Common = 40, Uncommon = 30, Rare = 30 }, relic = true },
	Boss = { gold = { 75, 75 }, cards = 3, odds = { Rare = 100 }, bossRelics = 3, fullHeal = true },
}

RunRules.shop = {
	cards = 5,
	cardOdds = { Common = 50, Uncommon = 37, Rare = 13 },
	cardPrices = { Common = 50, Uncommon = 75, Rare = 150 },
	saleMult = 0.5,
	relics = 3,
	relicPrices = { Common = 150, Uncommon = 200, Rare = 300 },
	removeBase = 75,
	removeStep = 25,
	upgradePrice = 100,
	-- Prices vary by up to this much either way so shops feel different.
	jitter = 0.1,
}

RunRules.rest = {
	healPercent = 0.3,
}

-- Events reveal this many cards from the top of a shuffled copy of the deck.
RunRules.cardCheckReveal = 3

-- Meta currency earned by a run, paid out when it ends.
RunRules.renown = { perRow = 1, elite = 5, boss = 25, win = 50 }

-- Odds for random relics (elites, treasure, events).
RunRules.relicOdds = { Common = 50, Uncommon = 33, Rare = 17 }

return RunRules
