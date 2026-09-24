--!strict
-- Pure economy formulas shared by server (authoritative) and client (display / prediction).

local Config = if script then require(script.Parent.Config) else require("./Config")
local Worlds = if script then require(script.Parent.Data.Worlds) else require("./Data/Worlds")
local Gear = if script then require(script.Parent.Data.Gear) else require("./Data/Gear")

local Economy = {}

-- Rounds to two significant digits so prices read cleanly (12,345 -> 12,000).
function Economy.nice(n: number): number
	if n < 100 then
		return math.max(1, math.floor(n + 0.5))
	end
	local magnitude = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / magnitude + 0.5) * magnitude
end

function Economy.depthStuds(world: number): number
	return math.floor(Config.DepthBase + Config.DepthStep * (world - 1) + 0.5)
end

function Economy.lagoonRadius(world: number): number
	return math.floor(Config.RadiusBase + Config.RadiusStep * (world - 1) + 0.5)
end

function Economy.goal(world: number): number
	return math.floor(Config.GoalBase * Config.GoalGrowth ^ (world - 1) + 0.5)
end

function Economy.worldValue(world: number): number
	return Config.RelicBaseValue * Config.RelicWorldGrowth ^ (world - 1)
end

function Economy.relicValue(world: number, rarity: number): number
	return math.floor(Economy.worldValue(world) * Config.RelicRarityValue[rarity] + 0.5)
end

function Economy.relicValueByKey(key: string): number
	local relic = Worlds.relics[key]
	if not relic then
		return 0
	end
	return Economy.relicValue(relic.world, relic.rarity)
end

function Economy.clearReward(world: number): number
	return Economy.nice(Economy.relicValue(world, 1) * Config.ClearRewardRelics)
end

-- Fee to unlock `world` after clearing the world before it (World 1 is free). It tracks what
-- a diver earns there: UnlockClears x (one treasure goal of the previous world, sold as commons,
-- with three Epic pets of that world equipped; the pet part ramps in over the first nine worlds,
-- before most divers have strong pets).
function Economy.unlockCost(world: number): number
	if world <= 1 then
		return 0
	end
	local previous = world - 1
	local typicalBoost = 3 * Config.PetBaseBoost * Config.PetWorldGrowth ^ (previous - 1) * Config.PetRarityFactor[4]
	typicalBoost *= math.min(1, previous / 9)
	return Economy.nice(Config.UnlockClears * Economy.goal(previous) * Economy.relicValue(previous, 1) * (1 + typicalBoost))
end

function Economy.eggCost(world: number): number
	return Economy.nice(Config.EggBaseCost * Config.EggWorldGrowth ^ (world - 1))
end

function Economy.petBoost(key: string): number
	local pet = Worlds.pets[key]
	if not pet then
		return 0
	end
	return Config.PetBaseBoost * Config.PetWorldGrowth ^ (pet.world - 1) * Config.PetRarityFactor[pet.rarity]
end

function Economy.pressure(world: number): number
	return Config.PressureBase + Config.PressureStep * (world - 1)
end

-- Oxygen seconds consumed per real second at a given depth (studs below the surface).
function Economy.oxygenDrain(world: number, depth: number): number
	return 1 + math.max(0, depth) * Economy.pressure(world)
end

function Economy.displayMeters(world: number, depth: number): number
	local data = Worlds.get(world)
	return math.max(0, math.floor(depth / Economy.depthStuds(world) * data.meters + 0.5))
end

-- Gear stats ----------------------------------------------------------------------------------
-- Each slot has a continuous stat curve over a "level" (1 = starter gear). Gear tiers map onto
-- that curve: tier 40 (World 20 Pro) reaches the slot's max level, early tiers climb faster.

local TRACKS = {}
for _, track in Config.Upgrades do
	TRACKS[track.id] = track
end
Economy.Tracks = TRACKS

local VALUE = {
	tank = function(level: number): number
		local l = level - 1
		return math.floor(20 + 6 * l + 0.22 * l * l)
	end,
	pack = function(level: number): number
		local l = level - 1
		return math.floor(4 + l + 0.07 * l * l)
	end,
	fins = function(level: number): number
		return math.floor((15 + 0.8 * (level - 1)) * 10 + 0.5) / 10
	end,
	magnet = function(level: number): number
		return math.floor((5 + 0.8 * (level - 1)) * 10 + 0.5) / 10
	end,
}

-- Stat value at a (possibly fractional) level of a slot's curve.
function Economy.upgradeValue(track: string, level: number): number
	local fn = VALUE[track]
	local def = TRACKS[track]
	if not fn or not def then
		return 0
	end
	return fn(math.clamp(level, 1, def.max))
end

function Economy.gearLevel(slot: string, tier: number): number
	local def = TRACKS[slot]
	if not def or tier <= 0 then
		return 1
	end
	return 1 + (def.max - 1) * (math.min(tier, Gear.Tiers) / Gear.Tiers) ^ Config.GearCurve
end

-- Stat a slot gives with the gear of `tier` equipped (0 = starter gear).
function Economy.gearValue(slot: string, tier: number): number
	return Economy.upgradeValue(slot, Economy.gearLevel(slot, tier))
end

function Economy.gearCost(key: string): number?
	local item = Gear.byKey[key]
	if not item then
		return nil
	end
	local def = TRACKS[item.slot]
	local level = Economy.gearLevel(item.slot, item.tier)
	return Economy.nice(Config.GearPriceScale * def.base * def.growth ^ (level - 2))
end

-- Stat from a profile's equipped gear map ({ slot = gearKey }).
function Economy.stat(equip: { [string]: string }?, slot: string): number
	return Economy.gearValue(slot, Gear.tier(equip and equip[slot]))
end

-- Pet mutations ---------------------------------------------------------------------------------
-- Mutations stack by adding their multipliers: Gold (x2) + Lava (x5) = x7 pet boost.

local MUTATIONS = {}
for _, mutation in Config.Mutations do
	MUTATIONS[mutation.key] = mutation
end
Economy.Mutations = MUTATIONS

function Economy.mutationMultiplier(list: { string }?): number
	if not list or #list == 0 then
		return 1
	end
	local sum = 0
	for _, key in list do
		local mutation = MUTATIONS[key]
		if mutation then
			sum += mutation.mult
		end
	end
	return math.max(1, sum)
end

-- Boost of an owned pet entry, mutations included.
function Economy.petPower(key: string, mutations: { string }?): number
	return Economy.petBoost(key) * Economy.mutationMultiplier(mutations)
end

-- Price of the next enchant on a pet (nil once it carries every mutation).
function Economy.mutateCost(key: string, mutations: { string }?): number?
	local pet = Worlds.pets[key]
	local count = if mutations then #mutations else 0
	if not pet or count >= #Config.Mutations then
		return nil
	end
	return Economy.nice(Economy.eggCost(pet.world) * Config.MutationCost[count + 1])
end

-- Weighted roll among the mutations the pet does not have yet, optionally limited to `pool`
-- (Lucky Enchants). roll in [0, 1).
function Economy.rollMutation(existing: { string }?, roll: number, pool: { string }?): string?
	local total = 0
	local options = {}
	for _, mutation in Config.Mutations do
		if not (existing and table.find(existing, mutation.key)) and (not pool or table.find(pool, mutation.key)) then
			table.insert(options, mutation)
			total += mutation.weight
		end
	end
	if #options == 0 then
		return nil
	end
	local target = roll * total
	for _, mutation in options do
		target -= mutation.weight
		if target < 0 then
			return mutation.key
		end
	end
	return options[#options].key
end

-- Chance (0..1) of each still-missing mutation on the next enchant.
function Economy.mutationChances(existing: { string }?): { { key: string, chance: number } }
	local total = 0
	for _, mutation in Config.Mutations do
		if not (existing and table.find(existing, mutation.key)) then
			total += mutation.weight
		end
	end
	local out = {}
	for _, mutation in Config.Mutations do
		if not (existing and table.find(existing, mutation.key)) then
			table.insert(out, { key = mutation.key, chance = mutation.weight / total })
		end
	end
	return out
end

-- Relic rarity by depth ---------------------------------------------------------------------------

function Economy.rarityWeights(depthRatio: number): { number }
	local d = math.clamp(depthRatio, 0, 1)
	return { 55 * (1 - d) + 8, 26, 9 + 14 * d, 2.5 + 9 * d, 0.4 + 3.2 * d }
end

-- roll in [0, 1)
function Economy.rollRarity(depthRatio: number, roll: number): number
	local weights = Economy.rarityWeights(depthRatio)
	local total = 0
	for _, w in weights do
		total += w
	end
	local target = roll * total
	for index, w in weights do
		target -= w
		if target < 0 then
			return index
		end
	end
	return #weights
end

-- Eggs ------------------------------------------------------------------------------------------

export type Chance = { key: string, chance: number }

-- Per-pet hatch chances (0..1) for a world's egg, in display order.
function Economy.eggChances(world: number, lucky: boolean): { Chance }
	local data = Worlds.get(world)
	local odds = table.clone(Config.EggOdds)
	if lucky then
		odds[4] *= Config.LuckyMultiplier
		odds[5] *= Config.LuckyMultiplier
	end
	local total = 0
	for _, o in odds do
		total += o
	end
	local secretChance = if data.secret then Config.SecretChance * (if lucky then Config.LuckyMultiplier else 1) else 0
	local out: { Chance } = {}
	for rarity, pet in data.pets do
		table.insert(out, { key = pet.key, chance = odds[rarity] / total * (1 - secretChance) })
	end
	if data.secret then
		table.insert(out, { key = data.secret.key, chance = secretChance })
	end
	return out
end

-- roll in [0, 1)
function Economy.rollPet(world: number, lucky: boolean, roll: number): string
	local chances = Economy.eggChances(world, lucky)
	-- Secret first so its tiny slice is not eaten by rounding at the end.
	local last = chances[#chances]
	local data = Worlds.get(world)
	if data.secret and roll < last.chance then
		return last.key
	end
	local acc = if data.secret then last.chance else 0
	for _, entry in chances do
		if entry.key ~= (data.secret and data.secret.key) then
			acc += entry.chance
			if roll < acc then
				return entry.key
			end
		end
	end
	return data.pets[1].key
end

-- Multipliers ---------------------------------------------------------------------------------

function Economy.coinMultiplier(boostSum: number, doubleCoins: boolean): number
	return (1 + boostSum) * (if doubleCoins then 2 else 1)
end

function Economy.productCoins(dives: number, world: number): number
	return Economy.nice(dives * Economy.relicValue(world, 1) * 14)
end

return Economy
