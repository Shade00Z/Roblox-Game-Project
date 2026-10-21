--!nonstrict
-- Glowing chevrons that slide along each fast lane so players can see which way it moves.
-- Purely visual and client-only. The server makes the belts actually move people.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Movement = require(Shared.Config.Movement)

local Walkways = {}

local player = Players.LocalPlayer

local SPACING = 8 -- studs between chevrons
local ARM_LENGTH = 3.4
local ARM_WIDTH = 0.45
local ARM_ANGLE = math.rad(35)
local ANIMATE_RANGE = 260 -- only animate when the player is this close

type Lane = {
	belt: BasePart,
	direction: Vector3,
	length: number,
	parts: { BasePart },
	offsets: { number },
}

local lanes: { Lane } = {}
local folder: Folder

local function makeArm(color: Color3): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(ARM_WIDTH, 0.05, ARM_LENGTH)
	p.Parent = folder
	return p
end

local function buildLane(belt: BasePart)
	local direction = belt:GetAttribute("BeltDirection").Unit
	local color = belt:GetAttribute("ChevronColor") or Color3.fromHex("FFC233")
	local lane: Lane = {
		belt = belt,
		direction = direction,
		length = belt.Size.X,
		parts = {},
		offsets = {},
	}
	local count = math.floor(lane.length / SPACING)
	for i = 0, count - 1 do
		-- two arms per chevron, forming a ">" that points along the belt
		table.insert(lane.parts, makeArm(color))
		table.insert(lane.parts, makeArm(color))
		table.insert(lane.offsets, i * SPACING)
	end
	table.insert(lanes, lane)
end

local function animate()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or player:GetAttribute("InShaft") then
		return
	end
	local t = os.clock() * Movement.WalkwaySpeed
	local parts, cframes = {}, {}
	for _, lane in ipairs(lanes) do
		local belt = lane.belt
		if belt.Parent and (belt.Position - root.Position).Magnitude < ANIMATE_RANGE + lane.length / 2 then
			-- belts run along their own X axis
			local sign = belt.CFrame.RightVector:Dot(lane.direction) >= 0 and 1 or -1
			local surfaceY = belt.Size.Y / 2 + 0.03
			for i, base in ipairs(lane.offsets) do
				local along = (base + t) % lane.length - lane.length / 2
				local tip = belt.CFrame * CFrame.new(along * sign, surfaceY, 0)
				-- arms sweep back from the tip, angled to either side
				local back = -sign * ARM_LENGTH / 2 * math.cos(ARM_ANGLE)
				local side = ARM_LENGTH / 2 * math.sin(ARM_ANGLE)
				local yaw = math.rad(90) + sign * ARM_ANGLE
				table.insert(parts, lane.parts[i * 2 - 1])
				table.insert(cframes, tip * CFrame.new(back, 0, side) * CFrame.Angles(0, yaw, 0))
				table.insert(parts, lane.parts[i * 2])
				table.insert(cframes, tip * CFrame.new(back, 0, -side) * CFrame.Angles(0, math.rad(90) - sign * ARM_ANGLE, 0))
			end
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Walkways.Init()
	folder = Instance.new("Folder")
	folder.Name = "LocalWalkwayFX"
	folder.Parent = workspace

	task.spawn(function()
		local map = workspace:WaitForChild("Map", 30)
		local topside = map and map:WaitForChild("Topside", 30)
		local walkways = topside and topside:WaitForChild("Walkways", 30)
		if not walkways then
			return
		end
		-- with streaming on, lanes can arrive after the folder does
		local built = {}
		local function tryLane(belt)
			if not built[belt] and belt:IsA("BasePart") and typeof(belt:GetAttribute("BeltDirection")) == "Vector3" then
				built[belt] = true
				buildLane(belt)
			end
		end
		for _, belt in ipairs(walkways:GetChildren()) do
			tryLane(belt)
		end
		walkways.ChildAdded:Connect(tryLane)
		RunService.RenderStepped:Connect(animate)
	end)
end

return Walkways
