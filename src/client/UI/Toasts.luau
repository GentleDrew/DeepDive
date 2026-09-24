--!strict
-- Stacked notification toasts under the world banner.

local Anim = require(script.Parent.Anim)
local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Toasts = {}

local KIND: { [string]: { any } } = {
	info = { Theme.Buttons.Navy, "" },
	good = { Theme.Buttons.Green, "" },
	gold = { Theme.Buttons.Gold, "" },
	bad = { Theme.Buttons.Red, "" },
	rare = { Theme.Buttons.Purple, "" },
	blue = { Theme.Buttons.Blue, "" },
}

local stack = Kit.new("Frame", {
	Name = "Toasts",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(560, 300),
	Position = UDim2.new(0.5, 0, 0, 132),
	AnchorPoint = Vector2.new(0.5, 0),
	Parent = Gui.hud,
})
Kit.list(stack, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

local order = 0
local active: { Frame } = {}

function Toasts.show(text: string, kind: string?, icon: string?)
	local palette = (KIND[kind or "info"] or KIND.info)[1]
	order += 1
	local toast = Kit.new("Frame", {
		Name = "Toast",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Parent = stack,
	}) :: Frame
	Kit.round(toast)
	Kit.gradient(toast, palette[1], palette[2])
	Kit.stroke(toast, palette[3], 3)
	Kit.padding(toast, 0, 20, 0, 20)
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = toast })
	Kit.list(row, Enum.FillDirection.Horizontal, 8)
	if icon then
		Kit.text({ Text = icon, TextSize = 26, Size = UDim2.fromOffset(30, 30), Stroke = 0, LayoutOrder = 1, Parent = row })
	end
	Kit.text({ Text = text, TextSize = 22, Size = UDim2.new(0, 0, 1, 0), AutoX = true, StrokeColor = palette[3], LayoutOrder = 2, Parent = row })
	Anim.appear(toast, 0.35)
	table.insert(active, toast)
	while #active > 3 do
		local oldest = table.remove(active, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	task.delay(2.8, function()
		if toast.Parent then
			local scale = Anim.scaleOf(toast)
			Anim.tween(scale, 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed:Wait()
			local index = table.find(active, toast)
			if index then
				table.remove(active, index)
			end
			toast:Destroy()
		end
	end)
end

return Toasts
