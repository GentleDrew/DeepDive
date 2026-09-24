--!strict
-- Diving gear shop: buying and equipping gear pieces, and dressing characters in their gear.
-- Gear of a world can be bought once that world is unlocked; buying auto-equips the piece when
-- it beats the one worn in that slot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Gear = require(Shared.Data.Gear)
local GearModels = require(Shared.Models.GearModels)

local Net = require(script.Parent.Parent.Net)
local Sessions = require(script.Parent.Parent.Sessions)
local Sync = require(script.Parent.Parent.Sync)
local DiveService = require(script.Parent.DiveService)

local GearService = {}

type Session = Sessions.Session

function GearService.dress(session: Session)
	local character = session.player.Character
	if character then
		local ok, err = pcall(function()
			GearModels.dress(character, session.profile.gear.equip)
		end)
		if not ok then
			warn("[DeepDive] Could not dress gear: " .. tostring(err))
		end
	end
end

local function applied(session: Session, item: Gear.Item)
	if item.slot == "tank" then
		DiveService.refreshOxygen(session)
	end
	GearService.dress(session)
	Sync.profile(session)
end

local function buy(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return false, "err.notReady"
	end
	local item = if type(payload) == "table" and type(payload.key) == "string" then Gear.get(payload.key) else nil
	if not item then
		return false, "err.generic"
	end
	local profile = session.profile
	if item.world > profile.unlocked then
		return false, "err.locked"
	end
	if profile.gear.owned[item.key] then
		return false, "gearOwned"
	end
	local cost = Economy.gearCost(item.key) :: number
	if profile.coins < cost then
		return false, "notEnough"
	end
	profile.coins -= cost
	profile.gear.owned[item.key] = true
	local equipped = false
	if item.tier > Gear.tier(profile.gear.equip[item.slot]) then
		profile.gear.equip[item.slot] = item.key
		equipped = true
	end
	if profile.tutorial == 4 then
		profile.tutorial = 5
	end
	applied(session, item)
	return true, nil, { key = item.key, equipped = equipped, cost = cost }
end

local function equip(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return false, "err.notReady"
	end
	local item = if type(payload) == "table" and type(payload.key) == "string" then Gear.get(payload.key) else nil
	if not item or not session.profile.gear.owned[item.key] then
		return false, "err.generic"
	end
	session.profile.gear.equip[item.slot] = item.key
	applied(session, item)
	return true
end

function GearService.init()
	Net.on("BuyGear", buy)
	Net.on("EquipGear", equip)
end

return GearService
