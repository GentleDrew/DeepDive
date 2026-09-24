--!strict
-- Relic index: every world's five relics. Discovered relics show their 3D model, rarity, value
-- and how many you have collected; undiscovered ones are black silhouettes marked "???".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)

local Kit = require(script.Parent.Parent.Kit)
local Panel = require(script.Parent.Parent.Panel)
local Theme = require(script.Parent.Parent.Theme)
local Viewport = require(script.Parent.Parent.Viewport)

local IndexPanel = {}

local C = Theme.C
local RELICS_PER_WORLD = 5

type Card = {
	frame: Frame,
	view: Viewport.ViewApi,
	name: TextLabel,
	rarityChip: Frame,
	rarity: TextLabel,
	worth: TextLabel,
	count: TextLabel,
	key: string?,
}

local function discoveredIn(profile: any, world: number): number
	local n = 0
	for _, relic in Worlds.get(world).relics do
		if (profile.relics[relic.key] or 0) > 0 then
			n += 1
		end
	end
	return n
end

function IndexPanel.totals(profile: any): (number, number)
	local found = 0
	for world = 1, Config.WorldCount do
		found += discoveredIn(profile, world)
	end
	return found, Config.WorldCount * RELICS_PER_WORLD
end

function IndexPanel.new(app: any): Panel.PanelApi
	local panel = Panel.new({
		Parent = app.Gui.panels,
		Title = Strings.get("indexTitle"),
		Icon = utf8.char(0x1F4D6),
		Palette = "Purple",
		Size = Vector2.new(900, 560),
	})
	local body = panel.body
	local selected = 1

	-- Header: total progress bar.
	local progress = Kit.progress({
		Size = UDim2.new(1, -8, 0, 30),
		Position = UDim2.fromOffset(4, 20),
		Colors = { Color.hex("#d99bff"), Color.hex("#8a4fe0") },
		TextSize = 18,
		Parent = body,
	})

	-- World list -----------------------------------------------------------------------------------
	local list = Kit.new("ScrollingFrame", {
		BackgroundColor3 = C.PanelAlt,
		BackgroundTransparency = 0.2,
		Size = UDim2.new(0, 250, 1, -70),
		Position = UDim2.fromOffset(0, 64),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.NavySoft,
		BorderSizePixel = 0,
		Parent = body,
	}) :: ScrollingFrame
	Kit.corner(list, 16)
	Kit.padding(list, 8, 12, 8, 8)
	Kit.list(list, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	type Row = { button: TextButton, label: TextLabel, tally: TextLabel, stroke: UIStroke }
	local rows: { Row } = {}
	local refresh: () -> () = function() end
	for world = 1, Config.WorldCount do
		local data = Worlds.get(world)
		local button = Kit.new("TextButton", {
			Name = "World" .. world,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(1, -4, 0, 46),
			LayoutOrder = world,
			Parent = list,
		}) :: TextButton
		Kit.corner(button, 12)
		Kit.gradient(button, Color.lighten(Color.hex(data.accent[1]), 0.25), Color.hex(data.accent[2]), 90)
		local stroke = Kit.stroke(button, Color.darken(Color.hex(data.accent[2]), 0.5), 2.5)
		local label = Kit.text({
			Text = "",
			TextSize = 16,
			Size = UDim2.new(1, -66, 1, 0),
			Position = UDim2.fromOffset(10, 0),
			XAlign = Enum.TextXAlignment.Left,
			Stroke = 2,
			StrokeColor = Color.darken(Color.hex(data.accent[2]), 0.55),
			Parent = button,
		})
		local tally = Kit.text({
			Text = "",
			TextSize = 15,
			Size = UDim2.fromOffset(58, 46),
			Position = UDim2.new(1, -60, 0, 0),
			Stroke = 2,
			Parent = button,
		})
		button.Activated:Connect(function()
			selected = world
			app.Sfx.play("Click")
			refresh()
		end)
		rows[world] = { button = button, label = label, tally = tally, stroke = stroke }
	end

	-- Relic cards ----------------------------------------------------------------------------------
	local title = Kit.text({
		Text = "",
		TextSize = 26,
		Size = UDim2.new(1, -266, 0, 32),
		Position = UDim2.fromOffset(266, 66),
		XAlign = Enum.TextXAlignment.Left,
		Stroke = 3,
		Parent = body,
	})
	local completeChip = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(120, 30),
		Position = UDim2.new(1, -4, 0, 67),
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		Parent = body,
	})
	Kit.round(completeChip)
	Kit.gradient(completeChip, Theme.Buttons.Gold[1], Theme.Buttons.Gold[2])
	Kit.stroke(completeChip, Theme.Buttons.Gold[3], 2.5)
	local completeLabel =
		Kit.text({ Text = "", TextSize = 17, Size = UDim2.fromScale(1, 1), StrokeColor = Theme.Buttons.Gold[3], Parent = completeChip })

	local grid = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -266, 1, -110),
		Position = UDim2.fromOffset(266, 108),
		Parent = body,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(186, 184),
		CellPadding = UDim2.fromOffset(12, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local lockedNote = Kit.text({
		Text = "",
		TextSize = 22,
		Color = C.Muted,
		Stroke = 0,
		Wrapped = true,
		Size = UDim2.new(1, -266, 0, 60),
		Position = UDim2.new(0, 266, 0.55, 0),
		Visible = false,
		Parent = body,
	})

	local cards: { Card } = {}
	for i = 1, RELICS_PER_WORLD do
		local frame = Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = i, Parent = grid }) :: Frame
		Kit.corner(frame, 16)
		Kit.stroke(frame, C.Outline, 3)
		local view = Viewport.new(frame, UDim2.fromOffset(150, 88), UDim2.new(0.5, 0, 0, 6), Vector2.new(0.5, 0))
		view.setSpin(true)
		local name =
			Kit.text({ Text = "", TextSize = 17, Size = UDim2.new(1, -10, 0, 20), Position = UDim2.fromOffset(5, 96), Stroke = 2, Parent = frame })
		local rarityChip = Kit.new("Frame", {
			BackgroundColor3 = C.Gray,
			Size = UDim2.fromOffset(110, 20),
			Position = UDim2.new(0.5, 0, 0, 120),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = frame,
		})
		Kit.round(rarityChip)
		Kit.stroke(rarityChip, C.Outline, 2)
		local rarity = Kit.text({ Text = "", TextSize = 13, Size = UDim2.fromScale(1, 1), Stroke = 1.6, Parent = rarityChip })
		local worthRow =
			Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 143), Parent = frame })
		Kit.list(worthRow, Enum.FillDirection.Horizontal, 4)
		local coin = Kit.Icons.coin(16, worthRow)
		coin.LayoutOrder = 1
		local worth =
			Kit.text({ Text = "", TextSize = 15, Size = UDim2.new(0, 0, 1, 0), AutoX = true, Stroke = 2, LayoutOrder = 2, Parent = worthRow })
		local count = Kit.text({
			Text = "",
			TextSize = 13,
			Color = C.Muted,
			Stroke = 0,
			Size = UDim2.new(1, -10, 0, 16),
			Position = UDim2.fromOffset(5, 164),
			Parent = frame,
		})
		cards[i] = { frame = frame, view = view, name = name, rarityChip = rarityChip, rarity = rarity, worth = worth, count = count, key = nil }
	end

	local function paintCard(card: Card, relic: any, found: number, world: number)
		local discovered = found > 0
		local rarityColor = Theme.rarityColor(relic.rarity)
		if card.key ~= relic.key then
			card.key = relic.key
			card.view.setModel(Viewport.relic(relic.key))
		end
		-- Undiscovered relics render as flat black silhouettes.
		card.view.frame.Ambient = if discovered then Color3.fromRGB(190, 200, 215) else Color3.new(0, 0, 0)
		card.view.frame.LightColor = if discovered then Color3.fromRGB(255, 250, 240) else Color3.new(0, 0, 0)
		card.view.frame.ImageColor3 = if discovered then Color3.new(1, 1, 1) else Color3.fromRGB(20, 28, 44)
		card.frame.BackgroundColor3 = if discovered then rarityColor:Lerp(Color3.new(1, 1, 1), 0.72) else Color3.fromRGB(196, 206, 220)
		card.name.Text = if discovered then Strings.name(relic.name) else "???"
		local stroke = card.name:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if discovered then rarityColor:Lerp(Color3.new(0, 0, 0), 0.55) else C.Ink
		end
		card.rarityChip.BackgroundColor3 = rarityColor
		card.rarity.Text = Strings.get("rarity." .. Config.Rarities[relic.rarity])
		card.worth.Text = Format.short(Economy.relicValue(world, relic.rarity))
		card.count.Text = if discovered then Strings.get("indexCount", { n = Format.commas(found) }) else Strings.get("indexUndiscovered")
	end

	refresh = function()
		local profile = app.State.profile
		if not profile then
			return
		end
		local found, total = IndexPanel.totals(profile)
		progress.set(found / total, Strings.get("indexProgress", { a = found, b = total }))
		for world, row in rows do
			local data = Worlds.get(world)
			local unlocked = world <= profile.unlocked
			local n = discoveredIn(profile, world)
			row.label.Text = (if unlocked then "" else utf8.char(0x1F512) .. " ") .. world .. ". " .. Strings.name(data.name)
			row.tally.Text = if n == RELICS_PER_WORLD then utf8.char(0x2714) else n .. "/" .. RELICS_PER_WORLD
			row.button.BackgroundTransparency = if unlocked then 0 else 0.45
			row.stroke.Thickness = if world == selected then 4 else 2.5
			row.stroke.Color = if world == selected then Color3.new(1, 1, 1) else Color.darken(Color.hex(data.accent[2]), 0.5)
		end
		local data = Worlds.get(selected)
		title.Text = Strings.get("world", { n = selected }) .. "  ·  " .. Strings.name(data.name)
		local titleStroke = title:FindFirstChildOfClass("UIStroke")
		if titleStroke then
			titleStroke.Color = Color.darken(Color.hex(data.accent[2]), 0.45)
		end
		title.TextColor3 = Color.lighten(Color.hex(data.accent[1]), 0.35)
		local count = discoveredIn(profile, selected)
		completeChip.Visible = count == RELICS_PER_WORLD
		completeLabel.Text = Strings.get("indexComplete")
		local unlocked = selected <= profile.unlocked
		for i, card in cards do
			local relic = data.relics[i]
			card.frame.Visible = relic ~= nil
			if relic then
				paintCard(card, relic, profile.relics[relic.key] or 0, selected)
			end
		end
		lockedNote.Visible = not unlocked and count == 0
		lockedNote.Text = Strings.get("indexLocked")
		grid.Visible = unlocked or count > 0
	end

	panel.onOpen = function()
		selected = app.State.world
		refresh()
	end
	app.State.profileChanged:Connect(function()
		if panel.isOpen then
			refresh()
		end
	end)
	app.State.languageChanged:Connect(function()
		panel.setTitle(Strings.get("indexTitle"))
		refresh()
	end)
	return panel
end

return IndexPanel
