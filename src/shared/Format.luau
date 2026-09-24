--!strict
-- Number and time formatting for UI text.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trim(text: string): string
	-- "12.30" -> "12.3", "5.00" -> "5"
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

function Format.commas(n: number): string
	local negative = n < 0
	local digits = tostring(math.floor(math.abs(n)))
	local out = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return if negative then "-" .. out else out
end

-- 999 -> "999", 12345 -> "12.3K", 1500000 -> "1.5M"
function Format.short(n: number): string
	if n ~= n then
		return "0"
	end
	local negative = n < 0
	n = math.abs(n)
	if n < 1000 then
		local text = tostring(math.floor(n))
		return if negative then "-" .. text else text
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = trim(string.format("%.1f", math.floor(scaled * 10) / 10))
	else
		text = trim(string.format("%.2f", math.floor(scaled * 100) / 100))
	end
	text ..= SUFFIXES[tier + 1]
	return if negative then "-" .. text else text
end

-- Multiplier such as x1.25 or x340
function Format.multiplier(m: number): string
	if m >= 100 then
		return "x" .. Format.short(m)
	elseif m >= 10 then
		return "x" .. trim(string.format("%.1f", m))
	end
	return "x" .. trim(string.format("%.2f", m))
end

function Format.percent(fraction: number): string
	local value = fraction * 100
	if value >= 10 then
		return string.format("%d%%", math.floor(value + 0.5))
	elseif value >= 1 then
		return trim(string.format("%.1f", value)) .. "%"
	elseif value >= 0.1 then
		return trim(string.format("%.2f", value)) .. "%"
	end
	return trim(string.format("%.3f", value)) .. "%"
end

function Format.seconds(s: number): string
	s = math.max(0, math.floor(s + 0.5))
	if s < 60 then
		return tostring(s) .. "s"
	end
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Days since the Unix epoch (UTC) into a proleptic-Gregorian y/m/d triple. Portable, pure-Luau
-- date math (Howard Hinnant's algorithm) since Roblox's os library has no os.date.
local function civilFromDays(z: number): (number, number, number)
	z += 719468
	local era = (if z >= 0 then z else z - 146096) // 146097
	local doe = z - era * 146097 -- [0, 146096]
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365 -- [0, 399]
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100) -- [0, 365]
	local mp = (5 * doy + 2) // 153 -- [0, 11]
	local d = doy - (153 * mp + 2) // 5 + 1 -- [1, 31]
	local m = if mp < 10 then mp + 3 else mp - 9 -- [1, 12]
	return (if m <= 2 then y + 1 else y), m, d
end

-- Unix timestamp (seconds, UTC) -> "2026.09.24".
function Format.date(timestamp: number): string
	local days = math.floor(timestamp / 86400)
	local y, m, d = civilFromDays(days)
	return string.format("%04d.%02d.%02d", y, m, d)
end

-- Seconds -> hours and minutes, for a "{h}h {m}m" / "{h}시간 {m}분" style playtime display.
function Format.hoursMinutes(seconds: number): (number, number)
	local total = math.max(0, math.floor(seconds))
	return total // 3600, (total % 3600) // 60
end

-- Replaces {name} placeholders with values from args.
function Format.fill(template: string, args: { [string]: any }?): string
	if not args then
		return template
	end
	return (
		string.gsub(template, "{(%w+)}", function(key)
			local value = args[key]
			if value == nil then
				return "{" .. key .. "}"
			end
			return tostring(value)
		end)
	)
end

return Format
