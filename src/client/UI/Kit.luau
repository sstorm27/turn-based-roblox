--[[
	Small building blocks every screen shares: pixel panels, buttons, text,
	icons, bars, cards, status chips, tooltips and pop-up numbers. Nothing in
	here knows about game rules; screens pass in what the server sent.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Sprites = require(script.Parent.Sprites)
local Theme = require(script.Parent.Theme)

local C = Theme.colors
local S = Theme.sizes

local Kit = {}

-- The UI's current UIScale (set by Main). Absolute sizes are in screen
-- pixels; divide by this to get layout units.
Kit.uiScale = 1

-- Instances ------------------------------------------------------------------------

local nextOrder = 0

function Kit.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		-- List layouts sort by LayoutOrder: keep creation order by default.
		nextOrder += 1
		inst.LayoutOrder = nextOrder
		inst.BorderSizePixel = 0
	end
	local parent = nil
	for key, value in (props or {}) :: { [string]: any } do
		if key == "Parent" then
			parent = value
		else
			(inst :: any)[key] = value
		end
	end
	for _, child in (children or {}) :: { Instance } do
		child.Parent = inst
	end
	inst.Parent = parent
	return inst
end
local make = Kit.make

function Kit.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

function Kit.hlist(padding: number?, align: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?)
	return make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		VerticalAlignment = valign or Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding or 8),
	})
end

function Kit.vlist(padding: number?, align: Enum.HorizontalAlignment?)
	return make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, padding or 8),
	})
end

function Kit.padding(px: number)
	local u = UDim.new(0, px)
	return make("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

-- The pixel look: hard corners, a thick dark outline, and a lighter strip
-- along the top edge as a bevel.
function Kit.outline(color: Color3?, thickness: number?)
	return make("UIStroke", {
		Color = color or C.ink,
		Thickness = thickness or S.outline,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	})
end

local function bevel(parent: Instance, color: Color3)
	make("Frame", {
		Name = "Bevel",
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = color,
		ZIndex = (parent :: GuiObject).ZIndex,
		Parent = parent,
	})
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end
local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end
Kit.lighten = lighten
Kit.darken = darken

function Kit.panel(props: { [string]: any }, children: { Instance }?)
	props.BackgroundColor3 = props.BackgroundColor3 or C.panel
	local frame = make("Frame", props, children)
	Kit.outline().Parent = frame
	bevel(frame, lighten(frame.BackgroundColor3, 0.12))
	return frame
end

-- Text -------------------------------------------------------------------------------

function Kit.text(props: { [string]: any })
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or C.text
	props.FontFace = props.FontFace or Theme.fonts.body
	props.TextSize = props.TextSize or 18
	if props.TextWrapped == nil then
		props.TextWrapped = true
	end
	return make("TextLabel", props)
end

function Kit.title(props: { [string]: any })
	props.FontFace = props.FontFace or Theme.fonts.display
	props.TextSize = props.TextSize or 16
	return Kit.text(props)
end

-- Pixel sprites become a few Frames: runs of one colour are merged into
-- rectangles, so a 12x12 icon is a few dozen Frames, not 144. Cached by name.
local rectCache: { [string]: { { number } } } = {}

local function spriteRects(name: string, rows: { string }): { { number } }
	local cached = rectCache[name]
	if cached then
		return cached
	end
	-- Horizontal runs first: { x, y, w, h, colourIndex }
	local rects = {}
	local open: { [string]: { number } } = {} -- runs from the row above, by "x,w,ch"
	for y, row in rows do
		local nextOpen = {}
		local x = 1
		while x <= #row do
			local ch = string.sub(row, x, x)
			local w = 1
			while string.sub(row, x + w, x + w) == ch do
				w += 1
			end
			if ch ~= "." then
				local key = `{x},{w},{ch}`
				local above = open[key]
				if above then
					above[4] += 1 -- grow the run above down by a row
					nextOpen[key] = above
				else
					local rect = { x - 1, y - 1, w, 1, string.byte(ch) }
					table.insert(rects, rect)
					nextOpen[key] = rect
				end
			end
			x += w
		end
		open = nextOpen
	end
	rectCache[name] = rects
	return rects
end

local paletteColors: { [number]: Color3 } = {}
for ch, rgb in Sprites.palette do
	paletteColors[string.byte(ch)] = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Whether `name` has art (a sprite or an uploaded image), not just a glyph.
function Kit.hasArt(name: string): boolean
	local spec = Theme.icons[name]
	return spec ~= nil and (spec.image ~= nil or spec.sprite ~= nil)
end

-- An icon by Theme.icons name: an uploaded image if it has one, else its
-- pixel sprite, else its glyph. `fallback` is used when `name` has none.
-- TextColor3 tints glyphs only; TextTransparency fades all three kinds.
function Kit.icon(name: string, size: number, props: { [string]: any }?, fallback: string?)
	local spec = Theme.icons[name] or (fallback and Theme.icons[fallback]) or Theme.icons.Unknown
	local p = props or {}
	p.Size = p.Size or UDim2.fromOffset(size, size)
	p.BackgroundTransparency = 1
	local fade = p.TextTransparency or 0
	if spec.image or spec.sprite then
		p.TextColor3 = nil
		p.TextTransparency = nil
	end
	if spec.image then
		p.Image = spec.image
		p.ImageTransparency = fade
		p.ScaleType = Enum.ScaleType.Fit
		p.ResampleMode = Enum.ResamplerMode.Pixelated
		return make("ImageLabel", p)
	end
	if spec.sprite then
		local rows = Sprites.art[spec.sprite]
		local frame = make("Frame", p)
		local gridW, gridH = #rows[1], #rows
		-- Sized in pixels, each edge is rounded from its grid line, so
		-- neighbouring rectangles always meet with no gap. Sized by scale,
		-- the rectangles scale with it.
		local px, py = p.Size.X.Offset, p.Size.Y.Offset
		local inPixels = p.Size.X.Scale == 0 and p.Size.Y.Scale == 0
		for _, r in spriteRects(spec.sprite, rows) do
			local position, rectSize
			if inPixels then
				local left, top = math.round(r[1] * px / gridW), math.round(r[2] * py / gridH)
				local right, bottom = math.round((r[1] + r[3]) * px / gridW), math.round((r[2] + r[4]) * py / gridH)
				position, rectSize = UDim2.fromOffset(left, top), UDim2.fromOffset(right - left, bottom - top)
			else
				position, rectSize = UDim2.fromScale(r[1] / gridW, r[2] / gridH), UDim2.fromScale(r[3] / gridW, r[4] / gridH)
			end
			make("Frame", {
				Position = position,
				Size = rectSize,
				BackgroundColor3 = paletteColors[r[5]],
				BackgroundTransparency = fade,
				ZIndex = frame.ZIndex,
				Parent = frame,
			})
		end
		return frame
	end
	p.Text = spec.glyph
	p.TextColor3 = p.TextColor3 or spec.color
	p.FontFace = Theme.fonts.icon
	p.TextScaled = true
	return make("TextLabel", p)
end

-- Fades an icon made by Kit.icon, whichever kind it is.
function Kit.setIconTransparency(icon: GuiObject, transparency: number)
	if icon:IsA("TextLabel") then
		icon.TextTransparency = transparency
	elseif icon:IsA("ImageLabel") then
		icon.ImageTransparency = transparency
	else
		for _, pixel in icon:GetChildren() do
			if pixel:IsA("Frame") then
				pixel.BackgroundTransparency = transparency
			end
		end
	end
end

-- Buttons ----------------------------------------------------------------------------

export type ButtonOptions = {
	color: Color3?,
	enabled: boolean?,
	textSize: number?,
	font: Font?,
}

-- A chunky button with a darker lip along the bottom that sinks when pressed.
function Kit.button(props: { [string]: any }, onClick: (() -> ())?, options: ButtonOptions?)
	local opts: ButtonOptions = options or {}
	local enabled = opts.enabled ~= false
	local color = if enabled then (opts.color or C.button) else C.disabled
	props.BackgroundColor3 = color
	props.AutoButtonColor = false
	props.TextColor3 = props.TextColor3 or (if enabled then C.text else C.textDim)
	props.FontFace = opts.font or Theme.fonts.display
	props.TextSize = opts.textSize or 14
	props.TextWrapped = true
	local b = make("TextButton", props)
	Kit.outline().Parent = b
	bevel(b, lighten(color, 0.18))
	local lip = make("Frame", {
		Name = "Lip",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundColor3 = darken(color, 0.35),
		ZIndex = b.ZIndex,
		Parent = b,
	})
	if enabled then
		b.MouseEnter:Connect(function()
			b.BackgroundColor3 = lighten(color, 0.1)
		end)
		b.MouseLeave:Connect(function()
			b.BackgroundColor3 = color
			lip.Visible = true
		end)
		b.MouseButton1Down:Connect(function()
			lip.Visible = false
		end)
		b.MouseButton1Up:Connect(function()
			lip.Visible = true
		end)
		if onClick then
			b.Activated:Connect(onClick)
		end
	end
	return b
end

-- Bars and chips ---------------------------------------------------------------------

export type Bar = {
	frame: Frame,
	set: (value: number, max: number, label: string?) -> (),
}

function Kit.bar(props: { [string]: any }, fillColor: Color3, backColor: Color3?): Bar
	props.BackgroundColor3 = backColor or C.hpBack
	local frame = make("Frame", props)
	Kit.outline(C.ink, 2).Parent = frame
	local fill = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = fillColor,
		ZIndex = frame.ZIndex,
		Parent = frame,
	})
	bevel(fill, lighten(fillColor, 0.25))
	local label = Kit.title({
		Size = UDim2.fromScale(1, 1),
		TextSize = 10,
		ZIndex = frame.ZIndex + 1,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = C.ink,
		Parent = frame,
	})
	local bar = { frame = frame }
	function bar.set(value: number, max: number, text: string?)
		local t = if max > 0 then math.clamp(value / max, 0, 1) else 0
		TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(t, 1) }):Play()
		label.Text = text or `{value}/{max}`
	end
	return bar
end

function Kit.chip(text: string, color: Color3, props: { [string]: any }?)
	local p = props or {}
	p.AutomaticSize = Enum.AutomaticSize.X
	p.Size = p.Size or UDim2.fromOffset(0, 20)
	p.BackgroundColor3 = darken(color, 0.55)
	p.Text = text
	p.TextColor3 = color
	p.TextSize = p.TextSize or 16
	p.TextWrapped = false
	local chip = Kit.text(p)
	chip.BackgroundTransparency = 0
	Kit.outline(color, 1).Parent = chip
	make("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = chip })
	return chip
end

-- Cards ------------------------------------------------------------------------------

-- Wraps the numbers in `text` that differ from the same-position number in
-- `base` in gold, for upgrade previews ("changed numbers highlighted").
function Kit.highlightChanges(base: string, text: string): string
	local baseNumbers = {}
	for n in string.gmatch(base, "%d+") do
		table.insert(baseNumbers, n)
	end
	local i = 0
	local hex = "#" .. Theme.colors.goldLight:ToHex()
	return (string.gsub(text, "%d+", function(n)
		i += 1
		if baseNumbers[i] ~= n then
			return `<font color="{hex}">{n}</font>`
		end
		return n
	end))
end

export type CardOptions = {
	scale: number?,
	enabled: boolean?, -- false greys the card out
	footer: string?, -- a price tag or note under the text
	footerColor: Color3?,
	richText: string?, -- card text with RichText markup, replaces card.text
}

-- A card face. `card` is a combat hand entry or a run card view: name, cost,
-- type, text, and qte as either a kind string or { kind, difficulty }.
function Kit.card(card: any, props: { [string]: any }?, onClick: (() -> ())?, options: CardOptions?)
	local opts: CardOptions = options or {}
	local scale = opts.scale or 1
	local enabled = opts.enabled ~= false
	local frameColor = Theme.cardColors[card.type] or Theme.cardColors.Status
	if not enabled then
		frameColor = C.disabled
	end
	local p = props or {}
	p.Size = p.Size or UDim2.fromOffset(S.cardW * scale, S.cardH * scale)
	p.BackgroundColor3 = frameColor
	p.AutoButtonColor = false
	p.Text = ""
	local root = make("TextButton", p)
	Kit.outline().Parent = root
	bevel(root, lighten(frameColor, 0.2))
	local z = root.ZIndex

	-- Inner face
	local face = make("Frame", {
		Position = UDim2.fromOffset(5, 26 * scale),
		Size = UDim2.new(1, -10, 1, -31 * scale),
		BackgroundColor3 = C.panelDark,
		ZIndex = z,
		Parent = root,
	})
	local name = Kit.title({
		Position = UDim2.fromOffset(22 * scale, 3),
		Size = UDim2.new(1, -24 * scale, 0, 22 * scale),
		Text = card.name,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = if card.upgrade then C.goldLight else C.text,
		ZIndex = z + 1,
		Parent = root,
	})
	make("UITextSizeConstraint", { MaxTextSize = math.floor(10 * scale), Parent = name })
	-- Cost gem
	local gem = make("Frame", {
		Position = UDim2.fromOffset(-6, -6),
		Size = UDim2.fromOffset(24 * scale, 24 * scale),
		BackgroundColor3 = if enabled then C.energy else C.disabled,
		ZIndex = z + 2,
		Parent = root,
	})
	Kit.outline().Parent = gem
	Kit.title({
		Size = UDim2.fromScale(1, 1),
		Text = if type(card.cost) == "number" then tostring(card.cost) else "X",
		TextSize = math.floor(12 * scale),
		TextColor3 = C.textDark,
		ZIndex = z + 3,
		Parent = gem,
	})
	Kit.text({
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.new(1, -8, 0, 14 * scale),
		Text = string.upper(card.type or ""),
		TextSize = math.floor(13 * scale),
		TextColor3 = C.textDim,
		ZIndex = z + 1,
		Parent = face,
	})
	local typeIcon = `{card.type}Card`
	if Kit.hasArt(typeIcon) then
		Kit.icon(typeIcon, math.floor(16 * scale), {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -2, 0, 1),
			TextTransparency = if enabled then 0 else 0.5,
			ZIndex = z + 1,
			Parent = face,
		})
	end
	local qteKind = if type(card.qte) == "table" then card.qte.kind else card.qte
	-- Long card text (QTE cards spell out their bonuses) shrinks to fit,
	-- above the QTE chip when there is one.
	local reserved = if qteKind then 22 * scale else 4
	local body = Kit.text({
		Position = UDim2.fromOffset(4, 16 * scale),
		Size = UDim2.new(1, -8, 1, -(16 * scale + reserved)),
		Text = opts.richText or card.text or "",
		RichText = opts.richText ~= nil,
		TextScaled = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = z + 1,
		Parent = face,
	})
	make("UITextSizeConstraint", { MaxTextSize = math.floor(16 * scale), MinTextSize = 8, Parent = body })
	body.TextColor3 = if enabled then C.text else C.textDim

	if qteKind then
		Kit.chip(`QTE {qteKind}`, C.perfect, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.fromOffset(0, 16 * scale),
			TextSize = math.floor(14 * scale),
			ZIndex = z + 1,
			Parent = face,
		})
	end
	if opts.footer then
		-- Under the card, so it never covers the text or the QTE chip.
		local tag = Kit.chip(opts.footer, opts.footerColor or C.gold, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, 6),
			Size = UDim2.fromOffset(0, 22),
			TextSize = 18,
			ZIndex = z + 3,
			Parent = root,
		})
		tag.BackgroundColor3 = C.ink
	end
	if onClick and enabled then
		root.Activated:Connect(onClick)
	end
	return root
end

-- Tooltips ---------------------------------------------------------------------------

local tipLabel: TextLabel? = nil

-- The tooltip draws in its own ScreenGui above everything else.
function Kit.mountTooltips(playerGui: Instance)
	local gui = make("ScreenGui", {
		Name = "Tooltips",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
		Parent = playerGui,
	})
	local label = Kit.text({
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(240, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.panelDark,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 18,
		RichText = true,
		Visible = false,
		ZIndex = 50,
		Parent = gui,
	})
	Kit.outline(C.gold, 2).Parent = label
	Kit.padding(8).Parent = label
	tipLabel = label
end

local function showTip(target: GuiObject, text: string)
	local label = tipLabel
	if not label or text == "" then
		return
	end
	label.Text = text
	label.Visible = true
	-- Every game ScreenGui ignores the GUI inset, so absolute positions line up.
	local pos, size = target.AbsolutePosition, target.AbsoluteSize
	local screen = (label.Parent :: ScreenGui).AbsoluteSize
	local x = math.clamp(pos.X + size.X / 2 - 120, 8, screen.X - 248)
	-- Above the element when there is room, otherwise below it.
	local height = label.AbsoluteSize.Y
	local y = if pos.Y - height - 10 > 8 then pos.Y - height - 10 else pos.Y + size.Y + 10
	label.Position = UDim2.fromOffset(x, y)
end

local function hideTip()
	if tipLabel then
		tipLabel.Visible = false
	end
end
Kit.hideTooltip = hideTip

-- Hover on desktop, long-press on touch. `text` may be a function so the
-- tooltip reads live state.
function Kit.tooltip(target: GuiObject, text: string | () -> string)
	local function resolve(): string
		return if type(text) == "function" then text() else text
	end
	target.MouseEnter:Connect(function()
		if not UserInputService.TouchEnabled then
			showTip(target, resolve())
		end
	end)
	target.MouseLeave:Connect(hideTip)
	target.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local started = os.clock()
		task.delay(0.45, function()
			if input.UserInputState == Enum.UserInputState.Begin and os.clock() - started >= 0.44 then
				showTip(target, resolve())
			end
		end)
	end)
	target.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			hideTip()
		end
	end)
	target.Destroying:Connect(hideTip)
end

-- Effects ----------------------------------------------------------------------------

-- Text that rises and fades over `parent`, for damage numbers and grades.
function Kit.pop(parent: GuiObject, text: string, color: Color3, options: { size: number?, rise: number?, hold: number? }?)
	local opts = options or {}
	local label = Kit.title({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, math.random(-12, 12), 0.4, 0),
		Size = UDim2.fromOffset(240, 40),
		Text = text,
		TextColor3 = color,
		TextSize = opts.size or 18,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = C.ink,
		ZIndex = parent.ZIndex + 20,
		Parent = parent,
	})
	local scale = make("UIScale", { Scale = 0.4, Parent = label })
	TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(opts.hold or 0.35, function()
		local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, info, {
			Position = label.Position - UDim2.fromOffset(0, opts.rise or 40),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		task.delay(0.65, function()
			label:Destroy()
		end)
	end)
	return label
end

function Kit.shake(target: GuiObject)
	local origin = target.Position
	task.spawn(function()
		for _, dx in { 6, -6, 4, -4, 0 } do
			target.Position = origin + UDim2.fromOffset(dx, 0)
			task.wait(0.03)
		end
		target.Position = origin
	end)
end

-- Modals -----------------------------------------------------------------------------

export type Modal = {
	root: Frame,
	body: Frame,
	close: () -> (),
}

-- A dimmed full-screen layer with a centred panel and a Close button.
function Kit.modal(parent: Instance, heading: string, size: UDim2, onClose: (() -> ())?): Modal
	local root = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 0.25,
		ZIndex = 30,
		Parent = parent,
	})
	-- Swallow clicks so nothing underneath reacts.
	make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 30,
		Parent = root,
	})
	local panel = Kit.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		ZIndex = 31,
		Parent = root,
	})
	make("UISizeConstraint", { MaxSize = Vector2.new(980, 640), Parent = panel })
	Kit.title({
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -140, 0, 24),
		Text = heading,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 32,
		Parent = panel,
	})
	local body = make("Frame", {
		Position = UDim2.fromOffset(16, 48),
		Size = UDim2.new(1, -32, 1, -64),
		BackgroundTransparency = 1,
		ZIndex = 32,
		Parent = panel,
	})
	local modal: Modal
	local function close()
		hideTip()
		root:Destroy()
		if onClose then
			onClose()
		end
	end
	Kit.button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(110, 30),
		Text = "Close",
		TextSize = 12,
		ZIndex = 32,
		Parent = panel,
	}, close)
	modal = { root = root, body = body, close = close }
	return modal
end

-- A scrolling grid of cards inside `parent`.
function Kit.cardGrid(parent: Instance, props: { [string]: any }?)
	local p = props or {}
	p.Size = p.Size or UDim2.fromScale(1, 1)
	p.BackgroundTransparency = 1
	p.AutomaticCanvasSize = Enum.AutomaticSize.Y
	p.CanvasSize = UDim2.new()
	p.ScrollBarThickness = 6
	p.ScrollBarImageColor3 = C.textDim
	p.Parent = parent
	local scroll = make("ScrollingFrame", p)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(S.cardW, S.cardH),
		CellPadding = UDim2.fromOffset(14, 18),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 16),
		Parent = scroll,
	})
	return scroll
end

return Kit
