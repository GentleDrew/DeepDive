--!strict
-- Right-hand HUD column, laid out like the left menu rail (one column on desktop; on touch screens
-- a two-wide block kept above Roblox's jump button so it never covers the controls): the limited
-- GOD Shark, the Starter Pack (with a real countdown for the first
-- Config.StarterOfferHours after a player's first visit), Rewards, the group and friend invites.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Operators = require(Shared.Operators)
local Strings = require(Shared.Strings)

local Anim = require(script.Parent.Anim)
local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)
local Purchase = require(script.Parent.Purchase)
local Theme = require(script.Parent.Theme)
local RewardsPanel = require(script.Parent.Panels.Rewards)

local RightRail = {}

local C = Theme.C
local BUTTON = 76
local GAP = 10
local TOUCH_SCALE = if Gui.isTouch() then 1.2 else 1
local MARGIN = 16

-- How far up from the bottom of the screen (in pixels) Roblox's touch jump button reaches: read
-- from the live button when it exists, never less than where Roblox's own layout puts it.
local function jumpReach(): number
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 760)
	local small = math.min(viewport.X, viewport.Y) <= 500
	local reach = if small then 90 else 210
	local touchGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	touchGui = touchGui and touchGui:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	if frame and jump and frame:IsA("GuiObject") and jump:IsA("GuiObject") then
		local bottom = frame.AbsolutePosition.Y + frame.AbsoluteSize.Y
		reach = math.max(reach, bottom - jump.AbsolutePosition.Y)
	end
	return reach
end

type Item = { api: Kit.ButtonApi, label: TextLabel, badge: Frame }

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

-- Opens Roblox's purchase dialog for a Robux item, or says it is not on sale yet.
local function buy(app: any, key: string)
	if not Purchase.prompt(key, app.State.passes) then
		app.Toasts.show(Strings.get("comingSoon"), "info")
	end
end

function RightRail.init(app: any, openRewards: () -> ())
	local rail = Kit.new("Frame", {
		Name = "RightRail",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(BUTTON, BUTTON),
		Position = UDim2.new(1, -MARGIN, 1, -MARGIN),
		AnchorPoint = Vector2.new(1, 1),
		Parent = Gui.hud,
	}) :: Frame
	-- Touch: rows of two filled from the top-right corner (the GOD Shark nearest the edge).
	local touch = TOUCH_SCALE > 1
	local grid = Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(BUTTON, BUTTON),
		CellPadding = UDim2.fromOffset(GAP, GAP + 4),
		FillDirection = if touch then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		StartCorner = if touch then Enum.StartCorner.TopRight else Enum.StartCorner.TopLeft,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = if touch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = rail,
	}) :: UIGridLayout
	if TOUCH_SCALE > 1 then
		local scale = Instance.new("UIScale")
		scale.Scale = TOUCH_SCALE
		scale.Parent = rail
	end

	local items: { Item } = {}

	local function item(name: string, icon: string, palette: string, order: number, onClick: () -> ()): Item
		local api = Kit.button({
			Name = name,
			Icon = icon,
			IconSize = 34,
			Palette = palette,
			Size = UDim2.fromOffset(BUTTON, BUTTON),
			Radius = 18,
			Stroke = 2.5,
			LayoutOrder = order,
			Parent = rail,
			OnClick = onClick,
		})
		local content = api.button:FindFirstChild("Content") :: Frame?
		if content then
			content.Position = UDim2.fromOffset(0, -9)
		end
		local label = Kit.text({
			Text = "",
			TextSize = 15,
			Size = UDim2.new(1, -4, 0, 18),
			Position = UDim2.new(0, 2, 1, -21),
			ZIndex = 4,
			Stroke = 2,
			StrokeColor = (Theme.Buttons[palette] or Theme.Buttons.Blue)[3],
			Parent = api.button,
		})
		label.TextScaled = true
		Kit.new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 9, Parent = label })
		local badge = Kit.new("Frame", {
			Name = "Badge",
			BackgroundColor3 = C.Red,
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.new(1, -4, 0, 4),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = false,
			ZIndex = 5,
			Parent = api.button,
		}) :: Frame
		Kit.round(badge)
		Kit.stroke(badge, C.White, 2)
		Kit.text({ Text = "!", TextSize = 14, Size = UDim2.fromScale(1, 1), ZIndex = 6, Stroke = 1.5, Parent = badge })
		local entry = { api = api, label = label, badge = badge }
		table.insert(items, entry)
		return entry
	end

	local function ribbon(target: Item): TextLabel
		local frame = Kit.new("Frame", {
			Name = "Ribbon",
			BackgroundColor3 = C.Red,
			Size = UDim2.fromOffset(66, 18),
			Position = UDim2.new(0.5, 0, 0, -9),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = 6,
			Parent = target.api.button,
		})
		Kit.round(frame)
		Kit.stroke(frame, C.White, 2)
		return Kit.text({ Text = "", TextSize = 11, Size = UDim2.fromScale(1, 1), ZIndex = 7, Stroke = 1.4, Parent = frame })
	end

	-- Limited GOD Shark: always on sale, glowing and pulsing so it stands out.
	local godShark = item("GodSharkButton", utf8.char(0x1F988), "Cyan", 1, function()
		buy(app, "GodShark")
	end)
	local godRibbon = ribbon(godShark)
	Kit.neon(godShark.api.button, C.Gold)

	local starter = item("StarterOffer", utf8.char(0x1F381), "Green", 2, function()
		buy(app, "StarterPack")
	end)
	local starterRibbon = ribbon(starter)

	local rewards = item("RewardsButton", utf8.char(0x1F381), "Pink", 3, openRewards)

	local group = item("GroupButton", utf8.char(0x1F465), "Blue", 4, function()
		local groupId = Operators.groupId()
		local profile = app.State.profile
		if groupId <= 0 or not profile then
			return
		end
		if profile.groupRewarded then
			app.Toasts.show(Strings.get("groupThanks"), "blue", utf8.char(0x1F465))
			return
		end
		pcall(function()
			GroupService:PromptJoinAsync(groupId)
		end)
		local result = app.Net.invoke("ClaimGroup")
		if result.ok then
			app.Sfx.play("Unlock")
			app.Toasts.show(Strings.get("groupReward", { n = Format.commas(result.data.coins) }), "gold", utf8.char(0x1F465))
		else
			app.Sfx.play("Error")
			app.Toasts.show(Strings.get(result.err or "err.generic"), "bad", utf8.char(0x1F465))
		end
	end)

	local invite = item("InviteButton", utf8.char(0x1F48C), "Purple", 5, function()
		local player = Players.LocalPlayer
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok and can then
			pcall(function()
				SocialService:PromptGameInvite(player)
			end)
		end
	end)

	-- Desktop: one column bottom-right (two on short screens). Touch: a block two wide whose bottom
	-- sits above the jump button, widening to three if the space above it is too short.
	local function layout()
		local visible = 0
		for _, entry in items do
			if entry.api.button.Visible then
				visible += 1
			end
		end
		visible = math.max(visible, 1)
		local canvas = Gui.canvasSize
		local columns, rows
		if touch then
			local bottom = canvas.Y - jumpReach() / Gui.scale - 12
			local room = (bottom - 64) / TOUCH_SCALE
			columns = 2
			rows = math.ceil(visible / columns)
			if rows * BUTTON + (rows - 1) * (GAP + 4) > room then
				columns = 3
				rows = math.ceil(visible / columns)
			end
			grid.FillDirectionMaxCells = columns
			rail.Position = UDim2.new(1, -MARGIN, 0, math.max(bottom, 64))
		else
			local perColumn = if canvas.Y < 660 then 3 else visible
			columns = math.ceil(visible / perColumn)
			rows = math.min(visible, perColumn)
			grid.FillDirectionMaxCells = perColumn
			rail.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
		end
		rail.Size = UDim2.fromOffset(columns * BUTTON + (columns - 1) * GAP, rows * BUTTON + (rows - 1) * (GAP + 4))
	end
	Gui.resized:Connect(layout)

	local function refresh()
		local profile = app.State.profile
		local sharkDef = Purchase.find("GodShark")
		godShark.api.button.Visible = sharkDef ~= nil and sharkDef.id > 0
		godShark.label.Text = if sharkDef then "R$ " .. tostring(sharkDef.price) else ""
		godRibbon.Text = Strings.get("limited")

		local left = RightRail.starterLeft(app)
		starter.api.button.Visible = left ~= nil
		starter.label.Text = if left then Format.clock(left) else ""
		starterRibbon.Text = Strings.get("limited")

		local ready = RewardsPanel.anyReady(app)
		if ready ~= rewards.badge.Visible then
			rewards.badge.Visible = ready
			if ready then
				Anim.pop(rewards.badge, 0.6)
			end
		end
		local wait = if ready then nil else RewardsPanel.nextUnlock(app)
		rewards.label.Text = if wait then Format.clock(wait) else Strings.get("rewardsTitle")

		group.api.button.Visible = Operators.groupId() > 0
		group.badge.Visible = profile ~= nil and not profile.groupRewarded
		group.label.Text = Strings.get("groupButton")
		invite.label.Text = Strings.get("inviteButton")
		layout()
	end

	-- Phones need the corner for swim controls while in the water.
	RunService.RenderStepped:Connect(function()
		rail.Visible = not (Gui.isTouch() and app.State.dive.swimming)
	end)
	task.spawn(function()
		local tick = 0
		while true do
			refresh()
			tick += 1
			if tick % 4 == 0 and godShark.api.button.Visible then
				Anim.pop(godShark.api.button, 0.12)
			end
			task.wait(1)
		end
	end)
	app.State.languageChanged:Connect(function()
		task.defer(refresh)
	end)
end

return RightRail
