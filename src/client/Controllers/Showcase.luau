--!nonstrict
-- Spins the gems on every player's gem stand (the server places them; see
-- PlotService). Purely visual and local: each device animates the stands it can see.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Showcase = {}

local RADIUS = 3
local gems: { [BasePart]: boolean } = {}

local function add(part: Instance)
	if part:IsA("BasePart") then
		gems[part] = true
	end
end

function Showcase.Init()
	for _, part in ipairs(CollectionService:GetTagged("ShowcaseGem")) do
		add(part)
	end
	CollectionService:GetInstanceAddedSignal("ShowcaseGem"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("ShowcaseGem"):Connect(function(part)
		gems[part] = nil
	end)

	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for part in pairs(gems) do
			local center = part:GetAttribute("Center")
			if center and part.Parent then
				local slot = part:GetAttribute("Slot") or 1
				local slots = part:GetAttribute("Slots") or 3
				local angle = t * 0.6 + (slot - 1) / slots * math.pi * 2
				local bob = math.sin(t * 2 + slot * 2) * 0.25
				part.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * RADIUS, bob, math.sin(angle) * RADIUS))
					* CFrame.Angles(t * 1.1 + slot, t * 0.7, math.rad(45))
			end
		end
	end)
end

return Showcase
