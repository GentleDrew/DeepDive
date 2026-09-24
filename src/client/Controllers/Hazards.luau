--!strict
-- Hazards (jellyfish, urchins, puffers, eels, ice shards, lava bubbles, void orbs). Motion is
-- a pure function of server time, so every client sees them in the same place.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Build = require(Shared.Models.Build)
local Color = require(Shared.Color)
local Config = require(Shared.Config)
local PetModels = require(Shared.Models.PetModels)
local RelicModels = require(Shared.Models.RelicModels)
local Worlds = require(Shared.Data.Worlds)

local Hazards = {}

local player = Players.LocalPlayer

type Hazard = { kind: string, x: number, y: number, z: number, radius: number, range: number, speed: number, phase: number }
type Entry = { def: Hazard, model: Model, base: Vector3, lastHit: number }

local function buildModel(kind: string, world: number): Model
	local data = Worlds.get(world)
	local accent = Color.hex(data.accent[1])
	local model = Build.model("Hazard_" .. kind)
	if kind == "jelly" then
		PetModels.Shapes.jelly(model, Color3.fromRGB(255, 120, 200), Color3.fromRGB(255, 190, 240))
		Build.style(model, "neon", Color3.fromRGB(255, 120, 220))
		Build.fit(model, 3.4)
	elseif kind == "urchin" then
		RelicModels.Shapes.urchin(model, Color3.fromRGB(70, 30, 90), Color3.fromRGB(150, 70, 190))
		Build.fit(model, 3)
	elseif kind == "puffer" then
		PetModels.Shapes.puffer(model, Color3.fromRGB(255, 160, 90), Color3.fromRGB(200, 60, 60))
		Build.fit(model, 3.2)
	elseif kind == "eel" then
		PetModels.Shapes.eel(model, Color3.fromRGB(70, 80, 50), Color3.fromRGB(255, 220, 90))
		Build.fit(model, 5)
	elseif kind == "shard" then
		RelicModels.Shapes.crystal(model, if data.kit == "ice" then Color3.fromRGB(170, 225, 255) else accent, Color3.fromRGB(255, 255, 255))
		Build.style(model, "neon", accent)
		Build.fit(model, 3.4)
	elseif kind == "lava" then
		local ball = Build.ball(model, 2.4, CFrame.identity, Color3.fromRGB(255, 120, 30))
		ball.Material = Enum.Material.Neon
		Build.light(ball, Color3.fromRGB(255, 130, 40), 12, 2)
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = "rbxasset://textures/particles/fire_main.dds"
		fire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 60, 30))
		fire.LightEmission = 1
		fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0.2) })
		fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		fire.Lifetime = NumberRange.new(0.3, 0.6)
		fire.Rate = 22
		fire.Speed = NumberRange.new(1, 3)
		fire.Parent = ball
	else
		local core = Build.ball(model, 2, CFrame.identity, Color3.fromRGB(40, 10, 60))
		core.Material = Enum.Material.Neon
		local shell = Build.ball(model, 3.2, CFrame.identity, Color3.fromRGB(170, 90, 255))
		shell.Material = Enum.Material.ForceField
		Build.light(core, Color3.fromRGB(170, 90, 255), 14, 2)
		Build.sparkles(core, Color3.fromRGB(200, 140, 255), 8)
	end
	return model
end

local function positionAt(def: Hazard, base: Vector3, t: number): (Vector3, number)
	local w = t * def.speed + def.phase
	if def.kind == "jelly" then
		return base + Vector3.new(math.sin(w * 0.5) * 1.2, math.sin(w) * def.range, math.cos(w * 0.4) * 1.2), 0
	elseif def.kind == "urchin" then
		return base, w * 0.2
	elseif def.kind == "puffer" then
		return base + Vector3.new(math.cos(w * 0.6) * def.range, math.sin(w * 1.3) * 1.2, math.sin(w * 0.6) * def.range), -w * 0.6
	elseif def.kind == "eel" then
		return base + Vector3.new(math.cos(w * 0.5) * def.range, math.sin(w * 2) * 0.6, math.sin(w * 0.5) * def.range), -w * 0.5 - math.pi / 2
	elseif def.kind == "shard" then
		return base + Vector3.new(0, math.sin(w) * 1.5, 0), w * 0.7
	elseif def.kind == "lava" then
		local cycle = (w * 0.35) % 1
		return base + Vector3.new(0, cycle * def.range, 0), 0
	end
	return base + Vector3.new(math.sin(w * 0.5) * def.range, math.sin(w) * def.range * 0.3, math.sin(w) * def.range * 0.5), w
end

function Hazards.init(app: any)
	local folder = Instance.new("Folder")
	folder.Name = "Hazards"
	folder.Parent = Workspace:WaitForChild("DeepDiveClient")
	local entries: { Entry } = {}
	local loadedWorld = 0

	local function load(world: number)
		folder:ClearAllChildren()
		table.clear(entries)
		loadedWorld = world
		local worlds = Workspace:FindFirstChild("Worlds")
		local wf = worlds and worlds:FindFirstChild("World" .. world)
		local raw = wf and wf:GetAttribute("Hazards")
		if type(raw) ~= "string" then
			loadedWorld = 0
			return
		end
		local ok, list = pcall(HttpService.JSONDecode, HttpService, raw)
		if not ok or type(list) ~= "table" then
			return
		end
		for _, def in list do
			local model = buildModel(def.kind, world)
			model.Parent = folder
			table.insert(entries, { def = def, model = model, base = Vector3.new(def.x, def.y, def.z), lastHit = 0 })
		end
	end

	RunService.RenderStepped:Connect(function()
		local world = app.State.world
		if loadedWorld ~= world then
			load(world)
		end
		local t = Workspace:GetServerTimeNow()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local dive = app.State.dive
		local now = os.clock()
		for index, entry in entries do
			local position, spin = positionAt(entry.def, entry.base, t)
			entry.model:PivotTo(CFrame.new(position) * CFrame.Angles(0, spin, 0))
			if root and dive.active and not dive.blackout and now - entry.lastHit > Config.Dive.HazardImmunity then
				if (root.Position - position).Magnitude < entry.def.radius + 1.6 then
					entry.lastHit = now
					app.Net.hazard(index)
				end
			end
		end
	end)
end

return Hazards
