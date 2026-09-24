--!strict
-- Screen layers with resolution-independent scaling. Everything is laid out against a 1280x700
-- reference canvas (the usable area below the Roblox top bar) and scaled to the device.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Signal"))

local Gui = {}

local REFERENCE = Vector2.new(1280, 700)
-- Touch screens get bigger UI, but never so big that the canvas drops below this height
-- (the HUD switches to a compact two-column menu and panels shrink to fit below 690).
local TOUCH_BOOST = 1.18
local MIN_CANVAS_HEIGHT = 600

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

Gui.scale = 1
Gui.canvasSize = REFERENCE
Gui.resized = Signal.new()
Gui.promptParent = playerGui
local scalers: { { frame: Frame, scale: UIScale } } = {}
local safeScreen: ScreenGui? = nil

function Gui.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Usable screen area: inside the top bar and device safe insets.
local function usableSize(): Vector2
	local screen = safeScreen
	if screen and screen.AbsoluteSize.X > 1 and screen.AbsoluteSize.Y > 1 then
		return screen.AbsoluteSize
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize - Vector2.new(0, 58) else REFERENCE
end

local function computeScale(usable: Vector2): number
	local s = math.min(usable.X / REFERENCE.X, usable.Y / REFERENCE.Y)
	if Gui.isTouch() then
		s = math.min(s * TOUCH_BOOST, usable.Y / MIN_CANVAS_HEIGHT)
	end
	-- Never scale above the reference size: big monitors get more room, not bigger buttons.
	return math.clamp(s, 0.45, 1)
end

local function layer(name: string, order: number, fullscreen: boolean): Frame
	local screen = Instance.new("ScreenGui")
	screen.Name = name
	screen.ResetOnSpawn = false
	screen.DisplayOrder = order
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.IgnoreGuiInset = fullscreen
	screen.ScreenInsets = if fullscreen then Enum.ScreenInsets.None else Enum.ScreenInsets.CoreUISafeInsets
	screen.Parent = playerGui
	if not fullscreen and not safeScreen then
		safeScreen = screen
	end
	local container = Instance.new("Frame")
	container.Name = "Canvas"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)
	container.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Parent = container
	table.insert(scalers, { frame = container, scale = scale })
	return container
end

local function refresh()
	local usable = usableSize()
	local s = computeScale(usable)
	local canvas = usable / s
	local changed = math.abs(s - Gui.scale) > 1e-4 or (canvas - Gui.canvasSize).Magnitude > 0.5
	Gui.scale = s
	Gui.canvasSize = canvas
	for _, entry in scalers do
		entry.scale.Scale = s
		entry.frame.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	if changed then
		Gui.resized:Fire(canvas, s)
	end
end

Gui.world = layer("DeepDiveWorldFx", 1, true) -- vignettes, underwater tint
Gui.hud = layer("DeepDiveHud", 5, false)
-- Same level as the HUD but drawn from the very top of the screen (the player list sits in the
-- Roblox top-bar row, which is empty on the right).
Gui.hudTop = layer("DeepDiveHudTop", 6, true)
Gui.panels = layer("DeepDivePanels", 10, false)
Gui.overlay = layer("DeepDiveOverlay", 20, true)
Gui.top = layer("DeepDiveTop", 30, true) -- loading screen, transitions

refresh()
if safeScreen then
	safeScreen:GetPropertyChangedSignal("AbsoluteSize"):Connect(refresh)
end
local function watchCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	refresh()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

return Gui
