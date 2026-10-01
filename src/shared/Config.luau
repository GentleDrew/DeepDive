--!strict
-- Deep Dive tuning values. Pure data (no Roblox datatypes) so the luau/lune test runner can load it.
-- Economy curves were tuned with a pacing simulation (tests/run.luau). World treasure goals
-- (Config.GoalBase/GoalGrowth) were later doubled on their own, which also roughly doubles the
-- unlock fees below (they scale with the goal): Worlds 1-5 still clear in well under an hour,
-- but the full 20 worlds now take an efficient player ~23 hours, well over a full day of normal
-- play. Lower GoalBase back toward 16 to return to the earlier, gentler pace.

local Config = {}

Config.Title = "Deep Dive"
Config.Version = "1.0.0"
Config.DataStoreName = "DeepDive_Profiles_v1"
Config.SchemaVersion = 1

-- "auto" follows the Roblox locale (ko -> Korean). Roblox has no rounded Hangul font, so the
-- default is English, which renders entirely in FredokaOne.
Config.DefaultLanguage = "en"

-- The game's creator (game.CreatorId, when solo-owned) always gets the red "Operator" nameplate
-- and aura, free. Add other UserIds here too (co-developers, moderators) if you want them to have
-- it as well, or if the experience is group-owned (game.CreatorId is then the group, not a player).
Config.AdminUserIds = { 2201094984 } -- Gentle_Drew

Config.WorldCount = 20
Config.WorldSpacing = 1000
Config.WorldColumns = 5
Config.SurfaceY = 0
Config.OceanDepth = 16

Config.Swim = {
	DashMultiplier = 1.8,
	DashSeconds = 0.42,
	DashCooldown = 1.5,
	VerticalFactor = 0.85,
	Accel = 7.5,
	DashAccel = 16,
	FloatOffset = 1.6, -- root rests this far below the surface while floating
	PitchDeadzone = 14, -- degrees of camera pitch that still swim level
	EnterDepth = 2.2, -- root depth that starts swim mode
	ExitDepth = 1.85, -- floating shallower than this over nearby ground walks out
	SurfaceJumpPower = 52,
}

Config.Dive = {
	SubmergeDepth = 3.2, -- root depth at which a dive starts (head fully under)
	SurfaceDepth = 2.4, -- root depth above which the diver counts as surfaced
	SurfaceHold = 0.25,
	ActiveRelics = 30, -- matches World/WorldBuilder's POINT_COUNT: every scanned spot holds a relic
	RelicRespawnMin = 6, -- a collected point refills with a fresh relic after this many seconds...
	RelicRespawnMax = 14, -- ...up to this many, as long as you're still diving the same layout
	CollectTolerance = 10,
	CollectPerSecond = 14,
	BlackoutKeep = 0.5,
	HazardPenalty = 0.2, -- each hazard hit costs this share of your max oxygen
	HazardImmunity = 1.25,
	OxygenWarn = 0.35,
	OxygenDanger = 0.18,
	RefillSeconds = 1.2,
	ServerHz = 10,
}

-- Selling happens at each world's sell stand (not on surfacing).
Config.SellRadius = 9 -- standing this close to the sell pad sells the backpack
Config.BackpackHardCap = 400 -- sanity cap for stored treasure

Config.Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Secret" }
Config.RarityColors = {
	Common = "#c9d6de",
	Uncommon = "#5ee280",
	Rare = "#3fa9ff",
	Epic = "#be68ff",
	Legendary = "#ffc62e",
	Secret = "#ff4f8b",
}

-- Relic value multiplier per rarity (index = rarity index).
Config.RelicRarityValue = { 1, 2.5, 6.5, 16, 45 }
Config.RelicBaseValue = 8
Config.RelicWorldGrowth = 1.62

-- Pet boosts: base(world) * factor(rarity). Boosts add up: coins x (1 + sum).
Config.PetBaseBoost = 0.2
Config.PetWorldGrowth = 1.36
Config.PetRarityFactor = { 1, 1.9, 3.6, 7, 16, 40 }
Config.EggOdds = { 60, 26, 10, 3.5, 0.5 } -- percent for rarity 1..5
Config.SecretChance = 0.0005 -- 1 in 2000, only in eggs that carry a secret pet
Config.LuckyMultiplier = 2 -- Lucky Eggs pass: Epic+ odds x2
Config.EggBaseCost = 800
Config.EggWorldGrowth = 1.85
Config.PetEquipBase = 3
Config.PetEquipPass = 2
Config.PetInventoryCap = 60

-- World progression.
Config.GoalBase = 32
Config.GoalGrowth = 1.175
Config.DepthBase = 40 -- studs, World 1
Config.DepthStep = 7.2
Config.RadiusBase = 74
Config.RadiusStep = 1.6
Config.PressureBase = 0.010 -- extra oxygen drain per stud of depth
Config.PressureStep = 0.0016
-- Extra pressure that grows with the square of the world number: barely felt early, it makes the
-- last worlds hard even with top gear (dive, farm a while, surface).
Config.PressureCurve = 0.00006
Config.ClearRewardRelics = 60 -- first-clear bonus = this many common relics of that world
-- Clearing a world makes the next one available; unlocking world N costs a fee worth
-- UnlockClears[N] treasure goals of income (see Economy.unlockCost). The curve keeps the first
-- worlds quick and makes the middle of the game a grind to push through.
-- stylua: ignore
Config.UnlockClears = {
	0, 1.1, 1.9, 1.4, 1.3, 5.9, 36, 40, 42, 36,
	34, 25, 16, 20, 15, 11.5, 12, 8.5, 18, 12,
}
Config.UnlockPetRamp = 4 -- worlds over which the fee's pet-boost part ramps in

-- Stat curves the gear tiers map onto (see Data/Gear.luau and Economy.gearValue). `base` and
-- `growth` shape gear prices: price = GearPriceScale * base * growth ^ (level - 2).
Config.Upgrades = {
	{ id = "tank", max = 30, base = 30, growth = 2.08, color = "#3fd2ff" },
	{ id = "pack", max = 30, base = 45, growth = 2.08, color = "#ffb13f" },
	{ id = "fins", max = 25, base = 65, growth = 2.25, color = "#5ee280" },
	{ id = "magnet", max = 15, base = 110, growth = 2.6, color = "#ff6f91" },
}
Config.GearCurve = 0.75 -- < 1: early tiers climb the stat curves faster
Config.GearPriceScale = 4
Config.GearFloorRelics = 80

-- Pet mutations (enchanting). An enchant adds one random mutation the pet does not have yet;
-- multipliers add up (Gold x2 + Lava x5 = x7) and scale the pet's boost.
Config.Mutations = {
	{ key = "Gold", mult = 2, weight = 50, color = "#ffc62e" },
	{ key = "Diamond", mult = 3, weight = 26, color = "#7ff0ff" },
	{ key = "Galaxy", mult = 4, weight = 14, color = "#9a5cff" },
	{ key = "Lava", mult = 5, weight = 7.5, color = "#ff5a1f" },
	{ key = "GOAT", mult = 6, weight = 2.5, color = "#ff4fd8" },
}
-- Limited mutations come pre-applied on limited pets only: never rolled by enchanting, but they
-- add their multiplier like any other and the pet can still be enchanted with the regular ones.
Config.LimitedMutations = {
	{ key = "GOD", mult = 8, weight = 0, color = "#fff06a" },
}
-- Limited pets (Robux only, never in eggs) are this many times the last world's secret pet.
Config.LimitedPetFactor = 1.5
-- Enchant price = this x the egg price of the pet's world, by mutations already on the pet.
Config.MutationCost = { 3, 8, 20, 50, 120 }

-- Trading.
Config.TradeMaxPets = 8
Config.TradeCountdown = 3
Config.TradeRequestSeconds = 20

-- Monetisation. id = 0 means "not created yet": the card shows "Coming soon" and cannot be bought.
-- Create the passes / products on the Creator Dashboard and paste their ids here.
Config.Passes = {
	{ key = "DoubleCoins", id = 2002856341, price = 199, color = "#ffc62e" },
	{ key = "LuckyEggs", id = 2001476598, price = 249, color = "#be68ff" },
	{ key = "PetSlots", id = 1999041680, price = 149, color = "#5ee280" },
	{ key = "SwiftFins", id = 2003210309, price = 99, color = "#3fd2ff" },
	-- Cosmetic only (a crown by your name + a gold sparkle trail): no gameplay effect.
	{ key = "VIPAura", id = 1998771645, price = 299, color = "#ffd23f" },
	-- Sells your backpack for you the instant you surface, from anywhere (skips the walk to the
	-- sell stand). Pure convenience: prices are unchanged, it just saves the trip.
	{ key = "AutoSell", id = 2001482530, price = 249, color = "#ff9a3f" },
	-- Cosmetic sparkle trail while swimming. No gameplay effect.
	{ key = "SwimTrail", id = 1998447645, price = 149, color = "#5ee0ff" },
	-- Cosmetic nameplate border tiers (own both: the higher tier shows). No gameplay effect.
	{ key = "BorderSilver", id = 2001254546, price = 149, color = "#c9d6de" },
	{ key = "BorderGold", id = 2003516280, price = 299, color = "#ffd23f" },
	-- One-time starter bundle (see Config.StarterPackReward). Granted once, on first purchase.
	{ key = "StarterPack", id = 2001872530, price = 99, color = "#5ee07a" },
}
-- One-time StarterPack grant (Profile.starterPackGranted guards against granting it twice).
Config.StarterPackReward = { coins = 5000, gearKey = "pack1b", enchants = 1 }
Config.Products = {
	{ key = "CoinsSmall", id = 3715542283, price = 25, dives = 4, enchants = 0, color = "#ffd84f" },
	{ key = "CoinsMedium", id = 3715542400, price = 99, dives = 20, enchants = 0, color = "#ffb13f" },
	{ key = "CoinsLarge", id = 3715542481, price = 299, dives = 75, enchants = 0, color = "#ff8a3f" },
	-- Lucky Enchants: free enchants that only roll Galaxy, Lava or GOAT.
	{ key = "LuckyEnchant", id = 3715542792, price = 79, dives = 0, enchants = 3, color = "#be68ff" },
	-- Coins worth exactly the fee to unlock your next world (or a flat bonus once you own World 20).
	{ key = "UnlockBoost", id = 3715542911, price = 149, dives = 0, enchants = 0, unlockBoost = true, color = "#4fe07a" },
	-- Unlocks your next world immediately at no coin cost (needs the world before it cleared;
	-- otherwise grants the same coins as UnlockBoost so the purchase always delivers value).
	{ key = "InstantUnlock", id = 3715543037, price = 199, dives = 0, enchants = 0, instantUnlock = true, color = "#4fe07a" },
	-- Doubles coin payouts for Config.TimedBoostMinutes (stacks its own duration; multiplies
	-- with the 2x Coins pass).
	{ key = "TimedBoost", id = 3715543178, price = 149, dives = 0, enchants = 0, timedBoost = true, color = "#ff6fb1" },
	-- Rerolls one of your unlocked pets into a fresh roll from its own world's egg (mutations
	-- reset). Picks the weakest eligible pet automatically; grants coins if none is eligible.
	{ key = "PetReroll", id = 3715543278, price = 49, dives = 0, enchants = 0, petReroll = true, color = "#3fd2ff" },
	-- Guarantees the rarest mutation you don't have yet on one eligible pet (no random roll).
	-- Picks automatically; grants coins if every pet is already fully mutated.
	{ key = "GuaranteedMutation", id = 3715543343, price = 129, dives = 0, enchants = 0, guaranteedMutation = true, color = "#9a5cff" },
	-- Tops your backpack off with common relics of your current world, up to capacity.
	{ key = "BackpackFill", id = 3715543440, price = 49, dives = 0, enchants = 0, backpackFill = true, color = "#ffb13f" },
	-- Limited GOD Shark: fill in the developer product id from the Creator Dashboard.
	{ key = "GodShark", id = 0, price = 399, dives = 0, enchants = 0, godShark = true, color = "#7fd3ff" },
}
Config.TimedBoostMinutes = 45
Config.TimedBoostMultiplier = 2
-- Promo codes redeemable once per player from Settings. Add more anytime; nothing needs
-- redeploying beyond this list. `coins` and/or `enchants` are granted on a valid, unused code.
export type PromoCode = { code: string, coins: number?, enchants: number? }
Config.PromoCodes = {
	{ code = "LAUNCH", coins = 2000 } :: PromoCode,
}
Config.LuckyMutations = { "Galaxy", "Lava", "GOAT" }
Config.SwiftFinsBonus = 1.25

-- Built-in engine sounds (no uploaded audio needed). Cues layer and re-pitch these.
Config.Sounds = {
	Ping = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/clickfast.wav",
	Button = "rbxasset://sounds/button.wav",
	Swoosh = "rbxasset://sounds/swoosh.wav",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Snap = "rbxasset://sounds/snap.wav",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Swim = "rbxasset://sounds/action_swim.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
}
-- Optional: paste Creator Store audio ids ("rbxassetid://123...") to replace any cue with a
-- real recording. Empty = use the built-in layered version.
Config.SoundIds = {
	Collect = "",
	CollectRare = "",
	Discover = "",
	Sell = "",
	Coin = "",
	Splash = "",
	Upgrade = "",
	Hatch = "",
	Reveal = "",
	Legendary = "",
	Clear = "",
	Click = "",
	Open = "",
	Error = "",
	Blackout = "",
}
-- Background music: these play shuffled, back to back, for as long as the Music setting is on.
Config.MusicTracks = {
	"rbxassetid://90752425060144", -- Puyaya
	"rbxassetid://113701688350194", -- Mayaya
	"rbxassetid://100256195388464", -- Heyaya
	"rbxassetid://134192020743091", -- Kayaya
	"rbxassetid://97032382875419", -- Kuyaya
}
Config.MusicVolume = 0.35
Config.MusicUnderwaterVolume = 0.2

-- Daily login rewards: one claim per UTC day. Claiming the day after your last claim moves the
-- streak on; missing a day starts it over at Day 1. After Day 7 the cycle repeats.
-- `dives` scales coins to the player's progress (Economy.productCoins, like the coin packs).
Config.DailyRewards = {
	{ dives = 0.5 },
	{ dives = 0.75 },
	{ dives = 1, enchants = 1 },
	{ dives = 1.25 },
	{ dives = 1.5 },
	{ dives = 2 },
	{ dives = 3, enchants = 2, boostMinutes = 15 },
}

-- Playtime rewards: each tier unlocks after that many minutes played today (UTC) and can be
-- claimed once per day.
Config.PlaytimeRewards = {
	{ minutes = 5, dives = 0.3 },
	{ minutes = 15, dives = 0.5 },
	{ minutes = 30, dives = 0.8 },
	{ minutes = 45, dives = 1, enchants = 1 },
	{ minutes = 60, dives = 1.2 },
	{ minutes = 90, dives = 1.5, boostMinutes = 10 },
}

-- The starter pack sits on the right of the HUD for this many hours after a player's first
-- visit, with a real countdown. Afterwards it is still sold in the shop, just not advertised.
Config.StarterOfferHours = 48

-- Purchase offers (small pop-ups): one every OfferGap seconds (the first after OfferFirstDelay),
-- picked by what the diver is missing; the same item at most once per OfferRepeat.
Config.OfferFirstDelay = 90
Config.OfferGap = 180
Config.OfferRepeat = 540
Config.OfferMaxPerSession = 60

-- The community group players are invited to join (0 = the group that owns the experience).
-- Joining pays a one-time reward worth GroupRewardDives of coin packs plus enchants.
Config.GroupId = 0
Config.GroupRewardDives = 3
Config.GroupRewardEnchants = 1

-- Ranking tiers: earned by holding a top-3 spot on a ranking board for a total number of hours
-- (tiers 1-6 on the weekly board, 7-8 on the monthly board). Earned tiers are permanent and show
-- as the diver's name colour. Red is reserved for the Director (Operator).
Config.Tiers = {
	{ hours = 10, board = "weekly", color = "#5ee6a8" },
	{ hours = 24, board = "weekly", color = "#4fd8ff" },
	{ hours = 72, board = "weekly", color = "#4f86ff" },
	{ hours = 100, board = "weekly", color = "#a66bff" },
	{ hours = 120, board = "weekly", color = "#ff6fd1" },
	{ hours = 140, board = "weekly", color = "#ffa73f" },
	{ hours = 14 * 24, board = "monthly", color = "#ffe14f" },
	{ hours = 30 * 24, board = "monthly", color = "#e8f6ff", prismatic = true },
}
-- The ranking board (and the podium statues behind it) cycle weekly -> monthly -> all-time.
Config.BoardRotateSeconds = 20

return Config
