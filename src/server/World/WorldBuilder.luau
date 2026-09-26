--!strict
-- Builds worlds on demand (terrain, decor, dock), then scans the finished lagoon for relic spawn
-- points, the Ancient Chest spot and hazard placements, published as JSON attributes.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Worlds = require(Shared.Data.Worlds)

local Decor = require(script.Parent.Decor)
local Dock = require(script.Parent.Dock)
local Terrain = require(script.Parent.Terrain)

local WorldBuilder = {}

export type Hazard = { kind: string, x: number, y: number, z: number, radius: number, range: number, speed: number, phase: number }

type Built = {
	folder: Folder,
	spawn: SpawnLocation,
	points: { Vector3 },
	depths: { number },
	chest: Vector3,
	hazards: { Hazard },
}

local root: Folder
local built: { [number]: Built } = {}
local building: { [number]: boolean } = {}

local POINT_COUNT = 30
local POINT_SPACING = 9

local function round(n: number): number
	return math.floor(n * 10 + 0.5) / 10
end

local function scanParams(world: Folder): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain, world }
	params.IgnoreWater = true
	return params
end

local function floorHit(world: number, params: RaycastParams, lx: number, lz: number): RaycastResult?
	local info = Layout.info(world)
	return Workspace:Raycast(info.origin + Vector3.new(lx, -0.6, lz), Vector3.new(0, -(info.depth + 24), 0), params)
end

local function scanPoints(world: number, folder: Folder, rng: Random): ({ Vector3 }, { number })
	local info = Layout.info(world)
	local params = scanParams(folder)
	local bands = {
		{ inner = info.midRadius + 1, outer = info.radius - 3, quota = math.floor(POINT_COUNT * 0.3) },
		{ inner = info.deepRadius + 1, outer = info.midRadius - 2, quota = math.floor(POINT_COUNT * 0.35) },
		{ inner = 2, outer = info.deepRadius - 3, quota = POINT_COUNT - math.floor(POINT_COUNT * 0.3) - math.floor(POINT_COUNT * 0.35) },
	}
	local points: { Vector3 } = {}
	local depths: { number } = {}
	for _, band in bands do
		local placed, attempts = 0, 0
		while placed < band.quota and attempts < 220 do
			attempts += 1
			local a = rng:NextNumber(0, math.pi * 2)
			local r = math.sqrt(rng:NextNumber((band.inner / band.outer) ^ 2, 1)) * band.outer
			local lx, lz = math.cos(a) * r, math.sin(a) * r
			local hit = floorHit(world, params, lx, lz)
			if hit then
				local p = hit.Position + hit.Normal * 1.7
				local depth = Config.SurfaceY - p.Y
				local farEnough = depth > 5
				if farEnough then
					for _, other in points do
						if (other - p).Magnitude < POINT_SPACING then
							farEnough = false
							break
						end
					end
				end
				if farEnough then
					table.insert(points, p)
					table.insert(depths, math.clamp(depth / info.depth, 0, 1))
					placed += 1
				end
			end
		end
	end
	return points, depths
end

local function scanChest(world: number, folder: Folder): Vector3
	local info = Layout.info(world)
	local params = scanParams(folder)
	local best: Vector3? = nil
	for _, offset in { Vector2.new(0, 0), Vector2.new(4, 0), Vector2.new(-4, 0), Vector2.new(0, 4), Vector2.new(0, -4) } do
		local hit = floorHit(world, params, offset.X, offset.Y)
		if hit and (not best or hit.Position.Y < best.Y) then
			best = hit.Position
		end
	end
	return (best or (info.origin + Vector3.new(0, -info.depth, 0))) + Vector3.new(0, 1.8, 0)
end

local function scanHazards(world: number, folder: Folder, rng: Random, points: { Vector3 }): { Hazard }
	local info = Layout.info(world)
	local data = Worlds.get(world)
	local params = scanParams(folder)
	local hazards: { Hazard } = {}
	local dockPoint = info.origin + Vector3.new(0, 0, info.radius)
	for _, spec in data.hazards do
		local placed, attempts = 0, 0
		while placed < spec.count and attempts < 80 do
			attempts += 1
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(6, info.radius - 6)
			local lx, lz = math.cos(a) * r, math.sin(a) * r
			local hit = floorHit(world, params, lx, lz)
			if hit then
				local floor = hit.Position
				local depth = Config.SurfaceY - floor.Y
				local p = floor
				local radius, range, speed = 1.8, 0, rng:NextNumber(0.6, 1.1)
				if spec.kind == "urchin" then
					p = floor + Vector3.new(0, 0.9, 0)
					radius = 1.6
				elseif spec.kind == "eel" then
					p = floor + Vector3.new(0, 2.2, 0)
					radius, range = 1.5, rng:NextNumber(7, 12)
				elseif spec.kind == "lava" then
					p = floor + Vector3.new(0, 0.5, 0)
					radius, range = 1.9, math.min(14, depth - 4)
				else
					local lift = rng:NextNumber(5, math.max(6, math.min(22, depth - 7)))
					p = floor + Vector3.new(0, lift, 0)
					range = if spec.kind == "jelly" then rng:NextNumber(2.5, 5) else rng:NextNumber(5, 9)
				end
				local ok = depth > 8 and (p - dockPoint).Magnitude > 26 and Config.SurfaceY - p.Y > 5
				if ok then
					for _, point in points do
						if (point - p).Magnitude < 6 then
							ok = false
							break
						end
					end
				end
				if ok then
					table.insert(hazards, {
						kind = spec.kind,
						x = round(p.X),
						y = round(p.Y),
						z = round(p.Z),
						radius = radius,
						range = round(range),
						speed = round(speed * 100) / 100,
						phase = round(rng:NextNumber(0, math.pi * 2)),
					})
					placed += 1
				end
			end
		end
	end
	return hazards
end

function WorldBuilder.init()
	-- Discards any edit-mode preview built by tools/studio-plugin so Play always starts from a
	-- clean, freshly generated Workspace instead of stacking a second copy on top of it.
	local preview = Workspace:FindFirstChild("Worlds")
	if preview then
		preview:Destroy()
	end

	root = Instance.new("Folder")
	root.Name = "Worlds"
	root.Parent = Workspace

	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.5
	clouds.Density = 0.6
	clouds.Parent = Workspace.Terrain

	local terrain = Workspace.Terrain
	terrain.WaterWaveSize = 0.18
	terrain.WaterWaveSpeed = 10
	terrain.WaterReflectance = 0.6
	terrain.WaterTransparency = 0.72
	Terrain.applyPalette(1)
end

local function build(world: number): Built
	local started = os.clock()
	local rng = Random.new(world * 104729 + 17)
	local folder = Instance.new("Folder")
	folder.Name = "World" .. world
	folder:SetAttribute("World", world)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = folder
	folder.Parent = root

	local ok, err = pcall(function()
		Terrain.buildOcean(world)
		task.wait()
		Terrain.buildIsland(world, rng)
		task.wait()
	end)
	if not ok then
		folder:Destroy()
		error(err, 0)
	end
	-- Decoration is cosmetic: a failure there must never make the world unplayable.
	local decorOk, decorErr = pcall(function()
		Decor.build(world, decor, rng)
	end)
	if not decorOk then
		warn(string.format("[DeepDive] World %d decor failed: %s", world, tostring(decorErr)))
	end
	task.wait()
	local spawnOk, spawn = pcall(Dock.build, world, folder)
	if not spawnOk then
		folder:Destroy()
		error(spawn, 0)
	end
	task.wait()

	local points, depths = scanPoints(world, folder, rng)
	local chest = scanChest(world, folder)
	local hazards = scanHazards(world, folder, rng, points)
	local encoded = {}
	for i, p in points do
		encoded[i] = { round(p.X), round(p.Y), round(p.Z) }
	end
	folder:SetAttribute("Points", HttpService:JSONEncode(encoded))
	folder:SetAttribute("Chest", HttpService:JSONEncode({ round(chest.X), round(chest.Y), round(chest.Z) }))
	folder:SetAttribute("Hazards", HttpService:JSONEncode(hazards))
	folder:SetAttribute("Ready", true)
	print(string.format("[DeepDive] World %d built in %.2fs (%d relic points, %d hazards)", world, os.clock() - started, #points, #hazards))
	return { folder = folder, spawn = spawn, points = points, depths = depths, chest = chest, hazards = hazards }
end

-- Yields until the world is built. Errors if the build fails (callers pcall where it matters).
function WorldBuilder.ensure(world: number): Built
	world = math.clamp(world, 1, Config.WorldCount)
	local existing = built[world]
	if existing then
		return existing
	end
	if building[world] then
		while building[world] do
			task.wait(0.1)
		end
		local finished = built[world]
		if not finished then
			error(string.format("World %d failed to build", world), 0)
		end
		return finished
	end
	building[world] = true
	local ok, result = pcall(build, world)
	building[world] = nil
	if not ok then
		warn(string.format("[DeepDive] World %d failed to build: %s", world, tostring(result)))
		error(result, 0)
	end
	built[world] = result
	return result
end

function WorldBuilder.get(world: number): Built?
	return built[world]
end

function WorldBuilder.buildRemaining()
	task.spawn(function()
		for world = 1, Config.WorldCount do
			if not built[world] then
				pcall(WorldBuilder.ensure, world)
				task.wait(0.25)
			end
		end
	end)
end

return WorldBuilder
