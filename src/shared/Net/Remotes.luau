--[[
	RemoteEvents for runs and combat. The server creates them; clients wait
	for them.

	Client to server
		StartRun     ()                       starts a new run (replaces any other)
		ChooseNode   (nodeId)                 a path card on the map
		ChooseOption (action)                 { kind = "Option", index } events,
		                                      rest, rewards, boss relics;
		                                      { kind = "Skip" }, { kind = "Proceed" },
		                                      { kind = "Buy", item, index? },
		                                      { kind = "Select", uid, path? },
		                                      { kind = "Cancel" }
		StartCombat  (encounterId?)           a single debug fight
		PlayCard     (cardUid, targetId?)
		EndTurn      ()
		QteResult    (qteId, inputs)          raw input times, graded on the server
		SetQteAssist ({ wideWindows, alwaysGood })

	Server to client
		StateUpdate  (snapshot, events)       combat snapshot of what the player
		                                      sees, plus the ordered events to animate
		RunUpdate    (snapshot)               run snapshot: map, screen, deck, HP
		QteStart     ({ qteId, kind, difficulty, params, deadline, source })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"StartRun",
	"ChooseNode",
	"ChooseOption",
	"StartCombat",
	"PlayCard",
	"EndTurn",
	"QteResult",
	"SetQteAssist",
	"StateUpdate",
	"RunUpdate",
	"QteStart",
}

local Remotes = {}

if RunService:IsServer() then
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in NAMES do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		Remotes[name] = remote
	end
else
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	for _, name in NAMES do
		Remotes[name] = folder:WaitForChild(name)
	end
end

return Remotes
