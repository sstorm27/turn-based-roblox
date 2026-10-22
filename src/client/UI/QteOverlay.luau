--[[
	The QTE overlay: one widget per kind, drawn from the challenge the server
	sent (QteStart). It records raw input times relative to when it opened
	and returns them with QteResult; the server grades them. The grade comes
	back as a QteGraded combat event and pops up here ("PERFECT!").

		Timing    a marker sweeps a bar; tap in the gold band (centre = Perfect)
		Sequence  enter the shown arrows in order (keys or on-screen buttons)
		Mash      tap as often as you can before the timer runs out
		Hold      hold to fill the bar, release inside the gold zone
		Trace     hold and swipe through the dots in order

	Tap or click anywhere, or press Space. Sequence also takes the arrow keys
	and WASD.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local C = Theme.colors
local make = Kit.make

local AREA_W, AREA_H = 420, 220

local ARROW_GLYPH = { Up = "↑", Down = "↓", Left = "←", Right = "→" }
local KEY_TO_SYMBOL = {
	[Enum.KeyCode.Up] = "Up",
	[Enum.KeyCode.W] = "Up",
	[Enum.KeyCode.Down] = "Down",
	[Enum.KeyCode.S] = "Down",
	[Enum.KeyCode.Left] = "Left",
	[Enum.KeyCode.A] = "Left",
	[Enum.KeyCode.Right] = "Right",
	[Enum.KeyCode.D] = "Right",
}

local GRADE_STYLE = {
	Perfect = { text = "PERFECT!", color = C.perfect, size = 40 },
	Good = { text = "GOOD", color = C.good, size = 30 },
	Miss = { text = "MISS", color = C.miss, size = 26 },
}

local QteOverlay = {}
QteOverlay.__index = QteOverlay

function QteOverlay.new(parent: Instance)
	local self = setmetatable({}, QteOverlay)
	self.active = nil
	self.handlers = nil
	self.conns = {}

	-- The whole screen is the tap target.
	local root = make("TextButton", {
		Name = "Qte",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 40,
		Parent = parent,
	})
	self.root = root

	local panel = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(AREA_W + 40, AREA_H + 110),
		ZIndex = 41,
		Parent = root,
	})
	self.panel = panel
	local stroke = panel:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = C.gold

	self.heading = Kit.title({
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 18,
		TextColor3 = C.gold,
		ZIndex = 42,
		Parent = panel,
	})
	self.help = Kit.text({
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 18,
		TextColor3 = C.textDim,
		ZIndex = 42,
		Parent = panel,
	})
	self.area = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 68),
		Size = UDim2.fromOffset(AREA_W, AREA_H),
		BackgroundTransparency = 1,
		ZIndex = 42,
		Parent = panel,
	})
	-- Time left until the deadline.
	local timerBack = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -40, 0, 6),
		BackgroundColor3 = C.panelDark,
		ZIndex = 42,
		Parent = panel,
	})
	self.timer = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.textDim,
		ZIndex = 43,
		Parent = timerBack,
	})

	root.MouseButton1Down:Connect(function()
		self:_press()
	end)
	root.MouseButton1Up:Connect(function()
		self:_release()
	end)
	UserInputService.InputBegan:Connect(function(input)
		if not self:_live() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			self:_press()
		elseif self.handlers.key and KEY_TO_SYMBOL[input.KeyCode] then
			self.handlers.key(KEY_TO_SYMBOL[input.KeyCode])
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not self:_live() then
			return
		end
		local pointer = input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		if input.KeyCode == Enum.KeyCode.Space or pointer then
			self:_release()
		end
	end)
	return self
end

function QteOverlay:_live(): boolean
	return self.active ~= nil and not self.active.finished and self.handlers ~= nil
end

function QteOverlay:_press()
	if self:_live() and self.handlers.press then
		self.handlers.press()
	end
end

function QteOverlay:_release()
	if self:_live() and self.handlers.release then
		self.handlers.release()
	end
end

function QteOverlay:_now(): number
	return if self.active then os.clock() - self.active.startedAt else 0
end

function QteOverlay:_input(value)
	table.insert(self.active.inputs, value)
end

function QteOverlay:_onFrame(fn: (number) -> ())
	table.insert(self.conns, RunService.RenderStepped:Connect(function()
		if self.active and not self.active.finished then
			fn(self:_now())
		end
	end))
end

function QteOverlay:_disconnect()
	for _, conn in self.conns do
		conn:Disconnect()
	end
	self.conns = {}
end

function QteOverlay:finish()
	local active = self.active
	if not active or active.finished then
		return
	end
	active.finished = true
	self:_disconnect()
	Remotes.QteResult:FireServer(active.challenge.qteId, active.inputs)
	-- If the grade never arrives (it normally does at once), close anyway.
	task.delay(1.2, function()
		if self.active == active then
			self:_close()
		end
	end)
end

function QteOverlay:_close()
	self.active = nil
	self.handlers = nil
	self:_disconnect()
	self.root.Visible = false
end

-- Called for each QteGraded combat event.
function QteOverlay:showGrade(qteId: string, grade: string)
	local style = GRADE_STYLE[grade] or GRADE_STYLE.Miss
	local active = self.active
	local host = if active and active.challenge.qteId == qteId then self.panel else self.root.Parent :: GuiObject
	Kit.pop(host, style.text, style.color, { size = style.size, hold = 0.45, rise = 30 })
	if active and active.challenge.qteId == qteId then
		task.delay(0.55, function()
			if self.active == active then
				self:_close()
			end
		end)
	end
end

-- Widgets ----------------------------------------------------------------------------

local kinds = {}

local function block(parent: Instance, props: { [string]: any })
	props.Parent = parent
	props.ZIndex = props.ZIndex or 43
	return make("Frame", props)
end

function kinds.Timing(self, p, deadline: number)
	local area = self.area
	local bar = block(area, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = C.panelDark,
	})
	Kit.outline().Parent = bar
	-- The marker sweeps the bar from 0 to 1 over the whole QTE, so the band
	-- sits where the marker is at hitTime and is as wide as the windows.
	local center = p.hitTime / deadline
	local good = p.goodWindow / deadline
	local perfect = p.perfectWindow / deadline
	block(bar, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(center, 0),
		Size = UDim2.fromScale(good * 2, 1),
		BackgroundColor3 = Kit.darken(C.gold, 0.3),
		ZIndex = 44,
	})
	block(bar, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(center, 0),
		Size = UDim2.new(perfect * 2, 2, 1, 0),
		BackgroundColor3 = C.goldLight,
		ZIndex = 45,
	})
	local marker = block(bar, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 8, 1, 16),
		BackgroundColor3 = C.text,
		ZIndex = 46,
	})
	Kit.outline(C.ink, 2).Parent = marker
	self:_onFrame(function(t)
		marker.Position = UDim2.fromScale(math.clamp(t / deadline, 0, 1), 0.5)
	end)
	return {
		press = function()
			self:_input(self:_now())
			self:finish()
		end,
	}
end

function kinds.Sequence(self, p)
	local area = self.area
	local count = #p.symbols
	local tileRow = block(area, {
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundTransparency = 1,
	})
	Kit.hlist(10).Parent = tileRow
	local tiles = {}
	for i, symbol in p.symbols do
		local tile = make("Frame", {
			Size = UDim2.fromOffset(56, 56),
			BackgroundColor3 = if i == 1 then C.panelLight else C.panelDark,
			ZIndex = 44,
			Parent = tileRow,
		})
		Kit.outline(if i == 1 then C.gold else C.ink).Parent = tile
		Kit.text({
			Size = UDim2.fromScale(1, 1),
			Text = ARROW_GLYPH[symbol],
			FontFace = Theme.fonts.icon,
			TextSize = 34,
			ZIndex = 45,
			Parent = tile,
		})
		tiles[i] = tile
	end
	local function enter(symbol: string)
		local active = self.active
		if not active or active.finished then
			return
		end
		self:_input({ symbol, self:_now() })
		local done = #active.inputs
		local tile = tiles[done]
		if tile then
			tile.BackgroundColor3 = if p.symbols[done] == symbol then C.gold else C.hp
			;(tile:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = C.ink
			local nextTile = tiles[done + 1]
			if nextTile then
				nextTile.BackgroundColor3 = C.panelLight
				;(nextTile:FindFirstChildOfClass("UIStroke") :: UIStroke).Color = C.gold
			end
		end
		if done >= count then
			self:finish()
		end
	end
	-- On-screen arrows for touch.
	local buttons = block(area, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundTransparency = 1,
	})
	Kit.hlist(14).Parent = buttons
	for _, symbol in { "Left", "Up", "Down", "Right" } do
		Kit.button({ Size = UDim2.fromOffset(76, 72), Text = ARROW_GLYPH[symbol], ZIndex = 44, Parent = buttons }, function()
			enter(symbol)
		end, { font = Theme.fonts.icon, textSize = 34 })
	end
	return { key = enter }
end

function kinds.Mash(self, p)
	local area = self.area
	local counter = Kit.title({
		Size = UDim2.new(1, 0, 0, 90),
		Text = "0",
		TextSize = 48,
		ZIndex = 44,
		Parent = area,
	})
	-- Progress toward the Perfect count, with ticks at Good and Perfect.
	local top = p.perfectTaps * 1.15
	local bar = block(area, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = C.panelDark,
	})
	Kit.outline().Parent = bar
	local fill = block(bar, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.energy, ZIndex = 44 })
	for _, mark in { { p.goodTaps, C.good, "GOOD" }, { p.perfectTaps, C.perfect, "PERFECT" } } do
		local x = mark[1] / top
		block(bar, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.new(0, 4, 1, 8),
			BackgroundColor3 = mark[2],
			ZIndex = 45,
		})
		Kit.text({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(x, 0, 1, 10),
			Size = UDim2.fromOffset(80, 16),
			Text = mark[3],
			TextColor3 = mark[2],
			TextSize = 16,
			ZIndex = 45,
			Parent = bar,
		})
	end
	task.delay(p.duration, function()
		if self.active and self.handlers == self.mashHandlers then
			self:finish()
		end
	end)
	local handlers = {
		press = function()
			self:_input(self:_now())
			local n = #self.active.inputs
			counter.Text = tostring(n)
			fill.Size = UDim2.fromScale(math.clamp(n / top, 0, 1), 1)
			fill.BackgroundColor3 = if n >= p.perfectTaps then C.perfect elseif n >= p.goodTaps then C.good else C.energy
		end,
	}
	self.mashHandlers = handlers
	return handlers
end

function kinds.Hold(self, p)
	local area = self.area
	local bar = block(area, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = C.panelDark,
	})
	Kit.outline().Parent = bar
	block(bar, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(p.zoneCenter, 0),
		Size = UDim2.fromScale(p.zoneWidth, 1),
		BackgroundColor3 = Kit.darken(C.gold, 0.3),
		ZIndex = 44,
	})
	block(bar, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(p.zoneCenter, 0),
		Size = UDim2.new(p.perfectWidth, 2, 1, 0),
		BackgroundColor3 = C.goldLight,
		ZIndex = 45,
	})
	local fill = block(bar, {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.energy,
		BackgroundTransparency = 0.25,
		ZIndex = 46,
	})
	local prompt = Kit.title({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.4, 40),
		Size = UDim2.fromOffset(300, 30),
		Text = "HOLD",
		TextSize = 20,
		ZIndex = 44,
		Parent = area,
	})
	local pressedAt: number? = nil
	self:_onFrame(function(t)
		if pressedAt then
			fill.Size = UDim2.fromScale(math.clamp((t - pressedAt) / p.fillTime, 0, 1), 1)
		end
	end)
	return {
		press = function()
			if not pressedAt then
				pressedAt = self:_now()
				self:_input(pressedAt)
				prompt.Text = "RELEASE IN THE GOLD"
			end
		end,
		release = function()
			if pressedAt then
				self:_input(self:_now())
				self:finish()
			end
		end,
	}
end

function kinds.Trace(self, p)
	-- Path points are in 0..1 of a square, so the play area is square.
	local side = AREA_H
	local box = block(self.area, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(side, side),
		BackgroundColor3 = C.panelDark,
	})
	Kit.outline().Parent = box
	-- Lines between the dots.
	for i = 1, #p.path - 1 do
		local a, b = p.path[i], p.path[i + 1]
		local ax, ay, bx, by = a[1] * side, a[2] * side, b[1] * side, b[2] * side
		local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
		block(box, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2),
			Size = UDim2.fromOffset(length, 4),
			Rotation = math.deg(math.atan2(by - ay, bx - ax)),
			BackgroundColor3 = C.panelLight,
			ZIndex = 44,
		})
	end
	-- Each dot is drawn at the size that still counts as on the path.
	local dotSize = math.max(18, p.radius * 2 * side)
	local dots = {}
	for i, point in p.path do
		local dot = block(box, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(point[1], point[2]),
			Size = UDim2.fromOffset(dotSize, dotSize),
			BackgroundColor3 = if i == 1 then C.gold else C.panelLight,
			BackgroundTransparency = 0.2,
			ZIndex = 45,
		})
		make("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = dot })
		Kit.title({
			Size = UDim2.fromScale(1, 1),
			Text = tostring(i),
			TextSize = 12,
			TextColor3 = C.textDark,
			ZIndex = 46,
			Parent = dot,
		})
		dots[i] = dot
	end
	local tracing = false
	local reached = 1
	self:_onFrame(function(t)
		if not tracing or #self.active.inputs >= 200 then
			return
		end
		local mouse = UserInputService:GetMouseLocation()
		local pos, size = box.AbsolutePosition, box.AbsoluteSize
		-- Our ScreenGuis ignore the GUI inset, so these share one origin.
		local x, y = (mouse.X - pos.X) / size.X, (mouse.Y - pos.Y) / size.Y
		self:_input({ x, y, t })
		-- Light up dots as the finger passes them (display only).
		local nextPoint = p.path[reached]
		if nextPoint and math.sqrt((x - nextPoint[1]) ^ 2 + (y - nextPoint[2]) ^ 2) <= p.radius then
			dots[reached].BackgroundColor3 = C.perfect
			reached += 1
			if dots[reached] then
				dots[reached].BackgroundColor3 = C.gold
			end
		end
		if #self.active.inputs % 2 == 0 then
			local trail = block(box, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(x, y),
				Size = UDim2.fromOffset(6, 6),
				BackgroundColor3 = C.goldLight,
				ZIndex = 47,
			})
			TweenService:Create(trail, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			task.delay(0.5, function()
				trail:Destroy()
			end)
		end
	end)
	return {
		press = function()
			tracing = true
		end,
		release = function()
			if tracing then
				self:finish()
			end
		end,
	}
end

function QteOverlay:start(challenge)
	self:_disconnect()
	Kit.clear(self.area)
	Kit.hideTooltip()
	local active = { challenge = challenge, startedAt = os.clock(), inputs = {}, finished = false }
	self.active = active
	self.root.Visible = true
	self.heading.Text = if challenge.source == "Defense" then "DEFEND!" else "EMPOWER!"
	self.heading.TextColor3 = if challenge.source == "Defense" then C.hp else C.gold
	self.help.Text = Theme.qteHelp[challenge.kind] or ""

	local build = kinds[challenge.kind]
	self.handlers = if build then build(self, challenge.params, challenge.deadline) else {}

	self.timer.Size = UDim2.fromScale(1, 1)
	TweenService:Create(self.timer, TweenInfo.new(challenge.deadline, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(0, 1),
	}):Play()
	-- The server grades a missing result as a Miss: send what we have at the deadline.
	task.delay(challenge.deadline, function()
		if self.active == active then
			self:finish()
		end
	end)
end

return QteOverlay
