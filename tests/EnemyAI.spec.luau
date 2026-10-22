local EnemyAI = require("../src/server/Combat/EnemyAI")
local Rng = require("../src/server/Combat/Rng")
local TestKit = require("./TestKit")
local expect = TestKit.expect

local function unit(hp, maxHp)
	return { hp = hp, maxHp = maxHp, ai = EnemyAI.newState() }
end

local function moves(...)
	local list = {}
	for _, id in { ... } do
		list[id] = { id = id }
	end
	return list
end

return function(t)
	t.test("Cycle loops from loopFrom", function()
		local def = { moves = moves("A", "B", "C"), pattern = { kind = "Cycle", order = { "A", "B", "C" }, loopFrom = 2 } }
		local u = unit(10, 10)
		local seq = {}
		for i = 1, 6 do
			seq[i] = EnemyAI.choose(def, u, Rng.new(1), { turn = i })
		end
		expect.equal(table.concat(seq), "ABCBCB")
	end)

	t.test("Weighted never exceeds maxRepeat", function()
		local def = {
			moves = moves("A", "B"),
			pattern = { kind = "Weighted", moves = { { "A", 99 }, { "B", 1 } }, maxRepeat = 2 },
		}
		local u = unit(10, 10)
		local rng = Rng.new(3)
		local run = 0
		for i = 1, 200 do
			local move = EnemyAI.choose(def, u, rng, { turn = i })
			run = move == "A" and run + 1 or 0
			expect.truthy(run <= 2, "repeat cap")
		end
	end)

	t.test("Conditional fires a once rule a single time, then falls through", function()
		local def = {
			moves = moves("Enrage", "Hit"),
			pattern = {
				kind = "Conditional",
				rules = { { when = { kind = "HpBelow", ratio = 0.5 }, move = "Enrage", once = true } },
				fallback = { kind = "Cycle", order = { "Hit" } },
			},
		}
		local u = unit(10, 10)
		local rng = Rng.new(1)
		expect.equal(EnemyAI.choose(def, u, rng, { turn = 1 }), "Hit")
		u.hp = 4
		expect.equal(EnemyAI.choose(def, u, rng, { turn = 2 }), "Enrage")
		expect.equal(EnemyAI.choose(def, u, rng, { turn = 3 }), "Hit")
	end)
end
