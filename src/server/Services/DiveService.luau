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
	return Economy.stat(session.profile.gear.equip, "pack")
end

local function magnet(session: Session): number
	return Economy.stat(session.profile.gear.equip, "magnet")
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
	session.oxygenMax = Economy.stat(profile.gear.equip, "tank")
	session.oxygen = session.oxygenMax
	session.diveStart = #profile.backpack
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
	-- The next world becomes available to unlock (for a fee) rather than opening right away.
	local nextWorld = nil
	if world < Config.WorldCount and profile.unlocked <= world then
		nextWorld = world + 1
	end
	return {
		world = world,
		reward = reward,
		nextWorld = nextWorld,
		unlockCost = if nextWorld then Economy.unlockCost(nextWorld) else nil,
		all = world == Config.WorldCount,
	}
end

-- Ends a dive. Treasure stays in the backpack until sold at the sell stand; a rescue (blackout,
-- death, leaving mid-dive) drops half of what was gathered on this dive.
-- reason: "surface" | "blackout" | "died" | "leave"
local function endDive(session: Session, reason: string)
	if session.mode ~= "Diving" and session.mode ~= "Rescue" then
		return
	end
	local profile = session.profile
	local world = session.world
	local backpack = profile.backpack
	local rescued = reason ~= "surface"
	local gathered = math.max(0, #backpack - session.diveStart)
	local lost = 0
	if rescued and gathered > 0 then
		lost = gathered - math.floor(gathered * Config.Dive.BlackoutKeep)
		for _ = 1, lost do
			table.remove(backpack)
		end
	end
	local progress = Profile.progress(profile, world)
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
	if rescued and reason ~= "leave" then
		profile.stats.blackouts += 1
	end
	if profile.tutorial == 2 and #backpack > 0 then
		profile.tutorial = 3
	end

	session.mode = "Dock"
	session.oxygen = session.oxygenMax
	session.chestCarried = false

	Net.push(session.player, "surfaced", {
		gathered = gathered,
		lost = lost,
		cargo = #backpack,
		rescued = rescued,
		chest = carried and not rescued,
		chestLost = carried and rescued,
		record = record,
	})
	if cleared then
		Net.push(session.player, "cleared", cleared)
	end
	Sync.profile(session)
	DiveService.rollLayout(session)
end

-- Sells the whole backpack. Only on the dock, standing at this world's sell stand.
-- `anywhere` bypasses the distance-to-stand check (the AutoSell pass sells the instant you
-- surface, wherever that is).
function DiveService.sell(session: Session, fromPrompt: boolean?, anywhere: boolean?): (boolean, string?)
	local profile = session.profile
	local backpack = profile.backpack
	if session.mode ~= "Dock" then
		return false, "err.diving"
	end
	if #backpack == 0 then
		return false, "nothingToSell"
	end
	local root = rootOf(session.player)
	if not root or not aliveHumanoid(session.player) then
		return false, "err.generic"
	end
	if not anywhere then
		local spot = Layout.origin(session.world) + Layout.dock(session.world).sell
		local offset = root.Position - spot
		local reach = Config.SellRadius + (if fromPrompt then 8 else 0)
		if Vector3.new(offset.X, 0, offset.Z).Magnitude > reach or math.abs(offset.Y) > 10 then
			return false, "sellFar"
		end
	end
	local now = os.clock()
	if now - session.lastSell < 0.8 then
		return false, "err.busy"
	end
	session.lastSell = now
	local total = 0
	local perWorld: { [number]: number } = {}
	for _, key in backpack do
		total += Economy.relicValueByKey(key)
		local relic = Worlds.relics[key]
		if relic then
			perWorld[relic.world] = (perWorld[relic.world] or 0) + 1
		end
	end
	local count = #backpack
	local payout = math.floor(total * Sessions.multiplier(session))
	profile.coins += payout
	profile.lifetime += payout
	table.clear(backpack)
	session.diveStart = 0
	local world = session.world
	local goal = Economy.goal(world)
	local current = Profile.progress(profile, world)
	local wasReady = current.sold >= goal
	for relicWorld, n in perWorld do
		local progress = Profile.progress(profile, relicWorld)
		progress.sold += n
	end
	local chestReady = not wasReady and current.sold >= goal and not current.cleared
	if profile.tutorial == 2 or profile.tutorial == 3 then
		profile.tutorial = 4
	end
	Net.push(session.player, "sold", {
		payout = payout,
		count = count,
		progress = current.sold,
		goal = goal,
		chestReady = chestReady,
	})
	Sync.profile(session)
	if chestReady then
		DiveService.rollLayout(session)
	end
	return true, nil
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
	session.profile.stats.playtime += dt
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
		elseif #session.profile.backpack > 0 then
			-- Stepping onto the sell pad sells everything.
			local spot = Layout.origin(session.world) + Layout.dock(session.world).sell
			local offset = position - spot
			if Vector3.new(offset.X, 0, offset.Z).Magnitude <= Config.SellRadius and math.abs(offset.Y) < 8 then
				DiveService.sell(session)
			end
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
			if session.passes.AutoSell and #session.profile.backpack > 0 then
				DiveService.sell(session, false, true)
			end
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
		if #session.profile.backpack >= capacity(session) then
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
	local profile = session.profile
	if point == 0 then
		session.chestCarried = true
		Net.push(player, "collected", { point = 0, chest = true, cargo = #profile.backpack })
		return
	end
	local key = session.relics[point]
	session.relics[point] = nil
	table.insert(profile.backpack, key)
	local discovered = (profile.relics[key] or 0) == 0
	profile.relics[key] = (profile.relics[key] or 0) + 1
	profile.stats.relics += 1
	Sync.stats(session)
	Net.push(player, "collected", {
		point = point,
		key = key,
		cargo = #profile.backpack,
		capacity = capacity(session),
		discovered = discovered,
		total = profile.relics[key],
	})
	-- The spot refills with a fresh relic after a short delay, as long as this is still the same
	-- dive (otherwise the next rollLayout already reseeds every point from scratch).
	local capturedLayout = session.layoutId
	local depth = built.depths[point]
	task.delay(Config.Dive.RelicRespawnMin + session.rng:NextNumber() * (Config.Dive.RelicRespawnMax - Config.Dive.RelicRespawnMin), function()
		if session.layoutId ~= capturedLayout or (session.mode ~= "Diving" and session.mode ~= "Rescue") or session.relics[point] then
			return
		end
		local rarity = Economy.rollRarity(depth * 0.95, session.rng:NextNumber())
		local newKey = Worlds.get(session.world).relics[rarity].key
		session.relics[point] = newKey
		Net.push(player, "relicSpawn", { point = point, key = newKey })
	end)
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
	if session.mode == "Diving" or session.mode == "Rescue" then
		endDive(session, if session.mode == "Rescue" then "blackout" else "leave")
	end
end

function DiveService.refreshOxygen(session: Session)
	if session.mode ~= "Diving" then
		session.oxygenMax = Economy.stat(session.profile.gear.equip, "tank")
		session.oxygen = session.oxygenMax
	end
end

function DiveService.init()
	Net.onEvent(Remotes.Collect, onCollect)
	Net.onEvent(Remotes.Hazard, onHazard)
	-- Keeps the Profile panel's playtime reasonably fresh even when nothing else syncs.
	task.spawn(function()
		while true do
			task.wait(30)
			for _, session in Sessions.all() do
				if session.ready then
					Sync.profile(session)
				end
			end
		end
	end)
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
