--!strict
-- Robux purchase prompts by Config key (a game pass or a developer product).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Purchase = {}

export type Def = { key: string, id: number, price: number, color: string }

-- Returns the definition and "pass" | "product", or nil for an unknown key.
function Purchase.find(key: string): (Def?, string?)
	for _, def in Config.Passes do
		if def.key == key then
			return def :: any, "pass"
		end
	end
	for _, def in Config.Products do
		if def.key == key then
			return def :: any, "product"
		end
	end
	return nil, nil
end

-- Opens Roblox's purchase dialog. Returns false when the item has no id yet or is an owned pass.
function Purchase.prompt(key: string, ownedPasses: { [string]: boolean }): boolean
	local def, kind = Purchase.find(key)
	if not def or def.id <= 0 then
		return false
	end
	local player = Players.LocalPlayer
	if kind == "pass" then
		if ownedPasses[key] then
			return false
		end
		MarketplaceService:PromptGamePassPurchase(player, def.id)
	else
		MarketplaceService:PromptProductPurchase(player, def.id)
	end
	return true
end

return Purchase
