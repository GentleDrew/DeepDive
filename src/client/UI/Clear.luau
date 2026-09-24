--!strict
-- "WORLD CLEARED!" celebration with the Ancient Chest, reward and the next-world unlock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)

local Anim = require(script.Parent.Anim)
local Effects = require(script.Parent.Effects)
local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Viewport = require(script.Parent.Viewport)

local Clear = {}

local C = Theme.C

export type ClearData = { world: number, reward: number, nextWorld: number?, unlockCost: number?, all: boolean? }

-- onUnlock(world, travel) pays the next world's unlock fee and returns true on success.
function Clear.show(data: ClearData, onUnlock: (number, boolean) -> boolean, sfx: (string) -> ())
	local root = Kit.new("Frame", {
		Name = "Clear",
		BackgroundColor3 = Color3.fromRGB(6, 16, 34),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 85,
		Parent = Gui.overlay,
	}) :: Frame
	Anim.tween(root, 0.35, { BackgroundTransparency = 0.3 })
	sfx("Clear")
	Effects.confetti(150)

	local card = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(620, 470),
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 86,
		Parent = root,
	})
	Kit.corner(card, 26)
	Kit.stroke(card, C.Outline, 4)
	Kit.gradient(card, Color3.fromRGB(255, 252, 235), Color3.fromRGB(255, 226, 150))
	Anim.appear(card, 0.5)

	local ribbon = Kit.new("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 60, 0, 84),
		Position = UDim2.new(0.5, 0, 0, -40),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 88,
		Parent = card,
	})
	Kit.corner(ribbon, 24)
	Kit.gradient(ribbon, Theme.Buttons.Gold[1], Theme.Buttons.Gold[2])
	Kit.stroke(ribbon, Theme.Buttons.Gold[3], 4)
	Kit.text({
		Text = Strings.get("worldCleared"),
		TextSize = 50,
		Size = UDim2.fromScale(1, 1),
		Stroke = 4,
		StrokeColor = Theme.Buttons.Gold[3],
		ZIndex = 89,
		Parent = ribbon,
	})

	local view = Viewport.new(card, UDim2.fromOffset(240, 200), UDim2.new(0.5, 0, 0, 50), Vector2.new(0.5, 0))
	view.setModel(Viewport.chest(data.world))
	view.setSpin(true)

	local worldData = Worlds.get(data.world)
	Kit.text({
		Text = Strings.get("world", { n = data.world }) .. "  -  " .. Strings.name(worldData.name),
		TextSize = 26,
		Color = C.Navy,
		Stroke = 0,
		Size = UDim2.new(1, -20, 0, 32),
		Position = UDim2.new(0.5, 0, 0, 252),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 87,
		Parent = card,
	})

	local rewardRow =
		Kit.pill({ Size = UDim2.fromOffset(300, 58), Position = UDim2.new(0.5, 0, 0, 292), AnchorPoint = Vector2.new(0.5, 0), Parent = card })
	local coin = Kit.Icons.coin(46, rewardRow)
	coin.Position = UDim2.fromOffset(8, 6)
	local rewardLabel = Kit.text({
		Text = "+0",
		TextSize = 34,
		Size = UDim2.new(1, -64, 1, 0),
		Position = UDim2.fromOffset(60, 0),
		XAlign = Enum.TextXAlignment.Left,
		Parent = rewardRow,
	})
	Anim.count(rewardLabel, 0, data.reward, 1.2, function(n)
		return "+" .. Format.commas(n)
	end)

	local subText = if data.all then Strings.get("allCleared") elseif data.nextWorld then Strings.get("unlockReady", { n = data.nextWorld }) else ""
	Kit.text({
		Text = subText,
		TextSize = 26,
		Color = C.GreenDark,
		Stroke = 0,
		Size = UDim2.new(1, -20, 0, 32),
		Position = UDim2.new(0.5, 0, 0, 356),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 87,
		Parent = card,
	})

	local buttons = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -40, 0, 64),
		Position = UDim2.new(0.5, 0, 1, -18),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 87,
		Parent = card,
	})
	Kit.list(buttons, Enum.FillDirection.Horizontal, 16)

	local function close()
		Anim.tween(root, 0.25, { BackgroundTransparency = 1 })
		Anim.tween(Anim.scaleOf(card), 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In).Completed:Once(function()
			root:Destroy()
		end)
	end
	if data.nextWorld then
		local cost = data.unlockCost or 0
		local unlock = Kit.button({
			Text = Strings.get("unlockButton", { n = Format.short(cost) }),
			TextSize = 24,
			Palette = "Green",
			Size = UDim2.fromOffset(280, 60),
			LayoutOrder = 1,
			Parent = buttons,
			OnClick = function()
				if onUnlock(data.nextWorld :: number, true) then
					close()
				end
			end,
		})
		local coinIcon = Kit.Icons.coin(30, unlock.button:FindFirstChild("Content") :: Instance)
		coinIcon.LayoutOrder = 0
		Kit.button({
			Text = Strings.get("stay"),
			TextSize = 24,
			Palette = "Gray",
			Size = UDim2.fromOffset(200, 60),
			LayoutOrder = 2,
			Parent = buttons,
			OnClick = close,
		})
	else
		Kit.button({
			Text = Strings.get("continue"),
			TextSize = 26,
			Palette = "Blue",
			Size = UDim2.fromOffset(250, 60),
			LayoutOrder = 1,
			Parent = buttons,
			OnClick = close,
		})
	end
end

return Clear
