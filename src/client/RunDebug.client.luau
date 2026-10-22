--[[
	Bare-bones debug screen for runs: the map (act progress bar plus 2 or 3
	path cards, with the full graph behind a button), rewards, events, shops,
	rests and card picks. Fights use the combat debug screen underneath, so
	this panel hides while a fight is on. Like that screen it only draws what
	the server sends and reports what the player clicked.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Data.Content)
local Remotes = require(Shared.Net.Remotes)

local player = Players.LocalPlayer

-- Layout helpers ---------------------------------------------------------------

local nextOrder = 0

local function make(className: string, props: { [string]: any }, children: { Instance }?)
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		-- List layouts sort by LayoutOrder: keep creation order.
		nextOrder += 1
		inst.LayoutOrder = nextOrder
	end
	for key, value in props do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end

local function corner(radius: number?)
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

local function label(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.Font = props.Font or Enum.Font.Gotham
	props.TextSize = props.TextSize or 14
	props.TextWrapped = true
	return make("TextLabel", props)
end

local function button(props, onClick: (() -> ())?)
	props.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(45, 50, 64)
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.Font = props.Font or Enum.Font.GothamMedium
	props.TextSize = props.TextSize or 14
	props.TextWrapped = true
	props.AutoButtonColor = true
	local b = make("TextButton", props, { corner() })
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local function row(parent: Instance, height: number)
	return make("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
		}),
	})
end

local function act(action)
	Remotes.ChooseOption:FireServer(action)
end

local TYPE_COLOURS = {
	Combat = Color3.fromRGB(110, 60, 60),
	Elite = Color3.fromRGB(150, 50, 90),
	Event = Color3.fromRGB(70, 80, 140),
	Rest = Color3.fromRGB(60, 120, 80),
	Shop = Color3.fromRGB(150, 120, 40),
	Treasure = Color3.fromRGB(170, 140, 50),
	Boss = Color3.fromRGB(160, 40, 40),
}

-- Screen ---------------------------------------------------------------------------

local gui = make("ScreenGui", {
	Name = "RunDebug",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 5,
	Parent = player:WaitForChild("PlayerGui"),
})

local panel = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(18, 20, 28),
	Visible = false,
	Parent = gui,
})

button({
	Size = UDim2.fromOffset(110, 32),
	Position = UDim2.new(1, -122, 0, 50),
	BackgroundColor3 = Color3.fromRGB(60, 110, 70),
	Text = "New Run",
	Parent = gui,
}, function()
	Remotes.StartRun:FireServer()
end)

local topLabel = label({
	Size = UDim2.new(1, -150, 0, 40),
	Position = UDim2.fromOffset(12, 8),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 15,
	Parent = panel,
})

local progressBack = make("Frame", {
	Size = UDim2.new(1, -24, 0, 18),
	Position = UDim2.fromOffset(12, 90),
	BackgroundColor3 = Color3.fromRGB(40, 44, 56),
	Parent = panel,
}, { corner(9) })
local progressFill = make("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.fromRGB(200, 160, 60),
	Parent = progressBack,
}, { corner(9) })
local progressText = label({
	Size = UDim2.new(1, -24, 0, 20),
	Position = UDim2.fromOffset(12, 112),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(180, 185, 200),
	TextSize = 13,
	Parent = panel,
})

local body = make("Frame", {
	Size = UDim2.new(1, -24, 1, -150),
	Position = UDim2.fromOffset(12, 140),
	BackgroundTransparency = 1,
	Parent = panel,
}, {
	make("UIListLayout", {
		Padding = UDim.new(0, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local snapshot = nil
local showFullMap = false
local render

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function title(text: string, size: number?)
	label({ Size = UDim2.new(1, 0, 0, (size or 20) + 10), Text = text, TextSize = size or 20, Font = Enum.Font.GothamBold, Parent = body })
end

local function paragraph(text: string, height: number?)
	label({ Size = UDim2.new(1, 0, 0, height or 40), Text = text, TextColor3 = Color3.fromRGB(200, 205, 215), Parent = body })
end

local function cardText(card): string
	local qte = if card.qte then `\n[QTE {card.qte}]` else ""
	return `({card.cost}) {card.name}\n{card.type} · {card.rarity}\n{card.text}{qte}`
end

local function cardButton(parent: Instance, card, extra: string?, onClick: (() -> ())?, enabled: boolean?)
	return button({
		Size = UDim2.fromOffset(150, 150),
		BackgroundColor3 = if enabled == false then Color3.fromRGB(40, 40, 46) else Color3.fromRGB(50, 70, 110),
		Text = cardText(card) .. (extra or ""),
		TextSize = 12,
		Parent = parent,
	}, onClick)
end

-- Screens ---------------------------------------------------------------------------

local screens = {}

function screens.Map(screen)
	local map = snapshot.map
	if showFullMap then
		title("Full map")
		local byId = {}
		for _, node in map.nodes do
			byId[node.id] = node
		end
		local lines = {}
		for r = map.progress.rows, 1, -1 do
			local cells = table.create(map.columns, "  .  ")
			for _, node in map.nodes do
				if node.row == r then
					local mark = if node.id == map.currentNodeId then "*" elseif node.visited then "+" else " "
					cells[node.col] = mark .. string.sub(node.type, 1, 4)
				end
			end
			table.insert(lines, string.format("%2d ", r) .. table.concat(cells, " "))
		end
		label({
			Size = UDim2.new(1, 0, 0, 330),
			Text = table.concat(lines, "\n"),
			Font = Enum.Font.Code,
			TextSize = 14,
			Parent = body,
		})
	else
		title("Choose your path")
		local cards = row(body, 190)
		for _, card in map.pathCards do
			local leads = {}
			for _, nodeType in card.leadsTo do
				local info = Content.RunRules.nodeTypes[nodeType]
				table.insert(leads, info and info.name or nodeType)
			end
			button({
				Size = UDim2.fromOffset(180, 180),
				BackgroundColor3 = TYPE_COLOURS[card.type] or Color3.fromRGB(60, 60, 70),
				Text = `{string.upper(card.name)}\n\n{card.hint}\n\nleads to: {table.concat(leads, ", ")}`,
				TextSize = 14,
				Parent = cards,
			}, function()
				Remotes.ChooseNode:FireServer(card.nodeId)
			end)
		end
	end
	local controls = row(body, 36)
	button({ Size = UDim2.fromOffset(160, 32), Text = if showFullMap then "Back to paths" else "View full map", Parent = controls }, function()
		showFullMap = not showFullMap
		render()
	end)
end

function screens.Reward(screen)
	title(if screen.source == "Event" then "Pick a card" else "Victory!")
	local parts = {}
	if screen.gold > 0 then
		table.insert(parts, `+{screen.gold} gold`)
	end
	if screen.relic then
		table.insert(parts, `Relic: {screen.relic.name} ({screen.relic.text})`)
	end
	paragraph(table.concat(parts, "   "), 24)
	local cards = row(body, 160)
	for index, card in screen.cards do
		cardButton(cards, card, nil, function()
			act({ kind = "Option", index = index })
		end)
	end
	button({ Size = UDim2.fromOffset(120, 32), Text = "Skip", Parent = row(body, 36) }, function()
		act({ kind = "Skip" })
	end)
end

function screens.RelicChoice(screen)
	title("Choose a boss relic")
	local relics = row(body, 130)
	for index, relic in screen.relics do
		button({ Size = UDim2.fromOffset(200, 120), Text = `{relic.name}\n\n{relic.text}`, Parent = relics }, function()
			act({ kind = "Option", index = index })
		end)
	end
	button({ Size = UDim2.fromOffset(120, 32), Text = "Skip", Parent = row(body, 36) }, function()
		act({ kind = "Skip" })
	end)
end

function screens.Event(screen)
	local event = screen.event
	title(event.name)
	paragraph(event.text, 50)
	for _, option in event.options do
		local tags = if #option.tags > 0 then `\n{table.concat(option.tags, " · ")}` else ""
		button({
			Size = UDim2.new(0, 420, 0, 50),
			BackgroundColor3 = if option.available then Color3.fromRGB(60, 70, 110) else Color3.fromRGB(40, 40, 46),
			TextColor3 = if option.available then Color3.new(1, 1, 1) else Color3.fromRGB(120, 120, 130),
			Text = option.label .. tags,
			Parent = body,
		}, function()
			if option.available then
				act({ kind = "Option", index = option.index })
			end
		end)
	end
end

function screens.EventResult(screen)
	title(`{screen.name}: {screen.label}`)
	if screen.success ~= nil then
		title(if screen.success then "Success!" else "Failed", 16)
	end
	if #screen.revealed > 0 then
		local cards = row(body, 160)
		for _, card in screen.revealed do
			cardButton(cards, card)
		end
	end
	paragraph(screen.text)
	button({ Size = UDim2.fromOffset(140, 36), Text = "Continue", Parent = row(body, 40) }, function()
		act({ kind = "Proceed" })
	end)
end

function screens.Shop(screen)
	title("Shop")
	local cards = row(body, 160)
	for index, entry in screen.cards do
		local price = if entry.sold then "\nSOLD" else `\n{entry.price} gold{if entry.onSale then " (sale!)" else ""}`
		cardButton(cards, entry.card, price, function()
			act({ kind = "Buy", item = "Card", index = index })
		end, not entry.sold)
	end
	local relics = row(body, 90)
	for index, entry in screen.relics do
		button({
			Size = UDim2.fromOffset(200, 80),
			BackgroundColor3 = if entry.sold then Color3.fromRGB(40, 40, 46) else Color3.fromRGB(90, 70, 40),
			Text = `{entry.relic.name}\n{entry.relic.text}\n{if entry.sold then "SOLD" else `{entry.price} gold`}`,
			TextSize = 12,
			Parent = relics,
		}, function()
			act({ kind = "Buy", item = "Relic", index = index })
		end)
	end
	local services = row(body, 40)
	button({
		Size = UDim2.fromOffset(170, 36),
		Text = if screen.remove.used then "Remove (used)" else `Remove a card: {screen.remove.price}`,
		Parent = services,
	}, function()
		act({ kind = "Buy", item = "Remove" })
	end)
	button({
		Size = UDim2.fromOffset(170, 36),
		Text = if screen.upgrade.used then "Upgrade (used)" else `Upgrade a card: {screen.upgrade.price}`,
		Parent = services,
	}, function()
		act({ kind = "Buy", item = "Upgrade" })
	end)
	button({ Size = UDim2.fromOffset(120, 36), Text = "Leave", Parent = services }, function()
		act({ kind = "Proceed" })
	end)
end

function screens.Rest(screen)
	title("Camp")
	local options = row(body, 90)
	for index, option in screen.options do
		local text = if option.id == "Heal"
			then `Rest\nHeal {option.amount} HP`
			elseif option.id == "Upgrade" then "Smith\nUpgrade a card"
			else "Purge\nRemove a card (once per act)"
		button({
			Size = UDim2.fromOffset(180, 80),
			BackgroundColor3 = if option.available then Color3.fromRGB(60, 110, 80) else Color3.fromRGB(40, 40, 46),
			Text = text,
			Parent = options,
		}, function()
			act({ kind = "Option", index = index })
		end)
	end
end

function screens.Treasure(screen)
	title("Treasure")
	paragraph(if screen.relic then `You found {screen.relic.name}: {screen.relic.text}` else "The chest held 50 gold.")
	button({ Size = UDim2.fromOffset(140, 36), Text = "Continue", Parent = row(body, 40) }, function()
		act({ kind = "Proceed" })
	end)
end

function screens.SelectCard(screen)
	title(if screen.purpose == "Upgrade" then "Pick a card to upgrade" else "Pick a card to remove")
	if screen.price then
		paragraph(`Costs {screen.price} gold`, 24)
	end
	local candidates = {}
	for _, uid in screen.candidates do
		candidates[uid] = true
	end
	local scroll = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 340),
		BackgroundTransparency = 1,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, {
		make("UIGridLayout", { CellSize = UDim2.fromOffset(150, 150), CellPadding = UDim2.fromOffset(8, 8) }),
	})
	for _, card in snapshot.deck do
		if not candidates[card.uid] then
			continue
		end
		if screen.purpose == "Upgrade" then
			for _, path in { "A", "B" } do
				local upgraded = Content.getCard(card.id, path)
				if upgraded and upgraded.upgrade == path then
					cardButton(scroll, {
						name = upgraded.name,
						cost = upgraded.cost,
						type = upgraded.type,
						rarity = upgraded.rarity,
						text = upgraded.text,
					}, `\n[path {path}]`, function()
						act({ kind = "Select", uid = card.uid, path = path })
					end)
				end
			end
		else
			cardButton(scroll, card, nil, function()
				act({ kind = "Select", uid = card.uid })
			end)
		end
	end
	if screen.cancellable then
		button({ Size = UDim2.fromOffset(120, 32), Text = "Cancel", Parent = row(body, 36) }, function()
			act({ kind = "Cancel" })
		end)
	end
end

local function ending(screen, heading: string)
	title(heading, 28)
	paragraph(`Rows climbed {screen.stats.rows}, elites {screen.stats.elites}, bosses {screen.stats.bosses}.\nRenown earned: {screen.renown}`, 60)
	button({ Size = UDim2.fromOffset(160, 40), Text = "Start a new run", Parent = row(body, 44) }, function()
		Remotes.StartRun:FireServer()
	end)
end

function screens.Won(screen)
	ending(screen, "Victory! The run is won.")
end

function screens.Lost(screen)
	ending(screen, "You died. The run is over.")
end

function render()
	if not snapshot then
		return
	end
	local screen = snapshot.screen
	panel.Visible = screen.kind ~= "Combat"
	local relics = {}
	for _, relic in snapshot.relics do
		table.insert(relics, relic.name)
	end
	topLabel.Text = `{snapshot.hero.name}  HP {snapshot.hero.hp}/{snapshot.hero.maxHp}  Gold {snapshot.gold}`
		.. `  Deck {#snapshot.deck}  Act {snapshot.act}/{snapshot.actCount}\nRelics: {if #relics > 0 then table.concat(relics, ", ") else "none"}`

	local progress = snapshot.map.progress
	progressFill.Size = UDim2.fromScale(progress.row / progress.rows, 1)
	local stops = {}
	for _, stop in progress.stops do
		table.insert(stops, `{stop.type} {stop.row}`)
	end
	progressText.Text = `{progress.actName}: row {progress.row} of {progress.rows}   ·   {table.concat(stops, "  ·  ")}`

	clear(body)
	local draw = screens[screen.kind]
	if draw then
		draw(screen)
	end
end

Remotes.RunUpdate.OnClientEvent:Connect(function(newSnapshot)
	if newSnapshot == nil then
		-- A debug fight replaced the run.
		snapshot = nil
		panel.Visible = false
		return
	end
	if snapshot and snapshot.screen.kind ~= "Map" then
		showFullMap = false
	end
	snapshot = newSnapshot
	render()
end)
