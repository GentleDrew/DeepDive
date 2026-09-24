--!strict
-- Modal panel: dimmed backdrop, rounded window with a coloured header ribbon and close button.
-- Only one panel is open at a time.

local Anim = require(script.Parent.Anim)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Panel = {}

local C = Theme.C

export type PanelApi = {
	root: Frame,
	window: Frame,
	body: Frame,
	title: TextLabel,
	isOpen: boolean,
	open: () -> (),
	close: () -> (),
	toggle: () -> (),
	setTitle: (string) -> (),
	onOpen: (() -> ())?,
	onClose: (() -> ())?,
}

local current: PanelApi? = nil

function Panel.closeAll()
	if current then
		current.close()
	end
end

function Panel.current(): PanelApi?
	return current
end

export type PanelProps = { Parent: Instance, Title: string, Icon: string?, Palette: string?, Size: Vector2? }

function Panel.new(props: PanelProps): PanelApi
	local palette = Theme.Buttons[props.Palette or "Blue"] or Theme.Buttons.Blue
	local size = props.Size or Vector2.new(720, 470)

	local root = Kit.new("Frame", {
		Name = "Panel_" .. props.Title,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 20,
		Parent = props.Parent,
	}) :: Frame
	local backdrop = Kit.new("TextButton", {
		Name = "Backdrop",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(4, 14, 28),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = root,
	}) :: TextButton
	-- Holder scales as one unit; the shadow is a sibling so it renders behind the window
	-- (ScreenGuis use Sibling z-ordering: children always draw above their parent).
	local holder = Kit.new("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.53),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 21,
		Parent = root,
	}) :: Frame
	local shadow = Kit.new("Frame", {
		Name = "Shadow",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.6,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 8),
		ZIndex = 1,
		Parent = holder,
	})
	Kit.corner(shadow, Theme.Radius.Large)
	local window = Kit.new("Frame", {
		Name = "Window",
		BackgroundColor3 = C.Panel,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = holder,
	}) :: Frame
	Kit.corner(window, Theme.Radius.Large)
	Kit.stroke(window, C.Outline, 4)
	Kit.gradient(window, Color3.fromRGB(255, 255, 255), Color3.fromRGB(214, 238, 255))

	local header = Kit.new("Frame", {
		Name = "Header",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 24, 0, 66),
		Position = UDim2.new(0.5, 0, 0, -26),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 23,
		Parent = window,
	})
	Kit.corner(header, 20)
	Kit.stroke(header, palette[3], 4)
	Kit.gradient(header, palette[1], palette[2])
	local gloss = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.8,
		Size = UDim2.new(1, -16, 0.42, 0),
		Position = UDim2.fromOffset(8, 5),
		ZIndex = 23,
		Parent = header,
	})
	Kit.corner(gloss, 14)
	local titleRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 24, Parent = header })
	Kit.list(titleRow, Enum.FillDirection.Horizontal, 10)
	if props.Icon then
		Kit.text({ Text = props.Icon, TextSize = 36, Size = UDim2.fromOffset(46, 46), Stroke = 0, ZIndex = 24, LayoutOrder = 1, Parent = titleRow })
	end
	local title = Kit.text({
		Text = props.Title,
		TextSize = 38,
		Size = UDim2.new(0, 0, 1, 0),
		AutoX = true,
		Stroke = 3,
		StrokeColor = palette[3],
		ZIndex = 24,
		LayoutOrder = 2,
		Parent = titleRow,
	})

	local body = Kit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -36, 1, -66),
		Position = UDim2.fromOffset(18, 52),
		ZIndex = 22,
		Parent = window,
	}) :: Frame

	local api: PanelApi = {
		root = root,
		window = window,
		body = body,
		title = title,
		isOpen = false,
		open = function() end,
		close = function() end,
		toggle = function() end,
		setTitle = function(_) end,
		onOpen = nil,
		onClose = nil,
	}

	local closeButton = Kit.button({
		Name = "Close",
		Text = "X",
		TextSize = 30,
		Palette = "Red",
		Size = UDim2.fromOffset(54, 54),
		Position = UDim2.new(1, 14, 0, -34),
		AnchorPoint = Vector2.new(0.5, 0),
		Radius = 27,
		ZIndex = 26,
		Parent = window,
		OnClick = function()
			api.close()
		end,
	})
	closeButton.button.ZIndex = 26

	local scale = Anim.scaleOf(holder)
	api.open = function()
		if api.isOpen then
			return
		end
		if current and current ~= api then
			current.close()
		end
		current = api
		api.isOpen = true
		root.Visible = true
		backdrop.BackgroundTransparency = 1
		Anim.tween(backdrop, 0.25, { BackgroundTransparency = 0.45 })
		scale.Scale = 0.82
		Anim.tween(scale, 0.38, { Scale = 1 }, Enum.EasingStyle.Back)
		if api.onOpen then
			api.onOpen()
		end
	end
	api.close = function()
		if not api.isOpen then
			return
		end
		api.isOpen = false
		if current == api then
			current = nil
		end
		Anim.tween(backdrop, 0.18, { BackgroundTransparency = 1 })
		local tween = Anim.tween(scale, 0.18, { Scale = 0.85 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween.Completed:Once(function()
			if not api.isOpen then
				root.Visible = false
			end
		end)
		if api.onClose then
			api.onClose()
		end
	end
	api.toggle = function()
		if api.isOpen then
			api.close()
		else
			api.open()
		end
	end
	api.setTitle = function(text: string)
		title.Text = text
	end
	backdrop.Activated:Connect(api.close)
	return api
end

return Panel
