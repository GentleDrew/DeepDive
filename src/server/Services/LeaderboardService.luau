--!strict
-- Ranking boards: weekly, monthly and all-time coins earned, each an OrderedDataStore. The top
-- 10 of each (Directors listed apart) are published as JSON in ReplicatedStorage for the dock
-- boards, the podium statues and the player list. Holding a top-3 spot accrues hold time
-- towards the ranking tiers (Config.Tiers). When DataStores are unavailable (Studio without
-- API access) the boards rank the players in this server and hold time is kept in memory.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Operators = require(Shared.Operators)
local Rankings = require(Shared.Rankings)
local Remotes = require(Shared.Remotes)

local ProfileStore = require(script.Parent.Parent.ProfileStore)
local Sessions = require(script.Parent.Parent.Sessions)

local LeaderboardService = {}

local TOP = 10
local GLOBAL_REFRESH = 60
local LOCAL_REFRESH = 8
local WRITE_INTERVAL = 120
local CREDIT_MIN = 45 -- seconds between hold-time credits (shared across servers)
local CREDIT_MAX = 300 -- never credit more than this at once (e.g. after every server was down)

export type Entry = { u: number, n: string, d: string, v: number, t: number, nt: number?, ns: number? }
type Row = { u: number, v: number }

local storeFailed = false
local ordered: { [string]: OrderedDataStore } = {}
local holdStore: GlobalDataStore? = nil
local clockStore: GlobalDataStore? = nil
local names: { [number]: { n: string, d: string } } = {}
local holds: { [number]: Rankings.Holds } = {}
local lastWrite: { [Player]: number } = {}
local lastValue: { [Player]: string } = {}
local lastLocalCredit = os.clock()
local published: StringValue
local latest: any = { global = false, boards = {}, directors = {} }

local function storesOn(): boolean
	return not storeFailed and not ProfileStore.memoryMode
end

local function storeName(board: string, now: number): string
	if board == "weekly" then
		return "DeepDive_Week_v1_" .. Rankings.weekId(now)
	elseif board == "monthly" then
		return "DeepDive_Month_v1_" .. Rankings.monthId(now)
	end
	return "DeepDive_TopDivers_v1"
end

local function orderedStore(board: string, now: number): OrderedDataStore?
	if not storesOn() then
		return nil
	end
	local name = storeName(board, now)
	local existing = ordered[name]
	if existing then
		return existing
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if not ok then
		storeFailed = true
		return nil
	end
	ordered[name] = result
	return result
end

local function holdStores(): (GlobalDataStore?, GlobalDataStore?)
	if not storesOn() then
		return nil, nil
	end
	if not holdStore then
		local ok = pcall(function()
			holdStore = DataStoreService:GetDataStore("DeepDive_Holds_v1")
			clockStore = DataStoreService:GetDataStore("DeepDive_HoldClock_v1")
		end)
		if not ok then
			storeFailed = true
			return nil, nil
		end
	end
	return holdStore, clockStore
end

local function cleanHolds(value: any): Rankings.Holds
	if type(value) ~= "table" then
		return { w = 0, m = 0 }
	end
	return { w = math.max(0, tonumber(value.w) or 0), m = math.max(0, tonumber(value.m) or 0) }
end

local function holdsOf(userId: number): Rankings.Holds
	local cached = holds[userId]
	if cached then
		return cached
	end
	local store = holdStores()
	local value: any = nil
	if store then
		pcall(function()
			value = store:GetAsync(tostring(userId))
		end)
	end
	local result = cleanHolds(value)
	holds[userId] = result
	return result
end

local function scores(player: Player): { [string]: number }
	return {
		weekly = tonumber(player:GetAttribute("Weekly")) or 0,
		monthly = tonumber(player:GetAttribute("Monthly")) or 0,
		alltime = tonumber(player:GetAttribute("Lifetime")) or 0,
	}
end

-- Queues this player's scores for the ranking stores (rate limited unless forced).
function LeaderboardService.submit(player: Player, force: boolean?)
	local session = Sessions.get(player)
	if not session then
		return
	end
	local now = os.time()
	local values = scores(player)
	local signature = string.format("%d/%d/%d", values.weekly, values.monthly, values.alltime)
	if not force and (os.clock() - (lastWrite[player] or -math.huge) < WRITE_INTERVAL or lastValue[player] == signature) then
		return
	end
	if not storesOn() then
		return
	end
	lastWrite[player] = os.clock()
	lastValue[player] = signature
	local key = tostring(player.UserId)
	for board, value in values do
		local store = orderedStore(board, now)
		if store then
			task.spawn(function()
				pcall(function()
					store:SetAsync(key, math.floor(value))
				end)
			end)
		end
	end
end

local function fetch(board: string, now: number): ({ Row }, boolean)
	local store = orderedStore(board, now)
	if store then
		local rows: { Row } = {}
		local ok = pcall(function()
			local pages = store:GetSortedAsync(false, TOP + #Operators.list() + 1)
			for _, item in pages:GetCurrentPage() do
				local userId = tonumber(item.key)
				if userId and type(item.value) == "number" then
					table.insert(rows, { u = userId, v = item.value })
				end
			end
		end)
		if ok and #rows > 0 then
			return rows, true
		end
	end
	local rows: { Row } = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("Lifetime") ~= nil then
			table.insert(rows, { u = player.UserId, v = math.floor(scores(player)[board]) })
		end
	end
	table.sort(rows, function(a, b)
		return a.v > b.v
	end)
	return rows, false
end

-- Directors who are not in the fetched top rows still get their own score on the board.
local function directorScore(board: string, now: number, userId: number): number?
	local player = Players:GetPlayerByUserId(userId)
	if player and player:GetAttribute("Lifetime") ~= nil then
		return math.floor(scores(player)[board])
	end
	local store = orderedStore(board, now)
	local value: any = nil
	if store then
		pcall(function()
			value = store:GetAsync(tostring(userId))
		end)
	end
	return if type(value) == "number" then value else nil
end

local function resolveNames(ids: { number })
	local missing = {}
	for _, id in ids do
		local player = Players:GetPlayerByUserId(id)
		if player then
			names[id] = { n = player.Name, d = player.DisplayName }
		elseif not names[id] then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	pcall(function()
		for _, info in UserService:GetUserInfosByUserIdsAsync(missing) do
			names[info.Id] = { n = info.Username, d = info.DisplayName }
		end
	end)
	for _, id in missing do
		if not names[id] then
			local ok, name = pcall(function()
				return Players:GetNameFromUserIdAsync(id)
			end)
			local text = if ok and type(name) == "string" then name else "Diver"
			names[id] = { n = text, d = text }
		end
	end
end

-- Adds the time since the last credit to the hold time of everyone in a top-3 spot. Across
-- servers one shared clock key decides who credits each window, so time is never counted twice.
local function creditHolds(tops: { [string]: { number } }, global: boolean)
	local delta = 0
	local store, clock = holdStores()
	if global and store and clock then
		local now = os.time()
		pcall(function()
			clock:UpdateAsync("clock", function(old: any)
				local last = if type(old) == "table" then tonumber(old.t) else nil
				if last and now - last < CREDIT_MIN then
					return nil
				end
				delta = if last then math.clamp(now - last, 0, CREDIT_MAX) else 0
				return { t = now }
			end)
		end)
	elseif not global then
		local now = os.clock()
		delta = math.min(now - lastLocalCredit, CREDIT_MAX)
		lastLocalCredit = now
	end
	if delta <= 0 then
		return
	end
	local gains: { [number]: Rankings.Holds } = {}
	for board, ids in tops do
		for _, id in ids do
			local gain = gains[id] or { w = 0, m = 0 }
			if board == "weekly" then
				gain.w += delta
			else
				gain.m += delta
			end
			gains[id] = gain
		end
	end
	for id, gain in gains do
		local current = holdsOf(id)
		current.w += gain.w
		current.m += gain.m
		if global and store then
			task.spawn(function()
				pcall(function()
					store:UpdateAsync(tostring(id), function(old: any)
						local value = cleanHolds(old)
						value.w += gain.w
						value.m += gain.m
						holds[id] = { w = value.w, m = value.m }
						return value
					end)
				end)
			end)
		end
	end
end

local function entry(row: Row, board: string, rank: number): Entry
	local name = names[row.u] or { n = "Diver", d = "Diver" }
	local h = holds[row.u] or { w = 0, m = 0 }
	local e: Entry = { u = row.u, n = name.n, d = name.d, v = row.v, t = Rankings.tier(h) }
	if rank <= 3 then
		local nextTier, seconds = Rankings.nextTier(holdsOf(row.u), board)
		e.nt = nextTier
		e.ns = if seconds then math.ceil(seconds) else nil
	end
	return e
end

-- Rebuilds every board; returns true when the data came from the global stores.
function LeaderboardService.refresh(): boolean
	local now = os.time()
	local global = true
	local ranked: { [string]: { Row } } = {}
	local directors: { [string]: Row } = {}
	local ids: { number } = {}
	local operators = Operators.list()
	for _, board in Rankings.Boards do
		local rows, fromStore = fetch(board, now)
		global = global and fromStore
		local list: { Row } = {}
		for _, row in rows do
			if Operators.is(row.u) then
				directors[board] = directors[board] or row
			elseif #list < TOP then
				table.insert(list, row)
				table.insert(ids, row.u)
			end
		end
		if not directors[board] and operators[1] then
			local value = directorScore(board, now, operators[1])
			if value then
				directors[board] = { u = operators[1], v = value }
			end
		end
		if directors[board] then
			table.insert(ids, directors[board].u)
		end
		ranked[board] = list
	end

	local tops: { [string]: { number } } = { weekly = {}, monthly = {} }
	for board, list in tops do
		for i = 1, math.min(3, #ranked[board]) do
			table.insert(list, ranked[board][i].u)
		end
	end
	creditHolds(tops, global)
	resolveNames(ids)

	local data: any = { global = global, at = now, boards = {}, directors = {} }
	for _, board in Rankings.Boards do
		local entries = {}
		for rank, row in ranked[board] do
			entries[rank] = entry(row, board, rank)
		end
		data.boards[board] = { entries = entries, reset = Rankings.untilReset(board, now) }
		local director = directors[board]
		if director then
			local name = names[director.u] or { n = "Director", d = "Director" }
			data.directors[board] = { u = director.u, n = name.n, d = name.d, v = director.v }
		end
	end
	latest = data
	published.Value = HttpService:JSONEncode(data)
	for _, player in Players:GetPlayers() do
		local h = holds[player.UserId]
		if h then
			player:SetAttribute("Tier", Rankings.tier(h))
		end
	end
	return global
end

function LeaderboardService.latest(): any
	return latest
end

function LeaderboardService.init()
	local existing = ReplicatedStorage:FindFirstChild(Remotes.Board)
	if existing then
		existing:Destroy()
	end
	published = Instance.new("StringValue")
	published.Name = Remotes.Board
	published.Value = HttpService:JSONEncode(latest)
	published.Parent = ReplicatedStorage

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			local h = holdsOf(player.UserId)
			if player.Parent then
				player:SetAttribute("Tier", Rankings.tier(h))
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		LeaderboardService.submit(player, true)
		lastWrite[player] = nil
		lastValue[player] = nil
	end)
	task.spawn(function()
		task.wait(4)
		while true do
			for player in Sessions.all() do
				LeaderboardService.submit(player)
			end
			local global = LeaderboardService.refresh()
			task.wait(if global then GLOBAL_REFRESH else LOCAL_REFRESH)
		end
	end)
end

return LeaderboardService
