--!strict
-- Draws the global leaderboard on the board at the current world's dock, from the JSON the
-- server publishes in ReplicatedStorage (top 10 by lifetime coins).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Remotes = require(Shared.Remotes)
local Strings = require(Shared.Strings)

local Board = {}

local MEDALS = { utf8.char(0x1F947), utf8.char(0x1F948), utf8.char(0x1F949) }

function Board.init(app: any)
	local Kit = app.Kit
	local current: SurfaceGui? = nil
	local localPlayer = Players.LocalPlayer

	local function decode(): (boolean, { any })
		local value = ReplicatedStorage:FindFirstChild(Remotes.Board)
		if not value or not value:IsA("StringValue") then
			return false, {}
		end
		local ok, data = pcall(HttpService.JSONDecode, HttpService, value.Value)
		if not ok or type(data) ~= "table" or type(data.entries) ~= "table" then
			return false, {}
		end
		return data.global == true, data.entries
	end

	local function render()
		if current then
			current:Destroy()
			current = nil
		end
		local worlds = Workspace:FindFirstChild("Worlds")
		local folder = worlds and worlds:FindFirstChild("World" .. app.State.world)
		local screen = folder and folder:FindFirstChild("BoardScreen", true)
		if not screen or not screen:IsA("BasePart") then
			return
		end
		local global, entries = decode()
		local gui = Instance.new("SurfaceGui")
		gui.Name = "LeaderboardGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		gui.Parent = screen
		current = gui
		local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
		Kit.padding(root, 14, 22, 14, 22)
		Kit.list(root, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
		Kit.text({
			Text = utf8.char(0x1F3C6) .. "  " .. Strings.get("boardTitle"),
			TextSize = 46,
			Color = Color3.fromRGB(255, 222, 92),
			Stroke = 4,
			Size = UDim2.new(1, 0, 0, 54),
			LayoutOrder = 1,
			Parent = root,
		})
		Kit.text({
			Text = Strings.get(if global then "boardGlobal" else "boardLocal"),
			TextSize = 22,
			Color = Color3.fromRGB(170, 200, 235),
			Stroke = 2,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = 2,
			Parent = root,
		})
		if #entries == 0 then
			Kit.text({ Text = Strings.get("boardEmpty"), TextSize = 26, Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 3, Parent = root })
			return
		end
		for rank, entry in entries do
			if rank > 10 then
				break
			end
			local mine = entry.u == localPlayer.UserId
			local row = Kit.new("Frame", {
				BackgroundColor3 = if mine then Color3.fromRGB(255, 214, 90) else Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = if mine then 0.55 else if rank % 2 == 0 then 0.92 else 0.84,
				Size = UDim2.new(1, 0, 0, 36),
				LayoutOrder = 10 + rank,
				Parent = root,
			})
			Kit.corner(row, 10)
			Kit.text({
				Text = MEDALS[rank] or ("#" .. rank),
				TextSize = if rank <= 3 then 28 else 24,
				Stroke = if rank <= 3 then 0 else 2,
				Size = UDim2.fromOffset(60, 36),
				Position = UDim2.fromOffset(6, 0),
				Parent = row,
			})
			Kit.text({
				Text = tostring(entry.n),
				TextSize = 26,
				Color = if rank == 1 then Color3.fromRGB(255, 230, 120) else Color3.new(1, 1, 1),
				Stroke = 2.5,
				Size = UDim2.new(1, -260, 1, 0),
				Position = UDim2.fromOffset(72, 0),
				XAlign = Enum.TextXAlignment.Left,
				Parent = row,
			})
			Kit.text({
				Text = Format.short(tonumber(entry.v) or 0),
				TextSize = 26,
				Color = Color3.fromRGB(255, 222, 92),
				Stroke = 2.5,
				Size = UDim2.fromOffset(170, 36),
				Position = UDim2.new(1, -180, 0, 0),
				XAlign = Enum.TextXAlignment.Right,
				Parent = row,
			})
		end
	end

	local function hook()
		local value = ReplicatedStorage:WaitForChild(Remotes.Board, 30)
		if value and value:IsA("StringValue") then
			value.Changed:Connect(render)
		end
		render()
	end
	task.spawn(hook)
	app.State.worldChanged:Connect(function()
		task.delay(0.5, render)
	end)
	app.State.languageChanged:Connect(render)
	-- The world folder may still be building when we first look.
	task.delay(3, render)
end

return Board
