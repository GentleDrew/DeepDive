--!strict
-- Game passes and developer products. Products are granted idempotently: the receipt id is
-- stored in the profile and saved before the purchase is acknowledged.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)

local Net = require(script.Parent.Parent.Net)
local ProfileStore = require(script.Parent.Parent.ProfileStore)
local Sessions = require(script.Parent.Parent.Sessions)
local Sync = require(script.Parent.Parent.Sync)
local PetService = require(script.Parent.PetService)

local PurchaseService = {}

local passById: { [number]: string } = {}
local productById: { [number]: any } = {}

function PurchaseService.loadPasses(session: Sessions.Session)
	for _, pass in Config.Passes do
		if pass.id > 0 then
			local ok, owned = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(session.player.UserId, pass.id)
			end)
			session.passes[pass.key] = ok and owned == true
		else
			session.passes[pass.key] = false
		end
	end
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local product = productById[receipt.ProductId]
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not product or not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local session = Sessions.get(player)
	if not session or not session.ready then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = session.profile
	local receiptId = tostring(receipt.PurchaseId)
	if table.find(profile.receipts, receiptId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local coins = Economy.productCoins(product.dives, profile.unlocked)
	profile.coins += coins
	profile.lifetime += coins
	table.insert(profile.receipts, receiptId)
	while #profile.receipts > 50 do
		table.remove(profile.receipts, 1)
	end
	ProfileStore.markDirty(player)
	if not ProfileStore.save(player, false) then
		profile.coins -= coins
		profile.lifetime -= coins
		local index = table.find(profile.receipts, receiptId)
		if index then
			table.remove(profile.receipts, index)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Sync.profile(session)
	Net.push(player, "toast", { key = "thanks", kind = "gold" })
	Net.push(player, "purchase", { coins = coins })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function PurchaseService.init()
	for _, pass in Config.Passes do
		if pass.id > 0 then
			passById[pass.id] = pass.key
		end
	end
	for _, product in Config.Products do
		if product.id > 0 then
			productById[product.id] = product
		end
	end
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local key = passById[passId]
		local session = Sessions.get(player)
		if purchased and key and session then
			session.passes[key] = true
			if key == "PetSlots" then
				PetService.clampEquipped(session)
			end
			Sync.profile(session)
			Net.push(player, "toast", { key = "thanks", kind = "gold" })
		end
	end)
end

return PurchaseService
