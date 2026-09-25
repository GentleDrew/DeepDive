--!strict
-- Runtime state per connected player (the persistent part lives in `profile`).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Profile = require(Shared.Profile)

local Sessions = {}

export type Session = {
	player: Player,
	profile: Profile.Data,
	world: number,
	ready: boolean,
	mode: string, -- "Dock" | "Diving" | "Rescue" | "Travel"
	oxygen: number,
	oxygenMax: number,
	layoutId: number,
	relics: { [number]: string },
	chestActive: boolean,
	chestCarried: boolean,
	diveStart: number, -- backpack size when the current dive began
	lastSell: number,
	surfacedFor: number,
	syncTimer: number,
	lastHazard: number,
	maxDepth: number,
	passes: { [string]: boolean },
	rng: Random,
	busy: boolean,
	trade: any?, -- the open trade this player is in (TradeService)
}

local sessions: { [Player]: Session } = {}

function Sessions.create(player: Player, profile: Profile.Data): Session
	local session: Session = {
		player = player,
		profile = profile,
		world = profile.world,
		ready = false,
		mode = "Dock",
		oxygen = 0,
		oxygenMax = 0,
		layoutId = 0,
		relics = {},
		chestActive = false,
		chestCarried = false,
		diveStart = 0,
		lastSell = 0,
		surfacedFor = 0,
		syncTimer = 0,
		lastHazard = 0,
		maxDepth = 0,
		passes = {},
		rng = Random.new(),
		busy = false,
		trade = nil,
	}
	session.oxygenMax = Economy.stat(profile.gear.equip, "tank")
	session.oxygen = session.oxygenMax
	sessions[player] = session
	return session
end

function Sessions.get(player: Player): Session?
	return sessions[player]
end

function Sessions.remove(player: Player)
	sessions[player] = nil
end

function Sessions.all(): { [Player]: Session }
	return sessions
end

function Sessions.equipCap(session: Session): number
	return Config.PetEquipBase + (if session.passes.PetSlots then Config.PetEquipPass else 0)
end

function Sessions.boostSum(session: Session): number
	local sum = 0
	for _, id in session.profile.equipped do
		local pet = session.profile.pets[id]
		if pet then
			sum += Economy.petPower(pet.s, pet.m)
		end
	end
	return sum
end

function Sessions.multiplier(session: Session): number
	local boosted = session.profile.boostUntil > os.time()
	return Economy.coinMultiplier(Sessions.boostSum(session), session.passes.DoubleCoins == true, boosted)
end

-- Equipped pets as JSON ("species" or "species|Gold,Lava" with mutations), replicated so every
-- client can render followers.
function Sessions.publishPets(session: Session)
	local keys = {}
	for _, id in session.profile.equipped do
		local pet = session.profile.pets[id]
		if pet then
			table.insert(keys, if pet.m and #pet.m > 0 then pet.s .. "|" .. table.concat(pet.m, ",") else pet.s)
		end
	end
	session.player:SetAttribute("Pets", HttpService:JSONEncode(keys))
end

return Sessions
