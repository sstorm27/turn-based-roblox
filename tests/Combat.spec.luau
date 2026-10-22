local Content = require("../src/shared/Data/Content")
local Combat = require("../src/server/Combat/Combat")
local TestKit = require("./TestKit")
local expect = TestKit.expect

local function fill(id: any, count: number)
	local deck = {}
	for i = 1, count do
		deck[i] = id
	end
	return deck
end

local function newCombat(overrides)
	local config = {
		seed = 7,
		hero = "Warden",
		enemies = { "Cultist" },
		deck = fill("Strike", 10),
	}
	for k, v in overrides or {} do
		config[k] = v
	end
	local combat = Combat.new(Content, config)
	combat:start()
	return combat
end

local function cardInHand(combat, id: string)
	for _, card in combat.hand do
		if card.id == id then
			return card.uid
		end
	end
	error(`no {id} in hand`)
end

local function eventsOfType(events, eventType: string)
	local list = {}
	for _, event in events do
		if event.type == eventType then
			table.insert(list, event)
		end
	end
	return list
end

local function always(grade: string)
	return function()
		return grade
	end
end

return function(t)
	t.test("start draws 5, fills energy and rolls intents", function()
		local combat = newCombat()
		local snap = combat:getSnapshot()
		expect.equal(snap.phase, "PlayerTurn")
		expect.equal(snap.turn, 1)
		expect.equal(snap.energy, 3)
		expect.equal(#snap.hand, 5)
		expect.equal(snap.drawCount, 5)
		expect.equal(snap.enemies[1].intent.moveId, "Incantation")
	end)

	t.test("playing Strike deals 6, spends energy and discards it", function()
		local combat = newCombat()
		local enemy = combat.enemies[1]
		local hp = enemy.hp
		local ok = combat:playCard(cardInHand(combat, "Strike"), "e1")
		expect.truthy(ok, "played")
		expect.equal(enemy.hp, hp - 6, "enemy hp")
		expect.equal(combat.energy, 2, "energy")
		expect.equal(#combat.discardPile, 1, "discard")
		expect.equal(#combat.hand, 4, "hand")
	end)

	t.test("rejects plays without energy, target or card", function()
		local combat = newCombat()
		for _ = 1, 3 do
			assert(combat:playCard(cardInHand(combat, "Strike"), "e1"))
		end
		local ok, err = combat:playCard(cardInHand(combat, "Strike"), "e1")
		expect.falsy(ok)
		expect.equal(err, "not enough energy")

		combat = newCombat()
		ok, err = combat:playCard(cardInHand(combat, "Strike"), "e9")
		expect.equal(err, "invalid target")
		ok, err = combat:playCard(cardInHand(combat, "Strike"), "hero")
		expect.equal(err, "invalid target")
		ok, err = combat:playCard("c999", "e1")
		expect.equal(err, "card not in hand")
	end)

	t.test("damage formula: (base + Strength) x1.5 Vulnerable x0.75 Weak, rounded down", function()
		local combat = newCombat()
		local enemy = combat.enemies[1]
		combat.hero.statuses.Strength = 2
		combat.hero.statuses.Weak = 1
		enemy.statuses.Vulnerable = 1
		local hp = enemy.hp
		combat:playCard(cardInHand(combat, "Strike"), "e1")
		expect.equal(hp - enemy.hp, 9) -- floor(8 * 1.5 * 0.75)
	end)

	t.test("Block absorbs damage and Frail / Dexterity change Block gained", function()
		local combat = newCombat({ deck = fill("Guard", 10) })
		combat.hero.statuses.Dexterity = 3
		combat:playCard(cardInHand(combat, "Guard"))
		expect.equal(combat.hero.block, 8)
		combat.hero.statuses.Frail = 1
		combat:playCard(cardInHand(combat, "Guard"))
		expect.equal(combat.hero.block, 14) -- 8 + floor(8 * 0.75)
		combat:applyDamage(combat.hero, 20, { isAttack = false })
		expect.equal(combat.hero.block, 0)
		expect.equal(combat.hero.hp, 64)
	end)

	t.test("Shield Bash deals damage equal to Block", function()
		local combat = newCombat({ deck = { "ShieldBash", "Guard", "Guard", "Guard", "Guard" } })
		combat:playCard(cardInHand(combat, "Guard"))
		local hp = combat.enemies[1].hp
		combat:playCard(cardInHand(combat, "ShieldBash"), "e1")
		expect.equal(hp - combat.enemies[1].hp, 5)
	end)

	t.test("Warden keeps 25% of Block; Fortify keeps all of it", function()
		local combat = newCombat({ deck = fill("Guard", 10) })
		combat:playCard(cardInHand(combat, "Guard"))
		combat:playCard(cardInHand(combat, "Guard"))
		combat:endTurn() -- Cultist buffs on turn 1, no damage
		expect.equal(combat.hero.block, 2) -- floor(10 * 0.25)

		combat = newCombat({ deck = fill("Guard", 10) })
		combat:playCard(cardInHand(combat, "Guard"))
		combat.hero.statuses.Fortify = 2
		combat:endTurn()
		expect.equal(combat.hero.block, 5)
	end)

	t.test("a QTE card pauses in AwaitingQte until the grade arrives", function()
		local combat = newCombat({ deck = fill("Smite", 10) })
		local enemy = combat.enemies[1]
		local hp = enemy.hp
		expect.truthy(combat:playCard(cardInHand(combat, "Smite"), "e1"))
		expect.equal(combat.phase, "AwaitingQte")
		expect.equal(enemy.hp, hp, "no damage before the QTE")
		local pending = combat.pendingQte
		expect.equal(pending.source, "Card")
		expect.equal(pending.kind, "Timing")
		expect.equal(pending.difficulty, 2)
		expect.equal(combat:getSnapshot().pendingQte.qteId, pending.qteId)

		local _, err = combat:playCard(cardInHand(combat, "Smite"), "e1")
		expect.equal(err, "not your turn")
		_, err = combat:endTurn()
		expect.equal(err, "not your turn")
		_, err = combat:resolveQte("q999", "Perfect")
		expect.equal(err, "wrong QTE id")
		_, err = combat:resolveQte(pending.qteId, "Amazing")
		expect.equal(err, "invalid grade")

		expect.truthy(combat:resolveQte(pending.qteId, "Perfect"))
		expect.equal(combat.phase, "PlayerTurn")
		expect.equal(hp - enemy.hp, 20, "12 + 8 Perfect bonus")
		expect.equal(enemy.statuses.Vulnerable, 2)
		expect.equal(combat.energy, 1)
		local graded = eventsOfType(combat:takeEvents(), "QteGraded")
		expect.equal(#graded, 1)
		expect.equal(graded[1].grade, "Perfect")
	end)

	t.test("QTE bonuses: Miss plays the printed card, Good merges into one hit", function()
		for grade, expected in { Miss = 12, Good = 16, Perfect = 20 } do
			local combat = newCombat({ deck = fill("Smite", 10), qteHandler = always(grade) })
			local enemy = combat.enemies[1]
			local hp = enemy.hp
			combat:takeEvents()
			combat:playCard(cardInHand(combat, "Smite"), "e1")
			expect.equal(hp - enemy.hp, expected, grade)
			expect.equal(#eventsOfType(combat:takeEvents(), "Damage"), 1, `{grade} hits`)
		end
	end)

	t.test("applyQteBonus appends effects it cannot merge and never mutates data", function()
		local smite = Content.Cards.Smite
		local effects = Combat.applyQteBonus(smite.effects, smite.qte, "Perfect")
		expect.equal(#effects, 2)
		expect.equal(effects[1].amount, 20)
		expect.equal(effects[2].status, "Vulnerable")
		expect.equal(smite.effects[1].amount, 12, "data untouched")
	end)

	t.test("Shield Storm hits all enemies with its Mash bonus", function()
		local combat = newCombat({
			enemies = { "AcidSlime", "AcidSlime" },
			deck = fill("ShieldStorm", 10),
			qteHandler = always("Perfect"),
		})
		local a, b = combat.enemies[1], combat.enemies[2]
		local hpA, hpB = a.hp, b.hp
		combat:playCard(cardInHand(combat, "ShieldStorm"))
		expect.equal(hpA - a.hp, 9)
		expect.equal(hpB - b.hp, 9)
		expect.equal(a.statuses.Weak, 1)
	end)

	t.test("defensive QTE: Miss full, Good half, Perfect avoids and gives Warden 3 Block", function()
		-- Cultist: Incantation (+3 Strength) on turn 1, Dark Strike 6 + 3 after.
		for grade, expected in { Miss = 61, Good = 66, Perfect = 70 } do
			local requests = {}
			local combat = newCombat({
				qteHandler = function(request)
					table.insert(requests, request)
					return grade
				end,
			})
			combat:endTurn()
			expect.equal(combat:getSnapshot().enemies[1].intent.damage, 9, "intent shows Strength")
			combat:endTurn()
			expect.equal(combat.hero.hp, expected, grade)
			expect.equal(#requests, 1)
			expect.equal(requests[1].source, "Defense")
			expect.equal(requests[1].enemyId, "e1")
			expect.equal(requests[1].moveId, "DarkStrike")
			expect.equal(requests[1].incoming, 9)
			if grade == "Perfect" then
				expect.equal(combat.hero.block, 0, "3 Block from the parry, 25% kept rounds to 0")
			end
		end
	end)

	t.test("defensive QTE pauses the enemy turn and resumes it", function()
		local combat = newCombat()
		combat:endTurn()
		expect.equal(combat.turn, 2)
		combat:endTurn()
		expect.equal(combat.phase, "AwaitingQte")
		expect.equal(combat.pendingQte.source, "Defense")
		expect.equal(combat:getSnapshot().pendingQte.kind, "Timing")
		local _, err = combat:playCard("c1", "e1")
		expect.equal(err, "not your turn")
		combat:resolveQte(combat.pendingQte.qteId, "Good")
		expect.equal(combat.phase, "PlayerTurn")
		expect.equal(combat.turn, 3)
		expect.equal(combat.hero.hp, 66)
	end)

	t.test("multi-hit attacks get one QTE per hit with narrower windows", function()
		local requests = {}
		local grades = { "Perfect", "Good", "Miss" }
		local combat = newCombat({
			enemies = { "Bandit" },
			qteHandler = function(request)
				table.insert(requests, request)
				return grades[#requests]
			end,
		})
		combat.enemies[1].intent = { moveId = "Flurry" }
		combat:takeEvents()
		combat:endTurn()
		expect.equal(#requests, 3)
		for i, request in requests do
			expect.equal(request.hit, i)
			expect.equal(request.hits, 3)
			expect.equal(request.windowMult, Content.Qte.MultiHitWindowMult)
		end
		local events = combat:takeEvents()
		expect.equal(#eventsOfType(events, "Dodged"), 1)
		local damage = eventsOfType(events, "Damage")
		expect.equal(#damage, 2)
		expect.equal(damage[1].amount, 1) -- floor(3 * 0.5)
		expect.equal(damage[2].amount, 3)
		-- Perfect gave 3 Block, which soaked 1 then 2 of the next hits.
		expect.equal(combat.hero.hp, 69)
	end)

	t.test("defensive QTEs leave a move's debuffs in place", function()
		local combat = newCombat({ enemies = { "Bandit" }, qteHandler = always("Perfect") })
		combat.enemies[1].intent = { moveId = "Stab" }
		combat:endTurn()
		expect.equal(combat.hero.hp, 70)
		expect.equal(combat.hero.statuses.Vulnerable, 1, "debuff applied and kept through the round")
	end)

	t.test("Focus, Dazed and wide windows change the QTE window multiplier", function()
		local seen
		local combat = newCombat({
			deck = fill("Smite", 10),
			qteHandler = function(request)
				seen = request
				return "Miss"
			end,
		})
		combat.hero.statuses.Focus = 2
		combat:playCard(cardInHand(combat, "Smite"), "e1")
		expect.equal(seen.windowMult, 1.4)

		combat = newCombat({ deck = fill("Smite", 10), wideQteWindows = true, qteHandler = function(request)
			seen = request
			return "Miss"
		end })
		combat.hero.statuses.Dazed = 1
		combat:playCard(cardInHand(combat, "Smite"), "e1")
		expect.equal(math.floor(seen.windowMult * 100 + 0.5), 120) -- 0.8 * 1.5
	end)

	t.test("enemy QTE difficulty gets the act bonus, capped at 5", function()
		local seen
		local combat = newCombat({
			enemies = { "Bandit" },
			qteDifficultyBonus = 4,
			qteHandler = function(request)
				seen = request
				return "Miss"
			end,
		})
		combat.enemies[1].intent = { moveId = "Slash" }
		combat:endTurn()
		expect.equal(seen.difficulty, 5)
	end)

	t.test("debuffs from enemies last through the hero's next turn", function()
		local combat = newCombat({ enemies = { "AcidSlime" } })
		combat.enemies[1].intent = { moveId = "Lick" }
		combat:endTurn()
		expect.equal(combat.hero.statuses.Weak, 1)
		combat.enemies[1].intent = { moveId = "Lick" }
		combat.enemies[1].statuses.Stun = 1
		combat:endTurn()
		expect.equal(combat.hero.statuses.Weak, nil, "decays the round after")
	end)

	t.test("Pollute shuffles Wounds into the discard; Wounds are unplayable", function()
		local combat = newCombat({ enemies = { "AcidSlime" } })
		combat.enemies[1].intent = { moveId = "Spit" }
		combat:endTurn()
		local wounds = 0
		for _, pile in { combat.drawPile, combat.hand, combat.discardPile } do
			for _, card in pile do
				if card.id == "Wound" then
					wounds += 1
				end
			end
		end
		expect.equal(wounds, 2)
		local wound = { id = "Wound" }
		expect.falsy(combat:canPlay(wound))
	end)

	t.test("Poison ticks at turn start and decays; Stun skips a move", function()
		local combat = newCombat()
		local enemy = combat.enemies[1]
		enemy.statuses.Poison = 3
		enemy.statuses.Stun = 1
		local hp = enemy.hp
		combat:endTurn()
		expect.equal(enemy.hp, hp - 3)
		expect.equal(enemy.statuses.Poison, 2)
		expect.equal(enemy.statuses.Strength, nil, "stunned, so no Incantation")
	end)

	t.test("Thorns hits back; Bleed hurts on each hit and halves at round end", function()
		local combat = newCombat({ qteHandler = always("Miss") })
		local enemy = combat.enemies[1]
		combat:endTurn()
		combat.hero.statuses.Thorns = 2
		local hp = enemy.hp
		combat:endTurn()
		expect.equal(hp - enemy.hp, 2)

		combat = newCombat()
		enemy = combat.enemies[1]
		enemy.statuses.Bleed = 5
		hp = enemy.hp
		combat:playCard(cardInHand(combat, "Strike"), "e1")
		expect.equal(hp - enemy.hp, 11)
		combat:endTurn()
		expect.equal(enemy.statuses.Bleed, 2)
	end)

	t.test("draw reshuffles the discard when the draw pile runs out", function()
		local combat = newCombat({ deck = fill("Strike", 7) })
		expect.equal(#combat.drawPile, 2)
		combat:takeEvents()
		combat:endTurn()
		expect.equal(#combat.hand, 5)
		expect.equal(#eventsOfType(combat:takeEvents(), "Reshuffled"), 1)
	end)

	t.test("hand is capped at 10", function()
		local combat = newCombat({ deck = fill("Brace", 20) })
		combat:draw(10)
		expect.equal(#combat.hand, 10)
	end)

	t.test("winning and losing end the combat", function()
		local combat = newCombat()
		combat.enemies[1].hp = 5
		combat:playCard(cardInHand(combat, "Strike"), "e1")
		expect.equal(combat.phase, "Won")
		local _, err = combat:playCard(cardInHand(combat, "Strike"), "e1")
		expect.equal(err, "not your turn")

		combat = newCombat({ qteHandler = always("Miss"), heroHp = 5 })
		combat:endTurn()
		combat:endTurn()
		expect.equal(combat.phase, "Lost")
		expect.equal(combat.hero.hp, 0)
	end)

	t.test("the same seed gives the same fight", function()
		local function handIds(seed)
			local combat = newCombat({ seed = seed, deck = Content.Encounters.Prototype.deck })
			local ids = {}
			for _, card in combat.hand do
				table.insert(ids, card.uid)
			end
			return table.concat(ids, ",")
		end
		expect.equal(handIds(99), handIds(99))
		expect.truthy(handIds(1) ~= handIds(2) or handIds(3) ~= handIds(4), "seeds differ")
	end)

	t.test("upgraded cards use their path's override", function()
		local combat = newCombat({ deck = fill({ id = "ShieldBash", upgrade = "B" }, 10) })
		local def = combat:getCardDef(combat.hand[1])
		expect.equal(def.cost, 0)
		expect.equal(def.name, "Light Shield Bash")
		combat:playCard(combat.hand[1].uid, "e1")
		expect.equal(#combat.exhaustPile, 1)
	end)

	t.test("a full prototype fight finishes with scripted play", function()
		local combat = Combat.new(Content, { seed = 3, encounter = "Prototype", qteHandler = always("Good") })
		combat:start()
		for _ = 1, 60 do
			if combat:isOver() then
				break
			end
			-- Play every affordable card on the first enemy, then end the turn.
			local played = true
			while played and combat.phase == "PlayerTurn" do
				played = false
				for _, card in combat.hand do
					if combat:canPlay(card) then
						local target = combat:livingEnemies()[1]
						if combat:playCard(card.uid, target and target.id) then
							played = true
							break
						end
					end
				end
			end
			if not combat:isOver() then
				combat:endTurn()
			end
		end
		expect.truthy(combat:isOver(), "fight ended")
	end)
end
