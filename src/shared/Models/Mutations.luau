--!strict
-- Pet mutation looks. A pet shows its strongest mutation: Gold (polished metal), Diamond (icy
-- crystal), Galaxy (deep space with stars), Lava (cracked lava with embers) or GOAT (rainbow
-- shimmer). Weaker mutations on the same pet still add their multiplier.

local Color = require(script.Parent.Parent.Color)
local Config = require(script.Parent.Parent.Config)
local Build = require(script.Parent.Build)

local Mutations = {}

local RANK: { [string]: number } = {}
for index, mutation in Config.Mutations do
	RANK[mutation.key] = index
end

-- Strongest mutation in a list (nil for none).
function Mutations.top(list: { string }?): string?
	local best, bestRank = nil, 0
	if list then
		for _, key in list do
			local rank = RANK[key] or 0
			if rank > bestRank then
				best, bestRank = key, rank
			end
		end
	end
	return best
end

function Mutations.color(key: string): Color3
	for _, mutation in Config.Mutations do
		if mutation.key == key then
			return Color.hex(mutation.color)
		end
	end
	return Color3.new(1, 1, 1)
end

-- Parses the replicated follower form "species|Gold,Lava".
function Mutations.parse(text: string): (string, { string })
	local bar = string.find(text, "|", 1, true)
	if not bar then
		return text, {}
	end
	local list = {}
	for key in string.gmatch(string.sub(text, bar + 1), "[^,]+") do
		table.insert(list, key)
	end
	return string.sub(text, 1, bar - 1), list
end

local function emitter(parent: BasePart, color: Color3, rate: number, size: number, texture: string?)
	local e = Build.sparkles(parent, color, rate)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	if texture then
		e.Texture = texture
	end
	return e
end

function Mutations.apply(model: Model, list: { string }?)
	local top = Mutations.top(list)
	if not top then
		return
	end
	local index = 0
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part.Name == "Root" or part.Transparency >= 1 or part:GetAttribute("Eye") then
			continue
		end
		index += 1
		local accent = part:GetAttribute("Accent") == true
		part.Transparency = 0
		if top == "Gold" then
			part.Color = if accent then Color3.fromRGB(255, 244, 170) else Color3.fromRGB(255, 196, 46)
			part.Material = if accent then Enum.Material.Neon else Enum.Material.Metal
			part.Reflectance = if accent then 0 else 0.25
		elseif top == "Diamond" then
			part.Color = if accent then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(150, 236, 255)
			part.Material = if accent then Enum.Material.Neon else Enum.Material.Ice
			part.Reflectance = 0.3
		elseif top == "Galaxy" then
			part.Color = if accent then Color3.fromRGB(255, 110, 230) else Color3.fromRGB(58, 26, 120)
			part.Material = if accent then Enum.Material.Neon else Enum.Material.SmoothPlastic
			part.Reflectance = 0.1
		elseif top == "Lava" then
			part.Color = if accent then Color3.fromRGB(255, 140, 30) else Color3.fromRGB(255, 92, 30)
			part.Material = if accent then Enum.Material.Neon else Enum.Material.CrackedLava
			part.Reflectance = 0
		elseif top == "GOAT" then
			part.Color = Color.Rainbow[(index % #Color.Rainbow) + 1]
			part.Material = if accent then Enum.Material.Neon else Enum.Material.Glass
			part.Reflectance = 0.15
		end
	end
	local root = model.PrimaryPart
	if not root then
		return
	end
	local color = Mutations.color(top)
	Build.light(root, color, 9, if top == "Gold" then 1 else 1.6)
	if top == "Gold" then
		emitter(root, Color3.fromRGB(255, 226, 110), 5, 0.4)
	elseif top == "Diamond" then
		emitter(root, Color3.fromRGB(220, 250, 255), 7, 0.45)
	elseif top == "Galaxy" then
		emitter(root, Color3.fromRGB(200, 160, 255), 14, 0.35)
		emitter(root, Color3.fromRGB(255, 120, 230), 4, 0.6)
	elseif top == "Lava" then
		local embers = emitter(root, Color3.fromRGB(255, 120, 30), 12, 0.3)
		embers.Acceleration = Vector3.new(0, 3, 0)
	elseif top == "GOAT" then
		emitter(root, Color3.fromRGB(255, 255, 255), 10, 0.5)
		emitter(root, Color3.fromRGB(255, 90, 220), 6, 0.55)
	end
	model:SetAttribute("Mutation", top)
end

return Mutations
