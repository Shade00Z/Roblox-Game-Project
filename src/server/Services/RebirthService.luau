--!nonstrict
-- Rebirth: once you're deep enough, start over from the surface for good.
--
-- Resets: depth, coins (and anything unsold in the cart or from gems), the geode
--         rack, your drill bit, cart and pickaxe, the dig front, and your mine's layout.
-- Keeps:  critters and your crew, eggs in incubators, the Gem Book, your gem stand,
--         Core Shards.
-- Gains:  +Economy.Rebirth.DigPerRebirth crew dig speed for every rebirth, extra slots
--         at some rebirth counts (Economy.Rebirth.Unlocks), and higher shop prices
--         (Formulas.Price) so each run is a little harder than the last.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Formulas = require(Shared.Formulas)
local DigFront = require(Shared.DigFront)
local Remotes = require(Shared.Remotes)

local ShaftService = require(script.Parent.ShaftService)
local PlotService = require(script.Parent.PlotService)

local RebirthService = {}

local rng = Random.new()

-- Reset one save for a rebirth. Returns what was unlocked, if anything.
function RebirthService.Apply(data)
	data.rebirths += 1
	data.depth = 0
	data.coins = 0
	data.cart = {}
	data.cartCount = 0
	data.gemCoins = 0
	data.geodes = {} -- a fresh start: no carrying deep geodes into the new run
	data.boostUntil = 0
	data.bitLevel = 1
	data.cartLevel = 1
	data.pickaxeLevel = 1
	data.seed = rng:NextInteger(1, 16777215) -- a fresh mine to dig
	data.front = DigFront.NewFront(0)
	data.front.crew = { targets = {}, turn = 0 }
	data.lastUpdate = os.time()
	return Economy.Rebirth.Unlocks[data.rebirths]
end

local function rebirth(player: Player)
	local data = ShaftService.Update(player) -- count every last meter first
	if not data then
		return { ok = false }
	end
	local need = Formulas.RebirthDepth(data.rebirths)
	if data.depth < need then
		return {
			ok = false,
			message = string.format("Reach %s m to rebirth. You're at %s m.", Formulas.FormatNumber(need), Formulas.FormatNumber(math.floor(data.depth))),
		}
	end
	-- out of the shaft first, so nobody is left standing in a mine that just reset
	if player:GetAttribute("InShaft") == true then
		PlotService.SendUp(player)
	end
	local unlock = RebirthService.Apply(data)
	ShaftService.PushState(player)
	return {
		ok = true,
		rebirths = data.rebirths,
		digBonus = Formulas.RebirthDig(data.rebirths),
		unlock = unlock and unlock.text or nil,
	}
end

-- Studio only: rebirth right now, whatever your depth
local function debugRebirth(player: Player)
	if not RunService:IsStudio() then
		return { ok = false }
	end
	local data = ShaftService.Update(player)
	if not data then
		return { ok = false }
	end
	if player:GetAttribute("InShaft") == true then
		PlotService.SendUp(player)
	end
	local unlock = RebirthService.Apply(data)
	ShaftService.PushState(player)
	return { ok = true, rebirths = data.rebirths, digBonus = Formulas.RebirthDig(data.rebirths), unlock = unlock and unlock.text or nil }
end

function RebirthService.Init()
	Remotes.Rebirth.OnServerInvoke = rebirth
	Remotes.DebugRebirth.OnServerInvoke = debugRebirth
end

return RebirthService
