--!strict
-- Per-world look (sky, lighting, water, terrain palette) and the underwater transition: tint,
-- haze, depth darkening, blur, reverb, drifting plankton, god rays and a headlamp in the deep.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Layout = require(Shared.Layout)
local Worlds = require(Shared.Data.Worlds)

local Ambience = {}

local player = Players.LocalPlayer
local terrain = Workspace.Terrain

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Ambience.init(app: any)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
	local colorFx = Lighting:FindFirstChild("DiveColor") :: ColorCorrectionEffect? or Instance.new("ColorCorrectionEffect")
	colorFx.Name = "DiveColor"
	colorFx.Parent = Lighting
	local blur = Lighting:FindFirstChild("DiveBlur") :: BlurEffect? or Instance.new("BlurEffect")
	blur.Name = "DiveBlur"
	blur.Parent = Lighting
	local bloom = Lighting:FindFirstChild("DiveBloom") :: BloomEffect? or Instance.new("BloomEffect")
	bloom.Name = "DiveBloom"
	bloom.Parent = Lighting
	local sunRays = Lighting:FindFirstChild("DiveSunRays") :: SunRaysEffect? or Instance.new("SunRaysEffect")
	sunRays.Name = "DiveSunRays"
	sunRays.Parent = Lighting
	local clouds = terrain:FindFirstChildOfClass("Clouds")

	local folder = Workspace:FindFirstChild("DeepDiveClient") or Instance.new("Folder")
	folder.Name = "DeepDiveClient"
	folder.Parent = Workspace

	-- Plankton volume that follows the camera underwater.
	local plankton = Instance.new("Part")
	plankton.Name = "Plankton"
	plankton.Anchored = true
	plankton.CanCollide = false
	plankton.CanQuery = false
	plankton.CanTouch = false
	plankton.Transparency = 1
	plankton.Size = Vector3.new(70, 40, 70)
	plankton.Parent = folder
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.12), NumberSequenceKeypoint.new(1, 0) })
	motes.Transparency = NumberSequence.new(0.35)
	motes.LightEmission = 0.8
	motes.LightInfluence = 0.2
	motes.Lifetime = NumberRange.new(4, 7)
	motes.Rate = 0
	motes.Speed = NumberRange.new(0.2, 0.8)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Parent = plankton

	-- God rays: faint beams slanting down from the surface of the current lagoon.
	local rays = Instance.new("Folder")
	rays.Name = "GodRays"
	rays.Parent = folder
	local rayBeams: { Beam } = {}
	local function buildRays(world: number)
		rays:ClearAllChildren()
		table.clear(rayBeams)
		local info = Layout.info(world)
		local data = Worlds.get(world)
		if data.sky.time > 19 or data.sky.time < 6 then
			return
		end
		local rng = Random.new(world * 31)
		for i = 1, 9 do
			local a = i / 9 * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local r = rng:NextNumber(0.1, 0.8) * info.radius
			local top = Instance.new("Part")
			top.Anchored = true
			top.CanCollide = false
			top.CanQuery = false
			top.CanTouch = false
			top.Transparency = 1
			top.Size = Vector3.new(1, 1, 1)
			top.Position = info.origin + Vector3.new(math.cos(a) * r, -0.5, math.sin(a) * r)
			top.Parent = rays
			local a0 = Instance.new("Attachment")
			a0.Parent = top
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(rng:NextNumber(-12, 12), -math.min(info.depth * 0.7, 70), rng:NextNumber(-12, 12))
			a1.Parent = top
			local beam = Instance.new("Beam")
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Width0 = rng:NextNumber(5, 9)
			beam.Width1 = rng:NextNumber(10, 16)
			beam.FaceCamera = true
			beam.LightEmission = 0.8
			beam.LightInfluence = 0
			beam.Color = ColorSequence.new(Color.lighten(Color.hex(data.water), 0.7))
			beam.Transparency =
				NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.5, 0.9), NumberSequenceKeypoint.new(1, 1) })
			beam.Segments = 2
			beam.Parent = top
			table.insert(rayBeams, beam)
		end
	end

	-- Headlamp for dark water.
	local lamp: SpotLight? = nil
	local glow: PointLight? = nil
	local function attachLamp(character: Model)
		local head = character:WaitForChild("Head", 10)
		if not head then
			return
		end
		local spot = Instance.new("SpotLight")
		spot.Name = "Headlamp"
		spot.Face = Enum.NormalId.Front
		spot.Angle = 70
		spot.Range = 48
		spot.Brightness = 0
		spot.Shadows = true
		spot.Color = Color3.fromRGB(230, 245, 255)
		spot.Parent = head
		lamp = spot
		local point = Instance.new("PointLight")
		point.Name = "DiverGlow"
		point.Range = 16
		point.Brightness = 0
		point.Shadows = false
		point.Color = Color3.fromRGB(200, 230, 255)
		point.Parent = head
		glow = point
	end
	player.CharacterAdded:Connect(attachLamp)
	if player.Character then
		task.spawn(attachLamp, player.Character)
	end

	local surfaceLook: any = {}
	local function applyWorld(world: number)
		local data = Worlds.get(world)
		local sky = data.sky
		surfaceLook = {
			clock = sky.time,
			brightness = sky.bright,
			ambient = Color.hex(sky.ambient),
			outdoor = Color.hex(sky.outdoor),
			density = sky.density,
			haze = sky.haze,
			atmo = Color.hex(sky.atmo),
			decay = Color.hex(sky.decay),
			glare = sky.glare,
			water = Color.hex(data.water),
			tint = Color.hex(data.under.tint),
			dark = data.under.dark,
		}
		Lighting.ClockTime = sky.time
		terrain.WaterColor = surfaceLook.water
		local t = data.terrain
		for _, pair in
			{ { t.land, t.landColor }, { t.beach, t.beachColor }, { t.rock, t.rockColor }, { t.floor, t.floorColor }, { t.deep, t.deepColor } }
		do
			terrain:SetMaterialColor(Color.material(pair[1], Enum.Material.Sand), Color.hex(pair[2]))
		end
		if clouds then
			clouds.Cover = sky.clouds
			clouds.Color = Color.hex(sky.cloudColor)
		end
		local skyObject = Lighting:FindFirstChildOfClass("Sky")
		if skyObject then
			skyObject.StarCount = if data.sky.stars then 3000 else 0
			skyObject.CelestialBodiesShown = true
		end
		buildRays(world)
	end
	applyWorld(app.State.world)
	app.State.worldChanged:Connect(applyWorld)

	local blend = 0
	local wasUnder = false
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if not camera or not surfaceLook.water then
			return
		end
		local world = app.State.world
		local lowFx = app.State.settings().lowFx
		local position = camera.CFrame.Position
		local over = Layout.overLagoon(world, position)
		local camDepth = Config.SurfaceY - position.Y
		local under = over and camDepth > 0.25
		if under ~= wasUnder then
			wasUnder = under
			SoundService.AmbientReverb = if under then Enum.ReverbType.UnderWater else Enum.ReverbType.NoReverb
		end
		blend += ((if under then 1 else 0) - blend) * math.clamp(dt * 7, 0, 1)
		local depthRatio = if under then math.clamp(camDepth / Economy.depthStuds(world), 0, 1) else 0
		local look = surfaceLook
		local darkness = look.dark * depthRatio

		Lighting.Brightness = lerp(look.brightness, look.brightness * (1 - darkness * 0.8), blend)
		Lighting.Ambient = look.ambient:Lerp(look.water:Lerp(Color3.new(0, 0, 0), 0.35 + darkness * 0.5), blend * 0.85)
		Lighting.OutdoorAmbient = look.outdoor:Lerp(look.water:Lerp(Color3.new(0, 0, 0), 0.25 + darkness * 0.6), blend)
		Lighting.ExposureCompensation = lerp(0.1, -0.15 - darkness * 1.4, blend)
		atmosphere.Density = lerp(look.density, math.min(0.8, 0.46 + depthRatio * 0.3), blend)
		atmosphere.Haze = lerp(look.haze, 2.2 + darkness * 2, blend)
		atmosphere.Color = look.atmo:Lerp(look.water, blend)
		atmosphere.Decay = look.decay:Lerp(look.water:Lerp(Color3.new(0, 0, 0), 0.55 + darkness * 0.4), blend)
		atmosphere.Glare = lerp(look.glare, 0, blend)
		atmosphere.Offset = lerp(0.12, 0, blend)
		colorFx.TintColor = Color3.new(1, 1, 1):Lerp(look.tint, blend * 0.55)
		colorFx.Saturation = lerp(0.12, 0.22, blend)
		colorFx.Contrast = lerp(0.08, 0.14, blend)
		blur.Size = if lowFx then 0 else blend * (2 + depthRatio * 3)
		bloom.Intensity = lerp(0.6, 1.1, blend)
		sunRays.Intensity = lerp(0.06, 0, blend)

		plankton.CFrame = CFrame.new(position)
		motes.Rate = if under and not lowFx then 24 else 0
		motes.Color = ColorSequence.new(look.tint:Lerp(Color3.new(1, 1, 1), 0.5))
		for _, beam in rayBeams do
			beam.Enabled = not lowFx
		end

		local lampPower = math.clamp((look.dark * depthRatio - 0.12) / 0.4, 0, 1) * blend
		if lamp then
			lamp.Brightness = lampPower * 3.2
			lamp.Enabled = lampPower > 0.02
		end
		if glow then
			glow.Brightness = lampPower * 0.9
			glow.Enabled = lampPower > 0.02
		end
	end)
end

return Ambience
