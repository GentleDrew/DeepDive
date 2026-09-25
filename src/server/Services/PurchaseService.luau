--!strict
-- Game passes and developer products. Products are granted idempotently: the receipt id is
-- stored in the profile and saved before the purchase is acknowledged.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Gear = require(Shared.Data.Gear)
local Worlds = require(Shared.Data.Worlds)

local Net = require(script.Parent.Parent.Net)
local ProfileStore = require(script.Parent.Parent.ProfileStore)
local Sessions = require(script.Parent.Parent.Sessions)
local Sync = require(script.Parent.Parent.Sync)
local GearService = require(script.Parent.GearService)
local PetService = require(script.Parent.PetService)

local PurchaseService = {}

local passById: { [number]: string } = {}
local productById: { [number]: any } = {}

-- Replicated cosmetics (VIP crown, swim trail, nameplate border): recomputed on join and again
-- right after any pass purchase, so other clients see the change immediately.
local function applyCosmetics(session: Sessions.Session)
	local player = session.player
	local passes = session.passes
	player:SetAttribute("VIP", passes.VIPAura == true)
	player:SetAttribute("Trail", passes.SwimTrail == true)
	player:SetAttribute("Border", if passes.BorderGold then "Gold" elseif passes.BorderSilver then "Silver" else "")
end

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
	applyCosmetics(session)
end

-- The pet with the least valuable boost, skipping locked ones (PetReroll's target).
local function weakestUnlockedPet(profile: any): string?
	local worst, worstBoost = nil, math.huge
	for id, pet in profile.pets do
		if not pet.l then
			local boost = Economy.petBoost(pet.s)
			if boost < worstBoost then
				worst, worstBoost = id, boost
			end
		end
	end
	return worst
end

-- A pet that does not yet have every mutation (GuaranteedMutation's target).
local function pickMutationTarget(profile: any): string?
	for id, pet in profile.pets do
		if #(pet.m or {}) < #Config.Mutations then
			return id
		end
	end
	return nil
end

-- The rarest mutation not already in `existing` (Config.Mutations is ordered weakest to strongest).
local function rarestMissing(existing: { string }?): string?
	for i = #Config.Mutations, 1, -1 do
		local key = Config.Mutations[i].key
		if not (existing and table.find(existing, key)) then
			return key
		end
	end
	return nil
end

-- A flat, modest coin grant so a special product always delivers value even when its usual
-- target (an eligible pet, backpack room, ...) is not available right now.
local function fallbackCoins(profile: any, amount: number): () -> ()
	profile.coins += amount
	profile.lifetime += amount
	return function()
		profile.coins -= amount
		profile.lifetime -= amount
	end
end

-- Applies one of the five special products (InstantUnlock, TimedBoost, PetReroll,
-- GuaranteedMutation, BackpackFill). Returns nil for every other product. Otherwise returns a
-- revert closure (call it if the save that follows fails) plus a toast key/args to show.
local function applySpecialProduct(session: Sessions.Session, product: any): ((() -> ())?, string?, any?)
	local profile = session.profile
	if product.instantUnlock then
		local nextWorld = profile.unlocked + 1
		local previous = profile.worlds[tostring(profile.unlocked)]
		if nextWorld <= Config.WorldCount and previous and previous.cleared then
			profile.unlocked = nextWorld
			return function()
				profile.unlocked = nextWorld - 1
			end, "grantedUnlock", { n = nextWorld }
		end
		local coins = if profile.unlocked < Config.WorldCount
			then Economy.unlockCost(profile.unlocked + 1)
			else Economy.nice(Economy.unlockCost(Config.WorldCount) * 0.15)
		return fallbackCoins(profile, coins), "grantedCoins", { n = coins }
	elseif product.timedBoost then
		local before = profile.boostUntil
		local extendFrom = math.max(before, os.time())
		profile.boostUntil = extendFrom + Config.TimedBoostMinutes * 60
		return function()
			profile.boostUntil = before
		end, "grantedBoost", { n = Config.TimedBoostMinutes }
	elseif product.petReroll then
		local id = weakestUnlockedPet(profile)
		if id then
			local pet = profile.pets[id]
			local pastPet = Worlds.pets[pet.s]
			local world = if pastPet then pastPet.world else 1
			local newKey = Economy.rollPet(world, false, session.rng:NextNumber())
			local previousSpecies, previousMutations = pet.s, pet.m
			pet.s = newKey
			pet.m = nil
			profile.index[newKey] = true
			return function()
				pet.s = previousSpecies
				pet.m = previousMutations
			end, "grantedReroll", { key = newKey }
		end
		return fallbackCoins(profile, 200), "grantedCoins", { n = 200 }
	elseif product.guaranteedMutation then
		local id = pickMutationTarget(profile)
		local key = id and rarestMissing(profile.pets[id].m)
		if id and key then
			local pet = profile.pets[id]
			local hadList = pet.m ~= nil
			local list: { string } = pet.m or {}
			table.insert(list, key)
			pet.m = list
			return function()
				table.remove(list)
				if not hadList then
					pet.m = nil
				end
			end, "grantedMutation", { mutation = key }
		end
		return fallbackCoins(profile, 300), "grantedCoins", { n = 300 }
	elseif product.backpackFill then
		local capacity = math.floor(Economy.stat(profile.gear.equip, "pack"))
		local room = math.max(0, capacity - #profile.backpack)
		if room > 0 then
			local relic = Worlds.get(session.world).relics[1]
			for _ = 1, room do
				table.insert(profile.backpack, relic.key)
			end
			profile.relics[relic.key] = (profile.relics[relic.key] or 0) + room
			profile.stats.relics += room
			return function()
				for _ = 1, room do
					table.remove(profile.backpack)
				end
				profile.relics[relic.key] -= room
				profile.stats.relics -= room
			end,
				"grantedFill",
				{ n = room }
		end
		return fallbackCoins(profile, 150), "grantedCoins", { n = 150 }
	end
	return nil, nil, nil
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

	local revert, toastKey, toastArgs = applySpecialProduct(session, product)
	local coins, enchants = 0, 0
	if not toastKey then
		-- The original coin / enchant products (CoinsSmall..Large, LuckyEnchant, UnlockBoost).
		if product.unlockBoost then
			coins = if profile.unlocked < Config.WorldCount
				then Economy.unlockCost(profile.unlocked + 1)
				else Economy.nice(Economy.unlockCost(Config.WorldCount) * 0.15)
		elseif product.dives > 0 then
			coins = Economy.productCoins(product.dives, profile.unlocked)
		end
		enchants = product.enchants or 0
		profile.coins += coins
		profile.lifetime += coins
		profile.enchants += enchants
		revert = function()
			profile.coins -= coins
			profile.lifetime -= coins
			profile.enchants -= enchants
		end
	end

	table.insert(profile.receipts, receiptId)
	while #profile.receipts > 50 do
		table.remove(profile.receipts, 1)
	end
	ProfileStore.markDirty(player)
	if not ProfileStore.save(player, false) then
		if revert then
			revert()
		end
		local index = table.find(profile.receipts, receiptId)
		if index then
			table.remove(profile.receipts, index)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if product.backpackFill or product.petReroll or product.guaranteedMutation then
		Sessions.publishPets(session)
	end
	Sync.profile(session)
	if toastKey then
		Net.push(player, "toast", { key = toastKey, kind = "gold", args = toastArgs })
	else
		Net.push(player, "toast", { key = "thanks", kind = "gold" })
		Net.push(player, "purchase", { coins = coins, enchants = enchants })
	end
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
			local profile = session.profile
			if key == "PetSlots" then
				PetService.clampEquipped(session)
			elseif key == "StarterPack" and not profile.starterPackGranted then
				profile.starterPackGranted = true
				local reward = Config.StarterPackReward
				profile.coins += reward.coins
				profile.lifetime += reward.coins
				profile.enchants += reward.enchants or 0
				local item = Gear.get(reward.gearKey)
				if item then
					profile.gear.owned[item.key] = true
					if item.tier > Gear.tier(profile.gear.equip[item.slot]) then
						profile.gear.equip[item.slot] = item.key
					end
					GearService.dress(session)
				end
				task.spawn(ProfileStore.save, player, false)
			end
			applyCosmetics(session)
			Sync.profile(session)
			Net.push(player, "toast", { key = "thanks", kind = "gold" })
		end
	end)
end

return PurchaseService
