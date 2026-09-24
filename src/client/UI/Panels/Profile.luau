--!strict
-- Your profile: avatar, join date, playtime and lifetime stats on one tab; the relic index (every
-- world's five relics, undiscovered ones as black silhouettes) on the other.

local Players = game:GetService("Players")
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

local ProfilePanel = {}

local C = Theme.C
local RELICS_PER_WORLD = 5

type RelicCard = {
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

function ProfilePanel.totals(profile: any): (number, number)
	local found = 0
	for world = 1, Config.WorldCount do
		found += discoveredIn(profile, world)
	end
	return found, Config.WorldCount * RELICS_PER_WORLD
end

local function worldsCleared(profile: any): number
	local n = 0
	for _, entry in profile.worlds do
		if entry.cleared then
			n += 1
		end
	end
	return n
end

function ProfilePanel.new(app: any): Panel.PanelApi
	local panel = Panel.new({
		Parent = app.Gui.panels,
		Title = Strings.get("profileTitle"),
		Icon = utf8.char(0x1F464),
		Palette = "Purple",
		Size = Vector2.new(900, 560),
	})
	local body = panel.body
	local relicWorld = 1
	local tab = "info" -- "info" | "relics"

	-- Tab bar --------------------------------------------------------------------------------------
	local tabs = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 16), Parent = body })
	Kit.list(tabs, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left)
	local tabButtons: { [string]: Kit.ButtonApi } = {}
	local refresh: () -> ()
	local function selectTab(key: string)
		tab = key
		refresh()
	end
	for order, key in { "info", "relics" } do
		tabButtons[key] = Kit.button({
			Text = "",
			TextSize = 19,
			Palette = "Navy",
			Size = UDim2.fromOffset(180, 44),
			LayoutOrder = order,
			Parent = tabs,
			OnClick = function()
				app.Sfx.play("Click")
				selectTab(key)
			end,
		})
	end

	-- Info tab ---------------------------------------------------------------------------------------
	local info = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -66), Position = UDim2.fromOffset(0, 66), Parent = body })

	local card = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(0, 250, 1, 0),
		Parent = info,
	})
	Kit.corner(card, 18)
	Kit.stroke(card, C.PanelLine, 3)
	Kit.gradient(card, Color3.fromRGB(255, 255, 255), Color3.fromRGB(228, 243, 255))
	local avatar = Kit.new("ImageLabel", {
		BackgroundColor3 = Color3.fromRGB(60, 90, 140),
		Size = UDim2.fromOffset(140, 140),
		Position = UDim2.new(0.5, 0, 0, 24),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = card,
	})
	Kit.round(avatar)
	Kit.stroke(avatar, C.Outline, 3)
	local nameLabel = Kit.text({
		Text = "",
		TextSize = 26,
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.new(0.5, 0, 0, 172),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = card,
	})
	local joinedLabel = Kit.text({
		Text = "",
		TextSize = 16,
		Color = C.Muted,
		Stroke = 0,
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 208),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = card,
	})
	local playtimeChip = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, -30, 0, 44),
		Position = UDim2.new(0.5, 0, 0, 244),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = card,
	})
	Kit.round(playtimeChip)
	local pg = Theme.Buttons.Blue
	Kit.gradient(playtimeChip, pg[1], pg[2])
	Kit.stroke(playtimeChip, pg[3], 2.5)
	local playtimeLabel = Kit.text({ Text = "", TextSize = 17, Size = UDim2.fromScale(1, 1), StrokeColor = pg[3], Parent = playtimeChip })

	-- Stat grid.
	local statsFrame = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -270, 1, 0),
		Position = UDim2.fromOffset(266, 0),
		Parent = info,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(276, 84),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = statsFrame,
	})

	local STAT_DEFS = {
		{ key = "lifetime", label = "profileLifetime", icon = utf8.char(0x1F4B0), palette = "Gold" },
		{ key = "dives", label = "profileDives", icon = utf8.char(0x1F3CA), palette = "Blue" },
		{ key = "relicsFound", label = "profileRelicsFound", icon = utf8.char(0x1F4E6), palette = "Green" },
		{ key = "petsHatched", label = "profilePetsHatched", icon = utf8.char(0x1F95A), palette = "Pink" },
		{ key = "worldsCleared", label = "profileWorldsCleared", icon = utf8.char(0x1F3C6), palette = "Orange" },
		{ key = "blackouts", label = "profileBlackouts", icon = utf8.char(0x1F4A8), palette = "Red" },
	}
	local statLabels: { [string]: TextLabel } = {}
	local statValues: { [string]: TextLabel } = {}
	for order, def in STAT_DEFS do
		local palette = Theme.Buttons[def.palette]
		local tile = Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = order, Parent = statsFrame })
		Kit.corner(tile, 16)
		Kit.stroke(tile, C.PanelLine, 2.5)
		local iconBack = Kit.new("Frame", {
			BackgroundColor3 = palette[2],
			Size = UDim2.fromOffset(56, 56),
			Position = UDim2.fromOffset(12, 14),
			Parent = tile,
		})
		Kit.round(iconBack)
		Kit.stroke(iconBack, palette[3], 2.5)
		Kit.text({ Text = def.icon, TextSize = 28, Size = UDim2.fromScale(1, 1), Stroke = 0, Parent = iconBack })
		statLabels[def.key] = Kit.text({
			Text = "",
			TextSize = 15,
			Color = C.Muted,
			Stroke = 0,
			Size = UDim2.new(1, -84, 0, 20),
			Position = UDim2.fromOffset(78, 14),
			XAlign = Enum.TextXAlignment.Left,
			Parent = tile,
		})
		statValues[def.key] = Kit.text({
			Text = "",
			TextSize = 24,
			Size = UDim2.new(1, -84, 0, 32),
			Position = UDim2.fromOffset(78, 36),
			XAlign = Enum.TextXAlignment.Left,
			Parent = tile,
		})
	end

	-- Relics tab (unchanged relic index) --------------------------------------------------------------
	local relics = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -66), Position = UDim2.fromOffset(0, 66), Parent = body })

	local progress = Kit.progress({
		Size = UDim2.new(1, -8, 0, 30),
		Position = UDim2.fromOffset(4, 0),
		Colors = { Color.hex("#d99bff"), Color.hex("#8a4fe0") },
		TextSize = 18,
		Parent = relics,
	})

	local list = Kit.new("ScrollingFrame", {
		BackgroundColor3 = C.PanelAlt,
		BackgroundTransparency = 0.2,
		Size = UDim2.new(0, 250, 1, -44),
		Position = UDim2.fromOffset(0, 44),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.NavySoft,
		BorderSizePixel = 0,
		Parent = relics,
	}) :: ScrollingFrame
	Kit.corner(list, 16)
	Kit.padding(list, 8, 12, 8, 8)
	Kit.list(list, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	type Row = { button: TextButton, label: TextLabel, tally: TextLabel, stroke: UIStroke }
	local rows: { Row } = {}
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
			relicWorld = world
			app.Sfx.play("Click")
			refresh()
		end)
		rows[world] = { button = button, label = label, tally = tally, stroke = stroke }
	end

	local relicTitle = Kit.text({
		Text = "",
		TextSize = 26,
		Size = UDim2.new(1, -266, 0, 32),
		Position = UDim2.fromOffset(266, 2),
		XAlign = Enum.TextXAlignment.Left,
		Stroke = 3,
		Parent = relics,
	})
	local completeChip = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(120, 30),
		Position = UDim2.new(1, -4, 0, 3),
		AnchorPoint = Vector2.new(1, 0),
		Visible = false,
		Parent = relics,
	})
	Kit.round(completeChip)
	Kit.gradient(completeChip, Theme.Buttons.Gold[1], Theme.Buttons.Gold[2])
	Kit.stroke(completeChip, Theme.Buttons.Gold[3], 2.5)
	local completeLabel =
		Kit.text({ Text = "", TextSize = 17, Size = UDim2.fromScale(1, 1), StrokeColor = Theme.Buttons.Gold[3], Parent = completeChip })

	local grid = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -266, 1, -44),
		Position = UDim2.fromOffset(266, 44),
		Parent = relics,
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
		Position = UDim2.new(0, 266, 0.5, 0),
		Visible = false,
		Parent = relics,
	})

	local cards: { RelicCard } = {}
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

	local function paintCard(card2: RelicCard, relic: any, found: number, world: number)
		local discovered = found > 0
		local rarityColor = Theme.rarityColor(relic.rarity)
		if card2.key ~= relic.key then
			card2.key = relic.key
			card2.view.setModel(Viewport.relic(relic.key))
		end
		card2.view.frame.Ambient = if discovered then Color3.fromRGB(190, 200, 215) else Color3.new(0, 0, 0)
		card2.view.frame.LightColor = if discovered then Color3.fromRGB(255, 250, 240) else Color3.new(0, 0, 0)
		card2.view.frame.ImageColor3 = if discovered then Color3.new(1, 1, 1) else Color3.fromRGB(20, 28, 44)
		card2.frame.BackgroundColor3 = if discovered then rarityColor:Lerp(Color3.new(1, 1, 1), 0.72) else Color3.fromRGB(196, 206, 220)
		card2.name.Text = if discovered then Strings.name(relic.name) else "???"
		local stroke = card2.name:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if discovered then rarityColor:Lerp(Color3.new(0, 0, 0), 0.55) else C.Ink
		end
		card2.rarityChip.BackgroundColor3 = rarityColor
		card2.rarity.Text = Strings.get("rarity." .. Config.Rarities[relic.rarity])
		card2.worth.Text = Format.short(Economy.relicValue(world, relic.rarity))
		card2.count.Text = if discovered then Strings.get("indexCount", { n = Format.commas(found) }) else Strings.get("indexUndiscovered")
	end

	refresh = function()
		local profile = app.State.profile
		panel.setTitle(if tab == "info" then Strings.get("profileTitle") else Strings.get("indexTitle"))
		tabButtons.info.setText(Strings.get("profileTabInfo"))
		tabButtons.relics.setText(Strings.get("profileTabRelics"))
		tabButtons.info.setPalette(if tab == "info" then "Purple" else "Navy")
		tabButtons.relics.setPalette(if tab == "relics" then "Purple" else "Navy")
		info.Visible = tab == "info"
		relics.Visible = tab == "relics"
		if not profile then
			return
		end
		if tab == "info" then
			local player = Players.LocalPlayer
			avatar.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=180&h=180", math.max(1, player.UserId))
			local vip = player:GetAttribute("VIP") == true
			nameLabel.Text = (if vip then utf8.char(0x1F451) .. " " else "") .. player.DisplayName
			joinedLabel.Text = Strings.get("profileJoined", { date = Format.date(profile.created) })
			local h, m = Format.hoursMinutes(profile.stats.playtime)
			playtimeLabel.Text = Strings.get("profilePlaytime", { h = h, m = m })
			local found = ProfilePanel.totals(profile)
			local values = {
				lifetime = Format.commas(profile.lifetime),
				dives = Format.commas(profile.stats.dives),
				relicsFound = found .. "/" .. Config.WorldCount * RELICS_PER_WORLD,
				petsHatched = Format.commas(profile.stats.hatched),
				worldsCleared = worldsCleared(profile) .. "/" .. Config.WorldCount,
				blackouts = Format.commas(profile.stats.blackouts),
			}
			for _, def in STAT_DEFS do
				statLabels[def.key].Text = Strings.get(def.label)
				statValues[def.key].Text = values[def.key]
			end
		else
			local found, total = ProfilePanel.totals(profile)
			progress.set(found / total, Strings.get("indexProgress", { a = found, b = total }))
			for world, row in rows do
				local data = Worlds.get(world)
				local unlocked = world <= profile.unlocked
				local n = discoveredIn(profile, world)
				row.label.Text = (if unlocked then "" else utf8.char(0x1F512) .. " ") .. world .. ". " .. Strings.name(data.name)
				row.tally.Text = if n == RELICS_PER_WORLD then utf8.char(0x2714) else n .. "/" .. RELICS_PER_WORLD
				row.button.BackgroundTransparency = if unlocked then 0 else 0.45
				row.stroke.Thickness = if world == relicWorld then 4 else 2.5
				row.stroke.Color = if world == relicWorld then Color3.new(1, 1, 1) else Color.darken(Color.hex(data.accent[2]), 0.5)
			end
			local data = Worlds.get(relicWorld)
			relicTitle.Text = Strings.get("world", { n = relicWorld }) .. "  ·  " .. Strings.name(data.name)
			local titleStroke = relicTitle:FindFirstChildOfClass("UIStroke")
			if titleStroke then
				titleStroke.Color = Color.darken(Color.hex(data.accent[2]), 0.45)
			end
			relicTitle.TextColor3 = Color.lighten(Color.hex(data.accent[1]), 0.35)
			local count = discoveredIn(profile, relicWorld)
			completeChip.Visible = count == RELICS_PER_WORLD
			completeLabel.Text = Strings.get("indexComplete")
			local unlocked = relicWorld <= profile.unlocked
			for i, card2 in cards do
				local relic = data.relics[i]
				card2.frame.Visible = relic ~= nil
				if relic then
					paintCard(card2, relic, profile.relics[relic.key] or 0, relicWorld)
				end
			end
			lockedNote.Visible = not unlocked and count == 0
			lockedNote.Text = Strings.get("indexLocked")
			grid.Visible = unlocked or count > 0
		end
	end

	panel.onOpen = function()
		relicWorld = app.State.world
		refresh()
	end
	app.State.profileChanged:Connect(function()
		if panel.isOpen then
			refresh()
		end
	end)
	app.State.languageChanged:Connect(refresh)
	return panel
end

return ProfilePanel
