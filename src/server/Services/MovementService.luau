--!nonstrict
-- Walking speed and the Topside fast lanes.
--
-- A fast lane is an anchored part with a "BeltDirection" attribute (a unit Vector3).
-- Giving an anchored part a velocity makes it act like a conveyor belt: anyone
-- standing on it gets carried along, without the part itself moving.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Movement = require(Shared.Config.Movement)

local MovementService = {}

local function startBelts()
	local walkways = workspace.Map.Topside:FindFirstChild("Walkways")
	if not walkways then
		warn("[MovementService] No Workspace.Map.Topside.Walkways folder; fast lanes are off")
		return
	end
	for _, part in ipairs(walkways:GetDescendants()) do
		local direction = part:IsA("BasePart") and part:GetAttribute("BeltDirection")
		if typeof(direction) == "Vector3" then
			part.AssemblyLinearVelocity = direction.Unit * Movement.WalkwaySpeed
		end
	end
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.WalkSpeed = Movement.WalkSpeed
	end
end

local function onPlayer(player: Player)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

function MovementService.Init()
	startBelts()
end

function MovementService.Start()
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

return MovementService
