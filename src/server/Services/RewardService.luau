--!strict
-- Daily login and playtime reward claims. All timing is checked here against os.time(); the
-- client only asks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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

function RewardService.init()
	Net.on("ClaimDaily", claimDaily)
	Net.on("ClaimPlaytime", claimPlaytime)
end

return RewardService
