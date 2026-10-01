--!strict
-- Draws the ranking board at the current world's dock from the JSON the server publishes in
-- ReplicatedStorage. Arrows on the board switch between weekly (the default), monthly and all-time;
-- the podium statues beside it follow the same choice. The Director has their own row on top.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Rankings = require(Shared.Rankings)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)
local Strings = require(Shared.Strings)

local TierStyle = require(script.Parent.Parent.UI.TierStyle)

local Board = {}

local MEDALS = { utf8.char(0x1F947), utf8.char(0x1F948), utf8.char(0x1F949) }
local ROW = 36
local data: any = { boards = {}, directors = {} }

-- The board this player picked with the arrows (the statues follow it too).
Board.selected = "weekly"
Board.selectionChanged = Signal.new()

-- Weekly rank of a UserId (1..10) on the published board, for the player list's "#N" tags.
function Board.weeklyRank(userId: number): number?
	local weekly = data.boards.weekly
	if type(weekly) == "table" and type(weekly.entries) == "table" then
		for rank, entry in weekly.entries do
			if entry.u == userId then
				return rank
			end
		end
	end
	return nil
end

function Board.init(app: any)
	local Kit = app.Kit
	local current: SurfaceGui? = nil
	local localPlayer = Players.LocalPlayer

	local function decode()
		local value = ReplicatedStorage:FindFirstChild(Remotes.Board)
		if not value or not value:IsA("StringValue") then
			return
		end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, value.Value)
		if ok and type(decoded) == "table" and type(decoded.boards) == "table" then
			data = decoded
		end
	end

	local function nameText(entry: any): string
		return string.format('%s <font size="17" color="#a9c3df">@%s</font>', tostring(entry.d), tostring(entry.n))
	end

	local function avatar(parent: Instance, userId: number, x: number)
		local image = Kit.new("ImageLabel", {
			BackgroundColor3 = Color3.fromRGB(40, 64, 104),
			Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", math.max(1, userId)),
			Size = UDim2.fromOffset(ROW - 6, ROW - 6),
			Position = UDim2.new(0, x, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = parent,
		})
		Kit.round(image)
		Kit.stroke(image, Color3.new(1, 1, 1), 1.5)
	end

	local function row(root: Frame, order: number, entry: any, rankText: string, director: boolean, tint: Color3, transparency: number)
		local frame = Kit.new("Frame", {
			BackgroundColor3 = tint,
			BackgroundTransparency = transparency,
			Size = UDim2.new(1, 0, 0, ROW),
			LayoutOrder = order,
			Parent = root,
		})
		Kit.corner(frame, 10)
		local rank = Kit.text({
			Text = rankText,
			TextSize = if director then 17 else 24,
			Stroke = if director then 2 else (if string.sub(rankText, 1, 1) == "#" then 2 else 0),
			Size = UDim2.fromOffset(if director then 96 else 54, ROW),
			Position = UDim2.fromOffset(4, 0),
			Parent = frame,
		})
		if director then
			local stroke = Kit.stroke(frame, Color3.new(1, 1, 1), 2.5)
			TierStyle.director(stroke)
			TierStyle.director(rank)
		end
		local x = if director then 104 else 62
		avatar(frame, tonumber(entry.u) or 1, x)
		local name = Kit.text({
			Text = nameText(entry),
			Rich = true,
			TextSize = 23,
			Stroke = 2.2,
			Size = UDim2.new(1, -(x + 200), 1, 0),
			Position = UDim2.fromOffset(x + ROW + 2, 0),
			XAlign = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		name.TextTruncate = Enum.TextTruncate.AtEnd
		if director then
			TierStyle.director(name)
		else
			TierStyle.apply(name, tonumber(entry.t) or 0, Color3.new(1, 1, 1))
		end
		Kit.text({
			Text = Format.short(tonumber(entry.v) or 0),
			TextSize = 24,
			Color = Color3.fromRGB(255, 222, 92),
			Stroke = 2.4,
			Size = UDim2.fromOffset(150, ROW),
			Position = UDim2.new(1, -158, 0, 0),
			XAlign = Enum.TextXAlignment.Right,
			Parent = frame,
		})
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
		local board = Board.selected
		local section = data.boards[board] or {}
		local entries = if type(section.entries) == "table" then section.entries else {}
		local gui = Instance.new("SurfaceGui")
		gui.Name = "LeaderboardGui"
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		-- Drawn on the board but parented to PlayerGui, the only place a SurfaceGui takes clicks.
		gui.Adornee = screen
		gui.ResetOnSpawn = false
		gui.Parent = app.Gui.promptParent
		current = gui
		local root = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
		Kit.padding(root, 10, 20, 10, 20)
		Kit.list(root, Enum.FillDirection.Vertical, 3, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
		local titleRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 1, Parent = root })
		Kit.text({
			Text = utf8.char(0x1F3C6) .. "  " .. Strings.get("board." .. board),
			TextSize = 38,
			Color = Color3.fromRGB(255, 222, 92),
			Stroke = 4,
			Size = UDim2.new(1, -130, 1, 0),
			Position = UDim2.fromScale(0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = titleRow,
		})
		for _, side in { -1, 1 } do
			Kit.button({
				Name = if side < 0 then "BoardPrev" else "BoardNext",
				Text = if side < 0 then "<" else ">",
				TextSize = 30,
				Palette = "Gold",
				Size = UDim2.fromOffset(56, 46),
				Position = if side < 0 then UDim2.fromOffset(0, 2) else UDim2.new(1, 0, 0, 2),
				AnchorPoint = Vector2.new(if side < 0 then 0 else 1, 0),
				Radius = 14,
				Parent = titleRow,
				OnClick = function()
					local index = table.find(Rankings.Boards, Board.selected) or 1
					Board.selected = Rankings.Boards[(index - 1 + side) % #Rankings.Boards + 1]
					Board.selectionChanged:Fire(Board.selected)
					render()
				end,
			})
		end
		local subtitle = if section.reset
			then Strings.get("boardResets", { t = Strings.duration(section.reset - (os.time() - (data.at or os.time()))) })
			else Strings.get("boardForever")
		if data.global ~= true then
			subtitle ..= "  " .. Strings.get("boardLocalTag")
		end
		-- Which of the three boards is showing (dots).
		local dots = {}
		for _, name in Rankings.Boards do
			table.insert(dots, if name == board then utf8.char(0x25CF) else utf8.char(0x25CB))
		end
		Kit.text({
			Text = subtitle .. "   " .. table.concat(dots, " "),
			TextSize = 19,
			Color = Color3.fromRGB(170, 200, 235),
			Stroke = 2,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 2,
			Parent = root,
		})
		local director = data.directors[board]
		if director then
			row(root, 3, director, Strings.get("director"), true, Color3.fromRGB(8, 8, 12), 0.15)
		end
		if #entries == 0 then
			Kit.text({ Text = Strings.get("boardEmpty"), TextSize = 26, Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 4, Parent = root })
			return
		end
		for rank, entry in entries do
			if rank > 10 then
				break
			end
			local mine = entry.u == localPlayer.UserId
			row(
				root,
				10 + rank,
				entry,
				MEDALS[rank] or ("#" .. rank),
				false,
				if mine then Color3.fromRGB(255, 214, 90) else Color3.fromRGB(255, 255, 255),
				if mine then 0.55 elseif rank % 2 == 0 then 0.92 else 0.84
			)
		end
	end

	local function hook()
		local value = ReplicatedStorage:WaitForChild(Remotes.Board, 30)
		if value and value:IsA("StringValue") then
			value.Changed:Connect(function()
				decode()
				render()
			end)
		end
		decode()
		render()
	end
	task.spawn(hook)
	app.State.worldChanged:Connect(function()
		task.delay(0.5, render)
	end)
	app.State.languageChanged:Connect(render)
	-- The world folder may still be building when we first look; the reset countdown ticks too.
	task.spawn(function()
		local age = 0
		while true do
			task.wait(1)
			age += 1
			if not current or not current.Adornee or not current.Adornee.Parent or age >= 30 then
				age = 0
				render()
			end
		end
	end)
end

return Board
