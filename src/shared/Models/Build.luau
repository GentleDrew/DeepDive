--!strict
-- Primitive part helpers for the procedural models (pets, relics, eggs, decor). Parts are
-- anchored, non-colliding and non-queryable by default; callers opt into collision.

local Color = require(script.Parent.Parent.Color)

local Build = {}

export type Style = string?

local DEFAULTS = {
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
	Material = Enum.Material.SmoothPlastic,
	TopSurface = Enum.SurfaceType.Smooth,
	BottomSurface = Enum.SurfaceType.Smooth,
}

local function apply(part: BasePart, color: Color3, cf: CFrame, parent: Instance)
	for key, value in DEFAULTS do
		(part :: any)[key] = value
	end
	part.Color = color
	part.CFrame = cf
	part.Parent = parent
end

function Build.model(name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	apply(root, Color3.new(1, 1, 1), CFrame.identity, model)
	model.PrimaryPart = root
	return model
end

function Build.block(parent: Instance, size: Vector3, cf: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Size = size
	apply(part, color, cf, parent)
	return part
end

function Build.ball(parent: Instance, diameter: number, cf: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	apply(part, color, cf, parent)
	return part
end

-- Non-uniform sphere (SpecialMesh sphere stretched to the part size).
function Build.ellipsoid(parent: Instance, size: Vector3, cf: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Size = size
	apply(part, color, cf, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Cylinder whose axis runs along the CFrame's X axis.
function Build.cylinder(parent: Instance, length: number, diameter: number, cf: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(length, diameter, diameter)
	apply(part, color, cf, parent)
	return part
end

-- Cylinder standing upright (axis along Y) centred at `position`.
function Build.column(parent: Instance, height: number, diameter: number, cf: CFrame, color: Color3): Part
	return Build.cylinder(parent, height, diameter, cf * CFrame.Angles(0, 0, math.rad(90)), color)
end

function Build.wedge(parent: Instance, size: Vector3, cf: CFrame, color: Color3): WedgePart
	local part = Instance.new("WedgePart")
	part.Size = size
	apply(part, color, cf, parent)
	return part
end

function Build.cornerWedge(parent: Instance, size: Vector3, cf: CFrame, color: Color3): CornerWedgePart
	local part = Instance.new("CornerWedgePart")
	part.Size = size
	apply(part, color, cf, parent)
	return part
end

-- CFrame.lookAt that stays well defined when looking straight up/down or at the same point.
function Build.look(at: Vector3, target: Vector3): CFrame
	local direction = target - at
	if direction.Magnitude < 1e-5 then
		return CFrame.new(at)
	end
	local up = if math.abs(direction.Unit.Y) > 0.999 then Vector3.zAxis else Vector3.yAxis
	return CFrame.lookAt(at, target, up)
end

-- Tapered spike pointing along the CFrame's -Z (look) direction: two wedges back to back.
-- A WedgePart is tallest at +Z and thins to an edge at -Z, so no yaw is needed here.
function Build.spike(parent: Instance, length: number, width: number, cf: CFrame, color: Color3, accent: boolean?)
	local half = width / 2
	local upper = Build.wedge(parent, Vector3.new(width, half, length), cf * CFrame.new(0, half / 2, 0), color)
	local lower = Build.wedge(parent, Vector3.new(width, half, length), cf * CFrame.new(0, -half / 2, 0) * CFrame.Angles(0, 0, math.pi), color)
	if accent then
		upper:SetAttribute("Accent", true)
		lower:SetAttribute("Accent", true)
	end
	return upper, lower
end

-- Cute cartoon eye: white ball, dark pupil, tiny shine. `cf` looks outward from the face.
function Build.eye(parent: Instance, size: number, cf: CFrame, pupilColor: Color3?)
	local white = Build.ball(parent, size, cf, Color3.new(1, 1, 1))
	local pupil = Build.ball(parent, size * 0.62, cf * CFrame.new(0, 0, -size * 0.24), pupilColor or Color3.fromRGB(28, 28, 36))
	local shine = Build.ball(parent, size * 0.22, cf * CFrame.new(size * 0.14, size * 0.16, -size * 0.46), Color3.new(1, 1, 1))
	shine.Material = Enum.Material.Neon
	for _, part in { white, pupil, shine } do
		part:SetAttribute("Eye", true)
	end
end

-- Pair of eyes on a face whose front is -Z. `x` is half spacing, `y` height, `z` depth.
function Build.eyes(parent: Instance, base: CFrame, x: number, y: number, z: number, size: number, outward: number?)
	local turn = math.rad(outward or 18)
	Build.eye(parent, size, base * CFrame.new(-x, y, z) * CFrame.Angles(0, turn, 0))
	Build.eye(parent, size, base * CFrame.new(x, y, z) * CFrame.Angles(0, -turn, 0))
end

function Build.light(parent: BasePart, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
	return light
end

function Build.sparkles(parent: BasePart, color: Color3, rate: number?): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Rate = rate or 6
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = parent
	return emitter
end

-- Applies a visual style to a finished model. Parts named with the "Accent" attribute are the
-- highlight parts (fins, spots, gems); everything else is the body.
function Build.style(model: Model, style: Style, accent: Color3)
	if not style then
		return
	end
	local index = 0
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Root" and part.Transparency < 1 then
			index += 1
			local isAccent = part:GetAttribute("Accent") == true
			local isEye = part:GetAttribute("Eye") == true
			if style == "neon" then
				if isAccent then
					part.Material = Enum.Material.Neon
				end
			elseif style == "glass" then
				if not isEye then
					part.Material = Enum.Material.Glass
					part.Transparency = math.max(part.Transparency, 0.3)
				end
			elseif style == "ghost" then
				if not isEye then
					part.Material = if isAccent then Enum.Material.Neon else Enum.Material.ForceField
				end
			elseif style == "gold" then
				if not isEye then
					part.Material = if isAccent then Enum.Material.Neon else Enum.Material.Metal
					part.Reflectance = if isAccent then 0 else 0.18
				end
			elseif style == "rainbow" then
				if not isEye then
					part.Color = Color.Rainbow[(index % #Color.Rainbow) + 1]
					if isAccent then
						part.Material = Enum.Material.Neon
					end
				end
			elseif style == "cosmic" then
				if not isEye then
					part.Material = if isAccent then Enum.Material.Neon else Enum.Material.ForceField
				end
			end
		end
	end
	local root = model.PrimaryPart
	if root and (style == "neon" or style == "rainbow" or style == "cosmic" or style == "gold" or style == "ghost") then
		Build.light(root, accent, 8, 1.2)
	end
	if root and (style == "cosmic" or style == "rainbow" or style == "gold") then
		Build.sparkles(root, accent, if style == "cosmic" then 10 else 4)
	end
end

function Build.markAccent(part: BasePart): BasePart
	part:SetAttribute("Accent", true)
	return part
end

-- Scales a finished model so its largest extent equals `size` studs.
function Build.fit(model: Model, size: number)
	local _, extents = model:GetBoundingBox()
	local largest = math.max(extents.X, extents.Y, extents.Z)
	if largest > 0 then
		model:ScaleTo(model:GetScale() * size / largest)
	end
end

return Build
