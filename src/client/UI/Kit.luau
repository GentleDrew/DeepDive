--!strict
-- UI component kit: rounded FredokaOne text with outlines, bubbly buttons with press/hover
-- animation, pills, progress bars, drawn icons and modal panels.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Anim = require(script.Parent.Anim)
local Theme = require(script.Parent.Theme)

local Kit = {}

local C = Theme.C

Kit.clickSound = nil :: (() -> ())?
Kit.hoverSound = nil :: (() -> ())?

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	if TEXT_CLASSES[className] then
		-- Every text object defaults to the rounded font, even text-less button containers.
		(instance :: any).FontFace = Theme.Font
	end
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Kit.corner(gui: GuiObject, radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius.Medium), Parent = gui })
end

function Kit.round(gui: GuiObject): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = gui })
end

function Kit.stroke(gui: GuiObject, color: Color3?, thickness: number?, contextual: boolean?): UIStroke
	return Kit.new("UIStroke", {
		Color = color or C.Outline,
		Thickness = thickness or 3,
		ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = gui,
	})
end

-- A second, larger stroke layered behind the normal one, breathing in thickness and transparency
-- for a glowing neon-sign look (used for the Operator's name everywhere it appears).
function Kit.neon(gui: GuiObject, color: Color3): UIStroke
	local glow = Kit.new("UIStroke", {
		Name = "NeonGlow",
		Color = color,
		Thickness = 2,
		Transparency = 0.25,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = gui,
	}) :: UIStroke
	TweenService
		:Create(glow, TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 6, Transparency = 0.75 })
		:Play()
	return glow
end

function Kit.gradient(gui: GuiObject, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return Kit.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90, Parent = gui })
end

function Kit.padding(gui: GuiObject, top: number, right: number?, bottom: number?, left: number?): UIPadding
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
		Parent = gui,
	})
end

function Kit.list(
	gui: GuiObject,
	direction: Enum.FillDirection,
	spacing: number,
	hAlign: Enum.HorizontalAlignment?,
	vAlign: Enum.VerticalAlignment?
): UIListLayout
	return Kit.new("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, spacing),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = gui,
	})
end

export type TextProps = {
	Text: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	TextSize: number?,
	Color: Color3?,
	Stroke: number?,
	StrokeColor: Color3?,
	XAlign: Enum.TextXAlignment?,
	YAlign: Enum.TextYAlignment?,
	Parent: Instance?,
	ZIndex: number?,
	Wrapped: boolean?,
	Rich: boolean?,
	Name: string?,
	LayoutOrder: number?,
	AutoX: boolean?,
}

function Kit.text(props: TextProps): TextLabel
	local label = Kit.new("TextLabel", {
		Name = props.Name or "Text",
		BackgroundTransparency = 1,
		FontFace = Theme.Font,
		Text = props.Text or "",
		TextSize = props.TextSize or 22,
		TextColor3 = props.Color or C.White,
		Size = props.Size or UDim2.new(1, 0, 0, (props.TextSize or 22) + 6),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Center,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrapped == true,
		RichText = props.Rich == true,
		ZIndex = props.ZIndex or 1,
		LayoutOrder = props.LayoutOrder or 0,
		AutomaticSize = if props.AutoX then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
		Parent = props.Parent,
	})
	local thickness = props.Stroke or Theme.TextStroke
	if thickness > 0 then
		Kit.new("UIStroke", {
			Color = props.StrokeColor or C.Ink,
			Thickness = thickness,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			LineJoinMode = Enum.LineJoinMode.Round,
			Parent = label,
		})
	end
	return label
end

-- Soft drop shadow: a sibling placed just behind `gui` (call after `gui` is parented).
function Kit.shadow(gui: GuiObject, offset: number?, radius: number?): Frame
	local shadow = Kit.new("Frame", {
		Name = gui.Name .. "Shadow",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.7,
		Size = gui.Size,
		Position = gui.Position + UDim2.fromOffset(0, offset or 5),
		AnchorPoint = gui.AnchorPoint,
		ZIndex = gui.ZIndex - 1,
		LayoutOrder = gui.LayoutOrder,
		Parent = gui.Parent,
	})
	Kit.corner(shadow, radius or Theme.Radius.Medium)
	return shadow
end

export type ButtonProps = {
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Text: string?,
	TextSize: number?,
	Palette: string?,
	Icon: string?,
	IconSize: number?,
	Radius: number?,
	LayoutOrder: number?,
	ZIndex: number?,
	Name: string?,
	OnClick: (() -> ())?,
	Stroke: number?,
}

export type ButtonApi = {
	button: TextButton,
	label: TextLabel,
	icon: TextLabel?,
	setText: (string) -> (),
	setPalette: (string) -> (),
	setEnabled: (boolean) -> (),
	enabled: boolean,
}

function Kit.button(props: ButtonProps): ButtonApi
	local palette = Theme.Buttons[props.Palette or "Blue"] or Theme.Buttons.Blue
	local radius = props.Radius or Theme.Radius.Medium
	local button = Kit.new("TextButton", {
		Name = props.Name or "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = props.Size or UDim2.fromOffset(160, 54),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 2,
		Parent = props.Parent,
	}) :: TextButton
	Kit.corner(button, radius)
	local gradient = Kit.gradient(button, palette[1], palette[2])
	local stroke = Kit.stroke(button, palette[3], props.Stroke or 3)
	-- Glossy highlight on the upper half. Circular buttons get a smaller centred highlight so it
	-- stays inside the curve (children are not clipped to a UICorner).
	local size = props.Size or UDim2.fromOffset(160, 54)
	local circular = radius * 2 >= math.min(size.X.Offset, size.Y.Offset) - 2 and size.X.Offset > 0
	local gloss = Kit.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		Size = if circular then UDim2.fromScale(0.62, 0.34) else UDim2.new(1, -10, 0.42, 0),
		Position = if circular then UDim2.fromScale(0.19, 0.09) else UDim2.fromOffset(5, 4),
		ZIndex = button.ZIndex,
		Parent = button,
	})
	if circular then
		Kit.round(gloss)
	else
		Kit.corner(gloss, math.max(4, radius - 4))
	end
	local content = Kit.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = button.ZIndex + 1,
		Parent = button,
	})
	Kit.list(content, Enum.FillDirection.Horizontal, 6)
	local icon: TextLabel? = nil
	if props.Icon then
		icon = Kit.text({
			Name = "Icon",
			Text = props.Icon,
			TextSize = props.IconSize or (props.TextSize or 24) + 4,
			Size = UDim2.fromOffset((props.IconSize or 28) + 4, (props.IconSize or 28) + 4),
			Stroke = 0,
			ZIndex = button.ZIndex + 1,
			LayoutOrder = 1,
			Parent = content,
		})
	end
	local label = Kit.text({
		Name = "Label",
		Text = props.Text or "",
		TextSize = props.TextSize or 24,
		Size = UDim2.new(0, 0, 1, 0),
		AutoX = true,
		ZIndex = button.ZIndex + 1,
		LayoutOrder = 2,
		StrokeColor = palette[3],
		Parent = content,
	})
	if (props.Text or "") == "" then
		label.Visible = false
	end

	local api: ButtonApi = {
		button = button,
		label = label,
		icon = icon,
		enabled = true,
		setText = function(_) end,
		setPalette = function(_) end,
		setEnabled = function(_) end,
	}
	api.setText = function(text: string)
		label.Text = text
		label.Visible = text ~= ""
	end
	api.setPalette = function(name: string)
		local p = Theme.Buttons[name] or Theme.Buttons.Blue
		gradient.Color = ColorSequence.new(p[1], p[2])
		stroke.Color = p[3]
		local labelStroke = label:FindFirstChildOfClass("UIStroke")
		if labelStroke then
			labelStroke.Color = p[3]
		end
	end
	api.setEnabled = function(enabled: boolean)
		api.enabled = enabled
		button.Active = enabled
		button.AutoButtonColor = false
		content.Visible = true
		gloss.Visible = enabled
	end

	local scale = Anim.scaleOf(button)
	local hovering = false
	button.MouseEnter:Connect(function()
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			return
		end
		hovering = true
		Anim.tween(scale, 0.15, { Scale = 1.05 }, Enum.EasingStyle.Back)
		if Kit.hoverSound then
			Kit.hoverSound()
		end
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		Anim.tween(scale, 0.15, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		Anim.tween(scale, 0.08, { Scale = 0.92 })
	end)
	button.MouseButton1Up:Connect(function()
		Anim.tween(scale, 0.3, { Scale = if hovering then 1.05 else 1 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		if not api.enabled then
			Anim.shake(button, 4)
			return
		end
		if Kit.clickSound then
			Kit.clickSound()
		end
		if props.OnClick then
			props.OnClick()
		end
	end)
	return api
end

-- Rounded translucent navy capsule used by HUD readouts.
function Kit.pill(props: {
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Name: string?,
	Transparency: number?,
	Outline: number?,
}): Frame
	local frame = Kit.new("Frame", {
		Name = props.Name or "Pill",
		BackgroundColor3 = C.Navy,
		BackgroundTransparency = props.Transparency or 0.18,
		Size = props.Size or UDim2.fromOffset(200, 52),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Parent = props.Parent,
	})
	Kit.round(frame)
	Kit.stroke(frame, C.Outline, props.Outline or 3)
	Kit.gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 214, 230))
	return frame
end

export type ProgressApi = { frame: Frame, fill: Frame, label: TextLabel, set: (number, string?) -> (), setColors: (Color3, Color3) -> () }

function Kit.progress(props: {
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Colors: { Color3 }?,
	TextSize: number?,
	Outline: number?,
	LabelStroke: number?,
}): ProgressApi
	local frame = Kit.new("Frame", {
		Name = "Progress",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.35,
		Size = props.Size or UDim2.fromOffset(300, 24),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ClipsDescendants = false,
		Parent = props.Parent,
	})
	Kit.round(frame)
	Kit.stroke(frame, C.Outline, props.Outline or 3)
	local fill = Kit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(0, 1),
		Parent = frame,
	})
	Kit.round(fill)
	local colors = props.Colors or { C.Cyan, C.Blue }
	local gradient = Kit.gradient(fill, colors[1], colors[2])
	local shine = Kit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.65,
		Size = UDim2.new(1, -8, 0.35, 0),
		Position = UDim2.fromOffset(4, 2),
		Parent = fill,
	})
	Kit.round(shine)
	local label =
		Kit.text({ Text = "", TextSize = props.TextSize or 16, Size = UDim2.fromScale(1, 1), ZIndex = 3, Stroke = props.LabelStroke, Parent = frame })
	local api: ProgressApi = {
		frame = frame,
		fill = fill,
		label = label,
		set = function(_, _) end,
		setColors = function(_, _) end,
	}
	api.set = function(ratio: number, text: string?)
		ratio = math.clamp(ratio, 0, 1)
		Anim.tween(fill, 0.35, { Size = UDim2.fromScale(ratio, 1) })
		fill.Visible = ratio > 0.01
		if text then
			label.Text = text
		end
	end
	api.setColors = function(a: Color3, b: Color3)
		gradient.Color = ColorSequence.new(a, b)
	end
	return api
end

-- Drawn icons ----------------------------------------------------------------------------------

Kit.Icons = {}

function Kit.Icons.coin(size: number, parent: Instance?): Frame
	local coin = Kit.new("Frame", { Name = "Coin", Size = UDim2.fromOffset(size, size), BackgroundColor3 = C.Gold, Parent = parent })
	Kit.round(coin)
	Kit.stroke(coin, C.GoldDark, math.max(2, size * 0.07))
	Kit.gradient(coin, Color3.fromRGB(255, 236, 140), Color3.fromRGB(255, 176, 40))
	local inner = Kit.new("Frame", {
		Size = UDim2.fromScale(0.62, 0.62),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 214, 80),
		Parent = coin,
	})
	Kit.round(inner)
	Kit.stroke(inner, Color3.fromRGB(230, 160, 30), math.max(1.5, size * 0.05))
	local shine = Kit.new("Frame", {
		Size = UDim2.fromScale(0.22, 0.22),
		Position = UDim2.fromScale(0.24, 0.2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.15,
		Parent = coin,
	})
	Kit.round(shine)
	return coin
end

function Kit.Icons.bubble(size: number, parent: Instance?): Frame
	local bubble = Kit.new("Frame", { Name = "Bubble", Size = UDim2.fromOffset(size, size), BackgroundColor3 = C.Oxygen, Parent = parent })
	Kit.round(bubble)
	Kit.stroke(bubble, Color3.fromRGB(20, 90, 150), math.max(2, size * 0.07))
	Kit.gradient(bubble, Color3.fromRGB(170, 245, 255), Color3.fromRGB(40, 160, 255))
	local shine = Kit.new("Frame", {
		Size = UDim2.fromScale(0.34, 0.2),
		Position = UDim2.fromScale(0.2, 0.18),
		Rotation = -30,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.1,
		Parent = bubble,
	})
	Kit.round(shine)
	local small = Kit.new("Frame", {
		Size = UDim2.fromScale(0.3, 0.3),
		Position = UDim2.fromScale(0.78, 0.72),
		BackgroundColor3 = Color3.fromRGB(150, 235, 255),
		Parent = bubble,
	})
	Kit.round(small)
	Kit.stroke(small, Color3.fromRGB(20, 90, 150), 1.5)
	return bubble
end

function Kit.Icons.bag(size: number, parent: Instance?): Frame
	local holder = Kit.new("Frame", { Name = "Bag", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
	local body = Kit.new("Frame", {
		Size = UDim2.fromScale(0.86, 0.72),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.Orange,
		Parent = holder,
	})
	Kit.corner(body, math.floor(size * 0.22))
	Kit.stroke(body, Color3.fromRGB(122, 64, 12), math.max(2, size * 0.07))
	Kit.gradient(body, Color3.fromRGB(255, 200, 110), Color3.fromRGB(240, 130, 40))
	local handle = Kit.new("Frame", {
		Size = UDim2.fromScale(0.46, 0.34),
		Position = UDim2.fromScale(0.5, 0.06),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = holder,
	})
	Kit.corner(handle, math.floor(size * 0.18))
	Kit.stroke(handle, Color3.fromRGB(122, 64, 12), math.max(2, size * 0.08))
	local pocket = Kit.new("Frame", {
		Size = UDim2.fromScale(0.5, 0.26),
		Position = UDim2.fromScale(0.5, 0.62),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 220, 150),
		Parent = holder,
	})
	Kit.corner(pocket, math.floor(size * 0.1))
	return holder
end

function Kit.Icons.emoji(text: string, size: number, parent: Instance?): TextLabel
	return Kit.text({ Text = text, TextSize = size, Size = UDim2.fromOffset(size + 6, size + 6), Stroke = 0, Parent = parent })
end

-- Toggle switch.
export type ToggleApi = { frame: TextButton, set: (boolean) -> () }

function Kit.toggle(
	props: { Parent: Instance?, Position: UDim2?, AnchorPoint: Vector2?, Value: boolean, OnChange: (boolean) -> (), LayoutOrder: number? }
): ToggleApi
	local value = props.Value
	local frame = Kit.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(86, 40),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = if value then C.Green else C.Gray,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}) :: TextButton
	Kit.round(frame)
	Kit.stroke(frame, C.Outline, 3)
	local knob = Kit.new("Frame", {
		Size = UDim2.fromOffset(32, 32),
		Position = if value then UDim2.new(1, -36, 0.5, 0) else UDim2.new(0, 4, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = frame,
	})
	Kit.round(knob)
	Kit.stroke(knob, C.Outline, 2)
	local api: ToggleApi = { frame = frame, set = function(_) end }
	api.set = function(v: boolean)
		value = v
		Anim.tween(frame, 0.2, { BackgroundColor3 = if v then C.Green else C.Gray })
		Anim.tween(knob, 0.25, { Position = if v then UDim2.new(1, -36, 0.5, 0) else UDim2.new(0, 4, 0.5, 0) }, Enum.EasingStyle.Back)
	end
	frame.Activated:Connect(function()
		if Kit.clickSound then
			Kit.clickSound()
		end
		api.set(not value)
		props.OnChange(value)
	end)
	return api
end

return Kit
