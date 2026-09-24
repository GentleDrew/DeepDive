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
