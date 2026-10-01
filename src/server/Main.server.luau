--!strict
-- Server entry point: builds the ocean + first world, loads profiles and spawns divers into the
-- world they last played. Remaining worlds build in the background.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Operators = require(Shared.Operators)
local Profile = require(Shared.Profile)

local Net = require(script.Parent.Net)
local ProfileStore = require(script.Parent.ProfileStore)
local Sessions = require(script.Parent.Sessions)
local Sync = require(script.Parent.Sync)
local WorldBuilder = require(script.Parent.World.WorldBuilder)
local ActionService = require(script.Parent.Services.ActionService)
local DiveService = require(script.Parent.Services.DiveService)
local GearService = require(script.Parent.Services.GearService)
local LeaderboardService = require(script.Parent.Services.LeaderboardService)
local PetService = require(script.Parent.Services.PetService)
local PurchaseService = require(script.Parent.Services.PurchaseService)
local RewardService = require(script.Parent.Services.RewardService)
local StatueService = require(script.Parent.Services.StatueService)
local TradeService = require(script.Parent.Services.TradeService)

Net.init()
ProfileStore.init()
ProfileStore.onSaved = function(player: Player)
	Net.push(player, "saved")
end
WorldBuilder.init()
DiveService.init()
PetService.init()
GearService.init()
TradeService.init()
ActionService.init()
PurchaseService.init()
RewardService.init()
LeaderboardService.init()
StatueService.init()

local function spawnCharacter(player: Player)
	if not player.Parent then
		return
	end
	local ok, err = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok then
		warn("[DeepDive] LoadCharacterAsync failed: " .. tostring(err))
	end
end

local function onCharacter(session: Sessions.Session, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	character:PivotTo(Layout.spawnCFrame(session.world))
	humanoid.WalkSpeed = 20
	-- Clients draw their own nameplates (name + coins) above every diver.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	-- Worn gear (tank, bag, flippers, magnet) once the body parts exist.
	character:WaitForChild(if humanoid.RigType == Enum.HumanoidRigType.R15 then "UpperTorso" else "Torso", 10)
	if Sessions.get(session.player) == session and session.player.Character == character then
		GearService.dress(session)
	end
	-- Avatar appearance loads after spawn and swaps body parts (body packages), which breaks the
	-- welds holding worn gear; dress again whenever a body part is replaced.
	local pending = false
	character.ChildAdded:Connect(function(child)
		if not child:IsA("BasePart") or pending then
			return
		end
		pending = true
		task.delay(0.2, function()
			pending = false
			if Sessions.get(session.player) == session and session.player.Character == character then
				GearService.dress(session)
			end
		end)
	end)
	humanoid.Died:Connect(function()
		DiveService.onDied(session)
		task.delay(2.5, function()
			if Sessions.get(session.player) == session then
				spawnCharacter(session.player)
			end
		end)
	end)
end

local function onPlayerAdded(player: Player)
	local profile = ProfileStore.load(player)
	if not player.Parent then
		-- Left while loading: release the session lock right away.
		ProfileStore.save(player, true)
		return
	end
	if not profile then
		player:Kick("Deep Dive could not load your save right now. Please rejoin in a moment.")
		return
	end
	local session = Sessions.create(player, profile)
	PurchaseService.loadPasses(session)
	local builtOk, built = pcall(WorldBuilder.ensure, session.world)
	if not builtOk then
		-- World 1 is built before anyone joins, so it is always a safe place to land.
		session.world = 1
		profile.world = 1
		built = WorldBuilder.ensure(1)
	end
	if not player.Parent then
		return
	end
	PetService.clampEquipped(session)
	player:SetAttribute("World", session.world)
	-- Red nameplate + aura: the game's creator (or anyone listed in Config.AdminUserIds).
	local isOperator = Operators.is(player.UserId)
	player:SetAttribute("Operator", isOperator)
	-- Operators always have every world open, so testing (relics, hazards, etc.) never waits on
	-- grinding through the economy to unlock worlds the normal way.
	if isOperator and profile.unlocked < Config.WorldCount then
		profile.unlocked = Config.WorldCount
	end
	-- Directors always keep one limited GOD Shark.
	if isOperator then
		local hasShark = false
		for _, pet in profile.pets do
			hasShark = hasShark or pet.s == "godShark"
		end
		if not hasShark then
			Profile.addPet(profile, "godShark", { "GOD" })
		end
	end
	player.RespawnLocation = built.spawn
	Sync.leaderstats(session)
	player.CharacterAdded:Connect(function(character)
		onCharacter(session, character)
	end)
	session.ready = true
	spawnCharacter(player)
	Sync.profile(session)
	DiveService.rollLayout(session)
end

local function onPlayerRemoving(player: Player)
	local session = Sessions.get(player)
	if session then
		TradeService.onLeave(session)
		DiveService.onLeave(session)
		Sessions.remove(player)
	end
	ProfileStore.save(player, true)
end

-- Build the ocean and World 1 before anyone spawns; the rest follows in the background.
WorldBuilder.ensure(1)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

WorldBuilder.buildRemaining()
