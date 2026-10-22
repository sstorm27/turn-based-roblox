--[[
	Builds QTE challenges and grades the client's raw inputs. Server only: the
	client draws the challenge and reports what the player did; the grade is
	decided here.

	createChallenge(qteData, request, rng) -> challenge
		challenge.public is what QteStart sends:
			{ qteId, kind, difficulty, params, deadline }
		deadline is seconds after the QTE starts.

	grade(qteData, challenge, inputs, elapsed, options) -> grade, reason
		inputs   raw input times measured by the client from QTE start
		elapsed  server seconds between sending QteStart and receiving the result
		options  { alwaysGood = bool }  (accessibility assist: always Good, never Perfect)

	Input shapes per kind
		Timing    { tapTime }
		Sequence  { { symbol, t }, ... }
		Mash      { t1, t2, ... }
		Hold      { pressTime, releaseTime }
		Trace     { { x, y, t }, ... }  points in 0..1 screen space of the QTE box

	Anything malformed, late, or faster than a human can react grades Miss.
	Because inputs are client timestamps, a cheater can still fake a clean
	result; the checks here stop instant or after-the-fact replies, and
	server-side plausibility is the best a client-drawn QTE can do.
]]

local QteJudge = {}

local MAX_LIST = 64
local CLOCK_TOLERANCE = 0.05

local function isNumber(v): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Builders ---------------------------------------------------------------------

local builders = {}

function builders.Timing(spec, d, mult, rng)
	local hitTime = rng:range(spec.minHitTime, spec.maxHitTime)
	return {
		hitTime = hitTime,
		perfectWindow = spec.perfectWindow(d) * mult,
		goodWindow = spec.goodWindow(d) * mult,
	}, hitTime + spec.tail
end

function builders.Sequence(spec, d, mult, rng)
	local symbols = {}
	for i = 1, spec.length(d) do
		symbols[i] = spec.symbols[rng:int(1, #spec.symbols)]
	end
	local timeLimit = #symbols * spec.timePerSymbol * mult
	return {
		symbols = symbols,
		timeLimit = timeLimit,
		perfectTime = timeLimit * spec.perfectFraction,
	}, timeLimit
end

function builders.Mash(spec, d, mult, rng)
	return {
		duration = spec.duration,
		goodTaps = math.max(1, math.ceil(spec.goodTaps(d) / mult)),
		perfectTaps = math.max(2, math.ceil(spec.perfectTaps(d) / mult)),
	}, spec.duration
end

function builders.Hold(spec, d, mult, rng)
	local width = math.min(0.5, spec.zoneWidth(d) * mult)
	local center = rng:range(spec.minZoneCenter, spec.maxZoneCenter)
	center = math.clamp(center, width / 2, 1 - width / 2)
	return {
		fillTime = spec.fillTime,
		zoneCenter = center,
		zoneWidth = width,
		perfectWidth = width * spec.perfectFraction,
	}, spec.fillTime + spec.tail
end

function builders.Trace(spec, d, mult, rng)
	local count = spec.points(d)
	local path = {}
	-- A loose left-to-right zigzag that always stays inside the box.
	for i = 1, count do
		local x = 0.1 + 0.8 * (i - 1) / (count - 1)
		local y = rng:range(0.2, 0.8)
		path[i] = { x, y }
	end
	local radius = spec.radius(d) * mult
	return {
		path = path,
		duration = spec.duration,
		radius = radius,
		perfectRadius = radius * spec.perfectRadiusFraction,
	}, spec.duration
end

function QteJudge.createChallenge(qteData, request, rng)
	local spec = qteData.Kinds[request.kind]
	assert(spec, `unknown QTE kind {request.kind}`)
	local difficulty = math.clamp(request.difficulty or 1, 1, 5)
	local mult = request.windowMult or 1
	local params, deadline = builders[request.kind](spec, difficulty, mult, rng)
	return {
		qteId = request.qteId,
		kind = request.kind,
		difficulty = difficulty,
		params = params,
		deadline = deadline,
		public = {
			qteId = request.qteId,
			kind = request.kind,
			difficulty = difficulty,
			params = params,
			deadline = deadline,
			source = request.source,
		},
	}
end

-- Graders ----------------------------------------------------------------------

local graders = {}

function graders.Timing(qteData, params, inputs)
	local tap = inputs[1]
	if not isNumber(tap) then
		return "Miss", "no tap"
	end
	local err = math.abs(tap - params.hitTime)
	if err <= params.perfectWindow then
		return "Perfect"
	elseif err <= params.goodWindow then
		return "Good"
	end
	return "Miss", "outside window"
end

function graders.Sequence(qteData, params, inputs)
	local symbols = params.symbols
	if #inputs < #symbols then
		return "Miss", "incomplete"
	end
	local last = 0
	for i, symbol in symbols do
		local input = inputs[i]
		if type(input) ~= "table" or input[1] ~= symbol or not isNumber(input[2]) then
			return "Miss", "wrong symbol"
		end
		if input[2] < last then
			return "Miss", "out of order"
		end
		last = input[2]
	end
	if last <= params.perfectTime then
		return "Perfect"
	elseif last <= params.timeLimit then
		return "Good"
	end
	return "Miss", "too slow"
end

function graders.Mash(qteData, params, inputs)
	local minGap = qteData.Kinds.Mash.minTapGap
	local count = 0
	local last = -math.huge
	for _, t in inputs do
		if not isNumber(t) then
			return "Miss", "bad input"
		end
		if t < last then
			return "Miss", "out of order"
		end
		if t <= params.duration and t - last >= minGap then
			count += 1
			last = t
		end
	end
	if count >= params.perfectTaps then
		return "Perfect"
	elseif count >= params.goodTaps then
		return "Good"
	end
	return "Miss", "not enough taps"
end

function graders.Hold(qteData, params, inputs)
	local press, release = inputs[1], inputs[2]
	if not isNumber(press) or not isNumber(release) or release <= press then
		return "Miss", "bad hold"
	end
	local fill = (release - press) / params.fillTime
	local off = math.abs(fill - params.zoneCenter)
	if off <= params.perfectWidth / 2 then
		return "Perfect"
	elseif off <= params.zoneWidth / 2 then
		return "Good"
	end
	return "Miss", "outside zone"
end

function graders.Trace(qteData, params, inputs)
	if #inputs > qteData.Kinds.Trace.maxSamples then
		return "Miss", "too many samples"
	end
	local cursor = 1
	local worst = 0
	for _, point in params.path do
		local best, bestIndex = math.huge, nil
		for j = cursor, #inputs do
			local sample = inputs[j]
			if type(sample) ~= "table" or not isNumber(sample[1]) or not isNumber(sample[2]) then
				return "Miss", "bad sample"
			end
			local dx, dy = sample[1] - point[1], sample[2] - point[2]
			local dist = math.sqrt(dx * dx + dy * dy)
			if dist < best then
				best, bestIndex = dist, j
			end
		end
		if not bestIndex or best > params.radius then
			return "Miss", "left the path"
		end
		cursor = bestIndex
		worst = math.max(worst, best)
	end
	if worst <= params.perfectRadius then
		return "Perfect"
	end
	return "Good"
end

-- Times every input claims, for the reaction and clock checks.
local function inputTimes(kind: string, inputs): { number }
	local times = {}
	for _, input in inputs do
		local t
		if kind == "Sequence" then
			t = type(input) == "table" and input[2]
		elseif kind == "Trace" then
			t = type(input) == "table" and input[3]
		else
			t = input
		end
		if isNumber(t) then
			table.insert(times, t)
		end
	end
	return times
end

function QteJudge.grade(qteData, challenge, inputs, elapsed: number, options)
	options = options or {}
	if options.alwaysGood then
		-- Accessibility assist: every QTE grades Good, with or without input.
		return "Good", "assist"
	end
	if type(inputs) ~= "table" then
		return "Miss", "no inputs"
	end
	local limit = challenge.kind == "Trace" and qteData.Kinds.Trace.maxSamples or MAX_LIST
	if #inputs > limit then
		return "Miss", "too many inputs"
	end
	if elapsed > challenge.deadline + qteData.LatencyAllowance + qteData.ResultGrace then
		return "Miss", "late"
	end

	local times = inputTimes(challenge.kind, inputs)
	if #times == 0 then
		return "Miss", "no inputs"
	end
	local first, lastTime = math.huge, -math.huge
	for _, t in times do
		first = math.min(first, t)
		lastTime = math.max(lastTime, t)
	end
	if first < qteData.MinReactionTime then
		return "Miss", "impossible reaction"
	end
	-- The client cannot claim an input after the server already had the reply.
	if lastTime > elapsed + CLOCK_TOLERANCE then
		return "Miss", "input after reply"
	end
	if lastTime > challenge.deadline + qteData.LatencyAllowance then
		return "Miss", "after deadline"
	end

	return graders[challenge.kind](qteData, challenge.params, inputs)
end

return QteJudge
