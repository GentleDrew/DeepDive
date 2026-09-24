--!strict
-- Gear shop: four slots (oxygen tank, treasure bag, flippers, magnet), each with two pieces per
-- world. Buying a piece equips it when it beats the one you wear, and it shows on your avatar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Gear = require(Shared.Data.Gear)
local Strings = require(Shared.Strings)

local Anim = require(script.Parent.Parent.Anim)
local Kit = require(script.Parent.Parent.Kit)
local Panel = require(script.Parent.Parent.Panel)
local Theme = require(script.Parent.Parent.Theme)
local Viewport = require(script.Parent.Parent.Viewport)

local GearPanel = {}

local C = Theme.C

local SLOT_ICON = {
	tank = utf8.char(0x1F4A8),
	pack = utf8.char(0x1F392),
	fins = utf8.char(0x1F9BF),
	magnet = utf8.char(0x1F9F2),
}
local SLOT_PALETTE = { tank = "Cyan", pack = "Orange", fins = "Green", magnet = "Red" }

function GearPanel.statText(slot: string, value: number): string
	local shown = if slot == "fins" or slot == "magnet" then string.format("%.1f", value) else tostring(math.floor(value))
	return Strings.get("upgrade." .. slot .. ".value", { n = shown })
end

function GearPanel.itemName(item: Gear.Item): string
	local name = Strings.get("gear." .. item.slot, { theme = Strings.name(item.theme) })
	return if item.pro then Strings.get("gearPro", { name = name }) else name
end

type Card = {
	frame: Frame,
	gradient: UIGradient,
	border: UIStroke,
	view: Viewport.ViewApi,
	name: TextLabel,
	stat: TextLabel,
	pro: Frame,
	worldTag: TextLabel,
	button: Kit.ButtonApi,
	coin: Frame,
	key: string,
}

function GearPanel.new(app: any): Panel.PanelApi
	local panel = Panel.new({
		Parent = app.Gui.panels,
		Title = Strings.get("menu.upgrades"),
		Icon = utf8.char(0x1F93F),
		Palette = "Orange",
		Size = Vector2.new(920, 580),
	})
	local body = panel.body
	local slot = "tank"

	-- Slot tabs ------------------------------------------------------------------------------------
	local tabs = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 62), Position = UDim2.fromOffset(0, 20), Parent = body })
	Kit.list(tabs, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
	local tabButtons: { [string]: Kit.ButtonApi } = {}

	-- Current gear strip --------------------------------------------------------------------------
	local strip = Kit.new("Frame", {
		BackgroundColor3 = C.Navy,
		BackgroundTransparency = 0.1,
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 90),
		Parent = body,
	})
	Kit.round(strip)
	local stripText = Kit.text({ Text = "", TextSize = 18, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), Parent = strip })

	-- Grid ----------------------------------------------------------------------------------------
	local grid = Kit.new("ScrollingFrame", {
		BackgroundColor3 = C.PanelAlt,
		BackgroundTransparency = 0.2,
		Size = UDim2.new(1, 0, 1, -140),
		Position = UDim2.fromOffset(0, 134),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = C.NavySoft,
		BorderSizePixel = 0,
		Parent = body,
	}) :: ScrollingFrame
	Kit.corner(grid, 16)
	Kit.padding(grid, 10, 16, 10, 10)
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(154, 206),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})

	local cards: { Card } = {}
	local refresh: () -> ()

	local function onCardClick(card: Card)
		local profile = app.State.profile
		local item = Gear.get(card.key)
		if not profile or not item then
			return
		end
		if profile.gear.owned[item.key] then
			if profile.gear.equip[item.slot] == item.key then
				return
			end
			local result = app.Net.invoke("EquipGear", { key = item.key })
			app.Sfx.play(if result.ok then "Upgrade" else "Error")
			if result.ok then
				Anim.pop(card.frame, 0.06)
			end
			return
		end
		local result = app.Net.invoke("BuyGear", { key = item.key })
		if result.ok then
			app.Sfx.play("Upgrade")
			Anim.pop(card.frame, 0.08)
			app.Toasts.show(Strings.get("gearBought", { name = GearPanel.itemName(item) }), "good", SLOT_ICON[item.slot])
		else
			app.Sfx.play("Error")
			Anim.shake(card.frame, 6)
			if result.err then
				app.Toasts.show(Strings.get(result.err), "bad")
			end
		end
	end

	for index = 1, Gear.Tiers do
		local frame = Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = index, Parent = grid }) :: Frame
		Kit.corner(frame, 16)
		local gradient = Kit.gradient(frame, Color3.new(1, 1, 1), Color3.new(1, 1, 1), 90)
		local border = Kit.stroke(frame, C.Outline, 3)
		local view = Viewport.new(frame, UDim2.fromOffset(120, 84), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
		local pro = Kit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(46, 22),
			Position = UDim2.fromOffset(6, 6),
			ZIndex = 3,
			Parent = frame,
		}) :: Frame
		Kit.round(pro)
		Kit.gradient(pro, Theme.Buttons.Gold[1], Theme.Buttons.Gold[2])
		Kit.stroke(pro, Theme.Buttons.Gold[3], 2)
		Kit.text({ Text = "PRO", TextSize = 14, Size = UDim2.fromScale(1, 1), StrokeColor = Theme.Buttons.Gold[3], ZIndex = 4, Parent = pro })
		local worldTag = Kit.text({
			Text = "",
			TextSize = 14,
			Size = UDim2.fromOffset(44, 20),
			Position = UDim2.new(1, -6, 0, 6),
			AnchorPoint = Vector2.new(1, 0),
			XAlign = Enum.TextXAlignment.Right,
			ZIndex = 3,
			Parent = frame,
		})
		local name = Kit.text({
			Text = "",
			TextSize = 16,
			Wrapped = true,
			Size = UDim2.new(1, -12, 0, 38),
			Position = UDim2.new(0.5, 0, 0, 92),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = frame,
		})
		local stat = Kit.text({
			Text = "",
			TextSize = 15,
			Color = C.Ink,
			Stroke = 0,
			Size = UDim2.new(1, -12, 0, 20),
			Position = UDim2.new(0.5, 0, 0, 130),
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = frame,
		})
		local card: Card
		local button = Kit.button({
			Text = "",
			TextSize = 17,
			Palette = "Green",
			Size = UDim2.new(1, -16, 0, 42),
			Position = UDim2.new(0.5, 0, 1, -8),
			AnchorPoint = Vector2.new(0.5, 1),
			Parent = frame,
			OnClick = function()
				onCardClick(card)
			end,
		})
		local coin = Kit.Icons.coin(22, button.button:FindFirstChild("Content") :: Instance)
		coin.LayoutOrder = 0
		card = {
			frame = frame,
			gradient = gradient,
			border = border,
			view = view,
			name = name,
			stat = stat,
			pro = pro,
			worldTag = worldTag,
			button = button,
			coin = coin,
			key = "",
		}
		frame.MouseEnter:Connect(function()
			view.setSpin(true)
		end)
		frame.MouseLeave:Connect(function()
			view.setSpin(false)
		end)
		table.insert(cards, card)
	end

	local function selectSlot(newSlot: string, scroll: boolean)
		slot = newSlot
		for id, tab in tabButtons do
			tab.setPalette(if id == slot then SLOT_PALETTE[id] else "Navy")
		end
		refresh()
		if scroll then
			-- Jump to the first piece you do not own yet.
			local profile = app.State.profile
			local first = 1
			if profile then
				for index, item in Gear.bySlot[slot] do
					if not profile.gear.owned[item.key] then
						first = index
						break
					end
				end
			end
			local row = math.floor((first - 1) / 5)
			grid.CanvasPosition = Vector2.new(0, row * 216)
		end
	end

	for order, id in Gear.Slots do
		local api = Kit.button({
			Text = "",
			Icon = SLOT_ICON[id],
			IconSize = 26,
			TextSize = 19,
			Palette = "Navy",
			Size = UDim2.fromOffset(206, 56),
			LayoutOrder = order,
			Parent = tabs,
			OnClick = function()
				app.Sfx.play("Click")
				selectSlot(id, true)
			end,
		})
		tabButtons[id] = api
	end

	refresh = function()
		local profile = app.State.profile
		if not profile then
			return
		end
		panel.setTitle(Strings.get("menu.upgrades"))
		for id, tab in tabButtons do
			tab.setText(Strings.get("upgrade." .. id))
		end
		local equippedKey = profile.gear.equip[slot]
		local equippedItem = Gear.get(equippedKey)
		local currentTier = Gear.tier(equippedKey)
		local currentValue = Economy.gearValue(slot, currentTier)
		stripText.Text = Strings.get("gearWearing", {
			name = if equippedItem then GearPanel.itemName(equippedItem) else Strings.get("gearStarter"),
			stat = GearPanel.statText(slot, currentValue),
		})
		for index, item in Gear.bySlot[slot] do
			local card = cards[index]
			local c1, c2 = Color.hex(item.color), Color.hex(item.accent)
			if card.key ~= item.key then
				card.key = item.key
				card.view.setModel(Viewport.gear(item.key))
			end
			card.gradient.Color = ColorSequence.new(c1:Lerp(Color3.new(1, 1, 1), 0.7), c1:Lerp(Color3.new(1, 1, 1), 0.25))
			card.name.Text = GearPanel.itemName(item)
			local nameStroke = card.name:FindFirstChildOfClass("UIStroke")
			if nameStroke then
				nameStroke.Color = c2:Lerp(Color3.new(0, 0, 0), 0.55)
			end
			card.pro.Visible = item.pro
			card.worldTag.Text = "W" .. item.world
			local value = Economy.gearValue(slot, item.tier)
			local owned = profile.gear.owned[item.key] == true
			local wearing = equippedKey == item.key
			local locked = item.world > profile.unlocked
			card.stat.Text = GearPanel.statText(slot, value)
			card.stat.TextColor3 = if value > currentValue then C.GreenDark elseif value < currentValue then C.Muted else C.Ink
			card.border.Color = if wearing then C.Gold elseif owned then C.GreenDark else C.Outline
			card.border.Thickness = if wearing then 5 else 3
			card.coin.Visible = false
			if wearing then
				card.button.setText(utf8.char(0x2714) .. " " .. Strings.get("equipped.short"))
				card.button.setPalette("Gold")
				card.button.setEnabled(false)
			elseif owned then
				card.button.setText(Strings.get("equip"))
				card.button.setPalette("Blue")
				card.button.setEnabled(true)
			elseif locked then
				card.button.setText(utf8.char(0x1F512) .. " " .. Strings.get("world", { n = item.world }))
				card.button.setPalette("Gray")
				card.button.setEnabled(false)
			else
				local cost = Economy.gearCost(item.key) :: number
				card.coin.Visible = true
				card.button.setText(Format.short(cost))
				card.button.setPalette(if profile.coins >= cost then "Green" else "Gray")
				card.button.setEnabled(true)
			end
		end
	end

	panel.onOpen = function()
		app.Sfx.play("Open")
		selectSlot(slot, true)
	end
	app.State.profileChanged:Connect(function()
		if panel.isOpen then
			refresh()
		end
	end)
	app.State.languageChanged:Connect(refresh)
	selectSlot(slot, false)
	return panel
end

-- True when a better piece than the one worn is affordable in some slot (HUD badge).
function GearPanel.anyAffordable(profile: any): boolean
	if not profile then
		return false
	end
	for _, slot in Gear.Slots do
		local current = Gear.tier(profile.gear.equip[slot])
		for _, item in Gear.bySlot[slot] do
			if item.tier > current and item.world <= profile.unlocked and not profile.gear.owned[item.key] then
				local cost = Economy.gearCost(item.key)
				if cost and profile.coins >= cost then
					return true
				end
			end
		end
	end
	return false
end

return GearPanel
