--!nonstrict
-- Selling at the Assay Office and buying upgrades at the Drill Shop.
-- Sells the next drill bit, cart size and pickaxe. Restocking shops come in Phase 2.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local ShaftService = require(script.Parent.ShaftService)

local ShopService = {}

local drillShop: BasePart? = nil

local function near(player: Player, part: BasePart?): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and part ~= nil and (root.Position - part.Position).Magnitude <= Economy.ShopRange
end

-- An invisible spot in front of a building's sign for its prompt to live on
local function promptAnchor(building: Model): BasePart
	local body = building.PrimaryPart
	local anchor = Instance.new("Part")
	anchor.Name = "PromptAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = Vector3.new(body.Position.X, body.Position.Y - body.Size.Y / 2 + 3, body.Position.Z - body.Size.Z / 2 - 2)
	anchor.Parent = building
	return anchor
end

local function addPrompt(parent: Instance, action: string, objectText: string, actionText: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = objectText
	prompt.ActionText = actionText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", action)
	prompt.Parent = parent
	return prompt
end

function ShopService.Sell(player: Player)
	local data = ShaftService.Update(player)
	if not data then
		return
	end
	-- gem stand Ore value boosts the ore, not the gems (they're already priced)
	local value = math.floor(Formulas.CartValue(data.cart) * (1 + ShaftService.Boosts(data).ore)) + data.gemCoins
	if value <= 0 then
		ShaftService.Notify(player, "Nothing to sell yet. Your crew is still digging!")
		return
	end
	data.coins += value
	data.cart = {}
	data.cartCount = 0
	data.gemCoins = 0
	ShaftService.Notify(player, "Sold for " .. Formulas.FormatNumber(value) .. " coins!")
	ShaftService.PushState(player)
end

local function requestUpgrade(player: Player, kind: any)
	if kind ~= "bit" and kind ~= "cart" and kind ~= "pickaxe" then
		return { ok = false }
	end
	local data = ShaftService.Update(player)
	if not data then
		return { ok = false }
	end
	if not near(player, drillShop) then
		return { ok = false, message = "Visit the Drill Shop to buy upgrades." }
	end

	local lists = { bit = Economy.Bits, cart = Economy.Carts, pickaxe = Economy.Pickaxes }
	local fields = { bit = "bitLevel", cart = "cartLevel", pickaxe = "pickaxeLevel" }
	local list, field = lists[kind], fields[kind]
	local nextItem = list[data[field] + 1]
	if not nextItem then
		return { ok = false, message = "Already maxed out!" }
	end
	local cost = Formulas.Price(nextItem.cost, data.rebirths) -- prices climb with every rebirth
	if data.coins < cost then
		return { ok = false, message = "You need " .. Formulas.FormatNumber(cost - data.coins) .. " more coins." }
	end

	data.coins -= cost
	data[field] += 1

	local message
	if kind == "bit" or kind == "pickaxe" then
		message = "Equipped the " .. nextItem.name .. "!"
	else
		message = "Your cart now holds " .. Formulas.FormatNumber(nextItem.capacity) .. " ore."
	end
	ShaftService.PushState(player)
	return { ok = true, message = message }
end

function ShopService.Init()
	local topside = workspace.Map.Topside

	local assay = topside:FindFirstChild("Assay Office")
	if assay then
		local sell = addPrompt(promptAnchor(assay), "Sell", "Assay Office", "Sell ore and gems")
		sell.Triggered:Connect(ShopService.Sell)
	end

	local shop = topside:FindFirstChild("Drill Shop")
	if shop then
		drillShop = shop.PrimaryPart
		-- the client opens the upgrade panel when this prompt fires
		addPrompt(promptAnchor(shop), "OpenUpgrades", "Drill Shop", "Upgrades")
	end

	local station = topside:FindFirstChild("Crack Station")
	if station then
		addPrompt(promptAnchor(station), "OpenRack", "Crack Station", "Crack geodes")
	end

	Remotes.RequestUpgrade.OnServerInvoke = requestUpgrade
end

return ShopService
