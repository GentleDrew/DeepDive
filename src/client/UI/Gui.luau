--!strict
-- Screen layers with resolution-independent scaling. Everything is laid out against a
-- 1280x760 reference canvas and scaled to the device (bigger on touch screens).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Gui = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

Gui.scale = 1
Gui.promptParent = playerGui
local scalers: { { frame: Frame, scale: UIScale } } = {}

local function computeScale(): number
	local camera = Workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.new(1280, 760)
	local s = math.min(size.X / 1280, size.Y / 760)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		s *= 1.18
	end
	return math.clamp(s, 0.5, 1.35)
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
	local s = computeScale()
	Gui.scale = s
	for _, entry in scalers do
		entry.scale.Scale = s
		entry.frame.Size = UDim2.fromScale(1 / s, 1 / s)
	end
end

Gui.world = layer("DeepDiveWorldFx", 1, true) -- vignettes, underwater tint
Gui.hud = layer("DeepDiveHud", 5, false)
Gui.panels = layer("DeepDivePanels", 10, false)
Gui.overlay = layer("DeepDiveOverlay", 20, true)
Gui.top = layer("DeepDiveTop", 30, true) -- loading screen, transitions

refresh()
local function watchCamera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	refresh()
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()

function Gui.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

return Gui
