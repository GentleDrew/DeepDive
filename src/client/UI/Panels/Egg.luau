--!strict
-- Egg stand panel: the world's egg, every pet inside with its chance, Hatch / Hatch x3 / Auto.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
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

local EggPanel = {}

local C = Theme.C

export type EggPanelApi = Panel.PanelApi & { openWorld: (number) -> () }

function EggPanel.new(app: any): EggPanelApi
	local panel =
		Panel.new({ Parent = app.Gui.panels, Title = "", Icon = utf8.char(0x1F95A), Palette = "Purple", Size = Vector2.new(860, 540) }) :: any
	local body = panel.body
	local world = 1
	local auto = false
	local busy = false

	local stage = Kit.new(
		"Frame",
		{ BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 280, 1, -30), Position = UDim2.fromOffset(0, 24), Parent = body }
	)
	Kit.corner(stage, 20)
	Kit.stroke(stage, C.PanelLine, 3)
	local stageGradient = Kit.gradient(stage, Color3.fromRGB(255, 255, 255), Color3.fromRGB(220, 235, 255))
	local eggView = Viewport.new(stage, UDim2.fromOffset(240, 240), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0))
	eggView.setSpin(true)
	local eggName = Kit.text({
		Text = "",
		TextSize = 28,
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.new(0.5, 0, 0, 252),
		AnchorPoint = Vector2.new(0.5, 0),
		Parent = stage,
	})
	local costPill =
		Kit.pill({ Size = UDim2.fromOffset(190, 50), Position = UDim2.new(0.5, 0, 0, 296), AnchorPoint = Vector2.new(0.5, 0), Parent = stage })
	local coin = Kit.Icons.coin(40, costPill)
	coin.Position = UDim2.fromOffset(6, 5)
	local costLabel = Kit.text({
		Text = "",
		TextSize = 28,
		Size = UDim2.new(1, -54, 1, 0),
		Position = UDim2.fromOffset(50, 0),
		XAlign = Enum.TextXAlignment.Left,
		Parent = costPill,
	})
	local autoRow = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 44),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		Parent = stage,
	})
	local autoLabel = Kit.text({
		Text = "Auto",
		TextSize = 22,
		Color = C.Navy,
		Stroke = 0,
		Size = UDim2.new(1, -96, 1, 0),
		XAlign = Enum.TextXAlignment.Left,
		Parent = autoRow,
	})
	local autoToggle = Kit.toggle({
		Value = false,
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = autoRow,
		OnChange = function(value)
			auto = value
		end,
	})

	local chancesTitle = Kit.text({
		Text = "",
		TextSize = 24,
		Color = C.Navy,
		Stroke = 0,
		Size = UDim2.new(1, -300, 0, 30),
		Position = UDim2.new(1, 0, 0, 24),
		AnchorPoint = Vector2.new(1, 0),
		XAlign = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local grid = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -300, 0, 300),
		Position = UDim2.new(1, 0, 0, 60),
		AnchorPoint = Vector2.new(1, 0),
		Parent = body,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(160, 140),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		Parent = grid,
	})

	local buttons = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -300, 0, 70),
		Position = UDim2.new(1, 0, 1, -8),
		AnchorPoint = Vector2.new(1, 1),
		Parent = body,
	})
	Kit.list(buttons, Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center)

	local function doHatch(count: number)
		if busy then
			return
		end
		busy = true
		local result = app.Net.invoke("Hatch", { world = world, count = count })
		if not result.ok then
			busy = false
			auto = false
			autoToggle.set(false)
			app.Sfx.play("Error")
			app.Toasts.show(Strings.get(result.err or "err.generic", { n = "" }), "bad")
			return
		end
		panel.root.Visible = false
		app.Hatch.play(world, result.data.results, function()
			busy = false
			if panel.isOpen then
				panel.root.Visible = true
			end
			if auto and panel.isOpen then
				local profile = app.State.profile
				if profile and profile.coins >= Economy.eggCost(world) * count then
					task.delay(0.25, function()
						doHatch(count)
					end)
				else
					auto = false
					autoToggle.set(false)
				end
			end
		end)
	end

	local hatchOne = Kit.button({
		Text = "",
		TextSize = 24,
		Palette = "Green",
		Size = UDim2.fromOffset(250, 64),
		LayoutOrder = 1,
		Parent = buttons,
		OnClick = function()
			doHatch(1)
		end,
	})
	local hatchThree = Kit.button({
		Text = "",
		TextSize = 24,
		Palette = "Gold",
		Size = UDim2.fromOffset(250, 64),
		LayoutOrder = 2,
		Parent = buttons,
		OnClick = function()
			doHatch(3)
		end,
	})

	local petCards: { Instance } = {}

	local function rebuild()
		for _, card in petCards do
			card:Destroy()
		end
		table.clear(petCards)
		local data = Worlds.get(world)
		local profile = app.State.profile
		local chances = Economy.eggChances(world, app.State.passes.LuckyEggs == true)
		for order, entry in chances do
			local pet = Worlds.pets[entry.key]
			local rarity = Config.Rarities[pet.rarity]
			local color = Theme.Rarity[rarity]
			local owned = profile ~= nil and profile.index[entry.key] == true
			local card = Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = order, Parent = grid })
			Kit.corner(card, 16)
			Kit.gradient(card, color:Lerp(Color3.new(1, 1, 1), 0.6), color, 90)
			Kit.stroke(card, color:Lerp(Color3.new(0, 0, 0), 0.5), 3)
			local view = Viewport.new(card, UDim2.fromOffset(110, 78), UDim2.new(0.5, 0, 0, 2), Vector2.new(0.5, 0))
			if pet.secret and not owned then
				Kit.text({
					Text = "?",
					TextSize = 56,
					Size = UDim2.fromOffset(110, 78),
					Position = UDim2.new(0.5, 0, 0, 2),
					AnchorPoint = Vector2.new(0.5, 0),
					Parent = card,
				})
				view.frame.Visible = false
			else
				view.setModel(Viewport.pet(entry.key))
				view.setSpin(true)
			end
			Kit.text({
				Text = if pet.secret and not owned then "???" else Strings.name(pet.name),
				TextSize = 16,
				Size = UDim2.new(1, -6, 0, 20),
				Position = UDim2.new(0.5, 0, 0, 80),
				AnchorPoint = Vector2.new(0.5, 0),
				StrokeColor = color:Lerp(Color3.new(0, 0, 0), 0.6),
				Parent = card,
			})
			Kit.text({
				Text = Format.percent(entry.chance),
				TextSize = 20,
				Size = UDim2.new(1, 0, 0, 24),
				Position = UDim2.new(0, 0, 1, -28),
				Color = Color3.fromRGB(255, 255, 210),
				StrokeColor = color:Lerp(Color3.new(0, 0, 0), 0.6),
				Parent = card,
			})
			if owned then
				local tick = Kit.new("Frame", {
					BackgroundColor3 = C.Green,
					Size = UDim2.fromOffset(24, 24),
					Position = UDim2.new(1, -4, 0, 4),
					AnchorPoint = Vector2.new(1, 0),
					Parent = card,
				})
				Kit.round(tick)
				Kit.text({ Text = utf8.char(0x2714), TextSize = 14, Size = UDim2.fromScale(1, 1), Parent = tick })
			end
			table.insert(petCards, card)
		end
		eggView.setModel(Viewport.egg(world))
		local accent = Color.hex(data.egg.accent)
		stageGradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), accent:Lerp(Color3.new(1, 1, 1), 0.6))
	end

	local function refresh()
		local data = Worlds.get(world)
		local cost = Economy.eggCost(world)
		local profile = app.State.profile
		panel.setTitle(Strings.name(data.egg.name))
		eggName.Text = Strings.get("world", { n = world }) .. "  -  " .. Strings.name(data.name)
		costLabel.Text = Format.short(cost)
		chancesTitle.Text = Strings.get("chances")
		autoLabel.Text = "Auto"
		hatchOne.setText(Strings.get("hatch") .. "  " .. Format.short(cost))
		hatchThree.setText(Strings.get("hatch3") .. "  " .. Format.short(cost * 3))
		local coins = if profile then profile.coins else 0
		hatchOne.setPalette(if coins >= cost then "Green" else "Gray")
		hatchThree.setPalette(if coins >= cost * 3 then "Gold" else "Gray")
	end

	function panel.openWorld(w: number)
		world = w
		rebuild()
		refresh()
		panel.open()
	end

	panel.onOpen = function()
		app.Sfx.play("Open")
		Anim.pop(stage, 0.05)
	end
	panel.onClose = function()
		auto = false
		autoToggle.set(false)
	end
	app.State.profileChanged:Connect(function()
		if panel.isOpen then
			refresh()
		end
	end)
	app.State.languageChanged:Connect(function()
		if panel.isOpen then
			rebuild()
			refresh()
		end
	end)
	return panel
end

return EggPanel
