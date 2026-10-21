--!nonstrict
-- The Drill Shop upgrade panel (opened by the Drill Shop's prompt).
-- Sells the next drill bit (crew digs faster and deeper), pickaxe (you dig faster)
-- and cart size (longer offline cap).

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local Style = require(script.Parent.Style)
local HUD = require(script.Parent.HUD)
local C = Style.Colors

local Shops = {}

local panel
local rows = {}

local function makeRow(order: number, kind: string)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 96)
	row.BackgroundColor3 = Color3.fromHex("F3E6C8")
	row.LayoutOrder = order
	Style.Corner(row, 10)
	Style.Stroke(row, 2)
	row.Parent = panel.Body
	local title = Style.Label(row, "", 22, { heading = true, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -170, 0, 28) })
	local detail = Style.Label(row, "", 16, {
		Position = UDim2.fromOffset(12, 40),
		Size = UDim2.new(1, -170, 0, 44),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.Muted,
	})
	local buy = Style.Button(row, "Buy", C.Green, UDim2.fromOffset(140, 50), function()
		local result = Remotes.RequestUpgrade:InvokeServer(kind)
		if result and result.message then
			HUD.Toast(result.message)
		end
	end)
	buy.Position = UDim2.new(1, -12, 0.5, 0)
	buy.AnchorPoint = Vector2.new(1, 0.5)
	rows[kind] = { title = title, detail = detail, buy = buy }
end

function Shops.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Shops"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	Style.AutoScale(gui)

	panel = Style.Panel(gui, "DrillShop", UDim2.fromOffset(520, 406), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.Visible = false
	Style.Padding(panel, 14)
	Style.Label(panel, "Drill Shop", 30, { heading = true })
	local close = Style.Button(panel, "X", C.Red, UDim2.fromOffset(40, 40), Shops.Close)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.AnchorPoint = Vector2.new(1, 0)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, 50)
	body.Size = UDim2.new(1, 0, 1, -50)
	body.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body

	makeRow(1, "bit")
	makeRow(2, "pickaxe")
	makeRow(3, "cart")

	-- close the panel when the player rides down or walks far away
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("InShaft"):Connect(Shops.Close)
end

local function setBuy(row, cost: number?, coins: number)
	if cost == nil then
		row.buy.Text = "Maxed"
		row.buy.BackgroundColor3 = C.Disabled
		return
	end
	row.buy.Text = Formulas.FormatNumber(cost)
	row.buy.BackgroundColor3 = coins >= cost and C.Green or C.Disabled
end

function Shops.Update(state)
	if not panel then
		return
	end
	local bit = Economy.Bits[state.bitLevel]
	local nextBit = Economy.Bits[state.bitLevel + 1]
	local bitRow = rows.bit
	if nextBit then
		local reach = Formulas.FullSpeedDepth(nextBit.tier)
		bitRow.title.Text = bit.name .. "  →  " .. nextBit.name
		bitRow.detail.Text = string.format(
			"Digs %.2fx faster (now %.2fx) and at full speed down to %s m.",
			nextBit.mult,
			bit.mult,
			reach == math.huge and "the Core" or Formulas.FormatNumber(reach)
		)
	else
		bitRow.title.Text = bit.name
		bitRow.detail.Text = "The best drill bit there is."
	end
	setBuy(bitRow, nextBit and nextBit.cost, state.coins)

	local pick = Economy.Pickaxes[state.pickaxeLevel]
	local nextPick = Economy.Pickaxes[state.pickaxeLevel + 1]
	local pickRow = rows.pickaxe
	if nextPick then
		pickRow.title.Text = pick.name .. "  →  " .. nextPick.name
		pickRow.detail.Text = string.format(
			"Hits %dx harder (now %dx) and swings faster. For digging yourself.",
			nextPick.power,
			pick.power
		)
	else
		pickRow.title.Text = pick.name
		pickRow.detail.Text = "The best pickaxe there is."
	end
	setBuy(pickRow, nextPick and nextPick.cost, state.coins)

	local cart = Economy.Carts[state.cartLevel]
	local nextCart = Economy.Carts[state.cartLevel + 1]
	local cartRow = rows.cart
	if nextCart then
		cartRow.title.Text = string.format("Ore cart: %d  →  %d", cart.capacity, nextCart.capacity)
		cartRow.detail.Text = "A bigger cart keeps your crew mining longer while you're away."
	else
		cartRow.title.Text = string.format("Ore cart: %d", cart.capacity)
		cartRow.detail.Text = "The biggest cart there is."
	end
	setBuy(cartRow, nextCart and nextCart.cost, state.coins)
end

function Shops.Open()
	panel.Visible = true
	local state = HUD.GetState()
	if state then
		Shops.Update(state)
	end
end

function Shops.Close()
	if panel then
		panel.Visible = false
	end
end

return Shops
