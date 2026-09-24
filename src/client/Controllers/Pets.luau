--!strict
-- Renders equipped pets following every nearby player (from the replicated "Pets" attribute).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Mutations = require(Shared.Models.Mutations)
local PetModels = require(Shared.Models.PetModels)

local Pets = {}

local localPlayer = Players.LocalPlayer

type PetView = { key: string, model: Model, cf: CFrame, phase: number }
type Owner = { player: Player, pets: { PetView }, raw: string }

local RENDER_DISTANCE = 260

function Pets.init(app: any)
	local folder = Instance.new("Folder")
	folder.Name = "Pets"
	folder.Parent = Workspace:WaitForChild("DeepDiveClient")
	local owners: { [Player]: Owner } = {}
	local templates: { [string]: Model } = {}

	-- `entry` is "species" or "species|Gold,Lava" (see Sessions.publishPets).
	local function template(entry: string): Model
		local model = templates[entry]
		if not model then
			local key, mutations = Mutations.parse(entry)
			local built = PetModels.build(key)
			Mutations.apply(built, mutations)
			templates[entry] = built
			return built:Clone()
		end
		return model:Clone()
	end

	local function clear(owner: Owner)
		for _, pet in owner.pets do
			pet.model:Destroy()
		end
		table.clear(owner.pets)
	end

	local function sync(player: Player)
		local raw = player:GetAttribute("Pets")
		local text = if type(raw) == "string" then raw else "[]"
		local owner = owners[player]
		if not owner then
			owner = { player = player, pets = {}, raw = "" }
			owners[player] = owner
		end
		if owner.raw == text then
			return
		end
		owner.raw = text
		clear(owner)
		local ok, keys = pcall(HttpService.JSONDecode, HttpService, text)
		if not ok or type(keys) ~= "table" then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local start = if root then root.CFrame else CFrame.new()
		for _, key in keys do
			if type(key) == "string" then
				local model = template(key)
				model.Parent = folder
				table.insert(owner.pets, { key = key, model = model, cf = start, phase = math.random() * 6.28 })
			end
		end
	end

	local function track(player: Player)
		sync(player)
		player:GetAttributeChangedSignal("Pets"):Connect(function()
			sync(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		track(player)
	end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		local owner = owners[player]
		if owner then
			clear(owner)
			owners[player] = nil
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
		local hideOthers = app.State.settings().hidePets
		local t = os.clock()
		for player, owner in owners do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local visible = root ~= nil and (player == localPlayer or not hideOthers) and (root.Position - cameraPosition).Magnitude < RENDER_DISTANCE
			local count = #owner.pets
			for i, pet in owner.pets do
				if not visible or not root then
					if pet.model.Parent then
						pet.model.Parent = nil
					end
					continue
				end
				if not pet.model.Parent then
					pet.model.Parent = folder
					pet.cf = root.CFrame
				end
				-- Arc behind the owner; pets bob and face where the owner is heading.
				local look = root.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
				local basis = CFrame.lookAt(root.Position, root.Position + flat)
				local spread = (i - (count + 1) / 2) * 1.0
				local offset = Vector3.new(math.sin(spread) * 5, 1.6 + math.sin(t * 2.4 + pet.phase) * 0.45, math.cos(spread) * 4.5 + 1.5)
				local targetPosition = basis:PointToWorldSpace(offset)
				local position = pet.cf.Position:Lerp(targetPosition, 1 - math.exp(-7 * dt))
				local velocity = targetPosition - pet.cf.Position
				local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
				local faceDirection = if flatVelocity.Magnitude > 1.5 then flatVelocity.Unit else flat
				local target = CFrame.lookAt(position, position + faceDirection)
					* CFrame.Angles(math.sin(t * 3 + pet.phase) * 0.08, 0, math.sin(t * 2 + pet.phase) * 0.1)
				pet.cf = pet.cf:Lerp(target, 1 - math.exp(-10 * dt))
				pet.cf = CFrame.new(position) * pet.cf.Rotation
				pet.model:PivotTo(pet.cf)
			end
		end
	end)
end

return Pets
