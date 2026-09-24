--!strict
-- Custom player list (replaces Roblox's Tab list): avatar, nickname, coins and relics collected,
-- sorted by coins. Tab toggles it; touch screens get a button instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)

local Anim = require(script.Parent.Anim)
local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local PlayerList = {}

local C = Theme.C
local VIP_CROWN = utf8.char(0x1F451) .. " "
local WIDTH = 392
local ROW = 38
-- Columns start after the avatar (42); the trade button (34) follows the relic column and the
-- row keeps an 8px right margin: 42 + 136 + 80 + 62 + 6 + 34 + 8 = 368 = 392 - 16 - 8.
local NAME_W, COIN_W, RELIC_W = 136, 80, 62
local TRADE_X = 42 + NAME_W + COIN_W + RELIC_W + 6

type Row = { frame: Frame, name: TextLabel, coins: TextLabel, relics: TextLabel, stroke: UIStroke }

function PlayerList.init(onTrade: ((Player) -> ())?)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	local localPlayer = Players.LocalPlayer

	local panel = Kit.new("Frame", {
		Name = "PlayerList",
		BackgroundColor3 = C.Navy,
		BackgroundTransparency = 0.18,
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(1, -16, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		Parent = Gui.hudTop,
	}) :: Frame
	Kit.corner(panel, 14)
	Kit.stroke(panel, C.Outline, 2.5)
	Kit.padding(panel, 0, 8, 8, 8)
	Kit.list(panel, Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	local header = Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, 16, 0, 40), LayoutOrder = 0, Parent = panel })
	Kit.corner(header, 14)
	Kit.gradient(header, Theme.Buttons.Purple[1], Theme.Buttons.Blue[2], 0)
	local title = Kit.text({
		Text = "",
		TextSize = 19,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.fromOffset(12, 0),
		XAlign = Enum.TextXAlignment.Left,
		Stroke = 2.5,
		Parent = header,
	})

	local function columns(parent: Instance, size: number, color: Color3?, stroke: number?): (TextLabel, TextLabel, TextLabel)
		local name = Kit.text({
			Text = "",
			TextSize = size,
			Color = color,
			Stroke = stroke,
			Size = UDim2.fromOffset(NAME_W, ROW),
			Position = UDim2.fromOffset(42, 0),
			XAlign = Enum.TextXAlignment.Left,
			Parent = parent,
		})
		local coins = Kit.text({
			Text = "",
			TextSize = size,
			Color = color,
			Stroke = stroke,
			Size = UDim2.fromOffset(COIN_W, ROW),
			Position = UDim2.fromOffset(42 + NAME_W, 0),
			XAlign = Enum.TextXAlignment.Right,
			Parent = parent,
		})
		local relics = Kit.text({
			Text = "",
			TextSize = size,
			Color = color,
			Stroke = stroke,
			Size = UDim2.fromOffset(RELIC_W, ROW),
			Position = UDim2.fromOffset(42 + NAME_W + COIN_W, 0),
			XAlign = Enum.TextXAlignment.Right,
			Parent = parent,
		})
		return name, coins, relics
	end

	local labels = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, Parent = panel })
	local labelName, labelCoins, labelRelics = columns(labels, 13, Color3.fromRGB(170, 196, 226), 0)
	for _, label in { labelName, labelCoins, labelRelics } do
		label.Size = UDim2.new(0, label.Size.X.Offset, 1, 0)
	end

	local rows: { [Player]: Row } = {}

	local function makeRow(player: Player): Row
		local frame = Kit.new("Frame", {
			Name = player.Name,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.9,
			Size = UDim2.new(1, 0, 0, ROW),
			Parent = panel,
		}) :: Frame
		Kit.corner(frame, 10)
		local stroke = Kit.stroke(frame, Theme.Buttons.Gold[2], 2)
		stroke.Enabled = player == localPlayer
		local avatar = Kit.new("ImageLabel", {
			BackgroundColor3 = Color3.fromRGB(60, 90, 140),
			Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=48&h=48", math.max(1, player.UserId)),
			Size = UDim2.fromOffset(30, 30),
			Position = UDim2.fromOffset(6, 4),
			Parent = frame,
		})
		Kit.round(avatar)
		Kit.stroke(avatar, C.Outline, 2)
		local name, coins, relics = columns(frame, 17, nil, 2)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		if player == localPlayer then
			name.TextColor3 = Color3.fromRGB(255, 232, 140)
		end
		coins.TextColor3 = Color3.fromRGB(255, 222, 92)
		relics.TextColor3 = Color3.fromRGB(150, 230, 255)
		if player ~= localPlayer and onTrade then
			Kit.button({
				Name = "Trade",
				Text = "",
				Icon = utf8.char(0x1F91D),
				IconSize = 17,
				Palette = "Cyan",
				Size = UDim2.fromOffset(34, 30),
				Position = UDim2.new(0, TRADE_X, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Radius = 10,
				Stroke = 2,
				Parent = frame,
				OnClick = function()
					onTrade(player)
				end,
			})
		end
		local row = { frame = frame, name = name, coins = coins, relics = relics, stroke = stroke }
		rows[player] = row
		return row
	end

	local function numberOf(player: Player, attribute: string): number
		local value = player:GetAttribute(attribute)
		return if type(value) == "number" then value else 0
	end

	local function refresh()
		local list = Players:GetPlayers()
		table.sort(list, function(a, b)
			local ca, cb = numberOf(a, "Coins"), numberOf(b, "Coins")
			if ca ~= cb then
				return ca > cb
			end
			return a.Name < b.Name
		end)
		for index, player in list do
			local row = rows[player] or makeRow(player)
			row.frame.LayoutOrder = 10 + index
			row.name.Text = (if player:GetAttribute("VIP") == true then VIP_CROWN else "") .. player.DisplayName
			row.coins.Text = Format.short(numberOf(player, "Coins"))
			row.relics.Text = Format.short(numberOf(player, "Relics"))
		end
		title.Text = utf8.char(0x1F465) .. "  " .. Strings.get("playersTitle") .. "  " .. #list
		labelName.Text = Strings.get("colName")
		labelCoins.Text = Strings.get("colCoins")
		labelRelics.Text = Strings.get("colRelics")
	end

	local function watch(player: Player)
		player:GetAttributeChangedSignal("Coins"):Connect(refresh)
		player:GetAttributeChangedSignal("Relics"):Connect(refresh)
		player:GetAttributeChangedSignal("VIP"):Connect(refresh)
		refresh()
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local row = rows[player]
		if row then
			row.frame:Destroy()
			rows[player] = nil
		end
		task.defer(refresh)
	end)

	-- Visibility: open by default with a keyboard, toggled with Tab or the touch button.
	local touch = Gui.isTouch()
	panel.Visible = not touch
	local function setOpen(open: boolean)
		panel.Visible = open
		if open then
			Anim.pop(panel, 0.06)
			refresh()
		end
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.Tab then
			setOpen(not panel.Visible)
		end
	end)
	if touch then
		local toggle = Kit.button({
			Name = "PlayersButton",
			Text = "",
			Icon = utf8.char(0x1F465),
			IconSize = 24,
			Palette = "Purple",
			Size = UDim2.fromOffset(52, 52),
			Position = UDim2.new(1, -16, 0, 6),
			AnchorPoint = Vector2.new(1, 0),
			Radius = 26,
			Stroke = 2.5,
			Parent = Gui.hudTop,
			OnClick = function()
				setOpen(not panel.Visible)
			end,
		})
		panel.Position = UDim2.new(1, -16, 0, 64)
		local _ = toggle
	end
	refresh()
	return { refresh = refresh, setOpen = setOpen }
end

return PlayerList
