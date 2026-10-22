-- Runs every engine spec: `luau tests/run.luau`
local TestKit = require("./TestKit")

local ok = TestKit.run({
	Combat = require("./Combat.spec"),
	Qte = require("./Qte.spec"),
	EnemyAI = require("./EnemyAI.spec"),
	Content = require("./Content.spec"),
	Map = require("./Map.spec"),
	Run = require("./Run.spec"),
})

if not ok then
	error("tests failed", 0)
end
