--!nonstrict
-- Always-on-screen HUD: coins, depth, ore cart, geode rack, crew, toasts and reveals.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Strata = require(Shared.Config.Strata)
local Economy = require(Shared.Config.Economy)
local Critters = require(Shared.Config.Critters)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local Style = require(script.Parent.Style)
local C = Style.Colors

local HUD = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local state = nil
local timeOffset = 0 -- serverTime - local os.time()
local lastStratum = nil

-- widgets
local coinsLabel, depthLabel, stratumLabel, rateLabel, bitLabel
local cartFill, cartLabel, cartFrame
local rackFrame, rackSlots = nil, {}
local crewButton, crewPanel, crewList
local toastHolder
local revealCard

local function serverNow(): number
	return os.time() + timeOffset
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------

local function buildCoins()
	local f = Style.Panel(gui, "Coins", UDim2.fromOffset(220, 56), UDim2.fromOffset(16, 16))
	local coin = Instance.new("Frame")
	coin.Size = UDim2.fromOffset(30, 30)
	coin.Position = UDim2.fromOffset(13, 13)
	coin.BackgroundColor3 = C.Gold
	Style.Corner(coin, 15)
	Style.Stroke(coin, 2)
	coin.Parent = f
	coinsLabel = Style.Label(f, "0", 30, {
		heading = true,
		Position = UDim2.fromOffset(54, 0),
		Size = UDim2.new(1, -62, 1, 0),
	})
end

local function buildDepth()
	local f = Style.Panel(gui, "Depth", UDim2.fromOffset(250, 132), UDim2.new(1, -16, 0, 16), Vector2.new(1, 0))
	Style.Padding(f, 10)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	depthLabel = Style.Label(f, "0 m", 36, { heading = true, LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Right })
	stratumLabel = Style.Label(f, "Clay Beds", 20, { heading = true, LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Right })
	rateLabel = Style.Label(f, "", 16, { LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Right })
	bitLabel = Style.Label(f, "", 16, { LayoutOrder = 4, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Muted })
end

local function buildCart()
	cartFrame = Style.Panel(gui, "Cart", UDim2.fromOffset(440, 46), UDim2.new(0.5, 0, 1, -16), Vector2.new(0.5, 1))
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -16, 1, -16)
	track.Position = UDim2.fromOffset(8, 8)
	track.BackgroundColor3 = C.Track
	Style.Corner(track, 8)
	track.Parent = cartFrame
	cartFill = Instance.new("Frame")
	cartFill.Size = UDim2.fromScale(0, 1)
	cartFill.BackgroundColor3 = C.Green
	Style.Corner(cartFill, 8)
	cartFill.Parent = track
	cartLabel = Style.Label(track, "Cart", 18, {
		heading = true,
		outlined = true,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
end

local function buildRack()
	rackFrame = Instance.new("Frame")
	rackFrame.Name = "GeodeRack"
	rackFrame.BackgroundTransparency = 1
	rackFrame.AnchorPoint = Vector2.new(0.5, 1)
	rackFrame.Position = UDim2.new(0.5, 0, 1, -72)
	rackFrame.Size = UDim2.fromOffset(440, 92)
	rackFrame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = rackFrame
	for i = 1, Economy.RackSlots do
		local slot = Style.Panel(rackFrame, "Slot" .. i, UDim2.fromOffset(104, 92), UDim2.new())
		slot.LayoutOrder = i
		local title = Style.Label(slot, "Empty", 16, {
			heading = true,
			Position = UDim2.fromOffset(0, 6),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local timer = Style.Label(slot, "", 15, {
			Position = UDim2.fromOffset(0, 28),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.Muted,
		})
		local button = Style.Button(slot, "Crack", C.Gold, UDim2.fromOffset(84, 30), function()
			local geode = rackSlots[i].geode
			if not geode then
				return
			end
			local result = Remotes.CrackGeode:InvokeServer(geode.id)
			if result and not result.ok and result.message then
				HUD.Toast(result.message)
			end
		end)
		button.Position = UDim2.new(0.5, 0, 1, -8)
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.TextSize = 17
		button.Visible = false
		rackSlots[i] = { frame = slot, title = title, timer = timer, button = button, geode = nil }
	end
end

local function buildCrew()
	crewButton = Style.Button(gui, "Crew", C.Blue, UDim2.fromOffset(150, 52), function()
		crewPanel.Visible = not crewPanel.Visible
	end)
	crewButton.Position = UDim2.new(0, 16, 0.5, 0)
	crewButton.AnchorPoint = Vector2.new(0, 0.5)

	crewPanel = Style.Panel(gui, "CrewPanel", UDim2.fromOffset(460, 380), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	crewPanel.Visible = false
	crewPanel.ZIndex = 5
	Style.Padding(crewPanel, 14)
	Style.Label(crewPanel, "Your crew", 28, { heading = true, Name = "Title" })
	local close = Style.Button(crewPanel, "X", C.Red, UDim2.fromOffset(40, 40), function()
		crewPanel.Visible = false
	end)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.AnchorPoint = Vector2.new(1, 0)

	crewList = Instance.new("ScrollingFrame")
	crewList.Size = UDim2.new(1, 0, 1, -48)
	crewList.Position = UDim2.fromOffset(0, 48)
	crewList.BackgroundTransparency = 1
	crewList.BorderSizePixel = 0
	crewList.ScrollBarThickness = 6
	crewList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	crewList.CanvasSize = UDim2.new()
	crewList.Parent = crewPanel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = crewList
end

-- Elevator button: only shown while you're down in your shaft
local function buildRideUp()
	local b = Style.Button(gui, "Ride up", C.Gold, UDim2.fromOffset(150, 52), function()
		Remotes.RideUp:FireServer()
	end)
	b.Name = "RideUp"
	b.Position = UDim2.new(0, 16, 0.5, 64)
	b.AnchorPoint = Vector2.new(0, 0.5)
	local function refresh()
		b.Visible = player:GetAttribute("InShaft") == true
	end
	player:GetAttributeChangedSignal("InShaft"):Connect(refresh)
	refresh()
end

local function buildToasts()
	toastHolder = Instance.new("Frame")
	toastHolder.BackgroundTransparency = 1
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.new(0.5, 0, 0, 16)
	toastHolder.Size = UDim2.fromOffset(480, 300)
	toastHolder.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = toastHolder
end

local function buildDevTools()
	if not RunService:IsStudio() then
		return
	end
	local b = Style.Button(gui, "+1 hour (Studio)", C.Muted, UDim2.fromOffset(180, 40), function()
		Remotes.DebugSkipTime:FireServer(3600)
	end)
	b.Position = UDim2.new(0, 16, 1, -16)
	b.AnchorPoint = Vector2.new(0, 1)
	b.TextSize = 16
end

----------------------------------------------------------------------
-- Crew list
----------------------------------------------------------------------

local crewSignature = ""

local function refreshCrew()
	if not state then
		return
	end
	crewButton.Text = string.format("Crew %d/%d", #state.crew, state.crewSlots)
	crewPanel.Title.Text = string.format("Your crew  (%d/%d working)", #state.crew, state.crewSlots)

	-- only rebuild the list when something changed
	local sig = table.concat(state.crew, ",") .. "|" .. #state.critters
	if sig == crewSignature then
		return
	end
	crewSignature = sig

	for _, child in ipairs(crewList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for order, critter in ipairs(state.critters) do
		local sp = Critters.Species[critter.species]
		if sp then
			local working = table.find(state.crew, critter.id) ~= nil
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -10, 0, 64)
			row.BackgroundColor3 = working and Color3.fromHex("F3E6C8") or C.Panel
			row.LayoutOrder = working and order or order + 1000
			Style.Corner(row, 10)
			Style.Stroke(row, 2, Critters.RarityColors[sp.rarity])
			row.Parent = crewList
			Style.Label(row, sp.name, 20, {
				heading = true,
				Position = UDim2.fromOffset(12, 6),
				Size = UDim2.new(1, -150, 0, 24),
			})
			local stats = string.format("%s  ·  Dig %.1f", sp.rarity, sp.dig)
			if sp.luck > 0 then
				stats ..= string.format("  ·  Luck +%d%%", sp.luck * 100)
			end
			if sp.heat > 0 then
				stats ..= "  ·  Heat " .. sp.heat
			end
			Style.Label(row, stats, 15, {
				Position = UDim2.fromOffset(12, 34),
				Size = UDim2.new(1, -150, 0, 20),
				TextColor3 = C.Muted,
			})
			local b = Style.Button(row, working and "Rest" or "Assign", working and C.Orange or C.Green, UDim2.fromOffset(110, 40), function()
				local result = Remotes.SetCrew:InvokeServer(critter.id, not working)
				if result and result.message then
					HUD.Toast(result.message)
				end
			end)
			b.Position = UDim2.new(1, -10, 0.5, 0)
			b.AnchorPoint = Vector2.new(1, 0.5)
		end
	end
end

----------------------------------------------------------------------
-- Per-frame refresh (timers)
----------------------------------------------------------------------

local function refreshRack()
	if not state then
		return
	end
	local now = serverNow()
	for i, slot in ipairs(rackSlots) do
		local geode = state.geodes[i]
		slot.geode = geode
		local border = slot.frame:FindFirstChildOfClass("UIStroke")
		if geode then
			local rarityColor = Critters.RarityColors[geode.rarity] or C.Outline
			slot.title.Text = geode.rarity
			-- darken the rarity color so it reads on the cream panel
			slot.title.TextColor3 = rarityColor:Lerp(C.Outline, 0.45)
			slot.title.TextStrokeTransparency = 1
			if border and not slot.flashing then
				border.Color = rarityColor:Lerp(C.Outline, 0.2)
			end
			local left = geode.maturesAt - now
			if left <= 0 then
				slot.timer.Text = "Ready!"
				slot.button.Visible = true
			else
				slot.timer.Text = Formulas.FormatDuration(left)
				slot.button.Visible = false
			end
		else
			slot.title.Text = "Empty"
			slot.title.TextColor3 = C.Disabled
			slot.title.TextStrokeTransparency = 1
			slot.timer.Text = "geode slot"
			slot.button.Visible = false
			if border and not slot.flashing then
				border.Color = C.Outline
			end
		end
	end
end

local function refreshRate()
	if not state then
		return
	end
	local boosted = state.boostUntil > serverNow()
	local rate = state.digRate * (boosted and Economy.BoostMultiplier or 1)
	local full = state.cartCount >= state.cartCapacity
	if full then
		rate *= Economy.CartFullDigFactor
	end
	local text = string.format("%.2f m/min", rate)
	if state.toughRock > 0 then
		text ..= "  ·  tough rock"
		rateLabel.TextColor3 = C.Orange
	elseif boosted then
		text ..= "  ·  BOOST x" .. Economy.BoostMultiplier
		rateLabel.TextColor3 = Color3.fromHex("2E9E44")
	elseif full then
		text ..= "  ·  cart full"
		rateLabel.TextColor3 = C.Orange
	else
		rateLabel.TextColor3 = C.Text
	end
	rateLabel.Text = text
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------

function HUD.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	Style.AutoScale(gui)

	buildCoins()
	buildDepth()
	buildRack()
	buildCart()
	buildCrew()
	buildRideUp()
	buildToasts()
	buildDevTools()

	task.spawn(function()
		while true do
			refreshRack()
			refreshRate()
			task.wait(0.25)
		end
	end)
end

function HUD.Update(newState)
	local first = state == nil
	state = newState
	timeOffset = newState.serverTime - os.time()

	coinsLabel.Text = Formulas.FormatNumber(state.coins)
	depthLabel.Text = string.format("%.1f m", state.depth)

	local stratum = Strata[state.stratum]
	stratumLabel.Text = stratum.name
	stratumLabel.TextColor3 = stratum.rockColor:Lerp(C.Text, 0.35)
	local bit = Economy.Bits[state.bitLevel]
	if state.fullSpeedTo == math.huge then
		bitLabel.Text = bit.name .. "  ·  full speed everywhere"
	else
		bitLabel.Text = string.format("%s  ·  full speed to %s m", bit.name, Formulas.FormatNumber(state.fullSpeedTo))
	end

	local frac = state.cartCount / state.cartCapacity
	TweenService:Create(cartFill, TweenInfo.new(0.3), { Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1) }):Play()
	cartFill.BackgroundColor3 = frac >= 1 and C.Red or (frac >= 0.8 and C.Orange or C.Green)
	local value = state.cartValue + state.gemsValue
	cartLabel.Text = string.format("Cart %d / %d  ·  worth %s", state.cartCount, state.cartCapacity, Formulas.FormatNumber(value))

	if not first and lastStratum and state.stratum > lastStratum then
		HUD.Banner("You reached the " .. stratum.name .. "!")
	end
	lastStratum = state.stratum

	refreshCrew()
	refreshRack()
	refreshRate()
end

function HUD.GetState()
	return state
end

function HUD.Toast(message: string)
	local t = Style.Panel(toastHolder, "Toast", UDim2.fromOffset(460, 44), UDim2.new())
	Style.Label(t, message, 18, {
		heading = true,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
	})
	task.delay(3.5, function()
		TweenService:Create(t, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.wait(0.3)
		t:Destroy()
	end)
end

function HUD.Banner(text: string)
	local l = Style.Label(gui, text, 54, {
		heading = true,
		outlined = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.fromOffset(900, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 0, TextStrokeTransparency = 0 }):Play()
	task.delay(3, function()
		TweenService:Create(l, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.6)
		l:Destroy()
	end)
end

-- Pulse the rack so players notice where the Crack buttons are
function HUD.FlashRack()
	HUD.Toast("Tap Crack on a ready geode below.")
	for _, slot in ipairs(rackSlots) do
		local s = slot.frame:FindFirstChildOfClass("UIStroke")
		if s then
			slot.flashing = true
			s.Color = C.Gold
			task.delay(1.5, function()
				slot.flashing = false
			end)
		end
	end
end

-- Something special came out of a block you dug yourself
function HUD.ShowFind(find)
	if find.kind == "pocket" then
		HUD.Banner(string.format("Ore pocket! +%d %s", find.amount, find.name))
		if find.lost and find.lost > 0 then
			HUD.Toast("Your cart couldn't hold it all. Sell at the Assay Office!")
		end
	elseif find.kind == "geode" then
		HUD.Banner("You dug up a " .. find.rarity .. " geode!")
	elseif find.kind == "geodeFull" then
		HUD.Toast(string.format("Your geode rack is full, so the geode crumbled into %d %s.", find.amount, find.name))
	elseif find.kind == "egg" then
		if revealCard then
			revealCard:Destroy()
		end
		local color = Critters.RarityColors[find.rarity] or C.Gold
		revealCard = Style.Panel(gui, "Reveal", UDim2.fromOffset(420, 230), UDim2.fromScale(0.5, 0.42), Vector2.new(0.5, 0.5))
		revealCard.ZIndex = 10
		Style.Padding(revealCard, 16)
		local s = revealCard:FindFirstChildOfClass("UIStroke")
		s.Color = color
		s.Thickness = 5
		local scale = Instance.new("UIScale")
		scale.Scale = 0.3
		scale.Parent = revealCard
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		Style.Label(revealCard, "Fossil egg!", 20, { heading = true, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Muted })
		Style.Label(revealCard, find.name, 40, {
			heading = true,
			outlined = true,
			Position = UDim2.fromOffset(0, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = color,
		})
		Style.Label(revealCard, find.rarity .. " critter · it hatched and joined your crew!", 17, {
			Position = UDim2.fromOffset(0, 84),
			Size = UDim2.new(1, 0, 0, 40),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local ok = Style.Button(revealCard, "Welcome!", C.Green, UDim2.fromOffset(160, 46), function()
			revealCard:Destroy()
			revealCard = nil
		end)
		ok.Position = UDim2.new(0.5, 0, 1, 0)
		ok.AnchorPoint = Vector2.new(0.5, 1)
	end
end

-- The geode reveal card
function HUD.ShowCrack(result)
	if revealCard then
		revealCard:Destroy()
	end
	local color = Critters.RarityColors[result.rarity] or C.Gold
	revealCard = Style.Panel(gui, "Reveal", UDim2.fromOffset(420, 250), UDim2.fromScale(0.5, 0.45), Vector2.new(0.5, 0.5))
	revealCard.ZIndex = 10
	Style.Padding(revealCard, 16)
	local s = revealCard:FindFirstChildOfClass("UIStroke")
	s.Color = color
	s.Thickness = 5

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = revealCard
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	Style.Label(revealCard, result.rarity .. " geode", 20, {
		heading = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
	})
	Style.Label(revealCard, result.gemName .. "!", 42, {
		heading = true,
		outlined = true,
		Position = UDim2.fromOffset(0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color,
	})
	Style.Label(revealCard, "Worth " .. Formulas.FormatNumber(result.gemValue) .. " coins at the Assay Office", 17, {
		Position = UDim2.fromOffset(0, 84),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	if result.critter then
		local sp = Critters.Species[result.critter]
		Style.Label(revealCard, "A " .. sp.name .. " was sleeping inside! It joined your crew.", 17, {
			heading = true,
			Position = UDim2.fromOffset(0, 112),
			Size = UDim2.new(1, 0, 0, 44),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Critters.RarityColors[sp.rarity],
		})
	end
	local ok = Style.Button(revealCard, "Nice!", C.Green, UDim2.fromOffset(160, 46), function()
		revealCard:Destroy()
		revealCard = nil
	end)
	ok.Position = UDim2.new(0.5, 0, 1, 0)
	ok.AnchorPoint = Vector2.new(0.5, 1)
end

return HUD
