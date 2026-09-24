--!strict
-- 3D model previews for UI (pets, eggs, relics) with a shared spin loop and a model cache.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetModels = require(Shared.Models.PetModels)
local RelicModels = require(Shared.Models.RelicModels)

local Viewport = {}

export type ViewApi = { frame: ViewportFrame, setModel: (Model?) -> (), setSpin: (boolean) -> (), destroy: () -> () }

type Entry = { model: Model?, frame: ViewportFrame, spin: boolean, base: CFrame, angle: number, bob: number }

local entries: { [ViewportFrame]: Entry } = {}
local cache: { [string]: Model } = {}

local function cached(key: string, build: () -> Model): Model
	local model = cache[key]
	if not model then
		model = build()
		cache[key] = model
	end
	return model:Clone()
end

function Viewport.pet(key: string): Model
	return cached("pet:" .. key, function()
		return PetModels.build(key, 3)
	end)
end

function Viewport.relic(key: string): Model
	return cached("relic:" .. key, function()
		return RelicModels.build(key, 2)
	end)
end

function Viewport.egg(world: number): Model
	return cached("egg:" .. world, function()
		return RelicModels.buildEgg(world, 3)
	end)
end

function Viewport.chest(world: number): Model
	return cached("chest:" .. world, function()
		return RelicModels.buildChest(world, 3)
	end)
end

local function frameModel(entry: Entry)
	local model = entry.model
	if not model then
		return
	end
	local camera = entry.frame.CurrentCamera
	if not camera then
		return
	end
	local _, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.08
	camera.CFrame = CFrame.lookAt(Vector3.new(0, radius * 0.25, -distance), Vector3.zero)
end

function Viewport.new(parent: Instance, size: UDim2, position: UDim2?, anchor: Vector2?): ViewApi
	local frame = Instance.new("ViewportFrame")
	frame.BackgroundTransparency = 1
	frame.Size = size
	frame.Position = position or UDim2.new()
	frame.AnchorPoint = anchor or Vector2.zero
	frame.Ambient = Color3.fromRGB(190, 200, 215)
	frame.LightColor = Color3.fromRGB(255, 250, 240)
	frame.LightDirection = Vector3.new(-0.4, -1, 0.6)
	frame.ZIndex = (parent :: any).ZIndex or 1
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = frame
	frame.CurrentCamera = camera
	frame.Parent = parent

	local entry: Entry = { model = nil, frame = frame, spin = false, base = CFrame.identity, angle = math.pi * 0.85, bob = math.random() * 6 }
	entries[frame] = entry

	local api: ViewApi = {
		frame = frame,
		setModel = function(_) end,
		setSpin = function(_) end,
		destroy = function() end,
	}
	api.setModel = function(model: Model?)
		if entry.model then
			entry.model:Destroy()
		end
		entry.model = model
		if model then
			model:PivotTo(CFrame.Angles(0, entry.angle, 0))
			model.Parent = frame
			frameModel(entry)
		end
	end
	api.setSpin = function(spin: boolean)
		entry.spin = spin
	end
	api.destroy = function()
		entries[frame] = nil
		frame:Destroy()
	end
	frame.Destroying:Connect(function()
		entries[frame] = nil
	end)
	return api
end

RunService.RenderStepped:Connect(function(dt: number)
	local t = os.clock()
	for _, entry in entries do
		if entry.spin and entry.model and entry.frame.Visible then
			entry.angle += dt * 1.1
			entry.model:PivotTo(CFrame.new(0, math.sin(t * 2 + entry.bob) * 0.08, 0) * CFrame.Angles(0, entry.angle, 0))
		end
	end
end)

return Viewport
