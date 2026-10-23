local Content = require("../src/shared/Data/Content")
local Run = require("../src/server/Run/Run")
local RunValidator = require("../src/server/Run/RunValidator")
local TestKit = require("./TestKit")
local expect = TestKit.expect

local function newRun(seed: number?, hero: string?)
	return Run.new(Content, {
		seed = seed or 11,
		hero = hero,
		qteHandler = function()
			return "Perfect"
		end,
	})
end

-- Kills every enemy in the current fight, then lets the run hand out rewards.
local function winFight(run)
	local combat = run.combat
	assert(combat, "no fight running")
	for _, enemy in combat.enemies do
		combat:applyDamage(enemy, 9999, {})
	end
	expect.truthy(run:checkCombat(), "fight handled")
end

-- Puts the run on a node of the given type as if the player had walked there.
local function enterNode(run, nodeType: string)
	local map = run.map
	for row = 1, map.rowCount do
		for _, id in map.rows[row] do
			if map.nodes[id].type == nodeType then
				run.screen = { kind = "Map" }
				run.currentNodeId = map.nodes[id].prev[1]
				expect.truthy(run:chooseNode(id), `enter {id}`)
				return id
			end
		end
	end
	error(`no {nodeType} node on this map`)
end

local function showEvent(run, eventId: string)
	run.stack = {}
	run.screen = { kind = "Event", ready = true, eventId = eventId }
end

local function deckOf(run, cardId: string, count: number)
	run.deck = {}
	for _ = 1, count do
		run:addCard(cardId)
	end
end

local function countCard(run, cardId: string): number
	local n = 0
	for _, card in run.deck do
		if card.id == cardId then
			n += 1
		end
	end
	return n
end

-- A simple bot: plays what it can (attacks on the first living enemy), then
-- ends the turn, and always takes the first available choice outside combat.
local function playCombatTurn(combat)
	local played = true
	while played and combat.phase == "PlayerTurn" do
		played = false
		for _, card in combat:getSnapshot().hand do
			if card.playable then
				local target = combat:livingEnemies()[1]
				if combat:playCard(card.uid, target and target.id) then
					played = true
					break
				end
			end
		end
	end
	if combat.phase == "PlayerTurn" then
		combat:endTurn()
	end
end

local function botStep(run)
	local snap = run:getSnapshot()
	local screen = snap.screen
	local kind = screen.kind
	if kind == "Map" then
		return run:chooseNode(snap.map.pathCards[1].nodeId)
	elseif kind == "Combat" then
		playCombatTurn(run.combat)
		run:checkCombat()
		return true
	elseif kind == "Reward" then
		return run:chooseOption(1)
	elseif kind == "RelicChoice" then
		return run:chooseOption(1)
	elseif kind == "Event" then
		for _, option in screen.event.options do
			if option.available then
				return run:chooseOption(option.index)
			end
		end
		error("no available event option")
	elseif kind == "Rest" then
		for index, option in screen.options do
			if option.available then
				return run:chooseOption(index)
			end
		end
	elseif kind == "SelectCard" then
		return run:selectCard(screen.candidates[1], "A")
	elseif kind == "Shop" then
		if not screen.cards[1].sold and snap.gold >= screen.cards[1].price then
			return run:buy("Card", 1)
		end
		return run:proceed()
	end
	return run:proceed()
end

return function(t)
	t.test("content: run data validates and the validator catches mistakes", function()
		local errors = RunValidator.validate(Content)
		expect.equal(#errors, 0, table.concat(errors, "\n"))

		local broken = table.clone(Content)
		broken.Events = table.clone(Content.Events)
		broken.Events.Broken = {
			id = "Broken",
			options = {
				{
					label = "x",
					requires = { { kind = "Charisma" } },
					outcome = { effects = { { op = "Teleport" }, { op = "AddCard", card = "Nope" } } },
				},
			},
		}
		errors = RunValidator.validate(broken)
		-- Unknown requirement, unknown op, unknown card, and no way to leave.
		expect.equal(#errors, 4, table.concat(errors, "\n"))
	end)

	t.test("a run starts on the act 1 map with the starter deck", function()
		local run = newRun()
		local snap = run:getSnapshot()
		expect.equal(snap.phase, "Map")
		expect.equal(snap.hero.hp, 70)
		expect.equal(snap.gold, 99)
		expect.equal(#snap.deck, 10)
		expect.equal(snap.map.progress.row, 0)
		expect.equal(snap.map.progress.rows, 15)
		expect.truthy(#snap.map.pathCards >= 2 and #snap.map.pathCards <= 3, "2 or 3 path cards")
		for _, card in snap.map.pathCards do
			expect.equal(card.type, "Combat", "row 1 is always a fight")
			expect.truthy(#card.leadsTo >= 1, "leads somewhere")
		end
		local stops = {}
		for _, stop in snap.map.progress.stops do
			stops[stop.type] = stop.row
		end
		expect.equal(stops.Treasure, 8)
		expect.equal(stops.Rest, 14)
		expect.equal(stops.Boss, 15)
	end)

	t.test("the same seed plays the same run", function()
		local a, b = newRun(99), newRun(99)
		for _ = 1, 40 do
			botStep(a)
			botStep(b)
		end
		local sa, sb = a:getSnapshot(), b:getSnapshot()
		expect.equal(sa.phase, sb.phase)
		expect.equal(sa.hero.hp, sb.hero.hp)
		expect.equal(sa.gold, sb.gold)
		expect.equal(#sa.deck, #sb.deck)
		expect.equal(sa.map.progress.row, sb.map.progress.row)
	end)

	t.test("only reachable nodes can be chosen, and only from the map", function()
		local run = newRun()
		local ok, err = run:chooseNode(run.map.bossId)
		expect.falsy(ok)
		expect.equal(err, "node not reachable")
		local first = run:getSnapshot().map.pathCards[1].nodeId
		expect.truthy(run:chooseNode(first))
		ok, err = run:chooseNode(first)
		expect.falsy(ok)
		expect.equal(err, "not on the map")
	end)

	t.test("a fight uses the run's deck and HP, then offers gold and 3 cards", function()
		local run = newRun()
		run.hp = 50
		run:upgradeCard(run.deck[1].uid, "A")
		expect.truthy(run:chooseNode(run:pathChoices()[1]))
		expect.equal(run.screen.kind, "Combat")
		local combat = run.combat
		expect.equal(combat.hero.hp, 50)
		expect.equal(#combat.drawPile + #combat.hand, 10)
		local upgraded = 0
		for _, card in combat.drawPile do
			upgraded += if card.upgrade then 1 else 0
		end
		for _, card in combat.hand do
			upgraded += if card.upgrade then 1 else 0
		end
		expect.equal(upgraded, 1, "upgrade carried into the fight")

		combat.hero.hp = 41
		winFight(run)
		expect.equal(run.hp, 41, "HP carries over")
		local screen = run:getSnapshot().screen
		expect.equal(screen.kind, "Reward")
		expect.truthy(screen.gold >= 10 and screen.gold <= 20, "gold 10 to 20")
		expect.equal(run.gold, 99 + screen.gold)
		expect.equal(#screen.cards, 3)
		local picked = screen.cards[2].id
		expect.truthy(run:chooseOption(2))
		expect.equal(#run.deck, 11)
		expect.equal(run.deck[11].id, picked)
		expect.equal(run.screen.kind, "Map")
		expect.equal(run:getSnapshot().map.progress.row, 1)
	end)

	t.test("rewards can be skipped and never offer starter or junk cards", function()
		local run = newRun()
		for _ = 1, 20 do
			run.stack = {}
			run.screen = { kind = "Map" }
			run:_show({ kind = "Reward", source = "Combat" })
			for _, cardId in run.screen.cards do
				local rarity = Content.Cards[cardId].rarity
				expect.truthy(rarity == "Common" or rarity == "Uncommon" or rarity == "Rare", `{cardId} {rarity}`)
			end
		end
		expect.truthy(run:skip())
		expect.equal(#run.deck, 10)
	end)

	t.test("one death ends the run", function()
		local run = newRun()
		run.hp = 1
		run.config.qteHandler = function()
			return "Miss"
		end
		run:chooseNode(run:pathChoices()[1])
		local combat = run.combat
		for _ = 1, 30 do
			if combat:isOver() then
				break
			end
			combat:endTurn()
		end
		expect.equal(combat.phase, "Lost")
		expect.truthy(run:checkCombat())
		local snap = run:getSnapshot()
		expect.equal(snap.phase, "Lost")
		expect.truthy(snap.over)
		expect.equal(snap.hero.hp, 0)
		expect.equal(snap.screen.renown, 1, "1 renown for the row climbed")
		local ok, err = run:perform({ kind = "Proceed" })
		expect.falsy(ok)
		expect.equal(err, "the run is over")
	end)

	t.test("elite fights pay 25 to 35 gold and a relic", function()
		local run = newRun(3)
		enterNode(run, "Elite")
		expect.equal(run.screen.fightKind, "Elite")
		winFight(run)
		local screen = run:getSnapshot().screen
		expect.truthy(screen.gold >= 25 and screen.gold <= 35, "elite gold")
		expect.truthy(screen.relic, "elite relic")
		expect.equal(#run.relics, 1)
	end)

	t.test("treasure gives a relic", function()
		local run = newRun()
		enterNode(run, "Treasure")
		local screen = run:getSnapshot().screen
		expect.equal(screen.kind, "Treasure")
		expect.truthy(screen.relic, "a relic")
		expect.truthy(run:hasRelic(screen.relic.id))
		expect.truthy(run:proceed())
		expect.equal(run.screen.kind, "Map")
	end)

	t.test("beating the boss heals fully, offers boss relics and wins the run", function()
		local run = newRun()
		run.hp = 20
		run.currentNodeId = run.map.nodes[run.map.bossId].prev[1]
		expect.truthy(run:chooseNode(run.map.bossId))
		expect.equal(run.screen.encounterId, "HollowKing")
		winFight(run)
		expect.equal(run.hp, run.maxHp, "full heal")
		local reward = run:getSnapshot().screen
		for _, card in reward.cards do
			expect.equal(card.rarity, "Rare")
		end
		expect.equal(reward.gold, 75)
		expect.truthy(run:skip())
		local choice = run:getSnapshot().screen
		expect.equal(choice.kind, "RelicChoice")
		expect.equal(#choice.relics, 3)
		for _, relic in choice.relics do
			expect.equal(relic.rarity, "Boss")
		end
		expect.truthy(run:chooseOption(1))
		local snap = run:getSnapshot()
		expect.equal(snap.phase, "Won")
		expect.truthy(snap.over)
		-- 1 row + 25 boss + 50 win.
		expect.equal(snap.renown, 76)
	end)

	t.test("events: a card check reveals the top 3 cards and branches", function()
		local run = newRun()
		deckOf(run, "Strike", 10)
		showEvent(run, "ShrineOfBlades")
		expect.truthy(run:chooseOption(1))
		local result = run:getSnapshot().screen
		expect.equal(result.kind, "EventResult")
		expect.equal(#result.revealed, 3)
		expect.equal(result.success, true)
		local upgraded = 0
		for _, card in run.deck do
			upgraded += if card.upgrade then 1 else 0
		end
		expect.equal(upgraded, 2, "two Attacks upgraded")

		local failing = newRun()
		deckOf(failing, "Guard", 10)
		showEvent(failing, "ShrineOfBlades")
		failing:chooseOption(1)
		expect.equal(failing.screen.success, false)
		expect.equal(failing.hp, 64, "lost 6 HP")
		expect.truthy(failing:proceed())
		expect.equal(failing.screen.kind, "Map")
	end)

	t.test("events: unmet requirements grey an option out", function()
		local run = newRun()
		run.gold = 10
		showEvent(run, "WanderingSmith")
		local options = run:getSnapshot().screen.event.options
		expect.falsy(options[1].available, "needs 40 gold")
		expect.truthy(options[2].available)
		expect.truthy(options[3].available)
		local ok, err = run:chooseOption(1)
		expect.falsy(ok)
		expect.equal(err, "option requirements not met")
		expect.equal(run.gold, 10)
	end)

	t.test("events: costs, card picks and fights come in order", function()
		local run = newRun()
		showEvent(run, "MerchantCaravan")
		expect.truthy(run:chooseOption(1))
		expect.equal(run.gold, 149, "paid on the spot")
		expect.truthy(run:proceed())
		local pick = run:getSnapshot().screen
		expect.equal(pick.kind, "SelectCard")
		expect.equal(pick.purpose, "Remove")
		expect.falsy(pick.cancellable)
		expect.falsy(run:cancel())
		expect.truthy(run:selectCard(pick.candidates[1]))
		expect.equal(#run.deck, 9)
		expect.equal(run.screen.kind, "Map")

		showEvent(run, "BanditToll")
		expect.truthy(run:chooseOption(2))
		expect.truthy(run:proceed())
		expect.equal(run.screen.kind, "Combat")
		expect.equal(run.screen.encounterId, "Highwayman")
		winFight(run)
		expect.equal(run:getSnapshot().screen.gold, 30)
	end)

	t.test("events: curses join the deck and outcomes heal by percent", function()
		local run = newRun()
		run.hp = 40
		showEvent(run, "OldWell")
		expect.truthy(run:chooseOption(1))
		expect.equal(run.hp, 57, "healed 25% of 70")
		expect.equal(countCard(run, "Doubt"), 1)
	end)

	t.test("events: losing HP in an event can end the run", function()
		local run = newRun()
		run.hp = 5
		deckOf(run, "Guard", 10)
		showEvent(run, "ShrineOfBlades")
		run:chooseOption(1)
		expect.equal(run.screen.kind, "Lost")
		expect.truthy(run.over)
	end)

	t.test("events never repeat in a run", function()
		local run = newRun()
		local seen = {}
		for _ = 1, #Content.Acts[1].events do
			run.stack = {}
			run:_show({ kind = "Event" })
			expect.equal(run.screen.kind, "Event")
			expect.falsy(seen[run.screen.eventId], run.screen.eventId)
			seen[run.screen.eventId] = true
		end
		-- Out of events, the node plays as a fight.
		run.stack = {}
		run:_show({ kind = "Event" })
		expect.equal(run.screen.kind, "Combat")
	end)

	t.test("shop: buy cards and relics, and pay for a removal when it is picked", function()
		local run = newRun()
		run.gold = 1000
		enterNode(run, "Shop")
		local shop = run:getSnapshot().screen
		expect.equal(#shop.cards, 5)
		expect.equal(#shop.relics, 3)
		local onSale = 0
		for _, entry in shop.cards do
			onSale += if entry.onSale then 1 else 0
		end
		expect.equal(onSale, 1, "one card on sale")

		local price = shop.cards[1].price
		expect.truthy(run:buy("Card", 1))
		expect.equal(run.gold, 1000 - price)
		expect.equal(#run.deck, 11)
		local ok, err = run:buy("Card", 1)
		expect.falsy(ok)
		expect.equal(err, "sold out")

		local relicPrice = shop.relics[1].price
		expect.truthy(run:buy("Relic", 1))
		expect.equal(#run.relics, 1)
		local goldBefore = run.gold
		expect.equal(goldBefore, 1000 - price - relicPrice)

		expect.truthy(run:buy("Remove"))
		expect.equal(run.screen.kind, "SelectCard")
		expect.equal(run.gold, goldBefore, "not charged until a card is picked")
		expect.truthy(run:cancel())
		expect.equal(run.screen.kind, "Shop")
		expect.truthy(run:buy("Remove"))
		expect.truthy(run:selectCard(run.deck[1].uid))
		expect.equal(run.gold, goldBefore - 75)
		expect.equal(run.screen.kind, "Shop", "back in the shop")
		ok, err = run:buy("Remove")
		expect.falsy(ok)
		expect.equal(err, "already used here")

		expect.truthy(run:proceed())
		expect.equal(run.screen.kind, "Map")
		run:_show({ kind = "Shop" })
		expect.equal(run.screen.remove.price, 100, "removal costs 25 more next time")
	end)

	t.test("shop: can't buy without the gold", function()
		local run = newRun()
		run.gold = 0
		enterNode(run, "Shop")
		local ok, err = run:buy("Card", 1)
		expect.falsy(ok)
		expect.equal(err, "not enough gold")
		ok, err = run:buy("Remove")
		expect.falsy(ok)
		expect.equal(err, "not enough gold")
	end)

	t.test("rest: heal 30%, upgrade with a path, or remove once per act", function()
		local run = newRun()
		run.hp = 30
		enterNode(run, "Rest")
		expect.truthy(run:chooseOption(1))
		expect.equal(run.hp, 51, "healed 21 (30% of 70)")
		expect.equal(run.screen.kind, "Map")

		run:_show({ kind = "Rest" })
		expect.truthy(run:chooseOption(2))
		local pick = run:getSnapshot().screen
		expect.equal(pick.purpose, "Upgrade")
		expect.truthy(pick.cancellable)
		local uid = pick.candidates[1]
		expect.falsy(run:selectCard(uid, "C"), "bad path")
		expect.truthy(run:selectCard(uid, "B"))
		local _, card = run:findCard(uid)
		expect.equal(card.upgrade, "B")
		expect.equal(run.screen.kind, "Map")

		run:_show({ kind = "Rest" })
		expect.truthy(run:chooseOption(3))
		expect.truthy(run:cancel())
		expect.equal(run.screen.kind, "Rest", "cancel goes back to the camp")
		expect.truthy(run:chooseOption(3))
		expect.truthy(run:selectCard(run.deck[2].uid))
		expect.equal(#run.deck, 9)

		run:_show({ kind = "Rest" })
		local ok, err = run:chooseOption(3)
		expect.falsy(ok)
		expect.equal(err, "option not available")
	end)

	t.test("upgraded cards can't be upgraded again", function()
		local run = newRun()
		local uid = run.deck[1].uid
		expect.truthy(run:upgradeCard(uid, "A"))
		expect.falsy(run:upgradeCard(uid, "B"))
		expect.falsy(table.find(run:cardsFor("Upgrade"), uid))
	end)

	t.test("relics: combat start Block, extra energy, max HP and smaller rewards", function()
		local run = newRun()
		run:gainRelic("IronBuckle")
		run:gainRelic("HeavyCrown")
		run:gainRelic("VigorFlask")
		expect.equal(run.maxHp, 78)
		expect.equal(run.hp, 78)
		run:chooseNode(run:pathChoices()[1])
		expect.equal(run.combat.hero.block, 6, "Iron Buckle")
		expect.equal(run.combat.energy, 4, "Heavy Crown")
		expect.equal(run.combat.hero.maxHp, 78)
		winFight(run)
		expect.equal(#run.screen.cards, 2, "Heavy Crown: 2 card choices")
	end)

	t.test("relics: Blood Oath stops Rest healing", function()
		local run = newRun()
		run:gainRelic("BloodOath")
		run.hp = 30
		enterNode(run, "Rest")
		local options = run:getSnapshot().screen.options
		expect.falsy(options[1].available)
	end)

	t.test("perform rejects malformed actions", function()
		local run = newRun()
		expect.falsy(run:perform(nil))
		expect.falsy(run:perform({ kind = "Teleport" }))
		expect.falsy(run:perform({ kind = "Option", index = "1" }))
		expect.falsy(run:perform({ kind = "Buy", item = "Card", index = 1 }))
		expect.falsy(run:perform({ kind = "Select", uid = 5 }))
	end)

	t.test("a bot can play whole runs from many seeds to a win or a loss", function()
		local endings = { Won = 0, Lost = 0 }
		for seed = 1, 15 do
			local run = newRun(seed)
			local steps = 0
			while not run.over do
				steps += 1
				assert(steps < 3000, `run {seed} stuck on {run.screen.kind}`)
				local ok, err = botStep(run)
				assert(ok ~= false, `run {seed}: {err} on {run.screen.kind}`)
			end
			endings[run.screen.kind] += 1
			expect.truthy(run.stats.rows >= 1, "climbed")
		end
		expect.equal(endings.Won + endings.Lost, 15)
	end)

	t.test("the bot plays whole runs as the Alchemist and the Hexxer too", function()
		for _, hero in { "Alchemist", "Hexxer" } do
			for seed = 1, 8 do
				local run = newRun(seed, hero)
				expect.equal(run.heroId, hero)
				local steps = 0
				while not run.over do
					steps += 1
					assert(steps < 3000, `{hero} run {seed} stuck on {run.screen.kind}`)
					local ok, err = botStep(run)
					assert(ok ~= false, `{hero} run {seed}: {err} on {run.screen.kind}`)
				end
				expect.truthy(run.stats.rows >= 1, "climbed")
			end
		end
	end)
end
