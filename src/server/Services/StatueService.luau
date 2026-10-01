--!strict
-- Podium statues behind each dock's ranking board: gold / silver / bronze podiums carry the top
-- 3 of every board (weekly, monthly, all-time) at once, and each client shows only the board it
-- picked on the dock board. The Director stands big beside the gear shop kiosk. Avatars are built from
-- each player's own outfit and prebuilt as soon as the rankings name them. Only worlds someone is
-- in get statues. Names and tier progress are podium attributes; clients draw the labels.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Build = require(Shared.Models.Build)
local Layout = require(Shared.Layout)
local Operators = require(Shared.Operators)
local Rankings = require(Shared.Rankings)

local Sessions = require(script.Parent.Parent.Sessions)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)
local LeaderboardService = require(script.Parent.LeaderboardService)

local StatueService = {}

local V = Vector3.new
local cf = CFrame.new

local PODIUMS = {
	-- rank, sideways offset (board space; + is the viewer's left), podium height, colour
	{ rank = 1, x = 0, height = 4.5, color = Color3.fromRGB(255, 205, 64) },
	{ rank = 2, x = 7.5, height = 3.2, color = Color3.fromRGB(205, 216, 228) },
	{ rank = 3, x = -7.5, height = 2.2, color = Color3.fromRGB(214, 140, 84) },
}
local PODIUM_SCALE = 1.25
local DIRECTOR_SCALE = 2.4

type Slot = { podium: BasePart, users: { [string]: number? }, scale: number }
type WorldStatues = { slots: { [number]: Slot }, director: Slot?, at: number }

local templates: { [number]: Model } = {}
local failed: { [number]: boolean } = {}
local building: { [number]: boolean } = {}
local placed: { [number]: WorldStatues } = {}
local cache: Folder

-- Starts building the avatar for `userId` (once); returns it when ready.
local function template(userId: number): Model?
	local existing = templates[userId]
	if existing or failed[userId] then
		return existing
	end
	if not building[userId] then
		building[userId] = true
		task.spawn(function()
			local ok, model = pcall(function()
				return Players:CreateHumanoidModelFromUserIdAsync(userId)
			end)
			if ok and model then
				for _, d in model:GetDescendants() do
					if d:IsA("Script") or d:IsA("LocalScript") then
						d:Destroy()
					end
				end
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				end
				model.Name = "Avatar_" .. userId
				model.Parent = cache
				templates[userId] = model
			else
				failed[userId] = true
			end
			building[userId] = nil
		end)
	end
	return nil
end

local directorNames: { [number]: string } = {}
local function directorName(userId: number): string?
	if directorNames[userId] == nil then
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		directorNames[userId] = if ok and type(name) == "string" then name else ""
	end
	local name = directorNames[userId]
	return if name ~= "" then name else nil
end

local function groundY(position: Vector3, fallback: number, ignore: Instance): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }
	local hit = Workspace:Raycast(position + V(0, 40, 0), V(0, -80, 0), params)
	return if hit then hit.Position.Y else fallback
end

local function podium(folder: Folder, at: CFrame, size: number, height: number, color: Color3, name: string): BasePart
	local base = Build.block(folder, V(size, height, size), at * cf(0, height / 2, 0), color)
	base.Name = name
	base.Material = Enum.Material.Marble
	base.CanCollide = true
	base.CanQuery = true
	local trim = Build.block(folder, V(size + 0.6, 0.5, size + 0.6), at * cf(0, height + 0.25, 0), Color3.fromRGB(250, 250, 255))
	trim.CanCollide = true
	return base
end

local function build(world: number): WorldStatues?
	local built = WorldBuilder.get(world)
	if not built then
		return nil
	end
	local info = Layout.info(world)
	local dock = Layout.dock(world)
	local o = info.origin
	local spawnFlat = o + V(dock.spawn.X, info.landY, dock.spawn.Z)
	local folder = Instance.new("Folder")
	folder.Name = "Statues"
	folder.Parent = built.folder

	local boardAt = CFrame.lookAt(o + V(dock.board.X, info.landY, dock.board.Z), spawnFlat)
	-- Left of the board as you face it from the spawn, and a little further back.
	local center = boardAt * cf(24, 0, 10)
	local slots: { [number]: Slot } = {}
	for _, spec in PODIUMS do
		local spot = center * cf(spec.x, 0, 0)
		local y = groundY(spot.Position, info.landY, built.folder)
		local at = CFrame.lookAt(V(spot.X, y, spot.Z), V(spawnFlat.X, y, spawnFlat.Z))
		local part = podium(folder, at, 6, spec.height, spec.color, "Podium" .. spec.rank)
		part:SetAttribute("Rank", spec.rank)
		slots[spec.rank] = { podium = part, users = {}, scale = PODIUM_SCALE }
	end

	-- The Director, big, beside the gear shop kiosk with room to walk between them.
	local director: Slot? = nil
	if Operators.list()[1] then
		local kiosk = CFrame.lookAt(o + V(dock.kiosk.X, info.landY, dock.kiosk.Z), spawnFlat)
		local spot = (kiosk * cf(-17, 0, 2)).Position
		local y = groundY(spot, info.landY, built.folder)
		local at = CFrame.lookAt(V(spot.X, y, spot.Z), V(spawnFlat.X, y, spawnFlat.Z))
		local part = podium(folder, at, 9, 3, Color3.fromRGB(24, 18, 22), "DirectorPodium")
		local glow = Build.block(folder, V(9.4, 0.3, 9.4), at * cf(0, 0.15, 0), Color3.fromRGB(255, 40, 60))
		glow.Material = Enum.Material.Neon
		part:SetAttribute("Rank", 0)
		director = { podium = part, users = {}, scale = DIRECTOR_SCALE }
	end
	return { slots = slots, director = director, at = -1 }
end

-- Stands `userId`'s avatar on the podium as `name` (or clears it). Only the root is anchored, so
-- the avatar's joints assemble it in place instead of leaving its parts scattered. Returns false
-- while the avatar is still being built.
local function stand(slot: Slot, key: string, userId: number?): boolean
	local name = "Statue_" .. key
	local old = slot.podium:FindFirstChild(name)
	if slot.users[key] == userId and (old or not userId) then
		return true
	end
	if old then
		old:Destroy()
	end
	slot.users[key] = nil
	if not userId then
		return true
	end
	local source = template(userId)
	if not source then
		return failed[userId] == true
	end
	local statue = source:Clone()
	statue.Name = name
	statue:SetAttribute("Board", key)
	local root = statue:FindFirstChild("HumanoidRootPart") :: BasePart?
	for _, d in statue:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == root
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	pcall(function()
		statue:ScaleTo(slot.scale)
	end)
	local humanoid = statue:FindFirstChildOfClass("Humanoid")
	local lift = (if humanoid then humanoid.HipHeight else 2) + (if root then root.Size.Y / 2 else 1)
	local top = slot.podium.CFrame * cf(0, slot.podium.Size.Y / 2 + 0.5 + lift, 0)
	if root then
		statue.PrimaryPart = root
	end
	statue:PivotTo(top)
	statue.Parent = slot.podium
	slot.users[key] = userId
	return true
end

-- Board-namespaced labels ("weekly_Display", ...) so each client reads the board it picked.
local function label(part: BasePart, prefix: string, entry: any?)
	part:SetAttribute(prefix .. "UserId", if entry then entry.u else nil)
	part:SetAttribute(prefix .. "Display", if entry then entry.d else nil)
	part:SetAttribute(prefix .. "Username", if entry then entry.n else nil)
	part:SetAttribute(prefix .. "NextTier", if entry then entry.nt else nil)
	part:SetAttribute(prefix .. "NextSeconds", if entry then entry.ns else nil)
end

local function update(world: number, data: any)
	local statues = placed[world]
	if not statues then
		local made = build(world)
		if not made then
			return
		end
		statues = made
		placed[world] = made
	end
	local fresh = statues.at ~= data.at
	local done = true
	for _, board in Rankings.Boards do
		local section = data.boards and data.boards[board]
		local entries = if section and type(section.entries) == "table" then section.entries else {}
		for rank, slot in statues.slots do
			local entry = entries[rank]
			done = stand(slot, board, if entry then entry.u else nil) and done
			if fresh then
				label(slot.podium, board .. "_", entry)
			end
		end
	end
	local director = statues.director
	if director then
		local id = Operators.list()[1]
		stand(director, "director", id)
		if fresh or director.podium:GetAttribute("Username") == nil then
			local entry = data.directors and data.directors.alltime
			local username = if entry then entry.n else directorName(id)
			label(director.podium, "", { u = id, d = if entry then entry.d else username, n = username })
		end
	end
	if fresh and done then
		statues.at = data.at
	end
end

-- Builds every avatar the rankings name (and the Director's) ahead of time.
local function preload(data: any)
	local first = Operators.list()[1]
	if first then
		template(first)
	end
	for _, board in Rankings.Boards do
		local section = data.boards and data.boards[board]
		local entries = if section and type(section.entries) == "table" then section.entries else {}
		for rank = 1, math.min(3, #entries) do
			template(entries[rank].u)
		end
	end
end

function StatueService.init()
	cache = Instance.new("Folder")
	cache.Name = "DeepDiveStatues"
	cache.Parent = ServerStorage
	task.spawn(function()
		while true do
			local data = LeaderboardService.latest()
			preload(data)
			local occupied: { [number]: boolean } = {}
			for _, session in Sessions.all() do
				if session.ready then
					occupied[session.world] = true
				end
			end
			for world in occupied do
				local ok, err = pcall(function()
					update(world, data)
				end)
				if not ok then
					warn("[DeepDive] Statues for world " .. world .. " failed: " .. tostring(err))
				end
			end
			task.wait(0.5)
		end
	end)
end

return StatueService
