--[[
	The look of the game UI in one place: a small pixel-art palette, two
	fonts, sizes and icons. Screens never hard-code a colour; they ask here.

	Art direction (design doc, "Simple UI"): flat 2D, chunky high-contrast
	panels with hard edges and a dark outline, few elements per screen, and
	intents as the one highlighted element in combat.

	Icons: every name in Sprites.art (generated from tools/sprites.py) gets
	its pixel sprite, drawn by Kit.icon with Frames. Give an entry an
	`image` (an uploaded rbxassetid) and Kit.icon shows that instead. The
	glyph is the fallback for names without art.
]]

local Sprites = require(script.Parent.Sprites)

local Theme = {}

Theme.gameTitle = "Turn Based"
Theme.subtitle = "A single-hero deckbuilder"

local rgb = Color3.fromRGB

Theme.colors = {
	backdrop = rgb(20, 18, 31),
	panel = rgb(37, 33, 56),
	panelLight = rgb(54, 49, 80),
	panelDark = rgb(28, 25, 43),
	ink = rgb(9, 8, 15), -- outlines and drop shadows
	text = rgb(244, 239, 226),
	textDim = rgb(150, 143, 176),
	textDark = rgb(28, 22, 18),

	gold = rgb(242, 193, 78),
	goldLight = rgb(255, 226, 140),
	hp = rgb(217, 80, 74),
	hpBack = rgb(70, 30, 38),
	block = rgb(90, 169, 230),
	energy = rgb(244, 170, 60),
	heal = rgb(110, 200, 110),
	buff = rgb(110, 200, 110),
	debuff = rgb(200, 110, 210),
	disabled = rgb(60, 56, 78),

	good = rgb(244, 239, 226),
	perfect = rgb(255, 214, 90),
	miss = rgb(150, 143, 176),

	button = rgb(61, 55, 92),
	buttonPrimary = rgb(194, 132, 46),
	buttonGo = rgb(70, 140, 90),
}

-- Card frames by card type, and node colours by map node type.
Theme.cardColors = {
	Attack = rgb(176, 72, 58),
	Skill = rgb(67, 118, 181),
	Power = rgb(138, 92, 196),
	Status = rgb(90, 90, 100),
	Curse = rgb(70, 40, 60),
	Wound = rgb(90, 70, 70),
}

Theme.nodeColors = {
	Combat = rgb(176, 72, 58),
	Elite = rgb(160, 52, 120),
	Event = rgb(80, 96, 176),
	Rest = rgb(70, 140, 90),
	Shop = rgb(194, 150, 46),
	Treasure = rgb(214, 170, 60),
	Boss = rgb(150, 30, 40),
}

Theme.rarityColors = {
	Starter = rgb(150, 143, 176),
	Common = rgb(200, 196, 210),
	Uncommon = rgb(90, 169, 230),
	Rare = rgb(242, 193, 78),
	Boss = rgb(217, 80, 74),
	Shop = rgb(110, 200, 110),
}

-- Press Start 2P for headings and numbers, Arcade for body text: both are
-- pixel fonts that ship with Roblox.
Theme.fonts = {
	display = Font.new("rbxasset://fonts/families/PressStart2P.json"),
	body = Font.fromEnum(Enum.Font.Arcade),
	-- Placeholder glyph icons use a font with wide symbol coverage.
	icon = Font.fromEnum(Enum.Font.BuilderSansBold),
}

Theme.sizes = {
	outline = 3, -- panel outline
	shadow = 4, -- drop shadow offset
	gutter = 12,
	topBar = 48,
	-- Design doc: cards at least 72 px wide on mobile. The UI scales down to
	-- 0.6 on small screens (see Main), so 118 stays above that.
	cardW = 118,
	cardH = 168,
}

Theme.icons = {
	hp = { glyph = "♥", color = rgb(217, 80, 74) },
	block = { glyph = "◈", color = rgb(90, 169, 230) },
	energy = { glyph = "⚡", color = rgb(244, 170, 60) },
	gold = { glyph = "●", color = rgb(242, 193, 78) },
	deck = { glyph = "▤", color = rgb(244, 239, 226) },
	draw = { glyph = "▤", color = rgb(244, 239, 226) },
	discard = { glyph = "▥", color = rgb(150, 143, 176) },
	exhaust = { glyph = "✕", color = rgb(150, 143, 176) },
	settings = { glyph = "⚙", color = rgb(244, 239, 226) },
	map = { glyph = "◎", color = rgb(244, 239, 226) },
	relic = { glyph = "◆", color = rgb(242, 193, 78) },
	qte = { glyph = "!", color = rgb(255, 214, 90) },

	-- Map nodes
	Combat = { glyph = "⚔", color = rgb(244, 239, 226) },
	Elite = { glyph = "☠", color = rgb(244, 239, 226) },
	Event = { glyph = "?", color = rgb(244, 239, 226) },
	Rest = { glyph = "▲", color = rgb(244, 239, 226) },
	Shop = { glyph = "$", color = rgb(244, 239, 226) },
	Treasure = { glyph = "◆", color = rgb(244, 239, 226) },
	Boss = { glyph = "♛", color = rgb(244, 239, 226) },

	-- Enemy intents
	Attack = { glyph = "⚔", color = rgb(217, 80, 74) },
	AttackDebuff = { glyph = "⚔", color = rgb(200, 110, 210) },
	Defend = { glyph = "◈", color = rgb(90, 169, 230) },
	Buff = { glyph = "▲", color = rgb(110, 200, 110) },
	Debuff = { glyph = "▼", color = rgb(200, 110, 210) },
	Pollute = { glyph = "☁", color = rgb(150, 143, 176) },
	Unknown = { glyph = "?", color = rgb(150, 143, 176) },
}

-- Uploaded PNGs (see tools/README.md), by icon name. Each one replaces
-- that icon's Frame-drawn sprite, e.g. Warden = "rbxassetid://123".
Theme.iconImages = {} :: { [string]: string }

-- Every sprite becomes an icon: units by enemy or hero id, statuses and
-- relics by id, card types as "<Type>Card".
for name in Sprites.art do
	local spec = Theme.icons[name] or { glyph = "?", color = Theme.colors.textDim }
	spec.sprite = name
	Theme.icons[name] = spec
end
for name, image in Theme.iconImages do
	if Theme.icons[name] then
		Theme.icons[name].image = image
	end
end

-- What each intent type means, for tooltips.
Theme.intentText = {
	Attack = "Attacks you.",
	AttackDebuff = "Attacks you and applies a debuff.",
	Defend = "Gains Block.",
	Buff = "Strengthens itself.",
	Debuff = "Applies a debuff to you.",
	Pollute = "Shuffles junk cards into your deck.",
}

Theme.qteHelp = {
	Timing = "Tap when the marker is in the gold band",
	Sequence = "Enter the arrows in order",
	Mash = "Tap as fast as you can",
	Hold = "Hold, then release in the gold zone",
	Trace = "Hold and swipe through the dots in order",
}

return Theme
