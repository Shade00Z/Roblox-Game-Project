--!nonstrict
-- Draws your own shaft: the side-on 2.5D camera, the dig front you and your crew
-- share, hold-to-mine input, and placeholder critters working the real blocks.
--
-- The dig-front blocks exist only on your device. What each block holds comes from
-- DigFront.CellAt(seed, meter, column), the same function the server uses, so the
-- server only ever sends which blocks are dug, never the blocks themselves.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local MaterialService = game:GetService("MaterialService")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Strata = require(Shared.Config.Strata)
local Economy = require(Shared.Config.Economy)
local OreConfig = require(Shared.Config.Ores)
local Critters = require(Shared.Config.Critters)
local Formulas = require(Shared.Formulas)
local DigFront = require(Shared.DigFront)

local ShaftRenderer = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local rng = Random.new()

local inShaft = false
local room: Model? = nil
local origin = Vector3.zero
local ledgeBlocks: { BasePart } = {}
local veins: { BasePart } = {}
local styledStratum = nil
local currentState = nil
local shownBitLevel = nil

local fxFolder: Folder
local backdrop: BasePart? = nil
local dolls: { Model } = {}
local dollX: { number } = {}
local dollY: { number } = {}
local dollSignature = ""
local firstCameraFrame = true

-- the dig front grid: grid[row][col] = Part (col is 0-based like DigFront)
local grid: { { BasePart } } = {}
local gridParts: { BasePart } = {}
local shownTop: number? = nil
local shownRows: { number }? = nil

-- local hit feedback for the block being mined
local localHits: { key: string, hits: number } = { key = "", hits = 0 }

-- a toast function the HUD hands us (so the renderer doesn't require the HUD)
local toast: (string) -> () = function() end

----------------------------------------------------------------------
-- Looks
----------------------------------------------------------------------

local variantCache = {}
local function findVariant(name: string)
	if variantCache[name] == nil then
		variantCache[name] = MaterialService:FindFirstChild(name, true) or false
	end
	return variantCache[name] or nil
end

local function applyLook(part: BasePart, look)
	local variant = look.variant and findVariant(look.variant)
	if variant then
		part.Material = variant.BaseMaterial
		part.MaterialVariant = look.variant
		part.Color = look.tint or Color3.new(1, 1, 1)
	else
		part.MaterialVariant = ""
		part.Material = look.material or (look.glow and Enum.Material.Neon or Enum.Material.SmoothPlastic)
		part.Color = look.tint and look.color:Lerp(Color3.new(0, 0, 0), 0.4) or look.color
	end
end

local function rockLook(si: number)
	local s = Strata[si]
	return { color = s.rockColor, variant = s.rockVariant }
end

local GEODE_LOOK = { color = Color3.fromHex("9B5DE5"), material = Enum.Material.Ice }
local EGG_LOOK = { color = Color3.fromHex("F3E6C8"), material = Enum.Material.Marble }

local function cellLook(cell)
	if cell.kind == "ore" then
		local ore = OreConfig.Ores[cell.oreId]
		return { color = ore.color, variant = ore.variant, glow = ore.glow }
	elseif cell.kind == "pocket" then
		-- pockets always glow, so they stand out from a plain ore block
		return { color = OreConfig.Ores[cell.oreId].color, glow = true }
	elseif cell.kind == "geode" then
		return GEODE_LOOK
	elseif cell.kind == "egg" then
		return EGG_LOOK
	end
	return rockLook(cell.stratum)
end

-- Restyle the ledges and walls for the current stratum
local function styleRoom(si: number)
	if not room then
		return
	end
	styledStratum = si
	for _, block in ipairs(ledgeBlocks) do
		applyLook(block, rockLook(si))
	end
	local shell = room:FindFirstChild("Shell")
	if shell then
		local wallLook = rockLook(si)
		wallLook.tint = Color3.fromRGB(150, 130, 120)
		for _, name in ipairs({ "BackWall", "LeftWall", "RightWall", "Ceiling" }) do
			local p = shell:FindFirstChild(name)
			if p then
				applyLook(p, wallLook)
			end
		end
	end
end

----------------------------------------------------------------------
-- Effects
----------------------------------------------------------------------

local function burst(position: Vector3, color: Color3, amount: number?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Speed = NumberRange.new(10, 16)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Rate = 0
	emitter.LightEmission = 0.2
	emitter.Parent = p
	p.Parent = fxFolder
	emitter:Emit(amount or 14)
	Debris:AddItem(p, 1.2)
end

----------------------------------------------------------------------
-- The dig front grid
----------------------------------------------------------------------

local BLOCK_SIZE = Vector3.new(4, 4, 8) -- one block spans both depth layers of the room

local function buildGrid()
	for _, p in ipairs(gridParts) do
		p:Destroy()
	end
	grid, gridParts = {}, {}
	for row = 1, DigFront.ROWS do
		grid[row] = {}
		for col = 0, DigFront.WIDTH - 1 do
			local p = Instance.new("Part")
			p.Name = "DigBlock"
			p.Anchored = true
			p.Size = BLOCK_SIZE
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Position = DigFront.CellPosition(origin, row, col)
			p:SetAttribute("Row", row)
			p:SetAttribute("Col", col)
			p.Parent = fxFolder
			grid[row][col] = p
			table.insert(gridParts, p)
		end
	end
	shownTop, shownRows = nil, nil
end

local function setVisible(p: BasePart, visible: boolean)
	p.Transparency = visible and 0 or 1
	p.CanCollide = visible
	p.CanQuery = visible
end

-- Draw every block from the state (no animation)
local function drawAll(state)
	local front = state.front
	for row = 1, DigFront.ROWS do
		local meter = front.top + row - 1
		for col = 0, DigFront.WIDTH - 1 do
			local p = grid[row][col]
			p.Size = BLOCK_SIZE
			p.Position = DigFront.CellPosition(origin, row, col)
			if DigFront.IsMined(front.rows[row], col) then
				setVisible(p, false)
			else
				setVisible(p, true)
				applyLook(p, cellLook(DigFront.CellAt(state.seed, meter, col)))
				-- rock too tough for your drill bit looks darker (it takes longer to dig)
				local bit = Economy.Bits[state.bitLevel] or Economy.Bits[1]
				if Formulas.TiersShort(bit.tier, Formulas.StratumIndexAt(meter)) > 0 then
					p.Color = p.Color:Lerp(Color3.new(0, 0, 0), 0.35)
				end
			end
		end
	end
	shownTop = front.top
	shownRows = table.clone(front.rows)
end

local function breakVisual(p: BasePart)
	burst(p.Position, p.Color)
	p.CanCollide = false
	p.CanQuery = false
	TweenService:Create(p, TweenInfo.new(0.15), { Size = BLOCK_SIZE * 0.2, Transparency = 1 }):Play()
end

-- Compare the new state with what's on screen and animate the difference
local function refreshGrid(state)
	if #gridParts == 0 then
		return
	end
	local front = state.front
	if shownTop == nil or shownRows == nil then
		drawAll(state)
		return
	end

	local rose = front.top - shownTop
	if rose > 0 then
		-- break through: the dig front slides up, carrying you with it if you're in a hole
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root.Position.Y < origin.Y + 13 and math.abs(root.Position.X - origin.X) < 21 then
			character:PivotTo(character:GetPivot() + Vector3.new(0, 4 * math.min(rose, DigFront.ROWS), 0))
		end
		-- the row that was just cleared bursts
		if shownRows[1] then
			for col = 0, DigFront.WIDTH - 1 do
				if not DigFront.IsMined(shownRows[1], col) then
					burst(grid[1][col].Position, grid[1][col].Color, 6)
				end
			end
		end
		drawAll(state)
		-- the rows below rise into place
		if rose == 1 then
			for _, p in ipairs(gridParts) do
				local final = p.Position
				p.Position = final - Vector3.new(0, 4, 0)
				TweenService:Create(p, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = final }):Play()
			end
		end
		return
	end

	-- same rows: break the blocks that were dug since last time
	for row = 1, DigFront.ROWS do
		local was, now = shownRows[row], front.rows[row]
		if was ~= now then
			for col = 0, DigFront.WIDTH - 1 do
				if DigFront.IsMined(now, col) and not DigFront.IsMined(was, col) then
					breakVisual(grid[row][col])
				end
			end
		end
	end
	shownRows = table.clone(front.rows)
end

----------------------------------------------------------------------
-- Critter stand-ins working the real blocks (real models come later)
----------------------------------------------------------------------

local function makeDoll(speciesId: string, stars: number): Model
	local sp = Critters.Species[speciesId]
	local m = Instance.new("Model")
	m.Name = speciesId
	local function piece(name, shape, size, color, offset)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p:SetAttribute("Offset", offset)
		p.Parent = m
		return p
	end
	piece("Body", Enum.PartType.Ball, Vector3.new(2.4, 2.4, 2.4), sp.color, CFrame.new())
	piece("Hat", Enum.PartType.Cylinder, Vector3.new(0.6, 1.9, 1.9), sp.accent, CFrame.new(0, 1.15, 0) * CFrame.Angles(0, 0, math.rad(90)))
	piece("EyeL", Enum.PartType.Ball, Vector3.new(0.38, 0.38, 0.38), Color3.new(0.08, 0.06, 0.05), CFrame.new(-0.45, 0.3, -1.05))
	piece("EyeR", Enum.PartType.Ball, Vector3.new(0.38, 0.38, 0.38), Color3.new(0.08, 0.06, 0.05), CFrame.new(0.45, 0.3, -1.05))
	local ring = piece("Aura", Enum.PartType.Cylinder, Vector3.new(0.15, 3, 3), Critters.RarityColors[sp.rarity], CFrame.new(0, -1.2, 0) * CFrame.Angles(0, 0, math.rad(90)))
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.3
	-- merged critters show their stars overhead
	if stars > 0 then
		local tag = Instance.new("BillboardGui")
		tag.Name = "Stars"
		tag.Size = UDim2.new(1.5 * stars, 0, 1.8, 0) -- studs, so it scales with the camera
		tag.StudsOffset = Vector3.new(0, 3.3, 0)
		tag.LightInfluence = 0
		tag.MaxDistance = 120
		tag.Adornee = m.Body
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Text = string.rep("★", stars)
		text.TextScaled = true
		text.TextColor3 = Color3.fromHex("FFC233")
		text.TextStrokeColor3 = Color3.fromHex("4A2E1A")
		text.TextStrokeTransparency = 0
		text.Font = Enum.Font.FredokaOne
		text.Parent = tag
		tag.Parent = m.Body
	end
	m.Parent = fxFolder
	return m
end

local function rebuildDolls(state)
	local byId = {}
	for _, c in ipairs(state.critters) do
		byId[c.id] = c
	end
	local members, parts = {}, {}
	for _, id in ipairs(state.crew) do
		local c = byId[id]
		if c then
			table.insert(members, c)
			table.insert(parts, c.species .. "*" .. (c.stars or 0))
		end
	end
	local sig = table.concat(parts, ",") .. tostring(room)
	if sig == dollSignature then
		return
	end
	dollSignature = sig
	for _, d in ipairs(dolls) do
		d:Destroy()
	end
	dolls, dollX, dollY = {}, {}, {}
	if not inShaft then
		return
	end
	for _, c in ipairs(members) do
		table.insert(dolls, makeDoll(c.species, c.stars or 0))
	end
end

-- Each critter stands on top of the block it is digging, in whichever row that block
-- is (the server decides, and only moves a critter when its own block breaks). A
-- critter digging the second row rides up when the top row clears, because its
-- block's row number changes and it glides to the new height.
local function animateDolls(t: number, dt: number)
	local state = currentState
	if not state or #dolls == 0 then
		return
	end
	local targets = DigFront.CrewTargets(state.front)
	for i, doll in ipairs(dolls) do
		local cell = targets[i]
		local targetX, targetY
		if cell and cell >= 0 then
			local row, col = DigFront.DecodeCell(cell)
			local pos = DigFront.CellPosition(origin, row, col)
			targetX, targetY = pos.X, pos.Y + 2 + 1.2
		else
			local home = DigFront.CellPosition(origin, 1, math.floor((i - 0.5) * DigFront.WIDTH / #dolls))
			targetX = dollX[i] or home.X
			targetY = dollY[i] or home.Y + 2 + 1.2
		end
		dollX[i] = dollX[i] and (dollX[i] + (targetX - dollX[i]) * math.min(1, dt * 6)) or targetX
		dollY[i] = dollY[i] and (dollY[i] + (targetY - dollY[i]) * math.min(1, dt * 10)) or targetY
		local hop = math.abs(math.sin(t * 7 + i * 1.7)) * 0.7
		local lean = math.sin(t * 14 + i) * 0.25
		local base = CFrame.new(dollX[i], dollY[i] + hop, origin.Z + 1) * CFrame.Angles(lean, 0, 0)
		for _, p in ipairs(doll:GetChildren()) do
			p.CFrame = base * p:GetAttribute("Offset")
		end
	end
end

----------------------------------------------------------------------
-- Camera
----------------------------------------------------------------------

-- A fixed "ant farm" view of the whole room. It's framed a little low so the dig
-- front sits above the cart bar and geode rack at the bottom of the screen.
local CAMERA_HEIGHT = 18 -- studs above the room floor
local CAMERA_DISTANCE = 64 -- studs in front of the room

local function updateCamera(dt: number)
	local eye = origin + Vector3.new(0, CAMERA_HEIGHT, -CAMERA_DISTANCE)
	local target = CFrame.lookAt(eye, origin + Vector3.new(0, CAMERA_HEIGHT, 4))
	if firstCameraFrame then
		camera.CFrame = target
		firstCameraFrame = false
	else
		camera.CFrame = camera.CFrame:Lerp(target, math.min(1, dt * 8))
	end
end

----------------------------------------------------------------------
-- Input: tap veins, hold on a block to mine it
----------------------------------------------------------------------

local pointerDown = false
local pointerPos = Vector2.zero
local nextSwing = 0
local lastRangeHint = 0
local toughHintShown = false

local function raycastFrom(screen: Vector2, targets: { Instance })
	local ray = camera:ScreenPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = targets
	return workspace:Raycast(ray.Origin, ray.Direction * 200, params)
end

local function tryVein(screen: Vector2): boolean
	if #veins == 0 then
		return false
	end
	local hit = raycastFrom(screen, veins)
	if hit and hit.Instance.Material == Enum.Material.Neon then
		burst(hit.Position, hit.Instance.Color)
		Remotes.TapVein:FireServer(hit.Instance:GetAttribute("VeinIndex"))
		return true
	end
	return false
end

-- One swing at whatever block is under the pointer
local function swing()
	local state = currentState
	if not state or #gridParts == 0 then
		return
	end
	local hit = raycastFrom(pointerPos, gridParts)
	if not hit then
		return
	end
	local part = hit.Instance
	local row, col = part:GetAttribute("Row"), part:GetAttribute("Col")
	local front = state.front
	local meter = front.top + row - 1
	if DigFront.IsMined(front.rows[row], col) or not DigFront.Exposed(front, row, col) then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - part.Position).Magnitude > Economy.Dig.Reach then
		if os.clock() - lastRangeHint > 3 then
			lastRangeHint = os.clock()
			toast("Walk closer to dig that block.")
		end
		return
	end

	local pick = Economy.Pickaxes[state.pickaxeLevel] or Economy.Pickaxes[1]
	nextSwing = os.clock() + pick.swing
	Remotes.MineBlock:FireServer(meter, col)

	-- instant local feedback: chips fly and the block darkens as it cracks
	local key = meter .. ":" .. col
	if localHits.key ~= key then
		localHits = { key = key, hits = 0 }
	end
	localHits.hits += 1
	local needed = DigFront.HitsNeeded(meter, state.pickaxeLevel, state.bitLevel)
	if needed > DigFront.HitsNeeded(meter, state.pickaxeLevel) and not toughHintShown then
		toughHintShown = true
		toast("Tough rock! Your drill bit isn't built for this depth, so digging is slower. Upgrade at the Drill Shop.")
	end
	burst(hit.Position, part.Color, 4)
	if localHits.hits < needed then
		local base = part.Color
		part.Color = base:Lerp(Color3.new(0, 0, 0), 0.12)
		part.Size = BLOCK_SIZE * 0.92
		TweenService:Create(part, TweenInfo.new(0.1), { Size = BLOCK_SIZE }):Play()
	end
end

-- the mouse button or the one finger that is mining (so lifting the thumb that's
-- on the movement stick doesn't stop the finger that's digging)
local activeInput: InputObject? = nil

local function onInputBegan(input: InputObject, processed: boolean)
	if processed or not inShaft then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local screen = Vector2.new(input.Position.X, input.Position.Y)
		if tryVein(screen) then
			return
		end
		activeInput = input
		pointerDown = true
		pointerPos = screen
		if os.clock() >= nextSwing then
			swing()
		end
	end
end

local function onInputChanged(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input == activeInput then
		pointerPos = Vector2.new(input.Position.X, input.Position.Y)
	end
end

local function onInputEnded(input: InputObject)
	if input == activeInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
		activeInput = nil
		pointerDown = false
	end
end

----------------------------------------------------------------------
-- Entering and leaving
----------------------------------------------------------------------

-- A dark rock wall far behind the room so the sky never shows underground
local function makeBackdrop()
	if backdrop then
		backdrop:Destroy()
	end
	local p = Instance.new("Part")
	p.Name = "Backdrop"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromHex("1E140E")
	p.Size = Vector3.new(400, 300, 2)
	p.Position = origin + Vector3.new(0, 20, 30)
	p.Parent = fxFolder
	backdrop = p
end

local function findRoom(): Model?
	local index = player:GetAttribute("PlotIndex")
	local shafts = workspace:FindFirstChild("Shafts")
	return index and shafts and shafts:FindFirstChild("Shaft" .. index) or nil
end

local function collectRoomParts()
	ledgeBlocks, veins = {}, {}
	local shell = room and room:FindFirstChild("Shell")
	if shell then
		for _, p in ipairs(shell:GetChildren()) do
			if p.Name == "Vein" and p:IsA("BasePart") then
				table.insert(veins, p)
			end
		end
	end
	local blocks = room and room:FindFirstChild("Blocks")
	if blocks then
		for _, b in ipairs(blocks:GetChildren()) do
			if b:IsA("BasePart") then
				table.insert(ledgeBlocks, b)
			end
		end
	end
end

local hintShown = false

local function enterShaft()
	room = findRoom()
	if not room then
		-- streaming may still be delivering the room
		local shafts = workspace:WaitForChild("Shafts", 5)
		room = shafts and shafts:WaitForChild("Shaft" .. tostring(player:GetAttribute("PlotIndex")), 5)
	end
	if not room then
		warn("[ShaftRenderer] Could not find your shaft room")
		return
	end
	origin = room:GetAttribute("Origin")
	room:WaitForChild("Shell", 5)
	collectRoomParts()

	inShaft = true
	firstCameraFrame = true
	makeBackdrop()
	buildGrid()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = 50
	if currentState then
		styleRoom(currentState.stratum)
		drawAll(currentState)
		dollSignature = ""
		rebuildDolls(currentState)
	end
	if not hintShown then
		hintShown = true
		task.delay(1, toast, "Hold on a block to dig it yourself. Your crew digs alongside you!")
	end
	RunService:BindToRenderStep("ShaftCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		updateCamera(dt)
		animateDolls(os.clock(), dt)
		if pointerDown and os.clock() >= nextSwing then
			swing()
		end
	end)
end

local function leaveShaft()
	if not inShaft then
		return
	end
	inShaft = false
	pointerDown = false
	RunService:UnbindFromRenderStep("ShaftCamera")
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	for _, d in ipairs(dolls) do
		d:Destroy()
	end
	dolls, dollX, dollY = {}, {}, {}
	dollSignature = ""
	for _, p in ipairs(gridParts) do
		p:Destroy()
	end
	grid, gridParts = {}, {}
	shownTop, shownRows = nil, nil
	if backdrop then
		backdrop:Destroy()
		backdrop = nil
	end
end

----------------------------------------------------------------------
-- Public
----------------------------------------------------------------------

-- toastFn: shows a short message (the HUD passes its Toast)
function ShaftRenderer.Init(toastFn: ((string) -> ())?)
	if toastFn then
		toast = toastFn
	end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "LocalShaftFX"
	fxFolder.Parent = workspace

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)

	player:GetAttributeChangedSignal("InShaft"):Connect(function()
		if player:GetAttribute("InShaft") then
			enterShaft()
		else
			leaveShaft()
		end
	end)
	if player:GetAttribute("InShaft") then
		task.spawn(enterShaft)
	end
end

function ShaftRenderer.Update(state)
	currentState = state
	if not inShaft then
		return
	end
	if state.stratum ~= styledStratum then
		styleRoom(state.stratum)
		shownTop = nil -- redraw blocks in the new stratum's look
	end
	if state.bitLevel ~= shownBitLevel then
		shownBitLevel = state.bitLevel
		shownTop = nil -- a new drill bit can turn tough rock back to normal
	end
	refreshGrid(state)
	rebuildDolls(state)
end

return ShaftRenderer
