--!nonstrict
-- Cracking mature geodes at the Crack Station.
-- (Finding geodes happens inside ShaftService while the crew digs, and DigService.)
--
-- What's inside: one of the 50 gems from the geode's rarity tier (some rarer than
-- others, the same odds in every layer), priced at Economy.GeodeOreWorth of the ore
-- from the layer the geode came from, plus rolls from Economy.GeodeExtras.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local OreConfig = require(Shared.Config.Ores)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)
local ShaftService = require(script.Parent.ShaftService)
local PlotService = require(script.Parent.PlotService)
local CrewService = require(script.Parent.CrewService)

local GeodeService = {}

local rng = Random.new()
local station: BasePart? = nil

-- pool entries are { id, weight }
local function pickWeighted(pool)
	local total = 0
	for _, e in ipairs(pool) do
		total += e[2]
	end
	local roll = rng:NextNumber() * total
	for _, e in ipairs(pool) do
		roll -= e[2]
		if roll <= 0 then
			return e[1]
		end
	end
	return pool[1][1]
end

local function allFound(data, ids: { string }): boolean
	for _, id in ipairs(ids) do
		if (data.gemBook[id] or 0) == 0 then
			return false
		end
	end
	return true
end

-- What the gems in old saves sold for before the 50-gem collection, so gems still
-- held when it arrived keep their value.
local LEGACY_GEM_VALUES = {
	abyssalglass=110000, agate=13, amethystheart=2200, auroralabradorite=2200, bandedagate=33, bandedonyx=240,
	blackopal=1400, bluemoonstone=120, cherryquartz=3500, chevronamethyst=5500, cinderstone=4700, corestar=70000,
	crowngarnet=1200, dawnstone=180000, emberheartstone=2000, eyeofthestorm=36000, fireagate=79, firegarnet=18000,
	galaxyopal=8600, glowingcinder=12000, harlequinopal=3600, heartstone=820, infernogarnet=110000, ironheart=4700,
	labradorite=360, lavapearl=28000, livingheartstone=4900, meteoriron=12000, moltengarnet=44000, moonstone=49,
	nebulaglass=44000, onyx=96, padparadscha=22000, phoenixheart=1800000, phoenixopal=290000, prismheart=37000,
	prismofages=220000, pulseoftheworld=730000, rainbowmoonstone=290, rainbowprism=92000, risingphoenix=730000, rosequartz=590,
	royalamethyst=13000, sardonyx=580, solarflare=420000, souloftheworld=1800000, spectrolite=900, starforgediron=28000,
	stargarnet=200, starrosequartz=1500, starsapphire=8900, stormglass=6000, sunstone=70000, supernova=420000,
	thunderglass=15000, twilightsapphire=53000, twincorestar=180000, twinstargarnet=490, voidglass=18000, worldheart=290000,
}

-- Older saves hold gems by id: turn them into coins waiting at the Assay Office,
-- keep Gem Book entries for gems still in the collection, and drop the rest.
local function migrate(data)
	if next(data.gems) ~= nil then
		for id, n in pairs(data.gems) do
			data.gemCoins += (LEGACY_GEM_VALUES[id] or 0) * n
		end
		data.gems = {}
	end
	for id in pairs(data.gemBook) do
		if not OreConfig.Gems[id] then
			data.gemBook[id] = nil
		end
	end
	for id in pairs(data.gemFlawless) do
		if not OreConfig.Gems[id] then
			data.gemFlawless[id] = nil
		end
	end
	-- page rewards from older book layouts (keyed by layer) are kept as they were
	-- the stand only holds gems that still exist and that you've found
	for i = #data.equippedGems, 1, -1 do
		local id = data.equippedGems[i]
		if not OreConfig.Gems[id] or (data.gemBook[id] or 0) == 0 then
			table.remove(data.equippedGems, i)
		end
	end
end

local function nearStation(player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and station ~= nil and (root.Position - station.Position).Magnitude <= Economy.ShopRange
end

local function crack(player: Player, geodeId: any)
	if type(geodeId) ~= "string" then
		return { ok = false }
	end
	local data = ShaftService.Update(player)
	if not data then
		return { ok = false }
	end
	if not nearStation(player) then
		return { ok = false, message = "Take your geodes to the Crack Station topside." }
	end

	local index, geode
	for i, g in ipairs(data.geodes) do
		if g.id == geodeId then
			index, geode = i, g
			break
		end
	end
	if not geode then
		return { ok = false }
	end
	if geode.maturesAt > os.time() then
		return { ok = false, message = "That geode isn't ready yet." }
	end

	table.remove(data.geodes, index)
	data.cracks += 1

	-- A geode pays out (gem price, ore pouch, which critters) for the shallower of the
	-- layer it was found in and the layer you're in now. In normal play that's where you
	-- found it; after a rebirth, geodes kept from deep down pay what your new depth pays,
	-- so they can't skip the early game. Geodes from before layers were tracked count as
	-- your current layer.
	local here = Formulas.StratumIndexAt(data.depth)
	local si = math.min(geode.stratum or here, here)
	local extras = Economy.GeodeExtras[geode.rarity] or Economy.GeodeExtras.Common

	-- which gem, and what it's worth here (set now, paid at the Assay Office)
	local gemId = OreConfig.RollGem(geode.rarity, rng)
	local flawless = rng:NextNumber() < Economy.FlawlessChance
	local gemValue = OreConfig.GemValue(geode.rarity, si, flawless, data.rebirths)
	data.gemCoins += gemValue

	-- the Gem Book: first finds, Flawless finds, and rewards for finished pages
	local isNew = (data.gemBook[gemId] or 0) == 0
	local newFlawless = flawless and not data.gemFlawless[gemId]
	data.gemBook[gemId] = (data.gemBook[gemId] or 0) + 1
	if flawless then
		data.gemFlawless[gemId] = true
	end
	local completedTier, completedBook = nil, false
	local tier = OreConfig.Gems[gemId].rarity
	if isNew and not data.gemSets[tier] and allFound(data, OreConfig.TierGems(tier)) then
		data.gemSets[tier] = true
		data.coreShards += Economy.GemSetShards
		completedTier = tier
	end
	if isNew and not data.gemSets.all and allFound(data, OreConfig.GemOrder) then
		data.gemSets.all = true
		data.coreShards += Economy.GemBookCompleteShards
		completedBook = true
	end

	-- sometimes a critter from that layer was sleeping inside
	local critterSpecies = nil
	if data.cracks == 1 then
		critterSpecies = Economy.FirstCrackCritter
	elseif rng:NextNumber() < extras.critter then
		critterSpecies = pickWeighted(Economy.Dig.EggPools[si] or Economy.Dig.EggPools[1])
	end
	local joinedCrew = false
	if critterSpecies then
		local critter = CrewService.Give(data, critterSpecies)
		joinedCrew = critter ~= nil and table.find(data.crew, critter.id) ~= nil
	end

	-- a Core Shard: +10% dig speed for good
	local shard = rng:NextNumber() < extras.shard
	if shard then
		data.coreShards += 1
	end

	-- a pouch of the layer's ore, sold on the spot so a full cart never wastes it
	local pouch = nil
	if rng:NextNumber() < extras.pouch then
		local oreId = Formulas.RollOre(Formulas.OreWeights(si, 0), rng)
		local amount = rng:NextInteger(extras.pouchOre[1], extras.pouchOre[2])
		local coins = math.floor(amount * OreConfig.Ores[oreId].value * (1 + ShaftService.Boosts(data).ore))
		data.coins += coins
		pouch = { name = OreConfig.Ores[oreId].name, amount = amount, coins = coins }
	end

	local gem = OreConfig.Gems[gemId]
	Remotes.CrackResult:FireClient(player, {
		rarity = geode.rarity,
		stratum = si,
		gemId = gemId,
		gemName = gem.name,
		gemValue = gemValue,
		chance = OreConfig.GemChance(gemId),
		flawless = flawless,
		newFlawless = newFlawless,
		isNew = isNew,
		completedTier = completedTier,
		setShards = completedTier and Economy.GemSetShards or nil,
		completedBook = completedBook,
		bookShards = completedBook and Economy.GemBookCompleteShards or nil,
		critter = critterSpecies,
		joinedCrew = joinedCrew,
		shard = shard,
		pouch = pouch,
	})
	ShaftService.PushState(player)
	return { ok = true }
end

-- The gem stand: put a gem you've found into a slot (or nil to take it out).
-- Slots fill left to right; taking one out slides the rest along.
local function setGemSlot(player: Player, slot: any, gemId: any)
	if type(slot) ~= "number" or slot ~= slot // 1 or slot < 1 or slot > Formulas.GemSlots(math.huge) then
		return { ok = false }
	end
	if gemId ~= nil and (type(gemId) ~= "string" or not OreConfig.Gems[gemId]) then
		return { ok = false }
	end
	local data = ShaftService.Update(player) -- settle digging with the old boosts first
	if not data then
		return { ok = false }
	end
	local slots = Formulas.GemSlots(data.rebirths)
	if slot > slots then
		return { ok = false, message = "That stand slot unlocks with a rebirth." }
	end
	local list = data.equippedGems
	if gemId == nil then
		if list[slot] then
			table.remove(list, slot)
		end
	else
		if (data.gemBook[gemId] or 0) == 0 then
			return { ok = false, message = "Find that gem first. Crack geodes to fill your Gem Book!" }
		end
		local current = table.find(list, gemId)
		if current then
			table.remove(list, current) -- moving it to another slot
		end
		if slot <= #list then
			list[slot] = gemId
		else
			table.insert(list, gemId)
		end
		while #list > slots do
			table.remove(list)
		end
	end
	ShaftService.PushState(player)
	PlotService.RefreshShowcase(player)
	return { ok = true }
end

function GeodeService.Init()
	Remotes.SetGemSlot.OnServerInvoke = setGemSlot
	PlayerData.OnLoaded(function(_, data)
		migrate(data)
	end)
	ShaftService.AddStateFields(function(data, state)
		state.gemBook = data.gemBook
		state.gemFlawless = data.gemFlawless
		state.gemSets = data.gemSets
	end)

	local building = workspace.Map.Topside:FindFirstChild("Crack Station")
	station = building and building.PrimaryPart
	if not station then
		warn("[GeodeService] Crack Station not found in Workspace.Map.Topside")
	end
	Remotes.CrackGeode.OnServerInvoke = crack
end

return GeodeService
