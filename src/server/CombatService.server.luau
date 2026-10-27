--[[
	Wraps the pure combat and run engines for real players. One session per
	player: either a whole run (StartRun) or a single debug fight
	(StartCombat). The server owns all state and every QTE grade, and the
	client only sends intents (pick this node, play this card, end turn, here
	are my QTE inputs).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared.Data.Content)
local Remotes = require(Shared.Net.Remotes)

local CombatFolder = script.Parent:WaitForChild("Combat")
local Combat = require(CombatFolder.Combat)
local ContentValidator = require(CombatFolder.ContentValidator)
local QteJudge = require(CombatFolder.QteJudge)
local Rng = require(CombatFolder.Rng)

local RunFolder = script.Parent:WaitForChild("Run")
local Run = require(RunFolder.Run)
local RunValidator = require(RunFolder.RunValidator)

for _, message in ContentValidator.validate(Content) do
	warn(`[Content] {message}`)
end
for _, message in RunValidator.validate(Content) do
	warn(`[Content] {message}`)
end

type Session = {
	run: any?, -- nil for a single debug fight
	combat: any?, -- the live fight, if any
	qteRng: any,
	qte: any?, -- { challenge, sentAt, timeout }
	assist: { wideWindows: boolean, alwaysGood: boolean },
}

local sessions: { [Player]: Session } = {}
local assists: { [Player]: { wideWindows: boolean, alwaysGood: boolean } } = {}

local function send(player: Player, session: Session)
	local combat = session.combat
	if combat then
		Remotes.StateUpdate:FireClient(player, combat:getSnapshot(), combat:takeEvents())
	end
	if session.run then
		Remotes.RunUpdate:FireClient(player, session.run:getSnapshot())
	end
end

local function newSeed(player: Player): number
	return bit32.bxor(player.UserId % 0x7FFFFFFF, math.floor(os.clock() * 1000))
end

local resolvePendingQte

-- After every action: if the engine paused on a QTE, start it on the client
-- with a server-side deadline; then push the new state.
local function afterAction(player: Player, session: Session)
	local combat = session.combat
	local run = session.run
	if run then
		-- A finished fight moves the run on to its rewards (or ends it); a run
		-- action may have started a new fight.
		if combat and run:checkCombat() then
			send(player, session)
			session.combat = nil
			return
		end
		session.combat = run.combat
		combat = run.combat
	end
	if not combat then
		send(player, session)
		return
	end
	local pending = combat.pendingQte
	if pending and not session.qte then
		local challenge = QteJudge.createChallenge(Content.Qte, pending, session.qteRng)
		local qteState = { challenge = challenge, sentAt = os.clock() }
		session.qte = qteState
		-- A missing result counts as a Miss.
		local wait = challenge.deadline + Content.Qte.LatencyAllowance + Content.Qte.ResultGrace
		qteState.timeout = task.delay(wait, function()
			if sessions[player] == session and session.qte == qteState then
				resolvePendingQte(player, session, "Miss")
			end
		end)
		send(player, session)
		Remotes.QteStart:FireClient(player, challenge.public)
		return
	end
	send(player, session)
end

function resolvePendingQte(player: Player, session: Session, grade: string)
	local qteState = session.qte
	if not qteState then
		return
	end
	session.qte = nil
	if qteState.timeout and coroutine.status(qteState.timeout) == "suspended" then
		task.cancel(qteState.timeout)
	end
	if not session.combat then
		return
	end
	session.combat:resolveQte(qteState.challenge.qteId, grade)
	afterAction(player, session)
end

local function endSession(player: Player)
	local old = sessions[player]
	if old and old.qte and old.qte.timeout then
		pcall(task.cancel, old.qte.timeout)
	end
	sessions[player] = nil
end

local function startCombat(player: Player, encounterId: any)
	if type(encounterId) ~= "string" or not Content.Encounters[encounterId] then
		encounterId = "Prototype"
	end
	endSession(player)
	local assist = assists[player] or { wideWindows = false, alwaysGood = false }
	local seed = newSeed(player)
	local combat = Combat.new(Content, {
		seed = seed,
		encounter = encounterId,
		wideQteWindows = assist.wideWindows,
	})
	local session: Session = {
		run = nil,
		combat = combat,
		qteRng = Rng.new(seed + 1),
		qte = nil,
		assist = assist,
	}
	sessions[player] = session
	Remotes.RunUpdate:FireClient(player, nil)
	combat:start()
	afterAction(player, session)
end

-- A new run replaces whatever the player had going. No hub, no lives: when
-- the run ends the player starts a new one.
local function startRun(player: Player, heroId: any)
	if type(heroId) ~= "string" or not Content.Heroes[heroId] then
		heroId = "Warden"
	end
	endSession(player)
	local assist = assists[player] or { wideWindows = false, alwaysGood = false }
	local seed = newSeed(player)
	local run = Run.new(Content, { seed = seed, hero = heroId, wideQteWindows = assist.wideWindows })
	local session: Session = {
		run = run,
		combat = nil,
		qteRng = Rng.new(seed + 1),
		qte = nil,
		assist = assist,
	}
	sessions[player] = session
	afterAction(player, session)
end

Remotes.StartCombat.OnServerEvent:Connect(function(player, encounterId)
	startCombat(player, encounterId)
end)

Remotes.StartRun.OnServerEvent:Connect(function(player, heroId)
	startRun(player, heroId)
end)

Remotes.ChooseNode.OnServerEvent:Connect(function(player, nodeId)
	local session = sessions[player]
	if not session or not session.run or type(nodeId) ~= "string" then
		return
	end
	session.run:chooseNode(nodeId)
	afterAction(player, session)
end)

Remotes.ChooseOption.OnServerEvent:Connect(function(player, action)
	local session = sessions[player]
	if not session or not session.run or type(action) ~= "table" then
		return
	end
	-- Copy only the fields an action uses, with their expected types.
	local clean = {
		kind = if type(action.kind) == "string" then action.kind else nil,
		index = if type(action.index) == "number" then math.floor(action.index) else nil,
		item = if type(action.item) == "string" then action.item else nil,
		uid = if type(action.uid) == "string" then action.uid else nil,
		path = if type(action.path) == "string" then action.path else nil,
	}
	session.run:perform(clean)
	afterAction(player, session)
end)

Remotes.PlayCard.OnServerEvent:Connect(function(player, cardUid, targetId)
	local session = sessions[player]
	if not session or not session.combat or type(cardUid) ~= "string" then
		return
	end
	if targetId ~= nil and type(targetId) ~= "string" then
		return
	end
	local ok, err = session.combat:playCard(cardUid, targetId)
	if not ok then
		session.combat:emit("Rejected", { reason = err })
	end
	afterAction(player, session)
end)

Remotes.EndTurn.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session or not session.combat then
		return
	end
	local ok, err = session.combat:endTurn()
	if not ok then
		session.combat:emit("Rejected", { reason = err })
	end
	afterAction(player, session)
end)

Remotes.QteResult.OnServerEvent:Connect(function(player, qteId, inputs)
	local session = sessions[player]
	local qteState = session and session.qte
	if not qteState or qteId ~= qteState.challenge.qteId then
		return
	end
	local elapsed = os.clock() - qteState.sentAt
	local grade = QteJudge.grade(Content.Qte, qteState.challenge, inputs, elapsed, {
		alwaysGood = session.assist.alwaysGood,
	})
	resolvePendingQte(player, session, grade)
end)

Remotes.SetQteAssist.OnServerEvent:Connect(function(player, settings)
	if type(settings) ~= "table" then
		return
	end
	-- Always Good applies right away; wide windows from the next combat.
	local assist = {
		wideWindows = settings.wideWindows == true,
		alwaysGood = settings.alwaysGood == true,
	}
	assists[player] = assist
	local session = sessions[player]
	if session then
		session.assist = assist
	end
end)

Players.PlayerRemoving:Connect(function(player)
	endSession(player)
	assists[player] = nil
end)
