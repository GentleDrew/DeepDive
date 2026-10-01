--!strict
-- Egg hatching (server-side rolls), equipping, locking and deleting pets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Layout = require(Shared.Layout)
local Profile = require(Shared.Profile)

local Net = require(script.Parent.Parent.Net)
local Sessions = require(script.Parent.Parent.Sessions)
local Sync = require(script.Parent.Parent.Sync)

local PetService = {}

type Session = Sessions.Session

local function nearEgg(session: Session, world: number): boolean
	local character = session.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local dock = Layout.dock(world)
	local eggPosition = Layout.origin(world) + Vector3.new(dock.egg.X, dock.egg.Y + 4, dock.egg.Z)
	return (root.Position - eggPosition).Magnitude < 26
end

local function hatch(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return false, "err.notReady"
	end
	if type(payload) ~= "table" then
		return false, "err.generic"
	end
	local world = tonumber(payload.world)
	local count = tonumber(payload.count)
	if not world or not count or (count ~= 1 and count ~= 3 and count ~= 5) then
		return false, "err.generic"
	end
	world = math.floor(world)
	local profile = session.profile
	if world < 1 or world > profile.unlocked then
		return false, "err.locked"
	end
	if session.world ~= world or not nearEgg(session, world) then
		return false, "err.generic"
	end
	if Profile.petCount(profile) + count > Config.PetInventoryCap then
		return false, "inventoryFull"
	end
	local cost = Economy.eggCost(world) * count
	if profile.coins < cost then
		return false, "notEnough"
	end
	profile.coins -= cost
	local lucky = session.passes.LuckyEggs == true
	local results = {}
	for _ = 1, count do
		local key = Economy.rollPet(world, lucky, session.rng:NextNumber())
		profile.petSeq += 1
		local id = "P" .. tostring(profile.petSeq)
		local isNew = not profile.index[key]
		profile.pets[id] = { s = key, l = false }
		profile.index[key] = true
		profile.stats.hatched += 1
		table.insert(results, { id = id, key = key, new = isNew })
	end
	-- Auto-equip into free slots so new players see their pet immediately.
	local cap = Sessions.equipCap(session)
	for _, result in results do
		if #profile.equipped < cap then
			table.insert(profile.equipped, result.id)
		end
	end
	if profile.tutorial == 5 then
		profile.tutorial = 6
	end
	Sessions.publishPets(session)
	Sync.profile(session)
	return true, nil, { results = results, cost = cost }
end

local function sortedByBoost(profile: Profile.Data): { string }
	local ids = {}
	for id in profile.pets do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local pa, pb = profile.pets[a], profile.pets[b]
		local ba, bb = Economy.petPower(pa.s, pa.m), Economy.petPower(pb.s, pb.m)
		if ba ~= bb then
			return ba > bb
		end
		return a < b
	end)
	return ids
end

local function equip(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or type(payload) ~= "table" or type(payload.id) ~= "string" then
		return false, "err.generic"
	end
	local profile = session.profile
	local id = payload.id :: string
	if not profile.pets[id] then
		return false, "err.generic"
	end
	local index = table.find(profile.equipped, id)
	if payload.on == false then
		if index then
			table.remove(profile.equipped, index)
		end
	elseif not index then
		if #profile.equipped >= Sessions.equipCap(session) then
			table.remove(profile.equipped, 1)
		end
		table.insert(profile.equipped, id)
	end
	Sessions.publishPets(session)
	Sync.profile(session)
	return true
end

local function equipBest(player: Player): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session then
		return false, "err.generic"
	end
	local profile = session.profile
	profile.equipped = {}
	for i, id in sortedByBoost(profile) do
		if i > Sessions.equipCap(session) then
			break
		end
		table.insert(profile.equipped, id)
	end
	Sessions.publishPets(session)
	Sync.profile(session)
	return true
end

local function unequipAll(player: Player): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session then
		return false, "err.generic"
	end
	session.profile.equipped = {}
	Sessions.publishPets(session)
	Sync.profile(session)
	return true
end

local function setLock(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or type(payload) ~= "table" or type(payload.id) ~= "string" or type(payload.locked) ~= "boolean" then
		return false, "err.generic"
	end
	local pet = session.profile.pets[payload.id]
	if not pet then
		return false, "err.generic"
	end
	pet.l = payload.locked
	Sync.profile(session)
	return true
end

local function deletePet(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or type(payload) ~= "table" or type(payload.id) ~= "string" then
		return false, "err.generic"
	end
	local profile = session.profile
	local pet = profile.pets[payload.id]
	if not pet or pet.l then
		return false, "err.generic"
	end
	if session.trade then
		return false, "tradeBusy"
	end
	profile.pets[payload.id] = nil
	local index = table.find(profile.equipped, payload.id)
	if index then
		table.remove(profile.equipped, index)
		Sessions.publishPets(session)
	end
	Sync.profile(session)
	return true
end

-- Enchanting: pay coins (or spend a Lucky Enchant) to add a random new mutation to a pet.
local function mutate(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return false, "err.notReady"
	end
	if type(payload) ~= "table" or type(payload.id) ~= "string" then
		return false, "err.generic"
	end
	local profile = session.profile
	local pet = profile.pets[payload.id]
	if not pet then
		return false, "err.generic"
	end
	if session.trade then
		return false, "tradeBusy"
	end
	local list = pet.m or {}
	if Economy.regularMutations(list) >= #Config.Mutations then
		return false, "mutateMax"
	end
	local key: string?
	local cost = 0
	if payload.lucky == true then
		if profile.enchants < 1 then
			return false, "noLucky"
		end
		key = Economy.rollMutation(list, session.rng:NextNumber(), Config.LuckyMutations) or Economy.rollMutation(list, session.rng:NextNumber())
		profile.enchants -= 1
	else
		cost = Economy.mutateCost(pet.s, pet.m) :: number
		if profile.coins < cost then
			return false, "notEnough"
		end
		profile.coins -= cost
		key = Economy.rollMutation(list, session.rng:NextNumber())
	end
	assert(key, "a mutation is always available below the cap")
	table.insert(list, key)
	pet.m = list
	if table.find(profile.equipped, payload.id) then
		Sessions.publishPets(session)
	end
	Sync.profile(session)
	return true, nil, { mutation = key, cost = cost, count = #list }
end

-- Trims equipped pets after a pass change or load.
function PetService.clampEquipped(session: Session)
	local cap = Sessions.equipCap(session)
	while #session.profile.equipped > cap do
		table.remove(session.profile.equipped)
	end
	Sessions.publishPets(session)
end

function PetService.init()
	Net.on("Hatch", hatch)
	Net.on("Equip", equip)
	Net.on("EquipBest", equipBest)
	Net.on("UnequipAll", unequipAll)
	Net.on("SetLock", setLock)
	Net.on("DeletePet", deletePet)
	Net.on("Mutate", mutate)
end

return PetService
