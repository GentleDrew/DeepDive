--!nocheck
-- Approximate HTML/CSS export of a live PlayerGui tree (from the Lune engine harness) for visual
-- review in a browser. Handles the subset of GUI features the game uses: frames, text, list and
-- grid layouts, padding, corners, strokes, gradients, UIScale, AutomaticSize and ScreenGui layers.

local roblox = require("@lune/roblox")
local Enum = roblox.Enum

local Html = {}

local function num(n: number): string
	if math.abs(n - math.floor(n)) < 1e-4 then
		return tostring(math.floor(n))
	end
	return string.format("%.3f", n)
end

local function rgba(c, transparency: number?): string
	return string.format(
		"rgba(%d,%d,%d,%s)",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5),
		num(1 - (transparency or 0))
	)
end

local function udim(u): string
	if u.Scale == 0 then
		return num(u.Offset) .. "px"
	elseif u.Offset == 0 then
		return num(u.Scale * 100) .. "%"
	end
	return string.format("calc(%s%% + %spx)", num(u.Scale * 100), num(u.Offset))
end

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- Minimal Roblox rich text → HTML.
local function richText(text: string): string
	local out = escape(text)
	out = string.gsub(out, '&lt;font color="(#%x+)"&gt;', '<span style="color:%1">')
	out = string.gsub(out, "&lt;font color='(#%x+)'&gt;", '<span style="color:%1">')
	out = string.gsub(out, "&lt;/font&gt;", "</span>")
	out = string.gsub(out, "&lt;(/?[biu])&gt;", "<%1>")
	out = string.gsub(out, "&lt;br */?&gt;", "<br>")
	out = string.gsub(out, "&lt;/?stroke[^&]*&gt;", "")
	return out
end

local function childOf(raw, className: string)
	for _, child in raw:GetChildren() do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

local function gradientCss(gradient, alphaScale: number): string
	local stops = {}
	for _, keypoint in gradient.Color.Keypoints do
		local transparency = 0
		for _, t in gradient.Transparency.Keypoints do
			if math.abs(t.Time - keypoint.Time) < 1e-3 then
				transparency = t.Value
			end
		end
		table.insert(stops, string.format("%s %s%%", rgba(keypoint.Value, 1 - (1 - transparency) * alphaScale), num(keypoint.Time * 100)))
	end
	return string.format("linear-gradient(%sdeg, %s)", num(gradient.Rotation + 90), table.concat(stops, ", "))
end

local function textShadow(color, transparency: number, thickness: number): string
	local parts = {}
	local steps = 12
	for i = 0, steps - 1 do
		local a = i / steps * math.pi * 2
		table.insert(parts, string.format("%spx %spx 0 %s", num(math.cos(a) * thickness), num(math.sin(a) * thickness), rgba(color, transparency)))
	end
	return table.concat(parts, ", ")
end

local ALIGN_X = { Left = "flex-start", Center = "center", Right = "flex-end" }
local ALIGN_Y = { Top = "flex-start", Center = "center", Bottom = "flex-end" }

local render

local function renderChildren(raw, mode): string
	local out = {}
	local kids = {}
	for index, child in raw:GetChildren() do
		if child:IsA("GuiObject") then
			table.insert(kids, { child = child, index = index })
		end
	end
	table.sort(kids, function(a, b)
		if a.child.ZIndex ~= b.child.ZIndex then
			return a.child.ZIndex < b.child.ZIndex
		end
		return a.index < b.index
	end)
	for _, entry in kids do
		table.insert(out, render(entry.child, mode))
	end
	return table.concat(out)
end

render = function(raw, parentMode): string
	if not raw.Visible then
		return ""
	end
	local style = {}
	local function add(k: string, v: string)
		table.insert(style, k .. ":" .. v)
	end
	local list = childOf(raw, "UIListLayout")
	local grid = childOf(raw, "UIGridLayout")
	local padding = childOf(raw, "UIPadding")
	local corner = childOf(raw, "UICorner")
	local gradient = childOf(raw, "UIGradient")
	local uiScale = childOf(raw, "UIScale")
	local strokes = {}
	for _, child in raw:GetChildren() do
		if child.ClassName == "UIStroke" and child.Enabled then
			table.insert(strokes, child)
		end
	end
	local isText = raw:IsA("TextLabel") or raw:IsA("TextButton") or raw:IsA("TextBox")
	local auto = raw.AutomaticSize
	local autoX = auto == Enum.AutomaticSize.X or auto == Enum.AutomaticSize.XY
	local autoY = auto == Enum.AutomaticSize.Y or auto == Enum.AutomaticSize.XY
	local flow = autoX or autoY

	-- Placement
	if parentMode and parentMode.kind == "stack" then
		-- Child of an auto-sized container without a layout: stacked in one grid cell so the
		-- container grows to fit it, then nudged by its Position.
		add("position", "relative")
		add("grid-area", "1 / 1")
		add("left", udim(raw.Position.X))
		add("top", udim(raw.Position.Y))
	elseif parentMode and parentMode.kind ~= "absolute" then
		add("position", "relative")
		add("flex-shrink", "0")
		add("order", tostring(raw.LayoutOrder))
	else
		add("position", "absolute")
		add("left", udim(raw.Position.X))
		add("top", udim(raw.Position.Y))
	end
	local size = raw.Size
	if parentMode and parentMode.kind == "grid" then
		size = parentMode.cell
	end
	if autoX then
		add("min-width", udim(size.X))
		add("width", "max-content")
	else
		add("width", udim(size.X))
	end
	if autoY then
		add("min-height", udim(size.Y))
		add("height", "max-content")
	else
		add("height", udim(size.Y))
	end
	add("box-sizing", "border-box")
	local transforms = {}
	local anchor = raw.AnchorPoint
	if (not parentMode or parentMode.kind == "absolute" or parentMode.kind == "stack") and (anchor.X ~= 0 or anchor.Y ~= 0) then
		table.insert(transforms, string.format("translate(%s%%, %s%%)", num(-anchor.X * 100), num(-anchor.Y * 100)))
	end
	if raw.Rotation ~= 0 then
		table.insert(transforms, string.format("rotate(%sdeg)", num(raw.Rotation)))
	end
	if uiScale and uiScale.Scale ~= 1 then
		table.insert(transforms, string.format("scale(%s)", num(uiScale.Scale)))
	end
	if #transforms > 0 then
		add("transform", table.concat(transforms, " "))
		-- UIScale scales around the AnchorPoint (the HUD canvases scale from their top-left).
		add("transform-origin", string.format("%s%% %s%%", num(anchor.X * 100), num(anchor.Y * 100)))
	end
	add("z-index", tostring(raw.ZIndex))

	-- Background
	local bgTransparency = raw.BackgroundTransparency
	local textGradient = isText and gradient and bgTransparency >= 1
	if bgTransparency < 1 then
		if gradient and gradient.Enabled then
			local white = raw.BackgroundColor3.R > 0.98 and raw.BackgroundColor3.G > 0.98 and raw.BackgroundColor3.B > 0.98
			add("background-image", gradientCss(gradient, 1 - bgTransparency))
			if not white then
				add("background-color", rgba(raw.BackgroundColor3, bgTransparency))
				add("background-blend-mode", "multiply")
			end
		else
			add("background-color", rgba(raw.BackgroundColor3, bgTransparency))
		end
	end
	if corner then
		local r = corner.CornerRadius
		if r.Scale >= 0.5 then
			add("border-radius", "9999px")
		elseif r.Scale > 0 then
			local abs = raw.AbsoluteSize
			add("border-radius", num(r.Scale * math.min(abs.X, abs.Y) + r.Offset) .. "px")
		else
			add("border-radius", num(r.Offset) .. "px")
		end
	end
	local shadows = {}
	local textStroke = nil
	for _, stroke in strokes do
		if stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual and isText then
			textStroke = stroke
		else
			table.insert(shadows, string.format("0 0 0 %spx %s", num(stroke.Thickness), rgba(stroke.Color, stroke.Transparency)))
		end
	end
	if #shadows > 0 then
		add("box-shadow", table.concat(shadows, ", "))
	end
	if raw.ClipsDescendants or raw:IsA("ScrollingFrame") then
		add("overflow", "hidden")
	end

	local pad = { "0px", "0px", "0px", "0px" }
	if padding then
		pad = { udim(padding.PaddingTop), udim(padding.PaddingRight), udim(padding.PaddingBottom), udim(padding.PaddingLeft) }
	end

	-- Children container (content box inside padding), laid out by a UIListLayout / UIGridLayout.
	local inner = {}
	local mode = { kind = "absolute" }
	if list then
		mode = { kind = "list" }
		local horizontal = list.FillDirection == Enum.FillDirection.Horizontal
		table.insert(inner, "display:flex")
		table.insert(inner, "flex-direction:" .. (if horizontal then "row" else "column"))
		table.insert(inner, "gap:" .. udim(list.Padding))
		local h, v = ALIGN_X[list.HorizontalAlignment.Name], ALIGN_Y[list.VerticalAlignment.Name]
		table.insert(inner, "justify-content:" .. (if horizontal then h else v))
		table.insert(inner, "align-items:" .. (if horizontal then v else h))
	elseif grid then
		mode = { kind = "grid", cell = grid.CellSize }
		table.insert(inner, "display:flex")
		table.insert(inner, "flex-wrap:wrap")
		table.insert(inner, "row-gap:" .. udim(grid.CellPadding.Y))
		table.insert(inner, "column-gap:" .. udim(grid.CellPadding.X))
		if grid.FillDirection == Enum.FillDirection.Vertical then
			-- Column-major fill: wrap into a new column after FillDirectionMaxCells cells.
			table.insert(inner, "flex-direction:column")
			table.insert(inner, "align-content:flex-start")
			table.insert(inner, "justify-content:" .. ALIGN_Y[grid.VerticalAlignment.Name])
		else
			table.insert(inner, "align-content:flex-start")
			table.insert(inner, "justify-content:" .. ALIGN_X[grid.HorizontalAlignment.Name])
		end
	end
	if flow then
		add("padding", table.concat(pad, " "))
		table.insert(inner, "position:relative")
		if mode.kind == "absolute" then
			mode = { kind = "stack" }
			table.insert(inner, "display:grid")
			table.insert(inner, "min-width:100%")
			table.insert(inner, "min-height:100%")
		end
	else
		table.insert(inner, string.format("position:absolute;top:%s;right:%s;bottom:%s;left:%s", pad[1], pad[2], pad[3], pad[4]))
	end
	if raw:IsA("ScrollingFrame") then
		local canvas = raw.CanvasSize
		table.insert(inner, "bottom:auto")
		local autoCanvasY = raw.AutomaticCanvasSize == Enum.AutomaticSize.Y or raw.AutomaticCanvasSize == Enum.AutomaticSize.XY
		if not autoCanvasY then
			table.insert(inner, "height:" .. udim(canvas.Y))
		end
	end

	-- Own text (inside the padded box, below children)
	local textHtml = ""
	if isText and raw.Text ~= "" and raw.TextTransparency < 1 then
		local t = {}
		table.insert(t, "font-family:'Fredoka One','Noto Color Emoji',sans-serif")
		table.insert(t, "font-size:" .. num(raw.TextSize) .. "px")
		table.insert(t, "line-height:1")
		table.insert(t, "color:" .. rgba(raw.TextColor3, raw.TextTransparency))
		table.insert(t, "display:flex")
		table.insert(t, "align-items:" .. ALIGN_Y[raw.TextYAlignment.Name])
		table.insert(t, "justify-content:" .. ALIGN_X[raw.TextXAlignment.Name])
		table.insert(t, "text-align:" .. string.lower(raw.TextXAlignment.Name))
		table.insert(t, "white-space:" .. (if raw.TextWrapped then "normal" else "pre"))
		if flow then
			table.insert(t, "position:relative")
			table.insert(t, "min-height:100%")
		else
			table.insert(t, string.format("position:absolute;top:%s;right:%s;bottom:%s;left:%s", pad[1], pad[2], pad[3], pad[4]))
		end
		if textStroke then
			table.insert(t, "text-shadow:" .. textShadow(textStroke.Color, textStroke.Transparency, textStroke.Thickness))
		elseif raw.TextStrokeTransparency < 1 then
			table.insert(t, "text-shadow:" .. textShadow(raw.TextStrokeColor3, raw.TextStrokeTransparency, 1))
		end
		local body = if raw.RichText then richText(raw.Text) else escape(raw.Text)
		if textGradient then
			-- Text gradients need a clipped background; keep the stroke on a copy underneath.
			local fill = table.clone(t)
			table.insert(fill, "background-image:" .. gradientCss(gradient, 1))
			table.insert(fill, "-webkit-background-clip:text;background-clip:text;color:transparent;text-shadow:none")
			textHtml = string.format('<div style="%s">%s</div><div style="%s">%s</div>', table.concat(t, ";"), body, table.concat(fill, ";"), body)
		else
			textHtml = string.format('<div style="%s">%s</div>', table.concat(t, ";"), body)
		end
	end

	local viewport = ""
	if raw:IsA("ViewportFrame") then
		viewport =
			'<div style="position:absolute;inset:12%;border-radius:40%;background:radial-gradient(circle at 40% 35%, rgba(255,255,255,.55), rgba(120,170,220,.25));"></div>'
	end

	return string.format(
		'<div data-name="%s" style="%s">%s%s<div style="%s">%s</div></div>',
		escape(raw.Name),
		table.concat(style, ";"),
		viewport,
		textHtml,
		table.concat(inner, ";"),
		renderChildren(raw, mode)
	)
end

-- Renders every enabled ScreenGui under `playerGui` into a full HTML page. `options.wrap` turns a
-- raw instance into an engine proxy so computed/defaulted properties read correctly.
function Html.page(playerGui, viewport, options): string
	options = options or {}
	if options.wrap then
		playerGui = options.wrap(playerGui)
	end
	local topInset = options.topInset or 58
	local layers = {}
	for _, screen in playerGui:GetChildren() do
		if screen.ClassName == "ScreenGui" and screen.Enabled then
			table.insert(layers, screen)
		end
	end
	table.sort(layers, function(a, b)
		return a.DisplayOrder < b.DisplayOrder
	end)
	local body = {}
	for _, screen in layers do
		local inset = if screen.IgnoreGuiInset or screen.ScreenInsets == Enum.ScreenInsets.None then 0 else topInset
		table.insert(
			body,
			string.format(
				'<div data-layer="%s" style="position:absolute;left:0;right:0;bottom:0;top:%dpx;z-index:%d;">%s</div>',
				screen.Name,
				inset,
				screen.DisplayOrder,
				renderChildren(screen, { kind = "absolute" })
			)
		)
	end
	local topbar = ""
	if options.topbar ~= false then
		topbar = [[<div style="position:absolute;left:0;right:0;top:0;height:58px;z-index:1000;pointer-events:none">
<div style="position:absolute;left:12px;top:10px;width:44px;height:44px;border-radius:22px;background:rgba(20,20,24,.72)"></div>
<div style="position:absolute;left:64px;top:10px;width:44px;height:44px;border-radius:22px;background:rgba(20,20,24,.72)"></div>
<div style="position:absolute;right:12px;top:10px;width:44px;height:44px;border-radius:22px;background:rgba(20,20,24,.72)"></div>
</div>]]
	end
	local background = options.background or "linear-gradient(180deg, #7fd3ff 0%, #bfeaff 38%, #1f9ad6 39%, #0c6aa6 70%, #06406b 100%)"
	return string.format(
		[[<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fredoka+One&display=block">
<style>
@font-face{font-family:'Fredoka One';src:url('%s') format('woff2');}
html,body{margin:0;padding:0;width:%dpx;height:%dpx;overflow:hidden;}
body{position:relative;background:%s;font-family:'Fredoka One','Noto Color Emoji',sans-serif;}
div{box-sizing:border-box;}
</style></head><body>%s%s</body></html>]],
		options.fontUrl or "FredokaOne.woff2",
		viewport.X,
		viewport.Y,
		background,
		table.concat(body),
		topbar
	)
end

return Html
