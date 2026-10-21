--!nonstrict
-- The Hatchery panel: the restocking egg shop with odds on every egg, your
-- incubators with their timers, and the hatch reveal (wobble, silhouette, reveal).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Eggs = require(Shared.Config.Eggs)
local Critters = require(Shared.Config.Critters)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local Style = require(script.Parent.Style)
local HUD = require(script.Parent.HUD)
local C = Style.Colors

local EggShop = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local panel: Frame
local restockLabel: TextLabel
local eggRows = {}
local incubatorSlots = {}
local state = nil
local timeOffset = 0

local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

local function serverNow(): number
	return os.time() + timeOffset
end

-- An egg-shaped icon: a tall rounded frame
local function eggIcon(parent: Instance, color: Color3, size: number): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(size * 0.78, size)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	Style.Stroke(f, 2)
	-- a little highlight so it reads as a shiny egg
	local shine = Instance.new("Frame")
	shine.Size = UDim2.fromScale(0.22, 0.28)
	shine.Position = UDim2.fromScale(0.22, 0.16)
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.55
	shine.BorderSizePixel = 0
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0.5, 0)
	sc.Parent = shine
	shine.Parent = f
	f.Parent = parent
	return f
end

local function rarityRange(egg): (string, string)
	local lo, hi = nil, nil
	for _, o in ipairs(egg.odds) do
		local r = Critters.Species[o[1]].rarity
		if not lo or RARITY_ORDER[r] < RARITY_ORDER[lo] then
			lo = r
		end
		if not hi or RARITY_ORDER[r] > RARITY_ORDER[hi] then
			hi = r
		end
	end
	return lo, hi
end

local function oddsText(egg): string
	local parts = {}
	for _, p in ipairs(Eggs.Percentages(egg)) do
		local sp = Critters.Species[p.species]
		table.insert(parts, string.format("%s %d%%", sp.name, math.floor(p.percent + 0.5)))
	end
	return table.concat(parts, "  ·  ")
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------

local function buildEggRow(parent: Instance, order: number, egg)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 92)
	row.BackgroundColor3 = Color3.fromHex("F3E6C8")
	row.LayoutOrder = order
	Style.Corner(row, 10)
	Style.Stroke(row, 2)
	row.Parent = parent

	local icon = eggIcon(row, egg.color, 64)
	icon.Position = UDim2.fromOffset(14, 14)

	local lo, hi = rarityRange(egg)
	Style.Label(row, egg.name, 22, { heading = true, Position = UDim2.fromOffset(78, 6), Size = UDim2.new(1, -250, 0, 26) })
	local range = Style.Label(row, lo == hi and lo or (lo .. " to " .. hi), 15, {
		heading = true,
		Position = UDim2.fromOffset(78, 32),
		Size = UDim2.new(1, -250, 0, 18),
		TextColor3 = Critters.RarityColors[hi]:Lerp(C.Outline, 0.35),
	})
	Style.Label(row, oddsText(egg), 13, {
		Position = UDim2.fromOffset(78, 52),
		Size = UDim2.new(1, -250, 0, 34),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.Muted,
	})
	local stockLabel = Style.Label(row, "", 15, {
		Position = UDim2.new(1, -164, 0, 8),
		Size = UDim2.fromOffset(150, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
	})
	local buy = Style.Button(row, Formulas.FormatNumber(egg.price), C.Green, UDim2.fromOffset(150, 50), function()
		local result = Remotes.BuyEgg:InvokeServer(egg.id)
		if result and result.message then
			HUD.Toast(result.message)
		end
	end)
	buy.Position = UDim2.new(1, -14, 1, -12)
	buy.AnchorPoint = Vector2.new(1, 1)
	eggRows[egg.id] = { stock = stockLabel, buy = buy, range = range }
end

local function buildIncubators(parent: Instance)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 120)
	holder.LayoutOrder = 100
	holder.Parent = parent
	Style.Label(holder, "Your incubators", 20, { heading = true, Size = UDim2.new(1, 0, 0, 24) })

	local slots = Instance.new("Frame")
	slots.BackgroundTransparency = 1
	slots.Position = UDim2.fromOffset(0, 28)
	slots.Size = UDim2.new(1, 0, 0, 92)
	slots.Parent = holder
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.Parent = slots

	for i = 1, Eggs.IncubatorSlots do
		local slot = Instance.new("Frame")
		slot.Size = UDim2.new(1 / Eggs.IncubatorSlots, -7, 1, 0)
		slot.BackgroundColor3 = Color3.fromHex("F3E6C8")
		slot.LayoutOrder = i
		Style.Corner(slot, 10)
		Style.Stroke(slot, 2)
		slot.Parent = slots
		local icon = eggIcon(slot, C.Disabled, 52)
		icon.Position = UDim2.fromOffset(10, 20)
		local name = Style.Label(slot, "Empty", 16, { heading = true, Position = UDim2.fromOffset(62, 10), Size = UDim2.new(1, -70, 0, 20) })
		local timer = Style.Label(slot, "Buy an egg above", 14, {
			Position = UDim2.fromOffset(62, 32),
			Size = UDim2.new(1, -70, 0, 18),
			TextColor3 = C.Muted,
		})
		local hatch = Style.Button(slot, "Hatch!", C.Gold, UDim2.new(1, -72, 0, 32), function()
			local inc = incubatorSlots[i].inc
			if not inc then
				return
			end
			local result = Remotes.HatchEgg:InvokeServer(inc.id)
			if result and result.message then
				HUD.Toast(result.message)
			end
		end)
		hatch.Position = UDim2.fromOffset(62, 52)
		hatch.TextSize = 17
		hatch.Visible = false
		incubatorSlots[i] = { icon = icon, name = name, timer = timer, hatch = hatch, inc = nil }
	end
end

function EggShop.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "EggShop"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	-- children always draw above their parent (the reveal card sits on a high ZIndex)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	Style.AutoScale(gui)

	panel = Style.Panel(gui, "Hatchery", UDim2.fromOffset(620, 620), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.Visible = false
	Style.Padding(panel, 14)
	Style.Label(panel, "Hatchery", 30, { heading = true })
	restockLabel = Style.Label(panel, "", 16, { Position = UDim2.fromOffset(0, 34), TextColor3 = C.Muted })
	local close = Style.Button(panel, "X", C.Red, UDim2.fromOffset(40, 40), EggShop.Close)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.AnchorPoint = Vector2.new(1, 0)

	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, 64)
	body.Size = UDim2.new(1, 0, 1, -64)
	body.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body

	for i, egg in ipairs(Eggs.List) do
		buildEggRow(body, i, egg)
	end
	buildIncubators(body)

	player:GetAttributeChangedSignal("InShaft"):Connect(EggShop.Close)

	-- timers tick between state updates
	task.spawn(function()
		while true do
			if panel.Visible then
				EggShop.Refresh()
			end
			task.wait(0.5)
		end
	end)
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------

function EggShop.Refresh()
	if not state or not state.eggShop then
		return
	end
	local now = serverNow()
	local shop = state.eggShop
	restockLabel.Text = "New stock for everyone in " .. Formulas.FormatDuration(shop.nextRestockAt - now)

	local full = #state.incubators >= state.incubatorSlots
	for _, egg in ipairs(Eggs.List) do
		local row = eggRows[egg.id]
		local left = shop.left[egg.id] or 0
		if left <= 0 then
			row.stock.Text = "Sold out"
			row.stock.TextColor3 = C.Red
		else
			row.stock.Text = left .. " in stock"
			row.stock.TextColor3 = C.Muted
		end
		row.buy.BackgroundColor3 = (left > 0 and not full and state.coins >= egg.price) and C.Green or C.Disabled
	end

	for i, slot in ipairs(incubatorSlots) do
		local inc = state.incubators[i]
		slot.inc = inc
		if inc then
			local egg = Eggs.Get(inc.egg)
			slot.icon.BackgroundColor3 = egg and egg.color or C.Disabled
			slot.name.Text = egg and egg.name or "Egg"
			local left = inc.hatchAt - now
			if left <= 0 then
				slot.timer.Text = "Ready to hatch!"
				slot.timer.TextColor3 = Color3.fromHex("2E9E44")
				slot.hatch.Visible = true
				-- a gentle wobble so ready eggs catch your eye
				slot.icon.Rotation = math.sin(os.clock() * 8) * 8
			else
				slot.timer.Text = "Hatches in " .. Formulas.FormatDuration(left)
				slot.timer.TextColor3 = C.Muted
				slot.hatch.Visible = false
				slot.icon.Rotation = 0
			end
		else
			slot.icon.BackgroundColor3 = C.Disabled
			slot.icon.Rotation = 0
			slot.name.Text = "Empty"
			slot.timer.Text = "Buy an egg above"
			slot.timer.TextColor3 = C.Muted
			slot.hatch.Visible = false
		end
	end
end

function EggShop.Update(newState)
	state = newState
	timeOffset = newState.serverTime - os.time()
	if panel and panel.Visible then
		EggShop.Refresh()
	end
end

function EggShop.Open()
	panel.Visible = true
	EggShop.Refresh()
end

function EggShop.Close()
	if panel then
		panel.Visible = false
	end
end

----------------------------------------------------------------------
-- Hatch reveal: the egg wobbles, cracks into a dark silhouette, then reveals
----------------------------------------------------------------------

local revealCard: Frame? = nil

function EggShop.ShowHatch(result)
	if revealCard then
		revealCard:Destroy()
	end
	local egg = Eggs.Get(result.egg)
	local sp = Critters.Species[result.species]
	local rarityColor = Critters.RarityColors[result.rarity] or C.Gold

	local card = Style.Panel(gui, "HatchReveal", UDim2.fromOffset(380, 424), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	card.ZIndex = 20
	Style.Padding(card, 16)
	revealCard = card
	local title = Style.Label(card, "Hatching your " .. result.eggName .. "...", 20, {
		heading = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
	})

	local stage = Instance.new("Frame")
	stage.BackgroundTransparency = 1
	stage.Size = UDim2.fromOffset(200, 200)
	stage.Position = UDim2.new(0.5, 0, 0, 40)
	stage.AnchorPoint = Vector2.new(0.5, 0)
	stage.Parent = card

	local eggFrame = eggIcon(stage, egg and egg.color or C.Gold, 170)
	eggFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	eggFrame.Position = UDim2.fromScale(0.5, 0.5)

	task.spawn(function()
		-- three wobbles, each a bit stronger
		for i = 1, 3 do
			local angle = 8 + i * 6
			TweenService:Create(eggFrame, TweenInfo.new(0.09), { Rotation = angle }):Play()
			task.wait(0.09)
			TweenService:Create(eggFrame, TweenInfo.new(0.18), { Rotation = -angle }):Play()
			task.wait(0.18)
			TweenService:Create(eggFrame, TweenInfo.new(0.09), { Rotation = 0 }):Play()
			task.wait(0.35)
		end
		if not card.Parent then
			return
		end
		-- crack: the egg pops away and a dark silhouette appears
		TweenService:Create(eggFrame, TweenInfo.new(0.15), { Size = UDim2.fromOffset(0, 0) }):Play()
		local critter = Instance.new("Frame")
		critter.AnchorPoint = Vector2.new(0.5, 0.5)
		critter.Position = UDim2.fromScale(0.5, 0.5)
		critter.Size = UDim2.fromOffset(140, 140)
		critter.BackgroundColor3 = Color3.fromHex("1E140E")
		critter.BorderSizePixel = 0
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0.5, 0)
		cc.Parent = critter
		local ring = Style.Stroke(critter, 6, rarityColor)
		ring.Transparency = 1
		critter.Parent = stage
		-- eyes, so the silhouette reads as a critter
		for _, x in ipairs({ 0.36, 0.64 }) do
			local eye = Instance.new("Frame")
			eye.AnchorPoint = Vector2.new(0.5, 0.5)
			eye.Position = UDim2.fromScale(x, 0.42)
			eye.Size = UDim2.fromOffset(16, 16)
			eye.BackgroundColor3 = Color3.new(1, 1, 1)
			eye.BorderSizePixel = 0
			local ec = Instance.new("UICorner")
			ec.CornerRadius = UDim.new(0.5, 0)
			ec.Parent = eye
			eye.Parent = critter
		end
		title.Text = "???"
		task.wait(0.6)
		if not card.Parent then
			return
		end

		-- reveal: color floods in and the rarity ring lights up
		TweenService:Create(critter, TweenInfo.new(0.35), { BackgroundColor3 = sp.color }):Play()
		TweenService:Create(ring, TweenInfo.new(0.35), { Transparency = 0 }):Play()
		local s = card:FindFirstChildOfClass("UIStroke")
		s.Color = rarityColor
		s.Thickness = 5
		title.Text = result.rarity .. " critter!"
		title.TextColor3 = rarityColor:Lerp(C.Outline, 0.35)
		Style.Label(card, sp.name, 36, {
			heading = true,
			outlined = true,
			Position = UDim2.fromOffset(0, 244),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = rarityColor,
		})
		local where = result.joinedCrew and "It joined your crew and starts digging right away!"
			or "Your crew is full, so it's resting on the bench. Swap it in from the Crew menu."
		Style.Label(card, where, 15, {
			Position = UDim2.fromOffset(0, 286),
			Size = UDim2.new(1, 0, 0, 40),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local ok = Style.Button(card, "Nice!", C.Green, UDim2.fromOffset(160, 46), function()
			card:Destroy()
			if revealCard == card then
				revealCard = nil
			end
		end)
		ok.Position = UDim2.new(0.5, 0, 1, 0)
		ok.AnchorPoint = Vector2.new(0.5, 1)
	end)
end

return EggShop
