--!strict
-- Full-screen moments: loading curtain, blackout, and the bubble wipe used for world travel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)

local Anim = require(script.Parent.Anim)
local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Screens = {}

local C = Theme.C

local function bubbles(parent: Frame, count: number)
	local alive = true
	task.spawn(function()
		while alive and parent.Parent do
			local size = math.random(10, 44)
			local bubble = Kit.new("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.72,
				Size = UDim2.fromOffset(size, size),
				Position = UDim2.new(math.random(), 0, 1, size),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Parent = parent,
			})
			Kit.round(bubble)
			Kit.stroke(bubble, Color3.new(1, 1, 1), 2).Transparency = 0.4
			local duration = 4 + math.random() * 4
			Anim.tween(
				bubble,
				duration,
				{ Position = UDim2.new(bubble.Position.X.Scale + (math.random() - 0.5) * 0.1, 0, -0.1, 0) },
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			)
			task.delay(duration, function()
				bubble:Destroy()
			end)
			task.wait(4 / count)
		end
	end)
	return function()
		alive = false
	end
end

-- Loading -----------------------------------------------------------------------------------------

local loading: Frame? = nil
local stopLoadingBubbles: (() -> ())? = nil
local loadingStatus: TextLabel? = nil

function Screens.showLoading()
	local frame = Kit.new("Frame", {
		Name = "Loading",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 100,
		Parent = Gui.top,
	}) :: Frame
	Kit.gradient(frame, Color.hex("#3fd6ff"), Color.hex("#0a1f4a"))
	stopLoadingBubbles = bubbles(frame, 16)

	local titleRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(900, 150),
		Position = UDim2.fromScale(0.5, 0.4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 101,
		Parent = frame,
	})
	Kit.list(titleRow, Enum.FillDirection.Horizontal, 2)
	local letters = {}
	local title = Strings.get("title")
	for index, char in utf8.codes(title) do
		-- Each letter sits in a fixed-width holder so it can bob without fighting the list layout.
		local glyph = utf8.char(char)
		local width = if char == 32 then 36 else TextService:GetTextSize(glyph, 110, Enum.Font.FredokaOne, Vector2.new(1000, 1000)).X + 8
		local holder = Kit.new(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.fromOffset(width, 140), LayoutOrder = index, ZIndex = 102, Parent = titleRow }
		)
		local letter = Kit.text({
			Text = glyph,
			TextSize = 110,
			Size = UDim2.fromScale(1, 1),
			Stroke = 6,
			StrokeColor = C.Outline,
			ZIndex = 102,
			Parent = holder,
		})
		Kit.gradient(letter, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 230, 255))
		table.insert(letters, letter)
	end
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not frame.Parent then
			connection:Disconnect()
			return
		end
		local t = os.clock() - start
		for i, letter in letters do
			letter.Position = UDim2.fromOffset(0, math.sin(t * 3 - i * 0.45) * 10)
			letter.Rotation = math.sin(t * 2 - i * 0.5) * 4
		end
	end)
	Kit.text({
		Text = Strings.get("subtitle"),
		TextSize = 30,
		Size = UDim2.fromOffset(800, 40),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 101,
		Parent = frame,
	})
	loadingStatus = Kit.text({
		Text = Strings.get("loading"),
		TextSize = 26,
		Color = Color.hex("#bdefff"),
		Size = UDim2.fromOffset(800, 36),
		Position = UDim2.fromScale(0.5, 0.78),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 101,
		Parent = frame,
	})
	local dots = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(120, 24),
		Position = UDim2.fromScale(0.5, 0.84),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 101,
		Parent = frame,
	})
	Kit.list(dots, Enum.FillDirection.Horizontal, 12)
	for i = 1, 3 do
		local dot = Kit.new(
			"Frame",
			{ BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(18, 18), LayoutOrder = i, ZIndex = 102, Parent = dots }
		)
		Kit.round(dot)
		task.spawn(function()
			while true do
				task.wait(i * 0.15)
				if not dot.Parent then
					break
				end
				Anim.pop(dot, 0.5)
				task.wait(1 - i * 0.15)
			end
		end)
	end
	loading = frame
end

function Screens.setLoadingStatus(text: string)
	if loadingStatus then
		loadingStatus.Text = text
	end
end

function Screens.hideLoading()
	local frame = loading
	if not frame then
		return
	end
	loading = nil
	if stopLoadingBubbles then
		stopLoadingBubbles()
	end
	local tween = Anim.tween(frame, 0.9, { Position = UDim2.fromScale(0, -1.1) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween.Completed:Once(function()
		frame:Destroy()
	end)
end

-- Blackout ----------------------------------------------------------------------------------------

local blackoutFrame = Kit.new("Frame", {
	Name = "Blackout",
	BackgroundColor3 = Color.hex("#030a18"),
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 90,
	Parent = Gui.top,
}) :: Frame
local blackoutTitle = Kit.text({
	Text = "",
	TextSize = 64,
	Size = UDim2.fromOffset(900, 80),
	Position = UDim2.fromScale(0.5, 0.44),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Color = Color.hex("#ff8a95"),
	Stroke = 4,
	ZIndex = 91,
	Parent = blackoutFrame,
})
local blackoutSub = Kit.text({
	Text = "",
	TextSize = 28,
	Size = UDim2.fromOffset(900, 40),
	Position = UDim2.fromScale(0.5, 0.54),
	AnchorPoint = Vector2.new(0.5, 0.5),
	ZIndex = 91,
	Parent = blackoutFrame,
})

function Screens.blackout()
	blackoutFrame.Visible = true
	blackoutFrame.BackgroundTransparency = 1
	blackoutTitle.Text = Strings.get("blackout")
	blackoutSub.Text = ""
	blackoutTitle.TextTransparency = 1
	Anim.tween(blackoutFrame, 1.0, { BackgroundTransparency = 0 })
	task.delay(0.4, function()
		Anim.tween(blackoutTitle, 0.4, { TextTransparency = 0 })
		Anim.pop(blackoutTitle, 0.3)
	end)
end

function Screens.rescued(text: string)
	if not blackoutFrame.Visible then
		return
	end
	blackoutSub.Text = text
	Anim.pop(blackoutSub, 0.2)
	task.delay(1.4, function()
		Anim.tween(blackoutTitle, 0.4, { TextTransparency = 1 })
		Anim.tween(blackoutFrame, 0.8, { BackgroundTransparency = 1 }).Completed:Once(function()
			blackoutFrame.Visible = false
			blackoutSub.Text = ""
		end)
	end)
end

-- Travel wipe ------------------------------------------------------------------------------------

local wipe = Kit.new("Frame", {
	Name = "TravelWipe",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Visible = false,
	ZIndex = 95,
	Parent = Gui.top,
}) :: Frame
local circle = Kit.new("Frame", {
	BackgroundColor3 = Color3.new(1, 1, 1),
	Size = UDim2.fromOffset(0, 0),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	ZIndex = 95,
	Parent = wipe,
}) :: Frame
Kit.round(circle)
local circleGradient = Kit.gradient(circle, C.Cyan, C.DeepBlue)
local wipeTitle = Kit.text({
	Text = "",
	TextSize = 72,
	Size = UDim2.fromOffset(1000, 90),
	Position = UDim2.fromScale(0.5, 0.45),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Stroke = 5,
	ZIndex = 96,
	Parent = wipe,
})
local wipeSub = Kit.text({
	Text = "",
	TextSize = 32,
	Size = UDim2.fromOffset(1000, 44),
	Position = UDim2.fromScale(0.5, 0.56),
	AnchorPoint = Vector2.new(0.5, 0.5),
	ZIndex = 96,
	Parent = wipe,
})
local stopWipeBubbles: (() -> ())? = nil

function Screens.travelStart(world: number)
	local data = Worlds.get(world)
	circleGradient.Color = ColorSequence.new(Color.hex(data.accent[1]), Color.hex(data.accent[2]))
	wipe.Visible = true
	wipeTitle.Text = ""
	wipeSub.Text = ""
	circle.Size = UDim2.fromOffset(0, 0)
	local size = math.max(Gui.top.AbsoluteSize.X, Gui.top.AbsoluteSize.Y) / Gui.scale * 1.6
	Anim.tween(circle, 0.55, { Size = UDim2.fromOffset(size, size) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.4, function()
		wipeTitle.Text = Strings.get("world", { n = world })
		wipeSub.Text = Strings.name(data.name)
		Anim.appear(wipeTitle, 0.45)
	end)
	stopWipeBubbles = bubbles(wipe, 14)
end

function Screens.travelEnd()
	if not wipe.Visible then
		return
	end
	task.delay(0.5, function()
		if stopWipeBubbles then
			stopWipeBubbles()
			stopWipeBubbles = nil
		end
		wipeTitle.Text = ""
		wipeSub.Text = ""
		Anim.tween(circle, 0.6, { Size = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out).Completed:Once(function()
			wipe.Visible = false
		end)
	end)
end

return Screens
