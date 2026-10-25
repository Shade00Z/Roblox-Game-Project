--!nonstrict
-- The Gem Book: all 50 gems, one tab per tier (Common, Rare, Epic, Legendary).
-- Every gem can be found in any layer. A geode's rarity decides the tier, and each
-- card shows that gem's chance inside a geode of its tier (the same at every depth).
-- Gems you haven't found show as "???"; a gold star marks a Flawless find.
-- Finishing a tier, and finishing the whole book, earn Core Shards (on the server).
--
-- The gem stand (top of the book): tap a gem you've found to put it on your stand,
-- tap a gem on the stand to take it off. Each gem gives one boost; the stand also
-- floats over your plot for everyone to see.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Strata = require(Shared.Config.Strata)
local Economy = require(Shared.Config.Economy)
local OreConfig = require(Shared.Config.Ores)
local Critters = require(Shared.Config.Critters)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local Style = require(script.Parent.Style)
local HUD = require(script.Parent.HUD)
local C = Style.Colors

local GemBook = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local panel: Frame
local openButton: TextButton
local countLabel: TextLabel
local tabs = {}
local rowsFrame: Frame
local footer: TextLabel
local state = nil
local page = nil -- tier being shown ("Common", "Rare", ...)
local header: TextLabel
local standSlots = {}
local standTotal: TextLabel
local signature = ""

local SHARD_PURPLE = Color3.fromHex("7B3FC4")
local STAR_GOLD = Color3.fromHex("C98A00")

-- percent text that keeps small odds readable (1.9% rather than 2%)
local function pct(x: number): string
	local p = math.floor(x * 1000 + 0.5) / 10 -- one decimal place, without float noise
	if p >= 10 or p == math.floor(p) then
		return string.format("%d%%", math.floor(p + 0.5))
	end
	return string.format("%.1f%%", p)
end

-- share of geodes that come out at each rarity (before crew Luck)
local function geodeShare(rarity: string): number
	local total, mine = 0, 0
	for _, r in ipairs(Economy.GeodeRarities) do
		total += r.weight
		if r.name == rarity then
			mine = r.weight
		end
	end
	return total > 0 and mine / total or 0
end

local function currentLayer(): number
	return math.clamp(state and state.stratum or 1, 1, OreConfig.LayerCount)
end

local function found(id: string): number
	return state and state.gemBook and state.gemBook[id] or 0
end

local function flawless(id: string): boolean
	return state ~= nil and state.gemFlawless ~= nil and state.gemFlawless[id] == true
end

local function equipped(): { string }
	return state and state.equippedGems or {}
end

local function slotCount(): number
	return state and state.gemSlots or Economy.GemSlots
end

local function boostText(id: string, short: boolean?): string
	local kind, amount = Formulas.GemBoost(id, flawless(id))
	return kind and Formulas.FormatBoost(kind, amount, short) or ""
end

local function setSlot(slot: number, id: string?)
	task.spawn(function()
		local result = Remotes.SetGemSlot:InvokeServer(slot, id)
		if result and result.message then
			HUD.Toast(result.message)
		end
	end)
end

-- tapping a card in the book
local function onCardTapped(id: string)
	if found(id) == 0 then
		HUD.Toast("You haven't found that gem yet. Keep cracking geodes!")
		return
	end
	local list = equipped()
	local at = table.find(list, id)
	if at then
		setSlot(at, nil)
	elseif #list < slotCount() then
		setSlot(#list + 1, id)
	else
		HUD.Toast("Your gem stand is full. Tap a gem on the stand to take it off first.")
	end
end

local function countFound(ids: { string }): number
	local n = 0
	for _, id in ipairs(ids) do
		if found(id) > 0 then
			n += 1
		end
	end
	return n
end

-- a gem icon: a rounded square turned 45 degrees
local function gemIcon(parent: Instance, color: Color3?, known: boolean): Frame
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(42, 42)
	holder.Parent = parent
	local d = Instance.new("Frame")
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.fromScale(0.5, 0.5)
	d.Size = UDim2.fromOffset(28, 28)
	d.Rotation = 45
	d.BackgroundColor3 = known and color or C.Disabled
	d.BorderSizePixel = 0
	Style.Corner(d, 6)
	Style.Stroke(d, 2, C.Outline)
	d.Parent = holder
	if known then
		local shine = Instance.new("Frame")
		shine.Size = UDim2.fromOffset(8, 8)
		shine.Position = UDim2.fromOffset(4, 4)
		shine.BackgroundColor3 = Color3.new(1, 1, 1)
		shine.BackgroundTransparency = 0.35
		shine.BorderSizePixel = 0
		Style.Corner(shine, 3)
		shine.Parent = d
	else
		Style.Label(holder, "?", 20, {
			heading = true,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.TextLight,
			ZIndex = 2,
		})
	end
	return holder
end

local function gemCard(parent: Instance, id: string, order: number)
	local chance = OreConfig.GemChance(id)
	local gem = OreConfig.Gems[id]
	local n = found(id)
	local known = n > 0
	local onStand = table.find(equipped(), id) ~= nil
	local card = Instance.new("TextButton")
	card.Text = ""
	card.AutoButtonColor = false
	card.LayoutOrder = order
	card.BackgroundColor3 = onStand and Color3.fromHex("E3F7E3") or (known and Color3.fromHex("FFFDF7") or Color3.fromHex("EFE3CC"))
	Style.Corner(card, 10)
	Style.Stroke(card, onStand and 3 or 2, onStand and Color3.fromHex("2E9E44") or (known and gem.color:Lerp(C.Outline, 0.35) or C.Disabled))
	card.Activated:Connect(function()
		onCardTapped(id)
	end)
	card.Parent = parent

	local icon = gemIcon(card, gem.color, known)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 2, 0.5, 0)

	local name = Style.Label(card, known and gem.name or "???", 15, {
		heading = true,
		Position = UDim2.fromOffset(46, 8),
		Size = UDim2.new(1, -50, 0, 20),
		TextColor3 = known and C.Text or C.Muted,
	})
	name.TextTruncate = Enum.TextTruncate.AtEnd
	-- line 2: what it does on the stand; line 3: odds and whether you have it
	local boostLine = Style.Label(card, boostText(id), 13, {
		heading = true,
		Position = UDim2.fromOffset(46, 30),
		Size = UDim2.new(1, -50, 0, 18),
		TextColor3 = (Critters.RarityColors[gem.rarity] or C.Muted):Lerp(C.Outline, 0.45),
	})
	boostLine.TextTruncate = Enum.TextTruncate.AtEnd
	local status = pct(chance) .. "  ·  " .. (known and ("found " .. n) or "not found")
	if flawless(id) then
		status ..= '  <font color="#C98A00">★</font>'
	end
	if onStand then
		status = pct(chance) .. '  ·  <font color="#2E9E44">on stand</font>' .. (flawless(id) and '  <font color="#C98A00">★</font>' or "")
	end
	Style.Label(card, status, 13, {
		RichText = true,
		Position = UDim2.fromOffset(46, 50),
		Size = UDim2.new(1, -50, 0, 16),
		TextColor3 = C.Muted,
	})
end

local function refreshStand()
	local list = equipped()
	-- share the row between however many slots you have unlocked
	local count = slotCount()
	local width = math.floor((552 - (count - 1) * 6) / count)
	for slot, ui in ipairs(standSlots) do
		local id = list[slot]
		ui.frame.Visible = slot <= count
		ui.frame.Position = UDim2.fromOffset(124 + (slot - 1) * (width + 6), 6)
		ui.frame.Size = UDim2.fromOffset(width, 50)
		if ui.icon then
			ui.icon:Destroy()
			ui.icon = nil
		end
		if id then
			local gem = OreConfig.Gems[id]
			ui.icon = gemIcon(ui.frame, gem.color, true)
			ui.icon.AnchorPoint = Vector2.new(0, 0.5)
			ui.icon.Position = UDim2.new(0, 4, 0.5, 0)
			ui.name.Text = gem.name .. (flawless(id) and "  ★" or "")
			ui.name.TextColor3 = C.Text
			ui.boost.Text = boostText(id)
		else
			ui.name.Text = "Empty slot"
			ui.name.TextColor3 = C.Muted
			ui.boost.Text = "Tap a gem below"
		end
	end
	local boosts = Formulas.GemBoosts(list, state and state.gemFlawless)
	local lines = {}
	for _, kind in ipairs({ "dig", "heat", "luck", "ore", "geode" }) do
		if boosts[kind] > 0 then
			table.insert(lines, Formulas.FormatBoost(kind, boosts[kind]))
		end
	end
	standTotal.Text = #lines > 0 and table.concat(lines, "\n") or "No boosts yet"
end

local function buildPage()
	for _, child in ipairs(rowsFrame:GetChildren()) do
		if child:IsA("GuiButton") or child:IsA("Frame") then
			child:Destroy()
		end
	end
	refreshStand()
	local here = currentLayer()
	header.Text = string.format(
		"%s geodes are %s of finds and hold one of these. Each is worth ~%s at your depth (%s). 1 in 20 is Flawless, worth x%d.",
		page,
		pct(geodeShare(page)),
		Formulas.FormatNumber(OreConfig.GemValue(page, here, false, state and state.rebirths)),
		Strata[here].name,
		Economy.FlawlessMult
	)
	header.TextColor3 = (Critters.RarityColors[page] or C.Muted):Lerp(C.Outline, 0.5)

	local ids = OreConfig.TierGems(page)
	for i, id in ipairs(ids) do
		gemCard(rowsFrame, id, i)
	end

	local sets = state and state.gemSets or {}
	if sets[page] then
		footer.Text = string.format("All %s gems found! You earned %d Core Shard%s.", page, Economy.GemSetShards, Economy.GemSetShards == 1 and "" or "s")
		footer.TextColor3 = Color3.fromHex("2E9E44")
	else
		footer.Text = string.format(
			"%d / %d %s gems: find them all for a Core Shard (+10%% dig speed for good). Find all 50 for %d more.",
			countFound(ids),
			#ids,
			page,
			Economy.GemBookCompleteShards
		)
		footer.TextColor3 = SHARD_PURPLE
	end
end

local function refreshTabs()
	for tier, tab in pairs(tabs) do
		local ids = OreConfig.TierGems(tier)
		local done = state and state.gemSets and state.gemSets[tier]
		tab.Text = string.format("%s  %d/%d", tier, countFound(ids), #ids) .. (done and "  ✓" or "")
		tab.BackgroundColor3 = tier == page and C.Gold or Color3.fromHex("E8D9C0")
	end
	local all = OreConfig.GemOrder
	countLabel.Text = string.format("%d of %d gems discovered  ·  every gem can be found in any layer", countFound(all), #all)
end

local function refresh(force: boolean?)
	if not (panel and panel.Visible and page) then
		return
	end
	-- rebuild when finds, Flawless marks, rewards or your layer change
	local parts = { "p" .. tostring(page), "l" .. currentLayer() }
	if state then
		for id, n in pairs(state.gemBook or {}) do
			table.insert(parts, id .. n)
		end
		for id in pairs(state.gemFlawless or {}) do
			table.insert(parts, "f" .. id)
		end
		for k in pairs(state.gemSets or {}) do
			table.insert(parts, "s" .. k)
		end
		for i, id in ipairs(state.equippedGems or {}) do
			table.insert(parts, "e" .. i .. id)
		end
	end
	table.sort(parts)
	local sig = table.concat(parts, ",")
	if sig == signature and not force then
		return
	end
	signature = sig
	refreshTabs()
	buildPage()
end

local function showPage(tier: string)
	page = tier
	refresh(true)
end

function GemBook.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "GemBook"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	Style.AutoScale(gui)

	-- left edge, above the Crew button
	openButton = Style.Button(gui, "Gem Book", Color3.fromHex("9B5DE5"), UDim2.fromOffset(150, 52), function()
		if panel.Visible then
			GemBook.Close()
		else
			GemBook.Open()
		end
	end)
	openButton.Position = UDim2.new(0, 16, 0.5, -64)
	openButton.AnchorPoint = Vector2.new(0, 0.5)

	panel = Style.Panel(gui, "Book", UDim2.fromOffset(820, 618), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.Visible = false
	panel.ZIndex = 5
	Style.Padding(panel, 14)
	Style.Label(panel, "Gem Book", 30, { heading = true, Size = UDim2.new(1, -60, 0, 34) })
	countLabel = Style.Label(panel, "", 14, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, -60, 0, 18), TextColor3 = C.Muted })
	local close = Style.Button(panel, "X", C.Red, UDim2.fromOffset(40, 40), GemBook.Close)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.AnchorPoint = Vector2.new(1, 0)

	-- one tab per tier
	local tabRow = Instance.new("Frame")
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromOffset(0, 62)
	tabRow.Size = UDim2.new(1, 0, 0, 38)
	tabRow.Parent = panel
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Padding = UDim.new(0, 6)
	tl.Parent = tabRow
	for i, tier in ipairs(OreConfig.GemRarities) do
		local tab = Style.Button(tabRow, tier, Color3.fromHex("E8D9C0"), UDim2.new(0.25, -5, 1, 0), function()
			showPage(tier)
		end)
		tab.TextSize = 15
		tab.LayoutOrder = i
		tab.TextColor3 = C.Text
		tab.TextStrokeTransparency = 1
		tabs[tier] = tab
	end

	-- the gem stand: three slots and what they add up to
	local stand = Instance.new("Frame")
	stand.BackgroundColor3 = Color3.fromHex("F3E6C8")
	stand.Position = UDim2.fromOffset(0, 108)
	stand.Size = UDim2.new(1, 0, 0, 62)
	Style.Corner(stand, 10)
	stand.Parent = panel
	Style.Label(stand, "Gem stand", 17, {
		heading = true,
		Position = UDim2.fromOffset(10, 6),
		Size = UDim2.fromOffset(110, 22),
	})
	Style.Label(stand, "Tap gems to add or remove", 11, {
		Position = UDim2.fromOffset(10, 30),
		Size = UDim2.fromOffset(112, 28),
		TextWrapped = true,
		TextColor3 = C.Muted,
	})
	local _, _, maxStand = Formulas.MaxSlots()
	for slot = 1, maxStand do
		local f = Instance.new("TextButton")
		f.Text = ""
		f.AutoButtonColor = false
		f.BackgroundColor3 = Color3.fromHex("FFFDF7")
		f.Position = UDim2.fromOffset(124 + (slot - 1) * 186, 6)
		f.Size = UDim2.fromOffset(180, 50)
		Style.Corner(f, 8)
		Style.Stroke(f, 2, C.Disabled)
		f.Activated:Connect(function()
			if equipped()[slot] then
				setSlot(slot, nil)
			end
		end)
		f.Parent = stand
		local name = Style.Label(f, "", 15, { heading = true, Position = UDim2.fromOffset(48, 5), Size = UDim2.new(1, -52, 0, 20) })
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local boost = Style.Label(f, "", 12, { Position = UDim2.fromOffset(48, 26), Size = UDim2.new(1, -52, 0, 18), TextColor3 = C.Muted })
		boost.TextTruncate = Enum.TextTruncate.AtEnd
		standSlots[slot] = { frame = f, name = name, boost = boost }
	end
	standTotal = Style.Label(stand, "", 13, {
		heading = true,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 4),
		Size = UDim2.fromOffset(100, 54),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextColor3 = Color3.fromHex("2E9E44"),
		TextScaled = true,
	})
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 14
	limit.Parent = standTotal

	header = Style.Label(panel, "", 14, {
		heading = true,
		Position = UDim2.fromOffset(0, 176),
		Size = UDim2.new(1, 0, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- up to 20 cards, five to a row
	rowsFrame = Instance.new("Frame")
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.Position = UDim2.fromOffset(0, 200)
	rowsFrame.Size = UDim2.new(1, 0, 0, 82 * 4 + 8 * 3)
	rowsFrame.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.2, -7, 0, 82)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = rowsFrame

	footer = Style.Label(panel, "", 15, {
		heading = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 40),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
end

function GemBook.Update(newState)
	state = newState
	refresh(false)
end

function GemBook.Open()
	page = page or "Common"
	panel.Visible = true
	refresh(true)
end

function GemBook.Close()
	panel.Visible = false
end

return GemBook
