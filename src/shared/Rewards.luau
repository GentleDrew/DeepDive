--!strict
-- Daily login and playtime rewards: claim rules and payouts. Pure module (tested outside Roblox).
-- Days are UTC calendar days (os.time() // 86400), so every player resets at the same moment.

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")

local Rewards = {}

local DAY = 86400

export type Payout = { coins: number, enchants: number, boostMinutes: number }
export type DailyState = { claimable: boolean, day: number, streak: number }

function Rewards.dayOf(now: number): number
	return now // DAY
end

-- Seconds until the next UTC midnight (when daily and playtime rewards reset).
function Rewards.untilReset(now: number): number
	return DAY - now % DAY
end

local function payout(entry: any, unlocked: number): Payout
	return {
		coins = Economy.productCoins(entry.dives or 0, unlocked),
		enchants = entry.enchants or 0,
		boostMinutes = entry.boostMinutes or 0,
	}
end

function Rewards.dailyPayout(day: number, unlocked: number): Payout
	return payout(Config.DailyRewards[day], unlocked)
end

function Rewards.playtimePayout(tier: number, unlocked: number): Payout
	return payout(Config.PlaytimeRewards[tier], unlocked)
end

-- `day` is the cycle position (1..7) a claim right now would pay (or today's, once claimed);
-- `streak` counts consecutive claimed days including that one.
function Rewards.daily(data: any, now: number): DailyState
	local today = Rewards.dayOf(now)
	local count = #Config.DailyRewards
	if data.daily.last == today then
		local streak = math.max(1, data.daily.streak)
		return { claimable = false, day = (streak - 1) % count + 1, streak = streak }
	end
	local streak = if data.daily.last == today - 1 then data.daily.streak + 1 else 1
	return { claimable = true, day = (streak - 1) % count + 1, streak = streak }
end

-- Rolls the playtime counter over to a new day when needed; returns today's tracker.
function Rewards.playToday(data: any, now: number): { day: number, seconds: number, claimed: { number } }
	local today = Rewards.dayOf(now)
	if data.play.day ~= today then
		data.play.day = today
		data.play.seconds = 0
		data.play.claimed = {}
	end
	return data.play
end

function Rewards.addPlaytime(data: any, seconds: number, now: number)
	local play = Rewards.playToday(data, now)
	play.seconds += seconds
end

-- "claimed" | "ready" | "locked" for each playtime tier (read-only: does not roll the day over).
function Rewards.tierStatus(tier: number, seconds: number, claimed: { number }): string
	local entry = Config.PlaytimeRewards[tier]
	if table.find(claimed, tier) then
		return "claimed"
	elseif seconds >= entry.minutes * 60 then
		return "ready"
	end
	return "locked"
end

-- Applies a payout to the profile. Boost minutes stack onto any running TimedBoost.
function Rewards.grant(data: any, reward: Payout, now: number)
	data.coins += reward.coins
	data.lifetime += reward.coins
	data.enchants += reward.enchants
	if reward.boostMinutes > 0 then
		data.boostUntil = math.max(now, data.boostUntil) + reward.boostMinutes * 60
	end
end

function Rewards.claimDaily(data: any, now: number): (boolean, string?, Payout?, number?)
	local state = Rewards.daily(data, now)
	if not state.claimable then
		return false, "rewardClaimed", nil, nil
	end
	local reward = Rewards.dailyPayout(state.day, data.unlocked)
	data.daily.last = Rewards.dayOf(now)
	data.daily.streak = state.streak
	Rewards.grant(data, reward, now)
	return true, nil, reward, state.day
end

function Rewards.claimPlaytime(data: any, tier: number, now: number): (boolean, string?, Payout?)
	if not Config.PlaytimeRewards[tier] then
		return false, "err.generic", nil
	end
	local play = Rewards.playToday(data, now)
	local status = Rewards.tierStatus(tier, play.seconds, play.claimed)
	if status == "claimed" then
		return false, "rewardClaimed", nil
	elseif status == "locked" then
		return false, "rewardLocked", nil
	end
	table.insert(play.claimed, tier)
	local reward = Rewards.playtimePayout(tier, data.unlocked)
	Rewards.grant(data, reward, now)
	return true, nil, reward
end

return Rewards
