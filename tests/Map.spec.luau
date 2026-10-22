local Content = require("../src/shared/Data/Content")
local MapGenerator = require("../src/server/Run/MapGenerator")
local Rng = require("../src/server/Combat/Rng")
local TestKit = require("./TestKit")
local expect = TestKit.expect

local MAP = Content.Acts[1].map

local function generate(seed: number)
	return MapGenerator.generate(MAP, Rng.new(seed))
end

local function eachNode(map, fn)
	for row = 1, map.rowCount do
		for _, id in map.rows[row] do
			fn(map.nodes[id])
		end
	end
end

return function(t)
	t.test("the same seed builds the same map", function()
		local a, b = generate(42), generate(42)
		eachNode(a, function(node)
			local other = b.nodes[node.id]
			expect.truthy(other, node.id)
			expect.equal(other.type, node.type, node.id)
			expect.equal(table.concat(other.next, ","), table.concat(node.next, ","), node.id)
		end)
		expect.equal(#a.startIds, #b.startIds)
	end)

	t.test("fixed rows, one boss, and 2 or 3 starts", function()
		for seed = 1, 50 do
			local map = generate(seed)
			expect.equal(#map.rows[15], 1, "boss row")
			expect.equal(map.nodes[map.bossId].type, "Boss")
			expect.truthy(#map.startIds >= 2 and #map.startIds <= 3, `starts {#map.startIds}`)
			for row, nodeType in MAP.fixed do
				for _, id in map.rows[row] do
					expect.equal(map.nodes[id].type, nodeType, id)
				end
			end
		end
	end)

	t.test("every node is reachable and leads somewhere, without crossings", function()
		for seed = 1, 50 do
			local map = generate(seed)
			local reachable = {}
			for _, id in map.startIds do
				reachable[id] = true
			end
			eachNode(map, function(node)
				if node.row < 15 then
					expect.truthy(#node.next >= 1 and #node.next <= 3, `{node.id} exits`)
				end
				if node.row > 1 then
					expect.truthy(#node.prev >= 1, `{node.id} has a parent`)
				end
				expect.truthy(reachable[node.id], `{node.id} reachable (seed {seed})`)
				for _, nextId in node.next do
					reachable[nextId] = true
					local nextNode = map.nodes[nextId]
					expect.equal(nextNode.row, node.row + 1, "next row")
					if nextNode.type ~= "Boss" then
						expect.truthy(math.abs(nextNode.col - node.col) <= 1, "one column step")
					end
				end
			end)
			-- Two edges between the same rows cross if they swap columns.
			for row = 1, 13 do
				for _, aId in map.rows[row] do
					for _, bId in map.rows[row] do
						local a, b = map.nodes[aId], map.nodes[bId]
						if a.col < b.col then
							for _, an in a.next do
								for _, bn in b.next do
									expect.truthy(map.nodes[an].col <= map.nodes[bn].col, `cross {aId} {bId}`)
								end
							end
						end
					end
				end
			end
		end
	end)

	t.test("type rules: min rows and no repeats of Elite, Rest or Shop on a path", function()
		for seed = 1, 100 do
			local map = generate(seed)
			eachNode(map, function(node)
				local minRow = MAP.minRow[node.type]
				if minRow then
					expect.truthy(node.row >= minRow, `{node.type} on row {node.row}`)
				end
				if MAP.noRepeat[node.type] then
					for _, nextId in node.next do
						expect.truthy(map.nodes[nextId].type ~= node.type, `{node.type} twice at {node.id}`)
					end
				end
			end)
		end
	end)

	t.test("most steps offer 2 or 3 path cards", function()
		local multi, total = 0, 0
		for seed = 1, 100 do
			eachNode(generate(seed), function(node)
				if node.row < 14 then
					total += 1
					if #node.next >= 2 then
						multi += 1
					end
				end
			end)
		end
		expect.truthy(multi / total >= 0.7, `share with a choice {multi / total}`)
	end)

	t.test("all node types show up over many maps", function()
		local seen = {}
		for seed = 1, 30 do
			eachNode(generate(seed), function(node)
				seen[node.type] = true
			end)
		end
		for _, nodeType in { "Combat", "Elite", "Event", "Rest", "Shop", "Treasure", "Boss" } do
			expect.truthy(seen[nodeType], nodeType)
		end
	end)
end
