--!strict
-- Renders this player's relic layout (per-player treasure), the Ancient Chest with its light
-- beam, and handles magnet pickups (optimistic, rolled back if the server rejects).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Config = require(Shared.Config)
local RelicModels = require(Shared.Models.RelicModels)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)

local Relics = {}

local player = Players.LocalPlayer

type Entry = {
	point: number,
	key: string,
	model: Model,
	base: Vector3,
	phase: number,
	collecting: boolean,
	started: number,
}

local RARITY_LIGHT = { 7, 9, 11, 14, 18 }

function Relics.init(app: any)
	local folder = Instance.new("Folder")
	folder.Name = "Relics"
	folder.Parent = Workspace:WaitForChild("DeepDiveClient")

	local entries: { [number]: Entry } = {}
	local pending: { [number]: Entry } = {}
	local points: { Vector3 } = {}
	local chestPosition: Vector3? = nil
	local chest: Model? = nil
	local layoutId = 0
	local lastFullToast = 0
	local templates: { [string]: Model } = {}

	local function worldFolder(world: number): Instance?
		local worlds = Workspace:FindFirstChild("Worlds")
		return worlds and worlds:FindFirstChild("World" .. world)
	end

	local function loadPoints(world: number): boolean
		local wf = worldFolder(world)
		if not wf then
			return false
		end
		local raw = wf:GetAttribute("Points")
		local rawChest = wf:GetAttribute("Chest")
		if type(raw) ~= "string" then
			return false
		end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		if not ok or type(decoded) ~= "table" then
			return false
		end
		points = {}
		for i, p in decoded do
			points[i] = Vector3.new(p[1], p[2], p[3])
		end
		chestPosition = nil
		if type(rawChest) == "string" then
			local okChest, c = pcall(HttpService.JSONDecode, HttpService, rawChest)
			if okChest and type(c) == "table" then
				chestPosition = Vector3.new(c[1], c[2], c[3])
			end
		end
		return true
	end

	local function template(key: string): Model
		local existing = templates[key]
		if existing then
			return existing:Clone()
		end
		do
			local model = RelicModels.build(key)
			local relic = Worlds.relics[key]
			local root = model.PrimaryPart :: BasePart
			local color = Color.hex(relic.accent):Lerp(app.Theme.rarityColor(relic.rarity), 0.5)
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = RARITY_LIGHT[relic.rarity] or 8
			light.Brightness = 0.9 + relic.rarity * 0.35
			light.Shadows = false
			light.Parent = root
			if relic.rarity >= 3 then
				local sparkle = Instance.new("ParticleEmitter")
				sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				sparkle.Color = ColorSequence.new(app.Theme.rarityColor(relic.rarity))
				sparkle.LightEmission = 1
				sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
				sparkle.Lifetime = NumberRange.new(0.6, 1.2)
				sparkle.Rate = relic.rarity * 2
				sparkle.Speed = NumberRange.new(0.5, 1.5)
				sparkle.SpreadAngle = Vector2.new(180, 180)
				sparkle.Parent = root
			end
			if relic.rarity >= 5 then
				local highlight = Instance.new("Highlight")
				highlight.FillTransparency = 0.75
				highlight.FillColor = app.Theme.rarityColor(5)
				highlight.OutlineColor = app.Theme.rarityColor(5)
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.Parent = model
			end
			templates[key] = model
			return model:Clone()
		end
	end

	local function clearAll()
		for _, entry in entries do
			entry.model:Destroy()
		end
		table.clear(entries)
		for _, entry in pending do
			entry.model:Destroy()
		end
		table.clear(pending)
		if chest then
			chest:Destroy()
			chest = nil
		end
	end

	local function spawnRelic(point: number, key: string)
		local base = points[point]
		if not base then
			return
		end
		local model = template(key)
		model:PivotTo(CFrame.new(base))
		model.Parent = folder
		entries[point] = { point = point, key = key, model = model, base = base, phase = math.random() * 6.28, collecting = false, started = 0 }
	end

	local function spawnChest(world: number)
		if not chestPosition then
			return
		end
		local model = RelicModels.buildChest(world, 4.2)
		model:PivotTo(CFrame.new(chestPosition + Vector3.new(0, 1, 0)))
		model.Parent = folder
		local root = model.PrimaryPart :: BasePart
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(0, Config.SurfaceY - chestPosition.Y + 6, 0)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Parent = root
		local beam = Instance.new("Beam")
		beam.Attachment0 = bottom
		beam.Attachment1 = top
		beam.Width0 = 5
		beam.Width1 = 3
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120))
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.85) })
		beam.Parent = root
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(240, 60)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
		billboard.AlwaysOnTop = true
		billboard.LightInfluence = 0
		billboard.MaxDistance = 400
		billboard.Parent = root
		app.Kit.text({
			Text = Strings.get("chest"),
			TextSize = 30,
			Color = Color3.fromRGB(255, 230, 120),
			Stroke = 3,
			Size = UDim2.fromScale(1, 1),
			Parent = billboard,
		})
		chest = model
	end

	local function rebuild()
		clearAll()
		local layout = app.State.layout
		layoutId = layout.id
		if not loadPoints(layout.world) then
			-- The world may still be streaming its attributes in; retry shortly.
			task.delay(1, function()
				if app.State.layout.id == layoutId then
					rebuild()
				end
			end)
			return
		end
		for point, key in layout.relics do
			spawnRelic(point, key)
		end
		if layout.chest and not app.State.dive.chestCarried then
			spawnChest(layout.world)
		end
	end
	app.State.layoutChanged:Connect(rebuild)

	function Relics.restore(point: number)
		local entry = pending[point]
		if entry then
			pending[point] = nil
			entry.collecting = false
			entry.model.Parent = folder
			entry.model:PivotTo(CFrame.new(entry.base))
			entries[point] = entry
		elseif point == 0 and not chest and app.State.layout.chest then
			spawnChest(app.State.layout.world)
		end
	end

	function Relics.confirm(point: number)
		local entry = pending[point]
		if entry then
			pending[point] = nil
			entry.model:Destroy()
		end
	end

	function Relics.nearest(): Vector3?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return nil
		end
		local best, bestDistance = nil, math.huge
		for _, entry in entries do
			local d = (entry.base - root.Position).Magnitude
			if d < bestDistance then
				best, bestDistance = entry.base, d
			end
		end
		return best
	end

	local function collect(entry: Entry)
		entry.collecting = true
		entry.started = os.clock()
		entries[entry.point] = nil
		pending[entry.point] = entry
		local relic = Worlds.relics[entry.key]
		app.Sfx.play(if relic.rarity >= 3 then "CollectRare" else "Collect")
		app.Effects.floatText("+1 " .. Strings.name(relic.name), app.Theme.rarityColor(relic.rarity), UDim2.fromScale(0.5, 0.42), 28)
		app.Net.collect(layoutId, entry.point)
	end

	RunService.RenderStepped:Connect(function(dt: number)
		local t = os.clock()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local rootPosition = root and root.Position
		local dive = app.State.dive
		local magnet = app.State.upgrade("magnet")
		local capacity = app.State.capacity()
		local canCollect = rootPosition ~= nil and dive.inWater and not dive.blackout and not app.State.traveling
		local pendingCount = 0
		for _ in pending do
			pendingCount += 1
		end
		for _, entry in entries do
			local bob = math.sin(t * 2 + entry.phase) * 0.35
			entry.model:PivotTo(
				CFrame.new(entry.base + Vector3.new(0, bob, 0)) * CFrame.Angles(0.25 * math.sin(t + entry.phase), t * 0.9 + entry.phase, 0)
			)
			if canCollect and rootPosition and (rootPosition - entry.base).Magnitude <= magnet then
				if dive.cargo + pendingCount >= capacity then
					if t - lastFullToast > 3 then
						lastFullToast = t
						app.Toasts.show(Strings.get("backpackFull"), "bad", utf8.char(0x1F392))
						app.Hud.flashFull()
						app.Sfx.play("Error")
					end
				else
					pendingCount += 1
					collect(entry)
				end
			end
		end
		-- Pull collected relics into the diver while the server confirms.
		for point, entry in pending do
			if rootPosition then
				local age = t - entry.started
				local alpha = math.clamp(age / 0.25, 0, 1)
				local position = entry.base:Lerp(rootPosition, alpha * alpha)
				entry.model:PivotTo(CFrame.new(position) * CFrame.Angles(0, t * 8, 0))
				if age > 0.25 then
					entry.model.Parent = nil
				end
				if age > 4 then
					-- No answer from the server: give up on the optimistic pickup.
					pending[point] = nil
					entry.model:Destroy()
				end
			end
		end
		if chest and canCollect and rootPosition and chestPosition and (rootPosition - chestPosition).Magnitude <= magnet + 3 then
			chest:Destroy()
			chest = nil
			app.Net.collect(layoutId, 0)
		end
		local _ = dt
	end)
end

return Relics
