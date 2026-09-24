--!strict
-- World select: 20 themed cards with each world's egg, lock/clear state and one-tap travel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)

local Anim = require(script.Parent.Parent.Anim)
local Kit = require(script.Parent.Parent.Kit)
local Panel = require(script.Parent.Parent.Panel)
local Theme = require(script.Parent.Parent.Theme)
local Viewport = require(script.Parent.Parent.Viewport)

local WorldsPanel = {}

local C = Theme.C

type Card = {
	button: TextButton,
	lock: Frame,
	lockText: TextLabel,
	here: Frame,
	check: Frame,
	name: TextLabel,
	number: TextLabel,
	depth: TextLabel,
	view: Viewport.ViewApi,
}

function WorldsPanel.new(app: any): Panel.PanelApi
	local panel = Panel.new({
		Parent = app.Gui.panels,
		Title = Strings.get("worldsTitle"),
		Icon = utf8.char(0x1F30D),
		Palette = "Blue",
		Size = Vector2.new(870, 540),
	})
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -10),
		Position = UDim2.fromOffset(0, 14),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = C.NavySoft,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		BorderSizePixel = 0,
		Parent = panel.body,
	}) :: ScrollingFrame
	Kit.padding(scroll, 10, 16, 16, 10)
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(186, 184),
		CellPadding = UDim2.fromOffset(12, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = scroll,
	})

	local cards: { Card } = {}
	for index = 1, Config.WorldCount do
		local data = Worlds.get(index)
		local a1, a2 = Color.hex(data.accent[1]), Color.hex(data.accent[2])
		local button = Kit.new("TextButton", {
			Name = "World" .. index,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(1, 1, 1),
			LayoutOrder = index,
			Parent = scroll,
		}) :: TextButton
		Kit.corner(button, 20)
		Kit.gradient(button, Color.lighten(a1, 0.15), a2, 120)
		Kit.stroke(button, Color.darken(a2, 0.55), 4)
		local gloss = Kit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.82,
			Size = UDim2.new(1, -12, 0.4, 0),
			Position = UDim2.fromOffset(6, 5),
			Parent = button,
		})
		Kit.corner(gloss, 16)
		local numberBubble = Kit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.fromOffset(8, 8),
			ZIndex = 3,
			Parent = button,
		})
		Kit.round(numberBubble)
		Kit.stroke(numberBubble, Color.darken(a2, 0.5), 3)
		local number = Kit.text({
			Text = tostring(index),
			TextSize = 26,
			Color = Color.darken(a2, 0.35),
			Stroke = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = numberBubble,
		})
		local view = Viewport.new(button, UDim2.fromOffset(120, 104), UDim2.new(0.5, 0, 0, 16), Vector2.new(0.5, 0))
		view.frame.ZIndex = 2
		view.setModel(Viewport.egg(index))
		local name = Kit.text({
			Text = "",
			TextSize = 20,
			Size = UDim2.new(1, -10, 0, 26),
			Position = UDim2.new(0.5, 0, 1, -54),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = 3,
			StrokeColor = Color.darken(a2, 0.55),
			Parent = button,
		})
		local depth = Kit.text({
			Text = "",
			TextSize = 16,
			Size = UDim2.new(1, -10, 0, 20),
			Position = UDim2.new(0.5, 0, 1, -28),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = 3,
			Color = Color.hex("#e8f8ff"),
			StrokeColor = Color.darken(a2, 0.55),
			Parent = button,
		})

		local here = Kit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(78, 30),
			Position = UDim2.new(1, -6, 0, 8),
			AnchorPoint = Vector2.new(1, 0),
			ZIndex = 5,
			Visible = false,
			Parent = button,
		})
		Kit.round(here)
		Kit.gradient(here, Theme.Buttons.Gold[1], Theme.Buttons.Gold[2])
		Kit.stroke(here, Theme.Buttons.Gold[3], 3)
		Kit.text({
			Name = "HereText",
			Text = "",
			TextSize = 18,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			StrokeColor = Theme.Buttons.Gold[3],
			Parent = here,
		})
		local check = Kit.new("Frame", {
			BackgroundColor3 = C.Green,
			Size = UDim2.fromOffset(34, 34),
			Position = UDim2.new(1, -8, 0, 8),
			AnchorPoint = Vector2.new(1, 0),
			ZIndex = 5,
			Visible = false,
			Parent = button,
		})
		Kit.round(check)
		Kit.stroke(check, C.GreenDark, 3)
		Kit.text({ Text = utf8.char(0x2714), TextSize = 20, Size = UDim2.fromScale(1, 1), ZIndex = 6, StrokeColor = C.GreenDark, Parent = check })

		local lock = Kit.new("Frame", {
			BackgroundColor3 = Color.hex("#0a1626"),
			BackgroundTransparency = 0.35,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 8,
			Visible = false,
			Parent = button,
		})
		Kit.corner(lock, 20)
		Kit.text({
			Text = utf8.char(0x1F512),
			TextSize = 44,
			Size = UDim2.new(1, 0, 0, 56),
			Position = UDim2.fromOffset(0, 34),
			Stroke = 0,
			ZIndex = 9,
			Parent = lock,
		})
		local lockText = Kit.text({
			Text = "",
			TextSize = 18,
			Size = UDim2.new(1, -10, 0, 40),
			Position = UDim2.new(0.5, 0, 0, 98),
			AnchorPoint = Vector2.new(0.5, 0),
			Wrapped = true,
			ZIndex = 9,
			Parent = lock,
		})

		local card: Card = {
			button = button,
			lock = lock,
			lockText = lockText,
			here = here,
			check = check,
			name = name,
			number = number,
			depth = depth,
			view = view,
		}
		cards[index] = card

		button.MouseEnter:Connect(function()
			view.setSpin(true)
			Anim.tween(Anim.scaleOf(button), 0.15, { Scale = 1.04 }, Enum.EasingStyle.Back)
		end)
		button.MouseLeave:Connect(function()
			view.setSpin(false)
			Anim.tween(Anim.scaleOf(button), 0.15, { Scale = 1 })
		end)
		button.Activated:Connect(function()
			local profile = app.State.profile
			if not profile then
				return
			end
			if index > profile.unlocked then
				app.Sfx.play("Error")
				Anim.shake(button, 6)
				app.Toasts.show(Strings.get("lockedHint", { n = index - 1 }), "bad", utf8.char(0x1F512))
				return
			end
			app.Sfx.play("Click")
			if index == app.State.world then
				panel.close()
				return
			end
			panel.close()
			app.travel(index)
		end)
	end

	local function refresh()
		local profile = app.State.profile
		panel.setTitle(Strings.get("worldsTitle"))
		for index, card in cards do
			local data = Worlds.get(index)
			card.name.Text = Strings.name(data.name)
			card.depth.Text = Strings.get("depthMax", { n = data.meters })
			local unlocked = profile ~= nil and index <= profile.unlocked
			local progress = app.State.progress(index)
			card.lock.Visible = not unlocked
			card.lockText.Text = Strings.get("lockedHint", { n = index - 1 })
			local current = index == app.State.world
			card.here.Visible = current
			local hereText = card.here:FindFirstChild("HereText") :: TextLabel?
			if hereText then
				hereText.Text = Strings.get("here")
			end
			card.check.Visible = progress.cleared and not current
		end
	end

	panel.onOpen = function()
		app.Sfx.play("Open")
		refresh()
		local profile = app.State.profile
		if profile then
			-- Scroll so the frontier world is visible.
			local row = math.floor((math.min(profile.unlocked, Config.WorldCount) - 1) / 4)
			scroll.CanvasPosition = Vector2.new(0, math.max(0, row - 1) * 198)
		end
	end
	app.State.profileChanged:Connect(function()
		if panel.isOpen then
			refresh()
		end
	end)
	app.State.languageChanged:Connect(refresh)
	return panel
end

return WorldsPanel
