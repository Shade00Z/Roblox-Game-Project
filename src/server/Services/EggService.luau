--!nonstrict
-- The Hatchery: buying fossil eggs from the restocking egg shop, incubating them over
-- real time (offline too), and hatching them into new critters.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Eggs = require(Shared.Config.Eggs)
local Critters = require(Shared.Config.Critters)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)
local ShaftService = require(script.Parent.ShaftService)
local CrewService = require(script.Parent.CrewService)

local EggService = {}

local rng = Random.new()
local hatchery: BasePart? = nil
local readyNotified: { [Player]: { [string]: boolean } } = {}

local function near(player: Player): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and hatchery ~= nil and (root.Position - hatchery.Position).Magnitude <= Economy.ShopRange
end

-- This player's view of the current restock: how many of each egg they can still buy.
-- Everyone sees the same stock; each player has their own "bought" count per restock.
local function shopFor(data, now: number)
	local index = Eggs.RestockIndex(now)
	local shop = data.eggShop
	if shop.restock ~= index then
		shop.restock = index
		shop.bought = {}
	end
	local stock = Eggs.StockFor(index)
	local left = {}
	for id, amount in pairs(stock) do
		left[id] = math.max(0, amount - (shop.bought[id] or 0))
	end
	return {
		nextRestockAt = (index + 1) * Eggs.RestockSeconds,
		left = left,
	}
end

local function rollSpecies(egg): string
	local total = 0
	for _, o in ipairs(egg.odds) do
		total += o[2]
	end
	local roll = rng:NextNumber() * total
	for _, o in ipairs(egg.odds) do
		roll -= o[2]
		if roll <= 0 then
			return o[1]
		end
	end
	return egg.odds[1][1]
end

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------

local function buyEgg(player: Player, eggId: any)
	if type(eggId) ~= "string" then
		return { ok = false }
	end
	local egg = Eggs.Get(eggId)
	local data = ShaftService.Update(player)
	if not (egg and data) then
		return { ok = false }
	end
	if not near(player) then
		return { ok = false, message = "Visit the Hatchery to buy eggs." }
	end

	local now = os.time()
	local shop = shopFor(data, now)
	if (shop.left[egg.id] or 0) <= 0 then
		return { ok = false, message = egg.name .. " is sold out. New stock in " .. Formulas.FormatDuration(shop.nextRestockAt - now) .. "." }
	end
	if #data.incubators >= Eggs.IncubatorSlots then
		return { ok = false, message = "All your incubators are full. Hatch an egg first!" }
	end
	local price = Formulas.Price(egg.price, data.rebirths) -- prices climb with every rebirth
	if data.coins < price then
		return { ok = false, message = "You need " .. Formulas.FormatNumber(price - data.coins) .. " more coins." }
	end

	data.coins -= price
	data.eggShop.bought[egg.id] = (data.eggShop.bought[egg.id] or 0) + 1
	table.insert(data.incubators, {
		id = ShaftService.NewId(data, "e"),
		egg = egg.id,
		startedAt = now,
		hatchAt = now + egg.hatchSeconds,
	})
	ShaftService.PushState(player)
	return { ok = true, message = egg.name .. " is in the incubator. It hatches in " .. Formulas.FormatDuration(egg.hatchSeconds) .. "." }
end

local function hatchEgg(player: Player, incubatorId: any)
	if type(incubatorId) ~= "string" then
		return { ok = false }
	end
	local data = ShaftService.Update(player)
	if not data then
		return { ok = false }
	end
	if not near(player) then
		return { ok = false, message = "Eggs hatch at the Hatchery topside." }
	end

	local index, inc
	for i, x in ipairs(data.incubators) do
		if x.id == incubatorId then
			index, inc = i, x
			break
		end
	end
	if not inc then
		return { ok = false }
	end
	if inc.hatchAt > os.time() then
		return { ok = false, message = "That egg isn't ready yet." }
	end
	local egg = Eggs.Get(inc.egg)
	if not egg then
		return { ok = false }
	end

	table.remove(data.incubators, index)
	local species = rollSpecies(egg)
	local critter = CrewService.Give(data, species)
	local sp = Critters.Species[species]
	if readyNotified[player] then
		readyNotified[player][inc.id] = nil
	end

	Remotes.HatchResult:FireClient(player, {
		egg = egg.id,
		eggName = egg.name,
		species = species,
		name = sp.name,
		rarity = sp.rarity,
		joinedCrew = critter ~= nil and table.find(data.crew, critter.id) ~= nil,
	})
	ShaftService.PushState(player)
	return { ok = true }
end

----------------------------------------------------------------------
-- The Hatchery building: a counter with the four eggs on display, and its prompt
----------------------------------------------------------------------

local function decorate(building: Model)
	local body = building.PrimaryPart
	local groundY = body.Position.Y - body.Size.Y / 2
	local frontZ = body.Position.Z - body.Size.Z / 2

	local counter = Instance.new("Part")
	counter.Name = "EggCounter"
	counter.Anchored = true
	counter.Size = Vector3.new(16, 3, 3)
	counter.Position = Vector3.new(body.Position.X, groundY + 1.5, frontZ - 1.5)
	counter.Color = Color3.fromHex("A0673A")
	counter.Material = Enum.Material.WoodPlanks
	counter.TopSurface = Enum.SurfaceType.Smooth
	counter.Parent = building

	for i, egg in ipairs(Eggs.List) do
		local p = Instance.new("Part")
		p.Name = egg.name
		p.Anchored = true
		p.CanCollide = false
		p.Size = Vector3.new(2.2, 2.8, 2.2)
		p.Color = egg.color
		p.Material = egg.id == "magma" and Enum.Material.Neon or Enum.Material.SmoothPlastic
		p.Position = counter.Position + Vector3.new(-6 + (i - 1) * 4, 1.5 + 1.4, 0)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		p.Parent = building
	end

	local anchor = Instance.new("Part")
	anchor.Name = "HatcheryPromptAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = Vector3.new(body.Position.X, groundY + 3, frontZ - 4)
	anchor.Parent = building

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Hatchery"
	prompt.ActionText = "Buy and hatch eggs"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", "OpenHatchery") -- the client opens the Hatchery panel
	prompt.Parent = anchor
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function EggService.Init()
	local building = workspace.Map.Topside:FindFirstChild("Hatchery")
	if building and building.PrimaryPart then
		hatchery = building.PrimaryPart
		decorate(building)
	else
		warn("[EggService] Hatchery not found in Workspace.Map.Topside")
	end

	Remotes.BuyEgg.OnServerInvoke = buyEgg
	Remotes.HatchEgg.OnServerInvoke = hatchEgg

	ShaftService.AddStateFields(function(data, state)
		state.eggShop = shopFor(data, os.time())
		state.incubators = data.incubators
		state.incubatorSlots = Eggs.IncubatorSlots
	end)

	Players.PlayerRemoving:Connect(function(player)
		readyNotified[player] = nil
	end)
end

function EggService.Start()
	-- let players know when an egg finishes incubating
	while true do
		local now = os.time()
		for _, player in ipairs(Players:GetPlayers()) do
			local data = PlayerData.Get(player)
			if data then
				local seen = readyNotified[player] or {}
				readyNotified[player] = seen
				for _, inc in ipairs(data.incubators) do
					if inc.hatchAt <= now and not seen[inc.id] then
						seen[inc.id] = true
						local egg = Eggs.Get(inc.egg)
						ShaftService.Notify(player, (egg and egg.name or "An egg") .. " is ready to hatch! Visit the Hatchery.")
					end
				end
			end
		end
		task.wait(5)
	end
end

return EggService
