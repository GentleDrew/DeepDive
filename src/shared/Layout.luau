--!strict
-- World geometry shared by the server builder and client systems. Every world is an island with
-- a terraced blue hole (lagoon) in the middle; the dock sits on the +Z rim of the lagoon.

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local Layout = {}

export type Info = {
	world: number,
	origin: Vector3,
	radius: number, -- lagoon rim radius (shelf)
	depth: number, -- deepest floor (studs below surface)
	shelfDepth: number,
	midRadius: number,
	midDepth: number,
	deepRadius: number,
	islandRadius: number,
	landY: number,
}

local cache: { [number]: Info } = {}

function Layout.origin(world: number): Vector3
	local col = (world - 1) % Config.WorldColumns
	local row = (world - 1) // Config.WorldColumns
	return Vector3.new(col * Config.WorldSpacing, Config.SurfaceY, row * Config.WorldSpacing)
end

function Layout.info(world: number): Info
	local cached = cache[world]
	if cached then
		return cached
	end
	local radius = Economy.lagoonRadius(world)
	local depth = Economy.depthStuds(world)
	local info: Info = {
		world = world,
		origin = Layout.origin(world),
		radius = radius,
		depth = depth,
		shelfDepth = math.floor(11 + (world - 1) * 0.25),
		midRadius = math.floor(radius * 0.7),
		midDepth = math.floor(depth * 0.58),
		deepRadius = math.floor(radius * 0.44),
		islandRadius = radius + 66,
		landY = 2,
	}
	cache[world] = info
	return info
end

-- World-space point from lagoon-local coordinates.
function Layout.at(world: number, x: number, y: number, z: number): Vector3
	return Layout.origin(world) + Vector3.new(x, y, z)
end

function Layout.spawnCFrame(world: number): CFrame
	local info = Layout.info(world)
	local position = Layout.at(world, 0, info.landY + 4.6, info.radius + 30)
	return CFrame.lookAt(position, Layout.at(world, 0, info.landY + 4.6, 0))
end

-- Dock anchor points (lagoon-local offsets are relative to the dock centre at the +Z rim).
function Layout.dock(world: number)
	local info = Layout.info(world)
	local r = info.radius
	return {
		spawn = Vector3.new(0, info.landY, r + 30),
		egg = Vector3.new(-26, info.landY, r + 22),
		kiosk = Vector3.new(26, info.landY, r + 26),
		portal = Vector3.new(0, info.landY, r + 50),
		pierStart = Vector3.new(38, info.landY, r + 14),
		pierEnd = Vector3.new(38, info.landY, r - 26),
		sell = Vector3.new(-46, info.landY, r + 34),
		board = Vector3.new(48, info.landY, r + 46),
		beachHalfWidth = 20,
	}
end

function Layout.horizontalDistance(world: number, position: Vector3): number
	local origin = Layout.origin(world)
	local dx, dz = position.X - origin.X, position.Z - origin.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- True if the position is over the lagoon water (including the beach inlet).
function Layout.overLagoon(world: number, position: Vector3): boolean
	local info = Layout.info(world)
	local origin = info.origin
	local lx, lz = position.X - origin.X, position.Z - origin.Z
	if lx * lx + lz * lz <= (info.radius + 1.5) ^ 2 then
		return true
	end
	-- Beach inlet on the dock side.
	return math.abs(lx) <= 21 and lz >= info.radius - 2 and lz <= info.radius + 14
end

-- Conservative swimmable radius at a depth (the terraces narrow as you go down).
function Layout.radiusAtDepth(world: number, depth: number): number
	local info = Layout.info(world)
	if depth <= info.shelfDepth - 1 then
		return info.radius - 1.5
	elseif depth <= info.midDepth - 1 then
		return info.midRadius - 1.5
	end
	return info.deepRadius - 1.5
end

-- Which world an arbitrary position belongs to (nearest island), or nil when far away.
function Layout.worldAt(position: Vector3): number?
	local col = math.floor(position.X / Config.WorldSpacing + 0.5)
	local row = math.floor(position.Z / Config.WorldSpacing + 0.5)
	if col < 0 or col >= Config.WorldColumns or row < 0 then
		return nil
	end
	local world = row * Config.WorldColumns + col + 1
	if world > Config.WorldCount then
		return nil
	end
	return world
end

function Layout.depthOf(position: Vector3): number
	return Config.SurfaceY - position.Y
end

return Layout
