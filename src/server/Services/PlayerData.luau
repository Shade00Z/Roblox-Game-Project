--!nonstrict
-- Loads, session-locks and saves each player's profile with ProfileStore.
-- Other services read data with PlayerData.Get(player) and react to loads
-- with PlayerData.OnLoaded(fn) / PlayerData.OnRemoving(fn).

local Players = game:GetService("Players")

local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)

local STORE_NAME = "PlayerData_v1"

-- Every new player starts from a copy of this. Adding a field here is safe:
-- Reconcile() fills it in for existing players on their next join.
local TEMPLATE = {
	coins = 0,
	coreShards = 0,
	rebirths = 0,

	depth = 0, -- meters
	lastUpdate = 0, -- os.time() when growth was last calculated (0 = brand new player)
	boostUntil = 0, -- os.time() when the vein-tap dig burst ends

	cart = {}, -- [oreId] = count
	cartCount = 0,
	gemCoins = 0, -- coins waiting at the Assay Office for gems you have cracked
	gems = {}, -- (old saves only) [gemId] = count; turned into gemCoins on load

	bitLevel = 1, -- index into Economy.Bits
	cartLevel = 1, -- index into Economy.Carts
	pickaxeLevel = 1, -- index into Economy.Pickaxes

	seed = 0, -- this player's mine layout (set on first join)
	front = { top = 0, rows = { 0, 0, 0 }, crew = { targets = {}, turn = 0 } }, -- dig-front blocks already mined, and which block each critter is working (see DigFront)

	critters = {}, -- list of { id = "c1", species = "pebblemole" }
	crew = {}, -- list of critter ids assigned to crew slots
	geodes = {}, -- list of { id = "g2", rarity = "Common", stratum = 3, foundAt = t, maturesAt = t }
	incubators = {}, -- list of { id = "e7", egg = "dirt", startedAt = t, hatchAt = t }
	eggShop = { restock = -1, bought = {} }, -- eggs bought in the current Hatchery restock
	nextId = 1,
	cracks = 0, -- geodes cracked, ever
	gemBook = {}, -- gem id -> how many you have ever found (the Gem Book)
	gemFlawless = {}, -- gem id -> true once you have found a Flawless one
	equippedGems = {}, -- gem ids on your gem stand, in slot order (up to Economy.GemSlots)
	gemSets = {}, -- ["Rare"] = true once that tier of the Gem Book is complete, ["all"] for all 50

	purchases = {}, -- processed Robux receipt ids (Phase 3)
}

local store = ProfileStore.New(STORE_NAME, TEMPLATE)
local profiles: { [Player]: any } = {}
local loadedCallbacks = {}
local removingCallbacks = {}

local PlayerData = {}

function PlayerData.Get(player: Player)
	local profile = profiles[player]
	return profile and profile.Data or nil
end

-- fn(player, data, isNewPlayer)
function PlayerData.OnLoaded(fn)
	table.insert(loadedCallbacks, fn)
end

-- fn(player, data) runs right before the profile is saved and released
function PlayerData.OnRemoving(fn)
	table.insert(removingCallbacks, fn)
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		if player.Parent == Players then
			player:Kick("We couldn't load your mine. Please rejoin in a moment.")
		end
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Your mine was opened on another server. Please rejoin.")
		end
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profiles[player] = profile
	local isNew = profile.Data.lastUpdate == 0
	for _, fn in ipairs(loadedCallbacks) do
		task.spawn(fn, player, profile.Data, isNew)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	for _, fn in ipairs(removingCallbacks) do
		local ok, err = pcall(fn, player, profile.Data)
		if not ok then
			warn("[PlayerData] OnRemoving callback failed:", err)
		end
	end
	profile:EndSession()
end

function PlayerData.Start()
	-- "Access" means progress saves; anything else means Studio is in practice mode
	task.spawn(function()
		local waited = 0
		while ProfileStore.DataStoreState == "NotReady" and waited < 30 do
			waited += task.wait(0.5)
		end
		print("[PlayerData] DataStore state:", ProfileStore.DataStoreState)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return PlayerData
