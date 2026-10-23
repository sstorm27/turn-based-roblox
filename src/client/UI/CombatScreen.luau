--[[
	The combat screen: the hero on the left, up to three enemies on the right
	with their intents, and the hand, energy, piles and End Turn along the
	bottom. It draws the server's snapshot and turns its events into short
	effects (damage numbers, Block, grades); it never works out a result.

	Playing a card: tap a card to lift it, then tap it again to play it, or
	tap an enemy to play it on that enemy. Tooltips on hover or long-press.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Data.Content)
local Remotes = require(Shared.Net.Remotes)

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local C = Theme.colors
local S = Theme.sizes
local make = Kit.make

local HAND_HEIGHT = 214
local UNIT_WIDTH = 150

local CombatScreen = {}
CombatScreen.__index = CombatScreen

-- "DarkStrike" -> "Dark Strike"
local function spaced(id: string): string
	return (string.gsub(id, "(%l)(%u)", "%1 %2"))
end

local function statusColor(statusId: string): Color3
	local def = Content.Statuses[statusId]
	local kind = def and def.kind
	if kind == "Buff" then
		return C.buff
	elseif kind == "Debuff" or kind == "Control" then
		return C.debuff
	elseif kind == "DoT" then
		return C.hp
	end
	return C.textDim
end

local function statusTooltip(statusId: string, stacks: number): string
	local def = Content.Statuses[statusId]
	if not def then
		return `{statusId} {stacks}`
	end
	return `<b>{def.name} {stacks}</b>\n{def.text or ""}`
end

-- Non-attack intents get a word so they read without a tooltip.
local INTENT_WORDS = { Defend = "Block", Buff = "Buff", Debuff = "Debuff", Pollute = "Junk" }

local function intentLabel(intent): string
	if intent.damage then
		return if intent.hits and intent.hits > 1 then `{intent.damage}x{intent.hits}` else tostring(intent.damage)
	end
	return INTENT_WORDS[intent.type] or intent.type
end

local function intentTooltip(enemyName: string, intent): string
	local lines = { `<b>{enemyName}: {spaced(intent.moveId)}</b>` }
	if intent.damage then
		local hits = intent.hits or 1
		table.insert(lines, if hits > 1 then `Attacks for {intent.damage} damage {hits} times.` else `Attacks for {intent.damage} damage.`)
		if intent.type ~= "Attack" then
			table.insert(lines, Theme.intentText[intent.type] or "")
		end
	else
		table.insert(lines, Theme.intentText[intent.type] or "Does something.")
	end
	if intent.defenseQte then
		table.insert(lines, `Defend with a {intent.defenseQte.kind} QTE: Good halves a hit, Perfect avoids it.`)
	end
	return table.concat(lines, "\n")
end

-- Units ------------------------------------------------------------------------------

type UnitWidget = {
	root: Frame,
	sprite: TextButton,
	art: GuiObject?,
	artId: string?,
	marker: TextLabel,
	intent: Frame?,
	intentIcon: GuiObject?,
	intentType: string?,
	intentText: TextLabel?,
	intentQte: TextLabel?,
	hpBar: Kit.Bar,
	blockBadge: Frame,
	blockText: TextLabel,
	statusRow: Frame,
	unit: any,
}

local function newUnit(parent: Instance, isHero: boolean, onClick: () -> ()): UnitWidget
	local root = make("Frame", {
		Size = UDim2.fromOffset(UNIT_WIDTH, 250),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local widget = {} :: UnitWidget
	widget.root = root

	if not isHero then
		-- The intent is the one highlighted element on this screen.
		local intent = Kit.panel({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(96, 34),
			BackgroundColor3 = C.panelDark,
			Parent = root,
		})
		local stroke = intent:FindFirstChildOfClass("UIStroke") :: UIStroke
		stroke.Color = C.gold
		widget.intent = intent
		local intentText = Kit.title({
			Position = UDim2.fromOffset(34, 0),
			Size = UDim2.new(1, -38, 1, 0),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = intent,
		})
		make("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 8, Parent = intentText })
		widget.intentText = intentText
		widget.intentQte = Kit.chip("QTE", C.perfect, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(0, 16),
			TextSize = 14,
			ZIndex = 3,
			Parent = intent,
		})
		-- A slow bob so the eye finds it.
		TweenService:Create(
			intent,
			TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.new(0.5, 0, 0, 4) }
		):Play()
	end

	local marker = Kit.title({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(40, 16),
		Text = "▼",
		TextColor3 = C.gold,
		TextSize = 14,
		Visible = false,
		Parent = root,
	})
	widget.marker = marker

	local sprite = make("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(UNIT_WIDTH / 2, 60),
		Size = UDim2.fromOffset(110, 110),
		BackgroundColor3 = if isHero then Color3.fromRGB(58, 84, 120) else Color3.fromRGB(96, 52, 62),
		AutoButtonColor = false,
		Text = "",
		Parent = root,
	})
	Kit.outline().Parent = sprite
	sprite.Activated:Connect(onClick)
	widget.sprite = sprite
	-- The unit's initial stands in for a unit with no sprite.
	Kit.title({
		Name = "Initial",
		Size = UDim2.new(1, 0, 1, -18),
		TextSize = 40,
		TextColor3 = Kit.lighten(sprite.BackgroundColor3, 0.5),
		Parent = sprite,
	})
	Kit.text({
		Name = "UnitName",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.ink,
		TextSize = 16,
		Parent = sprite,
	})

	local hpBar = Kit.bar({
		Position = UDim2.fromOffset(20, 180),
		Size = UDim2.new(1, -20, 0, 16),
		Parent = root,
	}, C.hp)
	widget.hpBar = hpBar

	local blockBadge = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(-4, 188),
		Size = UDim2.fromOffset(30, 26),
		BackgroundColor3 = C.block,
		ZIndex = 3,
		Visible = false,
		Parent = root,
	})
	Kit.outline().Parent = blockBadge
	widget.blockBadge = blockBadge
	widget.blockText = Kit.title({
		Size = UDim2.fromScale(1, 1),
		TextSize = 11,
		TextColor3 = C.textDark,
		ZIndex = 4,
		Parent = blockBadge,
	})
	Kit.tooltip(blockBadge, "<b>Block</b>\nStops damage until your next turn.")

	local statusRow = make("Frame", {
		Position = UDim2.fromOffset(0, 204),
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		Parent = root,
	}, {
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Wraps = true,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.Name,
			Padding = UDim.new(0, 3),
		}),
	})
	widget.statusRow = statusRow
	return widget
end

local function updateUnit(widget: UnitWidget, unit, intent)
	local previous = widget.unit
	widget.unit = unit
	local nameLabel = widget.sprite:FindFirstChild("UnitName") :: TextLabel
	local initial = widget.sprite:FindFirstChild("Initial") :: TextLabel
	nameLabel.Text = unit.name
	if widget.artId ~= unit.defId then
		widget.artId = unit.defId
		if widget.art then
			widget.art:Destroy()
			widget.art = nil
		end
		-- 16x16 sprites at 5x, above the name strip.
		if unit.defId and Kit.hasArt(unit.defId) then
			widget.art = Kit.icon(unit.defId, 80, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 6),
				Parent = widget.sprite,
			})
		end
	end
	initial.Text = if widget.art then "" else string.sub(unit.name, 1, 1)
	widget.hpBar.set(unit.hp, unit.maxHp)
	widget.blockBadge.Visible = unit.block > 0
	widget.blockText.Text = tostring(unit.block)

	if not unit.alive then
		widget.root.Visible = true
		TweenService:Create(widget.sprite, TweenInfo.new(0.4), { BackgroundTransparency = 0.8 }):Play()
		initial.TextTransparency = 0.8
		if widget.art then
			Kit.setIconTransparency(widget.art, 0.8)
		end
		if widget.intent then
			widget.intent.Visible = false
		end
		widget.hpBar.frame.Visible = false
		widget.statusRow.Visible = false
		widget.marker.Visible = false
		return
	end

	local intentFrame, label, qteTag = widget.intent, widget.intentText, widget.intentQte
	if intentFrame and label and qteTag then
		intentFrame.Visible = intent ~= nil
		if intent then
			if widget.intentType ~= intent.type then
				-- Icons may be glyphs or sprites, so swap the whole icon.
				widget.intentType = intent.type
				if widget.intentIcon then
					widget.intentIcon:Destroy()
				end
				widget.intentIcon = Kit.icon(intent.type, 24, { Position = UDim2.fromOffset(7, 5), Parent = intentFrame })
			end
			label.Text = intentLabel(intent)
			qteTag.Visible = intent.defenseQte ~= nil
			if intent.defenseQte then
				qteTag.Text = intent.defenseQte.kind
			end
		end
	end

	-- Status chips: rebuild only when they changed.
	local changed = previous == nil
	if previous then
		for id, stacks in unit.statuses do
			if previous.statuses[id] ~= stacks then
				changed = true
			end
		end
		for id in previous.statuses do
			if unit.statuses[id] == nil then
				changed = true
			end
		end
	end
	if changed then
		Kit.clear(widget.statusRow)
		for id, stacks in unit.statuses do
			local def = Content.Statuses[id]
			-- Icon and stacks; the name is in the tooltip.
			local hasArt = Kit.hasArt(id)
			local chip = Kit.chip(if hasArt then tostring(stacks) else `{if def then def.name else id} {stacks}`, statusColor(id), {
				Name = id,
				Size = UDim2.fromOffset(0, 24),
				Active = true,
				Parent = widget.statusRow,
			})
			if hasArt then
				local pad = chip:FindFirstChildOfClass("UIPadding") :: UIPadding
				pad.PaddingLeft = UDim.new(0, 26)
				Kit.icon(id, 24, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -26, 0.5, 0), Parent = chip })
			end
			Kit.tooltip(chip, statusTooltip(id, stacks))
		end
	end
end

-- Screen -----------------------------------------------------------------------------

function CombatScreen.new(parent: Instance, callbacks: { onQteGraded: (qteId: string, grade: string) -> () })
	local self = setmetatable({}, CombatScreen)
	self.callbacks = callbacks
	self.snapshot = nil
	self.selectedUid = nil
	self.targetId = nil
	self.units = {}
	self.enemyKey = ""

	local root = make("Frame", {
		Name = "Combat",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.backdrop,
		Visible = false,
		Parent = parent,
	})
	self.root = root

	-- Battlefield: a simple floor band under the units.
	local field = make("Frame", {
		Position = UDim2.fromOffset(0, S.topBar),
		Size = UDim2.new(1, 0, 1, -(S.topBar + HAND_HEIGHT)),
		BackgroundTransparency = 1,
		Parent = root,
	})
	self.field = field
	make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0.32, 0),
		BackgroundColor3 = C.panelDark,
		Parent = field,
	})
	make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 0.68, 0),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = C.ink,
		Parent = field,
	})

	local heroSlot = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.2, 0.5),
		Size = UDim2.fromOffset(UNIT_WIDTH, 250),
		BackgroundTransparency = 1,
		Parent = field,
	})
	self.heroSlot = heroSlot

	local enemyRow = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S.gutter, 0.5, 0),
		Size = UDim2.new(0.62, 0, 0, 250),
		BackgroundTransparency = 1,
		Parent = field,
	}, { Kit.hlist(14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top) })
	self.enemyRow = enemyRow

	-- Bottom strip: energy and draw pile left, hand centre, discard and End Turn right.
	local bottom = make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, HAND_HEIGHT),
		BackgroundTransparency = 1,
		Parent = root,
	})

	local energy = Kit.panel({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S.gutter, 1, -64),
		Size = UDim2.fromOffset(84, 84),
		BackgroundColor3 = C.energy,
		Parent = bottom,
	})
	self.energyText = Kit.title({
		Size = UDim2.fromScale(1, 1),
		TextSize = 20,
		TextColor3 = C.textDark,
		Parent = energy,
	})
	Kit.tooltip(energy, "<b>Energy</b>\nCards cost energy. It refills at the start of your turn.")

	local function pile(iconName: string, position: UDim2, anchor: Vector2, tip: string)
		local chip = Kit.panel({
			AnchorPoint = anchor,
			Position = position,
			Size = UDim2.fromOffset(72, 34),
			BackgroundColor3 = C.panelLight,
			Active = true,
			Parent = bottom,
		}, { Kit.hlist(6) })
		Kit.icon(iconName, 24, { Parent = chip })
		local count = Kit.title({ Size = UDim2.fromOffset(30, 20), TextSize = 12, Parent = chip })
		Kit.tooltip(chip, tip)
		return count, chip
	end
	self.drawText = pile("draw", UDim2.new(0, S.gutter, 1, -14), Vector2.new(0, 1), "<b>Draw pile</b>\nYou draw 5 cards each turn.")
	self.discardText = pile(
		"discard",
		UDim2.new(1, -S.gutter, 1, -86),
		Vector2.new(1, 1),
		"<b>Discard pile</b>\nShuffled back into the draw pile when it runs out."
	)
	local exhaustText, exhaustChip =
		pile("exhaust", UDim2.new(1, -S.gutter - 78, 1, -86), Vector2.new(1, 1), "<b>Exhausted</b>\nRemoved for the rest of this fight.")
	self.exhaustText, self.exhaustChip = exhaustText, exhaustChip

	self.endTurn = nil
	self.endTurnHolder = make("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -S.gutter, 1, -14),
		Size = UDim2.fromOffset(150, 64),
		BackgroundTransparency = 1,
		Parent = bottom,
	})

	local hand = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -(2 * S.gutter + 2 * 180), 0, S.cardH + 24),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	self.hand = hand
	self.hint = Kit.text({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.new(1, 0, 0, 20),
		TextColor3 = C.textDim,
		TextSize = 18,
		Parent = hand,
	})
	hand:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_renderHand()
	end)

	-- Banner for turn changes and the fight's result.
	self.banner = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = root,
	})
	self.resultLayer = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 25,
		Visible = false,
		Parent = root,
	})
	return self
end

function CombatScreen:setVisible(visible: boolean)
	self.root.Visible = visible
	if not visible then
		Kit.hideTooltip()
	end
end

function CombatScreen:reset()
	self.snapshot = nil
	self.selectedUid = nil
	self.targetId = nil
	self.enemyKey = ""
	self.units = {}
	Kit.clear(self.heroSlot)
	Kit.clear(self.enemyRow)
	Kit.clear(self.hand)
	self.resultLayer.Visible = false
	Kit.clear(self.resultLayer)
end

-- Playing ----------------------------------------------------------------------------

function CombatScreen:_card(uid: string)
	for _, card in self.snapshot and self.snapshot.hand or {} do
		if card.uid == uid then
			return card
		end
	end
	return nil
end

function CombatScreen:_play(card, targetId: string?)
	self.selectedUid = nil
	Kit.hideTooltip()
	Remotes.PlayCard:FireServer(card.uid, if card.target == "Enemy" then targetId or self.targetId else nil)
	self:_renderHand()
	self:_renderTargets()
end

function CombatScreen:_tapCard(card)
	if not card.playable then
		local widget = self.cardWidgets and self.cardWidgets[card.uid]
		if widget then
			Kit.shake(widget)
		end
		local reason = if self.snapshot.phase ~= "PlayerTurn"
			then "Wait for your turn."
			elseif type(card.cost) == "number" and card.cost > self.snapshot.energy then "Not enough energy."
			else "You can't play that now."
		self:_toast(reason)
		return
	end
	if self.selectedUid == card.uid then
		self:_play(card)
	else
		self.selectedUid = card.uid
		self:_renderHand()
		self:_renderTargets()
	end
end

function CombatScreen:_tapUnit(unitId: string)
	local snapshot = self.snapshot
	if not snapshot then
		return
	end
	local enemy = nil
	for _, e in snapshot.enemies do
		if e.id == unitId and e.alive then
			enemy = e
		end
	end
	if not enemy then
		return
	end
	self.targetId = unitId
	local card = self.selectedUid and self:_card(self.selectedUid)
	if card and card.target == "Enemy" then
		self:_play(card, unitId)
	else
		self:_renderTargets()
	end
end

function CombatScreen:_toast(text: string)
	self.hint.Text = text
	self.hint.TextColor3 = C.hp
	local stamp = os.clock()
	self.toastAt = stamp
	task.delay(1.4, function()
		if self.toastAt == stamp then
			self:_renderHint()
		end
	end)
end

-- Rendering --------------------------------------------------------------------------

function CombatScreen:_renderHint()
	local snapshot = self.snapshot
	self.hint.TextColor3 = C.textDim
	if not snapshot then
		self.hint.Text = ""
	elseif snapshot.phase == "AwaitingQte" then
		self.hint.Text = ""
	elseif snapshot.phase ~= "PlayerTurn" then
		self.hint.Text = "Enemy turn"
	else
		local card = self.selectedUid and self:_card(self.selectedUid)
		if card and card.target == "Enemy" then
			self.hint.Text = "Tap an enemy, or the card again to play it"
		elseif card then
			self.hint.Text = "Tap the card again to play it"
		else
			self.hint.Text = "Tap a card"
		end
	end
end

function CombatScreen:_renderTargets()
	local snapshot = self.snapshot
	if not snapshot then
		return
	end
	local card = self.selectedUid and self:_card(self.selectedUid)
	local aiming = card ~= nil and card.target == "Enemy"
	local hitsAll = card ~= nil and card.target == "AllEnemies"
	for _, enemy in snapshot.enemies do
		local widget = self.units[enemy.id]
		if widget and enemy.alive then
			widget.marker.Visible = (aiming and enemy.id == self.targetId) or hitsAll
			local stroke = widget.sprite:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Color = if widget.marker.Visible then C.gold else C.ink
		end
	end
	self:_renderHint()
end

function CombatScreen:_renderHand()
	local snapshot = self.snapshot
	local hand = self.hand
	for _, child in hand:GetChildren() do
		if child:IsA("GuiObject") and child ~= self.hint then
			child:Destroy()
		end
	end
	self.cardWidgets = {}
	if not snapshot then
		return
	end
	local cards = snapshot.hand
	local count = #cards
	local width = hand.AbsoluteSize.X / Kit.uiScale
	local cw = S.cardW
	-- Cards sit side by side, overlapping when the hand is wider than the
	-- space, and fan out past 7 cards (design doc, "mobile first").
	local step = if count > 1 then math.min(cw + 10, (width - cw) / (count - 1)) else 0
	local total = cw + step * (count - 1)
	local left = (width - total) / 2
	local fan = count > 7
	for index, card in cards do
		local selected = card.uid == self.selectedUid
		local offsetFromMid = index - (count + 1) / 2
		local lift = if selected then 26 else 0
		local drop = if fan then math.abs(offsetFromMid) ^ 2 * 1.6 else 0
		local widget = Kit.card(card, {
			Position = UDim2.new(0, left + step * (index - 1), 1, -(S.cardH + lift) + drop),
			Rotation = if fan and not selected then offsetFromMid * 2.5 else 0,
			ZIndex = if selected then 5 else 2,
			Parent = hand,
		}, function()
			self:_tapCard(card)
		end, { enabled = card.playable })
		if not card.playable then
			-- Still tappable, to say why it can't be played.
			widget.Activated:Connect(function()
				self:_tapCard(card)
			end)
		end
		if selected then
			local stroke = widget:FindFirstChildOfClass("UIStroke") :: UIStroke
			stroke.Color = C.gold
		end
		self.cardWidgets[card.uid] = widget
	end
	self:_renderHint()
end

function CombatScreen:_renderEndTurn()
	local snapshot = self.snapshot
	local enabled = snapshot ~= nil and snapshot.phase == "PlayerTurn"
	if self.endTurnEnabled == enabled and self.endTurn then
		return
	end
	self.endTurnEnabled = enabled
	if self.endTurn then
		self.endTurn:Destroy()
	end
	self.endTurn = Kit.button({
		Size = UDim2.fromScale(1, 1),
		Text = "End Turn",
		Parent = self.endTurnHolder,
	}, function()
		self.selectedUid = nil
		Remotes.EndTurn:FireServer()
	end, { color = C.buttonPrimary, enabled = enabled, textSize = 14 })
end

function CombatScreen:_ensureUnits(snapshot)
	local ids = {}
	for _, enemy in snapshot.enemies do
		table.insert(ids, enemy.id)
	end
	local key = table.concat(ids, ",")
	if key == self.enemyKey and self.units.hero then
		return
	end
	self.enemyKey = key
	self.units = {}
	Kit.clear(self.heroSlot)
	Kit.clear(self.enemyRow)
	self.units.hero = newUnit(self.heroSlot, true, function() end)
	for _, enemy in snapshot.enemies do
		local widget = newUnit(self.enemyRow, false, function()
			self:_tapUnit(enemy.id)
		end)
		self.units[enemy.id] = widget
		Kit.tooltip(widget.intent :: Frame, function()
			local current = widget.unit
			for _, e in self.snapshot.enemies do
				if e.id == enemy.id and e.intent then
					return intentTooltip(current and current.name or enemy.name, e.intent)
				end
			end
			return ""
		end)
	end
end

function CombatScreen:render(snapshot)
	self.snapshot = snapshot
	self:_ensureUnits(snapshot)

	updateUnit(self.units.hero, snapshot.hero, nil)
	for _, enemy in snapshot.enemies do
		updateUnit(self.units[enemy.id], enemy, enemy.intent)
	end

	-- Keep a live target: the last tapped enemy, else the first one alive.
	local targetAlive = false
	for _, enemy in snapshot.enemies do
		if enemy.id == self.targetId and enemy.alive then
			targetAlive = true
		end
	end
	if not targetAlive then
		self.targetId = nil
		for _, enemy in snapshot.enemies do
			if enemy.alive then
				self.targetId = enemy.id
				break
			end
		end
	end
	local selected = self.selectedUid and self:_card(self.selectedUid)
	if not selected or not selected.playable then
		self.selectedUid = nil
	end

	self.energyText.Text = `{snapshot.energy}/{snapshot.maxEnergy}`
	self.drawText.Text = tostring(snapshot.drawCount)
	self.discardText.Text = tostring(snapshot.discardCount)
	self.exhaustText.Text = tostring(snapshot.exhaustCount)
	self.exhaustChip.Visible = snapshot.exhaustCount > 0

	self:_renderHand()
	self:_renderTargets()
	self:_renderEndTurn()
end

-- Events -----------------------------------------------------------------------------

function CombatScreen:_unitSprite(unitId: string?): GuiObject?
	local widget = unitId and self.units[unitId]
	return widget and widget.sprite
end

function CombatScreen:_bannerText(text: string, color: Color3)
	Kit.pop(self.banner, text, color, { size = 28, hold = 0.5, rise = 20 })
end

function CombatScreen:_playEvent(event)
	local t = event.type
	if t == "Damage" then
		local sprite = self:_unitSprite(event.targetId)
		if sprite then
			if event.amount > 0 then
				Kit.pop(sprite, `-{event.amount}`, C.hp, { size = 22 })
				Kit.shake(sprite)
			end
			if event.blocked and event.blocked > 0 then
				Kit.pop(sprite, `◈{event.blocked}`, C.block, { size = 14, rise = 24 })
			end
		end
	elseif t == "LoseHp" then
		local sprite = self:_unitSprite(event.targetId)
		if sprite then
			Kit.pop(sprite, `-{event.amount}`, C.debuff, { size = 18 })
		end
	elseif t == "Block" then
		local sprite = self:_unitSprite(event.targetId)
		if sprite and event.amount > 0 then
			Kit.pop(sprite, `+{event.amount} ◈`, C.block, { size = 16 })
		end
	elseif t == "Heal" then
		local sprite = self:_unitSprite(event.targetId)
		if sprite and event.amount > 0 then
			Kit.pop(sprite, `+{event.amount}`, C.heal, { size = 18 })
		end
	elseif t == "Dodged" then
		local sprite = self:_unitSprite(event.targetId)
		if sprite then
			Kit.pop(sprite, "DODGE!", C.perfect, { size = 16 })
		end
	elseif t == "StatusApplied" then
		local sprite = self:_unitSprite(event.targetId)
		local def = Content.Statuses[event.status]
		if sprite and def then
			Kit.pop(sprite, `{def.name} {event.stacks}`, statusColor(event.status), { size = 10, rise = 30 })
		end
	elseif t == "Detonated" then
		local sprite = self:_unitSprite(event.targetId)
		local def = Content.Statuses[event.status]
		if sprite and def then
			Kit.pop(sprite, `{string.upper(def.name)} BURST!`, C.energy, { size = 12, rise = 36 })
		end
	elseif t == "Siphoned" or t == "Transferred" then
		local sprite = self:_unitSprite(event.targetId)
		local def = Content.Statuses[event.status]
		if sprite and def then
			local word = if t == "Siphoned" then "STOLEN" else "CURSED"
			Kit.pop(sprite, `{def.name} {word}`, statusColor(event.status), { size = 10, rise = 36 })
		end
	elseif t == "EnemyMove" then
		local sprite = self:_unitSprite(event.unitId)
		if sprite then
			Kit.pop(sprite, spaced(event.moveId), C.text, { size = 10, rise = 30 })
		end
	elseif t == "Stunned" then
		local sprite = self:_unitSprite(event.unitId)
		if sprite then
			Kit.pop(sprite, "STUNNED", C.debuff, { size = 12 })
		end
	elseif t == "QteGraded" then
		self.callbacks.onQteGraded(event.qteId, event.grade)
	elseif t == "TurnStarted" then
		self:_bannerText("YOUR TURN", C.gold)
	elseif t == "TurnEnded" then
		self:_bannerText("ENEMY TURN", C.hp)
	elseif t == "Rejected" then
		self:_toast(spaced(tostring(event.reason)))
	elseif t == "CombatEnded" then
		self:_bannerText(if event.result == "Won" then "VICTORY!" else "DEFEAT", if event.result == "Won" then C.gold else C.hp)
	end
end

-- Effects are staggered a little so a burst of events reads in order.
function CombatScreen:playEvents(events)
	local delay = 0
	for _, event in events do
		if event.type == "QteGraded" or event.type == "Rejected" then
			self:_playEvent(event)
		else
			task.delay(delay, function()
				self:_playEvent(event)
			end)
			delay = math.min(delay + 0.1, 1.2)
		end
	end
end

-- After a practice fight: a result panel with a way out.
function CombatScreen:showResult(result: string, buttons: { { text: string, onClick: () -> () } })
	local layer = self.resultLayer
	Kit.clear(layer)
	layer.Visible = true
	local panel = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(360, 170),
		ZIndex = 26,
		Parent = layer,
	})
	Kit.title({
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 30),
		Text = if result == "Won" then "VICTORY!" else "DEFEAT",
		TextColor3 = if result == "Won" then C.gold else C.hp,
		TextSize = 22,
		ZIndex = 27,
		Parent = panel,
	})
	local row = make("Frame", {
		Position = UDim2.fromOffset(0, 90),
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundTransparency = 1,
		ZIndex = 27,
		Parent = panel,
	}, { Kit.hlist(12) })
	for _, b in buttons do
		Kit.button({ Size = UDim2.fromOffset(150, 44), Text = b.text, ZIndex = 27, Parent = row }, b.onClick)
	end
end

return CombatScreen
