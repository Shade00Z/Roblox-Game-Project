--!nonstrict
-- One place that defines every client <-> server remote.
-- The server creates them; the client waits for them.
--
-- Usage:  local Remotes = require(ReplicatedStorage.Shared.Remotes)
--         Remotes.State:FireClient(player, state)        -- server
--         Remotes.State.OnClientEvent:Connect(fn)         -- client

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFINITIONS = {
	-- server -> client
	State = "RemoteEvent", -- full state snapshot for the HUD
	AwaySummary = "RemoteEvent", -- "While you were away" numbers
	Notify = "RemoteEvent", -- short toast message
	CrackResult = "RemoteEvent", -- what came out of a geode
	HatchResult = "RemoteEvent", -- which critter hatched from an egg

	-- client -> server
	TapVein = "RemoteEvent", -- (veinIndex) the server checks it's your shaft and the vein is ready
	MineBlock = "RemoteEvent", -- (meter, col) one pickaxe swing at a dig-front block
	RideUp = "RemoteEvent", -- the HUD's elevator button while in your shaft

	-- server -> client
	DigFind = "RemoteEvent", -- something special came out of a block you dug

	-- client -> server (functions return { ok = bool, message = string? })
	RequestUpgrade = "RemoteFunction", -- ("bit" | "cart")
	CrackGeode = "RemoteFunction", -- (geodeId)
	SetCrew = "RemoteFunction", -- (critterId, assign: boolean)
	MergeCritters = "RemoteFunction", -- (critterIdA, critterIdB)
	MergeAll = "RemoteFunction", -- () merge every pair possible
	SellCritter = "RemoteFunction", -- (critterId) bench critters only
	ToggleLock = "RemoteFunction", -- (critterId)
	BuyEgg = "RemoteFunction", -- (eggId) at the Hatchery
	HatchEgg = "RemoteFunction", -- (incubatorId) at the Hatchery
	SetGemSlot = "RemoteFunction", -- (slot, gemId or nil) the gem stand
	Rebirth = "RemoteFunction", -- () start over for a permanent boost

	-- Studio-only testing helper (ignored on live servers)
	DebugSkipTime = "RemoteEvent", -- (seconds)
	DebugRebirth = "RemoteFunction", -- () rebirth right now, at any depth
	DebugResetSave = "RemoteFunction", -- () back to a brand-new player
	DebugGiveGeode = "RemoteFunction", -- (rarity) a ready-to-crack geode on your rack
}

local FOLDER_NAME = "Remotes"
local folder: Instance

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) or Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for name, className in pairs(DEFINITIONS) do
		if not folder:FindFirstChild(name) then
			local r = Instance.new(className)
			r.Name = name
			r.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local Remotes = {}
for name in pairs(DEFINITIONS) do
	Remotes[name] = folder:WaitForChild(name)
end

return Remotes :: {
	State: RemoteEvent,
	AwaySummary: RemoteEvent,
	Notify: RemoteEvent,
	CrackResult: RemoteEvent,
	HatchResult: RemoteEvent,
	TapVein: RemoteEvent,
	MineBlock: RemoteEvent,
	RideUp: RemoteEvent,
	DigFind: RemoteEvent,
	RequestUpgrade: RemoteFunction,
	CrackGeode: RemoteFunction,
	SetCrew: RemoteFunction,
	MergeCritters: RemoteFunction,
	MergeAll: RemoteFunction,
	SellCritter: RemoteFunction,
	ToggleLock: RemoteFunction,
	BuyEgg: RemoteFunction,
	HatchEgg: RemoteFunction,
	SetGemSlot: RemoteFunction,
	Rebirth: RemoteFunction,
	DebugSkipTime: RemoteEvent,
	DebugRebirth: RemoteFunction,
	DebugResetSave: RemoteFunction,
	DebugGiveGeode: RemoteFunction,
}
