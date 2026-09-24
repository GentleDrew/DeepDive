--!strict
-- Pushes profile snapshots to the owning client and keeps leaderstats in step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

local Net = require(script.Parent.Net)
local ProfileStore = require(script.Parent.ProfileStore)
local Sessions = require(script.Parent.Sessions)

local Sync = {}

function Sync.view(session: Sessions.Session)
	return {
		profile = session.profile,
		passes = session.passes,
		world = session.world,
		memory = ProfileStore.memoryMode,
	}
end

-- Public stats as player attributes (nameplates, the Tab list and the global board read these)
-- plus classic leaderstats for tools that expect them.
function Sync.stats(session: Sessions.Session)
	local player = session.player
	local profile = session.profile
	player:SetAttribute("Coins", profile.coins)
	player:SetAttribute("Relics", profile.stats.relics)
	player:SetAttribute("Lifetime", profile.lifetime)
	local stats: Instance? = player:FindFirstChild("leaderstats")
	if not stats then
		local folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		local coins = Instance.new("StringValue")
		coins.Name = "Coins"
		coins.Parent = folder
		local relics = Instance.new("IntValue")
		relics.Name = "Relics"
		relics.Parent = folder
		folder.Parent = player
		stats = folder
	end
	assert(stats, "leaderstats")
	local coinsValue = stats:FindFirstChild("Coins") :: StringValue?
	local relicsValue = stats:FindFirstChild("Relics") :: IntValue?
	if coinsValue then
		coinsValue.Value = Format.short(profile.coins)
	end
	if relicsValue then
		relicsValue.Value = profile.stats.relics
	end
end

Sync.leaderstats = Sync.stats

-- Call after any profile change.
function Sync.profile(session: Sessions.Session)
	ProfileStore.markDirty(session.player)
	Sync.stats(session)
	Net.push(session.player, "profile", Sync.view(session))
end

return Sync
