--!nonstrict
-- The Rebirth panel: how close you are, what you gain, what resets and what you
-- keep, and the button (with a confirm card). The server does the actual reset
-- (RebirthService); this only shows the numbers and asks.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local Style = require(script.Parent.Style)
local HUD = require(script.Parent.HUD)
local C = Style.Colors

local Rebirth = {}

local REBIRTH_PINK = Color3.fromHex("E0479E")

local player = Players.LocalPlayer
local gui: ScreenGui
local panel: Frame
local openButton: TextButton
local title: TextLabel
local progressFill: Frame
local progressLabel: TextLabel
local gainLabel: TextLabel
local priceLabel: TextLabel
local goButton: TextButton
local state = nil

local function eligible(): boolean
	return state ~= nil and state.depth >= (state.rebirthDepth or math.huge)
end

local function refresh()
	if not state then
		return
	end
	local r = state.rebirths or 0
	local need = state.rebirthDepth or Formulas.RebirthDepth(r)
	local ready = eligible()

	openButton.Text = ready and "Rebirth!" or "Rebirth"
	openButton.BackgroundColor3 = ready and REBIRTH_PINK or Color3.fromHex("B58AA6")
	if not panel.Visible then
		return
	end

	title.Text = r == 0 and "Rebirth" or string.format("Rebirth %d", r + 1)
	local frac = math.clamp(state.depth / need, 0, 1)
	progressFill.Size = UDim2.fromScale(frac, 1)
	progressFill.BackgroundColor3 = ready and Color3.fromHex("2E9E44") or REBIRTH_PINK
	progressLabel.Text = ready and string.format("Ready! You're past %s m.", Formulas.FormatNumber(need))
		or string.format("Reach %s m to rebirth  ·  you're at %s m", Formulas.FormatNumber(need), Formulas.FormatNumber(math.floor(state.depth)))

	-- what the next rebirth gives
	local nowBonus = Formulas.RebirthDig(r)
	local nextBonus = Formulas.RebirthDig(r + 1)
	local gain = r == 0 and string.format("+%d%% crew dig speed, for good", math.floor(nextBonus * 100 + 0.5))
		or string.format("+%d%% more crew dig speed, for good (from +%d%% to +%d%%)", math.floor(Economy.Rebirth.DigPerRebirth * 100 + 0.5), math.floor(nowBonus * 100 + 0.5), math.floor(nextBonus * 100 + 0.5))
	local unlock = Economy.Rebirth.Unlocks[r + 1]
	gain ..= string.format("\nGems from geodes sell for x%.1f", Economy.Rebirth.GemValueGrowth)
	if unlock then
		gain ..= "\n" .. unlock.text .. ", unlocked for good"
	end
	gainLabel.Text = gain

	-- every upgrade and egg goes up: show what your next bit, pickaxe and cart will cost
	-- (after a rebirth you start again from the first one, so that's the one shown)
	local function priceText(name, base)
		return string.format("%s %s → %s", name, Formulas.FormatNumber(Formulas.Price(base, r)), Formulas.FormatNumber(Formulas.Price(base, r + 1)))
	end
	local bit, pick, cart = Economy.Bits[2], Economy.Pickaxes[2], Economy.Carts[2]
	priceLabel.Text = string.format(
		"Harder: every upgrade and egg costs x%.1f.  %s  ·  %s  ·  %s  ·  %s",
		Economy.Rebirth.PriceGrowth,
		priceText(bit.name, bit.cost),
		priceText(pick.name, pick.cost),
		priceText("Bigger cart", cart.cost),
		priceText(Economy.Bits[#Economy.Bits].name, Economy.Bits[#Economy.Bits].cost)
	)

	goButton.BackgroundColor3 = ready and REBIRTH_PINK or C.Disabled
end

local function section(parent, y, heading, color)
	Style.Label(parent, heading, 17, { heading = true, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 22), TextColor3 = color })
end

local function doRebirth()
	if not eligible() then
		HUD.Toast(string.format("Reach %s m to rebirth.", Formulas.FormatNumber(state and state.rebirthDepth or Economy.Rebirth.BaseDepth)))
		return
	end
	HUD.Confirm(
		"Rebirth now?",
		"Your depth, coins, cart, geode rack and gear reset to the start. Your critters, eggs, Gem Book, gem stand and Core Shards stay. This can't be undone.",
		"Rebirth",
		REBIRTH_PINK,
		function()
			local result = Remotes.Rebirth:InvokeServer()
			if result and result.ok then
				panel.Visible = false
				HUD.Banner(string.format("Rebirth %d! +%d%% dig speed", result.rebirths, math.floor(result.digBonus * 100 + 0.5)))
				if result.unlock then
					HUD.Toast(result.unlock .. " unlocked!")
				end
			elseif result and result.message then
				HUD.Toast(result.message)
			end
		end
	)
end

function Rebirth.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "Rebirth"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	Style.AutoScale(gui)

	-- left edge, above the Gem Book button
	openButton = Style.Button(gui, "Rebirth", Color3.fromHex("B58AA6"), UDim2.fromOffset(150, 52), function()
		panel.Visible = not panel.Visible
		refresh()
	end)
	openButton.Position = UDim2.new(0, 16, 0.5, -128)
	openButton.AnchorPoint = Vector2.new(0, 0.5)

	panel = Style.Panel(gui, "RebirthPanel", UDim2.fromOffset(560, 500), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.Visible = false
	panel.ZIndex = 5
	Style.Padding(panel, 16)
	title = Style.Label(panel, "Rebirth", 30, { heading = true, Size = UDim2.new(1, -60, 0, 34) })
	Style.Label(panel, "Start over from the surface, stronger for good.", 15, {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, -60, 0, 18),
		TextColor3 = C.Muted,
	})
	local close = Style.Button(panel, "X", C.Red, UDim2.fromOffset(40, 40), function()
		panel.Visible = false
	end)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.AnchorPoint = Vector2.new(1, 0)

	-- progress toward the depth you need
	local track = Instance.new("Frame")
	track.BackgroundColor3 = C.Track
	track.Position = UDim2.fromOffset(0, 66)
	track.Size = UDim2.new(1, 0, 0, 30)
	Style.Corner(track, 8)
	track.Parent = panel
	progressFill = Instance.new("Frame")
	progressFill.BackgroundColor3 = REBIRTH_PINK
	progressFill.Size = UDim2.fromScale(0, 1)
	Style.Corner(progressFill, 8)
	progressFill.Parent = track
	progressLabel = Style.Label(track, "", 15, {
		heading = true,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})

	section(panel, 110, "You gain", Color3.fromHex("2E9E44"))
	gainLabel = Style.Label(panel, "", 15, {
		Position = UDim2.fromOffset(0, 134),
		Size = UDim2.new(1, 0, 0, 58),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	priceLabel = Style.Label(panel, "", 14, {
		Position = UDim2.fromOffset(0, 194),
		Size = UDim2.new(1, 0, 0, 36),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.Muted,
	})

	section(panel, 240, "You keep", Color3.fromHex("2F7FD1"))
	Style.Label(panel, "Every critter and your crew, eggs, your Gem Book, gem stand and Core Shards", 15, {
		Position = UDim2.fromOffset(0, 264),
		Size = UDim2.new(1, 0, 0, 22),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	section(panel, 298, "Resets", C.Red:Lerp(C.Outline, 0.3))
	Style.Label(panel, "Depth back to 0 m in a brand-new mine, all your coins (spend them on eggs first: eggs stay!), geodes on your rack (crack them first), your drill bit, cart and pickaxe", 15, {
		Position = UDim2.fromOffset(0, 322),
		Size = UDim2.new(1, 0, 0, 58),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	goButton = Style.Button(panel, "Rebirth", C.Disabled, UDim2.fromOffset(220, 54), doRebirth)
	goButton.Position = UDim2.new(0.5, 0, 1, 0)
	goButton.AnchorPoint = Vector2.new(0.5, 1)
end

function Rebirth.Update(newState)
	state = newState
	refresh()
end

return Rebirth
