local Content = require("../src/shared/Data/Content")
local Combat = require("../src/server/Combat/Combat")
local Rewards = require("../src/server/Run/Rewards")
local Run = require("../src/server/Run/Run")
local StatusSystem = require("../src/server/Combat/StatusSystem")
local TestKit = require("./TestKit")
local expect = TestKit.expect

-- A fight with a hand of exactly `hand` (the deck is that list).
local function newCombat(hero: string, hand: { string }, overrides)
	local config = { seed = 3, hero = hero, enemies = { "Cultist" }, deck = hand }
	for k, v in overrides or {} do
		config[k] = v
	end
	local combat = Combat.new(Content, config)
	combat:start()
	return combat
end

local function play(combat, cardId: string, targetId: string?)
	for _, card in combat.hand do
		if card.id == cardId then
			local ok, err = combat:playCard(card.uid, targetId or "e1")
			assert(ok, err)
			return
		end
	end
	error(`no {cardId} in hand`)
end

local function enemyTurnStart(combat, enemy)
	StatusSystem.trigger(combat, enemy, "OnTurnStart")
end

return function(t)
	t.test("each class starts a run with its own starter deck and card pool", function()
		for _, hero in { "Warden", "Alchemist", "Hexxer" } do
			local run = Run.new(Content, { seed = 5, hero = hero })
			expect.equal(#run.deck, 10, hero)
			local ids = {}
			for _, card in run.deck do
				ids[card.id] = (ids[card.id] or 0) + 1
			end
			expect.equal(ids.Strike, 4, hero)
			expect.equal(ids.Guard, 4, hero)
			for _, cardId in Rewards.cardPool(Content, hero) do
				local class = Content.Cards[cardId].class
				expect.truthy(class == hero or class == "Neutral", `{hero} offered {cardId}`)
			end
		end
		local alchemist = Run.new(Content, { seed = 5, hero = "Alchemist" })
		expect.equal(alchemist:getSnapshot().hero.id, "Alchemist")
	end)

	t.test("class QTE cards: the Alchemist mixes Sequences, the Hexxer draws Traces", function()
		local kinds = { Alchemist = "Sequence", Hexxer = "Trace" }
		local counts = { Alchemist = 0, Hexxer = 0 }
		for id, card in Content.Cards do
			local want = kinds[card.class]
			if want and card.qte then
				expect.equal(card.qte.kind, want, id)
				counts[card.class] += 1
			end
		end
		expect.truthy(counts.Alchemist >= 3, "Alchemist QTE cards")
		expect.truthy(counts.Hexxer >= 3, "Hexxer QTE cards")
	end)

	-- Alchemist ---------------------------------------------------------------

	t.test("Catalyst: 2 different DoTs make DoT damage 25% higher", function()
		local combat = newCombat("Alchemist", { "Guard" })
		local enemy = combat.enemies[1]
		enemy.statuses.Poison = 4
		local hp = enemy.hp
		enemyTurnStart(combat, enemy)
		expect.equal(hp - enemy.hp, 4, "one DoT: plain Poison")

		enemy.statuses.Poison = 4
		enemy.statuses.Bleed = 1
		hp = enemy.hp
		enemyTurnStart(combat, enemy)
		expect.equal(hp - enemy.hp, 5, "Poison 4 x1.25")

		enemy.statuses.Poison = 2
		enemy.statuses.Bleed = 1
		hp = enemy.hp
		enemyTurnStart(combat, enemy)
		expect.equal(hp - enemy.hp, 3, "Poison 2 x1.25 = 2.5, rounded to nearest")

		-- Only the Alchemist has Catalyst.
		local warden = newCombat("Warden", { "Guard" })
		local other = warden.enemies[1]
		other.statuses.Poison = 4
		other.statuses.Bleed = 1
		hp = other.hp
		enemyTurnStart(warden, other)
		expect.equal(hp - other.hp, 4)
	end)

	t.test("Toxic Flask poisons; Volatile Mix lights an unburnt enemy, then detonates", function()
		local combat = newCombat("Alchemist", { "ToxicFlask", "VolatileMix", "VolatileMix" })
		local enemy = combat.enemies[1]
		play(combat, "ToxicFlask")
		expect.equal(enemy.statuses.Poison, 4)

		-- No Burn: apply 3, then consume it for 2x. Poison + Burn trigger Catalyst.
		local hp = enemy.hp
		play(combat, "VolatileMix")
		expect.equal(hp - enemy.hp, 8, "3 Burn x2 x1.25 = 7.5, rounded to nearest")
		expect.equal(enemy.statuses.Burn, nil, "Burn consumed")

		enemy.statuses.Poison = nil
		enemy.statuses.Burn = 5
		hp = enemy.hp
		play(combat, "VolatileMix")
		expect.equal(hp - enemy.hp, 10, "5 Burn x2")
	end)

	t.test("Detonate hits Block and Chain Reaction bursts every enemy", function()
		local combat = newCombat("Alchemist", { "ChainReaction" }, { enemies = { "Cultist", "AcidSlime" } })
		local a, b = combat.enemies[1], combat.enemies[2]
		a.statuses.Burn = 3
		b.statuses.Poison = 4
		b.block = 2
		local hpA, hpB = a.hp, b.hp
		play(combat, "ChainReaction", nil)
		expect.equal(hpA - a.hp, 6)
		expect.equal(hpB - b.hp, 6, "8 damage, 2 blocked")
		expect.equal(b.statuses.Poison, nil)
	end)

	t.test("Toxic Fumes poisons every enemy at the start of each turn", function()
		local combat = newCombat("Alchemist", { "ToxicFumes", "Guard", "Guard", "Guard", "Guard", "Guard" })
		play(combat, "ToxicFumes")
		expect.equal(combat.hero.statuses.Miasma, 2)
		combat:endTurn()
		-- Cultist's turn 1 is a buff, so no QTE; Poison lands on our next turn.
		expect.equal(combat.enemies[1].statuses.Poison, 2)
	end)

	t.test("an Alchemist's Perfect parry poisons the attacker", function()
		local combat = newCombat("Alchemist", { "Guard", "Guard", "Guard", "Guard", "Guard" }, {
			qteHandler = function()
				return "Perfect"
			end,
		})
		combat:endTurn()
		combat:endTurn()
		-- Poison ticks at the Cultist's turn start, which came before the hit.
		expect.equal(combat.enemies[1].statuses.Poison, 2)
		expect.equal(combat.hero.hp, 70)
	end)

	-- Hexxer ------------------------------------------------------------------

	t.test("Malice: Hexxer debuffs get +1 stack, and 3 debuffs mean +25% damage", function()
		local combat = newCombat("Hexxer", { "EvilEye", "Strike", "Strike" })
		local enemy = combat.enemies[1]
		play(combat, "EvilEye")
		expect.equal(enemy.statuses.Weak, 3)
		expect.equal(enemy.statuses.Vulnerable, 3)

		local hp = enemy.hp
		play(combat, "Strike")
		expect.equal(hp - enemy.hp, 9, "two debuffs: 6 x1.5")

		enemy.statuses.Frail = 1
		hp = enemy.hp
		play(combat, "Strike")
		expect.equal(hp - enemy.hp, 11, "three debuffs: 6 x1.5 x1.25")

		-- A Warden's debuffs keep their printed stacks.
		local warden = newCombat("Warden", { "Taunt" })
		play(warden, "Taunt")
		expect.equal(warden.enemies[1].statuses.Weak, 2)
	end)

	t.test("Siphon steals a buff, or curses an enemy with none", function()
		local combat = newCombat("Hexxer", { "Siphon", "Siphon" })
		local enemy = combat.enemies[1]
		enemy.statuses.Strength = 3
		play(combat, "Siphon")
		expect.equal(enemy.statuses.Strength, nil)
		expect.equal(combat.hero.statuses.Strength, 3)

		play(combat, "Siphon")
		expect.equal(enemy.statuses.Weak, 2, "1 Weak, +1 from Malice")
	end)

	t.test("Mirror Curse moves the Hexxer's debuffs onto an enemy", function()
		local combat = newCombat("Hexxer", { "DarkPact", "MirrorCurse" })
		play(combat, "DarkPact")
		expect.equal(combat.hero.statuses.Strength, 2)
		expect.equal(combat.hero.statuses.Weak, 2)
		play(combat, "MirrorCurse")
		expect.equal(combat.hero.statuses.Weak, nil)
		expect.equal(combat.hero.statuses.Strength, 2, "buffs stay")
		expect.equal(combat.enemies[1].statuses.Weak, 3, "2 moved, +1 from Malice")
		expect.equal(combat.hero.block, 6)
	end)

	t.test("Mirror Curse moves Poison, Bleed and Burn onto the enemy unchanged", function()
		local combat = newCombat("Hexxer", { "MirrorCurse" })
		local hero, enemy = combat.hero, combat.enemies[1]
		hero.statuses.Poison = 5
		hero.statuses.Bleed = 2
		hero.statuses.Burn = 3
		play(combat, "MirrorCurse")
		expect.equal(hero.statuses.Poison, nil)
		expect.equal(hero.statuses.Bleed, nil)
		expect.equal(hero.statuses.Burn, nil)
		expect.equal(enemy.statuses.Poison, 5, "DoTs are not debuffs: no Malice stack")
		expect.equal(enemy.statuses.Bleed, 2)
		expect.equal(enemy.statuses.Burn, 3)
	end)

	t.test("Spite and Doom scale with the number of different debuffs", function()
		local combat = newCombat("Hexxer", { "Spite", "Doom" }, {
			qteHandler = function()
				return "Miss"
			end,
		})
		local enemy = combat.enemies[1]
		enemy.statuses.Weak = 1
		enemy.statuses.Frail = 1
		local hp = enemy.hp
		play(combat, "Spite")
		expect.equal(hp - enemy.hp, 10, "4 + 2 x3")
		hp = enemy.hp
		play(combat, "Doom")
		expect.equal(hp - enemy.hp, 18, "8 + 2 x5")
	end)

	t.test("Dazed on an enemy widens your QTE against its attacks", function()
		local windows = {}
		local combat = newCombat("Hexxer", { "Guard", "Guard", "Guard", "Guard", "Guard" }, {
			qteHandler = function(request)
				table.insert(windows, request.windowMult)
				return "Perfect"
			end,
		})
		combat:endTurn()
		combat.enemies[1].statuses.Dazed = 2
		combat:endTurn()
		expect.equal(#windows, 1)
		expect.truthy(math.abs(windows[1] - 1.4) < 1e-6, `window {windows[1]}`)
		-- The Hexxer's parry curses the attacker: 1 Weak, +1 from Malice, then
		-- one round of decay.
		expect.equal(combat.enemies[1].statuses.Weak, 1)
	end)
end
