--!nonstrict
-- Digging yourself: each pickaxe swing is a request the server checks before it counts.
-- What's inside every block comes from DigFront.CellAt, so the client can show it
-- without the server ever sending block data.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Strata = require(Shared.Config.Strata)
local Critters = require(Shared.Config.Critters)
local OreConfig = require(Shared.Config.Ores)
local Formulas = require(Shared.Formulas)
local DigFront = require(Shared.DigFront)
local Remotes = require(Shared.Remotes)

local PlotService = require(script.Parent.PlotService)
local ShaftService = require(script.Parent.ShaftService)
local CrewService = require(script.Parent.CrewService)

local DigService = {}

local rng = Random.new()

-- per player: the block currently being hit and when the last swing landed
local swings: { [Player]: { key: string, hits: number, last: number } } = {}
local lastCartWarning: { [Player]: number } = {}

local function pickEgg(stratumIndex: number): string
	local pool = Economy.Dig.EggPools[stratumIndex] or Economy.Dig.EggPools[1]
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

local function warnCartFull(player: Player)
	local last = lastCartWarning[player] or 0
	if os.clock() - last > 10 then
		lastCartWarning[player] = os.clock()
		ShaftService.Notify(player, "Your cart is full! Sell at the Assay Office topside.")
	end
end

-- Hand out what was inside a broken block
local function reward(player: Player, data, cell)
	if cell.kind == "ore" then
		if ShaftService.AddOre(data, { [cell.oreId] = 1 }) == 0 then
			warnCartFull(player)
		end
	elseif cell.kind == "pocket" then
		local amount = rng:NextInteger(Economy.Dig.PocketOre[1], Economy.Dig.PocketOre[2])
		local added = ShaftService.AddOre(data, { [cell.oreId] = amount })
		if added == 0 then
			warnCartFull(player)
		end
		Remotes.DigFind:FireClient(player, {
			kind = "pocket",
			name = OreConfig.Ores[cell.oreId].name,
			amount = added,
			lost = amount - added,
		})
	elseif cell.kind == "geode" then
		if #data.geodes < Economy.RackSlots then
			local luck = Formulas.CrewLuck(ShaftService.CrewMembers(data)) + ShaftService.Boosts(data).luck + Economy.Dig.BuriedGeodeLuck
			local rarity = Formulas.RollGeodeRarity(rng, luck)
			local now = os.time()
			table.insert(data.geodes, {
				id = ShaftService.NewId(data, "g"),
				rarity = rarity,
				stratum = cell.stratum, -- the layer decides what's inside
				foundAt = now,
				maturesAt = now + Formulas.GeodeMatureSeconds(rarity),
			})
			Remotes.DigFind:FireClient(player, { kind = "geode", rarity = rarity })
		else
			-- no room on the rack: it cracks open early into ore instead of vanishing
			local ores = Strata[cell.stratum].ores
			local added = ShaftService.AddOre(data, { [ores[1]] = 3 })
			Remotes.DigFind:FireClient(player, { kind = "geodeFull", amount = added, name = OreConfig.Ores[ores[1]].name })
		end
	elseif cell.kind == "egg" then
		local species = pickEgg(cell.stratum)
		CrewService.Give(data, species)
		local sp = Critters.Species[species]
		Remotes.DigFind:FireClient(player, { kind = "egg", species = species, name = sp.name, rarity = sp.rarity })
	end
end

local function onSwing(player: Player, meter: any, col: any)
	-- shape checks first: never trust what the client sends
	if type(meter) ~= "number" or type(col) ~= "number" then
		return
	end
	meter, col = math.floor(meter), math.floor(col)
	if col < 0 or col >= DigFront.WIDTH then
		return
	end
	if player:GetAttribute("InShaft") ~= true then
		return
	end

	-- swing rate: anything faster than the pickaxe allows is ignored
	local data = ShaftService.Update(player)
	if not data then
		return
	end
	local pick = Economy.Pickaxes[data.pickaxeLevel] or Economy.Pickaxes[1]
	local now = os.clock()
	local state = swings[player]
	if state and now - state.last < pick.swing * 0.75 then
		return
	end

	-- the block must be in your front, not already dug, reachable and in range
	local front = data.front
	local row = meter - front.top + 1
	if row < 1 or row > DigFront.ROWS then
		return
	end
	if DigFront.IsMined(front.rows[row], col) or not DigFront.Exposed(front, row, col) then
		return
	end
	local room = PlotService.GetRoom(player:GetAttribute("PlotIndex"))
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (room and root) then
		return
	end
	local blockPos = DigFront.CellPosition(room:GetAttribute("Origin"), row, col)
	if (root.Position - blockPos).Magnitude > Economy.Dig.Reach then
		return
	end

	-- count the hit
	local key = meter .. ":" .. col
	if not state or state.key ~= key then
		state = { key = key, hits = 0, last = 0 }
		swings[player] = state
	end
	state.hits += 1
	state.last = now
	if state.hits < DigFront.HitsNeeded(meter, data.pickaxeLevel, data.bitLevel) then
		return
	end

	-- the block breaks
	swings[player] = { key = "", hits = 0, last = now }
	front.rows[row] = DigFront.SetMined(front.rows[row], col)
	reward(player, data, DigFront.CellAt(data.seed, meter, col))
	ShaftService.SyncFront(data)
	ShaftService.PushState(player)
end

function DigService.Init()
	Remotes.MineBlock.OnServerEvent:Connect(onSwing)
	Players.PlayerRemoving:Connect(function(player)
		swings[player] = nil
		lastCartWarning[player] = nil
	end)
end

return DigService
