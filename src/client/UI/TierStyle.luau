--!strict
-- Name colours for ranking tiers (Config.Tiers) and the Director's red chroma.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Config = require(Shared.Config)

local Kit = require(script.Parent.Kit)

local TierStyle = {}

TierStyle.DirectorColors = { Color3.fromRGB(255, 40, 60), Color3.fromRGB(255, 140, 140), Color3.fromRGB(160, 0, 20) }
local PRISMATIC = { Color.hex("#7ff0ff"), Color.hex("#c99bff"), Color.hex("#ffe36b"), Color.hex("#ffffff") }

function TierStyle.color(tier: number): Color3?
	local def = Config.Tiers[tier]
	return if def then Color.hex(def.color) else nil
end

-- Applies the tier look to a label (or clears it for tier 0). `fallback` is the normal colour.
function TierStyle.apply(label: TextLabel, tier: number, fallback: Color3)
	local old = label:FindFirstChild("Chroma")
	local def = Config.Tiers[tier]
	if def and def.prismatic then
		label.TextColor3 = Color3.new(1, 1, 1)
		if not old then
			Kit.chroma(label, PRISMATIC, 3)
		end
		return
	end
	if old then
		old:Destroy()
	end
	label.TextColor3 = if def then Color.hex(def.color) else fallback
end

-- Red chroma for the Director's name and tags.
function TierStyle.director(target: Instance)
	if not target:FindFirstChild("Chroma") then
		if target:IsA("TextLabel") then
			target.TextColor3 = Color3.new(1, 1, 1)
		end
		Kit.chroma(target, TierStyle.DirectorColors, 1.6)
	end
end

return TierStyle
