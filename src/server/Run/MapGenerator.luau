--[[
	Seeded act maps. The design doc's recipe: a grid of rows and columns,
	several paths drawn upward from row 1 (each step moves -1, 0 or +1 column
	and never crosses another path's edge), merged where they meet, with the
	boss alone on the top row. A widening pass then gives one-exit nodes a
	second exit (chance mapDef.branchChance), so about 4 in 5 steps offer 2 or
	3 path cards.

	Node types: fixed rows first (Combat, Treasure, Rest, Boss), then weighted
	picks with the act's rules: a type's minimum row, no Elite, Rest or Shop
	twice in a row on one path, and siblings (nodes reachable from the same
	node) prefer different types so a choice is a real choice.

	Pure Luau and deterministic: the same act data and seed give the same map.

	MapGenerator.generate(mapDef, rng) -> map
		map.nodes[id]  { id, row, col, type, next = { ids }, prev = { ids } }
		map.rows[r]    node ids on row r, left to right
		map.startIds   row 1 node ids
		map.bossId
]]

local MapGenerator = {}

local function nodeId(row: number, col: number): string
	return `r{row}c{col}`
end

local function sortedKeys(set): { any }
	local list = {}
	for key in set do
		table.insert(list, key)
	end
	table.sort(list)
	return list
end

-- Edges between row r and r + 1, as edges[r][fromCol][toCol] = true.
local function crosses(edges, row: number, from: number, to: number): boolean
	local rowEdges = edges[row]
	if not rowEdges then
		return false
	end
	if to == from + 1 then
		return rowEdges[from + 1] ~= nil and rowEdges[from + 1][from] == true
	elseif to == from - 1 then
		return rowEdges[from - 1] ~= nil and rowEdges[from - 1][from] == true
	end
	return false
end

local function addEdge(edges, row: number, from: number, to: number)
	edges[row] = edges[row] or {}
	edges[row][from] = edges[row][from] or {}
	edges[row][from][to] = true
end

local function pickWeighted(rng, weights: { [string]: number }, allowed: { [string]: boolean }): string?
	local total = 0
	local names = sortedKeys(allowed)
	for _, name in names do
		total += weights[name] or 0
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:float() * total
	for _, name in names do
		roll -= weights[name] or 0
		if roll < 0 then
			return name
		end
	end
	return names[#names]
end

function MapGenerator.generate(mapDef, rng)
	local rows, columns = mapDef.rows, mapDef.columns
	local pathTop = rows - 1 -- the last row paths reach; the boss sits above it

	-- 1. Start columns: a few distinct ones, so the first choice is 2 or 3 cards.
	local allColumns = {}
	for col = 1, columns do
		allColumns[col] = col
	end
	rng:shuffle(allColumns)
	local startCount = rng:int(mapDef.starts[1], mapDef.starts[2])
	local starts = {}
	for i = 1, startCount do
		starts[i] = allColumns[i]
	end

	-- 2. Draw the paths upward.
	local edges = {}
	local occupied = {} -- occupied[row][col] = true
	for row = 1, pathTop do
		occupied[row] = {}
	end
	for path = 1, mapDef.paths do
		local col = if path <= startCount then starts[path] else starts[rng:int(1, startCount)]
		occupied[1][col] = true
		for row = 1, pathTop - 1 do
			local options = {}
			for delta = -1, 1 do
				local to = col + delta
				if to >= 1 and to <= columns and not crosses(edges, row, col, to) then
					table.insert(options, to)
				end
			end
			local to = options[rng:int(1, #options)]
			addEdge(edges, row, col, to)
			occupied[row + 1][to] = true
			col = to
		end
	end

	-- 3. Widen: give one-exit nodes a second exit. Prefer an existing
	-- neighbour; otherwise branch into an empty cell and run that branch
	-- straight up until it can merge into a neighbouring node.
	for row = 1, pathTop - 1 do
		for _, from in sortedKeys(occupied[row]) do
			local exits = sortedKeys(edges[row][from])
			if #exits ~= 1 or rng:float() >= (mapDef.branchChance or 1) then
				continue
			end
			local existing, empty = {}, {}
			for to = from - 1, from + 1 do
				if to >= 1 and to <= columns and to ~= exits[1] and not crosses(edges, row, from, to) then
					table.insert(if occupied[row + 1][to] then existing else empty, to)
				end
			end
			if #existing > 0 then
				addEdge(edges, row, from, existing[rng:int(1, #existing)])
			elseif #empty > 0 then
				local col = empty[rng:int(1, #empty)]
				addEdge(edges, row, from, col)
				occupied[row + 1][col] = true
				for r = row + 1, pathTop - 1 do
					local merge = {}
					for to = col - 1, col + 1 do
						if occupied[r + 1][to] and not crosses(edges, r, col, to) then
							table.insert(merge, to)
						end
					end
					if #merge > 0 then
						addEdge(edges, r, col, merge[rng:int(1, #merge)])
						break
					end
					addEdge(edges, r, col, col)
					occupied[r + 1][col] = true
				end
			end
		end
	end

	-- 4. Build nodes.
	local map = { rowCount = rows, columns = columns, nodes = {}, rows = {}, startIds = {}, bossId = nil }
	for row = 1, pathTop do
		map.rows[row] = {}
		for _, col in sortedKeys(occupied[row]) do
			local id = nodeId(row, col)
			map.nodes[id] = { id = id, row = row, col = col, type = nil, next = {}, prev = {} }
			table.insert(map.rows[row], id)
		end
	end
	local bossCol = math.ceil(columns / 2)
	local bossId = nodeId(rows, bossCol)
	map.nodes[bossId] = { id = bossId, row = rows, col = bossCol, type = "Boss", next = {}, prev = {} }
	map.rows[rows] = { bossId }
	map.bossId = bossId

	for row = 1, pathTop - 1 do
		for _, from in sortedKeys(edges[row]) do
			for _, to in sortedKeys(edges[row][from]) do
				local a, b = map.nodes[nodeId(row, from)], map.nodes[nodeId(row + 1, to)]
				table.insert(a.next, b.id)
				table.insert(b.prev, a.id)
			end
		end
	end
	for _, id in map.rows[pathTop] do
		table.insert(map.nodes[id].next, bossId)
		table.insert(map.nodes[bossId].prev, id)
	end
	map.startIds = table.clone(map.rows[1])

	-- 5. Node types, bottom to top so parents are known.
	local fixed = mapDef.fixed or {}
	local noRepeat = mapDef.noRepeat or {}
	local minRow = mapDef.minRow or {}
	for row = 1, pathTop do
		for _, id in map.rows[row] do
			local node = map.nodes[id]
			if fixed[row] then
				node.type = fixed[row]
				continue
			end
			local allowed = {}
			for typeName in mapDef.weights do
				local ok = row >= (minRow[typeName] or 1)
				if ok and noRepeat[typeName] then
					if fixed[row + 1] == typeName then
						ok = false
					end
					for _, parentId in node.prev do
						if map.nodes[parentId].type == typeName then
							ok = false
						end
					end
				end
				if ok then
					allowed[typeName] = true
				end
			end
			-- Prefer a type no sibling has, so each choice offers variety.
			local varied = table.clone(allowed)
			for _, parentId in node.prev do
				for _, siblingId in map.nodes[parentId].next do
					local sibling = map.nodes[siblingId]
					if sibling.type then
						varied[sibling.type] = nil
					end
				end
			end
			node.type = pickWeighted(rng, mapDef.weights, varied)
				or pickWeighted(rng, mapDef.weights, allowed)
				or "Combat"
		end
	end

	return map
end

-- The nodes the player can pick next: row 1 at the start of an act, else the
-- current node's exits.
function MapGenerator.choices(map, currentId: string?): { string }
	if currentId == nil then
		return map.startIds
	end
	return map.nodes[currentId].next
end

return MapGenerator
