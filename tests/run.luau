-- Unit tests for the pure modules. Run with:  lune run tests/run.luau
local fs = require("@lune/fs")
local process = require("@lune/process")

local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Economy")
local Format = require("../src/shared/Format")
local Profile = require("../src/shared/Profile")
local Strings = require("../src/shared/Strings")
local Worlds = require("../src/shared/Data/Worlds")
local Gear = require("../src/shared/Data/Gear")

local passed, failed = 0, 0
local function check(condition: any, message: string)
	if condition then
		passed += 1
	else
		failed += 1
		print("  FAIL: " .. message)
	end
end
local function section(name: string)
	print("- " .. name)
end

local function definedShapes(path: string): { [string]: boolean }
	local source = fs.readFile(path)
	local shapes = {}
	for name in string.gmatch(source, "SHAPES%.(%w+)%s*=%s*function") do
		shapes[name] = true
	end
	return shapes
end

local TERRAIN_MATERIALS = {
	Grass = true,
	LeafyGrass = true,
	Sand = true,
	Rock = true,
	Slate = true,
	Basalt = true,
	Ground = true,
	Mud = true,
	Snow = true,
	Glacier = true,
	Ice = true,
	CrackedLava = true,
	Limestone = true,
	Sandstone = true,
	Salt = true,
	Pavement = true,
	Asphalt = true,
	Cobblestone = true,
	Concrete = true,
	Brick = true,
	WoodPlanks = true,
}
local HAZARDS = { jelly = true, urchin = true, puffer = true, eel = true, shard = true, lava = true, orb = true }
local STYLES = { neon = true, glass = true, ghost = true, gold = true, rainbow = true, cosmic = true }

local function isHex(value: any): boolean
	return type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

section("World data")
do
	local petShapes = definedShapes("src/shared/Models/PetModels.luau")
	local relicShapes = definedShapes("src/shared/Models/RelicModels.luau")
	local decor = fs.readFile("src/server/World/Decor.luau")
	check(#Worlds.list == Config.WorldCount, "there are exactly " .. Config.WorldCount .. " worlds")
	local seenKeys = {}
	for index, world in Worlds.list do
		local label = "world " .. index
		check(world.index == index, label .. " index")
		check(world.name.en ~= "" and world.name.ko ~= "", label .. " has English and Korean names")
		check(not seenKeys[world.key], label .. " key unique")
		seenKeys[world.key] = true
		check(#world.relics == 5, label .. " has 5 relics")
		check(#world.pets == 5, label .. " has 5 pets")
		check(isHex(world.water), label .. " water colour")
		check(isHex(world.accent[1]) and isHex(world.accent[2]), label .. " accent colours")
		check(#world.fish >= 3, label .. " fish colours")
		for _, hex in world.fish do
			check(isHex(hex), label .. " fish colour " .. tostring(hex))
		end
		for _, key in { "land", "beach", "rock", "floor", "deep" } do
			check(TERRAIN_MATERIALS[world.terrain[key]] == true, label .. " terrain material " .. key .. " = " .. tostring(world.terrain[key]))
			check(isHex(world.terrain[key .. "Color"]), label .. " terrain colour " .. key)
		end
		for _, key in { "ambient", "outdoor", "atmo", "decay", "cloudColor" } do
			check(isHex((world.sky :: any)[key]), label .. " sky colour " .. key)
		end
		check(isHex(world.under.tint), label .. " underwater tint")
		check(string.find(decor, "\t" .. world.kit .. " = {", 1, true) ~= nil, label .. " decor kit '" .. world.kit .. "' exists")
		for rarity, relic in world.relics do
			check(relic.rarity == rarity, label .. " relic rarity order")
			check(relicShapes[relic.shape] == true, label .. " relic shape '" .. relic.shape .. "' exists")
			check(isHex(relic.color) and isHex(relic.accent), label .. " relic colours")
			check(relic.style == nil or STYLES[relic.style], label .. " relic style")
			check(relic.name.en ~= "" and relic.name.ko ~= "", label .. " relic names")
		end
		for rarity, pet in world.pets do
			check(pet.rarity == rarity, label .. " pet rarity order")
			check(petShapes[pet.shape] == true, label .. " pet shape '" .. pet.shape .. "' exists")
			check(isHex(pet.color) and isHex(pet.accent), label .. " pet colours")
			check(pet.style == nil or STYLES[pet.style], label .. " pet style")
		end
		if world.secret then
			check(petShapes[world.secret.shape] == true, label .. " secret shape exists")
			check(world.secret.rarity == 6, label .. " secret rarity")
		end
		for _, hazard in world.hazards do
			check(HAZARDS[hazard.kind] == true, label .. " hazard kind " .. hazard.kind)
		end
	end
	local secrets = 0
	for _, pet in Worlds.pets do
		if pet.secret then
			secrets += 1
		end
	end
	check(secrets == 5, "five secret pets (every fourth world)")
end

section("Economy curves")
do
	for world = 1, Config.WorldCount do
		if world > 1 then
			check(Economy.goal(world) > Economy.goal(world - 1), "goal grows at world " .. world)
			check(Economy.eggCost(world) > Economy.eggCost(world - 1), "egg cost grows at world " .. world)
			check(Economy.depthStuds(world) > Economy.depthStuds(world - 1), "depth grows at world " .. world)
			check(Economy.relicValue(world, 1) > Economy.relicValue(world - 1, 1), "relic value grows at world " .. world)
			check(Economy.pressure(world) > Economy.pressure(world - 1), "pressure grows at world " .. world)
		end
		for rarity = 2, 5 do
			check(Economy.relicValue(world, rarity) > Economy.relicValue(world, rarity - 1), "rarity raises value")
		end
		local total = 0
		for _, entry in Economy.eggChances(world, false) do
			total += entry.chance
			check(Worlds.pets[entry.key] ~= nil, "egg chance key valid")
		end
		check(math.abs(total - 1) < 1e-9, "egg chances sum to 1 in world " .. world)
		local luckyTotal = 0
		for _, entry in Economy.eggChances(world, true) do
			luckyTotal += entry.chance
		end
		check(math.abs(luckyTotal - 1) < 1e-9, "lucky egg chances sum to 1 in world " .. world)
		for _, roll in { 0, 0.0001, 0.3, 0.6, 0.9, 0.99, 0.999999 } do
			local key = Economy.rollPet(world, false, roll)
			check(Worlds.pets[key] ~= nil and Worlds.pets[key].world == world, "rollPet returns a pet of world " .. world)
		end
	end
	check(Economy.rollPet(4, false, 0) == "s4", "roll 0 in a secret egg gives the secret pet")
	check(Economy.rollPet(1, false, 0) == "p1.1", "roll 0 in a normal egg gives the common pet")
	-- Gear: 2 pieces per world per slot, every tier strictly better and pricier than the last.
	check(#Gear.list == Config.WorldCount * 2 * #Gear.Slots, "160 gear pieces")
	for _, slot in Gear.Slots do
		local items = Gear.bySlot[slot]
		check(#items == Gear.Tiers, slot .. " has 40 tiers")
		local previousValue, previousCost = Economy.gearValue(slot, 0), 0
		for index, item in items do
			check(item.tier == index and Gear.byKey[item.key] == item, slot .. " tier order " .. index)
			local value = Economy.gearValue(slot, item.tier)
			local cost = Economy.gearCost(item.key) :: number
			check(value > previousValue, slot .. " value grows at tier " .. index)
			check(cost > previousCost, slot .. " price grows at tier " .. index)
			previousValue, previousCost = value, cost
		end
		local def = Economy.Tracks[slot]
		check(math.abs(Economy.gearValue(slot, Gear.Tiers) - Economy.upgradeValue(slot, def.max)) < 1e-9, slot .. " top tier reaches max")
	end
	check(Economy.stat(nil, "pack") == 4 and Economy.stat({ pack = "pack1a" }, "pack") > 4, "starter and equipped stat")
	check(Economy.gearCost("nope") == nil and Gear.tier("nope") == 0, "unknown gear")
	-- Mutations add their multipliers and never repeat on one pet.
	check(Economy.mutationMultiplier(nil) == 1 and Economy.mutationMultiplier({}) == 1, "no mutation is x1")
	check(Economy.mutationMultiplier({ "Gold" }) == 2 and Economy.mutationMultiplier({ "Gold", "Lava" }) == 7, "mutations stack by adding")
	check(Economy.mutationMultiplier({ "Gold", "Diamond", "Galaxy", "Lava", "GOAT" }) == 20, "all mutations x20")
	check(Economy.petPower("p1.1", { "Galaxy" }) == Economy.petBoost("p1.1") * 4, "mutation scales the pet boost")
	local owned: { string } = {}
	for i = 1, #Config.Mutations do
		local key = Economy.rollMutation(owned, (i * 0.37) % 1)
		check(key ~= nil and not table.find(owned, key), "enchant adds a new mutation")
		table.insert(owned, key :: string)
		if i < #Config.Mutations then
			check(
				(Economy.mutateCost("p1.1", owned) :: number) > (Economy.mutateCost("p1.1", { table.unpack(owned, 1, i - 1) }) :: number),
				"enchants get pricier"
			)
		end
	end
	check(Economy.rollMutation(owned, 0.5) == nil and Economy.mutateCost("p1.1", owned) == nil, "no enchant past every mutation")
	for _, roll in { 0, 0.3, 0.7, 0.999 } do
		local lucky = Economy.rollMutation({}, roll, Config.LuckyMutations)
		check(lucky ~= nil and table.find(Config.LuckyMutations, lucky) ~= nil, "lucky enchants roll Galaxy+")
	end
	local chanceSum = 0
	for _, entry in Economy.mutationChances({ "Gold" }) do
		chanceSum += entry.chance
		check(entry.key ~= "Gold", "owned mutation not offered")
	end
	check(math.abs(chanceSum - 1) < 1e-9, "mutation chances sum to 1")
	check(Economy.unlockCost(1) == 0, "World 1 is free")
	for world = 3, Config.WorldCount do
		check(Economy.unlockCost(world) > Economy.unlockCost(world - 1), "unlock fee grows at world " .. world)
	end
	check(Economy.oxygenDrain(1, 0) == 1, "no pressure at the surface")
	check(Economy.oxygenDrain(20, Economy.depthStuds(20)) > Economy.oxygenDrain(1, Economy.depthStuds(1)), "deep worlds drain faster")
	local counts = { 0, 0, 0, 0, 0 }
	for i = 0, 9999 do
		local r = Economy.rollRarity(0.9, (i + 0.5) / 10000)
		counts[r] += 1
	end
	check(counts[1] > counts[5] and counts[5] > 0, "deep relic rolls include legendaries")
	check(Economy.nice(12345) == 12000 and Economy.nice(987) == 990 and Economy.nice(42) == 42, "nice rounding")
end

section("Formatting")
do
	check(Format.short(999) == "999", "short 999")
	check(Format.short(1000) == "1K", "short 1K -> " .. Format.short(1000))
	check(Format.short(12345) == "12.3K", "short 12.3K -> " .. Format.short(12345))
	check(Format.short(1500000) == "1.5M", "short 1.5M -> " .. Format.short(1500000))
	check(Format.short(2.5e12) == "2.5T", "short 2.5T -> " .. Format.short(2.5e12))
	check(Format.commas(1234567) == "1,234,567", "commas -> " .. Format.commas(1234567))
	check(Format.commas(12) == "12", "commas small")
	check(Format.seconds(42.4) == "42s" and Format.seconds(75) == "1:15", "seconds")
	check(Format.multiplier(1.25) == "x1.25" and Format.multiplier(340) == "x340", "multiplier -> " .. Format.multiplier(340))
	check(
		Format.percent(0.6) == "60%" and Format.percent(0.005) == "0.5%" and Format.percent(0.0005) == "0.05%",
		"percent -> " .. Format.percent(0.0005)
	)
	check(Format.fill("World {n}", { n = 3 }) == "World 3", "fill")
end

section("Strings")
do
	local missing = Strings.missingKorean()
	check(#missing == 0, "every English string has Korean: " .. table.concat(missing, ", "))
	-- Every literal Strings.get("key") in the code base must exist.
	local function scan(dir: string)
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				scan(path)
			elseif string.sub(name, -5) == ".luau" then
				local source = fs.readFile(path)
				for key in string.gmatch(source, 'Strings%.get%("([%w%.]+)"') do
					-- Keys ending in "." are prefixes completed at runtime (checked separately below).
					if string.sub(key, -1) ~= "." then
						check(Strings.hasKey(key), "string key '" .. key .. "' used in " .. path)
					end
				end
				-- Keys the server sends for the client to translate: handler errors and toasts.
				for key in string.gmatch(source, 'return false, "([%w%.]+)"') do
					check(Strings.hasKey(key), "error key '" .. key .. "' returned in " .. path)
				end
				for key in string.gmatch(source, '"(err%.[%w]+)"') do
					check(Strings.hasKey(key), "error key '" .. key .. "' used in " .. path)
				end
				for key in string.gmatch(source, 'toast", { key = "([%w%.]+)"') do
					check(Strings.hasKey(key), "toast key '" .. key .. "' pushed in " .. path)
				end
			end
		end
	end
	scan("src")
	for _, def in Config.Upgrades do
		for _, suffix in { "", ".desc", ".value" } do
			check(Strings.hasKey("upgrade." .. def.id .. suffix), "upgrade string " .. def.id .. suffix)
		end
		check(Strings.hasKey("gear." .. def.id), "gear name string " .. def.id)
	end
	for _, mutation in Config.Mutations do
		check(Strings.hasKey("mutation." .. mutation.key), "mutation string " .. mutation.key)
	end
	for _, pass in Config.Passes do
		check(Strings.hasKey("pass." .. pass.key) and Strings.hasKey("pass." .. pass.key .. ".desc"), "pass strings " .. pass.key)
	end
	for _, product in Config.Products do
		check(Strings.hasKey("product." .. product.key), "product string " .. product.key)
		if product.enchants > 0 then
			check(Strings.hasKey("product." .. product.key .. ".desc"), "product desc " .. product.key)
		end
	end
	for _, rarity in Config.Rarities do
		check(Strings.hasKey("rarity." .. rarity), "rarity string " .. rarity)
	end
	for _, key in { "worlds", "upgrades", "pets", "index", "shop", "settings" } do
		check(Strings.hasKey("menu." .. key), "menu string " .. key)
	end
	Strings.setLanguage("ko")
	check(Strings.get("world", { n = 2 }) == "월드 2", "Korean fill")
	Strings.setLanguage("en")
end

section("Profile repair")
do
	local fresh = Profile.reconcile(nil, 100)
	check(fresh.world == 1 and fresh.unlocked == 1 and fresh.coins == 0, "fresh defaults")
	local repaired = Profile.reconcile({
		coins = -50,
		unlocked = 99,
		world = 7,
		upgrades = { tank = 999, pack = "x" },
		pets = { P1 = { s = "p3.2", m = { "Gold", "Gold", "Fake", 3, "Lava" } }, P2 = { s = "nope" }, P3 = 5 },
		equipped = { "P1", "P1", "P2" },
		settings = { lang = "fr", sfx = false },
		worlds = { ["3"] = { sold = 12, cleared = true, best = 40 }, ["99"] = { sold = 1 } },
	}, 100)
	check(repaired.coins == 0, "negative coins clamp to 0")
	check(repaired.unlocked == Config.WorldCount, "unlocked clamps to world count")
	check(repaired.world == 7, "world kept when unlocked")
	check(repaired.gear.equip.tank == "tank20b" and repaired.gear.owned.tank20b, "old max tank level migrates to the top tank")
	check(repaired.gear.equip.pack == nil and next(repaired.gear.owned) ~= nil, "bad upgrade level gives starter gear")
	local mutations = repaired.pets.P1.m :: { string }
	check(#mutations == 2 and mutations[1] == "Gold" and mutations[2] == "Lava", "mutations deduplicated and filtered")
	local geared = Profile.reconcile(
		{ gear = { owned = { tank3a = true, fins9b = true, bogus = true }, equip = { tank = "tank3a", fins = "tank3a", pack = "pack1a" } } },
		5
	)
	check(geared.gear.owned.tank3a and geared.gear.owned.fins9b and not geared.gear.owned.bogus, "owned gear filtered")
	check(
		geared.gear.equip.tank == "tank3a" and geared.gear.equip.fins == nil and geared.gear.equip.pack == nil,
		"equip needs owned gear in its own slot"
	)
	check(Profile.reconcile({ enchants = -4 }, 5).enchants == 0, "lucky enchant tokens clamp")
	check(repaired.pets.P1 ~= nil and repaired.pets.P2 == nil and repaired.pets.P3 == nil, "invalid pets dropped")
	check(#repaired.equipped == 1, "equipped deduplicated and filtered")
	check(repaired.settings.lang == Config.DefaultLanguage and repaired.settings.sfx == false, "settings repaired")
	check(repaired.worlds["3"].cleared == true and repaired.worlds["99"] == nil, "world progress filtered")
	check(repaired.index["p3.2"] == true, "owned pets are in the index")
	local garbage = Profile.reconcile({ coins = 0 / 0, stats = { dives = math.huge } }, 5)
	check(garbage.coins == 0 and garbage.stats.dives == 0, "NaN and inf are rejected")
	local realKey = next(Worlds.relics) :: string
	local bag = Profile.reconcile({ backpack = { realKey, "fake.relic", 42, realKey } }, 5)
	check(#bag.backpack == 2 and bag.backpack[1] == realKey, "backpack keeps only real relic keys")
	local huge = {}
	for i = 1, Config.BackpackHardCap + 50 do
		huge[i] = realKey
	end
	check(#Profile.reconcile({ backpack = huge }, 5).backpack == Config.BackpackHardCap, "backpack capped")
	check(#Profile.new(5).backpack == 0, "new profiles start with an empty backpack")
end

section("Pacing simulation (efficient player)")
do
	-- Mirrors the tuning model: pick the best depth/haul per dive, buy the cheapest upgrade,
	-- hatch a few eggs per world, clear when the goal is met and the chest depth is reachable.
	local ODDS = Config.EggOdds
	local seed = 7
	local rng = {
		NextNumber = function(_self): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end,
	}
	local coins, eggBank = 0, 0
	local tiers = { tank = 0, pack = 0, fins = 0, magnet = 0 }
	local savingTotal = 0
	local boosts = {}
	local t = 0
	local function bestBoost(): number
		table.sort(boosts, function(a, b)
			return a > b
		end)
		local sum = 0
		for i = 1, math.min(3, #boosts) do
			sum += boosts[i]
		end
		return sum
	end
	local function dive(world: number)
		local depth = Economy.depthStuds(world)
		local oxygen = Economy.gearValue("tank", tiers.tank)
		local capacity = Economy.gearValue("pack", tiers.pack)
		local speed = Economy.gearValue("fins", tiers.fins)
		local magnet = Economy.gearValue("magnet", tiers.magnet)
		local best = nil
		for step = 1, 20 do
			local r = step / 20
			local perItem = 34 / speed + 1.4 - magnet * 0.03
			local descent = 2 * r * depth / (speed * 0.8)
			for k = 1, math.min(capacity, Config.Dive.ActiveRelics) do
				local duration = descent + k * perItem
				local drain = 1 + r * depth * Economy.pressure(world) * 0.75
				if duration * drain > oxygen * 0.88 then
					break
				end
				local weights = Economy.rarityWeights(r * 0.92)
				local wsum, vsum = 0, 0
				for i, w in weights do
					wsum += w
					vsum += w * Economy.relicValue(world, i)
				end
				local value = k * (vsum / wsum) * (1 + bestBoost())
				local rate = value / (duration + 7)
				if not best or rate > best.rate then
					best = { rate = rate, value = value, time = duration + 7, count = k }
				end
			end
		end
		return best
	end
	-- Up to 8 eggs per world from the egg budget; the rest of the budget turns back into coins.
	local function hatch(world: number, eggs: number): number
		while eggBank >= Economy.eggCost(world) and eggs < 8 do
			eggBank -= Economy.eggCost(world)
			eggs += 1
			local roll, acc, rarity = rng:NextNumber() * 100, 0, 1
			for i, odds in ODDS do
				acc += odds
				if roll <= acc then
					rarity = i
					break
				end
			end
			table.insert(boosts, Economy.petBoost(Worlds.get(world).pets[rarity].key))
		end
		if eggs >= 8 then
			coins += eggBank
			eggBank = 0
		end
		return eggs
	end
	local rows = {}
	for world = 1, Config.WorldCount do
		local sold, started, eggs, saving = 0, t, 0, 0
		while true do
			local result = dive(world) or dive(math.max(1, world - 1))
			assert(result, "no viable dive")
			t += result.time
			sold += result.count
			coins += result.value * 0.65
			eggBank += result.value * 0.35
			-- Buys the next gear piece in the cheapest slot (conservative: players may also skip
			-- tiers). Only gear of unlocked worlds is for sale.
			while true do
				local cheapest, cheapestSlot = math.huge, nil
				for _, slot in Gear.Slots do
					local nextItem = Gear.bySlot[slot][tiers[slot] + 1]
					if nextItem and nextItem.world <= world then
						local cost = Economy.gearCost(nextItem.key) :: number
						if cost < cheapest then
							cheapest, cheapestSlot = cost, slot
						end
					end
				end
				if not cheapestSlot or cheapest > coins then
					break
				end
				coins -= cheapest
				tiers[cheapestSlot] += 1
			end
			eggs = hatch(world, eggs)
			local depth = Economy.depthStuds(world)
			local chestTime = 2 * depth / (Economy.gearValue("fins", tiers.fins) * 0.8) + 3
			local chestDrain = 1 + depth * Economy.pressure(world) * 0.7
			if sold >= Economy.goal(world) and chestTime * chestDrain < Economy.gearValue("tank", tiers.tank) * 0.9 then
				-- Cleared: keep diving (no gear shopping, eggs still hatch) until the next world's
				-- unlock fee is saved.
				coins += Economy.clearReward(world)
				local fee = if world < Config.WorldCount then Economy.unlockCost(world + 1) else 0
				local savingStart = t
				while coins < fee do
					local result2 = dive(world) :: any
					t += result2.time
					coins += result2.value * 0.65
					eggBank += result2.value * 0.35
					eggs = hatch(world, eggs)
					assert(t - savingStart < 20 * 3600, "unlock fee for world " .. (world + 1) .. " is unreachable")
				end
				coins -= fee
				saving = t - savingStart
				savingTotal += saving
				break
			end
			if t - started > 5 * 3600 then
				break
			end
		end
		table.insert(
			rows,
			string.format(
				"  world %2d: %5.1f min (saving %4.1f, total %6.1f)  tank %2d pack %2d fins %2d magnet %2d  boost x%s",
				world,
				(t - started) / 60,
				saving / 60,
				t / 60,
				tiers.tank,
				tiers.pack,
				tiers.fins,
				tiers.magnet,
				Format.short(1 + bestBoost())
			)
		)
	end
	print(table.concat(rows, "\n"))
	print(string.format("  saving for unlock fees: %.1f min of %.1f", savingTotal / 60, t / 60))
	check(t / 60 > 200 and t / 60 < 380, "efficient full clear takes 3.5-6 hours (" .. math.floor(t / 60) .. " min)")
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	process.exit(1)
end
