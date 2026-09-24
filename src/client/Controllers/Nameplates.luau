--!strict
-- Floating nameplates above every diver (including you): display name and coins. Coins come
-- from the "Coins" attribute the server keeps on each player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)

local Nameplates = {}

type Plate = { gui: BillboardGui, connections: { RBXScriptConnection } }

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
		Kit.text({
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
		plates[player] = { gui = gui, connections = { player:GetAttributeChangedSignal("Coins"):Connect(refresh) } }
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
