--[[
	Quick-time event tuning, shared so the client can draw the same QTE the
	server grades. The server owns every roll and every grade (see
	ServerScriptService.Server.Combat.QteJudge); nothing here is trusted from
	the client.

	Kinds (design doc, "Quick-time events")
		Timing    tap when a sweeping marker is in the gold band
		Sequence  tap 3 to 5 arrows in the shown order
		Mash      tap as often as possible in 1.5 s against a target count
		Hold      hold, release inside a marked zone on a filling bar
		Trace     swipe along a short shown path

	Difficulty is 1 to 5. A window multiplier (Focus, Dazed, multi-hit,
	accessibility) widens or narrows every window on top of it.
]]

local Qte = {}

Qte.Grades = { "Miss", "Good", "Perfect" }
Qte.GradeRank = { Miss = 0, Good = 1, Perfect = 2 }

-- A first input sooner than this after the QTE starts is impossible: Miss.
Qte.MinReactionTime = 0.08
-- Network allowance added to each QTE's deadline on the server.
Qte.LatencyAllowance = 0.15
-- Results arriving later than deadline + this are thrown away and graded Miss.
Qte.ResultGrace = 0.5

Qte.MinWindowMult = 0.4
Qte.MultiHitWindowMult = 0.8
Qte.WideWindowMult = 1.5 -- accessibility: wider windows

-- Damage multipliers for defensive QTEs when a move's defenseQte leaves them out.
Qte.DefenseDefaults = { good = 0.5, perfect = 0 }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- 0 at difficulty 1, 1 at difficulty 5.
local function d01(difficulty: number): number
	return (math.clamp(difficulty, 1, 5) - 1) / 4
end
Qte.difficultyT = d01

Qte.Kinds = {
	Timing = {
		-- The marker reaches the centre of the gold band at hitTime, picked in
		-- this range.
		minHitTime = 0.6,
		maxHitTime = 1.1,
		tail = 0.4, -- time after hitTime before the QTE closes
		perfectWindow = function(d)
			return lerp(0.060, 0.025, d01(d))
		end,
		goodWindow = function(d)
			return lerp(0.200, 0.090, d01(d))
		end,
	},
	Sequence = {
		symbols = { "Up", "Down", "Left", "Right" },
		length = function(d)
			return 3 + math.floor((math.clamp(d, 1, 5) - 1) / 2)
		end,
		timePerSymbol = 0.45,
		perfectFraction = 0.6, -- finish inside 60% of the limit for Perfect
	},
	Mash = {
		duration = 1.5,
		goodTaps = function(d)
			return 7 + math.clamp(d, 1, 5)
		end,
		perfectTaps = function(d)
			return 11 + 2 * math.clamp(d, 1, 5)
		end,
		minTapGap = 0.035, -- taps closer together than this are not human
	},
	Hold = {
		fillTime = 1.4, -- seconds to fill the bar from empty to full
		zoneWidth = function(d)
			return lerp(0.24, 0.10, d01(d))
		end,
		minZoneCenter = 0.55,
		maxZoneCenter = 0.85,
		perfectFraction = 0.35, -- inner part of the zone that counts as Perfect
		tail = 0.5,
	},
	Trace = {
		duration = 1.8,
		points = function(d)
			return 3 + math.min(math.clamp(d, 1, 5), 3)
		end,
		radius = function(d)
			return lerp(0.12, 0.06, d01(d))
		end,
		perfectRadiusFraction = 0.5,
		maxSamples = 240,
	},
}

return Qte
