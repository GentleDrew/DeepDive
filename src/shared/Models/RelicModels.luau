--!strict
-- Procedural relic (treasure) models, the Ancient Chest and pet eggs.

local Build = require(script.Parent.Build)
local Color = require(script.Parent.Parent.Color)
local Worlds = require(script.Parent.Parent.Data.Worlds)

local RelicModels = {}

local V = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rad = math.rad
local E = Build.ellipsoid
local B = Build.ball
local K = Build.block
local W = Build.wedge
local A = Build.markAccent

local DARK = Color3.fromRGB(34, 30, 40)
local WOOD = Color3.fromRGB(120, 78, 44)
local GOLD = Color3.fromRGB(255, 205, 64)

local function fibonacci(count: number): { Vector3 }
	local points = {}
	local golden = math.pi * (3 - math.sqrt(5))
	for i = 0, count - 1 do
		-- Half-step offset keeps samples off the exact poles (a vertical look has no defined up).
		local y = 1 - ((i + 0.5) / count) * 2
		local r = math.sqrt(1 - y * y)
		local theta = golden * i
		table.insert(points, V(math.cos(theta) * r, y, math.sin(theta) * r))
	end
	return points
end

-- Disc facing -Z (cylinder axis along Z).
local function disc(m: Model, thickness: number, diameter: number, at: CFrame, color: Color3): Part
	return Build.cylinder(m, thickness, diameter, at * ang(0, rad(90), 0), color)
end

local SHAPES: { [string]: (Model, Color3, Color3) -> () } = {}

SHAPES.shell = function(m, c1, c2)
	for i = -3, 3 do
		local a = rad(i * 17)
		local rib = E(m, V(0.36, 1.4, 0.18), ang(0, 0, a) * cf(0, 0.58, 0), if i % 2 == 0 then c1 else Color.lighten(c1, 0.2))
		rib.Name = "Rib"
	end
	A(E(m, V(0.62, 0.36, 0.24), cf(0, -0.02, 0), c2))
	for _, side in { -1, 1 } do
		A(W(m, V(0.2, 0.3, 0.3), cf(side * 0.36, -0.05, 0) * ang(0, rad(side * 90), 0), c2))
	end
end

SHAPES.conch = function(m, c1, c2)
	for i = 0, 6 do
		local t = i / 6
		local a = t * math.pi * 4
		local r = 0.45 * (1 - t)
		B(m, 1.2 * (1 - t * 0.78), cf(math.cos(a) * r, t * 1.5 - 0.45, math.sin(a) * r), c1)
		if i < 5 then
			local reach = r + 0.5 * (1 - t)
			A(W(m, V(0.12, 0.3, 0.2), cf(math.cos(a) * reach, t * 1.5 - 0.3, math.sin(a) * reach), c2))
		end
	end
	A(E(m, V(0.85, 1.05, 0.3), cf(0.05, -0.2, -0.5) * ang(0, 0, rad(-12)), c2))
end

SHAPES.sanddollar = function(m, c1, c2)
	disc(m, 0.2, 1.6, CFrame.identity, c1)
	for i = 0, 4 do
		local a = rad(90 + i * 72)
		A(E(m, V(0.2, 0.5, 0.06), cf(math.cos(a) * 0.35, math.sin(a) * 0.35, -0.11) * ang(0, 0, a - rad(90)), c2))
	end
	A(B(m, 0.14, cf(0, 0, -0.1), c2))
end

SHAPES.starfish = function(m, c1, c2)
	E(m, V(1.1, 1.1, 0.5), CFrame.identity, c1)
	for i = 0, 4 do
		local a = rad(90 + i * 72)
		local dir = V(math.cos(a), math.sin(a), 0)
		E(m, V(0.62, 1.5, 0.42), CFrame.new(dir * 0.8) * ang(0, 0, a - rad(90)), c1)
		A(B(m, 0.16, cf(dir * 0.7 + V(0, 0, -0.2)), c2))
		A(B(m, 0.13, cf(dir * 1.1 + V(0, 0, -0.16)), c2))
	end
end

SHAPES.pearl = function(m, c1, c2)
	E(m, V(1.8, 0.5, 1.4), cf(0, -0.3, 0), c1)
	E(m, V(1.8, 0.5, 1.4), cf(0, 0.32, 0.45) * ang(rad(-52), 0, 0), c1)
	E(m, V(1.4, 0.2, 1.05), cf(0, -0.12, 0), Color.lighten(c1, 0.35))
	local pearl = A(B(m, 0.72, cf(0, 0.1, -0.12), c2))
	pearl.Reflectance = 0.25
	pearl.Material = Enum.Material.Glass
end

SHAPES.coin = function(m, c1, c2)
	for i = 0, 2 do
		Build.column(m, 0.16, 1.0, cf(0.1 * i, -0.45 + i * 0.17, 0.35), c1)
	end
	disc(m, 0.2, 1.3, cf(0, 0.25, -0.05) * ang(rad(-8), rad(15), 0), c1)
	A(disc(m, 0.22, 0.95, cf(0, 0.25, -0.07) * ang(rad(-8), rad(15), 0), c2))
	A(B(m, 0.35, cf(0.05, 0.25, -0.2), c1))
end

SHAPES.bottle = function(m, c1, c2)
	local tilt = ang(0, 0, rad(-18))
	local body = Build.column(m, 1.4, 0.82, tilt * cf(0, -0.2, 0), c1)
	body.Material = Enum.Material.Glass
	body.Transparency = 0.35
	local neck = Build.column(m, 0.55, 0.36, tilt * cf(0, 0.75, 0), c1)
	neck.Material = Enum.Material.Glass
	neck.Transparency = 0.35
	Build.column(m, 0.28, 0.32, tilt * cf(0, 1.12, 0), WOOD)
	A(Build.column(m, 0.9, 0.34, tilt * cf(0, -0.2, 0), c2))
end

SHAPES.compass = function(m, c1, c2)
	disc(m, 0.3, 1.5, CFrame.identity, c1)
	disc(m, 0.1, 1.2, cf(0, 0, -0.16), Color3.fromRGB(245, 240, 225))
	A(K(m, V(0.12, 0.9, 0.06), cf(0, 0, -0.22) * ang(0, 0, rad(30)), Color3.fromRGB(230, 60, 60)))
	K(m, V(0.12, 0.45, 0.06), cf(0.11, -0.19, -0.23) * ang(0, 0, rad(30)), Color3.fromRGB(240, 240, 240))
	B(m, 0.16, cf(0, 0, -0.26), c2)
	A(Build.cylinder(m, 0.2, 0.3, cf(0, 0.82, 0), c2))
end

SHAPES.key = function(m, c1, c2)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		B(m, 0.24, cf(math.cos(a) * 0.36, 0.72 + math.sin(a) * 0.36, 0), c1)
	end
	A(B(m, 0.3, cf(0, 0.72, 0), c2))
	Build.column(m, 1.35, 0.2, cf(0, -0.25, 0), c1)
	K(m, V(0.36, 0.14, 0.16), cf(0.22, -0.72, 0), c1)
	K(m, V(0.26, 0.14, 0.16), cf(0.17, -0.48, 0), c1)
end

SHAPES.gem = function(m, c1, c2)
	local outer = K(m, V(1.05, 1.05, 1.05), ang(rad(45), rad(45), 0), c1)
	outer.Material = Enum.Material.Glass
	outer.Transparency = 0.2
	outer.Reflectance = 0.15
	A(K(m, V(0.55, 0.55, 0.55), ang(rad(45), rad(45), 0), c2))
	for i = 0, 3 do
		local a = rad(i * 90)
		local facet = W(m, V(0.4, 0.35, 0.4), cf(math.cos(a) * 0.5, 0.62, math.sin(a) * 0.5) * ang(0, -a + rad(90), 0), c1)
		facet.Material = Enum.Material.Glass
		facet.Transparency = 0.2
	end
end

SHAPES.crystal = function(m, c1, c2)
	E(m, V(1.3, 0.4, 1.0), cf(0, -0.7, 0), Color3.fromRGB(70, 66, 80))
	local spots = { { 0, 0, 1.4, 0 }, { -0.35, 0.05, 1.0, -22 }, { 0.38, -0.05, 1.1, 20 }, { 0.1, 0.3, 0.8, 8 }, { -0.15, -0.3, 0.75, -12 } }
	for index, spot in spots do
		local height = spot[3]
		local base = cf(spot[1], -0.55 + height / 2, spot[2]) * ang(rad(spot[2] * 30), 0, rad(spot[4]))
		local color = if index == 1 then c2 else c1
		local shaft = K(m, V(0.32, height, 0.32), base, color)
		shaft.Material = Enum.Material.Glass
		shaft.Transparency = 0.15
		A(shaft)
		Build.spike(m, 0.35, 0.32, base * cf(0, height / 2 + 0.17, 0) * ang(rad(90), 0, 0), color, true)
	end
end

SHAPES.orb = function(m, c1, c2)
	local orb = A(B(m, 1.1, cf(0, 0.25, 0), c1))
	orb.Material = Enum.Material.Glass
	orb.Transparency = 0.2
	A(B(m, 0.55, cf(0, 0.25, 0), c2))
	Build.column(m, 0.5, 0.55, cf(0, -0.55, 0), Color3.fromRGB(90, 80, 100))
	Build.column(m, 0.15, 0.8, cf(0, -0.82, 0), Color3.fromRGB(90, 80, 100))
	for i = 0, 2 do
		local a = rad(i * 120)
		W(m, V(0.14, 0.5, 0.25), cf(math.cos(a) * 0.45, -0.2, math.sin(a) * 0.45) * ang(0, -a, 0), Color3.fromRGB(110, 100, 120))
	end
end

SHAPES.idol = function(m, c1, c2)
	K(m, V(0.95, 1.35, 0.8), cf(0, 0.05, 0), c1)
	K(m, V(1.2, 0.3, 0.95), cf(0, -0.75, 0), Color.darken(c1, 0.2))
	for _, side in { -1, 1 } do
		A(B(m, 0.26, cf(side * 0.22, 0.25, -0.38), c2))
		K(m, V(0.34, 0.08, 0.1), cf(side * 0.22, 0.45, -0.4) * ang(0, 0, rad(side * -15)), Color.darken(c1, 0.35))
	end
	A(K(m, V(0.5, 0.14, 0.1), cf(0, -0.22, -0.41), c2))
	for i = -1, 1 do
		A(W(m, V(0.26, 0.5, 0.3), cf(i * 0.3, 0.95, 0) * ang(0, math.pi / 2, 0), c2))
	end
end

SHAPES.crown = function(m, c1, c2)
	local count = 12
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		K(m, V(0.32, 0.42, 0.14), cf(math.cos(a) * 0.62, 0, math.sin(a) * 0.62) * ang(0, -a + math.pi / 2, 0), c1)
	end
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		local p = V(math.cos(a) * 0.62, 0.45, math.sin(a) * 0.62)
		Build.spike(m, 0.5, 0.22, cf(p) * ang(rad(90), 0, 0), c1)
		A(B(m, 0.2, cf(p + V(0, 0.32, 0)), c2))
	end
	A(B(m, 0.26, cf(0, 0, -0.66), c2))
end

SHAPES.trident = function(m, c1, c2)
	Build.column(m, 2.0, 0.14, cf(0, -0.3, 0), c1)
	K(m, V(0.85, 0.14, 0.14), cf(0, 0.72, 0), c1)
	for _, x in { -0.36, 0, 0.36 } do
		local length = if x == 0 then 0.75 else 0.55
		Build.column(m, length * 0.6, 0.12, cf(x, 0.8 + length * 0.3, 0), c1)
		Build.spike(m, 0.35, 0.18, cf(x, 0.8 + length * 0.6 + 0.17, 0) * ang(rad(90), 0, 0), c1)
	end
	A(B(m, 0.26, cf(0, 0.72, -0.05), c2))
end

SHAPES.vase = function(m, c1, c2)
	E(m, V(1.0, 1.3, 1.0), CFrame.identity, c1)
	Build.column(m, 0.5, 0.42, cf(0, 0.82, 0), c1)
	Build.column(m, 0.12, 0.62, cf(0, 1.08, 0), c1)
	Build.column(m, 0.22, 0.55, cf(0, -0.72, 0), c1)
	A(Build.column(m, 0.14, 1.03, cf(0, 0.1, 0), c2))
	for _, side in { -1, 1 } do
		E(m, V(0.12, 0.55, 0.3), cf(side * 0.52, 0.6, 0) * ang(0, 0, rad(side * 20)), c1)
	end
end

SHAPES.goblet = function(m, c1, c2)
	E(m, V(0.95, 0.75, 0.95), cf(0, 0.45, 0), c1)
	Build.column(m, 0.1, 1.0, cf(0, 0.78, 0), c1)
	Build.column(m, 0.7, 0.2, cf(0, -0.1, 0), c1)
	Build.column(m, 0.12, 0.85, cf(0, -0.5, 0), c1)
	for i = 0, 2 do
		local a = rad(i * 120 + 90)
		A(B(m, 0.18, cf(math.cos(a) * 0.46, 0.45, math.sin(a) * 0.46), c2))
	end
end

SHAPES.mask = function(m, c1, c2)
	E(m, V(1.3, 1.6, 0.36), CFrame.identity, c1)
	for _, side in { -1, 1 } do
		E(m, V(0.36, 0.2, 0.12), cf(side * 0.3, 0.2, -0.18) * ang(0, 0, rad(side * -12)), DARK)
		A(B(m, 0.16, cf(side * 0.42, -0.2, -0.17), c2))
		A(W(m, V(0.18, 0.6, 0.25), cf(side * 0.4, 0.95, 0) * ang(0, 0, rad(side * -18)), c2))
	end
	E(m, V(0.5, 0.12, 0.12), cf(0, -0.42, -0.18), DARK)
	A(W(m, V(0.2, 0.8, 0.3), cf(0, 1.05, 0), c2))
end

SHAPES.skull = function(m, c1, c2)
	for _, a in { 35, -35 } do
		Build.cylinder(m, 2.0, 0.16, cf(0, -0.05, 0.25) * ang(0, 0, rad(a)), c1)
	end
	B(m, 1.3, cf(0, 0.15, 0), c1)
	E(m, V(0.9, 0.45, 0.8), cf(0, -0.45, -0.1), c1)
	for _, side in { -1, 1 } do
		A(E(m, V(0.34, 0.4, 0.2), cf(side * 0.27, 0.15, -0.55), c2))
	end
	W(m, V(0.16, 0.18, 0.1), cf(0, -0.12, -0.62), DARK)
	for i = -1, 1 do
		K(m, V(0.12, 0.14, 0.06), cf(i * 0.16, -0.42, -0.5), Color.lighten(c1, 0.3))
	end
end

SHAPES.sword = function(m, c1, c2)
	local blade = K(m, V(0.34, 1.3, 0.1), cf(0, 0.45, 0), c1)
	blade.Material = Enum.Material.Metal
	blade.Reflectance = 0.2
	local tip = W(m, V(0.1, 0.55, 0.34), cf(0, 1.36, 0) * ang(0, rad(90), 0), c1)
	tip.Material = Enum.Material.Metal
	K(m, V(0.85, 0.14, 0.22), cf(0, -0.25, 0), GOLD)
	Build.column(m, 0.5, 0.18, cf(0, -0.58, 0), WOOD)
	A(B(m, 0.26, cf(0, -0.9, 0), c2))
end

SHAPES.chest = function(m, c1, c2)
	K(m, V(1.6, 0.9, 1.0), CFrame.identity, c1)
	Build.cylinder(m, 1.6, 1.0, cf(0, 0.45, 0), c1)
	for _, x in { -0.6, 0.6 } do
		A(K(m, V(0.14, 0.95, 1.04), cf(x, 0, 0), c2))
		A(Build.cylinder(m, 0.14, 1.04, cf(x, 0.45, 0), c2))
	end
	A(K(m, V(0.28, 0.32, 0.12), cf(0, 0.2, -0.54), c2))
	A(B(m, 0.12, cf(0, 0.15, -0.62), DARK))
end

SHAPES.coral = function(m, c1, c2)
	Build.column(m, 0.7, 0.34, cf(0, -0.6, 0), c1)
	local branches = { { 0, 30, 0.9 }, { 120, 38, 0.8 }, { 240, 28, 0.85 }, { 60, 10, 1.0 } }
	for _, b in branches do
		local yaw, tilt, length = rad(b[1]), rad(b[2]), b[3]
		local base = cf(0, -0.3, 0) * ang(0, yaw, 0) * ang(tilt, 0, 0)
		Build.column(m, length, 0.24, base * cf(0, length / 2, 0), c1)
		A(B(m, 0.3, base * cf(0, length, 0), c2))
	end
end

SHAPES.fossil = function(m, c1, c2)
	E(m, V(1.6, 1.6, 0.4), cf(0, 0, 0.12), Color.darken(c1, 0.35))
	for i = 0, 11 do
		local a = i * 0.6
		local r = 0.62 * math.exp(-0.14 * i)
		local size = 0.5 * math.exp(-0.09 * i)
		local part = B(m, size, cf(math.cos(a) * r, math.sin(a) * r, -0.12), if i % 3 == 0 then c2 else c1)
		if i % 3 == 0 then
			A(part)
		end
	end
end

SHAPES.brain = function(m, c1, c2)
	B(m, 1.5, CFrame.identity, c1)
	for i = 0, 5 do
		A(E(m, V(1.54, 0.12, 0.3), ang(rad(i * 30), rad(i * 47), rad(i * 19)), c2))
	end
end

SHAPES.tablet = function(m, c1, c2)
	K(m, V(1.2, 1.3, 0.26), cf(0, -0.15, 0), c1)
	disc(m, 0.26, 1.2, cf(0, 0.5, 0), c1)
	for row = 0, 3 do
		for col = -1, 1 do
			K(m, V(0.22, 0.08, 0.05), cf(col * 0.3, 0.35 - row * 0.25, -0.14), Color.darken(c1, 0.4))
		end
	end
	A(B(m, 0.26, cf(0, 0.62, -0.12), c2))
end

SHAPES.medallion = function(m, c1, c2)
	for i = 0, 7 do
		local a = rad(i * 45)
		A(W(m, V(0.12, 0.35, 0.3), cf(math.cos(a) * 0.82, math.sin(a) * 0.82, 0) * ang(0, rad(90), a - rad(90)), c1))
	end
	disc(m, 0.2, 1.45, CFrame.identity, c1)
	A(disc(m, 0.22, 0.95, cf(0, 0, -0.02), c2))
	A(B(m, 0.4, cf(0, 0, -0.14), c1))
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		B(m, 0.12, cf(math.cos(a) * 0.12, 0.9 + math.sin(a) * 0.12, 0), c1)
	end
end

SHAPES.geode = function(m, c1, c2)
	E(m, V(1.4, 1.25, 1.3), cf(0, 0, 0.12), c1)
	E(m, V(1.0, 0.9, 0.2), cf(0, 0, -0.52), DARK)
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		local p = V(math.cos(a) * 0.3, math.sin(a) * 0.28, -0.55)
		Build.spike(m, 0.38, 0.16, Build.look(p, p + V(math.cos(a) * 0.3, math.sin(a) * 0.3, -1)), c2, true)
	end
	Build.spike(m, 0.4, 0.2, cf(0, 0, -0.55), c2, true)
end

SHAPES.urchin = function(m, c1, c2)
	B(m, 1.1, CFrame.identity, c1)
	for _, dir in fibonacci(20) do
		local p = dir * 0.5
		Build.spike(m, 0.7, 0.09, Build.look(p, p + dir) * cf(0, 0, -0.3), c2, true)
	end
end

SHAPES.float = function(m, c1, c2)
	local glass = B(m, 1.3, CFrame.identity, c1)
	glass.Material = Enum.Material.Glass
	glass.Transparency = 0.3
	for i = 0, 2 do
		A(E(m, V(1.36, 1.36, 0.07), ang(0, rad(i * 60), 0), c2))
	end
	A(E(m, V(1.36, 0.07, 1.36), CFrame.identity, c2))
	Build.column(m, 0.25, 0.3, cf(0, 0.72, 0), c2)
end

SHAPES.tooth = function(m, c1, c2)
	E(m, V(0.8, 1.4, 0.7), cf(0, -0.1, 0), c1)
	Build.spike(m, 0.9, 0.55, cf(0, 0.95, 0) * ang(rad(90), 0, 0), c1)
	for _, side in { -1, 1 } do
		A(E(m, V(0.3, 0.6, 0.3), cf(side * 0.2, -0.85, 0) * ang(0, 0, rad(side * 12)), c2))
	end
end

local RARITY_SIZE = { 1.5, 1.65, 1.8, 2.0, 2.3 }

function RelicModels.build(key: string, sizeOverride: number?): Model
	local relic = Worlds.relics[key]
	local model = Build.model("Relic_" .. key)
	if not relic then
		Build.ball(model, 1.5, CFrame.identity, Color3.new(1, 0, 1))
		return model
	end
	local c1, c2 = Color.hex(relic.color), Color.hex(relic.accent)
	local builder = SHAPES[relic.shape] or SHAPES.gem
	builder(model, c1, c2)
	Build.style(model, relic.style, c2)
	Build.fit(model, sizeOverride or RARITY_SIZE[relic.rarity] or 1.6)
	model:SetAttribute("RelicKey", key)
	return model
end

-- The world's Ancient Chest: bigger, gilded, with a glowing seam.
function RelicModels.buildChest(world: number, size: number?): Model
	local data = Worlds.get(world)
	local accent = Color.hex(data.accent[1])
	local model = Build.model("AncientChest")
	local wood = Color3.fromRGB(96, 60, 36)
	K(model, V(2.4, 1.3, 1.5), CFrame.identity, wood)
	Build.cylinder(model, 2.4, 1.5, cf(0, 0.65, 0), wood)
	for _, x in { -1.0, 0, 1.0 } do
		K(model, V(0.18, 1.36, 1.56), cf(x, 0, 0), GOLD).Material = Enum.Material.Metal
		Build.cylinder(model, 0.18, 1.56, cf(x, 0.65, 0), GOLD).Material = Enum.Material.Metal
	end
	local seam = K(model, V(2.46, 0.1, 1.56), cf(0, 0.66, 0), accent)
	seam.Material = Enum.Material.Neon
	local lock = K(model, V(0.45, 0.5, 0.16), cf(0, 0.35, -0.8), GOLD)
	lock.Material = Enum.Material.Metal
	local gem = B(model, 0.26, cf(0, 0.35, -0.9), accent)
	gem.Material = Enum.Material.Neon
	for _, corner in { V(-1.15, -0.6, -0.72), V(1.15, -0.6, -0.72), V(-1.15, -0.6, 0.72), V(1.15, -0.6, 0.72) } do
		K(model, V(0.3, 0.3, 0.3), cf(corner), GOLD).Material = Enum.Material.Metal
	end
	local root = model.PrimaryPart :: BasePart
	Build.light(root, accent, 14, 2.5)
	Build.sparkles(root, GOLD, 12)
	Build.fit(model, size or 4)
	return model
end

-- Pet egg for a world, decorated with spots in the egg's accent colour.
function RelicModels.buildEgg(world: number, size: number?): Model
	local data = Worlds.get(world)
	local c1, c2 = Color.hex(data.egg.color), Color.hex(data.egg.accent)
	local model = Build.model("Egg_" .. world)
	E(model, V(2.2, 2.8, 2.2), cf(0, 0, 0), c1)
	local rng = Random.new(world * 7919)
	for i = 1, 9 do
		local phi = math.acos(1 - 2 * (i - 0.5) / 9)
		local theta = rng:NextNumber(0, math.pi * 2)
		local normal = V(math.sin(phi) * math.cos(theta), math.cos(phi), math.sin(phi) * math.sin(theta))
		local p = V(normal.X * 1.08, normal.Y * 1.38, normal.Z * 1.08)
		local d = 0.45 + rng:NextNumber(0, 0.3)
		A(E(model, V(d, d, 0.14), Build.look(p, p + normal), c2))
	end
	A(E(model, V(2.24, 0.22, 2.24), cf(0, -0.2, 0), c2))
	Build.style(model, data.egg.style, c2)
	Build.fit(model, size or 3)
	return model
end

RelicModels.Shapes = SHAPES

return RelicModels
