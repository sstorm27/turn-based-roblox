--[[
	Map events, Across the Obelisk style: a story card with 2 to 4 options.

	Event   { name, text, options = { Option } }
	Option
		label       the button text
		requires    list of requirements; the option is shown greyed out if any
		            is unmet
		              { kind = "Gold", amount }      { kind = "MinHp", amount }
		              { kind = "CardType", type, count? }
		              { kind = "Relic", relic }      { kind = "Hero", hero }
		              { kind = "Upgradable" }        { kind = "Removable" }
		cost        run effects paid before anything else, shown as tags
		check       a card check: reveal the top 3 cards of a shuffled copy of
		            the deck and test them
		              { kind = "CountType", type, count }
		              { kind = "TotalCost", atLeast }
		              { kind = "CountQte", count }   cards with a QTE
		              { kind = "CountUpgraded", count }
		outcome     { text, effects } when there is no check
		success, failure   { text, effects } when there is one

	Run effect ops (shared with relic onPickup)
		GainGold, LoseGold { amount }        Heal { amount | percent }
		LoseHp { amount }                    GainMaxHp, LoseMaxHp { amount }
		AddCard { card, upgrade? }           AddRandomCard { rarity? }
		UpgradeRandom { count, type? }       RemoveRandom { count, type? }
		ChooseUpgrade, ChooseRemove          the player picks a card next
		GainRelic { relic? }                 random if no relic is named
		CardReward { rarity? }               a pick-1-of-3 screen next
		Fight { encounter, gold? }           a fight next, then its rewards

	Every event needs at least one option with no requirement, so the player
	can always leave.
]]

local Events = {}

local LEAVE = { label = "Leave", outcome = { text = "You move on.", effects = {} } }

Events.ShrineOfBlades = {
	name = "Shrine of Blades",
	text = "Rusted swords ring a stone altar. A voice asks you to show it your edge.",
	options = {
		{
			label = "Show your edge",
			check = { kind = "CountType", type = "Attack", count = 2 },
			success = {
				text = "The blades hum in approval and sharpen your strikes.",
				effects = { { op = "UpgradeRandom", count = 2, type = "Attack" } },
			},
			failure = { text = "The blades lash out at the unworthy.", effects = { { op = "LoseHp", amount = 6 } } },
		},
		LEAVE,
	},
}

Events.WanderingSmith = {
	name = "Wandering Smith",
	text = "A smith with a portable forge offers to work on your gear.",
	options = {
		{
			label = "Commission her",
			requires = { { kind = "Gold", amount = 40 }, { kind = "Upgradable" } },
			cost = { { op = "LoseGold", amount = 40 } },
			outcome = { text = "She works quickly and well.", effects = { { op = "ChooseUpgrade" } } },
		},
		{
			label = "Work the bellows yourself",
			requires = { { kind = "Upgradable" } },
			cost = { { op = "LoseHp", amount = 6 } },
			outcome = { text = "Burnt hands, but a better weapon.", effects = { { op = "UpgradeRandom", count = 1 } } },
		},
		LEAVE,
	},
}

Events.GamblersDen = {
	name = "Gambler's Den",
	text = "A hooded figure shuffles a deck. \"Draw three. Beat the house.\"",
	options = {
		{
			label = "Bet 30 gold",
			requires = { { kind = "Gold", amount = 30 } },
			cost = { { op = "LoseGold", amount = 30 } },
			check = { kind = "TotalCost", atLeast = 4 },
			success = { text = "The house pays out three to one.", effects = { { op = "GainGold", amount = 90 } } },
			failure = { text = "The house always wins.", effects = {} },
		},
		LEAVE,
	},
}

Events.OldWell = {
	name = "Old Well",
	text = "The water is black and very still.",
	options = {
		{
			label = "Drink deeply",
			outcome = {
				text = "You feel restored, and a little haunted.",
				effects = { { op = "Heal", percent = 0.25 }, { op = "AddCard", card = "Doubt" } },
			},
		},
		{
			label = "Toss in a coin",
			requires = { { kind = "Gold", amount = 15 } },
			cost = { { op = "LoseGold", amount = 15 } },
			outcome = { text = "The water glows briefly.", effects = { { op = "Heal", amount = 10 } } },
		},
		LEAVE,
	},
}

Events.HermitsLibrary = {
	name = "Hermit's Library",
	text = "A hermit guards shelves of crumbling manuals.",
	options = {
		{
			label = "Study the basics",
			requires = { { kind = "Removable" } },
			outcome = { text = "You unlearn a bad habit.", effects = { { op = "ChooseRemove" } } },
		},
		{
			label = "Read the forbidden book",
			outcome = {
				text = "Power, at a price.",
				effects = { { op = "AddCard", card = "Doubt" }, { op = "CardReward", rarity = "Rare" } },
			},
		},
		LEAVE,
	},
}

Events.BanditToll = {
	name = "Bandit Toll",
	text = "A bandit blocks the bridge. \"Thirty gold, or your life.\"",
	options = {
		{
			label = "Pay the toll",
			requires = { { kind = "Gold", amount = 30 } },
			cost = { { op = "LoseGold", amount = 30 } },
			outcome = { text = "He lets you pass with a sneer.", effects = {} },
		},
		{
			label = "Fight",
			outcome = {
				text = "He draws his blade.",
				effects = { { op = "Fight", encounter = "Highwayman", gold = 30 } },
			},
		},
	},
}

Events.TrainingYard = {
	name = "Training Yard",
	text = "Old soldiers run drills. They let you join in.",
	options = {
		{
			label = "Drill your defence",
			check = { kind = "CountType", type = "Skill", count = 2 },
			success = { text = "Your stance is rock solid.", effects = { { op = "GainMaxHp", amount = 6 } } },
			failure = { text = "You take a few hits.", effects = { { op = "LoseHp", amount = 5 } } },
		},
		{
			label = "Spar with the captain",
			requires = { { kind = "MinHp", amount = 15 } },
			cost = { { op = "LoseHp", amount = 10 } },
			outcome = { text = "You learn a trick or two.", effects = { { op = "AddRandomCard", rarity = "Uncommon" } } },
		},
		LEAVE,
	},
}

Events.MirrorPool = {
	name = "Mirror Pool",
	text = "Your reflection moves a heartbeat before you do.",
	options = {
		{
			label = "Match its rhythm",
			check = { kind = "CountQte", count = 1 },
			success = { text = "You move as one. Something rises from the water.", effects = { { op = "GainRelic" } } },
			failure = { text = "You fall out of step. It smiles.", effects = { { op = "AddCard", card = "Doubt" } } },
		},
		LEAVE,
	},
}

Events.FallenKnight = {
	name = "Fallen Knight",
	text = "A knight in Warden colours lies by the road, long dead.",
	options = {
		{
			label = "Take up his shield",
			requires = { { kind = "Hero", hero = "Warden" } },
			outcome = { text = "It fits your arm perfectly.", effects = { { op = "AddCard", card = "Bulwark" } } },
		},
		{
			label = "Bury him",
			outcome = {
				text = "You feel lighter for it.",
				effects = { { op = "Heal", amount = 10 }, { op = "GainMaxHp", amount = 3 } },
			},
		},
	},
}

Events.MerchantCaravan = {
	name = "Merchant Caravan",
	text = "A caravan stops to trade.",
	options = {
		{
			label = "Sell a card",
			requires = { { kind = "Removable" } },
			outcome = {
				text = "\"A fine piece. Pleasure doing business.\"",
				effects = { { op = "ChooseRemove" }, { op = "GainGold", amount = 50 } },
			},
		},
		{
			label = "Buy supplies",
			requires = { { kind = "Gold", amount = 25 } },
			cost = { { op = "LoseGold", amount = 25 } },
			outcome = { text = "A hot meal and fresh bandages.", effects = { { op = "Heal", amount = 20 } } },
		},
		LEAVE,
	},
}

Events.CollapsedMine = {
	name = "Collapsed Mine",
	text = "Gold glints between fallen beams.",
	options = {
		{
			label = "Dig it out",
			cost = { { op = "LoseHp", amount = 8 } },
			outcome = { text = "Bruised but richer.", effects = { { op = "GainGold", amount = 60 } } },
		},
		{
			label = "Brace the tunnel",
			check = { kind = "TotalCost", atLeast = 5 },
			success = { text = "Deep inside you find an old chest.", effects = { { op = "GainRelic" } } },
			failure = { text = "The roof comes down.", effects = { { op = "LoseHp", amount = 5 } } },
		},
		LEAVE,
	},
}

Events.BloodAltar = {
	name = "Blood Altar",
	text = "A relic rests on an altar stained dark red.",
	options = {
		{
			label = "Offer your blood",
			requires = { { kind = "MinHp", amount = 10 } },
			cost = { { op = "LoseMaxHp", amount = 6 } },
			outcome = { text = "The altar drinks, and gives.", effects = { { op = "GainRelic" } } },
		},
		{
			label = "Pray",
			check = { kind = "CountUpgraded", count = 1 },
			success = { text = "A warm light washes over you.", effects = { { op = "Heal", percent = 0.3 } } },
			failure = { text = "Nothing answers.", effects = {} },
		},
		LEAVE,
	},
}

for id, event in Events do
	event.id = id
end

return Events
