--[[
	The map screen (design doc, "Map presentation"): an act progress bar with
	its fixed stops, and 2 or 3 path cards for the nodes you can reach next,
	each with an icon, a type name, one line of text and what it leads to.
	The full branching graph sits behind "View full map", for players who
	want to plan ahead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Data.Content)
local Remotes = require(Shared.Net.Remotes)

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local C = Theme.colors
local S = Theme.sizes
local make = Kit.make

local MapScreen = {}
MapScreen.__index = MapScreen

local function nodeName(nodeType: string): string
	local info = Content.RunRules.nodeTypes[nodeType]
	return info and info.name or nodeType
end

local function nodeHint(nodeType: string): string
	local info = Content.RunRules.nodeTypes[nodeType]
	return info and info.hint or ""
end

local function nodeTile(parent: Instance, nodeType: string, size: number, props: { [string]: any }?)
	local p = props or {}
	p.Size = UDim2.fromOffset(size, size)
	p.BackgroundColor3 = Theme.nodeColors[nodeType] or C.panelLight
	p.Parent = parent
	local tile = make("Frame", p)
	Kit.outline(C.ink, 2).Parent = tile
	Kit.icon(nodeType, math.floor(size * 0.65), {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = tile.ZIndex + 1,
		Parent = tile,
	})
	return tile
end

function MapScreen.new(parent: Instance, modalLayer: Instance)
	local self = setmetatable({}, MapScreen)
	self.modalLayer = modalLayer
	self.run = nil

	local root = make("Frame", {
		Name = "Map",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.backdrop,
		Visible = false,
		Parent = parent,
	})
	self.root = root

	-- Act progress ------------------------------------------------------------------
	local progress = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S.topBar + 20),
		Size = UDim2.new(1, -2 * S.gutter, 0, 84),
		BackgroundTransparency = 1,
		Parent = root,
	})
	make("UISizeConstraint", { MaxSize = Vector2.new(860, 84), Parent = progress })
	self.actLabel = Kit.title({
		Size = UDim2.new(0.7, 0, 0, 18),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = progress,
	})
	self.floorLabel = Kit.title({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.3, 0, 0, 18),
		TextSize = 12,
		TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = progress,
	})
	self.track = make("Frame", {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Parent = progress,
	})

	-- Path cards ----------------------------------------------------------------------
	Kit.title({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S.topBar + 124),
		Size = UDim2.new(1, 0, 0, 24),
		Text = "CHOOSE YOUR PATH",
		TextSize = 16,
		Parent = root,
	})
	self.cards = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S.topBar + 166),
		Size = UDim2.new(1, -2 * S.gutter, 0, 270),
		BackgroundTransparency = 1,
		Parent = root,
	}, { Kit.hlist(22, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top) })

	Kit.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(220, 48),
		Text = "View full map",
		Parent = root,
	}, function()
		self:openFullMap()
	end, { textSize = 12 })
	return self
end

function MapScreen:setVisible(visible: boolean)
	self.root.Visible = visible
end

function MapScreen:_renderTrack(progress)
	local track = self.track
	Kit.clear(track)
	local rows = progress.rows
	local stops = {}
	for _, stop in progress.stops do
		stops[stop.row] = stop.type
	end
	local gap = 4
	for row = 1, rows do
		local done = row <= progress.row
		local current = row == progress.row
		local seg = make("Frame", {
			Position = UDim2.new((row - 1) / rows, gap / 2, 0, 0),
			Size = UDim2.new(1 / rows, -gap, 1, 0),
			BackgroundColor3 = if current then C.goldLight elseif done then C.gold else C.panelLight,
			Parent = track,
		})
		Kit.outline(C.ink, 2).Parent = seg
		local stopType = stops[row]
		if stopType then
			local tile = nodeTile(track, stopType, 26, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new((row - 0.5) / rows, 0, 0, -6),
				Active = true,
			})
			Kit.tooltip(tile, `<b>{nodeName(stopType)}</b> on floor {row}\n{nodeHint(stopType)}`)
		end
		if current then
			Kit.title({
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new((row - 0.5) / rows, 0, 1, 4),
				Size = UDim2.fromOffset(40, 12),
				Text = "▲",
				TextSize = 10,
				TextColor3 = C.goldLight,
				Parent = track,
			})
		end
	end
end

function MapScreen:_pathCard(card)
	local color = Theme.nodeColors[card.type] or C.panelLight
	local button = make("TextButton", {
		Size = UDim2.fromOffset(196, 260),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		Parent = self.cards,
	})
	Kit.outline().Parent = button
	local face = make("Frame", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		BackgroundColor3 = C.panelDark,
		Parent = button,
	})
	nodeTile(face, card.type, 84, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
	})
	Kit.title({
		Position = UDim2.fromOffset(0, 114),
		Size = UDim2.new(1, 0, 0, 22),
		Text = string.upper(card.name),
		TextSize = 14,
		Parent = face,
	})
	local hint = Kit.text({
		Position = UDim2.fromOffset(10, 140),
		Size = UDim2.new(1, -20, 1, -178),
		Text = card.hint,
		TextScaled = true,
		TextColor3 = C.textDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = face,
	})
	make("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 10, Parent = hint })
	-- What follows this node.
	local leads = make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -8),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Parent = face,
	}, { Kit.hlist(4) })
	Kit.text({ AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), Text = "Leads to", TextSize = 16, TextColor3 = C.textDim, Parent = leads })
	for _, nextType in card.leadsTo do
		local tile = nodeTile(leads, nextType, 22, { Active = true })
		Kit.tooltip(tile, nodeName(nextType))
	end

	local scale = make("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.04 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		Remotes.ChooseNode:FireServer(card.nodeId)
	end)
end

function MapScreen:render(run)
	self.run = run
	local progress = run.map.progress
	self.actLabel.Text = string.upper(`Act {progress.act}: {progress.actName}`)
	self.floorLabel.Text = `FLOOR {progress.row}/{progress.rows}`
	self:_renderTrack(progress)
	Kit.clear(self.cards)
	for _, card in run.map.pathCards do
		self:_pathCard(card)
	end
	if self.fullMap then
		self.fullMap.close()
		self:openFullMap()
	end
end

-- The whole graph, bottom to top, scrolled to where you are. Reachable
-- nodes glow and can be picked here too.
function MapScreen:openFullMap()
	local run = self.run
	if not run then
		return
	end
	local map = run.map
	local modal = Kit.modal(self.modalLayer, "Full map", UDim2.new(0.8, 0, 0.9, 0), function()
		self.fullMap = nil
	end)
	self.fullMap = modal
	local rows = map.progress.rows
	local rowHeight = 64
	local scroll = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		CanvasSize = UDim2.fromOffset(0, rows * rowHeight + 20),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.textDim,
		ZIndex = 33,
		Parent = modal.body,
	})
	local width = 520
	local canvas = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(width, rows * rowHeight + 20),
		BackgroundTransparency = 1,
		ZIndex = 33,
		Parent = scroll,
	})

	local reachable = {}
	for _, card in map.pathCards do
		reachable[card.nodeId] = true
	end
	local byId = {}
	for _, node in map.nodes do
		byId[node.id] = node
	end
	local function point(node): UDim2
		return UDim2.new((node.col - 0.5) / map.columns, 0, 0, (rows - node.row) * rowHeight + rowHeight / 2 + 10)
	end

	-- Edges under the nodes.
	local edges = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 33, Parent = canvas })
	do
		for _, node in map.nodes do
			for _, nextId in node.next do
				local other = byId[nextId]
				if other then
					local ax = (node.col - 0.5) / map.columns * width
					local bx = (other.col - 0.5) / map.columns * width
					local ay = (rows - node.row) * rowHeight + rowHeight / 2 + 10
					local by = (rows - other.row) * rowHeight + rowHeight / 2 + 10
					local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
					make("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2),
						Size = UDim2.fromOffset(length, 3),
						Rotation = math.deg(math.atan2(by - ay, bx - ax)),
						BackgroundColor3 = if node.visited and other.visited then C.gold else C.panelLight,
						ZIndex = 33,
						Parent = edges,
					})
				end
			end
		end
	end

	for _, node in map.nodes do
		local isCurrent = node.id == map.currentNodeId
		local canPick = reachable[node.id] == true
		local tile = make("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = point(node),
			Size = UDim2.fromOffset(38, 38),
			BackgroundColor3 = Theme.nodeColors[node.type] or C.panelLight,
			BackgroundTransparency = if node.visited or canPick or isCurrent then 0 else 0.35,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 34,
			Parent = canvas,
		})
		Kit.outline(if isCurrent or canPick then C.goldLight else C.ink, if isCurrent or canPick then 3 else 2).Parent = tile
		Kit.icon(node.type, 24, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextTransparency = if node.visited and not isCurrent then 0.5 else 0,
			ZIndex = 35,
			Parent = tile,
		})
		Kit.tooltip(tile, `<b>{nodeName(node.type)}</b> · floor {node.row}\n{nodeHint(node.type)}`)
		if canPick then
			TweenService:Create(
				tile,
				TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Size = UDim2.fromOffset(44, 44) }
			):Play()
			tile.Activated:Connect(function()
				modal.close()
				Remotes.ChooseNode:FireServer(node.id)
			end)
		end
	end

	-- Start scrolled so the current floor is in view.
	task.defer(function()
		local row = math.max(map.progress.row, 1)
		local y = (rows - row) * rowHeight - scroll.AbsoluteSize.Y / Kit.uiScale / 2
		scroll.CanvasPosition = Vector2.new(0, math.max(y, 0))
	end)
end

return MapScreen
