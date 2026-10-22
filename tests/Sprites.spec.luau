local Content = require("../src/shared/Data/Content")
local Sprites = require("../src/client/UI/Sprites")
local TestKit = require("./TestKit")
local expect = TestKit.expect

return function(t)
	t.test("every sprite is a square grid of palette colours", function()
		for name, rows in Sprites.art do
			local width = #rows[1]
			expect.truthy(width == 12 or width == 16, `{name} is {width} wide`)
			expect.equal(#rows, width, `{name} is not square`)
			for _, row in rows do
				expect.equal(#row, width, `{name} has a row of {#row}`)
				for i = 1, #row do
					local ch = string.sub(row, i, i)
					expect.truthy(ch == "." or Sprites.palette[ch] ~= nil, `{name} uses unknown colour {ch}`)
				end
			end
		end
	end)

	t.test("every hero, enemy, status, relic and intent has a sprite", function()
		local groups = { Content.Heroes, Content.Enemies, Content.Statuses, Content.Relics }
		for _, group in groups do
			for id in group do
				expect.truthy(Sprites.art[id] ~= nil, `no sprite for {id}`)
			end
		end
		for id, enemy in Content.Enemies do
			for moveId, move in enemy.moves do
				expect.truthy(Sprites.art[move.intent] ~= nil, `no intent sprite for {id}.{moveId} ({move.intent})`)
			end
		end
	end)

	t.test("every card type has a sprite", function()
		for id, card in Content.Cards do
			if card.type ~= "Wound" then
				expect.truthy(Sprites.art[`{card.type}Card`] ~= nil, `no sprite for {id}'s type {card.type}`)
			end
		end
	end)
end
