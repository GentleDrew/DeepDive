--!strict
-- Bottom-right HUD stack: the Starter Pack card (with a real countdown for the first
-- Config.StarterOfferHours after a player's first visit) and the Rewards button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)

local Anim = require(script.Parent.Anim)
local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)
local Purchase = require(script.Parent.Purchase)
local Theme = require(script.Parent.Theme)
local RewardsPanel = require(script.Parent.Panels.Rewards)

local RightRail = {}

local C = Theme.C

-- Seconds left on the starter offer, or nil when it should not be advertised.
function RightRail.starterLeft(app: any): number?
	local profile = app.State.profile
	local def = Purchase.find("StarterPack")
	if not profile or not def or def.id <= 0 or app.State.passes.StarterPack or profile.starterPackGranted then
		return nil
	end
	local left = profile.created + Config.StarterOfferHours * 3600 - os.time()
	return if left > 0 then left else nil
end

function RightRail.init(app: any, openRewards: () -> ())
	local rail = Kit.new("Frame", {
		Name = "RightRail",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(184, 240),
		Position = UDim2.new(1, -16, 1, -16),
		AnchorPoint = Vector2.new(1, 1),
		Parent = Gui.hud,
	}) :: Frame
	Kit.list(rail, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)
	if Gui.isTouch() then
		local scale = Instance.new("UIScale")
		scale.Scale = 1.2
		scale.Parent = rail
	end

	-- Starter Pack card -------------------------------------------------------------------------
	local starter = Kit.new("TextButton", {
		Name = "StarterOffer",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(184, 104),
		LayoutOrder = 1,
		Visible = false,
		Parent = rail,
	}) :: TextButton
	Kit.corner(starter, 16)
	Kit.gradient(starter, Theme.Buttons.Green[1], Theme.Buttons.Green[2])
	Kit.stroke(starter, Theme.Buttons.Green[3], 3)
	Kit.neon(starter, C.Gold)
	local ribbon = Kit.new("Frame", {
		BackgroundColor3 = C.Red,
		Size = UDim2.fromOffset(96, 22),
		Position = UDim2.new(0.5, 0, 0, -10),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
		Parent = starter,
	})
	Kit.round(ribbon)
	Kit.stroke(ribbon, C.White, 2)
	local ribbonText = Kit.text({ Text = "", TextSize = 13, Size = UDim2.fromScale(1, 1), ZIndex = 4, Stroke = 1.5, Parent = ribbon })
	Kit.text({
		Text = utf8.char(0x1F381),
		TextSize = 30,
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.fromOffset(6, 16),
		Stroke = 0,
		Parent = starter,
	})
	local starterName = Kit.text({
		Text = "",
		TextSize = 18,
		Size = UDim2.new(1, -52, 0, 22),
		Position = UDim2.fromOffset(46, 18),
		XAlign = Enum.TextXAlignment.Left,
		Stroke = 2,
		StrokeColor = Theme.Buttons.Green[3],
		Parent = starter,
	})
	local starterTimer = Kit.text({
		Text = "",
		TextSize = 14,
		Color = Color3.fromRGB(255, 244, 170),
		Size = UDim2.new(1, -52, 0, 18),
		Position = UDim2.fromOffset(46, 40),
		XAlign = Enum.TextXAlignment.Left,
		Stroke = 1.6,
		StrokeColor = Theme.Buttons.Green[3],
		Parent = starter,
	})
	local starterPrice = Kit.text({
		Text = "",
		TextSize = 20,
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 1, -8),
		AnchorPoint = Vector2.new(0, 1),
		Stroke = 2.2,
		StrokeColor = Theme.Buttons.Green[3],
		Parent = starter,
	})
	starter.Activated:Connect(function()
		if app.Sfx then
			app.Sfx.play("Click")
		end
		Anim.pop(starter, 0.1)
		if not Purchase.prompt("StarterPack", app.State.passes) then
			app.Toasts.show(Strings.get("comingSoon"), "info")
		end
	end)

	-- Rewards button ----------------------------------------------------------------------------
	local rewardsHolder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(84, 104), LayoutOrder = 2, Parent = rail })
	local rewards = Kit.button({
		Name = "RewardsButton",
		Icon = utf8.char(0x1F381),
		IconSize = 34,
		Palette = "Pink",
		Size = UDim2.fromOffset(76, 76),
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Radius = 18,
		Stroke = 2.5,
		Parent = rewardsHolder,
		OnClick = openRewards,
	})
	local content = rewards.button:FindFirstChild("Content") :: Frame?
	if content then
		content.Position = UDim2.fromOffset(0, -9)
	end
	local rewardsLabel = Kit.text({
		Text = "",
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -21),
		ZIndex = 4,
		Stroke = 2,
		StrokeColor = Theme.Buttons.Pink[3],
		Parent = rewards.button,
	})
	local badge = Kit.new("Frame", {
		Name = "Badge",
		BackgroundColor3 = C.Red,
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, -4, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 5,
		Parent = rewards.button,
	})
	Kit.round(badge)
	Kit.stroke(badge, C.White, 2)
	Kit.text({ Text = "!", TextSize = 15, Size = UDim2.fromScale(1, 1), ZIndex = 6, Stroke = 1.5, Parent = badge })
	local nextChip = Kit.pill({ Name = "NextReward", Size = UDim2.fromOffset(76, 22), Outline = 2, Parent = rewardsHolder })
	nextChip.Position = UDim2.new(1, 0, 1, 0)
	nextChip.AnchorPoint = Vector2.new(1, 1)
	local nextLabel = Kit.text({ Text = "", TextSize = 13, Size = UDim2.fromScale(1, 1), Stroke = 1.6, Parent = nextChip })

	local function refresh()
		rewardsLabel.Text = Strings.get("rewardsTitle")
		ribbonText.Text = Strings.get("limited")
		starterName.Text = Strings.get("pass.StarterPack")
		local def = Purchase.find("StarterPack")
		starterPrice.Text = if def then "R$ " .. tostring(def.price) else ""
		local left = RightRail.starterLeft(app)
		starter.Visible = left ~= nil
		if left then
			starterTimer.Text = Strings.get("endsIn", { t = Format.clock(left) })
		end
		local ready = RewardsPanel.anyReady(app)
		if ready ~= badge.Visible then
			badge.Visible = ready
			if ready then
				Anim.pop(badge, 0.6)
			end
		end
		local wait = if ready then nil else RewardsPanel.nextUnlock(app)
		nextChip.Visible = wait ~= nil
		if wait then
			nextLabel.Text = Format.clock(wait)
		end
	end

	-- Phones need the corner for swim controls while in the water.
	RunService.RenderStepped:Connect(function()
		rail.Visible = not (Gui.isTouch() and app.State.dive.swimming)
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
	app.State.languageChanged:Connect(function()
		task.defer(refresh)
	end)
end

return RightRail
