--!strict
-- Deep Dive tuning values. Pure data (no Roblox datatypes) so the luau/lune test runner can load it.
-- Economy curves were tuned with a pacing simulation: World 1 clears in ~2 minutes, the full 20
-- worlds take an efficient player ~2 hours (roughly 3-4 hours of normal play).

local Config = {}

Config.Title = "Deep Dive"
Config.Version = "1.0.0"
Config.DataStoreName = "DeepDive_Profiles_v1"
Config.SchemaVersion = 1

-- "auto" follows the Roblox locale (ko -> Korean). Roblox has no rounded Hangul font, so the
-- default is English, which renders entirely in FredokaOne.
Config.DefaultLanguage = "en"

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
	ActiveRelics = 20,
	CollectTolerance = 10,
	CollectPerSecond = 14,
	BlackoutKeep = 0.5,
	HazardPenalty = 5,
	HazardImmunity = 1.25,
	OxygenWarn = 0.35,
	OxygenDanger = 0.18,
	RefillSeconds = 1.2,
	ServerHz = 10,
}

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
Config.EggBaseCost = 200
Config.EggWorldGrowth = 1.8
Config.PetEquipBase = 3
Config.PetEquipPass = 2
Config.PetInventoryCap = 60

-- World progression.
Config.GoalBase = 12
Config.GoalGrowth = 1.2
Config.DepthBase = 40 -- studs, World 1
Config.DepthStep = 7.2
Config.RadiusBase = 74
Config.RadiusStep = 1.6
Config.PressureBase = 0.010 -- extra oxygen drain per stud of depth
Config.PressureStep = 0.0016
Config.ClearRewardRelics = 60 -- first-clear bonus = this many common relics of that world

Config.Upgrades = {
	{
		id = "tank",
		max = 30,
		base = 30,
		growth = 2.08,
		icon = "O2",
		color = "#3fd2ff",
	},
	{
		id = "pack",
		max = 30,
		base = 45,
		growth = 2.08,
		icon = "BAG",
		color = "#ffb13f",
	},
	{
		id = "fins",
		max = 25,
		base = 65,
		growth = 2.25,
		icon = "FIN",
		color = "#5ee280",
	},
	{
		id = "magnet",
		max = 15,
		base = 110,
		growth = 2.6,
		icon = "MAG",
		color = "#ff6f91",
	},
}

-- Monetisation. id = 0 means "not created yet": the card shows "Coming soon" and cannot be bought.
-- Create the passes / products on the Creator Dashboard and paste their ids here.
Config.Passes = {
	{ key = "DoubleCoins", id = 0, price = 199, color = "#ffc62e" },
	{ key = "LuckyEggs", id = 0, price = 249, color = "#be68ff" },
	{ key = "PetSlots", id = 0, price = 149, color = "#5ee280" },
	{ key = "SwiftFins", id = 0, price = 99, color = "#3fd2ff" },
}
Config.Products = {
	{ key = "CoinsSmall", id = 0, price = 25, dives = 4, color = "#ffd84f" },
	{ key = "CoinsMedium", id = 0, price = 99, dives = 20, color = "#ffb13f" },
	{ key = "CoinsLarge", id = 0, price = 299, dives = 75, color = "#ff8a3f" },
}
Config.SwiftFinsBonus = 1.25

-- Built-in engine sounds only (no uploaded audio needed).
Config.Sounds = {
	Ping = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/clickfast.wav",
	Splash = "rbxasset://sounds/impact_water.mp3",
	Snap = "rbxasset://sounds/snap.wav",
	Swim = "rbxasset://sounds/action_swim.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
}
-- Optional background music (rbxassetid://...). Empty = silent.
Config.Music = {
	Surface = "",
	Underwater = "",
}

return Config
