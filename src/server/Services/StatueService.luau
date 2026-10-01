--!strict
-- Podium statues: the top 3 of whichever ranking board is on display stand on gold / silver /
-- bronze podiums behind each dock's board (switching with the board every
-- Config.BoardRotateSeconds), and the Director stands on a red podium beside the egg stand.
-- Avatars are built from each player's own outfit. Only worlds someone is in get statues.
-- The podiums carry the names and tier progress as attributes; clients draw the labels.

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
local STATUE_SCALE = 1.25

type Slot = { podium: BasePart, userId: number? }
type WorldStatues = { folder: Folder, slots: { [number]: Slot }, director: Slot?, board: string, at: number }

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
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
					elseif d:IsA("Script") or d:IsA("LocalScript") then
						d:Destroy()
					end
				end
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				end
				pcall(function()
					model:ScaleTo(STATUE_SCALE)
				end)
				model.Name = "Statue_" .. userId
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

local function podium(folder: Folder, at: CFrame, height: number, color: Color3, name: string): BasePart
	local base = Build.block(folder, V(6, height, 6), at * cf(0, height / 2, 0), color)
	base.Name = name
	base.Material = Enum.Material.Marble
	base.CanCollide = true
	base.CanQuery = true
	local trim = Build.block(folder, V(6.6, 0.5, 6.6), at * cf(0, height + 0.25, 0), Color3.fromRGB(250, 250, 255))
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
		local part = podium(folder, at, spec.height, spec.color, "Podium" .. spec.rank)
		part:SetAttribute("Rank", spec.rank)
		slots[spec.rank] = { podium = part, userId = nil }
	end

	-- The Director's podium beside the egg stand.
	local director: Slot? = nil
	if Operators.list()[1] then
		local spot = o + V(dock.egg.X - 10, info.landY, dock.egg.Z - 1)
		local y = groundY(spot, info.landY, built.folder)
		local at = CFrame.lookAt(V(spot.X, y, spot.Z), V(spawnFlat.X, y, spawnFlat.Z))
		local part = podium(folder, at, 3, Color3.fromRGB(24, 18, 22), "DirectorPodium")
		local glow = Build.block(folder, V(6.2, 0.3, 6.2), at * cf(0, 0.15, 0), Color3.fromRGB(255, 40, 60))
		glow.Material = Enum.Material.Neon
		part:SetAttribute("Rank", 0)
		director = { podium = part, userId = nil }
	end
	return { folder = folder, slots = slots, director = director, board = "", at = -1 }
end

-- Puts `userId`'s statue on the podium (or clears it). Retries later while the avatar builds.
local function stand(slot: Slot, userId: number?): boolean
	local old = slot.podium:FindFirstChild("Statue")
	if slot.userId == userId and (old or not userId) then
		return true
	end
	if old then
		old:Destroy()
	end
	slot.userId = nil
	if not userId then
		return true
	end
	local source = template(userId)
	if not source then
		return failed[userId] == true
	end
	local statue = source:Clone()
	statue.Name = "Statue"
	local _, size = statue:GetBoundingBox()
	local top = slot.podium.CFrame * cf(0, slot.podium.Size.Y / 2 + 0.5 + size.Y / 2, 0)
	statue:PivotTo(top)
	statue.Parent = slot.podium
	slot.userId = userId
	return true
end

local function label(slot: Slot, entry: any?, board: string)
	local part = slot.podium
	part:SetAttribute("Board", board)
	part:SetAttribute("UserId", if entry then entry.u else nil)
	part:SetAttribute("Display", if entry then entry.d else nil)
	part:SetAttribute("Username", if entry then entry.n else nil)
	part:SetAttribute("NextTier", if entry then entry.nt else nil)
	part:SetAttribute("NextSeconds", if entry then entry.ns else nil)
end

local function update(world: number)
	local statues = placed[world]
	if not statues then
		local made = build(world)
		if not made then
			return
		end
		statues = made
		placed[world] = made
	end
	local data = LeaderboardService.latest()
	local board = Rankings.boardAt(os.time())
	local section = data.boards and data.boards[board]
	local entries = if section and type(section.entries) == "table" then section.entries else {}
	local fresh = statues.board ~= board or statues.at ~= data.at
	for rank, slot in statues.slots do
		local entry = entries[rank]
		local done = stand(slot, if entry then entry.u else nil)
		if fresh then
			label(slot, entry, board)
		end
		if not done then
			fresh = false -- try again next tick while the avatar loads
		end
	end
	local director = statues.director
	if director then
		local id = Operators.list()[1]
		stand(director, id)
		if fresh or director.podium:GetAttribute("Username") == nil then
			local entry = data.directors and (data.directors[board] or data.directors.alltime)
			local username = if entry then entry.n else directorName(id)
			label(director, { u = id, d = if entry then entry.d else username, n = username }, "director")
		end
	end
	statues.board = board
	if fresh then
		statues.at = data.at
	end
end

function StatueService.init()
	cache = Instance.new("Folder")
	cache.Name = "DeepDiveStatues"
	cache.Parent = ServerStorage
	task.spawn(function()
		while true do
			task.wait(1)
			local occupied: { [number]: boolean } = {}
			for _, session in Sessions.all() do
				if session.ready then
					occupied[session.world] = true
				end
			end
			for world in occupied do
				local ok, err = pcall(function()
					update(world)
				end)
				if not ok then
					warn("[DeepDive] Statues for world " .. world .. " failed: " .. tostring(err))
				end
			end
		end
	end)
end

return StatueService
