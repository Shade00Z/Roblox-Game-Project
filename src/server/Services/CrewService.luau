--!nonstrict
-- Your critters: assigning them to crew slots, giving new ones, and merging,
-- selling and locking them.
--
-- Merging: two of the same species at the same star level become one critter a star
-- higher (up to Economy.Merge.MaxStars). The survivor keeps its crew slot and lock;
-- a critter on your crew or locked is never the one used up.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Critters = require(Shared.Config.Critters)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local ShaftService = require(script.Parent.ShaftService)

local CrewService = {}

local MAX_STARS = Economy.Merge.MaxStars

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- Give a critter; it joins the crew automatically if there's a free slot.
function CrewService.Give(data, species: string)
	if not Critters.Species[species] then
		return nil
	end
	local critter = { id = ShaftService.NewId(data, "c"), species = species, stars = 0 }
	table.insert(data.critters, critter)
	if #data.crew < Economy.CrewSlots then
		table.insert(data.crew, critter.id)
	end
	return critter
end

local function find(data, critterId: string)
	for i, c in ipairs(data.critters) do
		if c.id == critterId then
			return c, i
		end
	end
	return nil, nil
end

local function onCrew(data, critterId: string): boolean
	return table.find(data.crew, critterId) ~= nil
end

-- Take a critter off the crew, freeing its block at the dig front
local function removeFromCrew(data, critterId: string)
	local index = table.find(data.crew, critterId)
	if index then
		table.remove(data.crew, index)
		if data.front and data.front.crew then
			table.remove(data.front.crew.targets, index)
		end
	end
end

local function removeCritter(data, critterId: string)
	removeFromCrew(data, critterId)
	local _, index = find(data, critterId)
	if index then
		table.remove(data.critters, index)
	end
end

local function starsOf(c): number
	return c.stars or 0
end

local function label(c): string
	local sp = Critters.Species[c.species]
	local stars = starsOf(c)
	return (stars > 0 and (stars .. "-star ") or "") .. sp.name
end

-- Merge two critters. Returns the survivor, or nil and a reason.
local function mergePair(data, a, b)
	if a.id == b.id or a.species ~= b.species or starsOf(a) ~= starsOf(b) then
		return nil, "You can only merge two of the same critter with the same stars."
	end
	if starsOf(a) >= MAX_STARS then
		return nil, "That critter is already at " .. MAX_STARS .. " stars."
	end
	if a.locked and b.locked then
		return nil, "Both critters are locked. Unlock one to merge them."
	end
	-- a locked critter always survives; otherwise the one on your crew does
	local survivor, consumed = a, b
	if b.locked then
		survivor, consumed = b, a
	elseif not a.locked and onCrew(data, b.id) and not onCrew(data, a.id) then
		survivor, consumed = b, a
	end
	-- if the used-up one was working, the survivor takes over its crew slot
	local slot = table.find(data.crew, consumed.id)
	if slot and not onCrew(data, survivor.id) then
		data.crew[slot] = survivor.id
	end
	removeCritter(data, consumed.id)
	survivor.stars = starsOf(survivor) + 1
	return survivor, nil
end

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------

local function setCrew(player: Player, critterId: any, assign: any)
	if type(critterId) ~= "string" or type(assign) ~= "boolean" then
		return { ok = false }
	end
	-- settle time with the old crew before changing it
	local data = ShaftService.Update(player)
	if not data or not find(data, critterId) then
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
		-- the rested critter's block is freed; everyone else keeps their own
		removeFromCrew(data, critterId)
	end

	ShaftService.SyncFront(data)
	ShaftService.PushState(player)
	return { ok = true }
end

local function mergeCritters(player: Player, idA: any, idB: any)
	if type(idA) ~= "string" or type(idB) ~= "string" then
		return { ok = false }
	end
	local data = ShaftService.Update(player) -- settle digging with the old stats first
	if not data then
		return { ok = false }
	end
	local a, b = find(data, idA), find(data, idB)
	if not (a and b) then
		return { ok = false }
	end
	local survivor, reason = mergePair(data, a, b)
	if not survivor then
		return { ok = false, message = reason }
	end
	ShaftService.SyncFront(data)
	ShaftService.PushState(player)
	return { ok = true, message = "Merged into a " .. label(survivor) .. "!", critterId = survivor.id }
end

-- Merge every pair possible, cascading up the stars. Never uses up a critter that's
-- on your crew or locked (those are only ever the survivor).
local function mergeAll(player: Player)
	local data = ShaftService.Update(player)
	if not data then
		return { ok = false }
	end
	local merges = 0
	for stars = 0, MAX_STARS - 1 do
		local groups = {}
		for _, c in ipairs(data.critters) do
			if starsOf(c) == stars then
				groups[c.species] = groups[c.species] or {}
				table.insert(groups[c.species], c)
			end
		end
		for _, list in pairs(groups) do
			local keepers, spares = {}, {}
			for _, c in ipairs(list) do
				if c.locked or onCrew(data, c.id) then
					table.insert(keepers, c)
				else
					table.insert(spares, c)
				end
			end
			-- crew and locked critters level up first, then spares pair up
			while #keepers > 0 and #spares > 0 do
				if mergePair(data, table.remove(keepers, 1), table.remove(spares, 1)) then
					merges += 1
				end
			end
			while #spares >= 2 do
				if mergePair(data, table.remove(spares, 1), table.remove(spares, 1)) then
					merges += 1
				end
			end
		end
	end
	if merges == 0 then
		return { ok = false, message = "Nothing to merge. You need two of the same critter with the same stars." }
	end
	ShaftService.SyncFront(data)
	ShaftService.PushState(player)
	return { ok = true, message = string.format("Made %d merge%s!", merges, merges == 1 and "" or "s") }
end

local function sellCritter(player: Player, critterId: any)
	if type(critterId) ~= "string" then
		return { ok = false }
	end
	local data = ShaftService.Update(player)
	local c = data and find(data, critterId)
	if not c then
		return { ok = false }
	end
	if c.locked then
		return { ok = false, message = "That critter is locked. Unlock it to sell it." }
	end
	if onCrew(data, c.id) then
		return { ok = false, message = "Rest that critter first. Only bench critters can be sold." }
	end
	local value = Formulas.CritterSellValue(c.species, starsOf(c))
	removeCritter(data, c.id)
	data.coins += value
	ShaftService.PushState(player)
	return { ok = true, message = "Sold your " .. label(c) .. " for " .. Formulas.FormatNumber(value) .. " coins." }
end

local function toggleLock(player: Player, critterId: any)
	if type(critterId) ~= "string" then
		return { ok = false }
	end
	local data = ShaftService.Update(player)
	local c = data and find(data, critterId)
	if not c then
		return { ok = false }
	end
	c.locked = not c.locked or nil -- stored only when locked
	ShaftService.PushState(player)
	return { ok = true, locked = c.locked == true }
end

function CrewService.Init()
	Remotes.SetCrew.OnServerInvoke = setCrew
	Remotes.MergeCritters.OnServerInvoke = mergeCritters
	Remotes.MergeAll.OnServerInvoke = mergeAll
	Remotes.SellCritter.OnServerInvoke = sellCritter
	Remotes.ToggleLock.OnServerInvoke = toggleLock
end

return CrewService
