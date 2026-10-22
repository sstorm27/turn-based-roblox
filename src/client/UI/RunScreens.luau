--[[
	Every run screen that isn't the map or a fight: rewards, boss relics,
	events and their results, shops, camp (rest), treasure, picking a card to
	upgrade or remove, and the end of the run. Each draws one `screen` from
	the run snapshot and sends the player's choice with ChooseOption.
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

local RunScreens = {}
RunScreens.__index = RunScreens

local function act(action)
	Kit.hideTooltip()
	Remotes.ChooseOption:FireServer(action)
end

function RunScreens.new(parent: Instance, modalLayer: Instance, callbacks: { onMainMenu: () -> () })
	local self = setmetatable({}, RunScreens)
	self.modalLayer = modalLayer
	self.callbacks = callbacks
	self.run = nil

	local root = make("Frame", {
		Name = "RunScreens",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.backdrop,
		Visible = false,
		Parent = parent,
	})
	self.root = root
	local body = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S.topBar + 18),
		Size = UDim2.new(1, -2 * S.gutter, 1, -(S.topBar + 30)),
		BackgroundTransparency = 1,
		Parent = root,
	}, { Kit.vlist(14) })
	make("UISizeConstraint", { MaxSize = Vector2.new(960, math.huge), Parent = body })
	self.body = body
	return self
end

function RunScreens:setVisible(visible: boolean)
	self.root.Visible = visible
end

-- Pieces -----------------------------------------------------------------------------

function RunScreens:_heading(text: string, color: Color3?, size: number?)
	return Kit.title({
		Size = UDim2.new(1, 0, 0, (size or 20) + 12),
		Text = text,
		TextSize = size or 20,
		TextColor3 = color or C.text,
		Parent = self.body,
	})
end

function RunScreens:_line(text: string, height: number?, color: Color3?)
	return Kit.text({
		Size = UDim2.new(1, 0, 0, height or 24),
		Text = text,
		TextSize = 20,
		TextColor3 = color or C.textDim,
		Parent = self.body,
	})
end

function RunScreens:_row(height: number, padding: number?)
	return make("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		Parent = self.body,
	}, { Kit.hlist(padding or 18, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top) })
end

function RunScreens:_button(parent: Instance, text: string, onClick: () -> (), options: Kit.ButtonOptions?, width: number?)
	return Kit.button({ Size = UDim2.fromOffset(width or 180, 46), Text = text, Parent = parent }, onClick, options)
end

-- A relic as a tile: icon, name and text.
local function relicTile(
	parent: Instance,
	relic,
	width: number,
	footer: string?,
	onClick: (() -> ())?,
	enabled: boolean?,
	footerColor: Color3?
)
	local live = enabled ~= false
	local rarity = Theme.rarityColors[relic.rarity] or C.gold
	local tile = make("TextButton", {
		Size = UDim2.fromOffset(width, 150),
		BackgroundColor3 = if live then C.panel else C.panelDark,
		AutoButtonColor = false,
		Text = "",
		Parent = parent,
	})
	Kit.outline(if live then rarity else C.disabled).Parent = tile
	Kit.icon("relic", 40, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		TextColor3 = if live then rarity else C.disabled,
		Parent = tile,
	})
	Kit.title({
		Position = UDim2.fromOffset(6, 56),
		Size = UDim2.new(1, -12, 0, 18),
		Text = relic.name,
		TextSize = 10,
		TextColor3 = if live then C.text else C.textDim,
		Parent = tile,
	})
	Kit.text({
		Position = UDim2.fromOffset(10, 78),
		Size = UDim2.new(1, -20, 0, 50),
		Text = relic.text,
		TextSize = 17,
		TextColor3 = C.textDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = tile,
	})
	if footer then
		local tag = Kit.chip(footer, footerColor or C.gold, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(0, 22),
			TextSize = 18,
			ZIndex = 3,
			Parent = tile,
		})
		tag.BackgroundColor3 = C.ink
	end
	if onClick and live then
		tile.Activated:Connect(onClick)
	end
	return tile
end

-- Flip a card in: grows from nothing after `delay` seconds.
local function reveal(widget: GuiObject, delay: number)
	local scale = make("UIScale", { Scale = 0, Parent = widget })
	task.delay(delay, function()
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
end

-- Screens ----------------------------------------------------------------------------

local screens = {}

function screens.Reward(self, screen)
	if screen.source == "Event" then
		self:_heading("PICK A CARD", C.gold)
	else
		self:_heading("VICTORY!", C.gold, 26)
	end
	local loot = self:_row(if screen.relic then 158 else 28, 12)
	if screen.gold > 0 then
		local chip = Kit.chip(`+{screen.gold} gold`, C.gold, { Size = UDim2.fromOffset(0, 26), TextSize = 20, Parent = loot })
		chip.LayoutOrder = -1
	end
	if screen.relic then
		relicTile(loot, screen.relic, 200, "Relic gained")
	end
	if #screen.cards > 0 then
		self:_line("Add a card to your deck, or skip.")
		local cards = self:_row(math.floor(S.cardH * 1.3) + 10, 22)
		for index, card in screen.cards do
			local widget = Kit.card(card, { Parent = cards }, function()
				act({ kind = "Option", index = index })
			end, { scale = 1.3 })
			reveal(widget, 0.1 * index)
			Kit.tooltip(widget, `{card.rarity} {card.type}`)
		end
	end
	local controls = self:_row(50)
	self:_button(controls, if #screen.cards > 0 then "Skip" else "Continue", function()
		act({ kind = "Skip" })
	end)
end

function screens.RelicChoice(self, screen)
	self:_heading("CHOOSE A BOSS RELIC", C.gold)
	self:_line("Boss relics are strong, with a drawback.")
	local row = self:_row(160, 22)
	for index, relic in screen.relics do
		local tile = relicTile(row, relic, 220, nil, function()
			act({ kind = "Option", index = index })
		end)
		reveal(tile, 0.1 * index)
	end
	self:_button(self:_row(50), "Skip", function()
		act({ kind = "Skip" })
	end)
end

function screens.Event(self, screen)
	local event = screen.event
	self:_heading(string.upper(event.name), C.gold)
	local content = make("Frame", {
		Size = UDim2.new(1, 0, 0, 380),
		BackgroundTransparency = 1,
		Parent = self.body,
	}, { Kit.hlist(20, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top) })
	-- Placeholder art panel until event art exists.
	local art = Kit.panel({ Size = UDim2.fromOffset(220, 220), BackgroundColor3 = Theme.nodeColors.Event, Parent = content })
	Kit.icon("Event", 110, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = art })

	local column = make("Frame", { Size = UDim2.new(1, -240, 1, 0), BackgroundTransparency = 1, Parent = content }, { Kit.vlist(10, Enum.HorizontalAlignment.Left) })
	Kit.text({
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 40),
		Text = event.text,
		TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = column,
	})
	for _, option in event.options do
		local holder = make("Frame", { Size = UDim2.new(1, 0, 0, if #option.tags > 0 then 64 else 46), BackgroundTransparency = 1, Parent = column })
		Kit.button({
			Size = UDim2.new(1, 0, 0, 44),
			Text = "  " .. option.label,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = holder,
		}, function()
			act({ kind = "Option", index = option.index })
		end, { enabled = option.available, font = Theme.fonts.body, textSize = 21 })
		if #option.tags > 0 then
			local tags = make("Frame", {
				Position = UDim2.fromOffset(8, 44),
				Size = UDim2.new(1, -8, 0, 20),
				BackgroundTransparency = 1,
				Parent = holder,
			}, { Kit.hlist(6, Enum.HorizontalAlignment.Left) })
			for _, tag in option.tags do
				Kit.chip(tag, if option.available then C.gold else C.textDim, { Size = UDim2.fromOffset(0, 18), TextSize = 16, Parent = tags })
			end
		end
	end
end

function screens.EventResult(self, screen)
	self:_heading(string.upper(screen.name), C.gold)
	if screen.success ~= nil then
		self:_heading(if screen.success then "SUCCESS!" else "FAILED", if screen.success then C.heal else C.hp, 16)
	end
	if #screen.revealed > 0 then
		-- Card checks show the 3 revealed cards one by one.
		local cards = self:_row(S.cardH + 10, 18)
		for index, card in screen.revealed do
			reveal(Kit.card(card, { Parent = cards }), 0.35 * index)
		end
	end
	Kit.text({
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 30),
		Text = screen.text,
		TextSize = 21,
		Parent = self.body,
	})
	self:_button(self:_row(50), "Continue", function()
		act({ kind = "Proceed" })
	end, { color = C.buttonGo })
end

function screens.Shop(self, screen)
	local gold = self.run.gold
	self:_heading("SHOP", C.gold)
	local cards = self:_row(S.cardH + 36, 16)
	for index, entry in screen.cards do
		local affordable = entry.price <= gold
		local footer = if entry.sold then "SOLD" elseif entry.onSale then `{entry.price}g SALE` else `{entry.price}g`
		Kit.card(entry.card, { Parent = cards }, function()
			act({ kind = "Buy", item = "Card", index = index })
		end, {
			enabled = not entry.sold and affordable,
			footer = footer,
			footerColor = if entry.sold then C.textDim elseif affordable then C.gold else C.hp,
		})
	end
	local relics = self:_row(166, 16)
	for index, entry in screen.relics do
		relicTile(
			relics,
			entry.relic,
			190,
			if entry.sold then "SOLD" else `{entry.price}g`,
			function()
				act({ kind = "Buy", item = "Relic", index = index })
			end,
			not entry.sold and entry.price <= gold,
			if entry.sold then C.textDim elseif entry.price <= gold then C.gold else C.hp
		)
	end
	local services = self:_row(50, 14)
	self:_button(services, if screen.remove.used then "Removal used" else `Remove a card  {screen.remove.price}g`, function()
		act({ kind = "Buy", item = "Remove" })
	end, { enabled = not screen.remove.used and screen.remove.price <= gold, textSize = 10 }, 230)
	self:_button(services, if screen.upgrade.used then "Upgrade used" else `Upgrade a card  {screen.upgrade.price}g`, function()
		act({ kind = "Buy", item = "Upgrade" })
	end, { enabled = not screen.upgrade.used and screen.upgrade.price <= gold, textSize = 10 }, 230)
	self:_button(services, "Leave", function()
		act({ kind = "Proceed" })
	end, { color = C.buttonPrimary }, 130)
end

local REST_OPTIONS = {
	Heal = { title = "REST", icon = "hp" },
	Upgrade = { title = "SMITH", icon = "Rest" },
	Remove = { title = "PURGE", icon = "exhaust" },
}

function screens.Rest(self, screen)
	self:_heading("CAMP", C.gold)
	self:_line("Choose one.")
	local row = self:_row(200, 22)
	for index, option in screen.options do
		local style = REST_OPTIONS[option.id] or { title = option.id, icon = "Rest" }
		local text = if option.id == "Heal"
			then `Heal {option.amount} HP.`
			elseif option.id == "Upgrade" then "Upgrade a card."
			else "Remove a card. Once per act."
		local tile = make("TextButton", {
			Size = UDim2.fromOffset(190, 190),
			BackgroundColor3 = if option.available then C.panel else C.panelDark,
			AutoButtonColor = false,
			Text = "",
			Parent = row,
		})
		Kit.outline(if option.available then Theme.nodeColors.Rest else C.disabled).Parent = tile
		Kit.icon(style.icon, 56, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 18),
			TextTransparency = if option.available then 0 else 0.6,
			Parent = tile,
		})
		Kit.title({
			Position = UDim2.fromOffset(0, 92),
			Size = UDim2.new(1, 0, 0, 22),
			Text = style.title,
			TextSize = 14,
			TextColor3 = if option.available then C.text else C.textDim,
			Parent = tile,
		})
		Kit.text({
			Position = UDim2.fromOffset(10, 122),
			Size = UDim2.new(1, -20, 0, 50),
			Text = text,
			TextSize = 18,
			TextColor3 = C.textDim,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = tile,
		})
		if option.available then
			tile.Activated:Connect(function()
				act({ kind = "Option", index = index })
			end)
		end
	end
end

function screens.Treasure(self, screen)
	self:_heading("TREASURE", C.gold)
	local row = self:_row(160)
	if screen.relic then
		reveal(relicTile(row, screen.relic, 240), 0.15)
	else
		self:_line("The chest held 50 gold.", 30, C.gold)
	end
	self:_button(self:_row(50), "Continue", function()
		act({ kind = "Proceed" })
	end, { color = C.buttonGo })
end

-- Upgrade A/B: both versions next to the current card, changed numbers in gold.
function RunScreens:_upgradeChoice(card)
	local base = Content.getCard(card.id, card.upgrade)
	if not base then
		return
	end
	local modal = Kit.modal(self.modalLayer, `Upgrade {base.name}`, UDim2.fromOffset(620, 360))
	local row = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 33, Parent = modal.body }, {
		Kit.hlist(24, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center),
	})
	local current = Kit.card(card, { ZIndex = 33, Parent = row }, nil, { scale = 1.3 })
	Kit.title({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -8),
		Size = UDim2.fromOffset(150, 14),
		Text = "NOW",
		TextSize = 10,
		TextColor3 = C.textDim,
		ZIndex = 33,
		Parent = current,
	})
	for _, path in { "A", "B" } do
		local upgraded = Content.getCard(card.id, path)
		if upgraded and upgraded.upgrade == path then
			local view = {
				name = upgraded.name,
				cost = upgraded.cost,
				type = upgraded.type,
				text = upgraded.text,
				upgrade = path,
				qte = upgraded.qte and upgraded.qte.kind,
			}
			local widget = Kit.card(view, { ZIndex = 33, Parent = row }, function()
				modal.close()
				act({ kind = "Select", uid = card.uid, path = path })
			end, {
				scale = 1.3,
				richText = Kit.highlightChanges(base.text, upgraded.text),
				footer = `Path {path}`,
			})
			Kit.tooltip(widget, `Pick path {path}`)
		end
	end
end

function screens.SelectCard(self, screen)
	local upgrading = screen.purpose == "Upgrade"
	self:_heading(if upgrading then "PICK A CARD TO UPGRADE" else "PICK A CARD TO REMOVE", C.gold)
	if screen.price then
		self:_line(`Costs {screen.price} gold`)
	end
	local candidates = {}
	for _, uid in screen.candidates do
		candidates[uid] = true
	end
	local holder = make("Frame", { Size = UDim2.new(1, 0, 1, -170), BackgroundTransparency = 1, Parent = self.body })
	local grid = Kit.cardGrid(holder)
	for _, card in self.run.deck do
		if candidates[card.uid] then
			Kit.card(card, { Parent = grid }, function()
				if upgrading then
					self:_upgradeChoice(card)
				else
					act({ kind = "Select", uid = card.uid })
				end
			end)
		end
	end
	if screen.cancellable then
		self:_button(self:_row(50), "Cancel", function()
			act({ kind = "Cancel" })
		end)
	end
end

local function ending(self, screen, won: boolean)
	self:_heading(if won then "VICTORY!" else "YOU DIED", if won then C.gold else C.hp, 30)
	self:_line(if won then "The run is won." else "The run is over.", 28)
	local stats = Kit.panel({ Size = UDim2.fromOffset(340, 170), Parent = self.body }, { Kit.vlist(6) })
	Kit.padding(18).Parent = stats
	for _, line in {
		{ "Floors climbed", screen.stats.rows },
		{ "Fights won", screen.stats.fights },
		{ "Elites beaten", screen.stats.elites },
		{ "Bosses beaten", screen.stats.bosses },
		{ "Renown earned", screen.renown },
	} do
		local row = make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = stats })
		Kit.text({ Size = UDim2.fromScale(0.7, 1), Text = line[1], TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		Kit.title({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.3, 1),
			Text = tostring(line[2] or 0),
			TextSize = 12,
			TextColor3 = C.gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
	end
	local controls = self:_row(50, 14)
	self:_button(controls, "New run", function()
		Remotes.StartRun:FireServer()
	end, { color = C.buttonGo })
	self:_button(controls, "Main menu", function()
		self.callbacks.onMainMenu()
	end)
end

function screens.Won(self, screen)
	ending(self, screen, true)
end

function screens.Lost(self, screen)
	ending(self, screen, false)
end

function RunScreens:render(run)
	self.run = run
	Kit.clear(self.body)
	local draw = screens[run.screen.kind]
	if draw then
		draw(self, run.screen)
	end
end

return RunScreens
