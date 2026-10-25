--!nonstrict
-- Always-on-screen HUD: coins, depth, ore cart, geode rack, crew, toasts and reveals.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Strata = require(Shared.Config.Strata)
local OreConfig = require(Shared.Config.Ores)
local Economy = require(Shared.Config.Economy)
local Critters = require(Shared.Config.Critters)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local Style = require(script.Parent.Style)
local C = Style.Colors

local HUD = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local overlay: ScreenGui -- toasts, banners and confirm cards: above every other panel
local state = nil
local timeOffset = 0 -- serverTime - local os.time()
local lastStratum = nil

-- widgets
local coinsLabel, depthLabel, stratumLabel, rateLabel, bitLabel, heatLabel, depthPanel
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

-- pink badge under the coins: which rebirth you're on and what it gives
local rebirthBadge, rebirthLabel
local function buildRebirthBadge()
	rebirthBadge = Style.Panel(gui, "RebirthBadge", UDim2.fromOffset(220, 40), UDim2.fromOffset(16, 80))
	rebirthBadge.BackgroundColor3 = Color3.fromHex("E0479E")
	rebirthBadge.Visible = false
	rebirthLabel = Style.Label(rebirthBadge, "", 18, {
		heading = true,
		outlined = true,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
end

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
	depthPanel = f
	Style.Padding(f, 10)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	depthLabel = Style.Label(f, "0 m", 36, { heading = true, LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Right })
	stratumLabel = Style.Label(f, "Clay Beds", 20, { heading = true, LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Right })
	rateLabel = Style.Label(f, "", 16, { LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Right })
	bitLabel = Style.Label(f, "", 16, { LayoutOrder = 4, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Muted })
	-- only shown in hot strata when the crew lacks Heat
	heatLabel = Style.Label(f, "", 15, {
		heading = true,
		LayoutOrder = 5,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Color3.fromHex("D63B3B"),
		Visible = false,
	})
end

-- How fast a critter digs here because of heat (1 = full speed)
local function heatSpeed(critter, stratumIndex: number): number
	local sp = Critters.Species[critter.species]
	local stratum = Strata[stratumIndex]
	if not (sp and stratum) then
		return 1
	end
	-- Heat gems on the stand add to every critter's Heat
	local gemHeat = state and state.gemBoosts and state.gemBoosts.heat or 0
	return Formulas.HeatFactor(Formulas.CritterStats(critter.species, critter.stars or 0).heat + gemHeat, stratum.heat)
end

-- The crew's overall speed from heat, weighted by how much each critter digs
local function crewHeatSpeed(): number
	local total, effective = 0, 0
	for _, id in ipairs(state.crew) do
		for _, c in ipairs(state.critters) do
			if c.id == id then
				local dig = Formulas.CritterStats(c.species, c.stars or 0).dig
				total += dig
				effective += dig * heatSpeed(c, state.stratum)
			end
		end
	end
	return total > 0 and effective / total or 1
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
	rackFrame.Size = UDim2.fromOffset(560, 92) -- room for slots unlocked by rebirths
	rackFrame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = rackFrame
	local _, maxRack = Formulas.MaxSlots()
	for i = 1, maxRack do
		local slot = Style.Panel(rackFrame, "Slot" .. i, UDim2.fromOffset(104, 92), UDim2.new())
		slot.Visible = i <= Economy.RackSlots
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

	crewPanel = Style.Panel(gui, "CrewPanel", UDim2.fromOffset(640, 480), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	crewPanel.Visible = false
	crewPanel.ZIndex = 5
	Style.Padding(crewPanel, 14)
	Style.Label(crewPanel, "Your crew", 26, { heading = true, Name = "Title", Size = UDim2.new(1, -230, 0, 32) })
	Style.Label(crewPanel, "Merge two of the same critter with the same stars to make it a star stronger.", 14, {
		Name = "Hint",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, -230, 0, 18),
		TextColor3 = C.Muted,
	})
	local close = Style.Button(crewPanel, "X", C.Red, UDim2.fromOffset(40, 40), function()
		crewPanel.Visible = false
	end)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.AnchorPoint = Vector2.new(1, 0)
	local mergeAll = Style.Button(crewPanel, "Merge all", Color3.fromHex("9B5DE5"), UDim2.fromOffset(150, 40), function()
		HUD.Confirm(
			"Merge all?",
			"Every matching pair will merge, cascading up the stars. Locked critters and critters on your crew are never used up.",
			"Merge all",
			Color3.fromHex("9B5DE5"),
			function()
				local result = Remotes.MergeAll:InvokeServer()
				if result and result.message then
					if result.ok then
						HUD.Banner(result.message)
					else
						HUD.Toast(result.message)
					end
				end
			end
		)
	end)
	mergeAll.Position = UDim2.new(1, -50, 0, 0)
	mergeAll.AnchorPoint = Vector2.new(1, 0)
	mergeAll.TextSize = 18

	crewList = Instance.new("ScrollingFrame")
	crewList.Size = UDim2.new(1, 0, 1, -60)
	crewList.Position = UDim2.fromOffset(0, 60)
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
	toastHolder.ZIndex = 40 -- above open panels
	toastHolder.Parent = overlay
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = toastHolder
end

local function buildDevTools()
	if not RunService:IsStudio() then
		return
	end
	local function devButton(text, row, onClick)
		local b = Style.Button(gui, text, C.Muted, UDim2.fromOffset(200, 40), onClick)
		b.Position = UDim2.new(0, 16, 1, -16 - (row - 1) * 48)
		b.AnchorPoint = Vector2.new(0, 1)
		b.TextSize = 16
		return b
	end
	devButton("+1 hour (Studio)", 1, function()
		Remotes.DebugSkipTime:FireServer(3600)
	end)
	devButton("Instant rebirth (Studio)", 2, function()
		HUD.Confirm("Rebirth now?", "Testing only: rebirths you right away, whatever your depth.", "Rebirth", Color3.fromHex("E0479E"), function()
			local result = Remotes.DebugRebirth:InvokeServer()
			if result and result.ok then
				HUD.Banner(string.format("Rebirth %d! +%d%% dig speed", result.rebirths, math.floor(result.digBonus * 100 + 0.5)))
				if result.unlock then
					HUD.Toast(result.unlock .. " unlocked!")
				end
			end
		end)
	end)
	-- a small picker: which rarity of geode to add
	local picker = Style.Panel(gui, "GeodePicker", UDim2.fromOffset(456, 64), UDim2.new(0, 224, 1, -160), Vector2.new(0, 1))
	picker.Visible = false
	picker.ZIndex = 8
	Style.Padding(picker, 8)
	local pl = Instance.new("UIListLayout")
	pl.FillDirection = Enum.FillDirection.Horizontal
	pl.Padding = UDim.new(0, 6)
	pl.SortOrder = Enum.SortOrder.LayoutOrder
	pl.Parent = picker
	for i, r in ipairs(Economy.GeodeRarities) do
		local b = Style.Button(picker, r.name, Critters.RarityColors[r.name] or C.Muted, UDim2.fromOffset(105, 46), function()
			local result = Remotes.DebugGiveGeode:InvokeServer(r.name)
			if result and result.message then
				HUD.Toast(result.message)
			end
		end)
		b.TextSize = 16
		b.LayoutOrder = i
	end
	devButton("Give geode (Studio)", 4, function()
		picker.Visible = not picker.Visible
	end)
	devButton("Reset save (Studio)", 3, function()
		HUD.Confirm("Reset your save?", "Testing only: wipes everything back to a brand-new player (rebirth 0, no critters, gems or coins).", "Reset", C.Red, function()
			local result = Remotes.DebugResetSave:InvokeServer()
			if result and result.ok then
				HUD.Banner("Fresh save!")
			end
		end)
	end)
end

----------------------------------------------------------------------
-- Crew list
----------------------------------------------------------------------

local crewSignature = ""
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
local MAX_STARS = Economy.Merge.MaxStars

-- "★★☆☆☆" with the earned stars in gold (rich text)
local function starText(stars: number): string
	return string.format(
		'<font color="#E0A100">%s</font><font color="#C9BBA8">%s</font>',
		string.rep("★", stars),
		string.rep("☆", MAX_STARS - stars)
	)
end

local function critterLabel(c): string
	local sp = Critters.Species[c.species]
	local stars = c.stars or 0
	return (stars > 0 and (stars .. "★ ") or "") .. sp.name
end

-- Another critter this one can merge with (same species and stars). Prefers a spare
-- on the bench that isn't locked, since that's the one that gets used up.
local function mergePartner(c)
	local best, bestScore = nil, -1
	for _, other in ipairs(state.critters) do
		if other.id ~= c.id and other.species == c.species and (other.stars or 0) == (c.stars or 0) then
			if not (c.locked and other.locked) then
				local score = 0
				if not other.locked then
					score += 2
				end
				if not table.find(state.crew, other.id) then
					score += 1
				end
				if score > bestScore then
					best, bestScore = other, score
				end
			end
		end
	end
	return best
end

local function smallButton(parent, text, color, width, onClick)
	local b = Style.Button(parent, text, color, UDim2.fromOffset(width, 38), onClick)
	b.TextSize = 15
	return b
end

local function refreshCrew()
	if not state then
		return
	end
	crewButton.Text = string.format("Crew %d/%d", #state.crew, state.crewSlots)
	crewPanel.Title.Text = string.format("Your crew  (%d/%d working)", #state.crew, state.crewSlots)

	-- only rebuild the list when something changed
	local parts = { table.concat(state.crew, ","), tostring(state.stratum) }
	for _, c in ipairs(state.critters) do
		table.insert(parts, c.id .. ":" .. (c.stars or 0) .. (c.locked and "L" or ""))
	end
	local sig = table.concat(parts, "|")
	if sig == crewSignature then
		return
	end
	crewSignature = sig

	for _, child in ipairs(crewList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- crew first, then rarer and higher-star critters
	local sorted = table.clone(state.critters)
	table.sort(sorted, function(a, b)
		local wa, wb = table.find(state.crew, a.id) ~= nil, table.find(state.crew, b.id) ~= nil
		if wa ~= wb then
			return wa
		end
		local ra, rb = RARITY_RANK[Critters.Species[a.species].rarity], RARITY_RANK[Critters.Species[b.species].rarity]
		if ra ~= rb then
			return ra > rb
		end
		if (a.stars or 0) ~= (b.stars or 0) then
			return (a.stars or 0) > (b.stars or 0)
		end
		return a.species < b.species
	end)

	for order, critter in ipairs(sorted) do
		local sp = Critters.Species[critter.species]
		if sp then
			local stars = critter.stars or 0
			local working = table.find(state.crew, critter.id) ~= nil
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -10, 0, 72)
			row.BackgroundColor3 = working and Color3.fromHex("F3E6C8") or C.Panel
			row.LayoutOrder = order
			Style.Corner(row, 10)
			Style.Stroke(row, 2, Critters.RarityColors[sp.rarity])
			row.Parent = crewList

			local name = Style.Label(row, sp.name .. "  " .. starText(stars), 19, {
				heading = true,
				RichText = true,
				Position = UDim2.fromOffset(12, 6),
				Size = UDim2.new(1, -360, 0, 24),
			})
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local st = Formulas.CritterStats(critter.species, stars)
			local stats = string.format("%s  ·  Dig %.1f", sp.rarity, st.dig)
			if st.luck > 0 then
				stats ..= string.format("  ·  Luck +%d%%", math.floor(st.luck * 100 + 0.5))
			end
			if st.heat > 0 then
				stats ..= string.format("  ·  Heat %.1f", st.heat)
			end
			Style.Label(row, stats, 14, {
				Position = UDim2.fromOffset(12, 32),
				Size = UDim2.new(1, -360, 0, 18),
				TextColor3 = C.Muted,
			})
			local where = working and "On your crew" or "On the bench"
			local speed = heatSpeed(critter, state.stratum)
			if speed < 0.995 then
				where ..= string.format('  ·  <font color="#D63B3B">too hot here: %d%% speed</font>', math.floor(speed * 100 + 0.5))
			end
			Style.Label(row, where, 13, {
				RichText = true,
				Position = UDim2.fromOffset(12, 50),
				Size = UDim2.new(1, -360, 0, 16),
				TextColor3 = working and Color3.fromHex("2E9E44") or C.Muted,
			})

			-- buttons, right to left
			local buttons = Instance.new("Frame")
			buttons.BackgroundTransparency = 1
			buttons.AnchorPoint = Vector2.new(1, 0.5)
			buttons.Position = UDim2.new(1, -8, 0.5, 0)
			buttons.Size = UDim2.fromOffset(350, 40)
			buttons.Parent = row
			local bl = Instance.new("UIListLayout")
			bl.FillDirection = Enum.FillDirection.Horizontal
			bl.HorizontalAlignment = Enum.HorizontalAlignment.Right
			bl.VerticalAlignment = Enum.VerticalAlignment.Center
			bl.SortOrder = Enum.SortOrder.LayoutOrder
			bl.Padding = UDim.new(0, 6)
			bl.Parent = buttons

			local lock = smallButton(buttons, critter.locked and "Locked" or "Lock", critter.locked and C.Gold or C.Disabled, 70, function()
				Remotes.ToggleLock:InvokeServer(critter.id)
			end)
			lock.LayoutOrder = 1

			local partner = stars < MAX_STARS and mergePartner(critter) or nil
			if partner then
				local merge = smallButton(buttons, "Merge", Color3.fromHex("9B5DE5"), 74, function()
					local next = Formulas.CritterStats(critter.species, stars + 1)
					HUD.Confirm(
						"Merge into " .. (stars + 1) .. "★ " .. sp.name .. "?",
						string.format(
							"Two %s become one %d★ %s with Dig %.1f (now %.1f). One of them is used up.",
							critterLabel(critter),
							stars + 1,
							sp.name,
							next.dig,
							st.dig
						),
						"Merge",
						Color3.fromHex("9B5DE5"),
						function()
							local result = Remotes.MergeCritters:InvokeServer(critter.id, partner.id)
							if result and result.message then
								if result.ok then
									HUD.Banner(result.message)
								else
									HUD.Toast(result.message)
								end
							end
						end
					)
				end)
				merge.LayoutOrder = 2
			end

			if not working and not critter.locked then
				local value = Formulas.CritterSellValue(critter.species, stars)
				local sell = smallButton(buttons, "Sell " .. Formulas.FormatNumber(value), C.Red, 96, function()
					HUD.Confirm(
						"Sell your " .. critterLabel(critter) .. "?",
						"You'll get " .. Formulas.FormatNumber(value) .. " coins. This can't be undone.",
						"Sell",
						C.Red,
						function()
							local result = Remotes.SellCritter:InvokeServer(critter.id)
							if result and result.message then
								HUD.Toast(result.message)
							end
						end
					)
				end)
				sell.LayoutOrder = 3
			end

			local assign = smallButton(buttons, working and "Rest" or "Assign", working and C.Orange or C.Green, 76, function()
				local result = Remotes.SetCrew:InvokeServer(critter.id, not working)
				if result and result.message then
					HUD.Toast(result.message)
				end
			end)
			assign.LayoutOrder = 4
		end
	end
end

-- A yes/no card on top of everything
local confirmCard = nil
function HUD.Confirm(title: string, body: string, confirmText: string, confirmColor: Color3, onConfirm: () -> ())
	if confirmCard then
		confirmCard:Destroy()
	end
	local card = Style.Panel(overlay, "Confirm", UDim2.fromOffset(420, 190), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	card.ZIndex = 30
	Style.Padding(card, 16)
	confirmCard = card
	Style.Label(card, title, 24, { heading = true, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Size = UDim2.new(1, 0, 0, 30) })
	Style.Label(card, body, 16, {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 60),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local function closeCard()
		card:Destroy()
		if confirmCard == card then
			confirmCard = nil
		end
	end
	local cancel = Style.Button(card, "Cancel", C.Disabled, UDim2.fromOffset(160, 46), closeCard)
	cancel.Position = UDim2.new(0.5, -8, 1, 0)
	cancel.AnchorPoint = Vector2.new(1, 1)
	local ok = Style.Button(card, confirmText, confirmColor, UDim2.fromOffset(160, 46), function()
		closeCard()
		onConfirm()
	end)
	ok.Position = UDim2.new(0.5, 8, 1, 0)
	ok.AnchorPoint = Vector2.new(0, 1)
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
		slot.frame.Visible = i <= (state.rackSlots or Economy.RackSlots)
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

	overlay = Instance.new("ScreenGui")
	overlay.Name = "HUDOverlay"
	overlay.ResetOnSpawn = false
	overlay.DisplayOrder = 20 -- over the Gem Book, Hatchery and Rebirth panels
	overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	overlay.Parent = gui.Parent
	Style.AutoScale(overlay)

	buildCoins()
	buildRebirthBadge()
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
	local rebirths = state.rebirths or 0
	rebirthBadge.Visible = rebirths > 0
	if rebirths > 0 then
		rebirthLabel.Text = string.format("Rebirth %d  ·  +%d%% dig", rebirths, math.floor(Formulas.RebirthDig(rebirths) * 100 + 0.5))
	end
	depthLabel.Text = string.format("%.1f m", state.depth)

	local stratum = Strata[state.stratum]
	stratumLabel.Text = stratum.name
	stratumLabel.TextColor3 = stratum.rockColor:Lerp(C.Text, 0.35)
	local bit = Economy.Bits[state.bitLevel]
	-- the bit line is only about the bit: heat and hardness are shown separately
	if state.fullSpeedTo == math.huge then
		bitLabel.Text = bit.name .. "  ·  strong everywhere"
	else
		bitLabel.Text = string.format("%s  ·  strong to %s m", bit.name, Formulas.FormatNumber(state.fullSpeedTo))
	end

	local heatPct = crewHeatSpeed()
	local hot = stratum.heat > 0 and heatPct < 0.995
	heatLabel.Visible = hot
	if hot then
		heatLabel.Text = string.format("Too hot: crew at %d%% (needs Heat %d)", math.floor(heatPct * 100 + 0.5), stratum.heat)
	end
	depthPanel.Size = UDim2.fromOffset(250, hot and 154 or 132)

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
	local l = Style.Label(overlay, text, 54, {
		heading = true,
		outlined = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.28),
		Size = UDim2.fromOffset(900, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		ZIndex = 40, -- above open panels
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
	local gem = OreConfig.Gems[result.gemId]
	local stratum = Strata[result.stratum or 1]

	-- extra finds, one line each
	local extras = {}
	if result.critter then
		local sp = Critters.Species[result.critter]
		table.insert(extras, {
			text = (sp.name:match("^[AEIOUaeiou]") and "An " or "A ") .. sp.name .. " was sleeping inside!" .. (result.joinedCrew and " It joined your crew." or " It's on your bench."),
			color = Critters.RarityColors[sp.rarity]:Lerp(C.Outline, 0.25),
		})
	end
	if result.shard then
		table.insert(extras, { text = "A Core Shard! Your crew digs 10% faster for good.", color = Color3.fromHex("9B5DE5") })
	end
	if result.completedTier then
		table.insert(extras, {
			text = string.format("All %s gems found! +%d Core Shard", result.completedTier, result.setShards or 1),
			color = Color3.fromHex("C98A00"),
		})
	end
	if result.completedBook then
		table.insert(extras, {
			text = string.format("Gem Book complete! All 50 found: +%d Core Shards", result.bookShards or 3),
			color = Color3.fromHex("C98A00"),
		})
	end
	if result.pouch then
		table.insert(extras, {
			text = string.format("A pouch of %d %s: +%s coins", result.pouch.amount, result.pouch.name, Formulas.FormatNumber(result.pouch.coins)),
			color = Color3.fromHex("2E9E44"),
		})
	end

	local LINE = 26
	local height = 222 + #extras * LINE
	revealCard = Style.Panel(gui, "Reveal", UDim2.fromOffset(440, height), UDim2.fromScale(0.5, 0.45), Vector2.new(0.5, 0.5))
	revealCard.ZIndex = 10
	Style.Padding(revealCard, 16)
	local s = revealCard:FindFirstChildOfClass("UIStroke")
	s.Color = color
	s.Thickness = 5

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = revealCard
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	Style.Label(revealCard, result.rarity .. " geode  ·  " .. stratum.name, 18, {
		heading = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
	})
	Style.Label(revealCard, result.gemName .. "!", 40, {
		heading = true,
		outlined = true,
		Position = UDim2.fromOffset(0, 28),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = gem and gem.color:Lerp(color, 0.3) or color,
	})
	local chance = (result.chance or 0) * 100
	local infoText = string.format(chance < 10 and "%.1f%% of %s gems" or "%d%% of %s gems", chance < 10 and chance or math.floor(chance + 0.5), result.rarity)
	if result.flawless then
		infoText = '<font color="#C98A00">★ Flawless (x' .. Economy.FlawlessMult .. ')</font>  ·  ' .. infoText
	end
	if result.isNew then
		infoText ..= '  ·  <font color="#2E9E44">NEW in your Gem Book!</font>'
	elseif result.newFlawless then
		infoText ..= '  ·  <font color="#2E9E44">First Flawless one!</font>'
	end
	Style.Label(revealCard, infoText, 16, {
		heading = true,
		RichText = true,
		Position = UDim2.fromOffset(0, 80),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
	})
	Style.Label(revealCard, "Worth " .. Formulas.FormatNumber(result.gemValue) .. " coins at the Assay Office", 17, {
		Position = UDim2.fromOffset(0, 106),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	for i, line in ipairs(extras) do
		Style.Label(revealCard, line.text, 16, {
			heading = true,
			Position = UDim2.fromOffset(0, 134 + (i - 1) * LINE),
			Size = UDim2.new(1, 0, 0, LINE - 2),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = line.color,
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
