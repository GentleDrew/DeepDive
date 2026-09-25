--!strict
-- SwimTrail pass cosmetic: a sparkling trail behind any diver (including you) who owns it, shown
-- only while they're actually underwater. No server-replicated "swimming" state is needed - depth
-- is just read off the character's own position, which always replicates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Trails = {}

local DEPTH_THRESHOLD = 2 -- studs below the surface before the trail shows

local function buildEmitter(root: BasePart): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(150, 235, 255), Color3.fromRGB(90, 170, 255))
	emitter.LightEmission = 0.9
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(0.2, 0.8)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Parent = root
	return emitter
end

function Trails.init()
	local emitters: { [Player]: ParticleEmitter } = {}

	local function clear(player: Player)
		local emitter = emitters[player]
		if emitter then
			emitter:Destroy()
			emitters[player] = nil
		end
	end

	local function refresh(player: Player)
		local owns = player:GetAttribute("Trail") == true
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if owns and root and not emitters[player] then
			emitters[player] = buildEmitter(root)
		elseif (not owns or not root) and emitters[player] then
			clear(player)
		end
	end

	local function watch(player: Player)
		player:GetAttributeChangedSignal("Trail"):Connect(function()
			refresh(player)
		end)
		player.CharacterAdded:Connect(function()
			clear(player)
			task.defer(refresh, player)
		end)
		refresh(player)
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clear)

	RunService.Heartbeat:Connect(function()
		for player, emitter in emitters do
			local root = emitter.Parent :: BasePart?
			local depth = if root then Config.SurfaceY - root.Position.Y else -1
			emitter.Rate = if depth > DEPTH_THRESHOLD then 10 else 0
		end
	end)
end

return Trails
