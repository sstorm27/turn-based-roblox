--[[
	All content tables in one place. The combat engine takes this as an
	argument instead of requiring it, so it runs the same in Roblox and in
	tests.
]]

local Content = {
	Cards = require("./Cards"),
	Statuses = require("./Statuses"),
	Enemies = require("./Enemies"),
	Heroes = require("./Heroes"),
	Encounters = require("./Encounters"),
	Qte = require("./Qte"),
}

-- The card definition with an upgrade path (A or B) applied, or nil.
function Content.getCard(id: string, upgrade: string?)
	local base = Content.Cards[id]
	if not base then
		return nil
	end
	if not upgrade then
		return base
	end
	local override = base.upgrades and base.upgrades[upgrade]
	if not override then
		return base
	end
	local card = table.clone(base)
	for key, value in override do
		card[key] = value
	end
	card.upgrade = upgrade
	card.name = override.name or (base.name .. "+" .. upgrade)
	return card
end

return Content
