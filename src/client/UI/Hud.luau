--[[
	The top bar shown on every run screen: hero, HP, gold, relics, and the
	Deck and Settings buttons. Also owns the deck viewer and the settings
	panel (QTE assist options and a way back to the main menu).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local C = Theme.colors
local S = Theme.sizes
local make = Kit.make

local Hud = {}
Hud.__index = Hud

function Hud.new(parent: Instance, modalLayer: Instance, callbacks: { onMainMenu: () -> () })
	local self = setmetatable({}, Hud)
	self.modalLayer = modalLayer
	self.callbacks = callbacks
	self.run = nil
	self.assist = { wideWindows = false, alwaysGood = false }

	local bar = make("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, S.topBar),
		BackgroundColor3 = C.panelDark,
		Visible = false,
		ZIndex = 10,
		Parent = parent,
	})
	make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = C.ink,
		ZIndex = 10,
		Parent = bar,
	})
	self.root = bar

	local left = make("Frame", {
		Position = UDim2.fromOffset(S.gutter, 0),
		Size = UDim2.new(0.6, 0, 1, -3),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = bar,
	}, { Kit.hlist(14, Enum.HorizontalAlignment.Left) })

	self.heroName = Kit.title({ AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), TextSize = 12, ZIndex = 11, Parent = left })
	local hp = make("Frame", { Size = UDim2.fromOffset(150, 24), BackgroundTransparency = 1, ZIndex = 11, Parent = left }, { Kit.hlist(6, Enum.HorizontalAlignment.Left) })
	Kit.icon("hp", 24, { ZIndex = 11, Parent = hp })
	self.hpBar = Kit.bar({ Size = UDim2.fromOffset(120, 16), ZIndex = 11, Parent = hp }, C.hp)
	local gold = make("Frame", { Size = UDim2.fromOffset(86, 24), BackgroundTransparency = 1, ZIndex = 11, Active = true, Parent = left }, { Kit.hlist(6, Enum.HorizontalAlignment.Left) })
	Kit.icon("gold", 24, { ZIndex = 11, Parent = gold })
	self.goldText = Kit.title({ Size = UDim2.fromOffset(56, 20), TextSize = 12, TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Parent = gold })
	Kit.tooltip(gold, "<b>Gold</b>\nSpend it in shops.")
	self.floorText = Kit.text({ AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 20), TextSize = 18, TextColor3 = C.textDim, ZIndex = 11, Parent = left })

	local right = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S.gutter, 0, 0),
		Size = UDim2.new(0.4, -S.gutter, 1, -3),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = bar,
	}, { Kit.hlist(8, Enum.HorizontalAlignment.Right) })
	self.relicRow = make("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = right,
	}, { Kit.hlist(4, Enum.HorizontalAlignment.Right) })
	self.deckButton = Kit.button({ Size = UDim2.fromOffset(92, 32), Text = "Deck", ZIndex = 11, Parent = right }, function()
		self:openDeck()
	end, { textSize = 11 })
	Kit.button({ Size = UDim2.fromOffset(36, 32), Text = Theme.icons.settings.glyph, ZIndex = 11, Parent = right }, function()
		self:openSettings()
	end, { font = Theme.fonts.icon, textSize = 20 })
	return self
end

function Hud:setVisible(visible: boolean)
	self.root.Visible = visible
end

function Hud:setRun(run)
	self.run = run
	if not run then
		return
	end
	self.heroName.Text = string.upper(run.hero.name)
	self.hpBar.set(run.hero.hp, run.hero.maxHp)
	self.goldText.Text = tostring(run.gold)
	local progress = run.map.progress
	self.floorText.Text = `Act {run.act} · Floor {progress.row}/{progress.rows}`
	self.deckButton.Text = `Deck {#run.deck}`
	Kit.clear(self.relicRow)
	for _, relic in run.relics do
		local tile = make("Frame", {
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = C.panel,
			Active = true,
			ZIndex = 11,
			Parent = self.relicRow,
		})
		Kit.outline(Theme.rarityColors[relic.rarity] or C.gold, 2).Parent = tile
		Kit.icon(relic.id, 24, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextColor3 = Theme.rarityColors[relic.rarity] or C.gold,
			ZIndex = 12,
			Parent = tile,
		}, "relic")
		Kit.tooltip(tile, `<b>{relic.name}</b>\n{relic.text}`)
	end
end

-- HP moves during a fight before the run snapshot catches up.
function Hud:setHp(hp: number, maxHp: number)
	self.hpBar.set(hp, maxHp)
end

function Hud:openDeck()
	local run = self.run
	if not run then
		return
	end
	local modal = Kit.modal(self.modalLayer, `Deck ({#run.deck} cards)`, UDim2.new(0.9, 0, 0.85, 0))
	local grid = Kit.cardGrid(modal.body, { ZIndex = 33 })
	for _, card in run.deck do
		local widget = Kit.card(card, { ZIndex = 33, Parent = grid })
		if card.rarity then
			Kit.tooltip(widget, `{card.rarity} {card.type}`)
		end
	end
end

function Hud:openSettings()
	local modal = Kit.modal(self.modalLayer, "Settings", UDim2.fromOffset(460, 300))
	local list = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 33, Parent = modal.body }, { Kit.vlist(12) })
	Hud.assistToggles(list, self.assist, 33)
	Kit.button({ Size = UDim2.fromOffset(220, 40), Text = "Main menu", ZIndex = 33, Parent = list }, function()
		modal.close()
		self.callbacks.onMainMenu()
	end)
end

-- QTE accessibility toggles (design doc: wider windows, or "always Good").
function Hud.assistToggles(parent: Instance, assist: { wideWindows: boolean, alwaysGood: boolean }, z: number)
	local options = {
		{ key = "wideWindows", label = "Wider QTE windows", note = "From the next fight" },
		{ key = "alwaysGood", label = "QTEs always Good", note = "Never worse than Good" },
	}
	for _, option in options do
		local holder = make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = z, Parent = parent })
		local button: TextButton
		local function draw()
			if button then
				button:Destroy()
			end
			local on = (assist :: any)[option.key]
			button = Kit.button({
				Size = UDim2.fromScale(1, 1),
				Text = `{option.label}: {if on then "ON" else "OFF"}`,
				ZIndex = z,
				Parent = holder,
			}, function()
				(assist :: any)[option.key] = not on
				Remotes.SetQteAssist:FireServer(assist)
				draw()
			end, { color = if on then C.buttonGo else C.button, textSize = 11 })
			Kit.tooltip(button, option.note)
		end
		draw()
	end
end

return Hud
