--!strict
-- Ranking boards (weekly / monthly / all-time coins earned) and hold-time tiers. Pure module.
-- Weeks start Monday 00:00 UTC; months on the 1st, 00:00 UTC.

local Config = if script then require(script.Parent.Config) else require("./Config")
local Format = if script then require(script.Parent.Format) else require("./Format")

local Rankings = {}

local DAY = 86400

Rankings.Boards = { "weekly", "monthly", "alltime" }

export type Holds = { w: number, m: number } -- seconds spent in a top-3 spot, weekly / monthly

function Rankings.weekId(now: number): number
	-- Day 0 (1970-01-01) was a Thursday; +3 makes weeks roll over on Mondays.
	return (now // DAY + 3) // 7
end

function Rankings.monthId(now: number): number
	local y, m = Format.ymd(now)
	return y * 12 + (m - 1)
end

-- Seconds until the board's period resets (nil for the all-time board).
function Rankings.untilReset(board: string, now: number): number?
	if board == "weekly" then
		return (Rankings.weekId(now) + 1) * 7 * DAY - 3 * DAY - now
	elseif board == "monthly" then
		local current = Rankings.monthId(now)
		local day = now // DAY + 1
		while Rankings.monthId(day * DAY) == current do
			day += 1
		end
		return day * DAY - now
	end
	return nil
end

-- Starts a new week/month when needed; returns this week's and month's coins earned.
function Rankings.roll(data: any, now: number): (number, number)
	local period = data.period
	local week, month = Rankings.weekId(now), Rankings.monthId(now)
	if period.week ~= week then
		period.week = week
		period.weekBase = data.lifetime
	end
	if period.month ~= month then
		period.month = month
		period.monthBase = data.lifetime
	end
	return math.max(0, data.lifetime - period.weekBase), math.max(0, data.lifetime - period.monthBase)
end

local function held(holds: Holds, board: string): number
	return if board == "monthly" then holds.m else holds.w
end

-- Highest tier earned (0 = none).
function Rankings.tier(holds: Holds): number
	local best = 0
	for index, tier in Config.Tiers do
		if held(holds, tier.board) >= tier.hours * 3600 then
			best = index
		end
	end
	return best
end

-- The next tier a diver is working towards on `board` and the seconds of top-3 time still
-- needed. The all-time board shows the next tier of any kind. nil when nothing is left.
function Rankings.nextTier(holds: Holds, board: string): (number?, number?)
	for index, tier in Config.Tiers do
		if (board == "alltime" or tier.board == board) and held(holds, tier.board) < tier.hours * 3600 then
			return index, tier.hours * 3600 - held(holds, tier.board)
		end
	end
	return nil, nil
end

return Rankings
