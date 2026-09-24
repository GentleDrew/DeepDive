--!strict
-- The dock on the lagoon rim: spawn deck, pier + diving board, egg stand, upgrade kiosk, travel
-- portal and the island boundary. Prompt UI and sign text are rendered by the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Build = require(Shared.Models.Build)
local Color = require(Shared.Color)
local Layout = require(Shared.Layout)
local RelicModels = require(Shared.Models.RelicModels)
local Worlds = require(Shared.Data.Worlds)

local Dock = {}

local V = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rad = math.rad

local WOOD = Color3.fromRGB(150, 104, 66)
local WOOD_DARK = Color3.fromRGB(104, 70, 44)

local function solid(part: BasePart): BasePart
	part.CanCollide = true
	part.CanQuery = true
	part.CastShadow = true
	return part
end

local function plankRow(parent: Instance, from: Vector3, to: Vector3, width: number, y: number)
	local dir = to - from
	local length = dir.Magnitude
	local count = math.max(1, math.floor(length / 2))
	local step = length / count
	local look = CFrame.lookAt(from, to).Rotation
	for i = 0, count - 1 do
		local center = from + dir.Unit * (step * (i + 0.5))
		local plank =
			Build.block(parent, V(width, 0.5, step - 0.15), cf(center.X, y, center.Z) * look, if i % 3 == 0 then Color.darken(WOOD, 0.08) else WOOD)
		plank.Material = Enum.Material.WoodPlanks
		solid(plank)
	end
end

local function prompt(parent: BasePart, kind: string, world: number, action: string, object: string, distance: number?)
	local p = Instance.new("ProximityPrompt")
	p.Name = kind .. "Prompt"
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = distance or 12
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Custom
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.GamepadKeyCode = Enum.KeyCode.ButtonX
	p:SetAttribute("Kind", kind)
	p:SetAttribute("World", world)
	p.Parent = parent
	return p
end

local function anchorPart(parent: Instance, name: string, at: CFrame, size: Vector3?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size or V(1, 1, 1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = at
	part.Parent = parent
	return part
end

local function lamp(parent: Instance, at: CFrame, color: Color3)
	Build.column(parent, 5, 0.3, at * cf(0, 2.5, 0), Color3.fromRGB(60, 56, 64))
	local head = Build.block(parent, V(1, 1.2, 1), at * cf(0, 5.4, 0), color)
	head.Material = Enum.Material.Neon
	Build.block(parent, V(1.4, 0.25, 1.4), at * cf(0, 6.1, 0), Color3.fromRGB(60, 56, 64))
	Build.light(head, color, 16, 1.2)
end

function Dock.build(world: number, parent: Instance): SpawnLocation
	local info = Layout.info(world)
	local data = Worlds.get(world)
	local o = info.origin
	local dock = Layout.dock(world)
	local accent = Color.hex(data.accent[1])
	local accent2 = Color.hex(data.accent[2])
	local landY = info.landY
	local folder = Instance.new("Folder")
	folder.Name = "Dock"
	folder.Parent = parent

	local function at(local3: Vector3, yOffset: number?): CFrame
		return cf(o + V(local3.X, local3.Y + (yOffset or 0), local3.Z))
	end
	local facing = ang(0, 0, 0) -- dock structures face -Z (toward the lagoon)

	-- Spawn deck with a glowing ring.
	local deck = Build.block(folder, V(20, 0.6, 22), at(dock.spawn, 0.25) * cf(0, 0, -2), WOOD)
	deck.Material = Enum.Material.WoodPlanks
	solid(deck)
	local pad = Build.column(folder, 0.3, 9, at(dock.spawn, 0.7), Color.lighten(accent, 0.6))
	pad.Material = Enum.Material.SmoothPlastic
	local ring = Build.column(folder, 0.32, 9.6, at(dock.spawn, 0.68), accent)
	ring.Material = Enum.Material.Neon
	-- Boardwalk to the beach and to the pier.
	plankRow(folder, o + V(0, 0, dock.spawn.Z - 12), o + V(0, 0, info.radius + 15), 8, landY + 0.25)
	plankRow(folder, o + V(10, 0, dock.spawn.Z - 6), o + V(dock.pierStart.X, 0, dock.pierStart.Z + 6), 5, landY + 0.25)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = V(8, 1, 8)
	spawn.CFrame = at(dock.spawn, 1.1) * facing
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Enabled = true
	spawn:SetAttribute("World", world)
	spawn.Parent = folder
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end

	-- Pier over the lagoon with posts, lamps and a diving board.
	local pierY = landY + 1.2
	plankRow(folder, o + V(dock.pierStart.X, 0, dock.pierStart.Z), o + V(dock.pierEnd.X, 0, dock.pierEnd.Z), 8, pierY)
	local z = dock.pierStart.Z
	while z >= dock.pierEnd.Z do
		for _, side in { -1, 1 } do
			local post = Build.column(folder, 14, 0.8, cf(o + V(dock.pierStart.X + side * 3.6, pierY - 7, z)), WOOD_DARK)
			solid(post)
		end
		z -= 7
	end
	for _, side in { -1, 1 } do
		lamp(folder, cf(o + V(dock.pierStart.X + side * 3.4, pierY + 0.25, dock.pierEnd.Z + 4)), Color3.fromRGB(255, 214, 140))
	end
	local boardBase = o + V(dock.pierEnd.X, pierY + 0.9, dock.pierEnd.Z - 5)
	local board = Build.block(folder, V(2.6, 0.4, 8), cf(boardBase) * ang(rad(-4), 0, 0), Color3.fromRGB(245, 248, 252))
	solid(board)
	local stripe = Build.block(folder, V(2.64, 0.42, 1), cf(boardBase) * ang(rad(-4), 0, 0) * cf(0, 0, -3.4), accent)
	solid(stripe)
	solid(Build.block(folder, V(2, 1.2, 1.4), cf(o + V(dock.pierEnd.X, pierY + 0.35, dock.pierEnd.Z - 1)), Color3.fromRGB(80, 90, 110)))

	-- Egg stand.
	local eggBase = at(dock.egg)
	local pedestal = Build.column(folder, 1.6, 7, eggBase * cf(0, 0.8, 0), Color3.fromRGB(245, 245, 250))
	solid(pedestal)
	local trim = Build.column(folder, 0.4, 7.4, eggBase * cf(0, 1.55, 0), accent)
	trim.Material = Enum.Material.Neon
	Build.column(folder, 0.9, 5.6, eggBase * cf(0, 2.0, 0), accent2)
	local egg = RelicModels.buildEgg(world, 5.2)
	egg.Name = "DisplayEgg"
	egg:PivotTo(eggBase * cf(0, 5.6, 0))
	egg:SetAttribute("Spin", 0.6)
	egg.Parent = folder
	local eggAnchor = anchorPart(folder, "EggAnchor", eggBase * cf(0, 5.6, 0), V(4, 5, 4))
	eggAnchor:SetAttribute("World", world)
	prompt(eggAnchor, "Egg", world, "Hatch", data.egg.name.en, 14)

	-- Upgrade kiosk: counter, posts and a striped awning.
	local spawnFlat = o + V(dock.spawn.X, landY, dock.spawn.Z)
	local kioskPosition = o + V(dock.kiosk.X, landY, dock.kiosk.Z)
	local kiosk = CFrame.lookAt(kioskPosition, spawnFlat)
	local counter = Build.block(folder, V(10, 3.4, 3.6), kiosk * cf(0, 1.7, 0), Color3.fromRGB(245, 240, 232))
	solid(counter)
	Build.block(folder, V(10.4, 0.4, 4), kiosk * cf(0, 3.6, 0), accent2)
	for _, x in { -4.6, 4.6 } do
		solid(Build.column(folder, 8, 0.6, kiosk * cf(x, 4, 1.4), Color3.fromRGB(245, 245, 250)))
	end
	for i = 0, 5 do
		local stripeColor = if i % 2 == 0 then accent else Color3.fromRGB(255, 255, 255)
		Build.wedge(folder, V(1.84, 1.4, 5), kiosk * cf(-4.6 + i * 1.84, 8.4, 0.4), stripeColor)
	end
	local kioskSign = Build.block(folder, V(7, 2.2, 0.3), kiosk * cf(0, 10.2, 1.2), Color3.fromRGB(40, 44, 60))
	kioskSign.Name = "KioskSign"
	kioskSign:SetAttribute("World", world)
	local kioskAnchor = anchorPart(folder, "KioskAnchor", kiosk * cf(0, 3, -2), V(8, 4, 3))
	prompt(kioskAnchor, "Kiosk", world, "Upgrades", "Dive Shop", 12)

	-- Travel portal behind the spawn.
	local portalPosition = o + V(dock.portal.X, landY, dock.portal.Z)
	local portal = CFrame.lookAt(portalPosition, spawnFlat)
	for i = 0, 19 do
		local a = i / 20 * math.pi * 2
		local seg = Build.block(
			folder,
			V(1.9, 1.6, 1.4),
			portal * cf(math.cos(a) * 6.4, 7.5 + math.sin(a) * 6.4, 0) * ang(0, 0, a),
			if i % 2 == 0 then Color3.fromRGB(245, 245, 250) else accent
		)
		solid(seg)
	end
	local swirl = Build.cylinder(folder, 0.4, 11.6, portal * cf(0, 7.5, 0) * ang(0, rad(90), 0), accent)
	swirl.Material = Enum.Material.Neon
	swirl.Transparency = 0.35
	swirl.Name = "PortalSwirl"
	swirl:SetAttribute("Spin", 1)
	Build.light(swirl, accent, 18, 1.5)
	for i = 0, 2 do
		local step = Build.block(folder, V(10 - i * 1.5, 0.5, 3.6 - i * 0.6), portal * cf(0, 0.25 + i * 0.5, 0), Color3.fromRGB(235, 235, 242))
		solid(step)
	end
	local portalAnchor = anchorPart(folder, "PortalAnchor", portal * cf(0, 4, 0), V(10, 8, 3))
	prompt(portalAnchor, "Portal", world, "Travel", "World Portal", 14)

	-- World sign facing the spawn.
	local signPosition = o + V(dock.spawn.X - 16, landY, dock.spawn.Z - 12)
	local signAt = CFrame.lookAt(signPosition, spawnFlat)
	for _, x in { -3.2, 3.2 } do
		solid(Build.column(folder, 6, 0.5, signAt * cf(x, 3, 0), WOOD_DARK))
	end
	local sign = Build.block(folder, V(8, 3.6, 0.4), signAt * cf(0, 5.2, 0), Color3.fromRGB(38, 42, 58))
	sign.Name = "WorldSign"
	sign:SetAttribute("World", world)
	solid(sign)
	local signTrim = Build.block(folder, V(8.4, 4, 0.3), signAt * cf(0, 5.2, 0.1), accent)
	signTrim.Material = Enum.Material.Neon

	-- Invisible boundary around the island so divers stay home.
	local walls = Instance.new("Folder")
	walls.Name = "Boundary"
	walls.Parent = parent
	local r = info.islandRadius - 4
	local segments = 40
	local width = 2 * math.pi * r / segments + 1
	for i = 0, segments - 1 do
		local a = i / segments * math.pi * 2
		local wall = Instance.new("Part")
		wall.Name = "Wall"
		wall.Size = V(width, 140, 2)
		wall.CFrame = CFrame.lookAt(o + V(math.cos(a) * r, 20, math.sin(a) * r), o + V(0, 20, 0))
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanQuery = false
		wall.CanTouch = false
		wall.Transparency = 1
		wall.Parent = walls
	end

	return spawn
end

return Dock
