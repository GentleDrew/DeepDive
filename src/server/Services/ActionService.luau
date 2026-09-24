--!strict
-- Selling, travel, settings, tutorial progress and the client "Ready" handshake.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)

local Net = require(script.Parent.Parent.Net)
local ProfileStore = require(script.Parent.Parent.ProfileStore)
local Sessions = require(script.Parent.Parent.Sessions)
local Sync = require(script.Parent.Parent.Sync)
local DiveService = require(script.Parent.DiveService)

local ActionService = {}

local function teleport(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return false, "err.notReady"
	end
	local world = if type(payload) == "table" then tonumber(payload.world) else nil
	if not world then
		return false, "err.generic"
	end
	return DiveService.teleport(session, math.floor(world))
end

-- Pays the fee for the next world once the world before it is cleared.
local function unlockWorld(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return false, "err.notReady"
	end
	local world = if type(payload) == "table" then tonumber(payload.world) else nil
	local profile = session.profile
	if not world or world ~= profile.unlocked + 1 or world > Config.WorldCount then
		return false, "err.generic"
	end
	local previous = profile.worlds[tostring(world - 1)]
	if not previous or not previous.cleared then
		return false, "err.locked"
	end
	local cost = Economy.unlockCost(world)
	if profile.coins < cost then
		return false, "notEnough"
	end
	profile.coins -= cost
	profile.unlocked = world
	Sync.profile(session)
	task.spawn(ProfileStore.save, player, false)
	return true, nil, { world = world, cost = cost }
end

local BOOL_SETTINGS = { music = true, sfx = true, lowFx = true, hidePets = true }

local function setting(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or type(payload) ~= "table" or type(payload.key) ~= "string" then
		return false, "err.generic"
	end
	local settings = session.profile.settings :: any
	if BOOL_SETTINGS[payload.key] and type(payload.value) == "boolean" then
		settings[payload.key] = payload.value
	elseif payload.key == "lang" and (payload.value == "en" or payload.value == "ko") then
		settings.lang = payload.value
	else
		return false, "err.generic"
	end
	Sync.profile(session)
	return true
end

local function tutorial(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or type(payload) ~= "table" or type(payload.step) ~= "number" then
		return false, "err.generic"
	end
	local profile = session.profile
	-- The client may only advance informational steps (6 -> done) or skip the tutorial.
	local step = math.floor(payload.step)
	if (profile.tutorial == 6 and step == 7) or step == 99 then
		profile.tutorial = step
		Sync.profile(session)
		return true
	end
	return false, "err.generic"
end

local function ready(player: Player): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return false, "err.notReady"
	end
	DiveService.rollLayout(session)
	return true, nil, Sync.view(session)
end

function ActionService.init()
	Net.on("Sell", function(player: Player): (boolean, string?, any)
		local session = Sessions.get(player)
		if not session or not session.ready then
			return false, "err.notReady"
		end
		return DiveService.sell(session, true)
	end)
	Net.on("Teleport", teleport)
	Net.on("UnlockWorld", unlockWorld)
	Net.on("Setting", setting)
	Net.on("Tutorial", tutorial)
	Net.on("Ready", ready)
end

return ActionService
