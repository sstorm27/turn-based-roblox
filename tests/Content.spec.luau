local Content = require("../src/shared/Data/Content")
local ContentValidator = require("../src/server/Combat/ContentValidator")
local TestKit = require("./TestKit")
local expect = TestKit.expect

return function(t)
	t.test("all content references resolve", function()
		local errors = ContentValidator.validate(Content)
		expect.equal(#errors, 0, table.concat(errors, "\n"))
	end)

	t.test("the validator catches a bad op, status and move", function()
		local broken = table.clone(Content)
		broken.Cards = table.clone(Content.Cards)
		broken.Cards.Broken = {
			id = "Broken",
			cost = 1,
			type = "Attack",
			target = "Enemy",
			effects = { { op = "Explode" }, { op = "ApplyStatus", status = "Sleepy", stacks = 1 } },
			qte = { kind = "Juggle" },
		}
		broken.Enemies = table.clone(Content.Enemies)
		broken.Enemies.Ghost = { id = "Ghost", moves = {}, pattern = { kind = "Cycle", order = { "Boo" } } }
		local errors = ContentValidator.validate(broken)
		expect.equal(#errors, 4, table.concat(errors, "\n"))
	end)

	t.test("about the design's share of QTE cards: every QTE card has a bonus", function()
		for id, card in Content.Cards do
			if card.qte then
				expect.truthy(card.qte.good or card.qte.perfect, id)
			end
		end
	end)
end
