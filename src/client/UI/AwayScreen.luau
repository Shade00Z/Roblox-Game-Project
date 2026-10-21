--!nonstrict
-- "While you were away" card shown when a player returns.
-- This is the payoff moment of the whole loop, so the numbers count up.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Formulas = require(Shared.Formulas)

local Style = require(script.Parent.Style)
local C = Style.Colors

local AwayScreen = {}

local gui: ScreenGui

function AwayScreen.Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "AwayScreen"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.IgnoreGuiInset = true
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	Style.AutoScale(gui)
end

local function statRow(parent: Instance, order: number, name: string)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 36)
	row.LayoutOrder = order
	row.Parent = parent
	Style.Label(row, name, 20, { Size = UDim2.new(0.55, 0, 1, 0), TextColor3 = C.Muted })
	return Style.Label(row, "0", 26, {
		heading = true,
		Position = UDim2.fromScale(0.55, 0),
		Size = UDim2.new(0.45, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
end

function AwayScreen.Show(summary)
	gui:ClearAllChildren()
	Style.AutoScale(gui)

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Parent = gui
	TweenService:Create(dim, TweenInfo.new(0.3), { BackgroundTransparency = 0.45 }):Play()

	local card = Style.Panel(gui, "Card", UDim2.fromOffset(480, 0), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	card.AutomaticSize = Enum.AutomaticSize.Y
	Style.Padding(card, 18)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = card
	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = card

	Style.Label(card, "While you were away", 32, { heading = true, LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Center })
	Style.Label(card, "Gone for " .. Formulas.FormatDuration(summary.seconds), 18, {
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.Muted,
	})

	local spacer = Instance.new("Frame")
	spacer.BackgroundTransparency = 1
	spacer.Size = UDim2.new(1, 0, 0, 8)
	spacer.LayoutOrder = 3
	spacer.Parent = card

	local dug = statRow(card, 4, "Your crew dug")
	local ore = statRow(card, 5, "Ore collected")
	local worth = statRow(card, 6, "Worth")
	local geodes = statRow(card, 7, "Geodes found")
	Style.CountUp(dug, 0, summary.meters, 1.2, function(n)
		return string.format("%.1f m", n)
	end)
	Style.CountUp(ore, 0, summary.ore, 1.2, function(n)
		return Formulas.FormatNumber(n)
	end)
	Style.CountUp(worth, 0, summary.oreValue, 1.2, function(n)
		return Formulas.FormatNumber(n) .. " coins"
	end)
	geodes.Text = tostring(summary.geodes)

	local notes = {}
	for _, name in ipairs(summary.newStrata) do
		table.insert(notes, "New stratum reached: " .. name .. "!")
	end
	if summary.cartFull then
		table.insert(notes, "Your cart filled up. A bigger cart at the Drill Shop keeps your crew mining longer.")
	end
	if summary.toughRock then
		table.insert(notes, "Your crew hit rock too tough for your drill bit, so they slowed down. The next bit at the Drill Shop gets them back to full speed.")
	end
	for i, text in ipairs(notes) do
		Style.Label(card, text, 16, {
			LayoutOrder = 10 + i,
			Size = UDim2.new(1, 0, 0, 40),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.Orange,
		})
	end

	-- the button sits centered in its own row at the bottom
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 64)
	holder.LayoutOrder = 100
	holder.Parent = card
	local collect = Style.Button(holder, "Collect", C.Green, UDim2.fromOffset(200, 52), function()
		gui:ClearAllChildren()
	end)
	collect.TextSize = 24
	collect.AnchorPoint = Vector2.new(0.5, 0.5)
	collect.Position = UDim2.fromScale(0.5, 0.5)
end

return AwayScreen
