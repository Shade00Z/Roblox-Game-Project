--!nonstrict
-- The heart of the game: depth growth, ore, geode finds, offline catch-up and vein taps.
--
-- Growth is never simulated in a loop per second of time. Update() looks at how long
-- it has been since data.lastUpdate and solves the whole span at once, so 1 second
-- online and 9 hours offline cost the same.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Strata = require(Shared.Config.Strata)
local Economy = require(Shared.Config.Economy)
local Ores = require(Shared.Config.Ores).Ores
local Formulas = require(Shared.Formulas)
local DigFront = require(Shared.DigFront)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)
local PlotService = require(script.Parent.PlotService)

local ShaftService = {}

local rng = Random.new()
local tapLog: { [Player]: { number } } = {}
local cartFullNotified: { [Player]: number } = {}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- The critters on your crew, in crew order: { { species = id, stars = n }, ... }
-- (stars make a critter dig faster, see Formulas.StarMultiplier)
function ShaftService.CrewMembers(data): { any }
	local byId = {}
	for _, c in ipairs(data.critters) do
		byId[c.id] = c
	end
	local list = {}
	for _, id in ipairs(data.crew) do
		local c = byId[id]
		if c then
			table.insert(list, { species = c.species, stars = c.stars or 0 })
		end
	end
	return list
end

function ShaftService.NewId(data, prefix: string): string
	local id = prefix .. data.nextId
	data.nextId += 1
	return id
end

local function cartCapacity(data): number
	return Economy.Carts[data.cartLevel].capacity
end

-- Adds ore to the cart, never past capacity. Returns how many units fit.
-- Totals from the gem stand: { dig, heat, luck, ore, geode }
-- Totals from the gem stand: { dig, heat, luck, ore, geode }, plus `rebirth`,
-- the permanent dig bonus from rebirths
function ShaftService.Boosts(data)
	local boosts = Formulas.GemBoosts(data.equippedGems, data.gemFlawless)
	boosts.rebirth = Formulas.RebirthDig(data.rebirths)
	return boosts
end

function ShaftService.AddOre(data, ore: { [string]: number }): number
	local room = cartCapacity(data) - data.cartCount
	local added = 0
	for id, n in pairs(ore) do
		local take = math.min(n, room - added)
		if take <= 0 then
			break
		end
		data.cart[id] = (data.cart[id] or 0) + take
		added += take
	end
	data.cartCount += added
	return added
end

----------------------------------------------------------------------
-- The growth solver
----------------------------------------------------------------------

-- Advance a player's shaft from data.lastUpdate to `now`.
-- Splits time at every point where the dig rate changes (a new stratum, the cart
-- filling, the vein boost ending) and solves each piece exactly.
-- Fills in `summary` if given.
local function advanceDepth(data, now: number, summary)
	local from = data.lastUpdate
	if now <= from then
		data.lastUpdate = math.max(from, now)
		return
	end

	local species = ShaftService.CrewMembers(data)
	local boosts = ShaftService.Boosts(data)
	local luck = Formulas.CrewLuck(species) + boosts.luck
	local bit = Economy.Bits[data.bitLevel]
	local capacity = cartCapacity(data)

	local t = from
	for _ = 1, 64 do -- a span never needs more than a handful of pieces
		if t >= now then
			break
		end
		local si = Formulas.StratumIndexAt(data.depth)
		local stratum = Strata[si]
		local boosted = data.boostUntil > t
		local full = data.cartCount >= capacity

		-- includes the slowdown when this rock is too tough for your bit
		local rate = Formulas.DigRate(species, si, bit.mult, data.coreShards, bit.tier, boosts) / 60 -- meters per second
		if boosted then
			rate *= Economy.BoostMultiplier
		end
		if full then
			rate *= Economy.CartFullDigFactor
		end
		if rate <= 0 then
			break
		end

		-- when does the rate next change?
		local stopDepth = stratum.bottom
		local pieceEnd = math.min(now, t + (stopDepth - data.depth) / rate)
		if boosted then
			pieceEnd = math.min(pieceEnd, data.boostUntil)
		end
		if not full then
			local metersUntilFull = (capacity - data.cartCount) / Economy.OrePerMeter
			pieceEnd = math.min(pieceEnd, t + metersUntilFull / rate)
		end

		local dt = math.max(pieceEnd - t, 0)
		local meters = rate * dt
		data.depth = math.min(data.depth + meters, stopDepth)
		if stopDepth - data.depth < 1e-6 then
			data.depth = stopDepth -- land exactly on the boundary
		end

		if not full and meters > 0 then
			local weights = Formulas.OreWeights(si, luck)
			local ore = Formulas.DistributeOre(weights, meters * Economy.OrePerMeter, rng)
			local added = ShaftService.AddOre(data, ore)
			if summary then
				summary.ore += added
				for id, n in pairs(ore) do
					summary.oreById[id] = (summary.oreById[id] or 0) + n
				end
			end
		end

		-- geodes: expected count, with random rounding
		local expected = meters * Economy.GeodeChancePerMeter * (1 + luck) * (1 + boosts.geode)
		local count = math.floor(expected)
		if rng:NextNumber() < expected - count then
			count += 1
		end
		for k = 1, count do
			if #data.geodes >= Formulas.RackSlots(data.rebirths) then
				break
			end
			local rarity = Formulas.RollGeodeRarity(rng, luck)
			local foundAt = math.floor(t + dt * k / (count + 1))
			table.insert(data.geodes, {
				id = ShaftService.NewId(data, "g"),
				rarity = rarity,
				stratum = si, -- the layer decides what's inside
				foundAt = foundAt,
				maturesAt = foundAt + Formulas.GeodeMatureSeconds(rarity),
			})
			if summary then
				summary.geodes += 1
			end
		end

		if summary then
			summary.meters += meters
			local newSi = Formulas.StratumIndexAt(data.depth)
			if newSi > si then
				table.insert(summary.newStrata, Strata[newSi].name)
			end
		end

		if dt <= 0 and data.depth < stopDepth then
			break -- nothing can move; avoid spinning
		end
		t = pieceEnd
	end

	data.lastUpdate = now
end

-- Keep the visible dig front in step with depth (see DigFront.Sync).
-- Returns how many rows broke through.
function ShaftService.SyncFront(data): number
	return DigFront.Sync(data, math.huge, #ShaftService.CrewMembers(data))
end

local function advance(data, now: number, summary)
	advanceDepth(data, now, summary)
	ShaftService.SyncFront(data)
end

local function newSummary()
	return { meters = 0, ore = 0, oreById = {}, geodes = 0, newStrata = {} }
end

-- Bring a player's shaft up to the current time. Call before any action that reads
-- or changes depth, cart, crew or upgrades, so the old values apply to the past.
function ShaftService.Update(player: Player)
	local data = PlayerData.Get(player)
	if data then
		advance(data, os.time(), nil)
	end
	return data
end

----------------------------------------------------------------------
-- State for the client
----------------------------------------------------------------------

-- Other services can add their own fields to the client state (e.g. the Hatchery)
local stateExtras = {}
function ShaftService.AddStateFields(fn: (any, any) -> ())
	table.insert(stateExtras, fn)
end

function ShaftService.BuildState(data)
	local now = os.time()
	local si = Formulas.StratumIndexAt(data.depth)
	local species = ShaftService.CrewMembers(data)
	local boosts = ShaftService.Boosts(data)
	local bit = Economy.Bits[data.bitLevel]
	local nextBit = Economy.Bits[data.bitLevel + 1]
	local nextCart = Economy.Carts[data.cartLevel + 1]
	local state = {
		serverTime = now,
		coins = data.coins,
		depth = data.depth,
		stratum = si,
		fullSpeedTo = Formulas.FullSpeedDepth(bit.tier), -- deeper than this is tough rock
		toughRock = Formulas.TiersShort(bit.tier, si), -- bit tiers short for this stratum
		digRate = Formulas.DigRate(species, si, bit.mult, data.coreShards, bit.tier, boosts),
		boostUntil = data.boostUntil,
		cartCount = data.cartCount,
		cartCapacity = cartCapacity(data),
		cartValue = math.floor(Formulas.CartValue(data.cart) * (1 + boosts.ore)),
		gemBoosts = boosts,
		equippedGems = data.equippedGems,
		gemSlots = Formulas.GemSlots(data.rebirths),
		rebirths = data.rebirths,
		rebirthDepth = Formulas.RebirthDepth(data.rebirths),
		gemsValue = data.gemCoins,
		bitLevel = data.bitLevel,
		cartLevel = data.cartLevel,
		pickaxeLevel = data.pickaxeLevel,
		nextBitCost = nextBit and Formulas.Price(nextBit.cost, data.rebirths) or nil,
		nextCartCost = nextCart and Formulas.Price(nextCart.cost, data.rebirths) or nil,
		seed = data.seed,
		front = data.front,
		critters = data.critters,
		crew = data.crew,
		crewSlots = Formulas.CrewSlots(data.rebirths),
		geodes = data.geodes,
		rackSlots = Formulas.RackSlots(data.rebirths),
	}
	for _, addFields in ipairs(stateExtras) do
		addFields(data, state)
	end
	return state
end

function ShaftService.PushState(player: Player)
	local data = PlayerData.Get(player)
	if data then
		Remotes.State:FireClient(player, ShaftService.BuildState(data))
	end
end

function ShaftService.Notify(player: Player, message: string)
	Remotes.Notify:FireClient(player, message)
end

----------------------------------------------------------------------
-- Joining and the "While you were away" screen
----------------------------------------------------------------------

local function catchUp(player: Player, data, minSeconds: number)
	local now = os.time()
	local away = now - data.lastUpdate
	local depthBefore = data.depth
	local summary = newSummary()
	advance(data, now, summary)

	if away >= minSeconds then
		local oreValue = 0
		for id, n in pairs(summary.oreById) do
			oreValue += (Ores[id] and Ores[id].value or 0) * n
		end
		oreValue = math.floor(oreValue * (1 + ShaftService.Boosts(data).ore))
		Remotes.AwaySummary:FireClient(player, {
			seconds = away,
			meters = data.depth - depthBefore,
			ore = summary.ore,
			oreValue = oreValue,
			geodes = summary.geodes,
			newStrata = summary.newStrata,
			cartFull = data.cartCount >= cartCapacity(data),
			toughRock = Formulas.TiersShort(Economy.Bits[data.bitLevel].tier, Formulas.StratumIndexAt(data.depth)) > 0,
		})
	end
end

local function setUpNewPlayer(data)
	local now = os.time()
	data.lastUpdate = now
	local moleId = ShaftService.NewId(data, "c")
	table.insert(data.critters, { id = moleId, species = "pebblemole" })
	table.insert(data.crew, moleId)
	-- a starter geode that is already mature, so the first session has a crack moment
	table.insert(data.geodes, {
		id = ShaftService.NewId(data, "g"),
		rarity = "Common",
		stratum = 1,
		foundAt = now - 3600,
		maturesAt = now,
	})
end

----------------------------------------------------------------------
-- Vein taps
----------------------------------------------------------------------

local function rateLimited(player: Player): boolean
	local now = os.clock()
	local log = tapLog[player] or {}
	tapLog[player] = log
	while log[1] and now - log[1] > 1 do
		table.remove(log, 1)
	end
	if #log >= Economy.MaxTapsPerSecond then
		return true
	end
	table.insert(log, now)
	return false
end

local VEIN_ON_COLOR = Color3.fromHex("FFD166")
local VEIN_OFF_COLOR = Color3.fromHex("6E4A2A")

local function onVeinTapped(player: Player, plotIndex: number, vein: BasePart)
	if player:GetAttribute("PlotIndex") ~= plotIndex or player:GetAttribute("InShaft") ~= true then
		return
	end
	if (vein:GetAttribute("CooldownUntil") or 0) > os.clock() then
		return
	end
	if rateLimited(player) then
		return
	end
	local data = ShaftService.Update(player)
	if not data then
		return
	end

	-- reward: a little ore plus a dig-speed burst
	local si = Formulas.StratumIndexAt(data.depth)
	local luck = Formulas.CrewLuck(ShaftService.CrewMembers(data)) + ShaftService.Boosts(data).luck
	local weights = Formulas.OreWeights(si, luck)
	local ore = {}
	for _ = 1, Economy.VeinOre do
		local id = Formulas.RollOre(weights, rng)
		ore[id] = (ore[id] or 0) + 1
	end
	local added = ShaftService.AddOre(data, ore)
	data.boostUntil = math.max(data.boostUntil, os.time() + Economy.BoostSeconds)

	if added == 0 then
		local last = cartFullNotified[player] or 0
		if os.clock() - last > 10 then
			cartFullNotified[player] = os.clock()
			ShaftService.Notify(player, "Your cart is full! Sell at the Assay Office topside.")
		end
	end

	-- the vein goes dull, then glows again
	vein:SetAttribute("CooldownUntil", os.clock() + Economy.VeinCooldown)
	vein.Material = Enum.Material.SmoothPlastic
	vein.Color = VEIN_OFF_COLOR
	task.delay(Economy.VeinCooldown, function()
		if vein.Parent then
			vein.Material = Enum.Material.Neon
			vein.Color = VEIN_ON_COLOR
		end
	end)

	ShaftService.PushState(player)
end

-- The client raycasts the tap itself (so the invisible front wall doesn't block it)
-- and only sends which vein; the server decides whether it counts.
local function wireVeins()
	Remotes.TapVein.OnServerEvent:Connect(function(player, veinIndex)
		if type(veinIndex) ~= "number" then
			return
		end
		local plotIndex = player:GetAttribute("PlotIndex")
		local room = plotIndex and PlotService.GetRoom(plotIndex)
		if not room then
			return
		end
		for _, part in ipairs(room.Shell:GetChildren()) do
			if part.Name == "Vein" and part:GetAttribute("VeinIndex") == veinIndex then
				onVeinTapped(player, plotIndex, part)
				return
			end
		end
	end)
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function ShaftService.Init()
	PlayerData.OnLoaded(function(player, data, isNew)
		if data.seed == 0 then
			data.seed = rng:NextInteger(1, 16777215) -- this player's own mine layout
		end
		if isNew then
			setUpNewPlayer(data)
		else
			catchUp(player, data, Economy.AwaySummaryMinSeconds)
		end
		ShaftService.PushState(player)
	end)

	PlayerData.OnRemoving(function(player, data)
		advance(data, os.time(), nil)
		tapLog[player] = nil
		cartFullNotified[player] = nil
	end)

	-- Studio-only: pretend the player was away, to test offline progress quickly
	Remotes.DebugSkipTime.OnServerEvent:Connect(function(player, seconds)
		if not RunService:IsStudio() or type(seconds) ~= "number" then
			return
		end
		local data = ShaftService.Update(player)
		if not data then
			return
		end
		seconds = math.clamp(math.floor(seconds), 1, 7 * 86400)
		data.lastUpdate -= seconds
		data.boostUntil = 0
		for _, g in ipairs(data.geodes) do
			g.foundAt -= seconds
			g.maturesAt -= seconds
		end
		for _, inc in ipairs(data.incubators or {}) do
			inc.startedAt -= seconds
			inc.hatchAt -= seconds
		end
		catchUp(player, data, 0)
		ShaftService.PushState(player)
	end)

	-- Studio only: a geode of the chosen rarity, from your current layer, ready to crack
	Remotes.DebugGiveGeode.OnServerInvoke = function(player, rarity)
		if not RunService:IsStudio() then
			return { ok = false }
		end
		local known = false
		for _, r in ipairs(Economy.GeodeRarities) do
			if r.name == rarity then
				known = true
			end
		end
		if not known then
			return { ok = false }
		end
		local data = ShaftService.Update(player)
		if not data then
			return { ok = false }
		end
		if #data.geodes >= Formulas.RackSlots(data.rebirths) then
			return { ok = false, message = "Your geode rack is full. Crack one first." }
		end
		local now = os.time()
		table.insert(data.geodes, {
			id = ShaftService.NewId(data, "g"),
			rarity = rarity,
			stratum = Formulas.StratumIndexAt(data.depth),
			foundAt = now,
			maturesAt = now,
		})
		ShaftService.PushState(player)
		return { ok = true, message = rarity .. " geode added to your rack." }
	end

	-- Studio only: start over as a brand-new player (rebirth 0, nothing found)
	Remotes.DebugResetSave.OnServerInvoke = function(player)
		if not RunService:IsStudio() then
			return { ok = false }
		end
		if player:GetAttribute("InShaft") == true then
			PlotService.SendUp(player)
		end
		local data = PlayerData.ResetForTesting(player)
		if not data then
			return { ok = false }
		end
		data.seed = rng:NextInteger(1, 16777215)
		setUpNewPlayer(data)
		ShaftService.PushState(player)
		PlotService.RefreshShowcase(player)
		return { ok = true }
	end
end

function ShaftService.Start()
	wireVeins()
	-- once a second: bring every online player up to date and refresh their HUD
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			if ShaftService.Update(player) then
				ShaftService.PushState(player)
			end
		end
		task.wait(1)
	end
end

return ShaftService
