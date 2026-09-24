--!strict
-- Roblox-side helpers for the pure data modules (hex colors, material names).

local Color = {}

local cache: { [string]: Color3 } = {}

function Color.hex(hex: string): Color3
	local cached = cache[hex]
	if cached then
		return cached
	end
	local value = Color3.fromHex(hex)
	cache[hex] = value
	return value
end

function Color.material(name: string?, fallback: Enum.Material?): Enum.Material
	if name then
		local ok, material = pcall(function()
			return (Enum.Material :: any)[name]
		end)
		if ok and material then
			return material
		end
	end
	return fallback or Enum.Material.SmoothPlastic
end

function Color.lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

function Color.darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- Rainbow palette used by "rainbow" styled pets/relics.
Color.Rainbow = {
	Color3.fromRGB(255, 95, 110),
	Color3.fromRGB(255, 170, 60),
	Color3.fromRGB(255, 230, 80),
	Color3.fromRGB(100, 230, 120),
	Color3.fromRGB(70, 190, 255),
	Color3.fromRGB(170, 110, 255),
}

return Color
