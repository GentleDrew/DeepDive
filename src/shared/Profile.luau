--!strict
-- Player save data: defaults, validation and repair. Pure module (tested outside Roblox).

local Config = if script then require(script.Parent.Config) else require("./Config")
local Worlds = if script then require(script.Parent.Data.Worlds) else require("./Data/Worlds")
local Gear = if script then require(script.Parent.Data.Gear) else require("./Data/Gear")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")

local Profile = {}

-- s = species key, l = locked, m = mutations (Config.Mutations keys, in the order gained)
export type PetEntry = { s: string, l: boolean?, m: { string }? }
export type GearData = { owned: { [string]: boolean }, equip: { [string]: string } }
export type WorldProgress = { sold: number, cleared: boolean, best: number }
export type Data = {
	v: number,
	coins: number,
	lifetime: number,
	world: number,
	unlocked: number,
	worlds: { [string]: WorldProgress },
	gear: GearData,
	enchants: number, -- Lucky Enchant tokens (developer product)
	pets: { [string]: PetEntry },
	equipped: { string },
	petSeq: number,
	index: { [string]: boolean },
	relics: { [string]: number },
	backpack: { string },
	tutorial: number,
	settings: { music: boolean, sfx: boolean, lowFx: boolean, hidePets: boolean, lang: string },
	stats: { dives: number, relics: number, blackouts: number, hatched: number, playtime: number },
	receipts: { string },
	created: number,
	seen: number,
}

function Profile.new(now: number): Data
	return {
		v = Config.SchemaVersion,
		coins = 0,
		lifetime = 0,
		world = 1,
		unlocked = 1,
		worlds = {},
		gear = { owned = {}, equip = {} },
		enchants = 0,
		pets = {},
		equipped = {},
		petSeq = 0,
		index = {},
		relics = {},
		backpack = {},
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
	if type(raw.gear) == "table" then
		if type(raw.gear.owned) == "table" then
			for key, value in raw.gear.owned do
				if type(key) == "string" and Gear.byKey[key] and value == true then
					data.gear.owned[key] = true
				end
			end
		end
		if type(raw.gear.equip) == "table" then
			for _, slot in Gear.Slots do
				local key = raw.gear.equip[slot]
				local item = if type(key) == "string" then Gear.byKey[key] else nil
				if item and item.slot == slot and data.gear.owned[key] then
					data.gear.equip[slot] = key
				end
			end
		end
	elseif type(raw.upgrades) == "table" then
		-- Saves from before gear: grant the best piece whose stat the old upgrade level covered.
		for _, slot in Gear.Slots do
			local level = number(raw.upgrades[slot], 1, 1)
			for _, item in Gear.bySlot[slot] do
				if Economy.gearLevel(slot, item.tier) <= level + 1e-6 then
					data.gear.owned[item.key] = true
					data.gear.equip[slot] = item.key
				end
			end
		end
	end
	data.enchants = math.floor(number(raw.enchants, 0, 0, 9999))
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
				local mutations: { string }? = nil
				if type(entry.m) == "table" then
					local list = {}
					for _, key in entry.m do
						if type(key) == "string" and Economy.Mutations[key] and not table.find(list, key) then
							table.insert(list, key)
						end
					end
					if #list > 0 then
						mutations = list
					end
				end
				data.pets[id] = { s = entry.s, l = entry.l == true, m = mutations }
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
	-- Unsold treasure carried between dives (sold only at a world's sell stand).
	if type(raw.backpack) == "table" then
		for _, key in raw.backpack do
			if type(key) == "string" and Worlds.relics[key] and #data.backpack < Config.BackpackHardCap then
				table.insert(data.backpack, key)
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
