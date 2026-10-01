--!strict
-- Daily login, playtime and group-join reward claims. All timing and membership is checked here;
-- the client only asks.

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Operators = require(Shared.Operators)
local Rewards = require(Shared.Rewards)

local Net = require(script.Parent.Parent.Net)
local ProfileStore = require(script.Parent.Parent.ProfileStore)
local Sessions = require(script.Parent.Parent.Sessions)
local Sync = require(script.Parent.Parent.Sync)

local RewardService = {}

local function finish(player: Player, session: Sessions.Session, reward: Rewards.Payout)
	Sync.profile(session)
	Net.push(player, "purchase", { coins = reward.coins, enchants = reward.enchants })
	task.spawn(ProfileStore.save, player, false)
end

local function claimDaily(player: Player): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return false, "err.notReady"
	end
	local ok, err, reward, day = Rewards.claimDaily(session.profile, os.time())
	if not ok or not reward then
		return false, err
	end
	finish(player, session, reward)
	return true, nil, { day = day, coins = reward.coins, enchants = reward.enchants, boostMinutes = reward.boostMinutes }
end

local function claimPlaytime(player: Player, payload: any): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return false, "err.notReady"
	end
	local tier = if type(payload) == "table" then tonumber(payload.tier) else nil
	if not tier then
		return false, "err.generic"
	end
	local ok, err, reward = Rewards.claimPlaytime(session.profile, math.floor(tier), os.time())
	if not ok or not reward then
		return false, err
	end
	finish(player, session, reward)
	return true, nil, { tier = tier, coins = reward.coins, enchants = reward.enchants, boostMinutes = reward.boostMinutes }
end

-- Player:IsInGroupAsync caches its answer for the whole session, so a join made a moment ago is
-- checked against the live group list instead.
local function inGroup(player: Player, groupId: number): boolean
	local ok, groups = pcall(function()
		return GroupService:GetGroupsAsync(player.UserId)
	end)
	if ok and type(groups) == "table" then
		for _, group in groups do
			if group.Id == groupId then
				return true
			end
		end
		return false
	end
	local cached, member = pcall(function()
		return player:IsInGroupAsync(groupId)
	end)
	return cached and member == true
end

local function claimGroup(player: Player): (boolean, string?, any)
	local session = Sessions.get(player)
	if not session or not session.ready then
		return false, "err.notReady"
	end
	local profile = session.profile
	local groupId = Operators.groupId()
	if groupId <= 0 then
		return false, "err.generic"
	elseif profile.groupRewarded then
		return false, "rewardClaimed"
	elseif not inGroup(player, groupId) then
		return false, "notInGroup"
	end
	profile.groupRewarded = true
	local reward =
		{ coins = Economy.productCoins(Config.GroupRewardDives, profile.unlocked), enchants = Config.GroupRewardEnchants, boostMinutes = 0 }
	Rewards.grant(profile, reward, os.time())
	finish(player, session, reward)
	return true, nil, { coins = reward.coins, enchants = reward.enchants }
end

function RewardService.init()
	Net.on("ClaimDaily", claimDaily)
	Net.on("ClaimPlaytime", claimPlaytime)
	Net.on("ClaimGroup", claimGroup)
end

return RewardService
