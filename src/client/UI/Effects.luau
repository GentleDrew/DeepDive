--!strict
-- Screen-space juice: floating numbers, coin bursts that fly into the coin counter, flashes,
-- confetti and the low-oxygen vignette.

local RunService = game:GetService("RunService")

local Anim = require(script.Parent.Anim)
local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Effects = {}

local C = Theme.C

function Effects.floatText(text: string, color: Color3, position: UDim2, size: number?)
	local label = Kit.text({
		Text = text,
		TextSize = size or 34,
		Color = color,
		Stroke = 3,
		Size = UDim2.fromOffset(600, (size or 34) + 10),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 50,
		Parent = Gui.hud,
	})
	Anim.appear(label, 0.3)
	Anim.tween(label, 1.3, { Position = position - UDim2.fromOffset(0, 70) }, Enum.EasingStyle.Quad)
	task.delay(0.8, function()
		Anim.tween(label, 0.5, { TextTransparency = 1 })
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			Anim.tween(stroke, 0.5, { Transparency = 1 })
		end
	end)
	task.delay(1.4, function()
		label:Destroy()
	end)
end

-- Coins spray from `from` (fraction of the HUD canvas) and home into `target`. Runs on the HUD
-- layer so positions share one coordinate space with the coin counter.
function Effects.coinBurst(count: number, from: Vector2, target: GuiObject?, onEach: (() -> ())?)
	local overlay = Gui.hud
	local canvasSize = overlay.AbsoluteSize / Gui.scale
	local start = Vector2.new(from.X * canvasSize.X, from.Y * canvasSize.Y)
	local goal = start - Vector2.new(0, 300)
	if target then
		local absolute = target.AbsolutePosition + target.AbsoluteSize / 2 - overlay.AbsolutePosition
		goal = absolute / Gui.scale
	end
	for i = 1, count do
		task.delay(i * 0.035, function()
			local coin = Kit.Icons.coin(34, overlay)
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			coin.ZIndex = 60
			coin.Position = UDim2.fromOffset(start.X, start.Y)
			local spread = Vector2.new(math.random(-160, 160), math.random(-150, -40))
			local mid = start + spread
			local t0 = os.clock()
			local duration = 0.75 + math.random() * 0.2
			local connection
			connection = RunService.RenderStepped:Connect(function()
				local t = math.clamp((os.clock() - t0) / duration, 0, 1)
				local a = start:Lerp(mid, t)
				local b = mid:Lerp(goal, t)
				local p = a:Lerp(b, t * t)
				coin.Position = UDim2.fromOffset(p.X, p.Y)
				coin.Rotation = t * 360
				local s = 1 - t * 0.35
				coin.Size = UDim2.fromOffset(34 * s, 34 * s)
				if t >= 1 then
					connection:Disconnect()
					coin:Destroy()
					if onEach then
						onEach()
					end
				end
			end)
		end)
	end
end

local flashFrame = Kit.new("Frame", {
	Name = "Flash",
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 40,
	Parent = Gui.overlay,
})

function Effects.flash(color: Color3, strength: number?, duration: number?)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 1 - (strength or 0.5)
	Anim.tween(flashFrame, duration or 0.45, { BackgroundTransparency = 1 })
end

local CONFETTI = { C.Gold, C.Pink, C.Cyan, C.Green, C.Purple, C.Orange, C.Red }

function Effects.confetti(amount: number?)
	local overlay = Gui.overlay
	local size = overlay.AbsoluteSize / Gui.scale
	for i = 1, amount or 90 do
		task.delay(math.random() * 0.6, function()
			local piece = Kit.new("Frame", {
				BackgroundColor3 = CONFETTI[(i % #CONFETTI) + 1],
				Size = UDim2.fromOffset(math.random(10, 18), math.random(6, 12)),
				Position = UDim2.fromOffset(math.random() * size.X, -20),
				Rotation = math.random(0, 360),
				ZIndex = 70,
				Parent = overlay,
			})
			Kit.corner(piece, 3)
			local fall = 2 + math.random() * 1.6
			local drift = math.random(-140, 140)
			local start = piece.Position
			Anim.tween(
				piece,
				fall,
				{ Position = start + UDim2.fromOffset(drift, size.Y + 60), Rotation = piece.Rotation + math.random(-540, 540) },
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.In
			)
			task.delay(fall, function()
				piece:Destroy()
			end)
		end)
	end
end

-- Low oxygen vignette: four gradient edges on the world layer.
local vignette: { Frame } = {}
local VIGNETTE_EDGES: { { any } } = {
	{ UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0), 90 },
	{ UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0.78), 270 },
	{ UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
	{ UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0.84, 0), 180 },
}
for _, spec in VIGNETTE_EDGES do
	local edge = Kit.new("Frame", {
		BackgroundColor3 = C.Danger,
		BackgroundTransparency = 1,
		Size = spec[1],
		Position = spec[2],
		Parent = Gui.world,
	})
	Kit.new("UIGradient", { Rotation = spec[3], Transparency = NumberSequence.new(0.2, 1), Parent = edge })
	table.insert(vignette, edge)
end

function Effects.setVignette(strength: number, color: Color3?)
	for _, edge in vignette do
		edge.BackgroundTransparency = 1 - math.clamp(strength, 0, 1)
		if color then
			edge.BackgroundColor3 = color
		end
	end
end

return Effects
