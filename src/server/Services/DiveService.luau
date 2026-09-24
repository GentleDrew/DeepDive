--!strict
-- Authoritative dive loop: detects diving/surfacing from the character position, drains oxygen
-- with depth pressure, validates relic pickups, auto-sells on surfacing, handles blackouts, the
-- Ancient Chest, world clears and travel between worlds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Layout = require(Shared.Layout)
local Profile = require(Shared.Profile)
local Remotes = require(Shared.Remotes)
local Worlds = require(Shared.Data.Worlds)

local Net = require(script.Parent.Parent.Net)
local Sessions = require(script.Parent.Parent.Sessions)
local Sync = require(script.Parent.Parent.Sync)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)

local DiveService = {}

type Session = Sessions.Session

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function aliveHumanoid(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function capacity(session: Session): number
	return Economy.upgradeValue("pack", session.profile.upgrades.pack)
end

local function magnet(session: Session): number
	return Economy.upgradeValue("magnet", session.profile.upgrades.magnet)
end

function DiveService.rollLayout(session: Session)
	local built = WorldBuilder.get(session.world)
	if not built then
		return
	end
	session.layoutId += 1
	session.relics = {}
	local count = #built.points
	local order = table.create(count)
	for i = 1, count do
		order[i] = i
	end
	for i = count, 2, -1 do
		local j = session.rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local data = Worlds.get(session.world)
	local list: { any } = {}
	for n = 1, math.min(Config.Dive.ActiveRelics, count) do
		local index = order[n]
		local rarity = Economy.rollRarity(built.depths[index] * 0.95, session.rng:NextNumber())
		local key = data.relics[rarity].key
		session.relics[index] = key
		table.insert(list, { index, key } :: { any })
	end
	local progress = Profile.progress(session.profile, session.world)
	session.chestActive = not progress.cleared and progress.sold >= Economy.goal(session.world)
	session.chestCarried = false
	Net.push(session.player, "layout", { id = session.layoutId, world = session.world, relics = list, chest = session.chestActive })
end

local function startDive(session: Session)
	local profile = session.profile
	session.mode = "Diving"
	session.oxygenMax = Economy.upgradeValue("tank", profile.upgrades.tank)
	session.oxygen = session.oxygenMax
	session.cargo = {}
	session.surfacedFor = 0
	session.syncTimer = 0
	session.maxDepth = 0
	session.chestCarried = false
	profile.stats.dives += 1
	if profile.tutorial == 1 then
		profile.tutorial = 2
		Sync.profile(session)
	end
	Net.push(session.player, "dive", { state = "start", oxygen = session.oxygen, max = session.oxygenMax, layout = session.layoutId })
end

local function clearWorld(session: Session): { [string]: any }
	local profile = session.profile
	local world = session.world
	local progress = Profile.progress(profile, world)
	progress.cleared = true
	local reward = Economy.clearReward(world)
	profile.coins += reward
	profile.lifetime += reward
	local nextWorld = nil
	if world < Config.WorldCount and profile.unlocked <= world then
		profile.unlocked = world + 1
		nextWorld = world + 1
	end
	return { world = world, reward = reward, nextWorld = nextWorld, all = world == Config.WorldCount }
end

-- reason: "surface" | "blackout" | "died" | "leave"
local function endDive(session: Session, reason: string)
	if session.mode ~= "Diving" and session.mode ~= "Rescue" then
		return
	end
	local profile = session.profile
	local world = session.world
	local cargo = session.cargo
	local rescued = reason == "blackout" or reason == "died"
	-- Leaving mid-dive settles like a rescue so quitting is never better than surfacing.
	local penalised = rescued or reason == "leave"
	local keep = if penalised then Config.Dive.BlackoutKeep else 1
	local total = 0
	local discovered = {}
	for _, key in cargo do
		total += Economy.relicValueByKey(key)
		if (profile.relics[key] or 0) == 0 and not table.find(discovered, key) then
			table.insert(discovered, key)
		end
		profile.relics[key] = (profile.relics[key] or 0) + 1
	end
	local payout = math.floor(total * Sessions.multiplier(session) * keep)
	local counted = if penalised then math.floor(#cargo * keep) else #cargo
	profile.coins += payout
	profile.lifetime += payout
	profile.stats.relics += #cargo
	local progress = Profile.progress(profile, world)
	local goal = Economy.goal(world)
	local wasReady = progress.sold >= goal
	progress.sold += counted
	local meters = Economy.displayMeters(world, session.maxDepth)
	local record = nil
	if meters > progress.best then
		progress.best = meters
		if meters >= 10 then
			record = meters
		end
	end
	local carried = session.chestCarried
	local cleared = nil
	if carried and not rescued and not progress.cleared then
		cleared = clearWorld(session)
	end
	if rescued then
		profile.stats.blackouts += 1
	end
	if profile.tutorial == 2 and #cargo > 0 then
		profile.tutorial = 3
	end
	if profile.tutorial == 3 and not rescued and #cargo > 0 then
		profile.tutorial = 4
	end

	session.mode = "Dock"
	session.oxygen = session.oxygenMax
	session.cargo = {}
	session.chestCarried = false

	Net.push(session.player, "sold", {
		payout = payout,
		count = #cargo,
		keys = cargo,
		rescued = rescued,
		chest = carried and not rescued,
		chestLost = carried and rescued,
		record = record,
		discovered = discovered,
		progress = progress.sold,
		goal = goal,
		chestReady = not wasReady and progress.sold >= goal and not progress.cleared,
	})
	if cleared then
		Net.push(session.player, "cleared", cleared)
	end
	Sync.profile(session)
	DiveService.rollLayout(session)
end

local function blackout(session: Session)
	if session.mode ~= "Diving" then
		return
	end
	session.mode = "Rescue"
	Net.push(session.player, "dive", { state = "blackout" })
	task.delay(1.5, function()
		if Sessions.get(session.player) ~= session then
			return
		end
		local character = session.player.Character
		if character and aliveHumanoid(session.player) then
			character:PivotTo(Layout.spawnCFrame(session.world))
		end
		endDive(session, "blackout")
	end)
end

local function tick(session: Session, dt: number)
	if session.mode == "Travel" or session.mode == "Rescue" then
		return
	end
	local root = rootOf(session.player)
	if not root or not aliveHumanoid(session.player) then
		return
	end
	local position = root.Position
	local depth = Config.SurfaceY - position.Y
	if session.mode == "Dock" then
		if depth >= Config.Dive.SubmergeDepth and Layout.overLagoon(session.world, position) then
			startDive(session)
		end
		return
	end
	-- Diving
	local d = math.max(0, depth)
	session.oxygen -= Economy.oxygenDrain(session.world, d) * dt
	if d > session.maxDepth then
		session.maxDepth = d
	end
	if session.oxygen <= 0 then
		session.oxygen = 0
		blackout(session)
		return
	end
	if depth < Config.Dive.SurfaceDepth then
		session.surfacedFor += dt
		if session.surfacedFor >= Config.Dive.SurfaceHold then
			endDive(session, "surface")
			return
		end
	else
		session.surfacedFor = 0
	end
	session.syncTimer += dt
	if session.syncTimer >= 1.5 then
		session.syncTimer = 0
		Net.push(session.player, "oxygen", { value = session.oxygen, max = session.oxygenMax })
	end
end

local function reject(session: Session, point: number, reason: string)
	Net.push(session.player, "reject", { point = point, reason = reason, layout = session.layoutId })
end

local function onCollect(player: Player, layoutId: any, point: any)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return
	end
	if type(layoutId) ~= "number" or type(point) ~= "number" or point ~= point then
		return
	end
	point = math.floor(point)
	if layoutId ~= session.layoutId or session.mode == "Rescue" or session.mode == "Travel" then
		reject(session, point, "stale")
		return
	end
	local root = rootOf(player)
	local built = WorldBuilder.get(session.world)
	if not root or not built or not aliveHumanoid(player) then
		reject(session, point, "stale")
		return
	end
	local reach = magnet(session) + Config.Dive.CollectTolerance
	local target = if point == 0 then built.chest else built.points[point]
	if not target then
		reject(session, point, "gone")
		return
	end
	if (root.Position - target).Magnitude > reach + (if point == 0 then 3 else 0) then
		reject(session, point, "far")
		return
	end
	if point == 0 then
		if not session.chestActive or session.chestCarried then
			reject(session, point, "gone")
			return
		end
	else
		if not session.relics[point] then
			reject(session, point, "gone")
			return
		end
		if #session.cargo >= capacity(session) then
			reject(session, point, "full")
			return
		end
	end
	if session.mode == "Dock" then
		local depth = Config.SurfaceY - root.Position.Y
		if depth < 0.5 or not Layout.overLagoon(session.world, root.Position) then
			reject(session, point, "far")
			return
		end
		startDive(session)
	end
	if point == 0 then
		session.chestCarried = true
		Net.push(player, "collected", { point = 0, chest = true, cargo = #session.cargo })
		return
	end
	local key = session.relics[point]
	session.relics[point] = nil
	table.insert(session.cargo, key)
	Net.push(player, "collected", { point = point, key = key, cargo = #session.cargo, capacity = capacity(session) })
end

local function onHazard(player: Player, index: any)
	local session = Sessions.get(player)
	if not session or session.mode ~= "Diving" or type(index) ~= "number" then
		return
	end
	local built = WorldBuilder.get(session.world)
	if not built or not built.hazards[math.floor(index)] then
		return
	end
	local now = os.clock()
	if now - session.lastHazard < Config.Dive.HazardImmunity then
		return
	end
	session.lastHazard = now
	session.oxygen = math.max(0, session.oxygen - Config.Dive.HazardPenalty)
	Net.push(player, "oxygen", { value = session.oxygen, max = session.oxygenMax, hit = true })
end

-- Travel ---------------------------------------------------------------------------------------

function DiveService.teleport(session: Session, world: number): (boolean, string?)
	if session.busy then
		return false, "err.busy"
	end
	if world < 1 or world > session.profile.unlocked then
		return false, "err.locked"
	end
	if session.mode ~= "Dock" then
		return false, "err.diving"
	end
	session.busy = true
	session.mode = "Travel"
	Net.push(session.player, "travel", { state = "start", world = world })
	local ok, built = pcall(WorldBuilder.ensure, world)
	if not ok or not built then
		session.mode = "Dock"
		session.busy = false
		Net.push(session.player, "travel", { state = "failed", world = session.world })
		return false, "err.generic"
	end
	session.world = world
	session.profile.world = world
	session.player:SetAttribute("World", world)
	session.player.RespawnLocation = built.spawn
	local character = session.player.Character
	if character then
		character:PivotTo(Layout.spawnCFrame(world))
	end
	task.wait(0.2)
	session.mode = "Dock"
	session.busy = false
	DiveService.rollLayout(session)
	Sync.profile(session)
	Net.push(session.player, "travel", { state = "done", world = world })
	return true, nil
end

function DiveService.onDied(session: Session)
	if session.mode == "Diving" or session.mode == "Rescue" then
		endDive(session, "died")
	end
end

function DiveService.onLeave(session: Session)
	if (session.mode == "Diving" or session.mode == "Rescue") and #session.cargo > 0 then
		endDive(session, if session.mode == "Rescue" then "blackout" else "leave")
	end
end

function DiveService.refreshOxygen(session: Session)
	if session.mode ~= "Diving" then
		session.oxygenMax = Economy.upgradeValue("tank", session.profile.upgrades.tank)
		session.oxygen = session.oxygenMax
	end
end

function DiveService.init()
	Net.onEvent(Remotes.Collect, onCollect)
	Net.onEvent(Remotes.Hazard, onHazard)
	local accumulator = 0
	local step = 1 / Config.Dive.ServerHz
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < step then
			return
		end
		local elapsed = math.min(accumulator, 0.5)
		accumulator = 0
		for _, session in Sessions.all() do
			if session.ready then
				local ok, err = pcall(tick :: any, session, elapsed)
				if not ok then
					warn("[DiveService] tick failed: " .. tostring(err))
				end
			end
		end
	end)
end

return DiveService
