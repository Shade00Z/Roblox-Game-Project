--!nonstrict
-- Assigning critters to crew slots, and giving players new critters.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Critters = require(Shared.Config.Critters)
local Remotes = require(Shared.Remotes)

local ShaftService = require(script.Parent.ShaftService)

local CrewService = {}

-- Give a critter; it joins the crew automatically if there's a free slot.
function CrewService.Give(data, species: string)
	if not Critters.Species[species] then
		return nil
	end
	local critter = { id = ShaftService.NewId(data, "c"), species = species }
	table.insert(data.critters, critter)
	if #data.crew < Economy.CrewSlots then
		table.insert(data.crew, critter.id)
	end
	return critter
end

local function owns(data, critterId: string): boolean
	for _, c in ipairs(data.critters) do
		if c.id == critterId then
			return true
		end
	end
	return false
end

local function setCrew(player: Player, critterId: any, assign: any)
	if type(critterId) ~= "string" or type(assign) ~= "boolean" then
		return { ok = false }
	end
	-- settle time with the old crew before changing it
	local data = ShaftService.Update(player)
	if not data or not owns(data, critterId) then
		return { ok = false }
	end

	local index = table.find(data.crew, critterId)
	if assign then
		if index then
			return { ok = true }
		end
		if #data.crew >= Economy.CrewSlots then
			return { ok = false, message = "All crew slots are full. Remove a critter first." }
		end
		table.insert(data.crew, critterId)
	else
		if not index then
			return { ok = true }
		end
		table.remove(data.crew, index)
		-- the rested critter's block is freed; everyone else keeps their own
		if data.front and data.front.crew then
			table.remove(data.front.crew.targets, index)
		end
	end

	ShaftService.SyncFront(data)
	ShaftService.PushState(player)
	return { ok = true }
end

function CrewService.Init()
	Remotes.SetCrew.OnServerInvoke = setCrew
end

return CrewService
