--[[
	Bare-bones debug screen for the combat prototype: enough to play a fight
	and every QTE type. The real UI comes later; this one only draws what the
	server sends and reports what the player did. It never computes results.

	Controls
		Click an enemy to target it, click a card to play it, End Turn.
		QTEs: click / tap the QTE box or press Space. Sequence also takes the
		arrow keys or WASD. Trace: hold and drag through the dots in order.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)

local player = Players.LocalPlayer

-- Layout helpers ---------------------------------------------------------------

local function make(className: string, props: { [string]: any }, children: { Instance }?)
	local inst = Instance.new(className)
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

local function button(props)
	props.BackgroundColor3 = props.BackgroundColor3 or Color3.fromRGB(45, 50, 64)
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.Font = props.Font or Enum.Font.GothamMedium
	props.TextSize = props.TextSize or 14
	props.TextWrapped = true
	props.AutoButtonColor = true
	return make("TextButton", props, { corner() })
end

local gui = make("ScreenGui", {
	Name = "CombatDebug",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	Parent = player:WaitForChild("PlayerGui"),
})

local root = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(20, 22, 30),
	Parent = gui,
})

local heroLabel = label({
	Size = UDim2.new(1, -24, 0, 40),
	Position = UDim2.fromOffset(12, 8),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 16,
	Text = "Pick a fight to start.",
	Parent = root,
})

local startRow = make("Frame", {
	Size = UDim2.new(1, -24, 0, 32),
	Position = UDim2.fromOffset(12, 50),
	BackgroundTransparency = 1,
	Parent = root,
}, { make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }) })

for _, encounterId in { "Prototype", "Slimes", "Ambush" } do
	local b = button({ Size = UDim2.fromOffset(110, 32), Text = `Fight: {encounterId}`, Parent = startRow })
	b.Activated:Connect(function()
		Remotes.StartCombat:FireServer(encounterId)
	end)
end

local enemyRow = make("Frame", {
	Size = UDim2.new(1, -24, 0, 130),
	Position = UDim2.fromOffset(12, 92),
	BackgroundTransparency = 1,
	Parent = root,
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
	}),
})

local logLabel = label({
	Size = UDim2.new(1, -24, 0, 90),
	Position = UDim2.fromOffset(12, 230),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextColor3 = Color3.fromRGB(170, 175, 190),
	TextSize = 13,
	Text = "",
	Parent = root,
})

local handRow = make("Frame", {
	Size = UDim2.new(1, -150, 0, 140),
	Position = UDim2.new(0, 12, 1, -152),
	BackgroundTransparency = 1,
	Parent = root,
}, {
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }),
})

local endTurnButton = button({
	Size = UDim2.fromOffset(120, 56),
	Position = UDim2.new(1, -132, 1, -68),
	BackgroundColor3 = Color3.fromRGB(180, 120, 40),
	Text = "End Turn",
	TextSize = 18,
	Parent = root,
})
endTurnButton.Activated:Connect(function()
	Remotes.EndTurn:FireServer()
end)

-- State rendering --------------------------------------------------------------

local snapshot = nil
local selectedTarget: string? = nil
local logLines: { string } = {}

local function statusText(statuses): string
	local parts = {}
	for id, stacks in statuses do
		table.insert(parts, `{id} {stacks}`)
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function intentText(intent): string
	if not intent then
		return ""
	end
	local text = intent.type
	if intent.damage then
		text ..= intent.hits > 1 and ` {intent.damage}x{intent.hits}` or ` {intent.damage}`
	end
	if intent.defenseQte then
		text ..= ` [QTE {intent.defenseQte.kind}]`
	end
	return text
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function render()
	if not snapshot then
		return
	end
	local hero = snapshot.hero
	heroLabel.Text = `{hero.name}  HP {hero.hp}/{hero.maxHp}  Block {hero.block}  Energy {snapshot.energy}/{snapshot.maxEnergy}`
		.. `  Turn {snapshot.turn}  [{snapshot.phase}]  Draw {snapshot.drawCount}  Discard {snapshot.discardCount}`
		.. `  Exhaust {snapshot.exhaustCount}\n{statusText(hero.statuses)}`

	if selectedTarget then
		local stillAlive = false
		for _, enemy in snapshot.enemies do
			if enemy.id == selectedTarget and enemy.alive then
				stillAlive = true
			end
		end
		if not stillAlive then
			selectedTarget = nil
		end
	end
	if not selectedTarget then
		for _, enemy in snapshot.enemies do
			if enemy.alive then
				selectedTarget = enemy.id
				break
			end
		end
	end

	clear(enemyRow)
	for _, enemy in snapshot.enemies do
		local selected = enemy.id == selectedTarget
		local b = button({
			Size = UDim2.fromOffset(200, 120),
			BackgroundColor3 = if not enemy.alive
				then Color3.fromRGB(40, 40, 40)
				elseif selected then Color3.fromRGB(120, 50, 50)
				else Color3.fromRGB(70, 40, 40),
			Text = if enemy.alive
				then `{enemy.name}\nHP {enemy.hp}/{enemy.maxHp}  Block {enemy.block}\n{statusText(enemy.statuses)}\n> {intentText(enemy.intent)}`
				else `{enemy.name}\n(dead)`,
			Parent = enemyRow,
		})
		b.Activated:Connect(function()
			selectedTarget = enemy.id
			render()
		end)
	end

	clear(handRow)
	for _, card in snapshot.hand do
		local qte = card.qte and `\n[QTE {card.qte.kind} {card.qte.difficulty}]` or ""
		local b = button({
			Size = UDim2.fromOffset(110, 140),
			BackgroundColor3 = if card.playable then Color3.fromRGB(50, 70, 110) else Color3.fromRGB(45, 45, 55),
			Text = `({card.cost}) {card.name}\n{card.text}{qte}`,
			TextSize = 12,
			Parent = handRow,
		})
		b.Activated:Connect(function()
			Remotes.PlayCard:FireServer(card.uid, if card.target == "Enemy" then selectedTarget else nil)
		end)
	end
end

local function describeEvent(event): string?
	local t = event.type
	if t == "CardPlayed" then
		return `Played {event.cardId}`
	elseif t == "Damage" then
		return `{event.targetId} took {event.amount} ({event.blocked} blocked)`
	elseif t == "Dodged" then
		return `Dodged! (prevented {event.prevented})`
	elseif t == "QteGraded" then
		return `QTE: {event.grade}`
	elseif t == "EnemyMove" then
		return `{event.unitId} used {event.moveId}`
	elseif t == "StatusApplied" then
		return `{event.targetId} +{event.stacks} {event.status}`
	elseif t == "Died" then
		return `{event.unitId} died`
	elseif t == "CombatEnded" then
		return `Combat over: {event.result}`
	elseif t == "Rejected" then
		return `Rejected: {event.reason}`
	end
	return nil
end

Remotes.StateUpdate.OnClientEvent:Connect(function(newSnapshot, events)
	snapshot = newSnapshot
	for _, event in events do
		local line = describeEvent(event)
		if line then
			table.insert(logLines, line)
		end
	end
	while #logLines > 6 do
		table.remove(logLines, 1)
	end
	logLabel.Text = table.concat(logLines, "\n")
	render()
end)

-- QTE overlay ------------------------------------------------------------------

local overlay = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.4,
	Visible = false,
	ZIndex = 10,
	Parent = gui,
})

local qteTitle = label({
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.new(0, 0, 0.5, -230),
	TextSize = 22,
	Font = Enum.Font.GothamBold,
	ZIndex = 11,
	Parent = overlay,
})

-- The play area: everything a QTE draws goes in here (0..1 coordinates).
local box = make("TextButton", {
	Size = UDim2.fromOffset(360, 360),
	Position = UDim2.new(0.5, -180, 0.5, -180),
	BackgroundColor3 = Color3.fromRGB(30, 34, 46),
	Text = "",
	AutoButtonColor = false,
	ZIndex = 11,
	Parent = overlay,
}, { corner(12) })

local active = nil -- the running QTE: { challenge, startedAt, inputs, finished, ... }
local renderConn: RBXScriptConnection? = nil

local function now(): number
	return active and (os.clock() - active.startedAt) or 0
end

local function finish()
	if not active or active.finished then
		return
	end
	active.finished = true
	Remotes.QteResult:FireServer(active.challenge.qteId, active.inputs)
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	task.delay(0.25, function()
		if active and active.finished then
			overlay.Visible = false
			active = nil
		end
	end)
end

local function dot(x: number, y: number, size: number, color: Color3, z: number?)
	return make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		ZIndex = z or 12,
		Parent = box,
	}, { corner(size) })
end

local function boxPoint(screen: Vector2): (number, number)
	local pos, size = box.AbsolutePosition, box.AbsoluteSize
	return (screen.X - pos.X) / size.X, (screen.Y - pos.Y) / size.Y
end

-- Per-kind setup: draws the QTE and wires its inputs.
local kinds = {}

function kinds.Timing(p)
	qteTitle.Text = "Tap when the ring meets the circle"
	dot(0.5, 0.5, 70, Color3.fromRGB(80, 200, 120))
	local ring = dot(0.5, 0.5, 300, Color3.fromRGB(240, 240, 240), 13)
	ring.BackgroundTransparency = 0.7
	renderConn = RunService.RenderStepped:Connect(function()
		local progress = math.clamp(now() / p.hitTime, 0, 2)
		local size = 300 - (300 - 70) * progress
		ring.Size = UDim2.fromOffset(math.max(size, 0), math.max(size, 0))
	end)
	return {
		press = function()
			table.insert(active.inputs, now())
			finish()
		end,
	}
end

local ARROWS = { Up = "^", Down = "v", Left = "<", Right = ">" }
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

function kinds.Sequence(p)
	qteTitle.Text = "Enter the arrows in order"
	local text = {}
	for _, symbol in p.symbols do
		table.insert(text, ARROWS[symbol])
	end
	local shown = label({
		Size = UDim2.new(1, 0, 0, 80),
		Position = UDim2.fromScale(0, 0.1),
		Text = table.concat(text, "  "),
		TextSize = 40,
		Font = Enum.Font.GothamBold,
		ZIndex = 12,
		Parent = box,
	})
	local function enter(symbol)
		table.insert(active.inputs, { symbol, now() })
		local done = #active.inputs
		local parts = {}
		for i, s in p.symbols do
			table.insert(parts, i <= done and "*" or ARROWS[s])
		end
		shown.Text = table.concat(parts, "  ")
		if done >= #p.symbols then
			finish()
		end
	end
	-- On-screen arrows for touch.
	for i, symbol in { "Left", "Up", "Down", "Right" } do
		local b = button({
			Size = UDim2.fromOffset(70, 70),
			Position = UDim2.new(0, 10 + (i - 1) * 88, 1, -90),
			Text = ARROWS[symbol],
			TextSize = 28,
			ZIndex = 12,
			Parent = box,
		})
		b.Activated:Connect(function()
			enter(symbol)
		end)
	end
	return {
		key = function(keyCode)
			local symbol = KEY_TO_SYMBOL[keyCode]
			if symbol then
				enter(symbol)
			end
		end,
	}
end

function kinds.Mash(p)
	qteTitle.Text = `Tap fast! Good {p.goodTaps}, Perfect {p.perfectTaps}`
	local counter = label({
		Size = UDim2.fromScale(1, 1),
		Text = "0",
		TextSize = 60,
		Font = Enum.Font.GothamBold,
		ZIndex = 12,
		Parent = box,
	})
	task.delay(p.duration, finish)
	return {
		press = function()
			table.insert(active.inputs, now())
			counter.Text = tostring(#active.inputs)
		end,
	}
end

function kinds.Hold(p)
	qteTitle.Text = "Hold, release inside the zone"
	local bar = make("Frame", {
		Size = UDim2.fromScale(0.8, 0.12),
		Position = UDim2.fromScale(0.1, 0.44),
		BackgroundColor3 = Color3.fromRGB(60, 60, 70),
		ZIndex = 12,
		Parent = box,
	})
	make("Frame", {
		Size = UDim2.fromScale(p.zoneWidth, 1),
		Position = UDim2.fromScale(p.zoneCenter - p.zoneWidth / 2, 0),
		BackgroundColor3 = Color3.fromRGB(80, 200, 120),
		BackgroundTransparency = 0.3,
		ZIndex = 13,
		Parent = bar,
	})
	local fill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(240, 200, 80),
		BackgroundTransparency = 0.2,
		ZIndex = 14,
		Parent = bar,
	})
	local pressedAt: number? = nil
	renderConn = RunService.RenderStepped:Connect(function()
		if pressedAt then
			fill.Size = UDim2.fromScale(math.clamp((now() - pressedAt) / p.fillTime, 0, 1), 1)
		end
	end)
	return {
		press = function()
			if not pressedAt then
				pressedAt = now()
				table.insert(active.inputs, pressedAt)
			end
		end,
		release = function()
			if pressedAt then
				table.insert(active.inputs, now())
				finish()
			end
		end,
	}
end

function kinds.Trace(p)
	qteTitle.Text = "Hold and swipe through the dots in order"
	for i, point in p.path do
		dot(point[1], point[2], 34, if i == 1 then Color3.fromRGB(80, 200, 120) else Color3.fromRGB(200, 200, 220))
	end
	local tracing = false
	renderConn = RunService.RenderStepped:Connect(function()
		if tracing and #active.inputs < 200 then
			local x, y = boxPoint(UserInputService:GetMouseLocation())
			table.insert(active.inputs, { x, y, now() })
		end
	end)
	return {
		press = function()
			tracing = true
		end,
		release = function()
			if tracing then
				finish()
			end
		end,
	}
end

local handlers = nil

Remotes.QteStart.OnClientEvent:Connect(function(challenge)
	clear(box)
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	active = { challenge = challenge, startedAt = os.clock(), inputs = {}, finished = false }
	overlay.Visible = true
	handlers = kinds[challenge.kind](challenge.params)
	local current = active
	-- The server grades a missing result as a Miss; send what we have at the deadline.
	task.delay(challenge.deadline, function()
		if active == current then
			finish()
		end
	end)
end)

box.MouseButton1Down:Connect(function()
	if active and not active.finished and handlers and handlers.press then
		handlers.press()
	end
end)
box.MouseButton1Up:Connect(function()
	if active and not active.finished and handlers and handlers.release then
		handlers.release()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not active or active.finished or not handlers then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space and handlers.press then
		handlers.press()
	elseif handlers.key then
		handlers.key(input.KeyCode)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not active or active.finished or not handlers then
		return
	end
	local mouseUp = input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	if (input.KeyCode == Enum.KeyCode.Space or mouseUp) and handlers.release then
		handlers.release()
	end
end)
