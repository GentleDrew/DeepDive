--!strict
-- Themed decoration kits placed procedurally on each island and inside its lagoon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Build = require(Shared.Models.Build)
local Color = require(Shared.Color)
local Layout = require(Shared.Layout)
local RelicModels = require(Shared.Models.RelicModels)
local Worlds = require(Shared.Data.Worlds)

local Decor = {}

local V = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rad = math.rad

export type Pal = {
	a1: Color3,
	a2: Color3,
	corals: { Color3 },
	rock: Color3,
	land: Color3,
	sand: Color3,
	leaf: Color3,
	wood: Color3,
	bone: Color3,
	glow: boolean,
}

export type Ctx = {
	parent: Instance,
	rng: Random,
	pal: Pal,
	world: number,
	info: Layout.Info,
	lights: number,
	maxLights: number,
}

local MAX_LIGHTS = 26

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function vary(rng: Random, color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(
		(h + rng:NextNumber(-amount, amount) * 0.1) % 1,
		math.clamp(s + rng:NextNumber(-amount, amount), 0, 1),
		math.clamp(v + rng:NextNumber(-amount, amount), 0, 1)
	)
end

local function addLight(ctx: Ctx, part: BasePart, color: Color3, range: number, brightness: number)
	if ctx.lights >= ctx.maxLights then
		return
	end
	ctx.lights += 1
	Build.light(part, color, range, brightness)
end

local function solid(part: BasePart): BasePart
	part.CanCollide = true
	part.CanQuery = true
	return part
end

local function group(ctx: Ctx, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = ctx.parent
	return model
end

-- Square pyramid out of four wedges (tall faces meet in the middle).
local function pyramid(parent: Instance, base: CFrame, width: number, height: number, color: Color3, material: Enum.Material?)
	for k = 0, 3 do
		local wedge = Build.wedge(parent, V(width, height, width / 2), base * ang(0, k * math.pi / 2, 0) * cf(0, height / 2, -width / 4), color)
		if material then
			wedge.Material = material
		end
	end
end

local function fire(part: BasePart, color: Color3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.fromRGB(255, 80, 40))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.1) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Rate = 18
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Parent = part
end

local function smoke(part: BasePart, color: Color3, bubbles: boolean)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = if bubbles then "rbxasset://textures/particles/sparkles_main.dds" else "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = if bubbles then 0.6 else 0.1
	emitter.Size = if bubbles
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.6) })
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(2.5, 4)
	emitter.Rate = if bubbles then 10 else 5
	emitter.Speed = NumberRange.new(4, 7)
	emitter.SpreadAngle = Vector2.new(10, 10)
	emitter.Parent = part
end

-- Swaying plants pivot around their base so the client can rock them without sliding.
local function tagSway(model: Model, strength: number, base: CFrame)
	model.WorldPivot = base
	model:SetAttribute("Sway", strength)
end

-- Elements -------------------------------------------------------------------------------------

local E: { [string]: (Ctx, CFrame) -> () } = {}

E.palm = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Palm")
	local height = rng:NextNumber(14, 20)
	local lean = rng:NextNumber(-14, 14)
	local trunk = Color3.fromRGB(150, 108, 68)
	local frame = at * ang(0, rng:NextNumber(0, math.pi * 2), 0)
	local segments = 5
	for i = 1, segments do
		local segH = height / segments
		frame = frame * ang(rad(lean / segments), 0, 0)
		Build.column(m, segH + 0.3, 1.35 - i * 0.12, frame * cf(0, segH / 2, 0), if i % 2 == 0 then trunk else Color.darken(trunk, 0.12))
		frame = frame * cf(0, segH, 0)
	end
	for i = 1, 7 do
		local yaw = i / 7 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local base = frame * ang(0, yaw, 0) * ang(rad(-18), 0, 0)
		local leaf = vary(rng, ctx.pal.leaf, 0.08)
		Build.block(m, V(1.8, 0.2, 4.2), base * cf(0, 0, -2.1), leaf)
		Build.block(m, V(1.4, 0.2, 3.4), base * cf(0, 0, -4) * ang(rad(-40), 0, 0) * cf(0, 0, -1.6), Color.darken(leaf, 0.1))
	end
	for i = 1, 3 do
		Build.ball(m, 0.9, frame * ang(0, i * 2.1, 0) * cf(0.6, -0.7, 0), Color3.fromRGB(110, 70, 40))
	end
end

E.pine = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Pine")
	local scale = rng:NextNumber(0.8, 1.3)
	local green = vary(rng, Color3.fromRGB(46, 110, 78), 0.05)
	Build.column(m, 3 * scale, 1.2 * scale, at * cf(0, 1.5 * scale, 0), Color3.fromRGB(96, 66, 44))
	local y = 2.5 * scale
	for tier = 1, 3 do
		local w = (10 - tier * 2.4) * scale
		local h = (5.5 - tier * 0.6) * scale
		pyramid(m, at * cf(0, y, 0), w, h, green)
		if Worlds.get(ctx.world).kit == "ice" then
			pyramid(m, at * cf(0, y + h * 0.55, 0), w * 0.5, h * 0.45, Color3.fromRGB(244, 250, 255))
		end
		y += h * 0.62
	end
end

E.deadTree = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "DeadTree")
	local color = Color.darken(ctx.pal.rock, 0.3)
	local height = rng:NextNumber(8, 13)
	local frame = at * ang(0, rng:NextNumber(0, 6.28), 0)
	Build.column(m, height, 1.1, frame * cf(0, height / 2, 0), color)
	for i = 1, 4 do
		local y = height * (0.45 + i * 0.12)
		local branch = frame * cf(0, y, 0) * ang(0, i * 1.7, 0) * ang(rad(55), 0, 0)
		Build.column(m, 4 - i * 0.5, 0.45, branch * cf(0, (4 - i * 0.5) / 2, 0), color)
	end
end

E.rock = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Rock")
	local size = rng:NextNumber(2.5, 6)
	local color = vary(rng, ctx.pal.rock, 0.06)
	for i = 1, rng:NextInteger(2, 3) do
		local s = size * rng:NextNumber(0.6, 1)
		local part = Build.ellipsoid(
			m,
			V(s * 1.3, s * 0.8, s),
			at
				* cf(rng:NextNumber(-1, 1) * size * 0.4, s * 0.25, rng:NextNumber(-1, 1) * size * 0.4)
				* ang(0, rng:NextNumber(0, 6), rng:NextNumber(-0.3, 0.3)),
			color
		)
		part.Material = Enum.Material.Slate
		if i == 1 and size > 4 then
			solid(part)
		end
	end
end

E.umbrella = function(ctx, at)
	local m = group(ctx, "Umbrella")
	Build.column(m, 7, 0.3, at * cf(0, 3.5, 0) * ang(rad(8), 0, 0), Color3.fromRGB(240, 240, 240))
	local top = at * cf(0.4, 7, -0.4)
	for k = 0, 7 do
		local color = if k % 2 == 0 then ctx.pal.a1 else Color3.fromRGB(255, 255, 255)
		Build.wedge(m, V(3.4, 1.2, 4), top * ang(0, k * math.pi / 4, 0) * cf(0, -0.6, -2), color)
	end
	Build.block(m, V(3, 0.1, 5.5), at * cf(3, 0.05, 1) * ang(0, rad(20), 0), ctx.pal.a2)
end

E.torch = function(ctx, at)
	local m = group(ctx, "Torch")
	Build.column(m, 5, 0.35, at * cf(0, 2.5, 0), Color3.fromRGB(120, 80, 50))
	Build.column(m, 0.8, 1.0, at * cf(0, 5.2, 0), Color3.fromRGB(80, 60, 45))
	local flame = Build.ball(m, 0.9, at * cf(0, 5.9, 0), Color3.fromRGB(255, 170, 60))
	flame.Material = Enum.Material.Neon
	fire(flame, Color3.fromRGB(255, 200, 80))
	addLight(ctx, flame, Color3.fromRGB(255, 170, 90), 16, 1.6)
end

E.lantern = function(ctx, at)
	local m = group(ctx, "Lantern")
	local glow = if ctx.pal.glow then ctx.pal.corals[1] else Color3.fromRGB(255, 200, 110)
	Build.column(m, 6, 0.3, at * cf(0, 3, 0), Color3.fromRGB(60, 56, 64))
	Build.block(m, V(1.2, 0.2, 1.2), at * cf(0, 6, 0), Color3.fromRGB(60, 56, 64))
	local core = Build.block(m, V(0.8, 1.1, 0.8), at * cf(0, 5.35, 0), glow)
	core.Material = Enum.Material.Neon
	addLight(ctx, core, glow, 14, 1.4)
end

E.seagrass = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Seagrass")
	for _ = 1, rng:NextInteger(5, 8) do
		local h = rng:NextNumber(2, 5)
		local color = vary(rng, ctx.pal.leaf, 0.1)
		local base = at
			* cf(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2))
			* ang(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6), rng:NextNumber(-0.25, 0.25))
		Build.block(m, V(0.5, h, 0.18), base * cf(0, h / 2, 0), color)
	end
	tagSway(m, 0.12, at)
end

E.kelp = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Kelp")
	local depth = -at.Position.Y
	local height = math.clamp(depth - rng:NextNumber(3, 8), 6, 42)
	local stalk = Color3.fromRGB(120, 110, 40)
	local leaf = vary(rng, Color3.fromRGB(96, 150, 54), 0.08)
	local segments = math.max(2, math.floor(height / 4))
	local frame = at
	for i = 1, segments do
		local segH = height / segments
		frame = frame * ang(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.06, 0.06))
		Build.column(m, segH + 0.2, 0.35, frame * cf(0, segH / 2, 0), stalk)
		local side = if i % 2 == 0 then 1 else -1
		Build.ellipsoid(m, V(2.4, 0.18, 0.9), frame * cf(side * 1.2, segH * 0.6, 0) * ang(0, 0, rad(side * 25)), leaf)
		frame = frame * cf(0, segH, 0)
	end
	local bulb = Build.ball(m, 0.9, frame, Color3.fromRGB(150, 140, 60))
	bulb.Name = "Bulb"
	tagSway(m, 0.25, at)
end

E.coral = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Coral")
	local color = vary(rng, pick(rng, ctx.pal.corals), 0.06)
	local tip = Color.lighten(color, 0.35)
	local kind = rng:NextInteger(1, 5)
	local neon = ctx.pal.glow
	local function finish(part: BasePart)
		if neon then
			part.Material = Enum.Material.Neon
		end
	end
	if kind == 1 then
		local size = rng:NextNumber(2.2, 4)
		Build.ball(m, size, at * cf(0, size * 0.35, 0), color)
		for i = 0, 4 do
			finish(Build.ellipsoid(m, V(size * 1.02, 0.14, size * 0.2), at * cf(0, size * 0.35, 0) * ang(rad(i * 36), rad(i * 50), 0), tip))
		end
	elseif kind == 2 then
		local frame = at * ang(0, rng:NextNumber(0, 6), 0)
		Build.column(m, 1.4, 0.6, frame * cf(0, 0.7, 0), color)
		for i = 1, 5 do
			local branch = frame * cf(0, 1.1, 0) * ang(0, i * 1.26, 0) * ang(rad(rng:NextNumber(18, 45)), 0, 0)
			local len = rng:NextNumber(1.6, 3)
			Build.column(m, len, 0.42, branch * cf(0, len / 2, 0), color)
			finish(Build.ball(m, 0.55, branch * cf(0, len, 0), tip))
		end
	elseif kind == 3 then
		local fan =
			Build.ellipsoid(m, V(rng:NextNumber(3, 5), rng:NextNumber(3, 4.5), 0.18), at * cf(0, 2, 0) * ang(0, rng:NextNumber(0, 6), 0), color)
		fan.Transparency = 0.1
		for i = -2, 2 do
			finish(Build.block(m, V(0.12, 3, 0.22), fan.CFrame * ang(0, 0, rad(i * 18)) * cf(0, -0.3, 0), tip))
		end
	elseif kind == 4 then
		for _ = 1, rng:NextInteger(3, 5) do
			local h = rng:NextNumber(1.5, 3.5)
			local offset = cf(rng:NextNumber(-0.9, 0.9), 0, rng:NextNumber(-0.9, 0.9))
			Build.column(m, h, 0.8, at * offset * cf(0, h / 2, 0), color)
			finish(Build.column(m, 0.12, 0.62, at * offset * cf(0, h + 0.02, 0), Color.darken(color, 0.4)))
		end
	else
		Build.column(m, 1, 1.4, at * cf(0, 0.5, 0), color)
		for i = 1, 12 do
			local a = i / 12 * math.pi * 2
			finish(
				Build.ellipsoid(
					m,
					V(0.24, 1.3, 0.24),
					at * cf(math.cos(a) * 0.45, 1.4, math.sin(a) * 0.45) * ang(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5),
					tip
				)
			)
		end
	end
	if neon and rng:NextNumber() < 0.35 then
		local root = m:FindFirstChildWhichIsA("BasePart")
		if root then
			addLight(ctx, root, tip, 10, 1.2)
		end
	end
end

E.anemone = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Anemone")
	local color = vary(rng, pick(rng, ctx.pal.corals), 0.05)
	Build.column(m, 1.2, 1.6, at * cf(0, 0.6, 0), Color.darken(color, 0.2))
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		local r = if i % 2 == 0 then 0.6 else 0.3
		Build.ellipsoid(
			m,
			V(0.22, 1.1, 0.22),
			at * cf(math.cos(a) * r, 1.6, math.sin(a) * r) * ang(math.sin(a) * 0.4, 0, -math.cos(a) * 0.4),
			Color.lighten(color, 0.3)
		)
	end
	tagSway(m, 0.08, at)
end

E.shell = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Shell")
	local model = Build.model("S")
	RelicModels.Shapes.shell(model, pick(rng, ctx.pal.corals), Color3.fromRGB(255, 240, 230))
	Build.fit(model, rng:NextNumber(1.6, 2.6))
	model:PivotTo(at * cf(0, 0.4, 0) * ang(rad(-70), rng:NextNumber(0, 6), 0))
	model.Parent = m
end

E.starfish = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Starfish")
	local model = Build.model("S")
	RelicModels.Shapes.starfish(model, pick(rng, ctx.pal.corals), Color3.fromRGB(255, 230, 200))
	Build.fit(model, rng:NextNumber(1.4, 2.2))
	model:PivotTo(at * cf(0, 0.2, 0) * ang(rad(-90), rng:NextNumber(0, 6), 0))
	model.Parent = m
end

E.barrel = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Barrel")
	local tilt = if rng:NextNumber() < 0.4 then ang(rad(90), rng:NextNumber(0, 6), 0) * cf(0, 0, 0) else ang(0, rng:NextNumber(0, 6), 0)
	local frame = at * cf(0, 1.1, 0) * tilt
	local body = Build.column(m, 2.2, 1.8, frame, ctx.pal.wood)
	body.Material = Enum.Material.WoodPlanks
	for _, y in { -0.7, 0.7 } do
		Build.column(m, 0.2, 1.88, frame * cf(0, y, 0), Color3.fromRGB(70, 66, 70))
	end
end

E.crate = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Crate")
	local size = rng:NextNumber(2, 2.8)
	local frame = at * cf(0, size / 2, 0) * ang(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 6), rng:NextNumber(-0.2, 0.2))
	local box = Build.block(m, V(size, size, size), frame, ctx.pal.wood)
	box.Material = Enum.Material.WoodPlanks
	for _, y in { -0.35, 0.35 } do
		Build.block(m, V(size + 0.1, 0.25, size + 0.1), frame * cf(0, size * y, 0), Color.darken(ctx.pal.wood, 0.3))
	end
end

E.cannon = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Cannon")
	local frame = at * ang(0, rng:NextNumber(0, 6), 0)
	local barrel = Build.cylinder(m, 4, 1.1, frame * cf(0, 1.2, 0) * ang(0, 0, rad(12)), Color3.fromRGB(58, 58, 64))
	barrel.Material = Enum.Material.Metal
	Build.block(m, V(3, 0.8, 1.6), frame * cf(0, 0.4, 0), ctx.pal.wood)
	for _, z in { -0.9, 0.9 } do
		Build.cylinder(m, 0.3, 1.2, frame * cf(0, 0.6, z) * ang(0, rad(90), 0), Color.darken(ctx.pal.wood, 0.3))
	end
end

E.anchor = function(ctx, at)
	local m = group(ctx, "Anchor")
	local frame = at * ang(rad(70), ctx.rng:NextNumber(0, 6), 0)
	local color = Color3.fromRGB(70, 70, 78)
	Build.column(m, 6, 0.6, frame * cf(0, 3, 0), color)
	Build.block(m, V(3.4, 0.5, 0.5), frame * cf(0, 5.2, 0), color)
	for _, side in { -1, 1 } do
		Build.column(m, 2.4, 0.5, frame * cf(side * 1.1, 0.8, 0) * ang(0, 0, rad(side * 50)), color)
		Build.spike(m, 1.2, 0.6, frame * cf(side * 1.9, 1.7, 0) * ang(rad(90), 0, 0), color)
	end
end

E.hull = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Shipwreck")
	local frame = at * ang(0, rng:NextNumber(0, 6), rad(rng:NextNumber(-14, 14)))
	local wood = ctx.pal.wood
	local dark = Color.darken(wood, 0.3)
	local length = 26
	local keel = Build.block(m, V(1.2, 1.2, length), frame * cf(0, 0.6, 0), dark)
	solid(keel)
	for _, side in { -1, 1 } do
		local bottom = Build.block(m, V(4.5, 0.6, length - 2), frame * cf(side * 2.3, 1.1, 0) * ang(0, 0, rad(side * -18)), wood)
		bottom.Material = Enum.Material.WoodPlanks
		solid(bottom)
		local wallLength = if side == 1 then length - 4 else length * 0.55
		local wall = Build.block(
			m,
			V(0.6, 5, wallLength),
			frame * cf(side * 4.4, 3.6, if side == 1 then 0 else -length * 0.2) * ang(0, 0, rad(side * -8)),
			wood
		)
		wall.Material = Enum.Material.WoodPlanks
		solid(wall)
	end
	for i = -2, 2 do
		for _, side in { -1, 1 } do
			Build.column(m, 6, 0.5, frame * cf(side * 3.4, 3.2, i * 4.5) * ang(0, 0, rad(side * -25)), dark)
		end
	end
	local deck = Build.block(m, V(8, 0.5, 8), frame * cf(0, 5.6, 7) * ang(rad(-6), 0, 0), wood)
	deck.Material = Enum.Material.WoodPlanks
	solid(deck)
	local mast = Build.column(m, 16, 1.1, frame * cf(0, 9, -3) * ang(rad(28), 0, rad(10)), wood)
	solid(mast)
	Build.column(m, 8, 0.5, frame * cf(0, 14, -7.5) * ang(rad(28), 0, rad(10)) * ang(0, 0, rad(90)), wood)
	local sail = Build.block(m, V(7, 5, 0.12), frame * cf(0.5, 12, -6) * ang(rad(28), 0, rad(14)), Color3.fromRGB(230, 222, 200))
	sail.Transparency = 0.15
	for i = 1, 3 do
		E.barrel(ctx, frame * cf(rng:NextNumber(-2, 2), 1.4, -8 + i * 4))
	end
end

E.pillar = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Pillar")
	local kit = Worlds.get(ctx.world).kit
	local stone = if kit == "atlantis" then Color3.fromRGB(236, 242, 248) else Color3.fromRGB(222, 196, 140)
	local material = if kit == "atlantis" then Enum.Material.Marble else Enum.Material.Sandstone
	local broken = rng:NextNumber() < 0.45
	local height = if broken then rng:NextNumber(4, 8) else rng:NextNumber(10, 14)
	local frame = at * ang(rng:NextNumber(-0.05, 0.05), rng:NextNumber(0, 6), rng:NextNumber(-0.05, 0.05))
	local base = Build.block(m, V(3.4, 1, 3.4), frame * cf(0, 0.5, 0), stone)
	base.Material = material
	local shaft = Build.column(m, height, 2.4, frame * cf(0, 1 + height / 2, 0), stone)
	shaft.Material = material
	solid(shaft)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		Build.block(m, V(0.25, height, 0.25), frame * cf(math.cos(a) * 1.15, 1 + height / 2, math.sin(a) * 1.15), Color.darken(stone, 0.12))
	end
	if broken then
		local piece = Build.column(m, 5, 2.4, frame * cf(4.5, 1.2, 1) * ang(0, rad(30), rad(90)), stone)
		piece.Material = material
	else
		local capital = Build.block(m, V(3.6, 1, 3.6), frame * cf(0, 1.5 + height, 0), stone)
		capital.Material = material
	end
	if kit == "atlantis" then
		local ring = Build.column(m, 0.4, 2.6, frame * cf(0, 1 + height * 0.6, 0), ctx.pal.a1)
		ring.Material = Enum.Material.Neon
	end
end

E.arch = function(ctx, at)
	local m = group(ctx, "Arch")
	local kit = Worlds.get(ctx.world).kit
	local stone = if kit == "atlantis" then Color3.fromRGB(236, 242, 248) else Color3.fromRGB(222, 196, 140)
	local frame = at * ang(0, ctx.rng:NextNumber(0, 6), 0)
	for _, side in { -1, 1 } do
		local leg = Build.block(m, V(3, 16, 3), frame * cf(side * 7, 8, 0), stone)
		leg.Material = Enum.Material.Sandstone
		solid(leg)
	end
	local top = Build.block(m, V(18, 3, 3.6), frame * cf(0, 17.5, 0), stone)
	top.Material = Enum.Material.Sandstone
	solid(top)
	local gem = Build.ball(m, 2, frame * cf(0, 17.5, -1.9), ctx.pal.a1)
	gem.Material = Enum.Material.Neon
	addLight(ctx, gem, ctx.pal.a1, 24, 2)
end

E.statue = function(ctx, at)
	local m = group(ctx, "Statue")
	local stone = Color3.fromRGB(150, 140, 128)
	local frame = at * ang(rad(ctx.rng:NextNumber(-8, 8)), ctx.rng:NextNumber(0, 6), 0)
	local head = Build.block(m, V(5, 8, 4.5), frame * cf(0, 3.5, 0), stone)
	head.Material = Enum.Material.Slate
	solid(head)
	Build.block(m, V(5.4, 1.2, 1.5), frame * cf(0, 5.5, -2.2), Color.darken(stone, 0.15))
	Build.block(m, V(1.2, 3, 1.6), frame * cf(0, 3.5, -2.6), Color.darken(stone, 0.1))
	for _, side in { -1, 1 } do
		local eye = Build.block(m, V(1.2, 0.7, 0.4), frame * cf(side * 1.3, 4.7, -2.3), ctx.pal.a1)
		eye.Material = Enum.Material.Neon
	end
end

E.rune = function(ctx, at)
	local m = group(ctx, "Rune")
	local frame = at * ang(rad(ctx.rng:NextNumber(-10, 10)), ctx.rng:NextNumber(0, 6), 0)
	local slab = Build.block(m, V(3.5, 5, 0.8), frame * cf(0, 2.5, 0), Color3.fromRGB(90, 96, 110))
	slab.Material = Enum.Material.Slate
	for i = 0, 2 do
		local line = Build.block(m, V(2.2 - i * 0.4, 0.25, 0.1), frame * cf(0, 3.8 - i * 1.1, -0.42), ctx.pal.a1)
		line.Material = Enum.Material.Neon
	end
	local dot = Build.ball(m, 0.6, frame * cf(0, 1.1, -0.42), ctx.pal.a1)
	dot.Material = Enum.Material.Neon
	addLight(ctx, dot, ctx.pal.a1, 10, 1)
end

E.dome = function(ctx, at)
	local m = group(ctx, "Dome")
	local stone = Color3.fromRGB(236, 242, 248)
	local shell = Build.ellipsoid(m, V(16, 10, 16), at * cf(0, 6, 0), stone)
	shell.Material = Enum.Material.Marble
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local pillar = Build.column(m, 7, 1.4, at * cf(math.cos(a) * 7.2, 3.5, math.sin(a) * 7.2), stone)
		pillar.Material = Enum.Material.Marble
		solid(pillar)
	end
	local top = Build.ball(m, 2.2, at * cf(0, 11.4, 0), ctx.pal.a1)
	top.Material = Enum.Material.Neon
	addLight(ctx, top, ctx.pal.a1, 26, 2)
end

E.iceSpike = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "IceSpike")
	local height = rng:NextNumber(4, 11)
	local width = height * 0.32
	local frame = at * ang(rng:NextNumber(-0.2, 0.2), rng:NextNumber(0, 6), rng:NextNumber(-0.2, 0.2))
	local a, b = Build.spike(m, height, width, frame * cf(0, height / 2, 0) * ang(rad(90), 0, 0), Color3.fromRGB(200, 236, 255))
	for _, part in { a, b } do
		part.Material = Enum.Material.Ice
		part.Transparency = 0.15
	end
end

E.iceberg = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Iceberg")
	for i = 1, 4 do
		local size = V(rng:NextNumber(6, 12), rng:NextNumber(6, 14), rng:NextNumber(6, 12))
		local part = Build.block(
			m,
			size,
			at
				* cf(rng:NextNumber(-4, 4), size.Y * 0.3 + i, rng:NextNumber(-4, 4))
				* ang(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)),
			Color3.fromRGB(226, 244, 255)
		)
		part.Material = Enum.Material.Glacier
		solid(part)
	end
end

E.crystal = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Crystal")
	local color = vary(rng, if Worlds.get(ctx.world).kit == "ice" then Color3.fromRGB(170, 225, 255) else ctx.pal.a1, 0.06)
	local scale = rng:NextNumber(1, 2.4)
	for i = 1, rng:NextInteger(3, 6) do
		local height = rng:NextNumber(2, 5) * scale
		local w = 0.9 * scale
		local frame = at
			* cf(rng:NextNumber(-1, 1) * scale, 0, rng:NextNumber(-1, 1) * scale)
			* ang(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0, 6), rng:NextNumber(-0.45, 0.45))
		local shaft = Build.block(m, V(w, height, w), frame * cf(0, height / 2, 0), color)
		shaft.Material = if i == 1 then Enum.Material.Neon else Enum.Material.Glass
		shaft.Transparency = if i == 1 then 0 else 0.2
		local a, b = Build.spike(m, w * 1.1, w, frame * cf(0, height + w * 0.55, 0) * ang(rad(90), 0, 0), color)
		a.Material = Enum.Material.Glass
		b.Material = Enum.Material.Glass
	end
	local core = m:FindFirstChildWhichIsA("BasePart")
	if core then
		addLight(ctx, core, color, 12 * scale, 1.3)
	end
end

E.basalt = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Basalt")
	for _ = 1, rng:NextInteger(3, 6) do
		local h = rng:NextNumber(2, 7)
		local col =
			Build.column(m, h, rng:NextNumber(1.6, 2.4), at * cf(rng:NextNumber(-2, 2), h / 2, rng:NextNumber(-2, 2)), Color3.fromRGB(46, 42, 44))
		col.Material = Enum.Material.Basalt
		solid(col)
	end
end

E.lava = function(ctx, at)
	local m = group(ctx, "Lava")
	local r = ctx.rng:NextNumber(3, 6)
	local pool = Build.column(m, 0.3, r * 2, at * cf(0, 0.15, 0), Color3.fromRGB(255, 110, 30))
	pool.Material = Enum.Material.Neon
	local rim = Build.column(m, 0.5, r * 2 + 1.2, at * cf(0, 0.05, 0), Color3.fromRGB(40, 32, 30))
	rim.Material = Enum.Material.Basalt
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.25)
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Rate = 6
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Parent = pool
	addLight(ctx, pool, Color3.fromRGB(255, 120, 40), 18, 2.2)
end

E.vent = function(ctx, at)
	local m = group(ctx, "Vent")
	local color = Color3.fromRGB(58, 50, 50)
	for i = 0, 2 do
		local c = Build.column(m, 1.6, 3 - i * 0.7, at * cf(0, 0.8 + i * 1.5, 0), color)
		c.Material = Enum.Material.Basalt
	end
	local mouth = Build.column(m, 0.2, 1.2, at * cf(0, 4.4, 0), Color3.fromRGB(255, 120, 50))
	mouth.Material = Enum.Material.Neon
	smoke(mouth, Color3.fromRGB(230, 230, 240), -at.Position.Y > 1)
end

E.tubeWorms = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "TubeWorms")
	for _ = 1, rng:NextInteger(5, 9) do
		local h = rng:NextNumber(1.5, 4)
		local offset = cf(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2)) * ang(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2))
		Build.column(m, h, 0.35, at * offset * cf(0, h / 2, 0), Color3.fromRGB(235, 232, 225))
		local tip = Build.ball(m, 0.5, at * offset * cf(0, h, 0), Color3.fromRGB(255, 60, 70))
		tip.Material = Enum.Material.Neon
	end
	tagSway(m, 0.06, at)
end

E.glowPlant = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "GlowPlant")
	local color = pick(rng, ctx.pal.corals)
	local h = rng:NextNumber(2, 5)
	local frame = at * ang(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25))
	Build.column(m, h, 0.3, frame * cf(0, h / 2, 0), Color.darken(color, 0.5))
	local bulb = Build.ellipsoid(m, V(1.1, 1.4, 1.1), frame * cf(0, h + 0.5, 0), color)
	bulb.Material = Enum.Material.Neon
	for i = 1, 3 do
		Build.ellipsoid(m, V(1.4, 0.15, 0.5), frame * cf(0, h * 0.4, 0) * ang(0, i * 2.1, rad(-25)) * cf(0.6, 0, 0), Color.darken(color, 0.3))
	end
	if rng:NextNumber() < 0.5 then
		addLight(ctx, bulb, color, 10, 1.2)
	end
	tagSway(m, 0.1, at)
end

E.mushroom = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Mushroom")
	local color = pick(rng, ctx.pal.corals)
	local h = rng:NextNumber(3, 7)
	Build.column(m, h, 0.9, at * cf(0, h / 2, 0), Color3.fromRGB(230, 225, 240))
	local cap = Build.ellipsoid(m, V(h * 1.1, h * 0.45, h * 1.1), at * cf(0, h, 0), color)
	cap.Material = Enum.Material.Neon
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		Build.ball(m, 0.6, at * cf(math.cos(a) * h * 0.3, h + h * 0.18, math.sin(a) * h * 0.3), Color3.fromRGB(255, 255, 255))
	end
	addLight(ctx, cap, color, 14, 1.4)
end

E.spire = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Spire")
	local color = Color.darken(ctx.pal.rock, 0.2)
	local glow = pick(rng, ctx.pal.corals)
	local height = rng:NextNumber(6, 16)
	local steps = math.floor(height / 2)
	local frame = at
	for i = 1, steps do
		local w = 3 * (1 - i / (steps + 1)) + 0.4
		local seg = Build.block(m, V(w, 2.2, w), frame * cf(0, 1.1, 0), color)
		seg.Material = Enum.Material.Slate
		if i == 1 then
			solid(seg)
		end
		if i % 3 == 0 then
			local ring = Build.block(m, V(w + 0.3, 0.25, w + 0.3), frame * cf(0, 1.9, 0), glow)
			ring.Material = Enum.Material.Neon
		end
		frame = frame * cf(0, 2, 0) * ang(0, rad(22), rng:NextNumber(-0.06, 0.06))
	end
	local tip = Build.ball(m, 0.9, frame * cf(0, 0.6, 0), glow)
	tip.Material = Enum.Material.Neon
	addLight(ctx, tip, glow, 12, 1.2)
end

E.bones = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Bones")
	for _ = 1, rng:NextInteger(2, 4) do
		local frame = at * cf(rng:NextNumber(-1.5, 1.5), 0.3, rng:NextNumber(-1.5, 1.5)) * ang(0, rng:NextNumber(0, 6), rad(90))
		Build.column(m, 2.4, 0.35, frame, ctx.pal.bone)
		for _, y in { -1.25, 1.25 } do
			Build.ball(m, 0.6, frame * cf(0, y, 0.18), ctx.pal.bone)
			Build.ball(m, 0.6, frame * cf(0, y, -0.18), ctx.pal.bone)
		end
	end
end

E.skull = function(ctx, at)
	local m = group(ctx, "Skull")
	local model = Build.model("S")
	RelicModels.Shapes.skull(model, ctx.pal.bone, Color3.fromRGB(30, 26, 30))
	Build.fit(model, ctx.rng:NextNumber(3, 5))
	model:PivotTo(at * cf(0, 1.4, 0) * ang(0, ctx.rng:NextNumber(0, 6), 0))
	model.Parent = m
end

E.lollipop = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Lollipop")
	local h = rng:NextNumber(6, 11)
	Build.column(m, h, 0.5, at * cf(0, h / 2, 0), Color3.fromRGB(255, 255, 255))
	local frame = at * cf(0, h + 1.6, 0) * ang(0, rng:NextNumber(0, 6), 0)
	local c1, c2 = pick(rng, ctx.pal.corals), Color3.fromRGB(255, 255, 255)
	for i = 0, 3 do
		Build.cylinder(m, 0.6 + i * 0.02, 4 - i * 0.9, frame * ang(0, rad(90), 0), if i % 2 == 0 then c1 else c2)
	end
end

E.gumdrop = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "Gumdrop")
	local size = rng:NextNumber(1.6, 3.2)
	local drop = Build.ball(m, size, at * cf(0, size * 0.25, 0), pick(rng, ctx.pal.corals))
	drop.Material = Enum.Material.Glass
	drop.Transparency = 0.15
end

E.candyCane = function(ctx, at)
	local rng = ctx.rng
	local m = group(ctx, "CandyCane")
	local frame = at * ang(0, rng:NextNumber(0, 6), 0)
	for i = 0, 7 do
		Build.column(m, 1.05, 0.8, frame * cf(0, 0.5 + i, 0), if i % 2 == 0 then Color3.fromRGB(240, 60, 80) else Color3.fromRGB(255, 255, 255))
	end
	for i = 0, 5 do
		local a = i / 5 * math.pi
		Build.ball(
			m,
			0.85,
			frame * cf(-1 + math.cos(a), 8.3 + math.sin(a) * 1, 0),
			if i % 2 == 0 then Color3.fromRGB(240, 60, 80) else Color3.fromRGB(255, 255, 255)
		)
	end
end

E.ribcage = function(ctx, _at)
	local m = group(ctx, "Leviathan")
	local bone = ctx.pal.bone
	local info = ctx.info
	local o = info.origin
	-- A colossal skeleton arching over the lagoon: spine across the back, ribs rising from the water.
	local spineCount = 14
	for i = 0, spineCount do
		local t = i / spineCount
		local a = math.rad(200 + t * 140)
		local r = info.radius + 10
		local p = o + V(math.cos(a) * r, 6 + math.sin(t * math.pi) * 10, math.sin(a) * r)
		solid(Build.ball(m, 5 - math.abs(t - 0.5) * 3, cf(p), bone))
		if i % 2 == 0 and i > 0 and i < spineCount then
			local inward = ((o - p) * V(1, 0, 1)).Unit
			-- Each rib starts pointing inward and up, then bends down toward the water.
			local seg = cf(p) * CFrame.lookAt(Vector3.zero, inward).Rotation * ang(rad(35), 0, 0)
			for _ = 1, 4 do
				seg = seg * cf(0, 0, -3)
				solid(Build.cylinder(m, 6.6, 1.4, seg * ang(0, rad(90), 0), bone))
				seg = seg * cf(0, 0, -3) * ang(rad(-22), 0, 0)
			end
		end
	end
	local skullAt = o + V(math.cos(math.rad(345)) * (info.radius + 18), 8, math.sin(math.rad(345)) * (info.radius + 18))
	local skull = Build.model("GiantSkull")
	RelicModels.Shapes.skull(skull, bone, Color3.fromRGB(255, 60, 90))
	Build.fit(skull, 26)
	skull:PivotTo(CFrame.lookAt(skullAt, o + V(0, 8, 0)))
	skull.Parent = m
	for _, part in skull:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			part.CanCollide = true
		end
	end
end

-- Kits ------------------------------------------------------------------------------------------

type Kit = { land: { [string]: number }, shelf: { [string]: number }, mid: { [string]: number }, deep: { [string]: number }, set: string? }

local KITS: { [string]: Kit } = {
	tropical = {
		land = { palm = 7, umbrella = 2, torch = 3, rock = 5 },
		shelf = { seagrass = 12, coral = 6, shell = 5, starfish = 4, rock = 3 },
		mid = { coral = 8, seagrass = 5, rock = 4 },
		deep = { rock = 5, coral = 3 },
	},
	seagrass = {
		land = { palm = 6, rock = 6, torch = 2 },
		shelf = { seagrass = 26, rock = 4, shell = 3 },
		mid = { seagrass = 14, rock = 5, starfish = 2 },
		deep = { seagrass = 6, rock = 5 },
	},
	kelp = {
		land = { palm = 3, rock = 9, deadTree = 2, torch = 2 },
		shelf = { kelp = 10, rock = 5, seagrass = 6 },
		mid = { kelp = 10, rock = 4 },
		deep = { kelp = 6, rock = 5 },
	},
	tidepool = {
		land = { rock = 14, palm = 3, torch = 2 },
		shelf = { anemone = 10, starfish = 6, rock = 8, shell = 4 },
		mid = { anemone = 6, coral = 4, rock = 5 },
		deep = { rock = 6, anemone = 3 },
	},
	reef = {
		land = { palm = 6, umbrella = 2, torch = 3, rock = 3 },
		shelf = { coral = 16, seagrass = 6, starfish = 3 },
		mid = { coral = 16, rock = 3 },
		deep = { coral = 8, rock = 4 },
	},
	candy = {
		land = { lollipop = 6, gumdrop = 8, candyCane = 4 },
		shelf = { coral = 14, gumdrop = 6 },
		mid = { coral = 12, lollipop = 2 },
		deep = { coral = 6, gumdrop = 4 },
	},
	glow = {
		land = { mushroom = 7, glowPlant = 6, rock = 4 },
		shelf = { glowPlant = 10, coral = 8 },
		mid = { crystal = 4, glowPlant = 6, coral = 6 },
		deep = { crystal = 5, glowPlant = 4 },
	},
	wreck = {
		land = { palm = 5, barrel = 4, crate = 4, torch = 3 },
		shelf = { barrel = 4, crate = 4, seagrass = 8, rock = 4 },
		mid = { cannon = 3, barrel = 3, rock = 4, coral = 4, anchor = 1 },
		deep = { hull = 1, crate = 3 },
	},
	graveyard = {
		land = { deadTree = 6, lantern = 6, bones = 4, rock = 5 },
		shelf = { bones = 6, barrel = 4, seagrass = 6 },
		mid = { hull = 1, cannon = 3, bones = 4 },
		deep = { hull = 1, skull = 3, crate = 3 },
	},
	temple = {
		land = { palm = 5, pillar = 6, statue = 2, torch = 4 },
		shelf = { pillar = 5, seagrass = 8, rock = 3 },
		mid = { pillar = 5, rune = 3, statue = 1 },
		deep = { arch = 1, pillar = 3, rune = 3 },
	},
	atlantis = {
		land = { pillar = 6, palm = 4, rune = 3 },
		shelf = { pillar = 4, coral = 8 },
		mid = { dome = 1, pillar = 5, rune = 4, crystal = 2 },
		deep = { arch = 1, crystal = 4, rune = 3 },
	},
	ice = {
		land = { pine = 10, iceSpike = 6, rock = 4 },
		shelf = { iceSpike = 6, rock = 5, iceberg = 2 },
		mid = { iceSpike = 5, crystal = 3 },
		deep = { iceSpike = 4, crystal = 4 },
	},
	crystal = { land = { crystal = 12, rock = 6 }, shelf = { crystal = 8, rock = 4 }, mid = { crystal = 8 }, deep = { crystal = 8 } },
	volcanic = {
		land = { deadTree = 6, basalt = 6, lava = 4, rock = 6 },
		shelf = { basalt = 6, vent = 3, rock = 4 },
		mid = { basalt = 5, vent = 3, lava = 2 },
		deep = { vent = 4, lava = 3, basalt = 3 },
	},
	abyss = {
		land = { glowPlant = 8, deadTree = 3, rock = 6, lantern = 3 },
		shelf = { tubeWorms = 6, glowPlant = 6, rock = 4 },
		mid = { tubeWorms = 6, glowPlant = 5, bones = 3 },
		deep = { tubeWorms = 5, crystal = 3, bones = 3 },
	},
	trench = {
		land = { spire = 6, rock = 8, lantern = 4 },
		shelf = { tubeWorms = 6, spire = 3, rock = 4 },
		mid = { tubeWorms = 6, spire = 3, glowPlant = 4 },
		deep = { spire = 3, crystal = 4, tubeWorms = 4 },
	},
	alien = {
		land = { spire = 6, glowPlant = 8, mushroom = 4 },
		shelf = { glowPlant = 8, tubeWorms = 4, spire = 2 },
		mid = { spire = 4, glowPlant = 6, crystal = 3 },
		deep = { spire = 3, crystal = 5, glowPlant = 4 },
	},
	maw = {
		land = { spire = 5, bones = 6, lantern = 5, rock = 4 },
		shelf = { bones = 6, tubeWorms = 4 },
		mid = { crystal = 4, bones = 5, glowPlant = 4 },
		deep = { crystal = 6, skull = 2 },
		set = "ribcage",
	},
}

Decor.Kits = KITS

function Decor.palette(world: number): Pal
	local data = Worlds.get(world)
	local corals = {}
	for _, hex in data.fish do
		table.insert(corals, Color.hex(hex))
	end
	table.insert(corals, Color.hex(data.accent[1]))
	local land = Color.hex(data.terrain.landColor)
	return {
		a1 = Color.hex(data.accent[1]),
		a2 = Color.hex(data.accent[2]),
		corals = corals,
		rock = Color.hex(data.terrain.rockColor),
		land = land,
		sand = Color.hex(data.terrain.beachColor),
		leaf = if data.kit == "candy" then Color3.fromRGB(120, 230, 150) else Color.darken(land, 0.1):Lerp(Color3.fromRGB(60, 170, 70), 0.4),
		wood = Color3.fromRGB(128, 86, 54),
		bone = Color3.fromRGB(238, 230, 212),
		glow = data.fishGlow,
	}
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Include
raycastParams.IgnoreWater = true

local function groundAt(position: Vector3, depth: number): RaycastResult?
	raycastParams.FilterDescendantsInstances = { Workspace.Terrain }
	return Workspace:Raycast(position, Vector3.new(0, -depth, 0), raycastParams)
end

-- Random land spot on the island ring, away from the dock.
local function landSpot(ctx: Ctx): CFrame?
	local info = ctx.info
	for _ = 1, 12 do
		local a = ctx.rng:NextNumber(0, math.pi * 2)
		local r = ctx.rng:NextNumber(info.radius + 9, info.islandRadius - 10)
		local lx, lz = math.cos(a) * r, math.sin(a) * r
		local nearDock = math.abs(lx) < 56 and lz > info.radius - 4 and lz < info.radius + 64
		if not nearDock then
			local hit = groundAt(info.origin + Vector3.new(lx, 90, lz), 140)
			if hit and hit.Position.Y > 0.5 then
				return CFrame.new(hit.Position)
			end
		end
	end
	return nil
end

local function floorSpot(ctx: Ctx, band: string): CFrame?
	local info = ctx.info
	local inner, outer
	if band == "shelf" then
		inner, outer = info.midRadius + 2, info.radius - 3
	elseif band == "mid" then
		inner, outer = info.deepRadius + 2, info.midRadius - 3
	else
		inner, outer = 0, info.deepRadius - 4
	end
	for _ = 1, 10 do
		local a = ctx.rng:NextNumber(0, math.pi * 2)
		local r = ctx.rng:NextNumber(inner, math.max(inner + 1, outer))
		local lx, lz = math.cos(a) * r, math.sin(a) * r
		local hit = groundAt(info.origin + Vector3.new(lx, -1, lz), info.depth + 20)
		if hit then
			local up = hit.Normal:Lerp(Vector3.yAxis, 0.6).Unit
			local right = up:Cross(Vector3.zAxis)
			if right.Magnitude < 0.01 then
				right = Vector3.xAxis
			end
			return CFrame.fromMatrix(hit.Position, right.Unit, up)
		end
	end
	return nil
end

function Decor.build(world: number, parent: Instance, rng: Random)
	local data = Worlds.get(world)
	local kit = KITS[data.kit] or KITS.tropical
	local ctx: Ctx = {
		parent = parent,
		rng = rng,
		pal = Decor.palette(world),
		world = world,
		info = Layout.info(world),
		lights = 0,
		maxLights = MAX_LIGHTS,
	}
	local function place(entries: { [string]: number }, spot: (Ctx) -> CFrame?)
		local names = {}
		for name in entries do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local builder = E[name]
			if builder then
				for _ = 1, entries[name] do
					local at = spot(ctx)
					if at then
						builder(ctx, at)
					end
				end
			end
		end
	end
	place(kit.land, landSpot)
	task.wait()
	place(kit.shelf, function(c)
		return floorSpot(c, "shelf")
	end)
	place(kit.mid, function(c)
		return floorSpot(c, "mid")
	end)
	place(kit.deep, function(c)
		return floorSpot(c, "deep")
	end)
	if kit.set and E[kit.set] then
		E[kit.set](ctx, CFrame.new(ctx.info.origin))
	end
end

return Decor
