--[[
	A tiny test kit so the engine tests run with the plain `luau` CLI, no
	Roblox needed. Specs return a function(t) and call t.test(name, fn).
]]

local TestKit = {}

local function show(v)
	if type(v) == "string" then
		return `"{v}"`
	end
	return tostring(v)
end

local function fail(message: string, level: number?)
	error(message, (level or 1) + 1)
end

TestKit.expect = {
	equal = function(actual, expected, label: string?)
		if actual ~= expected then
			fail(`{label or "value"}: expected {show(expected)}, got {show(actual)}`, 2)
		end
	end,
	truthy = function(value, label: string?)
		if not value then
			fail(`{label or "value"}: expected truthy, got {show(value)}`, 2)
		end
	end,
	falsy = function(value, label: string?)
		if value then
			fail(`{label or "value"}: expected falsy, got {show(value)}`, 2)
		end
	end,
}

function TestKit.run(specs: { [string]: any }): boolean
	local passed, failed = 0, 0
	local names = {}
	for name in specs do
		table.insert(names, name)
	end
	table.sort(names)
	for _, specName in names do
		local tests = {}
		specs[specName]({
			test = function(name, fn)
				table.insert(tests, { name = name, fn = fn })
			end,
		})
		for _, case in tests do
			local ok, err = pcall(case.fn)
			if ok then
				passed += 1
			else
				failed += 1
				print(`FAIL {specName} > {case.name}\n     {err}`)
			end
		end
	end
	print(`{passed} passed, {failed} failed`)
	return failed == 0
end

return TestKit
