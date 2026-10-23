--[[
	The game UI's entry point. Builds one ScreenGui with the title menu, the
	top bar, the map, the combat screen, the other run screens and the QTE
	overlay, then shows whichever one the server's state calls for:

		RunUpdate(snapshot)        run.screen.kind picks Map, Combat, or a
		                           run screen (Reward, Shop, Event, ...)
		RunUpdate(nil)             a practice fight with no run around it
		StateUpdate(snapshot, ev)  the fight: drawn by the combat screen
		QteStart(challenge)        opens the QTE overlay

	The client only draws what it is sent and reports what the player did.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Data.Content)
local Remotes = require(Shared.Net.Remotes)

local UI = script.Parent:WaitForChild("UI")
local CombatScreen = require(UI.CombatScreen)
local Hud = require(UI.Hud)
local Kit = require(UI.Kit)
local MapScreen = require(UI.MapScreen)
local QteOverlay = require(UI.QteOverlay)
local RunScreens = require(UI.RunScreens)
local Theme = require(UI.Theme)

local C = Theme.colors
local make = Kit.make

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local gui = make("ScreenGui", {
	Name = "Game",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})
Kit.mountTooltips(playerGui)

-- Everything is laid out for a screen of about 1100 x 620 and scaled to
-- fit: down to 0.6 on phones, up to 1.5 on big monitors.
local scaler = make("Frame", { BackgroundTransparency = 1, Parent = gui })
local uiScale = make("UIScale", { Parent = scaler })
local function fit()
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local scale = math.clamp(math.min(size.X / 1100, size.Y / 620), 0.6, 1.5)
	uiScale.Scale = scale
	Kit.uiScale = scale
	scaler.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
fit()

-- Layers, back to front.
local screensLayer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = scaler })
local hudLayer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 10, Parent = scaler })
local modalLayer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 30, Parent = scaler })
local qteLayer = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 40, Parent = scaler })

-- State --------------------------------------------------------------------------------

local mode: "Title" | "Run" | "Practice" = "Title"
local run = nil -- last run snapshot
local fight = nil -- last combat snapshot
local shownKind: string? = nil -- the run screen on display
local holdToken = 0
local awaitingRun = false -- New Run pressed on the menu

local showTitle, showRun

local function clearModals()
	Kit.hideTooltip()
	Kit.clear(modalLayer)
end

local hud = Hud.new(hudLayer, modalLayer, {
	onMainMenu = function()
		showTitle()
	end,
})
local qte = QteOverlay.new(qteLayer)
local combat = CombatScreen.new(screensLayer, {
	onQteGraded = function(qteId, grade)
		qte:showGrade(qteId, grade)
	end,
})
local map = MapScreen.new(screensLayer, modalLayer)
local runScreens = RunScreens.new(screensLayer, modalLayer, {
	onMainMenu = function()
		showTitle()
	end,
})

-- Title menu ---------------------------------------------------------------------------

local title = make("Frame", {
	Name = "Title",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.backdrop,
	ZIndex = 20,
	Parent = scaler,
})
Kit.title({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.18),
	Size = UDim2.new(1, -24, 0, 50),
	Text = string.upper(Theme.gameTitle),
	TextSize = 40,
	TextColor3 = C.gold,
	TextStrokeTransparency = 0,
	TextStrokeColor3 = C.ink,
	ZIndex = 21,
	Parent = title,
})
Kit.text({
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.18, 62),
	Size = UDim2.new(1, -24, 0, 24),
	Text = Theme.subtitle,
	TextSize = 22,
	TextColor3 = C.textDim,
	ZIndex = 21,
	Parent = title,
})
local menu = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.fromOffset(280, 260),
	BackgroundTransparency = 1,
	ZIndex = 21,
	Parent = title,
}, { Kit.vlist(14) })

local function openTitleSettings()
	local modal = Kit.modal(modalLayer, "Settings", UDim2.fromOffset(460, 240))
	local list = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 33, Parent = modal.body }, { Kit.vlist(12) })
	Hud.assistToggles(list, hud.assist, 33)
end

-- New Run opens the class select: one panel per hero with its art,
-- passive, QTE style and the two cards that set its starter deck apart.
local function openClassSelect()
	local modal = Kit.modal(modalLayer, "Choose your class", UDim2.fromOffset(940, 560))
	local row = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 33, Parent = modal.body }, {
		Kit.hlist(14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top),
	})
	local heroes = {}
	for _, hero in Content.Heroes do
		table.insert(heroes, hero)
	end
	table.sort(heroes, function(a, b)
		return (a.order or 99) < (b.order or 99)
	end)
	for _, hero in heroes do
		local panel = Kit.panel({ Size = UDim2.new(0, 290, 1, 0), BackgroundColor3 = C.panelLight, ZIndex = 33, Parent = row }, {
			Kit.vlist(6),
			Kit.padding(10),
		})
		Kit.icon(hero.id, 72, { ZIndex = 34, Parent = panel })
		Kit.title({ Size = UDim2.new(1, 0, 0, 20), Text = string.upper(hero.name), TextColor3 = C.gold, ZIndex = 34, Parent = panel })
		Kit.text({ Size = UDim2.new(1, 0, 0, 34), Text = hero.blurb or "", TextSize = 16, TextColor3 = C.textDim, ZIndex = 34, Parent = panel })
		local passive = hero.passive
		Kit.text({
			Size = UDim2.new(1, 0, 0, 62),
			RichText = true,
			Text = if passive then `<b>{passive.name}:</b> {passive.text}` else "",
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 34,
			Parent = panel,
		})
		Kit.text({
			Size = UDim2.new(1, 0, 0, 18),
			Text = `{hero.maxHp} HP · QTE style: {hero.qteStyle or "Mixed"}`,
			TextSize = 16,
			ZIndex = 34,
			Parent = panel,
		})
		-- The class cards in the starter deck (everyone shares Strike and Guard).
		local cards = make("Frame", { Size = UDim2.new(1, 0, 0, 130), BackgroundTransparency = 1, ZIndex = 34, Parent = panel }, {
			Kit.hlist(8),
		})
		local seen = {}
		for _, cardId in hero.starterDeck do
			local def = Content.Cards[cardId]
			if def.class == hero.id and not seen[cardId] then
				seen[cardId] = true
				local card = Kit.card(def, { ZIndex = 34, Parent = cards }, nil, { scale = 0.76 })
				Kit.tooltip(card, `<b>{def.name}</b>\n{def.text}`)
			end
		end
		Kit.button({ Size = UDim2.new(1, 0, 0, 40), Text = `Play {hero.name}`, ZIndex = 34, Parent = panel }, function()
			modal.close()
			Remotes.StartRun:FireServer(hero.id)
			awaitingRun = true
		end, { color = C.buttonGo, textSize = 12 })
	end
end

local function drawMenu()
	Kit.clear(menu)
	local canContinue = run ~= nil and not run.over
	if canContinue then
		Kit.button({ Size = UDim2.new(1, 0, 0, 52), Text = "Continue", ZIndex = 21, Parent = menu }, function()
			mode = "Run"
			showRun(run)
		end, { color = C.buttonGo, textSize = 16 })
	end
	Kit.button({ Size = UDim2.new(1, 0, 0, 52), Text = "New Run", ZIndex = 21, Parent = menu }, openClassSelect, {
		color = if canContinue then C.button else C.buttonGo,
		textSize = 16,
	})
	Kit.button({ Size = UDim2.new(1, 0, 0, 44), Text = "Practice fight", ZIndex = 21, Parent = menu }, function()
		Remotes.StartCombat:FireServer("Prototype")
	end, { textSize = 12 })
	Kit.button({ Size = UDim2.new(1, 0, 0, 44), Text = "Settings", ZIndex = 21, Parent = menu }, openTitleSettings, { textSize = 12 })
end

-- Routing ------------------------------------------------------------------------------

local function hideAll()
	combat:setVisible(false)
	map:setVisible(false)
	runScreens:setVisible(false)
	hud:setVisible(false)
end

function showTitle()
	mode = "Title"
	clearModals()
	hideAll()
	drawMenu()
	title.Visible = true
end

function showRun(snapshot)
	local kind = snapshot.screen.kind
	if kind ~= shownKind or title.Visible then
		clearModals()
	end
	title.Visible = false
	hud:setVisible(true)
	hud:setRun(snapshot)
	shownKind = kind
	combat:setVisible(kind == "Combat")
	map:setVisible(kind == "Map")
	runScreens:setVisible(kind ~= "Combat" and kind ~= "Map")
	if kind == "Combat" then
		if fight then
			hud:setHp(fight.hero.hp, fight.hero.maxHp)
		end
	elseif kind == "Map" then
		map:render(snapshot)
	else
		runScreens:render(snapshot)
	end
end

Remotes.RunUpdate.OnClientEvent:Connect(function(snapshot)
	if snapshot == nil then
		-- A practice fight replaced the run.
		run = nil
		mode = "Practice"
		clearModals()
		hideAll()
		title.Visible = false
		combat:setVisible(true)
		return
	end
	run = snapshot
	if mode == "Title" and not awaitingRun then
		-- Only New Run or Continue leaves the menu.
		drawMenu()
		return
	end
	awaitingRun = false
	mode = "Run"
	holdToken += 1
	if shownKind == "Combat" and snapshot.screen.kind ~= "Combat" then
		-- Let the last hit and the result banner land before leaving the fight.
		local token = holdToken
		task.delay(1.3, function()
			if holdToken == token and mode == "Run" then
				showRun(run)
			end
		end)
		return
	end
	showRun(snapshot)
end)

Remotes.StateUpdate.OnClientEvent:Connect(function(snapshot, events)
	for _, event in events do
		if event.type == "CombatStarted" then
			combat:reset()
		end
	end
	fight = snapshot
	combat:render(snapshot)
	combat:playEvents(events)
	if mode == "Run" then
		hud:setHp(snapshot.hero.hp, snapshot.hero.maxHp)
	end
	if mode == "Practice" then
		for _, event in events do
			if event.type == "CombatEnded" then
				task.delay(1.2, function()
					combat:showResult(event.result, {
						{
							text = "Fight again",
							onClick = function()
								Remotes.StartCombat:FireServer("Prototype")
							end,
						},
						{ text = "Main menu", onClick = showTitle },
					})
				end)
			end
		end
	end
end)

Remotes.QteStart.OnClientEvent:Connect(function(challenge)
	clearModals()
	qte:start(challenge)
end)

showTitle()
