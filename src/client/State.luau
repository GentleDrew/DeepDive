--!strict
-- Client-side store: latest profile snapshot, current world, relic layout and dive state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Profile = require(Shared.Profile)
local Signal = require(Shared.Signal)

local State = {}

export type Layout = { id: number, world: number, relics: { [number]: string }, chest: boolean }
export type Dive = {
	active: boolean,
	blackout: boolean,
	oxygen: number,
	max: number,
	cargo: number,
	chestCarried: boolean,
	depth: number,
	inWater: boolean,
	swimming: boolean,
}

State.profile = nil :: Profile.Data?
State.passes = {} :: { [string]: boolean }
State.world = 1
State.memory = false
State.layout = { id = 0, world = 1, relics = {}, chest = false } :: Layout
State.dive = {
	active = false,
	blackout = false,
	oxygen = 0,
	max = 1,
	cargo = 0,
	chestCarried = false,
	depth = 0,
	inWater = false,
	swimming = false,
} :: Dive
State.traveling = false

State.profileChanged = Signal.new()
State.worldChanged = Signal.new()
State.layoutChanged = Signal.new()
State.diveChanged = Signal.new()
State.languageChanged = Signal.new()
State.settingsChanged = Signal.new()

function State.applyView(view: any)
	if type(view) ~= "table" or type(view.profile) ~= "table" then
		return
	end
	local previousWorld = State.world
	local previousLang = State.profile and State.profile.settings.lang
	local previousSettings = State.profile and State.profile.settings
	State.profile = view.profile
	State.passes = view.passes or {}
	State.memory = view.memory == true
	State.world = view.world or view.profile.world or 1
	if type(view.profile.backpack) == "table" then
		State.dive.cargo = #view.profile.backpack
	end
	State.profileChanged:Fire(State.profile)
	if State.world ~= previousWorld then
		State.worldChanged:Fire(State.world)
	end
	local profile = State.profile :: Profile.Data
	if profile.settings.lang ~= previousLang then
		State.languageChanged:Fire(profile.settings.lang)
	end
	if previousSettings ~= profile.settings then
		State.settingsChanged:Fire(profile.settings)
	end
end

-- Stat from the equipped gear in a slot ("tank", "pack", "fins", "magnet").
function State.upgrade(track: string): number
	local profile = State.profile
	return Economy.stat(if profile then profile.gear.equip else nil, track)
end

function State.capacity(): number
	return State.upgrade("pack")
end

function State.swimSpeed(): number
	return State.upgrade("fins") * (if State.passes.SwiftFins then Config.SwiftFinsBonus else 1)
end

function State.boostSum(): number
	local profile = State.profile
	if not profile then
		return 0
	end
	local sum = 0
	for _, id in profile.equipped do
		local pet = profile.pets[id]
		if pet then
			sum += Economy.petPower(pet.s, pet.m)
		end
	end
	return sum
end

function State.multiplier(): number
	return Economy.coinMultiplier(State.boostSum(), State.passes.DoubleCoins == true)
end

function State.equipCap(): number
	return Config.PetEquipBase + (if State.passes.PetSlots then Config.PetEquipPass else 0)
end

function State.progress(world: number?): Profile.WorldProgress
	local profile = State.profile
	local w = world or State.world
	if not profile then
		return { sold = 0, cleared = false, best = 0 }
	end
	return profile.worlds[tostring(w)] or { sold = 0, cleared = false, best = 0 }
end

function State.settings()
	local profile = State.profile
	if profile then
		return profile.settings
	end
	return { music = true, sfx = true, lowFx = false, hidePets = false, lang = Config.DefaultLanguage }
end

return State
