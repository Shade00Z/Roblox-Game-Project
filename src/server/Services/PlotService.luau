--!nonstrict
-- Hands each player a plot on the Ridge, builds one private shaft room per plot
-- from the Workspace.Map.ShaftRoom template, and runs the headframe elevator.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Strata = require(Shared.Config.Strata)
local Formulas = require(Shared.Formulas)
local Remotes = require(Shared.Remotes)

local PlayerData = require(script.Parent.PlayerData)

local PLOT_COUNT = 8
local ROOM_SPACING = 120 -- studs between shaft rooms; wide enough that the side-on camera never sees a neighbor

local PlotService = {}

local map = workspace:WaitForChild("Map")
local plotsFolder = map.Ridge.Plots
local shaftsFolder: Folder
local rooms: { [number]: Model } = {}
local owners: { [number]: Player? } = {}

local function setLabel(part: BasePart, text: string)
	local gui = part:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChildOfClass("TextLabel")
	if label then
		label.Text = text
	end
end

local function addPrompt(parent: Instance, action: string, objectText: string, actionText: string, distance: number?)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = action .. "Prompt"
	prompt.ObjectText = objectText
	prompt.ActionText = actionText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = distance or 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", action)
	prompt.Parent = parent
	return prompt
end

-- Copy the template room into a Model, shifted along X for this plot
local function buildRoom(template: Instance, index: number): Model
	local offset = Vector3.new((index - 1) * ROOM_SPACING - (PLOT_COUNT - 1) * ROOM_SPACING / 2, 0, 0)
	local room = Instance.new("Model")
	room.Name = "Shaft" .. index
	for _, child in ipairs(template:GetChildren()) do
		child:Clone().Parent = room
	end
	for _, d in ipairs(room:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame += offset
		end
	end
	-- the bottom three rows are the dig front, which each player's device now draws
	-- itself from their save data (see DigFront); keep only the ledges above it
	local origin0 = template:GetAttribute("Origin") or Vector3.new(0, 0, -800)
	for _, block in ipairs(room.Blocks:GetChildren()) do
		local row = math.round((block.Position.Y - origin0.Y - 2) / 4)
		if row <= 2 or row == 7 then
			-- the high ledge (row 7) goes too: the ladder replaces it, and it would
			-- otherwise catch your shoulders on the way up
			block:Destroy()
		end
	end

	-- a ladder from the top of the dig front up beside the elevator platform's inner
	-- edge (not under it, or you'd bump your head); step sideways off the top onto it
	local origin = origin0 + offset
	local ladder = Instance.new("TrussPart")
	ladder.Name = "Ladder"
	ladder.Anchored = true
	-- runs from the shaft floor (so you can reach it even from a hole) up to the platform top
	ladder.Size = Vector3.new(2, 40, 2)
	ladder.Position = origin + Vector3.new(-11, 21, 4)
	ladder.Color = Color3.fromHex("A0673A")
	ladder.Material = Enum.Material.Wood
	ladder.Parent = room.Shell
	room:SetAttribute("Origin", origin)
	room:SetAttribute("PlotIndex", index)
	room.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	room.Parent = shaftsFolder
	return room
end

function PlotService.GetRoom(index: number): Model?
	return rooms[index]
end

function PlotService.GetPlot(index: number): Model?
	return plotsFolder:FindFirstChild("Plot" .. index)
end

function PlotService.GetPlotIndex(player: Player): number?
	return player:GetAttribute("PlotIndex")
end

function PlotService.GetOwner(index: number): Player?
	return owners[index]
end

function PlotService.SendDown(player: Player)
	local index = player:GetAttribute("PlotIndex")
	local room = index and rooms[index]
	local character = player.Character
	if not (room and character and character.PrimaryPart) then
		return
	end
	local arrival = room.Shell.ElevatorArrival
	local target = arrival.Position + Vector3.new(0, 4, 0)
	pcall(function()
		player:RequestStreamAroundAsync(target, 5)
	end)
	character:PivotTo(CFrame.new(target))
	player:SetAttribute("InShaft", true)
end

function PlotService.SendUp(player: Player)
	local index = player:GetAttribute("PlotIndex")
	local plot = index and PlotService.GetPlot(index)
	local character = player.Character
	if not (plot and character) then
		return
	end
	local pad = plot.Headframe.ElevatorPad
	local target = pad.Position + Vector3.new(0, 4, 8)
	pcall(function()
		player:RequestStreamAroundAsync(target, 5)
	end)
	character:PivotTo(CFrame.new(target))
	player:SetAttribute("InShaft", false)
end

local function assignPlot(player: Player)
	for i = 1, PLOT_COUNT do
		if owners[i] == nil then
			owners[i] = player
			player:SetAttribute("PlotIndex", i)
			rooms[i]:AddPersistentPlayer(player)
			local plot = PlotService.GetPlot(i)
			plot.Headframe.ElevatorPad.Color = Color3.fromHex("FFC233")
			setLabel(plot.Headframe.Nameplate, player.DisplayName .. "  ·  0 m")
			return
		end
	end
	warn("[PlotService] No free plot for", player.Name)
end

local function releasePlot(player: Player)
	local index = player:GetAttribute("PlotIndex")
	if index and owners[index] == player then
		owners[index] = nil
		pcall(function()
			rooms[index]:RemovePersistentPlayer(player)
		end)
		local plot = PlotService.GetPlot(index)
		plot.Headframe.ElevatorPad.Color = Color3.fromHex("8D99AE")
		setLabel(plot.Headframe.Nameplate, "Empty plot")
	end
end

-- Move each owned plot's glowing depth marker and nameplate to match the owner's depth
local function refreshPlots()
	for i = 1, PLOT_COUNT do
		local plot = PlotService.GetPlot(i)
		local owner = owners[i]
		local data = owner and PlayerData.Get(owner)
		local marker = plot and plot:FindFirstChild("Column") and plot.Column:FindFirstChild("DepthMarker")
		if plot and marker then
			local depth = data and data.depth or 0
			local si = Formulas.StratumIndexAt(depth)
			local s = Strata[si]
			local frac = 1
			if s.bottom ~= math.huge then
				frac = math.clamp((depth - s.top) / (s.bottom - s.top), 0, 1)
			end
			-- the column shows four 25-stud bands from y = 100 down to y = 0
			local band = math.min(si, 4)
			local y = 100 - (band - 1) * 25 - frac * 25
			if si > 4 then
				y = 1
			end
			marker.Position = Vector3.new(marker.Position.X, math.clamp(y, 1, 99), marker.Position.Z)
			if owner and data then
				setLabel(plot.Headframe.Nameplate, string.format("%s  ·  %s m", owner.DisplayName, Formulas.FormatNumber(depth)))
			end
		end
	end
end

function PlotService.Init()
	-- the HUD's "Ride up" button: works from anywhere in your own shaft
	Remotes.RideUp.OnServerEvent:Connect(function(player)
		if player:GetAttribute("InShaft") == true then
			PlotService.SendUp(player)
		end
	end)

	shaftsFolder = Instance.new("Folder")
	shaftsFolder.Name = "Shafts"
	shaftsFolder.Parent = workspace

	local template = map:WaitForChild("ShaftRoom")
	for i = 1, PLOT_COUNT do
		rooms[i] = buildRoom(template, i)
	end
	template.Parent = ServerStorage -- keep the original out of the world

	for i = 1, PLOT_COUNT do
		local plot = PlotService.GetPlot(i)
		local pad = plot.Headframe.ElevatorPad
		pad.Color = Color3.fromHex("8D99AE")
		setLabel(plot.Headframe.Nameplate, "Empty plot")
		local down = addPrompt(pad, "RideDown", "Elevator", "Ride down", 10)
		down.Triggered:Connect(function(player)
			if owners[i] == player then
				PlotService.SendDown(player)
			end
		end)

		local up = addPrompt(rooms[i].Shell.ElevatorArrival, "RideUp", "Elevator", "Ride up", 10)
		up.Triggered:Connect(function(player)
			if owners[i] == player then
				PlotService.SendUp(player)
			end
		end)
	end
end

function PlotService.Start()
	local function onPlayer(player: Player)
		assignPlot(player)
		player:SetAttribute("InShaft", false)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("InShaft", false)
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(releasePlot)

	while true do
		refreshPlots()
		task.wait(2)
	end
end

return PlotService
