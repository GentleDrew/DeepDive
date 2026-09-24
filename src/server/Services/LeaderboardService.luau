--!strict
-- Global leaderboard: every diver's lifetime coins go into an OrderedDataStore and the top 10
-- are published as JSON in ReplicatedStorage for the boards on every dock. When DataStores are
-- unavailable (Studio without API access) the board ranks the players in this server instead.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local ProfileStore = require(script.Parent.Parent.ProfileStore)
local Sessions = require(script.Parent.Parent.Sessions)

local LeaderboardService = {}

local STORE_NAME = "DeepDive_TopDivers_v1"
local TOP = 10
local GLOBAL_REFRESH = 90
local LOCAL_REFRESH = 8
local WRITE_INTERVAL = 120

local store: OrderedDataStore? = nil
local storeFailed = false
local names: { [number]: string } = {}
local lastWrite: { [Player]: number } = {}
local lastValue: { [Player]: number } = {}
local published: StringValue

local function getStore(): OrderedDataStore?
	if store or storeFailed or ProfileStore.memoryMode then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		storeFailed = true
	end
	return store
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.Name
		return player.Name
	end
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and type(result) == "string" then result else "Diver"
	names[userId] = name
	return name
end

-- Queues this player's lifetime coins for the global store (rate limited unless forced).
function LeaderboardService.submit(player: Player, force: boolean?)
	local session = Sessions.get(player)
	if not session then
		return
	end
	local value = math.floor(session.profile.lifetime)
	local now = os.clock()
	if not force and (now - (lastWrite[player] or -math.huge) < WRITE_INTERVAL or lastValue[player] == value) then
		return
	end
	local ds = getStore()
	if not ds then
		return
	end
	lastWrite[player] = now
	lastValue[player] = value
	local userId = player.UserId
	task.spawn(function()
		pcall(function()
			ds:SetAsync(tostring(userId), value)
		end)
	end)
end

type Entry = { n: string, v: number, u: number }

local function localEntries(): { Entry }
	local list: { Entry } = {}
	for _, player in Players:GetPlayers() do
		local lifetime = player:GetAttribute("Lifetime")
		if type(lifetime) == "number" then
			table.insert(list, { n = player.Name, v = math.floor(lifetime), u = player.UserId })
		end
	end
	table.sort(list, function(a, b)
		return a.v > b.v
	end)
	while #list > TOP do
		table.remove(list)
	end
	return list
end

-- Returns true when the published list came from the global store.
function LeaderboardService.refresh(): boolean
	local list: { Entry } = {}
	local global = false
	local ds = getStore()
	if ds then
		global = pcall(function()
			local pages = ds:GetSortedAsync(false, TOP)
			for _, item in pages:GetCurrentPage() do
				local userId = tonumber(item.key)
				if userId and type(item.value) == "number" then
					table.insert(list, { n = nameOf(userId), v = item.value, u = userId })
				end
			end
		end)
	end
	if not global or #list == 0 then
		list = localEntries()
		global = false
	end
	published.Value = HttpService:JSONEncode({ global = global, entries = list })
	return global
end

function LeaderboardService.init()
	local existing = ReplicatedStorage:FindFirstChild(Remotes.Board)
	if existing then
		existing:Destroy()
	end
	published = Instance.new("StringValue")
	published.Name = Remotes.Board
	published.Value = HttpService:JSONEncode({ global = false, entries = {} })
	published.Parent = ReplicatedStorage

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
