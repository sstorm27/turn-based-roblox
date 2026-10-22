--[[
	Rolls for card rewards, relics and shop stock. Everything takes the run's
	content and an Rng stream, so rewards never shift map or combat rolls.
]]

local Rewards = {}

local POOL_RARITIES = { Common = true, Uncommon = true, Rare = true }
local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Boss" }

local function sortedIds(tbl): { string }
	local ids = {}
	for id in tbl do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function rollRarity(rng, odds: { [string]: number }): string
	local total = 0
	for _, rarity in RARITY_ORDER do
		total += odds[rarity] or 0
	end
	local roll = rng:float() * total
	for _, rarity in RARITY_ORDER do
		roll -= odds[rarity] or 0
		if roll < 0 then
			return rarity
		end
	end
	return "Common"
end

-- Card ids the hero can be offered: its class cards and Neutral cards of a
-- reward rarity.
function Rewards.cardPool(content, heroId: string): { string }
	local pool = {}
	for _, id in sortedIds(content.Cards) do
		local card = content.Cards[id]
		if POOL_RARITIES[card.rarity] and (card.class == heroId or card.class == "Neutral") then
			table.insert(pool, id)
		end
	end
	return pool
end

-- `count` distinct card ids. Each slot rolls a rarity from `odds`; when that
-- rarity has run dry, the slot takes any card left in the pool.
function Rewards.rollCards(content, heroId: string, rng, odds, count: number): { string }
	local remaining = Rewards.cardPool(content, heroId)
	local picked: { string } = {}
	for _ = 1, count do
		if #remaining == 0 then
			break
		end
		local rarity = rollRarity(rng, odds)
		local matching = {}
		for index, id in remaining do
			if content.Cards[id].rarity == rarity then
				table.insert(matching, index)
			end
		end
		local index = if #matching > 0 then matching[rng:int(1, #matching)] else rng:int(1, #remaining)
		table.insert(picked, (table.remove(remaining, index) :: any) :: string)
	end
	return picked
end

-- A random relic the run doesn't own, rolled by rarity (boss relics are
-- excluded unless `bossOnly`). Nil when none are left.
function Rewards.rollRelic(content, rng, owned: { [string]: boolean }, odds, bossOnly: boolean?): string?
	local candidates = {}
	for _, id in sortedIds(content.Relics) do
		local relic = content.Relics[id]
		local isBoss = relic.rarity == "Boss"
		if not owned[id] and isBoss == (bossOnly == true) then
			table.insert(candidates, id)
		end
	end
	if #candidates == 0 then
		return nil
	end
	if not bossOnly then
		local rarity = rollRarity(rng, odds)
		local matching = {}
		for _, id in candidates do
			if content.Relics[id].rarity == rarity then
				table.insert(matching, id)
			end
		end
		if #matching > 0 then
			candidates = matching
		end
	end
	return candidates[rng:int(1, #candidates)]
end

-- Up to `count` distinct relics (used for the boss's pick 1 of 3).
function Rewards.rollRelics(content, rng, owned, odds, count: number, bossOnly: boolean?): { string }
	local taken = table.clone(owned)
	local list = {}
	for _ = 1, count do
		local id = Rewards.rollRelic(content, rng, taken, odds, bossOnly)
		if not id then
			break
		end
		taken[id] = true
		table.insert(list, id)
	end
	return list
end

local function jitter(rng, price: number, amount: number): number
	return math.floor(price * (1 + rng:range(-amount, amount)) + 0.5)
end

-- A shop's stock: cards (one on sale), relics, and the remove and upgrade
-- services.
function Rewards.rollShop(content, heroId: string, rng, owned, removalsSoFar: number)
	local rules = content.RunRules.shop
	local shop = { cards = {}, relics = {} }
	for _, id in Rewards.rollCards(content, heroId, rng, rules.cardOdds, rules.cards) do
		local rarity = content.Cards[id].rarity
		table.insert(shop.cards, { cardId = id, price = jitter(rng, rules.cardPrices[rarity], rules.jitter), sold = false })
	end
	if #shop.cards > 0 then
		local sale = shop.cards[rng:int(1, #shop.cards)]
		sale.price = math.floor(sale.price * rules.saleMult)
		sale.onSale = true
	end
	for _, id in Rewards.rollRelics(content, rng, owned, content.RunRules.relicOdds, rules.relics) do
		local rarity = content.Relics[id].rarity
		table.insert(shop.relics, { relicId = id, price = jitter(rng, rules.relicPrices[rarity], rules.jitter), sold = false })
	end
	shop.remove = { price = rules.removeBase + rules.removeStep * removalsSoFar, used = false }
	shop.upgrade = { price = rules.upgradePrice, used = false }
	return shop
end

return Rewards
