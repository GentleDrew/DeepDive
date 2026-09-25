--!strict
-- Floating nameplates above every diver (including you): display name and coins. Coins come
-- from the "Coins" attribute the server keeps on each player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

local Nameplates = {}

type Plate = { gui: BillboardGui, name: TextLabel, aura: ParticleEmitter?, connections: { RBXScriptConnection } }

local VIP_CROWN = utf8.char(0x1F451) .. " "

-- Gold sparkle worn by VIPAura pass owners, attached to the root part.
local function auraEmitter(root: BasePart): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 226, 130), Color3.fromRGB(255, 190, 40))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.7, 1.2)
	emitter.Rate = 6
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = root
	return emitter
end

function Nameplates.init(app: any)
	local Kit = app.Kit
	local localPlayer = Players.LocalPlayer
	local plates: { [Player]: Plate } = {}

	local function remove(player: Player)
		local plate = plates[player]
		if plate then
			for _, connection in plate.connections do
				connection:Disconnect()
			end
			plate.gui:Destroy()
			plates[player] = nil
		end
	end

	local function build(player: Player, character: Model)
		remove(player)
		local head = character:WaitForChild("Head", 10)
		if not head or player.Character ~= character then
			return
		end
		local isMe = player == localPlayer
		local gui = Instance.new("BillboardGui")
		gui.Name = "DeepDiveNameplate"
		gui.Size = UDim2.fromOffset(240, 62)
		gui.StudsOffset = Vector3.new(0, 2.7, 0)
		gui.Adornee = head :: Instance
		gui.LightInfluence = 0
		gui.MaxDistance = 110
		gui.ResetOnSpawn = false
		gui.Parent = app.Gui.promptParent
		local column = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
		Kit.list(column, Enum.FillDirection.Vertical, 0)
		local name = Kit.text({
			Text = player.DisplayName,
			TextSize = 22,
			Color = if isMe then Color3.fromRGB(255, 236, 150) else Color3.new(1, 1, 1),
			Stroke = 3,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = 1,
			Parent = column,
		})
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 2, Parent = column })
		Kit.list(row, Enum.FillDirection.Horizontal, 4)
		local coin = Kit.Icons.coin(20, row)
		coin.LayoutOrder = 1
		local amount = Kit.text({
			Text = "0",
			TextSize = 20,
			Color = Color3.fromRGB(255, 222, 92),
			Stroke = 3,
			StrokeColor = Color3.fromRGB(90, 56, 8),
			Size = UDim2.new(0, 0, 1, 0),
			AutoX = true,
			LayoutOrder = 2,
			Parent = row,
		})
		local function refresh()
			local coins = player:GetAttribute("Coins")
			amount.Text = Format.short(if type(coins) == "number" then coins else 0)
		end
		refresh()
		local nameStroke = name:FindFirstChildOfClass("UIStroke")
		local plate: Plate = { gui = gui, name = name, aura = nil, connections = { player:GetAttributeChangedSignal("Coins"):Connect(refresh) } }
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local function refreshVip()
			local vip = player:GetAttribute("VIP") == true
			name.Text = (if vip then VIP_CROWN else "") .. player.DisplayName
			if vip and not plate.aura and root then
				plate.aura = auraEmitter(root)
			elseif not vip and plate.aura then
				plate.aura:Destroy()
				plate.aura = nil
			end
			if nameStroke then
				local border = player:GetAttribute("Border")
				nameStroke.Color = if border == "Gold"
					then Color3.fromRGB(255, 214, 90)
					elseif border == "Silver" then Color3.fromRGB(210, 220, 232)
					else Color3.fromRGB(21, 38, 58) -- Theme.C.Ink, the stroke's normal default
			end
		end
		refreshVip()
		table.insert(plate.connections, player:GetAttributeChangedSignal("VIP"):Connect(refreshVip))
		table.insert(plate.connections, player:GetAttributeChangedSignal("Border"):Connect(refreshVip))
		plates[player] = plate
	end

	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			build(player, character)
		end)
		if player.Character then
			task.spawn(build, player, player.Character)
		end
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(remove)
end

return Nameplates
