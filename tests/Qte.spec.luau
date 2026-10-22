local Content = require("../src/shared/Data/Content")
local QteJudge = require("../src/server/Combat/QteJudge")
local Rng = require("../src/server/Combat/Rng")
local TestKit = require("./TestKit")
local expect = TestKit.expect

local Qte = Content.Qte

local function challenge(kind: string, difficulty: number?, windowMult: number?)
	return QteJudge.createChallenge(Qte, {
		qteId = "q1",
		kind = kind,
		difficulty = difficulty or 1,
		windowMult = windowMult or 1,
		source = "Card",
	}, Rng.new(5))
end

local function grade(c, inputs, elapsed: number?, options: any?)
	return (QteJudge.grade(Qte, c, inputs, elapsed or c.deadline, options))
end

return function(t)
	t.test("challenges carry the QteStart payload", function()
		local c = challenge("Timing", 2)
		expect.equal(c.public.qteId, "q1")
		expect.equal(c.public.kind, "Timing")
		expect.equal(c.public.difficulty, 2)
		expect.truthy(c.public.params.hitTime, "params")
		expect.truthy(c.public.deadline > c.params.hitTime, "deadline after the hit")
	end)

	t.test("Timing windows follow difficulty: Perfect 60 to 25 ms, Good 200 to 90 ms", function()
		local easy, hard = challenge("Timing", 1), challenge("Timing", 5)
		expect.equal(math.floor(easy.params.perfectWindow * 1000 + 0.5), 60)
		expect.equal(math.floor(easy.params.goodWindow * 1000 + 0.5), 200)
		expect.equal(math.floor(hard.params.perfectWindow * 1000 + 0.5), 25)
		expect.equal(math.floor(hard.params.goodWindow * 1000 + 0.5), 90)
		local wide = challenge("Timing", 1, 1.5)
		expect.equal(math.floor(wide.params.perfectWindow * 1000 + 0.5), 90)
	end)

	t.test("Timing grades by distance from the hit time", function()
		local c = challenge("Timing", 1)
		local hit = c.params.hitTime
		expect.equal(grade(c, { hit + 0.02 }), "Perfect")
		expect.equal(grade(c, { hit - 0.15 }), "Good")
		expect.equal(grade(c, { hit + 0.3 }), "Miss")
		expect.equal(grade(c, {}), "Miss")
		expect.equal(grade(c, { "soon" }), "Miss")
	end)

	t.test("impossible, late and after-the-reply inputs are Misses", function()
		local c = challenge("Timing", 1)
		local hit = c.params.hitTime
		-- Tap claimed after the server already had the reply.
		expect.equal(grade(c, { hit }, hit - 0.2), "Miss")
		-- Reply long after the deadline.
		expect.equal(grade(c, { hit }, c.deadline + 5), "Miss")
		-- Faster than 80 ms after the start.
		local m = challenge("Mash", 1)
		local taps = { 0.05 }
		for i = 1, 30 do
			taps[#taps + 1] = 0.05 + i * 0.045
		end
		expect.equal(grade(m, taps), "Miss")
	end)

	t.test("Sequence needs every symbol in order, fast for Perfect", function()
		local c = challenge("Sequence", 1)
		local symbols = c.params.symbols
		expect.equal(#symbols, 3)
		expect.equal(#challenge("Sequence", 5).params.symbols, 5)
		local function inputs(step)
			local list = {}
			for i, s in symbols do
				list[i] = { s, 0.1 + i * step }
			end
			return list
		end
		expect.equal(grade(c, inputs(0.2)), "Perfect")
		expect.equal(grade(c, inputs(0.38)), "Good")
		expect.equal(grade(c, inputs(0.6)), "Miss")
		local wrong = inputs(0.2)
		wrong[2] = { symbols[2] == "Up" and "Down" or "Up", wrong[2][2] }
		expect.equal(grade(c, wrong), "Miss")
	end)

	t.test("Mash counts human-speed taps against the targets", function()
		local c = challenge("Mash", 1)
		expect.equal(c.params.goodTaps, 8)
		expect.equal(c.params.perfectTaps, 13)
		local function taps(n, gap)
			local list = {}
			for i = 1, n do
				list[i] = 0.1 + (i - 1) * gap
			end
			return list
		end
		expect.equal(grade(c, taps(14, 0.09)), "Perfect")
		expect.equal(grade(c, taps(9, 0.1)), "Good")
		expect.equal(grade(c, taps(5, 0.1)), "Miss")
		-- 40 taps 10 ms apart: only the ones 35 ms apart count.
		expect.equal(grade(c, taps(40, 0.01)), "Good")
	end)

	t.test("Hold grades where the bar was released", function()
		local c = challenge("Hold", 1)
		local p = c.params
		local function releaseAt(fill)
			return { 0.2, 0.2 + fill * p.fillTime }
		end
		expect.equal(grade(c, releaseAt(p.zoneCenter)), "Perfect")
		expect.equal(grade(c, releaseAt(p.zoneCenter + p.zoneWidth * 0.4)), "Good")
		expect.equal(grade(c, releaseAt(p.zoneCenter + p.zoneWidth)), "Miss")
		expect.equal(grade(c, { 0.5, 0.4 }), "Miss")
	end)

	t.test("Trace grades how closely the swipe followed the path", function()
		local c = challenge("Trace", 1)
		local path = c.params.path
		local function swipe(offset)
			local list = {}
			for i, point in path do
				list[i] = { point[1], point[2] + offset, 0.2 + i * 0.2 }
			end
			return list
		end
		expect.equal(grade(c, swipe(0.01)), "Perfect")
		expect.equal(grade(c, swipe(c.params.radius * 0.8)), "Good")
		expect.equal(grade(c, swipe(c.params.radius * 2)), "Miss")
		-- Path visited backwards misses.
		local backwards = swipe(0)
		local reversed = {}
		for i = #backwards, 1, -1 do
			local p = backwards[i]
			table.insert(reversed, { p[1], p[2], 0.2 + #reversed * 0.2 })
		end
		expect.equal(grade(c, reversed), "Miss")
	end)

	t.test("accessibility assist always grades Good", function()
		local c = challenge("Timing", 5)
		expect.equal(grade(c, {}, nil, { alwaysGood = true }), "Good")
		expect.equal(grade(c, { c.params.hitTime }, nil, { alwaysGood = true }), "Good")
	end)

	t.test("every QTE kind can be built at every difficulty", function()
		for kind in Qte.Kinds do
			for d = 1, 5 do
				local c = challenge(kind, d)
				expect.truthy(c.deadline > 0, `{kind} {d}`)
			end
		end
	end)
end
