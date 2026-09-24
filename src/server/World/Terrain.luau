--!strict
-- Voxel terrain for the shared ocean and each world's island + terraced blue hole.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Worlds = require(Shared.Data.Worlds)

local TerrainBuilder = {}

local terrain = Workspace.Terrain
local WATER = Enum.Material.Water
local AIR = Enum.Material.Air

local function block(center: Vector3, size: Vector3, material: Enum.Material)
	terrain:FillBlock(CFrame.new(center), size, material)
end

-- Upright cylinder between two heights.
local function cylinder(origin: Vector3, radius: number, bottom: number, top: number, material: Enum.Material)
	local height = top - bottom
	if height <= 0 then
		return
	end
	terrain:FillCylinder(CFrame.new(origin + Vector3.new(0, bottom + height / 2, 0)), height, radius, material)
end

-- Ocean for one world's grid cell. Cells are WorldSpacing wide, so neighbouring patches tile
-- seamlessly and never reach another island. Edge cells extend outward to push the horizon back.
function TerrainBuilder.buildOcean(world: number)
	local o = Layout.origin(world)
	local half = Config.WorldSpacing / 2
	local rows = math.ceil(Config.WorldCount / Config.WorldColumns)
	local col = (world - 1) % Config.WorldColumns
	local row = (world - 1) // Config.WorldColumns
	local extra = 600
	local minX = o.X - half - (if col == 0 then extra else 0)
	local maxX = o.X + half + (if col == Config.WorldColumns - 1 then extra else 0)
	local minZ = o.Z - half - (if row == 0 then extra else 0)
	local maxZ = o.Z + half + (if row == rows - 1 or world + Config.WorldColumns > Config.WorldCount then extra else 0)
	local tile = 500
	local depth = Config.OceanDepth
	local x = minX
	while x < maxX do
		local z = minZ
		while z < maxZ do
			local sx, sz = math.min(tile, maxX - x), math.min(tile, maxZ - z)
			local cx, cz = x + sx / 2, z + sz / 2
			block(Vector3.new(cx, -depth - 3, cz), Vector3.new(sx, 6, sz), Enum.Material.Sand)
			block(Vector3.new(cx, -depth / 2, cz), Vector3.new(sx, depth, sz), WATER)
			z += tile
		end
		x += tile
	end
end

-- Builds the island, lagoon terraces, beach inlet and backdrop hills for a world.
function TerrainBuilder.buildIsland(world: number, rng: Random)
	local info = Layout.info(world)
	local data = Worlds.get(world)
	local o = info.origin
	local t = data.terrain
	local land = Color.material(t.land, Enum.Material.Grass)
	local beach = Color.material(t.beach, Enum.Material.Sand)
	local rock = Color.material(t.rock, Enum.Material.Rock)
	local floor = Color.material(t.floor, Enum.Material.Sand)
	local deep = Color.material(t.deep, Enum.Material.Slate)
	local R, D, Ri = info.radius, info.depth, info.islandRadius
	local landY = info.landY

	-- Solid rock core and a sloped sandy shoreline skirt.
	cylinder(o, Ri + 16, -Config.OceanDepth - 2, -9, beach)
	cylinder(o, Ri + 8, -9, -3, beach)
	cylinder(o, Ri + 3, -3, 1, beach)
	cylinder(o, Ri, -(D + 18), landY, rock)
	cylinder(o, Ri - 5, landY - 3, landY, land)
	for i = 1, 30 do
		local a = (i / 30) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local r = Ri + rng:NextNumber(-3, 5)
		terrain:FillBall(o + Vector3.new(math.cos(a) * r, rng:NextNumber(-3, -1), math.sin(a) * r), rng:NextNumber(6, 10), beach)
	end
	task.wait()

	-- Backdrop hills around the far side (the dock faces +Z, so keep that sector open).
	local kit = data.kit
	local hillMaterial = if kit == "ice" then Enum.Material.Glacier else rock
	local capMaterial = if kit == "ice" then Enum.Material.Snow elseif kit == "volcanic" or kit == "maw" or kit == "trench" then rock else land
	for i = 1, 16 do
		local a = math.rad(rng:NextNumber(140, 400))
		local r = Ri - rng:NextNumber(12, 26)
		local size = rng:NextNumber(14, 26)
		local base = o + Vector3.new(math.cos(a) * r, landY + rng:NextNumber(0, 10), math.sin(a) * r)
		terrain:FillBall(base, size, hillMaterial)
		if capMaterial ~= hillMaterial then
			terrain:FillBall(base + Vector3.new(0, size * 0.35, 0), size * 0.72, capMaterial)
		end
	end
	if kit == "volcanic" then
		-- A volcano cone behind the lagoon.
		local cone = o + Vector3.new(0, 0, -(Ri - 20))
		for step = 0, 7 do
			cylinder(cone, 46 - step * 5.5, landY + step * 7, landY + step * 7 + 8, rock)
		end
		cylinder(cone, 9, landY + 44, landY + 58, AIR)
		cylinder(cone, 9, landY + 40, landY + 45, Enum.Material.CrackedLava)
	elseif kit == "ice" or kit == "crystal" or kit == "trench" or kit == "maw" then
		-- Tall jagged cliffs.
		for i = 1, 9 do
			local a = math.rad(160 + i * 25 + rng:NextNumber(-8, 8))
			local r = Ri - 14
			local base = o + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			cylinder(base, rng:NextNumber(10, 16), landY, landY + rng:NextNumber(26, 48), hillMaterial)
		end
	end
	task.wait()

	-- Lagoon: shelf, middle terrace and deep pit, each with its own floor layer.
	cylinder(o, R, -info.shelfDepth, 0, WATER)
	cylinder(o, R, 0, landY + 12, AIR)
	cylinder(o, R, -info.shelfDepth - 2, -info.shelfDepth, floor)
	cylinder(o, info.midRadius, -info.midDepth, -info.shelfDepth + 1, WATER)
	cylinder(o, info.midRadius, -info.midDepth - 2, -info.midDepth, floor)
	cylinder(o, info.deepRadius, -D, -info.midDepth + 1, WATER)
	cylinder(o, info.deepRadius, -D - 3, -D, deep)

	-- Rugged walls: rocks jutting in around every terrace edge.
	local rings = {
		{ radius = R, top = 0, bottom = -info.shelfDepth, count = 22, size = { 4, 7 } },
		{ radius = info.midRadius, top = -info.shelfDepth, bottom = -info.midDepth, count = 16, size = { 4, 8 } },
		{ radius = info.deepRadius, top = -info.midDepth, bottom = -D, count = 12, size = { 4, 7 } },
	}
	for _, ring in rings do
		for i = 1, ring.count do
			local a = (i / ring.count) * math.pi * 2 + rng:NextNumber(-0.12, 0.12)
			-- Keep the beach inlet clear.
			if not (ring.radius == R and math.abs(math.cos(a)) < 0.3 and math.sin(a) > 0) then
				local r = ring.radius + rng:NextNumber(0, 3)
				local y = rng:NextNumber(ring.bottom, ring.top)
				terrain:FillBall(o + Vector3.new(math.cos(a) * r, y, math.sin(a) * r), rng:NextNumber(ring.size[1], ring.size[2]), rock)
			end
		end
	end
	-- Floor mounds so the bottom is not perfectly flat.
	local mounds = {
		{ inner = info.midRadius + 3, outer = R - 4, y = -info.shelfDepth, material = floor, count = 14 },
		{ inner = info.deepRadius + 3, outer = info.midRadius - 3, y = -info.midDepth, material = floor, count = 10 },
		{ inner = 0, outer = info.deepRadius - 4, y = -D, material = deep, count = 7 },
	}
	for _, ring in mounds do
		for _ = 1, ring.count do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(ring.inner, math.max(ring.inner + 1, ring.outer))
			terrain:FillBall(o + Vector3.new(math.cos(a) * r, ring.y - rng:NextNumber(2, 3.5), math.sin(a) * r), rng:NextNumber(3, 6), ring.material)
		end
	end
	task.wait()

	-- Beach inlet on the dock side: carve, then lay a sandy ramp down into the shelf.
	block(o + Vector3.new(0, -6, R + 4), Vector3.new(42, 12, 22), WATER)
	block(o + Vector3.new(0, 6, R + 4), Vector3.new(42, 12, 22), AIR)
	terrain:FillWedge(CFrame.new(o + Vector3.new(0, -4, R + 4)), Vector3.new(42, 12, 22), beach)
	block(o + Vector3.new(0, -12, R + 4), Vector3.new(42, 4, 22), beach)
end

-- Server-side default palette (clients re-apply per world as they travel).
function TerrainBuilder.applyPalette(world: number)
	local t = Worlds.get(world).terrain
	for _, pair in { { t.land, t.landColor }, { t.beach, t.beachColor }, { t.rock, t.rockColor }, { t.floor, t.floorColor }, { t.deep, t.deepColor } } do
		local material = Color.material(pair[1], Enum.Material.Sand)
		terrain:SetMaterialColor(material, Color.hex(pair[2]))
	end
	terrain.WaterColor = Color.hex(Worlds.get(world).water)
end

return TerrainBuilder
