--!strict
-- Procedural pet models. Every model faces -Z, is centred on its Root part and is built from
-- primitives only, so the same builder serves followers, egg displays and UI viewports.

local Build = require(script.Parent.Build)
local Color = require(script.Parent.Parent.Color)
local Worlds = require(script.Parent.Parent.Data.Worlds)

local PetModels = {}

local V = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rad = math.rad
local E = Build.ellipsoid
local B = Build.ball
local K = Build.block
local W = Build.wedge
local A = Build.markAccent

local WHITE = Color3.new(1, 1, 1)
local DARK = Color3.fromRGB(34, 30, 40)
local ORANGE = Color3.fromRGB(255, 165, 63)
local BLUSH = Color3.fromRGB(255, 140, 170)

local function light(c: Color3): Color3
	return Color.lighten(c, 0.45)
end

local function shade(c: Color3): Color3
	return Color.darken(c, 0.25)
end

local function mouth(m: Model, position: Vector3, width: number)
	E(m, V(width, width * 0.28, width * 0.35), cf(position), DARK)
end

local function blush(m: Model, x: number, y: number, z: number, size: number)
	for _, side in { -1, 1 } do
		local part = E(m, V(size, size * 0.55, size * 0.3), cf(side * x, y, z) * ang(0, rad(side * -25), 0), BLUSH)
		part.Transparency = 0.25
		part:SetAttribute("Eye", true)
	end
end

-- Forked tail made of two wedges meeting at the tail root (z = root), spreading toward +Z.
local function forkTail(m: Model, root: number, height: number, length: number, color: Color3, y: number?)
	local oy = y or 0
	A(W(m, V(0.18, height, length), cf(0, oy + height / 2, root + length / 2) * ang(rad(-12), 0, 0), color))
	A(W(m, V(0.18, height, length), cf(0, oy - height / 2, root + length / 2) * ang(rad(12), 0, 0) * ang(0, 0, math.pi), color))
end

-- Flat horizontal flukes (whales, dolphins).
local function flukes(m: Model, z: number, span: number, color: Color3, y: number?)
	local oy = y or 0
	for _, side in { -1, 1 } do
		A(E(m, V(span, 0.16, span * 0.45), cf(side * span * 0.42, oy, z) * ang(0, rad(side * 28), 0), color))
	end
end

local function dorsal(m: Model, y: number, z: number, height: number, length: number, color: Color3)
	A(W(m, V(0.16, height, length), cf(0, y + height / 2, z), color))
end

local function sideFins(m: Model, x: number, y: number, z: number, size: Vector3, color: Color3, spread: number?)
	for _, side in { -1, 1 } do
		A(E(m, size, cf(side * x, y, z) * ang(0, rad(side * 30), rad(side * (spread or 35))), color))
	end
end

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

local SHAPES: { [string]: (Model, Color3, Color3) -> () } = {}

SHAPES.fish = function(m, c1, c2)
	E(m, V(1.5, 1.6, 2.4), cf(0, 0, 0), c1)
	E(m, V(1.2, 0.95, 1.9), cf(0, -0.35, -0.1), light(c1))
	A(E(m, V(1.56, 1.3, 0.22), cf(0, 0, 0.35), c2))
	forkTail(m, 1.0, 1.0, 1.05, c2)
	dorsal(m, 0.62, 0.15, 0.7, 1.0, c2)
	sideFins(m, 0.78, -0.2, -0.05, V(0.12, 0.45, 0.75), c2)
	Build.eyes(m, CFrame.identity, 0.5, 0.25, -0.82, 0.58, 28)
	mouth(m, V(0, -0.18, -1.18), 0.3)
	blush(m, 0.56, -0.12, -0.82, 0.28)
end

SHAPES.lionfish = function(m, c1, c2)
	SHAPES.fish(m, c1, c2)
	for i = 0, 5 do
		local z = -0.55 + i * 0.3
		Build.spike(m, 1.0, 0.12, cf(0, 1.15, z) * ang(rad(108), 0, 0), if i % 2 == 0 then c2 else c1, true)
	end
	for _, z in { -0.25, 0.3 } do
		A(E(m, V(1.56, 1.66, 0.14), cf(0, 0, z), c2))
	end
end

SHAPES.puffer = function(m, c1, c2)
	B(m, 2.2, cf(0, 0, 0), c1)
	E(m, V(1.9, 1.1, 1.9), cf(0, -0.5, 0), light(c1))
	for _, dir in fibonacci(22) do
		if dir.Z > -0.55 then
			local pos = dir * 1.02
			Build.spike(m, 0.42, 0.14, Build.look(pos, pos + dir), c2, true)
		end
	end
	forkTail(m, 1.0, 0.7, 0.7, c2)
	sideFins(m, 1.05, -0.1, -0.1, V(0.12, 0.4, 0.55), c2)
	Build.eyes(m, CFrame.identity, 0.46, 0.25, -0.92, 0.66, 22)
	E(m, V(0.34, 0.3, 0.2), cf(0, -0.25, -1.1), DARK)
	blush(m, 0.62, -0.1, -0.86, 0.3)
end

SHAPES.turtle = function(m, c1, c2)
	E(m, V(2.4, 1.35, 2.8), cf(0, 0.25, 0.1), c1)
	E(m, V(2.25, 0.4, 2.6), cf(0, -0.28, 0.1), Color.lighten(c2, 0.55))
	for _, p in { V(0, 0.95, 0.1), V(-0.62, 0.72, -0.35), V(0.62, 0.72, -0.35), V(-0.62, 0.72, 0.6), V(0.62, 0.72, 0.6) } do
		local tilt = Build.look(p, p + (p - V(0, -0.4, 0.1)).Unit)
		A(E(m, V(0.62, 0.62, 0.16), tilt, shade(c1)))
	end
	E(m, V(0.95, 0.85, 1.0), cf(0, 0.15, -1.55), c2)
	for _, side in { -1, 1 } do
		E(m, V(1.3, 0.18, 0.55), cf(side * 1.2, -0.1, -0.7) * ang(0, rad(side * 30), rad(side * -10)), c2)
		E(m, V(0.8, 0.16, 0.45), cf(side * 0.95, -0.15, 1.15) * ang(0, rad(side * -30), 0), c2)
	end
	Build.eyes(m, CFrame.identity, 0.26, 0.3, -1.92, 0.42, 30)
	mouth(m, V(0, -0.02, -2.02), 0.26)
end

SHAPES.crab = function(m, c1, c2)
	E(m, V(2.4, 1.05, 1.8), cf(0, 0, 0), c1)
	E(m, V(2.0, 0.5, 1.5), cf(0, -0.35, 0), light(c1))
	for _, side in { -1, 1 } do
		Build.cylinder(m, 0.8, 0.26, cf(side * 1.25, 0.05, -0.7) * ang(0, rad(side * 40), 0), c1)
		E(m, V(0.8, 0.62, 0.95), cf(side * 1.55, 0.15, -1.2), c1)
		A(E(m, V(0.34, 0.36, 0.7), cf(side * 1.72, 0.48, -1.5) * ang(rad(20), 0, 0), c2))
		for i, z in { -0.2, 0.25, 0.65 } do
			Build.cylinder(m, 1.0, 0.16, cf(side * 1.35, -0.38, z) * ang(0, rad(side * (i - 2) * 12), rad(side * -35)), c2)
		end
		Build.column(m, 0.6, 0.14, cf(side * 0.42, 0.72, -0.55), c1)
	end
	Build.eyes(m, CFrame.identity, 0.42, 1.08, -0.62, 0.48, 12)
	mouth(m, V(0, 0.02, -0.9), 0.34)
	blush(m, 0.7, 0.1, -0.78, 0.3)
end

SHAPES.octopus = function(m, c1, c2)
	E(m, V(2.0, 2.2, 2.0), cf(0, 0.55, 0.15), c1)
	for i = 1, 8 do
		local a = (i - 0.5) / 8 * math.pi * 2
		local dir = V(math.cos(a), 0, math.sin(a))
		B(m, 0.62, cf(dir * 0.8 + V(0, -0.45, 0)), c1)
		B(m, 0.5, cf(dir * 1.15 + V(0, -0.85, 0)), c1)
		A(B(m, 0.38, cf(dir * 1.38 + V(0, -1.05, 0)), c2))
	end
	for _, p in { V(-0.55, 1.25, 0.35), V(0.45, 1.4, 0.55), V(0.1, 1.55, -0.05) } do
		A(E(m, V(0.36, 0.2, 0.36), cf(p), c2))
	end
	Build.eyes(m, CFrame.identity, 0.45, 0.45, -0.78, 0.64, 25)
	mouth(m, V(0, 0.02, -0.86), 0.28)
	blush(m, 0.66, 0.12, -0.7, 0.32)
end

SHAPES.jelly = function(m, c1, c2)
	local bell = E(m, V(2.4, 1.7, 2.4), cf(0, 0.45, 0), c1)
	bell.Transparency = 0.18
	A(E(m, V(1.5, 1.0, 1.5), cf(0, 0.4, 0), c2))
	E(m, V(2.5, 0.35, 2.5), cf(0, -0.3, 0), c1)
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local x, z = math.cos(a) * 0.8, math.sin(a) * 0.8
		local sway = if i % 2 == 0 then 1 else -1
		A(E(m, V(0.18, 0.95, 0.18), cf(x, -0.85, z) * ang(rad(10 * sway), 0, rad(6 * sway)), c2))
		A(E(m, V(0.15, 0.8, 0.15), cf(x * 1.05, -1.6, z * 1.05) * ang(rad(-12 * sway), 0, 0), c2))
	end
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2
		E(m, V(0.35, 1.3, 0.25), cf(math.cos(a) * 0.25, -1.0, math.sin(a) * 0.25), light(c1))
	end
	Build.eyes(m, CFrame.identity, 0.42, 0.42, -1.02, 0.46, 26)
	mouth(m, V(0, 0.08, -1.12), 0.24)
end

SHAPES.starfish = function(m, c1, c2)
	E(m, V(1.2, 1.2, 0.6), cf(0, 0, 0), c1)
	for i = 0, 4 do
		local a = rad(90 + i * 72)
		local dir = V(math.cos(a), math.sin(a), 0)
		E(m, V(0.66, 1.55, 0.48), CFrame.new(dir * 0.85) * ang(0, 0, a - rad(90)), c1)
		A(B(m, 0.18, cf(dir * 0.8 + V(0, 0, -0.24)), c2))
		A(B(m, 0.14, cf(dir * 1.2 + V(0, 0, -0.18)), c2))
	end
	Build.eyes(m, CFrame.identity, 0.24, 0.14, -0.32, 0.36, 20)
	mouth(m, V(0, -0.18, -0.34), 0.2)
end

SHAPES.seahorse = function(m, c1, c2)
	E(m, V(0.85, 0.95, 1.05), cf(0, 1.15, -0.1), c1)
	Build.cylinder(m, 0.75, 0.32, cf(0, 1.02, -0.78) * ang(0, rad(90), 0), c1)
	E(m, V(0.95, 1.25, 1.05), cf(0, 0.3, 0.1), c1)
	E(m, V(0.72, 1.0, 0.62), cf(0, 0.25, -0.2), light(c1))
	local tailPoints = { V(0, -0.5, 0.25), V(0, -0.95, 0.22), V(0, -1.25, -0.02), V(0, -1.32, -0.34), V(0, -1.12, -0.5) }
	local tailSizes = { 0.62, 0.48, 0.36, 0.28, 0.22 }
	for i, point in tailPoints do
		B(m, tailSizes[i], cf(point), c1)
	end
	for i = 0, 2 do
		A(W(m, V(0.12, 0.35, 0.4), cf(0, 1.55 - i * 0.18, 0.2 + i * 0.22) * ang(rad(-30 - i * 15), 0, 0), c2))
	end
	dorsal(m, 0.15, 0.62, 0.55, 0.5, c2)
	Build.eyes(m, CFrame.identity, 0.34, 1.26, -0.36, 0.4, 40)
	blush(m, 0.4, 1.0, -0.4, 0.22)
end

SHAPES.shark = function(m, c1, c2)
	E(m, V(1.4, 1.35, 3.4), cf(0, 0, 0), c1)
	E(m, V(1.15, 0.8, 2.8), cf(0, -0.3, -0.1), c2)
	dorsal(m, 0.5, 0.2, 1.05, 1.1, c1)
	A(W(m, V(0.16, 1.2, 1.0), cf(0, 0.55, 2.0) * ang(rad(-25), 0, 0), c1))
	A(W(m, V(0.16, 0.7, 0.7), cf(0, -0.3, 1.95) * ang(rad(25), 0, 0) * ang(0, 0, math.pi), c1))
	sideFins(m, 0.7, -0.35, -0.2, V(0.14, 0.5, 1.0), c1, 55)
	Build.eyes(m, CFrame.identity, 0.46, 0.2, -1.22, 0.44, 40)
	E(m, V(0.62, 0.12, 0.22), cf(0, -0.36, -1.45), DARK)
	for i = -1, 1 do
		local tooth = W(m, V(0.1, 0.12, 0.08), cf(i * 0.16, -0.31, -1.52) * ang(0, 0, math.pi), WHITE)
		tooth:SetAttribute("Eye", true)
	end
	for _, side in { -1, 1 } do
		for i = 0, 2 do
			K(m, V(0.05, 0.4, 0.06), cf(side * 0.68, 0.0, -0.75 + i * 0.16), shade(c1))
		end
	end
end

SHAPES.hammerhead = function(m, c1, c2)
	SHAPES.shark(m, c1, c2)
	E(m, V(2.5, 0.42, 0.85), cf(0, 0.1, -1.55), c1)
	Build.eye(m, 0.36, cf(-1.15, 0.12, -1.55) * ang(0, rad(75), 0))
	Build.eye(m, 0.36, cf(1.15, 0.12, -1.55) * ang(0, rad(-75), 0))
end

SHAPES.dolphin = function(m, c1, c2)
	E(m, V(1.35, 1.35, 3.2), cf(0, 0.1, 0), c1)
	E(m, V(1.1, 0.8, 2.6), cf(0, -0.25, -0.1), c2)
	E(m, V(1.12, 1.05, 1.2), cf(0, 0.25, -1.1), c1)
	E(m, V(0.5, 0.42, 0.9), cf(0, -0.08, -1.78), c1)
	dorsal(m, 0.62, 0.3, 0.8, 0.9, c1)
	flukes(m, 1.85, 1.3, c1, 0.1)
	sideFins(m, 0.68, -0.3, -0.45, V(0.12, 0.35, 0.8), c1, 50)
	Build.eyes(m, CFrame.identity, 0.52, 0.2, -1.0, 0.38, 45)
	E(m, V(0.5, 0.08, 0.2), cf(0, -0.25, -1.6), DARK)
	blush(m, 0.55, -0.02, -1.08, 0.26)
end

SHAPES.whale = function(m, c1, c2)
	E(m, V(2.4, 2.1, 3.6), cf(0, 0, 0), c1)
	E(m, V(2.0, 1.2, 3.0), cf(0, -0.5, -0.2), c2)
	for i = -1, 1 do
		K(m, V(0.08, 0.06, 2.2), cf(i * 0.4, -1.02, -0.3), shade(c2))
	end
	E(m, V(0.95, 0.85, 1.1), cf(0, 0.1, 1.65), c1)
	flukes(m, 2.15, 1.3, c1, 0.2)
	for _, side in { -1, 1 } do
		A(E(m, V(0.22, 0.45, 1.2), cf(side * 1.2, -0.45, -0.35) * ang(0, rad(side * 25), rad(side * 35)), c1))
	end
	Build.eyes(m, CFrame.identity, 0.88, -0.02, -1.15, 0.42, 48)
	E(m, V(0.9, 0.1, 0.25), cf(0, -0.3, -1.72), DARK)
	blush(m, 0.95, -0.25, -1.1, 0.34)
end

SHAPES.narwhal = function(m, c1, c2)
	E(m, V(2.0, 1.8, 3.2), cf(0, 0, 0), c1)
	E(m, V(1.7, 1.0, 2.6), cf(0, -0.45, -0.2), light(c1))
	for _, p in { V(-0.45, 0.8, 0.2), V(0.35, 0.75, 0.7), V(0.1, 0.85, -0.4) } do
		E(m, V(0.3, 0.12, 0.3), cf(p), shade(c1))
	end
	local base = cf(0, 0.38, -1.55) * ang(rad(12), 0, 0)
	A(Build.cylinder(m, 0.8, 0.28, base * cf(0, 0, -0.4) * ang(0, rad(90), 0), c2))
	A(Build.cylinder(m, 0.7, 0.2, base * cf(0, 0, -1.1) * ang(0, rad(90), 0), c2))
	A(Build.cylinder(m, 0.6, 0.12, base * cf(0, 0, -1.72) * ang(0, rad(90), 0), c2))
	flukes(m, 1.95, 1.1, c1, 0.15)
	sideFins(m, 1.0, -0.4, -0.4, V(0.18, 0.4, 0.9), c1, 35)
	Build.eyes(m, CFrame.identity, 0.72, 0.05, -1.08, 0.4, 45)
	blush(m, 0.8, -0.2, -1.0, 0.3)
end

SHAPES.ray = function(m, c1, c2)
	E(m, V(2.0, 0.5, 2.4), cf(0, 0, 0), c1)
	for _, side in { -1, 1 } do
		E(m, V(2.3, 0.36, 1.4), cf(side * 1.05, 0, 0.15) * ang(0, rad(side * 25), rad(side * -6)), c1)
		E(m, V(0.32, 0.26, 0.62), cf(side * 0.55, 0, -1.25), c1)
	end
	E(m, V(1.8, 0.3, 2.0), cf(0, -0.14, 0), c2)
	Build.cylinder(m, 2.0, 0.12, cf(0, 0, 2.1) * ang(0, rad(90), 0), c1)
	for _, p in { V(-0.45, 0.24, 0.35), V(0.45, 0.24, 0.35), V(0, 0.26, 0.75) } do
		A(E(m, V(0.3, 0.1, 0.3), cf(p), c2))
	end
	Build.eyes(m, cf(0, 0.12, 0) * ang(rad(-20), 0, 0), 0.42, 0.14, -0.9, 0.36, 22)
	blush(m, 0.62, 0.1, -0.85, 0.24)
end

SHAPES.squid = function(m, c1, c2)
	E(m, V(1.2, 1.2, 2.6), cf(0, 0.1, 0.6), c1)
	for _, side in { -1, 1 } do
		A(E(m, V(0.9, 0.12, 0.8), cf(side * 0.55, 0.1, 1.6) * ang(0, rad(side * 30), 0), c2))
	end
	E(m, V(1.05, 1.0, 0.95), cf(0, 0.05, -0.75), c1)
	for i = -2, 2 do
		E(m, V(0.2, 0.2, 0.95), cf(i * 0.2, -0.32, -1.45) * ang(rad(25), 0, 0), c1)
	end
	for _, side in { -1, 1 } do
		E(m, V(0.16, 0.16, 1.5), cf(side * 0.3, -0.45, -1.7) * ang(rad(18), 0, 0), c1)
		A(E(m, V(0.28, 0.24, 0.4), cf(side * 0.3, -0.72, -2.4), c2))
	end
	for _, p in { V(-0.3, 0.45, 0.6), V(0.25, 0.5, 1.05), V(0, 0.55, 0.2) } do
		A(B(m, 0.18, cf(p), c2))
	end
	Build.eyes(m, CFrame.identity, 0.42, 0.18, -1.05, 0.52, 36)
end

SHAPES.angler = function(m, c1, c2)
	B(m, 2.2, cf(0, 0, 0), c1)
	E(m, V(1.5, 0.72, 0.42), cf(0, -0.45, -0.95), DARK)
	for i = -2, 2 do
		local up = W(m, V(0.12, 0.2, 0.1), cf(i * 0.26, -0.2, -1.12) * ang(0, 0, math.pi), WHITE)
		up:SetAttribute("Eye", true)
		local down = W(m, V(0.12, 0.18, 0.1), cf(i * 0.26 + 0.13, -0.72, -1.08), WHITE)
		down:SetAttribute("Eye", true)
	end
	Build.cylinder(m, 0.9, 0.1, cf(0, 1.35, -0.35) * ang(0, rad(90), rad(70)), shade(c1))
	Build.cylinder(m, 0.8, 0.1, cf(0, 1.62, -0.95) * ang(0, rad(90), rad(-10)), shade(c1))
	local lure = A(B(m, 0.5, cf(0, 1.45, -1.38), c2))
	lure.Material = Enum.Material.Neon
	Build.light(lure :: BasePart, c2, 10, 2)
	forkTail(m, 1.0, 0.8, 0.8, shade(c1))
	sideFins(m, 1.05, -0.1, 0, V(0.12, 0.45, 0.6), shade(c1))
	Build.eyes(m, CFrame.identity, 0.55, 0.4, -0.86, 0.44, 30)
end

SHAPES.eel = function(m, c1, c2)
	E(m, V(0.95, 0.85, 1.1), cf(0, 0.05, -1.6), c1)
	local count = 7
	for i = 1, count do
		local t = i / count
		local z = -1.2 + t * 3.0
		local x = math.sin(i * 0.9) * 0.35
		local size = 0.9 - t * 0.5
		B(m, size, cf(x, 0, z), c1)
		A(K(m, V(0.08, size * 0.5, 0.45), cf(x, size * 0.55, z), c2))
	end
	Build.eyes(m, CFrame.identity, 0.3, 0.25, -1.96, 0.36, 30)
	E(m, V(0.5, 0.08, 0.2), cf(0, -0.18, -2.12), DARK)
end

SHAPES.axolotl = function(m, c1, c2)
	E(m, V(1.3, 1.0, 2.2), cf(0, -0.1, 0.3), c1)
	E(m, V(1.65, 1.2, 1.25), cf(0, 0.05, -0.85), c1)
	for _, side in { -1, 1 } do
		for k = 0, 2 do
			A(E(m, V(0.2, 0.55, 0.2), cf(side * 0.85, 0.3 + k * 0.08, -0.62 + k * 0.2) * ang(0, 0, rad(side * (-40 - k * 25))), c2))
		end
		E(m, V(0.3, 0.2, 0.5), cf(side * 0.6, -0.55, -0.35), c1)
		E(m, V(0.3, 0.2, 0.5), cf(side * 0.55, -0.55, 0.9), c1)
	end
	E(m, V(0.2, 0.75, 1.5), cf(0, 0.05, 1.65), c1)
	A(E(m, V(0.14, 0.9, 1.2), cf(0, 0.1, 1.8), c2))
	Build.eyes(m, CFrame.identity, 0.5, 0.18, -1.4, 0.34, 30)
	E(m, V(0.6, 0.08, 0.2), cf(0, -0.15, -1.45), DARK)
	blush(m, 0.62, -0.08, -1.3, 0.26)
end

SHAPES.penguin = function(m, c1, c2)
	E(m, V(1.7, 2.3, 1.6), cf(0, 0, 0), c1)
	E(m, V(1.3, 1.85, 1.0), cf(0, -0.12, -0.36), c2)
	W(m, V(0.3, 0.24, 0.45), cf(0, 0.52, -0.92) * ang(rad(-10), 0, 0), ORANGE)
	for _, side in { -1, 1 } do
		E(m, V(0.5, 0.18, 0.7), cf(side * 0.4, -1.15, -0.35), ORANGE)
		E(m, V(0.22, 1.2, 0.6), cf(side * 0.9, -0.05, 0) * ang(0, 0, rad(side * 15)), c1)
	end
	Build.eyes(m, CFrame.identity, 0.3, 0.75, -0.66, 0.36, 20)
	blush(m, 0.46, 0.45, -0.72, 0.24)
end

SHAPES.seal = function(m, c1, c2)
	E(m, V(1.6, 1.5, 2.6), cf(0, -0.1, 0.3), c1)
	B(m, 1.5, cf(0, 0.35, -0.85), c1)
	E(m, V(0.82, 0.5, 0.5), cf(0, 0.15, -1.5), c2)
	B(m, 0.24, cf(0, 0.32, -1.72), DARK)
	for _, side in { -1, 1 } do
		E(m, V(0.6, 0.16, 0.9), cf(side * 0.75, -0.6, -0.3) * ang(0, rad(side * 25), rad(side * -20)), c1)
		A(W(m, V(0.5, 0.14, 0.6), cf(side * 0.3, -0.2, 1.75) * ang(0, rad(side * 20), 0), c2))
	end
	Build.eye(m, 0.5, cf(-0.36, 0.55, -1.4) * ang(0, rad(22), 0), Color3.fromRGB(20, 18, 24))
	Build.eye(m, 0.5, cf(0.36, 0.55, -1.4) * ang(0, rad(-22), 0), Color3.fromRGB(20, 18, 24))
	blush(m, 0.5, 0.18, -1.45, 0.26)
end

SHAPES.otter = function(m, c1, c2)
	E(m, V(1.4, 1.9, 1.3), cf(0, -0.2, 0), c1)
	E(m, V(1.0, 1.4, 0.8), cf(0, -0.25, -0.36), c2)
	B(m, 1.3, cf(0, 1.0, -0.1), c1)
	E(m, V(1.0, 0.7, 0.6), cf(0, 0.85, -0.5), c2)
	for _, side in { -1, 1 } do
		B(m, 0.34, cf(side * 0.5, 1.55, 0), shade(c1))
		B(m, 0.34, cf(side * 0.32, -0.05, -0.72), shade(c1))
	end
	A(E(m, V(0.5, 0.2, 0.5), cf(0, 0.0, -0.78) * ang(rad(70), 0, 0), Color3.fromRGB(255, 200, 210)))
	B(m, 0.22, cf(0, 0.95, -0.82), DARK)
	E(m, V(0.5, 0.25, 1.3), cf(0, -1.05, 0.8), shade(c1))
	Build.eyes(m, CFrame.identity, 0.28, 1.15, -0.6, 0.32, 20)
	blush(m, 0.42, 0.85, -0.68, 0.22)
end

SHAPES.serpent = function(m, c1, c2)
	local count = 9
	for i = 0, count - 1 do
		local t = i / (count - 1)
		local z = -1.6 + t * 3.6
		local x = math.sin(t * math.pi * 1.5) * 0.6
		local y = math.cos(t * math.pi * 2) * 0.35
		local size = 1.1 - t * 0.55
		B(m, size, cf(x, y, z), c1)
		A(B(m, size * 0.7, cf(x, y - size * 0.22, z - 0.05), c2))
		if i % 2 == 0 and i < count - 1 then
			Build.spike(m, size * 0.55, 0.12, cf(x, y + size * 0.5, z) * ang(rad(105), 0, 0), c2, true)
		end
	end
	E(m, V(1.2, 1.0, 1.4), cf(0, 0.2, -2.1), c1)
	E(m, V(0.9, 0.6, 0.72), cf(0, 0.05, -2.75), c1)
	for _, side in { -1, 1 } do
		local base = V(side * 0.35, 0.65, -1.9)
		Build.spike(m, 0.8, 0.16, Build.look(base, base + V(side * 0.3, 0.7, 1)), c2, true)
		A(Build.cylinder(m, 0.9, 0.06, cf(side * 0.55, -0.05, -2.95) * ang(0, rad(side * 60), rad(-15)), c2))
	end
	Build.eyes(m, CFrame.identity, 0.38, 0.45, -2.38, 0.4, 32)
end

SHAPES.slug = function(m, c1, c2)
	E(m, V(1.2, 0.8, 2.6), cf(0, 0, 0), c1)
	E(m, V(1.45, 0.3, 2.8), cf(0, -0.32, 0), light(c1))
	for i = 1, 6 do
		local z = -0.95 + i * 0.3
		for _, side in { -1, 1 } do
			A(E(m, V(0.24, 0.5, 0.24), cf(side * 0.35, 0.45, z) * ang(0, 0, rad(side * -20)), c2))
		end
	end
	for _, side in { -1, 1 } do
		A(Build.column(m, 0.5, 0.16, cf(side * 0.25, 0.55, -1.0) * ang(rad(-15), 0, 0), c2))
	end
	Build.eyes(m, CFrame.identity, 0.26, 0.2, -1.22, 0.3, 25)
	mouth(m, V(0, -0.1, -1.3), 0.22)
end

local RARITY_SIZE = { 2.3, 2.5, 2.8, 3.1, 3.5, 4.0 }

function PetModels.build(key: string, sizeOverride: number?): Model
	local pet = Worlds.pets[key]
	local model = Build.model("Pet_" .. key)
	if not pet then
		Build.ball(model, 2, CFrame.identity, Color3.new(1, 0, 1))
		return model
	end
	local c1, c2 = Color.hex(pet.color), Color.hex(pet.accent)
	local builder = SHAPES[pet.shape] or SHAPES.fish
	builder(model, c1, c2)
	Build.style(model, pet.style, c2)
	Build.fit(model, sizeOverride or RARITY_SIZE[pet.rarity] or 2.5)
	model:SetAttribute("PetKey", key)
	return model
end

PetModels.Shapes = SHAPES

return PetModels
