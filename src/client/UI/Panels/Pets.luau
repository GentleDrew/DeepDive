--!strict
-- Pet inventory: 3D pet cards by rarity, equip/lock/delete, equip best and total boost.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)
local Mutations = require(Shared.Models.Mutations)

local Anim = require(script.Parent.Parent.Anim)
local Kit = require(script.Parent.Parent.Kit)
local Panel = require(script.Parent.Parent.Panel)
local Theme = require(script.Parent.Parent.Theme)
local Viewport = require(script.Parent.Parent.Viewport)

local PetsPanel = {}

local C = Theme.C

function PetsPanel.boostText(key: string, mutations: { string }?): string
	return Format.multiplier(1 + Economy.petPower(key, mutations))
end

local LUCKY_PRODUCT = nil :: any
for _, product in Config.Products do
	if product.enchants > 0 then
		LUCKY_PRODUCT = product
	end
end

function PetsPanel.new(app: any): Panel.PanelApi
	local panel = Panel.new({
		Parent = app.Gui.panels,
		Title = Strings.get("petsTitle"),
		Icon = utf8.char(0x1F43E),
		Palette = "Pink",
		Size = Vector2.new(940, 620),
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

	-- Drag a card onto the bin to delete it (locked pets are refused by the server).
	local trash = Kit.new("Frame", {
		Name = "TrashZone",
		BackgroundColor3 = C.Red,
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(260, 70),
		Position = UDim2.new(0.5, -165, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		ZIndex = 30,
		Parent = body,
	}) :: Frame
	Kit.corner(trash, 18)
	local trashStroke = Kit.stroke(trash, C.White, 3)
	local trashLabel = Kit.text({
		Text = "",
		TextSize = 22,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 31,
		StrokeColor = C.RedDark,
		Parent = trash,
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
	-- Vertical budget (detail is ~468 tall): preview 4-136, name, rarity, origin, boost, mutation
	-- chips up to ~290, then the action grid (3 rows, 148) pinned to the bottom.
	local bigView = Viewport.new(detail, UDim2.fromOffset(200, 132), UDim2.new(0.5, 0, 0, 4), Vector2.new(0.5, 0))
	bigView.setSpin(true)
	local detailName = Kit.text({
		Text = "",
		TextSize = 28,
		Size = UDim2.new(1, -16, 0, 32),
		Position = UDim2.new(0.5, 0, 0, 138),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = detail,
	})
	local rarityChip = Kit.new("Frame", {
		BackgroundColor3 = C.Gray,
		Size = UDim2.fromOffset(150, 28),
		Position = UDim2.new(0.5, 0, 0, 174),
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
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.new(0.5, 0, 0, 206),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = detail,
	})
	local boostDetail = Kit.text({
		Text = "",
		TextSize = 26,
		Color = C.Gold,
		StrokeColor = C.GoldDark,
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.new(0.5, 0, 0, 228),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = detail,
	})
	-- Mutation chips (Gold x2, Lava x5, ...) or a hint when the pet has none.
	local mutationRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.new(0.5, 0, 0, 264),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = detail,
	})
	Kit.list(mutationRow, Enum.FillDirection.Horizontal, 4)
	local mutationHint = Kit.text({
		Text = "",
		TextSize = 15,
		Color = C.Muted,
		Stroke = 0,
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = 99,
		Parent = mutationRow,
	})
	local mutationChips: { Frame } = {}
	local function setMutations(list: { string }?)
		for _, chip in mutationChips do
			chip:Destroy()
		end
		table.clear(mutationChips)
		mutationHint.Visible = not list or #list == 0
		mutationHint.Text = Strings.get("noMutations")
		if not list then
			return
		end
		for order, key in list do
			local color = Mutations.color(key)
			local chip = Kit.new("Frame", {
				BackgroundColor3 = color,
				Size = UDim2.fromOffset(0, 24),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = order,
				Parent = mutationRow,
			}) :: Frame
			Kit.round(chip)
			Kit.stroke(chip, color:Lerp(Color3.new(0, 0, 0), 0.55), 2)
			Kit.padding(chip, 0, 7, 0, 7)
			Kit.text({
				Text = Strings.get("mutation." .. key) .. " x" .. Economy.Mutations[key].mult,
				TextSize = 13,
				AutoX = true,
				Size = UDim2.new(0, 0, 1, 0),
				StrokeColor = color:Lerp(Color3.new(0, 0, 0), 0.6),
				Parent = chip,
			})
			table.insert(mutationChips, chip)
		end
	end
	local actions = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 148),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = detail,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(136, 44),
		CellPadding = UDim2.fromOffset(10, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = actions,
	})

	local selected: string? = nil
	local deleteArmed = false
	local cards: { [string]: { frame: TextButton, view: Viewport.ViewApi, key: string, look: string } } = {}

	local equipButton: Kit.ButtonApi
	local lockButton: Kit.ButtonApi
	local deleteButton: Kit.ButtonApi
	local enchantButton: Kit.ButtonApi
	local luckyButton: Kit.ButtonApi
	local enchantCoin: Frame

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
		boostDetail.Text = Strings.get("boost", { x = PetsPanel.boostText(pet.s, pet.m) })
		setMutations(pet.m)
		local cost = Economy.mutateCost(pet.s, pet.m)
		if cost then
			enchantButton.setText(Format.short(cost))
			enchantButton.setPalette(if profile.coins >= cost then "Purple" else "Gray")
			enchantButton.setEnabled(true)
			enchantCoin.Visible = true
			luckyButton.setText(utf8.char(0x2728) .. " " .. Strings.get("lucky", { n = profile.enchants }))
			luckyButton.setEnabled(true)
		else
			enchantButton.setText(Strings.get("max"))
			enchantButton.setPalette("Gold")
			enchantButton.setEnabled(false)
			enchantCoin.Visible = false
			luckyButton.setText(Strings.get("max"))
			luckyButton.setEnabled(false)
		end
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
	local function enchant(lucky: boolean)
		local profile = app.State.profile
		if not profile or not selected then
			return
		end
		if lucky and profile.enchants < 1 then
			if LUCKY_PRODUCT and LUCKY_PRODUCT.id > 0 then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, LUCKY_PRODUCT.id)
			else
				app.Toasts.show(Strings.get("comingSoon"), "info")
			end
			return
		end
		local result = app.Net.invoke("Mutate", { id = selected, lucky = lucky })
		if not result.ok then
			app.Sfx.play("Error")
			Anim.shake(detail, 6)
			if result.err then
				app.Toasts.show(Strings.get(result.err), "bad")
			end
			return
		end
		local key = result.data.mutation :: string
		local def = Economy.Mutations[key]
		local color = Mutations.color(key)
		app.Sfx.play(if def.mult >= 5 then "Legendary" elseif def.mult >= 4 then "Reveal" else "Upgrade")
		app.Effects.flash(color, if def.mult >= 5 then 0.55 else 0.35, 0.5)
		if def.mult >= 5 then
			app.Effects.confetti(40)
		end
		Anim.pop(detail, 0.08)
		app.Toasts.show(Strings.get("mutated", { name = Strings.get("mutation." .. key), x = def.mult }), "gold", utf8.char(0x2728))
	end
	enchantButton = Kit.button({
		Text = "",
		TextSize = 19,
		Palette = "Purple",
		LayoutOrder = 3,
		Parent = actions,
		OnClick = function()
			enchant(false)
		end,
	})
	enchantCoin = Kit.Icons.coin(22, enchantButton.button:FindFirstChild("Content") :: Instance)
	enchantCoin.LayoutOrder = 0
	luckyButton = Kit.button({
		Text = "",
		TextSize = 17,
		Palette = "Pink",
		LayoutOrder = 4,
		Parent = actions,
		OnClick = function()
			enchant(true)
		end,
	})
	deleteButton = Kit.button({
		Text = "",
		TextSize = 18,
		Palette = "Red",
		LayoutOrder = 5,
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
			bigView.setModel(Viewport.pet(pet.s, pet.m))
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

	local dragging: { id: string, ghost: GuiObject, input: InputObject }? = nil
	local justDragged = false

	local function overTrash(position: Vector3): boolean
		local at, size = trash.AbsolutePosition, trash.AbsoluteSize
		return position.X >= at.X and position.X <= at.X + size.X and position.Y >= at.Y and position.Y <= at.Y + size.Y
	end

	local function moveGhost(position: Vector3)
		local current = dragging
		if not current then
			return
		end
		local canvas = app.Gui.panels
		current.ghost.Position =
			UDim2.fromOffset((position.X - canvas.AbsolutePosition.X) / app.Gui.scale, (position.Y - canvas.AbsolutePosition.Y) / app.Gui.scale)
		local hot = overTrash(position)
		trash.BackgroundColor3 = if hot then C.RedDark else C.Red
		trashStroke.Thickness = if hot then 5 else 3
	end

	local function startDrag(id: string, frame: TextButton, input: InputObject)
		if dragging then
			return
		end
		local ghost = frame:Clone() :: GuiObject
		ghost.Name = "DragGhost"
		ghost.Size = UDim2.fromOffset(92, 110)
		ghost.AnchorPoint = Vector2.new(0.5, 0.5)
		ghost.ZIndex = 60
		ghost.Parent = app.Gui.panels
		dragging = { id = id, ghost = ghost, input = input }
		grid.ScrollingEnabled = false
		trash.Visible = true
		trashLabel.Text = utf8.char(0x1F5D1) .. "  " .. Strings.get("dropToDelete")
		app.Sfx.play("Click")
		moveGhost(input.Position)
	end

	local function endDrag(position: Vector3?)
		local current = dragging
		if not current then
			return
		end
		dragging = nil
		current.ghost:Destroy()
		grid.ScrollingEnabled = true
		trash.Visible = false
		justDragged = true
		task.delay(0.1, function()
			justDragged = false
		end)
		if position and overTrash(position) then
			local profile = app.State.profile
			local pet = profile and profile.pets[current.id]
			if pet and pet.l then
				app.Sfx.play("Error")
				app.Toasts.show(Strings.get("petLocked"), "bad", utf8.char(0x1F512))
				return
			end
			local result = app.Net.invoke("DeletePet", { id = current.id })
			if result.ok then
				app.Sfx.play("Sell")
				app.Toasts.show(Strings.get("petDeleted"), "info", utf8.char(0x1F5D1))
				if selected == current.id then
					selected = nil
				end
			else
				app.Sfx.play("Error")
				app.Toasts.show(Strings.get(result.err or "err.generic"), "bad")
			end
		end
	end

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local current = dragging
		if current and (input == current.input or input.UserInputType == Enum.UserInputType.MouseMovement) then
			moveGhost(input.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local current = dragging
		if
			current
			and (input == current.input or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
		then
			endDrag(input.Position)
		end
	end)

	-- Mouse: drag once the pointer moves a little. Touch: press and hold (so swipes still scroll).
	local function hookDrag(id: string, frame: TextButton)
		frame.InputBegan:Connect(function(input: InputObject)
			local mouse = input.UserInputType == Enum.UserInputType.MouseButton1
			if not mouse and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local origin = input.Position
			local released = false
			local moved: RBXScriptConnection? = nil
			local ended: RBXScriptConnection? = nil
			local function cleanup()
				released = true
				if moved then
					moved:Disconnect()
				end
				if ended then
					ended:Disconnect()
				end
			end
			ended = UserInputService.InputEnded:Connect(function(other: InputObject)
				if other == input or (mouse and other.UserInputType == Enum.UserInputType.MouseButton1) then
					cleanup()
				end
			end)
			if mouse then
				moved = UserInputService.InputChanged:Connect(function(other: InputObject)
					if other.UserInputType == Enum.UserInputType.MouseMovement and (other.Position - origin).Magnitude > 10 then
						cleanup()
						startDrag(id, frame, input)
					end
				end)
			else
				task.delay(0.35, function()
					if not released and (input.Position - origin).Magnitude < 14 then
						cleanup()
						startDrag(id, frame, input)
					end
				end)
			end
		end)
	end

	local function buildCard(id: string, key: string, mutations: { string }?, order: number): TextButton
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
		view.setModel(Viewport.pet(key, mutations))
		local top = Mutations.top(mutations)
		if top then
			local tag = Kit.new("Frame", {
				Name = "Mutation",
				BackgroundColor3 = Mutations.color(top),
				Size = UDim2.fromOffset(0, 20),
				AutomaticSize = Enum.AutomaticSize.X,
				Position = UDim2.new(0.5, 0, 1, -48),
				AnchorPoint = Vector2.new(0.5, 0),
				ZIndex = 4,
				Parent = frame,
			})
			Kit.round(tag)
			Kit.padding(tag, 0, 6, 0, 6)
			Kit.stroke(tag, Mutations.color(top):Lerp(Color3.new(0, 0, 0), 0.55), 2)
			Kit.text({
				Text = Strings.get("mutation." .. top) .. (if mutations and #mutations > 1 then " +" .. (#mutations - 1) else ""),
				TextSize = 12,
				AutoX = true,
				Size = UDim2.new(0, 0, 1, 0),
				ZIndex = 5,
				Parent = tag,
			})
		end
		Kit.text({
			Name = "Boost",
			Text = PetsPanel.boostText(key, mutations),
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
			if justDragged then
				return
			end
			app.Sfx.play("Click")
			select(id)
			Anim.pop(frame, 0.1)
		end)
		hookDrag(id, frame)
		cards[id] = { frame = frame, view = view, key = key, look = key .. table.concat(mutations or {}, ",") }
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
			local pa, pb = profile.pets[a], profile.pets[b]
			local ba, bb = Economy.petPower(pa.s, pa.m), Economy.petPower(pb.s, pb.m)
			if ba ~= bb then
				return ba > bb
			end
			return a < b
		end)
		local keep = {}
		local rebuiltSelected = false
		for order, id in ids do
			keep[id] = true
			local card = cards[id]
			local pet = profile.pets[id]
			local look = pet.s .. table.concat(pet.m or {}, ",")
			if not card or card.look ~= look then
				if card then
					card.frame:Destroy()
				end
				buildCard(id, pet.s, pet.m, order)
				card = cards[id]
				rebuiltSelected = rebuiltSelected or id == selected
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
		elseif rebuiltSelected then
			select(selected)
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
