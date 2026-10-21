--!nonstrict
-- Shared look for every UI panel: cream paper panels, dark brown outlines,
-- chunky rounded buttons. Colors and fonts come from the project guide.

local TweenService = game:GetService("TweenService")

local Style = {}

Style.Colors = {
	Panel = Color3.fromHex("FFF6E5"),
	Outline = Color3.fromHex("4A2E1A"),
	Text = Color3.fromHex("4A2E1A"),
	TextLight = Color3.fromHex("FFF6E5"),
	Muted = Color3.fromHex("8A6A52"),
	Green = Color3.fromHex("5CD65C"),
	Gold = Color3.fromHex("FFC233"),
	Blue = Color3.fromHex("4DA6FF"),
	Red = Color3.fromHex("FF6B6B"),
	Orange = Color3.fromHex("FF9F43"),
	Disabled = Color3.fromHex("C9BBA8"),
	Track = Color3.fromHex("E8D9C0"),
}

Style.Heading = Font.fromEnum(Enum.Font.FredokaOne)
Style.Body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.SemiBold)

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
	return c
end
Style.Corner = corner

local function stroke(parent: Instance, thickness: number?, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 3
	s.Color = color or Style.Colors.Outline
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
Style.Stroke = stroke

function Style.Padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	return p
end

function Style.Panel(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2?)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor or Vector2.zero
	f.BackgroundColor3 = Style.Colors.Panel
	f.BorderSizePixel = 0
	corner(f, 12)
	stroke(f, 3)
	f.Parent = parent
	return f
end

-- heading = true uses Fredoka One with a dark outline (for numbers and titles)
function Style.Label(parent: Instance, text: string, textSize: number, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = textSize
	l.TextColor3 = Style.Colors.Text
	l.FontFace = Style.Body
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.new(1, 0, 0, textSize + 6)
	if props then
		if props.heading then
			l.FontFace = Style.Heading
		end
		if props.outlined then
			l.TextColor3 = Style.Colors.TextLight
			l.TextStrokeColor3 = Style.Colors.Outline
			l.TextStrokeTransparency = 0
		end
		for k, v in pairs(props) do
			if k ~= "heading" and k ~= "outlined" then
				l[k] = v
			end
		end
	end
	l.Parent = parent
	return l
end

function Style.Button(parent: Instance, text: string, color: Color3, size: UDim2, onClick: () -> ())
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.AutoButtonColor = false
	b.Text = text
	b.TextSize = 20
	b.FontFace = Style.Heading
	b.TextColor3 = Style.Colors.TextLight
	b.TextStrokeColor3 = Style.Colors.Outline
	b.TextStrokeTransparency = 0
	corner(b, 10)
	stroke(b, 3)
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.93 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	b.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	b.Activated:Connect(onClick)
	b.Parent = parent
	return b
end

-- Shrinks every UI on small phone screens
function Style.AutoScale(gui: ScreenGui)
	local s = Instance.new("UIScale")
	s.Parent = gui
	local camera = workspace.CurrentCamera
	local function refresh()
		local vp = camera.ViewportSize
		s.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.55, 1.15)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	refresh()
end

-- Number that ticks up to its value instead of jumping
function Style.CountUp(label: TextLabel, from: number, to: number, seconds: number, format: (number) -> string)
	task.spawn(function()
		local start = os.clock()
		while true do
			local a = math.clamp((os.clock() - start) / seconds, 0, 1)
			local eased = 1 - (1 - a) ^ 3
			label.Text = format(from + (to - from) * eased)
			if a >= 1 then
				break
			end
			task.wait()
		end
	end)
end

return Style
