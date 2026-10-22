--[[
	Wraps the pure combat engine for real players. One combat session per
	player; the server owns all state and every QTE grade, and the client only
	sends intents (play this card, end turn, here are my QTE inputs).
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

local contentErrors = ContentValidator.validate(Content)
for _, message in contentErrors do
	warn(`[Content] {message}`)
end

type Session = {
	combat: any,
	qteRng: any,
	qte: any?, -- { challenge, sentAt, timeout }
	assist: { wideWindows: boolean, alwaysGood: boolean },
}

local sessions: { [Player]: Session } = {}
local assists: { [Player]: { wideWindows: boolean, alwaysGood: boolean } } = {}

local function send(player: Player, session: Session)
	Remotes.StateUpdate:FireClient(player, session.combat:getSnapshot(), session.combat:takeEvents())
end

local resolvePendingQte

-- After every action: if the engine paused on a QTE, start it on the client
-- with a server-side deadline; then push the new state.
local function afterAction(player: Player, session: Session)
	local combat = session.combat
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
	session.combat:resolveQte(qteState.challenge.qteId, grade)
	afterAction(player, session)
end

local function startCombat(player: Player, encounterId: any)
	if type(encounterId) ~= "string" or not Content.Encounters[encounterId] then
		encounterId = "Prototype"
	end
	local old = sessions[player]
	if old and old.qte and old.qte.timeout then
		pcall(task.cancel, old.qte.timeout)
	end
	local assist = assists[player] or { wideWindows = false, alwaysGood = false }
	local seed = bit32.bxor(player.UserId % 0x7FFFFFFF, math.floor(os.clock() * 1000))
	local combat = Combat.new(Content, {
		seed = seed,
		encounter = encounterId,
		wideQteWindows = assist.wideWindows,
	})
	local session: Session = {
		combat = combat,
		qteRng = Rng.new(seed + 1),
		qte = nil,
		assist = assist,
	}
	sessions[player] = session
	combat:start()
	afterAction(player, session)
end

Remotes.StartCombat.OnServerEvent:Connect(function(player, encounterId)
	startCombat(player, encounterId)
end)

Remotes.PlayCard.OnServerEvent:Connect(function(player, cardUid, targetId)
	local session = sessions[player]
	if not session or type(cardUid) ~= "string" then
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
	if not session then
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
	local session = sessions[player]
	if session and session.qte and session.qte.timeout then
		pcall(task.cancel, session.qte.timeout)
	end
	sessions[player] = nil
	assists[player] = nil
end)
