--!strict
-- Player save data: defaults, validation and repair. Pure module (tested outside Roblox).

local Config = if script then require(script.Parent.Config) else require("./Config")
local Worlds = if script then require(script.Parent.Data.Worlds) else require("./Data/Worlds")

local Profile = {}

export type PetEntry = { s: string, l: boolean? }
export type WorldProgress = { sold: number, cleared: boolean, best: number }
export type Data = {
	v: number,
	coins: number,
	lifetime: number,
	world: number,
	unlocked: number,
	worlds: { [string]: WorldProgress },
	upgrades: { [string]: number },
	pets: { [string]: PetEntry },
	equipped: { string },
	petSeq: number,
	index: { [string]: boolean },
	relics: { [string]: number },
	tutorial: number,
	settings: { music: boolean, sfx: boolean, lowFx: boolean, hidePets: boolean, lang: string },
	stats: { dives: number, relics: number, blackouts: number, hatched: number, playtime: number },
	receipts: { string },
	created: number,
	seen: number,
}

function Profile.new(now: number): Data
	local upgrades = {}
	for _, track in Config.Upgrades do
		upgrades[track.id] = 1
	end
	return {
		v = Config.SchemaVersion,
		coins = 0,
		lifetime = 0,
		world = 1,
		unlocked = 1,
		worlds = {},
		upgrades = upgrades,
		pets = {},
		equipped = {},
		petSeq = 0,
		index = {},
		relics = {},
		tutorial = 1,
		settings = { music = true, sfx = true, lowFx = false, hidePets = false, lang = Config.DefaultLanguage },
		stats = { dives = 0, relics = 0, blackouts = 0, hatched = 0, playtime = 0 },
		receipts = {},
		created = now,
		seen = now,
	}
end

local function number(value: any, fallback: number, min: number?, max: number?): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	if min and value < min then
		return min
	end
	if max and value > max then
		return max
	end
	return value
end

local function bool(value: any, fallback: boolean): boolean
	if type(value) == "boolean" then
		return value
	end
	return fallback
end

-- Returns a repaired copy of stored data (or a fresh profile). Never errors on bad input.
function Profile.reconcile(raw: any, now: number): Data
	local fresh = Profile.new(now)
	if type(raw) ~= "table" then
		return fresh
	end
	local data = fresh
	data.coins = math.floor(number(raw.coins, 0, 0))
	data.lifetime = math.floor(number(raw.lifetime, data.coins, 0))
	data.unlocked = math.floor(number(raw.unlocked, 1, 1, Config.WorldCount))
	data.world = math.floor(number(raw.world, 1, 1, data.unlocked))
	if type(raw.worlds) == "table" then
		for key, entry in raw.worlds do
			local index = tonumber(key)
			if index and index >= 1 and index <= Config.WorldCount and type(entry) == "table" then
				data.worlds[tostring(math.floor(index))] = {
					sold = math.floor(number(entry.sold, 0, 0)),
					cleared = bool(entry.cleared, false),
					best = number(entry.best, 0, 0),
				}
			end
		end
	end
	if type(raw.upgrades) == "table" then
		for _, track in Config.Upgrades do
			data.upgrades[track.id] = math.floor(number(raw.upgrades[track.id], 1, 1, track.max))
		end
	end
	local count = 0
	if type(raw.pets) == "table" then
		for id, entry in raw.pets do
			if
				type(id) == "string"
				and type(entry) == "table"
				and type(entry.s) == "string"
				and Worlds.pets[entry.s]
				and count < Config.PetInventoryCap
			then
				data.pets[id] = { s = entry.s, l = entry.l == true }
				count += 1
			end
		end
	end
	if type(raw.equipped) == "table" then
		local seen = {}
		for _, id in raw.equipped do
			if type(id) == "string" and data.pets[id] and not seen[id] and #data.equipped < Config.PetEquipBase + Config.PetEquipPass then
				seen[id] = true
				table.insert(data.equipped, id)
			end
		end
	end
	data.petSeq = math.floor(number(raw.petSeq, count, 0))
	if type(raw.index) == "table" then
		for key, value in raw.index do
			if type(key) == "string" and Worlds.pets[key] and value == true then
				data.index[key] = true
			end
		end
	end
	for _, entry in data.pets do
		data.index[entry.s] = true
	end
	if type(raw.relics) == "table" then
		for key, value in raw.relics do
			if type(key) == "string" and Worlds.relics[key] then
				data.relics[key] = math.floor(number(value, 0, 0))
			end
		end
	end
	data.tutorial = math.floor(number(raw.tutorial, 1, 0, 99))
	if type(raw.settings) == "table" then
		local s = raw.settings
		data.settings.music = bool(s.music, true)
		data.settings.sfx = bool(s.sfx, true)
		data.settings.lowFx = bool(s.lowFx, false)
		data.settings.hidePets = bool(s.hidePets, false)
		if s.lang == "en" or s.lang == "ko" then
			data.settings.lang = s.lang
		end
	end
	if type(raw.stats) == "table" then
		for key in data.stats do
			(data.stats :: any)[key] = number(raw.stats[key], 0, 0)
		end
	end
	if type(raw.receipts) == "table" then
		for _, receipt in raw.receipts do
			if type(receipt) == "string" and #data.receipts < 60 then
				table.insert(data.receipts, receipt)
			end
		end
	end
	data.created = number(raw.created, now)
	data.seen = now
	return data
end

function Profile.progress(data: Data, world: number): WorldProgress
	local key = tostring(world)
	local entry = data.worlds[key]
	if not entry then
		entry = { sold = 0, cleared = false, best = 0 }
		data.worlds[key] = entry
	end
	return entry
end

function Profile.petCount(data: Data): number
	local count = 0
	for _ in data.pets do
		count += 1
	end
	return count
end

return Profile
