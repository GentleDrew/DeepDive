--!strict
-- DataStore persistence with a session lock so two servers never own the same profile.
-- Profiles live in memory and autosave; purchases force an immediate save. In Studio without
-- API access the store falls back to memory-only profiles (progress is not saved).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Profile = require(Shared.Profile)

local ProfileStore = {}

local LOCK_TIMEOUT = 240
local AUTOSAVE_INTERVAL = 75
local jobId = if game.JobId ~= "" then game.JobId else "studio-" .. tostring(math.random(1, 1e9))

type Entry = { data: Profile.Data, dirty: boolean, saving: boolean, released: boolean, lastSave: number }

local entries: { [Player]: Entry } = {}
local store: DataStore? = nil
ProfileStore.memoryMode = false

local function key(userId: number): string
	return "p_" .. tostring(userId)
end

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
		return store
	end
	warn("[DeepDive] DataStore unavailable: " .. tostring(result))
	return nil
end

local function enterMemoryMode(reason: string)
	if not ProfileStore.memoryMode then
		ProfileStore.memoryMode = true
		warn("[DeepDive] Using session-only profiles (progress will not be saved): " .. reason)
		warn("[DeepDive] Publish the place and enable Game Settings > Security > 'Enable Studio Access to API Services' to test saving.")
	end
end

local function waitForBudget(requestType: Enum.DataStoreRequestType)
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 and waited < 8 do
		task.wait(0.5)
		waited += 0.5
	end
end

-- Yields. Returns the profile, or nil if the player left or loading failed.
function ProfileStore.load(player: Player): Profile.Data?
	local now = os.time()
	if ProfileStore.memoryMode then
		local data = Profile.new(now)
		entries[player] = { data = data, dirty = false, saving = false, released = false, lastSave = os.clock() }
		return data
	end
	local ds = getStore()
	if not ds then
		if RunService:IsStudio() then
			enterMemoryMode("no DataStore")
			return ProfileStore.load(player)
		end
		return nil
	end
	local attempt = 0
	while player.Parent do
		attempt += 1
		local loaded: Profile.Data? = nil
		local lockedBy: string? = nil
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player.UserId), function(record)
				loaded = nil
				lockedBy = nil
				local current = if type(record) == "table" then record else {}
				local lock = current.lock
				local stale = type(lock) ~= "table" or type(lock.time) ~= "number" or os.time() - lock.time > LOCK_TIMEOUT
				if type(lock) == "table" and lock.job ~= jobId and not stale then
					lockedBy = tostring(lock.job)
					return nil
				end
				local data = Profile.reconcile(current.data, os.time())
				loaded = data
				return { data = data, lock = { job = jobId, time = os.time() } }
			end)
		end)
		if ok and loaded then
			entries[player] = { data = loaded, dirty = false, saving = false, released = false, lastSave = os.clock() }
			return loaded
		elseif ok and lockedBy then
			-- Another server still owns this profile (the player just hopped servers). Wait for it.
			if attempt >= 45 then
				return nil
			end
			task.wait(5)
		else
			if RunService:IsStudio() then
				enterMemoryMode(tostring(err))
				return ProfileStore.load(player)
			end
			if attempt >= 6 then
				warn("[DeepDive] Profile load failed for " .. player.Name .. ": " .. tostring(err))
				return nil
			end
			task.wait(math.min(2 ^ attempt, 20))
		end
	end
	return nil
end

function ProfileStore.get(player: Player): Profile.Data?
	local entry = entries[player]
	return entry and entry.data
end

function ProfileStore.markDirty(player: Player)
	local entry = entries[player]
	if entry then
		entry.dirty = true
	end
end

-- Writes the profile. `release` drops the session lock (player leaving / shutdown).
function ProfileStore.save(player: Player, release: boolean?): boolean
	local entry = entries[player]
	if not entry or entry.released then
		return false
	end
	if ProfileStore.memoryMode then
		entry.dirty = false
		if release then
			entry.released = true
			entries[player] = nil
		end
		return true
	end
	local ds = getStore()
	if not ds then
		return false
	end
	while entry.saving do
		task.wait(0.1)
	end
	if entry.released then
		-- Another caller released the profile while this save was waiting.
		return true
	end
	entry.saving = true
	entry.data.seen = os.time()
	local snapshot = entry.data
	local success = false
	for attempt = 1, 4 do
		waitForBudget(Enum.DataStoreRequestType.UpdateAsync)
		local lost = false
		local ok, err = pcall(function()
			ds:UpdateAsync(key(player.UserId), function(record)
				local current = if type(record) == "table" then record else {}
				local lock = current.lock
				if type(lock) == "table" and lock.job ~= jobId and type(lock.time) == "number" and os.time() - lock.time <= LOCK_TIMEOUT then
					lost = true
					return nil
				end
				return { data = snapshot, lock = if release then nil else { job = jobId, time = os.time() } }
			end)
		end)
		if ok and not lost then
			success = true
			break
		elseif lost then
			warn("[DeepDive] Session lock lost for " .. player.Name .. "; not overwriting newer data.")
			break
		else
			warn("[DeepDive] Save attempt " .. attempt .. " failed: " .. tostring(err))
			task.wait(attempt * 1.5)
		end
	end
	entry.saving = false
	if success then
		entry.dirty = false
		entry.lastSave = os.clock()
	end
	if release then
		entry.released = true
		entries[player] = nil
	end
	return success
end

function ProfileStore.init()
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for player, entry in entries do
				if
					not entry.released
					and not entry.saving
					and (entry.dirty or now - entry.lastSave > AUTOSAVE_INTERVAL * 2)
					and now - entry.lastSave > AUTOSAVE_INTERVAL
				then
					task.spawn(ProfileStore.save, player, false)
				end
			end
		end
	end)
	game:BindToClose(function()
		-- Covers every loaded profile, including players whose PlayerRemoving save is still running.
		local pending = 0
		for player, entry in entries do
			if not entry.released then
				pending += 1
				task.spawn(function()
					ProfileStore.save(player, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

return ProfileStore
