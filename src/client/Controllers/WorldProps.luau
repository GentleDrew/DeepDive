--!strict
-- Client-side life for the current world's props: spinning egg + portal, swaying plants,
-- localised signs and the floating egg label.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)

local WorldProps = {}

type Spinner = { instance: Instance, base: CFrame, speed: number, isModel: boolean }
type Swayer = { model: Model, base: CFrame, strength: number, phase: number }

function WorldProps.init(app: any)
	local spinners: { Spinner } = {}
	local swayers: { Swayer } = {}
	local guis: { Instance } = {}
	local loadedWorld = 0

	local function worldFolder(world: number): Instance?
		local worlds = Workspace:FindFirstChild("Worlds")
		return worlds and worlds:FindFirstChild("World" .. world)
	end

	local function signGui(part: BasePart, lines: { { text: string, size: number, color: Color3? } })
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = 0
		gui.Parent = part
		local holder = app.Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
		app.Kit.list(holder, Enum.FillDirection.Vertical, 0)
		for i, line in lines do
			app.Kit.text({
				Text = line.text,
				TextSize = line.size,
				Color = line.color,
				Stroke = 4,
				Size = UDim2.new(1, -20, 0, line.size + 10),
				LayoutOrder = i,
				Parent = holder,
			})
		end
		table.insert(guis, gui)
	end

	local function load(world: number)
		for _, gui in guis do
			gui:Destroy()
		end
		table.clear(guis)
		table.clear(spinners)
		table.clear(swayers)
		loadedWorld = world
		local wf = worldFolder(world)
		if not wf then
			loadedWorld = 0
			return
		end
		local data = Worlds.get(world)
		for _, descendant in wf:GetDescendants() do
			local spin = descendant:GetAttribute("Spin")
			if type(spin) == "number" then
				if descendant:IsA("Model") then
					table.insert(spinners, { instance = descendant :: Instance, base = descendant:GetPivot(), speed = spin, isModel = true })
				elseif descendant:IsA("BasePart") then
					table.insert(spinners, { instance = descendant :: Instance, base = descendant.CFrame, speed = spin, isModel = false })
				end
			end
			local sway = descendant:GetAttribute("Sway")
			if type(sway) == "number" and descendant:IsA("Model") then
				table.insert(swayers, { model = descendant, base = descendant:GetPivot(), strength = sway, phase = math.random() * 6.28 })
			end
			if descendant.Name == "WorldSign" and descendant:IsA("BasePart") then
				signGui(descendant, {
					{ text = Strings.get("world", { n = world }), size = 58, color = Color.hex(data.accent[1]) },
					{ text = Strings.name(data.name), size = 44 },
				})
			elseif descendant.Name == "KioskSign" and descendant:IsA("BasePart") then
				signGui(
					descendant,
					{ { text = utf8.char(0x1F93F) .. " " .. Strings.get("menu.upgrades"), size = 52, color = Color3.fromRGB(255, 226, 120) } }
				)
			elseif descendant.Name == "GodSharkSign" and descendant:IsA("BasePart") then
				signGui(descendant, {
					{ text = utf8.char(0x1F988) .. " GOD SHARK", size = 50, color = Color3.fromRGB(255, 236, 120) },
					{ text = Strings.get("limited") .. "  ·  R$ 399", size = 34, color = Color3.fromRGB(255, 120, 140) },
				})
			elseif descendant.Name == "EnchantSign" and descendant:IsA("BasePart") then
				signGui(
					descendant,
					{ { text = utf8.char(0x2728) .. " " .. Strings.get("enchantAltar"), size = 46, color = Color3.fromRGB(226, 180, 255) } }
				)
			elseif descendant.Name == "SellSign" and descendant:IsA("BasePart") then
				signGui(
					descendant,
					{ { text = utf8.char(0x1F4B0) .. " " .. Strings.get("sellShop"), size = 50, color = Color3.fromRGB(255, 222, 92) } }
				)
			elseif descendant.Name == "EggAnchor" and descendant:IsA("BasePart") then
				local billboard = Instance.new("BillboardGui")
				billboard.Size = UDim2.fromOffset(300, 96)
				billboard.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
				billboard.LightInfluence = 0
				billboard.MaxDistance = 90
				billboard.Parent = descendant
				local frame = app.Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = billboard })
				app.Kit.list(frame, Enum.FillDirection.Vertical, 2)
				app.Kit.text({
					Text = Strings.name(data.egg.name),
					TextSize = 34,
					Color = Color.hex(data.egg.accent),
					Stroke = 4,
					Size = UDim2.new(1, 0, 0, 40),
					LayoutOrder = 1,
					Parent = frame,
				})
				local costRow = app.Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, Parent = frame })
				app.Kit.list(costRow, Enum.FillDirection.Horizontal, 6)
				local coin = app.Kit.Icons.coin(32, costRow)
				coin.LayoutOrder = 1
				app.Kit.text({
					Text = Format.short(Economy.eggCost(world)),
					TextSize = 32,
					Stroke = 4,
					Size = UDim2.new(0, 0, 1, 0),
					AutoX = true,
					LayoutOrder = 2,
					Parent = costRow,
				})
				table.insert(guis, billboard)
			end
		end
	end

	app.State.languageChanged:Connect(function()
		loadedWorld = 0
	end)

	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt: number)
		local world = app.State.world
		if loadedWorld ~= world then
			load(world)
		end
		local t = os.clock()
		for _, spinner in spinners do
			local cf = spinner.base
				* CFrame.new(0, if spinner.isModel then math.sin(t * 1.6) * 0.5 else 0, 0)
				* CFrame.Angles(0, t * spinner.speed, 0)
			if spinner.isModel then
				(spinner.instance :: Model):PivotTo(cf)
			else
				local part = spinner.instance :: BasePart
				part.CFrame = spinner.base * CFrame.Angles(t * spinner.speed, 0, 0)
			end
		end
		accumulator += dt
		if accumulator < 1 / 30 or app.State.settings().lowFx then
			return
		end
		accumulator = 0
		local camera = Workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
		for _, swayer in swayers do
			if (swayer.base.Position - cameraPosition).Magnitude < 140 then
				local s = swayer.strength
				swayer.model:PivotTo(swayer.base * CFrame.Angles(math.sin(t * 1.1 + swayer.phase) * s, 0, math.cos(t * 0.8 + swayer.phase) * s))
			end
		end
	end)
end

return WorldProps
