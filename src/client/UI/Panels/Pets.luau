--!strict
-- Pet inventory: 3D pet cards by rarity, equip/lock/delete, equip best and total boost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)

local Anim = require(script.Parent.Parent.Anim)
local Kit = require(script.Parent.Parent.Kit)
local Panel = require(script.Parent.Parent.Panel)
local Theme = require(script.Parent.Parent.Theme)
local Viewport = require(script.Parent.Parent.Viewport)

local PetsPanel = {}

local C = Theme.C

function PetsPanel.boostText(key: string): string
	return Format.multiplier(1 + Economy.petBoost(key))
end

function PetsPanel.new(app: any): Panel.PanelApi
	local panel = Panel.new({
		Parent = app.Gui.panels,
		Title = Strings.get("petsTitle"),
		Icon = utf8.char(0x1F43E),
		Palette = "Pink",
		Size = Vector2.new(900, 560),
	})
	local body = panel.body

	-- Top bar ------------------------------------------------------------------------------------
	local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), Position = UDim2.fromOffset(0, 20), Parent = body })
	Kit.list(top, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left)
	local function chip(order: number, palette: string, width: number): TextLabel
		local frame =
			Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromOffset(width, 44), LayoutOrder = order, Parent = top })
		Kit.round(frame)
		local p = Theme.Buttons[palette]
		Kit.gradient(frame, p[1], p[2])
		Kit.stroke(frame, p[3], 3)
		return Kit.text({ Text = "", TextSize = 20, Size = UDim2.fromScale(1, 1), StrokeColor = p[3], Parent = frame })
	end
	local equippedLabel = chip(1, "Green", 170)
	local boostLabel = chip(2, "Pink", 220)
	local countLabel = chip(3, "Navy", 150)
	local equipBest = Kit.button({
		Text = "",
		TextSize = 20,
		Palette = "Gold",
		Size = UDim2.fromOffset(170, 44),
		LayoutOrder = 4,
		Parent = top,
		OnClick = function()
			local result = app.Net.invoke("EquipBest")
			app.Sfx.play(if result.ok then "Upgrade" else "Error")
		end,
	})

	-- Grid ---------------------------------------------------------------------------------------
	local grid = Kit.new("ScrollingFrame", {
		BackgroundColor3 = C.PanelAlt,
		BackgroundTransparency = 0.2,
		Size = UDim2.new(1, -330, 1, -86),
		Position = UDim2.fromOffset(0, 80),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = C.NavySoft,
		BorderSizePixel = 0,
		Parent = body,
	}) :: ScrollingFrame
	Kit.corner(grid, 16)
	Kit.padding(grid, 10, 14, 10, 10)
	Kit.new(
		"UIGridLayout",
		{ CellSize = UDim2.fromOffset(104, 124), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid }
	)
	local empty = Kit.text({
		Text = "",
		TextSize = 22,
		Color = C.Muted,
		Stroke = 0,
		Wrapped = true,
		Size = UDim2.new(1, -330, 0, 80),
		Position = UDim2.fromOffset(0, 220),
		Parent = body,
	})

	-- Detail -------------------------------------------------------------------------------------
	local detail = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(0, 310, 1, -86),
		Position = UDim2.new(1, 0, 0, 80),
		AnchorPoint = Vector2.new(1, 0),
		Parent = body,
	})
	Kit.corner(detail, 18)
	Kit.stroke(detail, C.PanelLine, 3)
	local detailGradient = Kit.gradient(detail, Color3.fromRGB(255, 255, 255), Color3.fromRGB(220, 240, 255))
	local bigView = Viewport.new(detail, UDim2.fromOffset(220, 170), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
	bigView.setSpin(true)
	local detailName = Kit.text({
		Text = "",
		TextSize = 28,
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.new(0.5, 0, 0, 180),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = detail,
	})
	local rarityChip = Kit.new("Frame", {
		BackgroundColor3 = C.Gray,
		Size = UDim2.fromOffset(150, 30),
		Position = UDim2.new(0.5, 0, 0, 218),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = detail,
	})
	Kit.round(rarityChip)
	Kit.stroke(rarityChip, C.Outline, 2)
	local rarityLabel = Kit.text({ Text = "", TextSize = 18, Size = UDim2.fromScale(1, 1), Parent = rarityChip })
	local originLabel = Kit.text({
		Text = "",
		TextSize = 16,
		Color = C.Muted,
		Stroke = 0,
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 254),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = detail,
	})
	local boostDetail = Kit.text({
		Text = "",
		TextSize = 26,
		Color = C.Gold,
		StrokeColor = C.GoldDark,
		Size = UDim2.new(1, -16, 0, 32),
		Position = UDim2.new(0.5, 0, 0, 280),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = detail,
	})
	local actions = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 110),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = detail,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(136, 48),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = actions,
	})

	local selected: string? = nil
	local deleteArmed = false
	local cards: { [string]: { frame: TextButton, view: Viewport.ViewApi, key: string } } = {}

	local equipButton: Kit.ButtonApi
	local lockButton: Kit.ButtonApi
	local deleteButton: Kit.ButtonApi

	local function refreshDetail()
		local profile = app.State.profile
		local pet = profile and selected and profile.pets[selected]
		detail.Visible = pet ~= nil
		if not profile or not pet or not selected then
			return
		end
		local data = Worlds.pets[pet.s]
		if not data then
			return
		end
		local rarity = Config.Rarities[data.rarity]
		local color = Theme.Rarity[rarity]
		detailName.Text = Strings.name(data.name)
		local stroke = detailName:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color:Lerp(Color3.new(0, 0, 0), 0.55)
		end
		rarityChip.BackgroundColor3 = color
		rarityLabel.Text = Strings.get("rarity." .. rarity)
		originLabel.Text = Strings.get("world", { n = data.world }) .. "  -  " .. Strings.name(Worlds.get(data.world).egg.name)
		boostDetail.Text = Strings.get("boost", { x = PetsPanel.boostText(pet.s) })
		detailGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), color:Lerp(Color3.new(1, 1, 1), 0.7))
		local equipped = table.find(profile.equipped, selected) ~= nil
		equipButton.setText(Strings.get(if equipped then "unequip" else "equip"))
		equipButton.setPalette(if equipped then "Gray" else "Green")
		lockButton.setText(Strings.get(if pet.l then "unlock" else "lock"))
		deleteButton.setText(Strings.get(if deleteArmed then "deleteConfirm" else "delete"))
		deleteButton.setEnabled(not pet.l)
		deleteButton.setPalette(if pet.l then "Gray" else "Red")
	end

	equipButton = Kit.button({
		Text = "",
		TextSize = 20,
		Palette = "Green",
		LayoutOrder = 1,
		Parent = actions,
		OnClick = function()
			local profile = app.State.profile
			if not profile or not selected then
				return
			end
			local equipped = table.find(profile.equipped, selected) ~= nil
			local result = app.Net.invoke("Equip", { id = selected, on = not equipped })
			app.Sfx.play(if result.ok then "Upgrade" else "Error")
		end,
	})
	lockButton = Kit.button({
		Text = "",
		TextSize = 20,
		Palette = "Navy",
		LayoutOrder = 2,
		Parent = actions,
		OnClick = function()
			local profile = app.State.profile
			local pet = profile and selected and profile.pets[selected]
			if pet and selected then
				app.Net.invoke("SetLock", { id = selected, locked = not pet.l })
			end
		end,
	})
	deleteButton = Kit.button({
		Text = "",
		TextSize = 18,
		Palette = "Red",
		LayoutOrder = 3,
		Parent = actions,
		OnClick = function()
			if not selected then
				return
			end
			if not deleteArmed then
				deleteArmed = true
				refreshDetail()
				task.delay(2.5, function()
					deleteArmed = false
					refreshDetail()
				end)
				return
			end
			deleteArmed = false
			local result = app.Net.invoke("DeletePet", { id = selected })
			if result.ok then
				selected = nil
			end
		end,
	})

	local function select(id: string?)
		selected = id
		deleteArmed = false
		local profile = app.State.profile
		local pet = profile and id and profile.pets[id]
		if pet then
			bigView.setModel(Viewport.pet(pet.s))
		else
			bigView.setModel(nil)
		end
		for cardId, card in cards do
			local border = card.frame:FindFirstChild("Border") :: UIStroke?
			if border then
				local isSelected = cardId == id
				border.Color = if isSelected then C.White else (card.frame:GetAttribute("BorderColor") :: Color3? or C.Outline)
				border.Thickness = if isSelected then 5 else 3
			end
		end
		refreshDetail()
	end

	local function buildCard(id: string, key: string, order: number): TextButton
		local data = Worlds.pets[key]
		local rarity = Config.Rarities[data.rarity]
		local color = Theme.Rarity[rarity]
		local frame = Kit.new(
			"TextButton",
			{ Name = id, Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = order, Parent = grid }
		) :: TextButton
		Kit.corner(frame, 16)
		Kit.gradient(frame, color:Lerp(Color3.new(1, 1, 1), 0.55), color, 90)
		-- One UIStroke per object: selection recolours and thickens the border.
		local border = Kit.stroke(frame, color:Lerp(Color3.new(0, 0, 0), 0.5), 3)
		border.Name = "Border"
		frame:SetAttribute("BorderColor", border.Color)
		local view = Viewport.new(frame, UDim2.fromOffset(92, 86), UDim2.new(0.5, 0, 0, 4), Vector2.new(0.5, 0))
		view.setModel(Viewport.pet(key))
		Kit.text({
			Name = "Boost",
			Text = PetsPanel.boostText(key),
			TextSize = 18,
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.new(0, 0, 1, -28),
			StrokeColor = color:Lerp(Color3.new(0, 0, 0), 0.6),
			Parent = frame,
		})
		local equipped = Kit.new("Frame", {
			Name = "Equipped",
			BackgroundColor3 = C.Green,
			Size = UDim2.fromOffset(28, 28),
			Position = UDim2.new(1, -4, 0, 4),
			AnchorPoint = Vector2.new(1, 0),
			ZIndex = 4,
			Visible = false,
			Parent = frame,
		})
		Kit.round(equipped)
		Kit.stroke(equipped, C.GreenDark, 2)
		Kit.text({ Text = utf8.char(0x2714), TextSize = 16, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = equipped })
		Kit.text({
			Name = "Lock",
			Text = utf8.char(0x1F512),
			TextSize = 18,
			Size = UDim2.fromOffset(24, 24),
			Position = UDim2.fromOffset(4, 4),
			Stroke = 0,
			ZIndex = 4,
			Visible = false,
			Parent = frame,
		})
		frame.MouseEnter:Connect(function()
			view.setSpin(true)
		end)
		frame.MouseLeave:Connect(function()
			view.setSpin(false)
		end)
		frame.Activated:Connect(function()
			app.Sfx.play("Click")
			select(id)
			Anim.pop(frame, 0.1)
		end)
		cards[id] = { frame = frame, view = view, key = key }
		return frame
	end

	local function refresh()
		local profile = app.State.profile
		if not profile then
			return
		end
		panel.setTitle(Strings.get("petsTitle"))
		equipBest.setText(Strings.get("equipBest"))
		local cap = app.State.equipCap()
		equippedLabel.Text = Strings.get("equipped", { a = #profile.equipped, b = cap })
		boostLabel.Text = Strings.get("totalBoost", { x = Format.multiplier(app.State.multiplier()) })
		local count = 0
		for _ in profile.pets do
			count += 1
		end
		countLabel.Text = Strings.get("inventory", { a = count, b = Config.PetInventoryCap })
		empty.Text = if count == 0 then Strings.get("noPets") else ""

		local ids = {}
		for id in profile.pets do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, b)
			local ea, eb = table.find(profile.equipped, a) ~= nil, table.find(profile.equipped, b) ~= nil
			if ea ~= eb then
				return ea
			end
			local ba, bb = Economy.petBoost(profile.pets[a].s), Economy.petBoost(profile.pets[b].s)
			if ba ~= bb then
				return ba > bb
			end
			return a < b
		end)
		local keep = {}
		for order, id in ids do
			keep[id] = true
			local card = cards[id]
			if not card or card.key ~= profile.pets[id].s then
				if card then
					card.frame:Destroy()
				end
				buildCard(id, profile.pets[id].s, order)
				card = cards[id]
			end
			card.frame.LayoutOrder = order
			local equippedBadge = card.frame:FindFirstChild("Equipped") :: Frame?
			if equippedBadge then
				equippedBadge.Visible = table.find(profile.equipped, id) ~= nil
			end
			local lockBadge = card.frame:FindFirstChild("Lock") :: TextLabel?
			if lockBadge then
				lockBadge.Visible = profile.pets[id].l == true
			end
		end
		for id, card in cards do
			if not keep[id] then
				card.frame:Destroy()
				cards[id] = nil
			end
		end
		if selected and not profile.pets[selected] then
			selected = nil
		end
		if not selected and ids[1] then
			select(ids[1])
		else
			refreshDetail()
		end
	end

	panel.onOpen = function()
		app.Sfx.play("Open")
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

return PetsPanel
