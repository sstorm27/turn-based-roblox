--[[
	Deterministic xorshift32 RNG. Pure Luau so the combat engine can run outside
	Roblox (tests, replays) and give the same rolls from the same seed.
]]

local Rng = {}
Rng.__index = Rng

function Rng.new(seed: number)
	local self = setmetatable({}, Rng)
	self.state = bit32.band(math.floor(seed), 0xFFFFFFFF)
	if self.state == 0 then
		self.state = 0x9E3779B9
	end
	-- Warm up so nearby seeds diverge quickly.
	for _ = 1, 8 do
		self:nextU32()
	end
	return self
end

function Rng:nextU32(): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

-- Float in [0, 1).
function Rng:float(): number
	return self:nextU32() / 4294967296
end

-- Integer in [min, max], inclusive.
function Rng:int(min: number, max: number): number
	return min + math.floor(self:float() * (max - min + 1))
end

function Rng:range(min: number, max: number): number
	return min + self:float() * (max - min)
end

function Rng:shuffle(list: { any })
	for i = #list, 2, -1 do
		local j = self:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- A child stream, so one system's rolls never shift another's.
function Rng:fork(salt: number)
	return Rng.new(bit32.bxor(self:nextU32(), salt))
end

return Rng
