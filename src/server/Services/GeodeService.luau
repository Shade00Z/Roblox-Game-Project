--!nonstrict
-- Cracking mature geodes at the Crack Station.
-- (Finding geodes happens inside ShaftService while the crew digs.)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local OreConfig = require(Shared.Config.Ores)
local Remotes = require(Shared.Remotes)

local ShaftService = require(script.Parent.ShaftService)
local CrewService = require(script.Parent.CrewService)

local GeodeService = {}

local rng = Random.new()
local station: BasePart? = nil

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

	local gemId = OreConfig.GemByRarity[geode.rarity] or "agate"
	data.gems[gemId] = (data.gems[gemId] or 0) + 1

	-- sometimes a critter was sleeping inside
	local critterSpecies = nil
	if data.cracks == 1 then
		critterSpecies = Economy.FirstCrackCritter
	elseif rng:NextNumber() < Economy.CrackCritterChance then
		local pool = Economy.CrackCritterPool
		critterSpecies = pool[rng:NextInteger(1, #pool)]
	end
	if critterSpecies then
		CrewService.Give(data, critterSpecies)
	end

	local gem = OreConfig.Gems[gemId]
	Remotes.CrackResult:FireClient(player, {
		rarity = geode.rarity,
		gemId = gemId,
		gemName = gem.name,
		gemValue = gem.value,
		critter = critterSpecies,
	})
	ShaftService.PushState(player)
	return { ok = true }
end

function GeodeService.Init()
	local building = workspace.Map.Topside:FindFirstChild("Crack Station")
	station = building and building.PrimaryPart
	if not station then
		warn("[GeodeService] Crack Station not found in Workspace.Map.Topside")
	end
	Remotes.CrackGeode.OnServerInvoke = crack
end

return GeodeService
