--!strict
-- Ambient fish schools that circle the lagoon and scatter from the diver.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Layout = require(Shared.Layout)
local Worlds = require(Shared.Data.Worlds)

local Fish = {}

local player = Players.LocalPlayer

type FishEntry = { body: BasePart, tail: BasePart, offset: Vector3, phase: number, position: Vector3 }
type School = { fish: { FishEntry }, radius: number, depth: number, speed: number, phase: number, tilt: number }

function Fish.init(app: any)
	local folder = Instance.new("Folder")
	folder.Name = "Fish"
	folder.Parent = Workspace:WaitForChild("DeepDiveClient")
	local schools: { School } = {}
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local loadedWorld = 0
	local loadedLow = false

	local function newPart(size: Vector3, color: Color3, wedge: boolean, glow: boolean): BasePart
		local part: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
		part.Size = size
		part.Color = color
		part.Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = folder
		if not wedge then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		return part
	end

	local function build(world: number)
		folder:ClearAllChildren()
		table.clear(schools)
		table.clear(parts)
		loadedWorld = world
		local data = Worlds.get(world)
		local info = Layout.info(world)
		local low = app.State.settings().lowFx
		loadedLow = low
		local rng = Random.new(world * 977)
		local schoolCount = if low then 2 else 4
		for s = 1, schoolCount do
			local color = Color.hex(data.fish[((s - 1) % #data.fish) + 1])
			local school: School = {
				fish = {},
				radius = rng:NextNumber(0.35, 0.75) * info.midRadius,
				depth = rng:NextNumber(0.2, 0.75) * info.depth,
				speed = rng:NextNumber(0.12, 0.22) * (if rng:NextNumber() < 0.5 then 1 else -1),
				phase = rng:NextNumber(0, math.pi * 2),
				tilt = rng:NextNumber(-0.3, 0.3),
			}
			local count = rng:NextInteger(6, 9)
			for _ = 1, count do
				local scale = rng:NextNumber(0.8, 1.2)
				local body = newPart(Vector3.new(0.55, 0.75, 1.3) * scale, color, false, data.fishGlow)
				local tail = newPart(Vector3.new(0.1, 0.6, 0.5) * scale, Color.darken(color, 0.2), true, data.fishGlow)
				table.insert(school.fish, {
					body = body,
					tail = tail,
					offset = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(-2, 2), rng:NextNumber(-4, 4)),
					phase = rng:NextNumber(0, 6),
					position = info.origin,
				})
				table.insert(parts, body)
				table.insert(parts, tail)
			end
			table.insert(schools, school)
		end
	end

	RunService.RenderStepped:Connect(function(dt: number)
		local world = app.State.world
		local low = app.State.settings().lowFx
		if world ~= loadedWorld or low ~= loadedLow then
			build(world)
		end
		local info = Layout.info(world)
		local t = os.clock()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local diver = root and root.Position
		local index = 0
		table.clear(cframes)
		for _, school in schools do
			local angle = t * school.speed + school.phase
			local center = info.origin
				+ Vector3.new(math.cos(angle) * school.radius, -school.depth + math.sin(t * 0.3 + school.phase) * 3, math.sin(angle) * school.radius)
			local heading = Vector3.new(-math.sin(angle), 0, math.cos(angle)) * math.sign(school.speed)
			for _, fish in school.fish do
				local wobble = Vector3.new(math.sin(t * 1.3 + fish.phase), math.sin(t * 0.9 + fish.phase) * 0.5, math.cos(t * 1.1 + fish.phase))
				local target = center + fish.offset + wobble
				if diver then
					local away = target - diver
					local distance = away.Magnitude
					if distance < 9 and distance > 0.01 then
						target += away.Unit * (9 - distance) * 1.4
					end
				end
				local previous = fish.position
				fish.position = previous:Lerp(target, math.clamp(dt * 3, 0, 1))
				local velocity = fish.position - previous
				-- Fish swim mostly level: damp the climb so the look direction never goes vertical.
				local level = Vector3.new(velocity.X, velocity.Y * 0.35, velocity.Z)
				local direction = if Vector3.new(level.X, 0, level.Z).Magnitude > 0.004 then level.Unit else heading
				local cf = CFrame.lookAt(fish.position, fish.position + direction)
				local swish = math.sin(t * 10 + fish.phase) * 0.5
				index += 1
				cframes[index] = cf
				index += 1
				-- WedgePart is tallest at +Z, which is the back of the fish here.
				cframes[index] = cf * CFrame.new(0, 0, fish.body.Size.Z * 0.62) * CFrame.Angles(0, swish, 0)
			end
		end
		if #parts > 0 then
			Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return Fish
