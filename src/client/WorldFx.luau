--!strict
-- World-space effects: sparkle bursts, expanding shockwave rings and coin fountains. Everything
-- is anchored, non-colliding and cleaned up automatically.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local WorldFx = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local function folder(): Instance
	local existing = Workspace:FindFirstChild("DeepDiveClient")
	if existing then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "DeepDiveClient"
	created.Parent = Workspace
	return created
end

local function anchor(position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "Fx"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(position)
	part.Parent = folder()
	return part
end

local function emitter(parent: Instance, color: Color3, size: number, speed: NumberRange, lifetime: NumberRange): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color)
	e.LightEmission = 0.9
	e.LightInfluence = 0
	e.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(0.4, size * 0.8), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = lifetime
	e.Speed = speed
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Drag = 3
	e.Rate = 0
	e.Parent = parent
	return e
end

local function cleanup(instance: Instance, after: number)
	task.delay(after, function()
		instance:Destroy()
	end)
end

-- Star-sparkle burst, e.g. when a relic is collected.
function WorldFx.burst(position: Vector3, color: Color3, amount: number?, size: number?)
	local part = anchor(position)
	local s = size or 0.9
	emitter(part, color, s, NumberRange.new(6, 14), NumberRange.new(0.5, 0.9)):Emit(amount or 22)
	local glow = emitter(part, Color3.new(1, 1, 1), s * 2.6, NumberRange.new(0, 0.5), NumberRange.new(0.25, 0.35))
	glow.Drag = 0
	glow:Emit(2)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 3
	light.Parent = part
	TweenService:Create(light, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	cleanup(part, 1.2)
end

-- Flat neon ring that expands and fades.
function WorldFx.ring(position: Vector3, color: Color3, radius: number?, duration: number?)
	local ring = Instance.new("Part")
	ring.Name = "FxRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder()
	local r = (radius or 8) * 2
	local t = duration or 0.6
	TweenService:Create(ring, TweenInfo.new(t, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.1, r, r), Transparency = 1 })
		:Play()
	cleanup(ring, t + 0.1)
end

-- Gold coins that pop up out of a spot and rain back down (sell stand).
function WorldFx.coinFountain(position: Vector3, count: number?)
	local n = math.clamp(count or 12, 4, 24)
	for i = 1, n do
		task.delay(i * 0.03, function()
			local coin = Instance.new("Part")
			coin.Name = "FxCoin"
			coin.Shape = Enum.PartType.Cylinder
			coin.Anchored = true
			coin.CanCollide = false
			coin.CanQuery = false
			coin.CanTouch = false
			coin.CastShadow = false
			coin.Material = Enum.Material.Neon
			coin.Color = Color3.fromRGB(255, 210, 70)
			coin.Size = Vector3.new(0.25, 1.1, 1.1)
			local start = position + Vector3.new(math.random(-10, 10) / 10, 0.5, math.random(-10, 10) / 10)
			coin.CFrame = CFrame.new(start)
			coin.Parent = folder()
			local angle = math.random() * math.pi * 2
			local outward = Vector3.new(math.cos(angle), 0, math.sin(angle)) * (2 + math.random() * 3)
			local peak = start + outward * 0.5 + Vector3.new(0, 5 + math.random() * 3, 0)
			local land = start + outward + Vector3.new(0, -0.3, 0)
			local up = TweenService:Create(coin, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(peak) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			})
			up:Play()
			up.Completed:Wait()
			local down = TweenService:Create(coin, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = CFrame.new(land) * CFrame.Angles(0, 0, math.rad(90)),
				Transparency = 0.6,
			})
			down:Play()
			down.Completed:Wait()
			TweenService:Create(coin, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			cleanup(coin, 0.35)
		end)
	end
	WorldFx.burst(position + Vector3.new(0, 1.5, 0), Color3.fromRGB(255, 214, 90), 30, 1.1)
	WorldFx.ring(position + Vector3.new(0, 0.6, 0), Color3.fromRGB(255, 214, 90), 9)
end

return WorldFx
