--!strict
-- Tween helpers: pops, shakes, pulses, counters.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Anim = {}

function Anim.tween(instance: Instance, duration: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

-- UIScale child used for pop/press animations (created on demand).
function Anim.scaleOf(gui: GuiObject): UIScale
	local scale = gui:FindFirstChild("AnimScale")
	if scale and scale:IsA("UIScale") then
		return scale
	end
	local created = Instance.new("UIScale")
	created.Name = "AnimScale"
	created.Parent = gui
	return created
end

function Anim.pop(gui: GuiObject, amount: number?)
	local scale = Anim.scaleOf(gui)
	scale.Scale = 1 + (amount or 0.18)
	Anim.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

function Anim.appear(gui: GuiObject, duration: number?)
	local scale = Anim.scaleOf(gui)
	scale.Scale = 0.4
	Anim.tween(scale, duration or 0.4, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

function Anim.shake(gui: GuiObject, strength: number?)
	local origin = gui.Position
	local s = strength or 6
	task.spawn(function()
		for i = 1, 6 do
			local offset = (if i % 2 == 0 then 1 else -1) * s * (1 - i / 7)
			gui.Position = origin + UDim2.fromOffset(offset, 0)
			task.wait(0.03)
		end
		gui.Position = origin
	end)
end

-- Counts a TextLabel from `from` to `to` using `formatter`.
function Anim.count(label: TextLabel, from: number, to: number, duration: number, formatter: (number) -> string)
	local token = ((label:GetAttribute("CountToken") :: number?) or 0) + 1
	label:SetAttribute("CountToken", token)
	local start = os.clock()
	task.spawn(function()
		while true do
			if label:GetAttribute("CountToken") ~= token then
				return
			end
			local t = math.clamp((os.clock() - start) / duration, 0, 1)
			local eased = 1 - (1 - t) ^ 3
			label.Text = formatter(from + (to - from) * eased)
			if t >= 1 then
				return
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

function Anim.fade(group: CanvasGroup, to: number, duration: number?)
	return Anim.tween(group, duration or 0.25, { GroupTransparency = to })
end

return Anim
