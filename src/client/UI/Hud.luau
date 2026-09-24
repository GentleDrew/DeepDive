--!strict
-- Heads-up display: coins + boost, world banner with treasure progress, menu buttons, oxygen
-- bar with pressure, backpack, depth gauge and touch swim buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)

local Anim = require(script.Parent.Anim)
local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local State = require(script.Parent.Parent.State)

local Hud = {}

local C = Theme.C
local root = Gui.hud

export type Actions = {
	openWorlds: () -> (),
	openUpgrades: () -> (),
	openPets: () -> (),
	openShop: () -> (),
	openSettings: () -> (),
	swimInput: (string, boolean) -> (),
}

Hud.coinTarget = nil :: GuiObject?
local refreshers: { () -> () } = {}

local function onRefresh(fn: () -> ())
	table.insert(refreshers, fn)
	fn()
end

function Hud.refresh()
	for _, fn in refreshers do
		fn()
	end
end

-- Coins ------------------------------------------------------------------------------------------

local coinPill = Kit.pill({ Name = "Coins", Size = UDim2.fromOffset(250, 58), Position = UDim2.fromOffset(46, 14), Parent = root })
local coinIcon = Kit.Icons.coin(66, root)
coinIcon.Position = UDim2.fromOffset(14, 10)
coinIcon.ZIndex = 3
local coinLabel = Kit.text({
	Text = "0",
	TextSize = 38,
	Size = UDim2.new(1, -60, 1, 0),
	Position = UDim2.fromOffset(46, 0),
	XAlign = Enum.TextXAlignment.Left,
	Stroke = 3,
	Parent = coinPill,
})
Hud.coinTarget = coinIcon
local shownCoins = 0

local boostChip = Kit.new("TextButton", {
	Name = "Boost",
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = Color3.new(1, 1, 1),
	Size = UDim2.fromOffset(170, 36),
	Position = UDim2.fromOffset(60, 78),
	Parent = root,
}) :: TextButton
Kit.round(boostChip)
Kit.gradient(boostChip, Theme.Buttons.Pink[1], Theme.Buttons.Pink[2])
Kit.stroke(boostChip, Theme.Buttons.Pink[3], 3)
local boostLabel = Kit.text({ Text = "x1", TextSize = 20, Size = UDim2.fromScale(1, 1), StrokeColor = Theme.Buttons.Pink[3], Parent = boostChip })

-- World banner -----------------------------------------------------------------------------------

local banner = Kit.pill({
	Name = "WorldBanner",
	Size = UDim2.fromOffset(470, 88),
	Position = UDim2.new(0.5, 0, 0, 12),
	AnchorPoint = Vector2.new(0.5, 0),
	Parent = root,
})
local bannerCorner = banner:FindFirstChildOfClass("UICorner")
if bannerCorner then
	bannerCorner.CornerRadius = UDim.new(0, 24)
end
local worldTitle =
	Kit.text({ Text = "", TextSize = 26, Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 6), Stroke = 3, Parent = banner })
local progress = Kit.progress({
	Size = UDim2.new(1, -40, 0, 28),
	Position = UDim2.new(0.5, 0, 0, 46),
	AnchorPoint = Vector2.new(0.5, 0),
	Colors = { C.Gold, C.Orange },
	TextSize = 18,
	Parent = banner,
})
local chestPulse = false

local function refreshBanner()
	local world = State.world
	local data = Worlds.get(world)
	worldTitle.Text = Strings.get("world", { n = world }) .. "  -  " .. Strings.name(data.name)
	local titleStroke = worldTitle:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Color = Color.darken(Color.hex(data.accent[2]), 0.45)
	end
	local p = State.progress(world)
	local goal = Economy.goal(world)
	chestPulse = false
	if p.cleared then
		progress.setColors(C.Green, C.GreenDark)
		progress.set(1, Strings.get("clearedTag") .. "  " .. utf8.char(0x2714))
	elseif p.sold >= goal then
		progress.setColors(Color.hex("#ffe96b"), Color.hex("#ff9b2e"))
		progress.set(1, Strings.get("findChest"))
		chestPulse = true
	else
		progress.setColors(C.Cyan, C.Blue)
		progress.set(p.sold / goal, Strings.get("treasure", { a = p.sold, b = goal }))
	end
end

-- Menu buttons -----------------------------------------------------------------------------------

local menu = Kit.new("Frame", {
	Name = "Menu",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(96, 480),
	Position = UDim2.new(0, 16, 0.5, 10),
	AnchorPoint = Vector2.new(0, 0.5),
	Parent = root,
})
Kit.list(menu, Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
local badges: { [string]: Frame } = {}
local menuLabels: { [string]: TextLabel } = {}

local function menuButton(key: string, emoji: string, palette: string, order: number, onClick: () -> ())
	local api = Kit.button({
		Name = key,
		Icon = emoji,
		IconSize = 40,
		Palette = palette,
		Size = UDim2.fromOffset(86, 86),
		Radius = 22,
		LayoutOrder = order,
		Parent = menu,
		OnClick = onClick,
	})
	local content = api.button:FindFirstChild("Content") :: Frame?
	if content then
		content.Position = UDim2.fromOffset(0, -9)
	end
	local label = Kit.text({
		Text = "",
		TextSize = 17,
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 1, -24),
		ZIndex = 4,
		StrokeColor = (Theme.Buttons[palette] or Theme.Buttons.Blue)[3],
		Parent = api.button,
	})
	menuLabels[key] = label
	local badge = Kit.new("Frame", {
		Name = "Badge",
		BackgroundColor3 = C.Red,
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, -8, 0, -8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 5,
		Parent = api.button,
	})
	Kit.round(badge)
	Kit.stroke(badge, C.White, 3)
	Kit.text({ Text = "!", TextSize = 18, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = badge })
	badges[key] = badge
	return api
end

Hud.menuButtons = {} :: { [string]: Kit.ButtonApi }

function Hud.setBadge(key: string, visible: boolean)
	local badge = badges[key]
	if badge and badge.Visible ~= visible then
		badge.Visible = visible
		if visible then
			Anim.pop(badge, 0.6)
		end
	end
end

-- Dive readouts ----------------------------------------------------------------------------------

local dive = Kit.new("Frame", {
	Name = "Dive",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(700, 110),
	Position = UDim2.new(0.5, 0, 1, -18),
	AnchorPoint = Vector2.new(0.5, 1),
	Parent = root,
})
local oxygenBar = Kit.progress({
	Size = UDim2.fromOffset(460, 44),
	Position = UDim2.new(0, 70, 1, -8),
	AnchorPoint = Vector2.new(0, 1),
	Colors = { C.Oxygen, C.OxygenDeep },
	TextSize = 24,
	Parent = dive,
})
oxygenBar.label.Position = UDim2.fromOffset(0, 0)
local bubble = Kit.Icons.bubble(64, dive)
bubble.Position = UDim2.new(0, 38, 1, 0)
bubble.AnchorPoint = Vector2.new(0, 1)
bubble.ZIndex = 3
local pressureChip = Kit.pill({
	Name = "Pressure",
	Size = UDim2.fromOffset(190, 32),
	Position = UDim2.new(0, 100, 1, -58),
	AnchorPoint = Vector2.new(0, 1),
	Parent = dive,
})
local pressureLabel = Kit.text({ Text = "", TextSize = 18, Size = UDim2.fromScale(1, 1), Parent = pressureChip })
pressureChip.Visible = false
local cargoChip = Kit.pill({
	Name = "Cargo",
	Size = UDim2.fromOffset(150, 52),
	Position = UDim2.new(0, 548, 1, -4),
	AnchorPoint = Vector2.new(0, 1),
	Parent = dive,
})
local bag = Kit.Icons.bag(50, cargoChip)
bag.Position = UDim2.fromOffset(6, 0)
local cargoLabel = Kit.text({
	Text = "0/5",
	TextSize = 28,
	Size = UDim2.new(1, -60, 1, 0),
	Position = UDim2.fromOffset(56, 0),
	XAlign = Enum.TextXAlignment.Left,
	Parent = cargoChip,
})
local lowLabel = Kit.text({
	Text = "",
	TextSize = 30,
	Color = Color.hex("#ffd0d4"),
	Size = UDim2.fromOffset(460, 36),
	Position = UDim2.new(0, 70, 1, -104),
	AnchorPoint = Vector2.new(0, 1),
	Stroke = 3,
	StrokeColor = C.RedDark,
	Parent = dive,
})

-- Depth gauge ------------------------------------------------------------------------------------

local gauge = Kit.new("Frame", {
	Name = "Depth",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(120, 360),
	Position = UDim2.new(1, -20, 0.5, 20),
	AnchorPoint = Vector2.new(1, 0.5),
	Parent = root,
})
local track = Kit.new("Frame", {
	BackgroundColor3 = C.Ink,
	BackgroundTransparency = 0.3,
	Size = UDim2.new(0, 34, 1, -60),
	Position = UDim2.new(1, -8, 0, 30),
	AnchorPoint = Vector2.new(1, 0),
	Parent = gauge,
})
Kit.round(track)
Kit.stroke(track, C.Outline, 3)
local trackFill = Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 0), Parent = track })
Kit.round(trackFill)
local trackGradient = Kit.gradient(trackFill, C.Cyan, C.DeepBlue)
local marker = Kit.pill({
	Name = "Marker",
	Size = UDim2.fromOffset(92, 34),
	Position = UDim2.new(0, -6, 0, 0),
	AnchorPoint = Vector2.new(1, 0.5),
	Parent = track,
})
local markerLabel = Kit.text({ Text = "0m", TextSize = 20, Size = UDim2.fromScale(1, 1), Parent = marker })
local gaugeTop = Kit.text({
	Text = "0m",
	TextSize = 16,
	Size = UDim2.fromOffset(80, 20),
	Position = UDim2.new(1, 16, 0, 4),
	AnchorPoint = Vector2.new(1, 0),
	Parent = gauge,
})
local gaugeBottom = Kit.text({
	Text = "",
	TextSize = 16,
	Size = UDim2.fromOffset(80, 20),
	Position = UDim2.new(1, 16, 1, -4),
	AnchorPoint = Vector2.new(1, 1),
	Parent = gauge,
})

-- Touch swim buttons ------------------------------------------------------------------------------

local touchPad = Kit.new("Frame", {
	Name = "SwimPad",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(260, 260),
	Position = UDim2.new(1, -24, 1, -150),
	AnchorPoint = Vector2.new(1, 1),
	Visible = false,
	Parent = root,
})
local touchButtons: { [string]: Kit.ButtonApi } = {}

local memoryLabel = Kit.text({
	Text = "",
	TextSize = 16,
	Color = Color.hex("#ffe08a"),
	Size = UDim2.fromOffset(420, 22),
	Position = UDim2.new(0, 16, 1, -8),
	AnchorPoint = Vector2.new(0, 1),
	XAlign = Enum.TextXAlignment.Left,
	Parent = root,
})

-- Wiring -----------------------------------------------------------------------------------------

function Hud.init(actions: Actions)
	Hud.menuButtons.worlds = menuButton("worlds", utf8.char(0x1F30D), "Blue", 1, actions.openWorlds)
	Hud.menuButtons.upgrades = menuButton("upgrades", utf8.char(0x1F93F), "Orange", 2, actions.openUpgrades)
	Hud.menuButtons.pets = menuButton("pets", utf8.char(0x1F43E), "Pink", 3, actions.openPets)
	Hud.menuButtons.shop = menuButton("shop", utf8.char(0x1F6D2), "Green", 4, actions.openShop)
	Hud.menuButtons.settings = menuButton("settings", utf8.char(0x2699) .. utf8.char(0xFE0F), "Gray", 5, actions.openSettings)
	boostChip.Activated:Connect(actions.openPets)

	local function padButton(key: string, text: string, palette: string, size: number, position: UDim2)
		local api = Kit.button({
			Name = key,
			Text = text,
			TextSize = if size > 100 then 26 else 22,
			Palette = palette,
			Size = UDim2.fromOffset(size, size),
			Position = position,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Radius = math.floor(size / 2),
			Parent = touchPad,
		})
		api.button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				actions.swimInput(key, true)
			end
		end)
		api.button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				actions.swimInput(key, false)
			end
		end)
		touchButtons[key] = api
	end
	padButton("dash", "", "Cyan", 118, UDim2.fromScale(0.34, 0.62))
	padButton("up", "", "Green", 88, UDim2.fromScale(0.78, 0.3))
	padButton("down", "", "Purple", 88, UDim2.fromScale(0.78, 0.78))

	onRefresh(function()
		for key, label in menuLabels do
			label.Text = Strings.get("menu." .. key)
		end
		touchButtons.dash.setText(Strings.get("dash"))
		touchButtons.up.setText(Strings.get("up"))
		touchButtons.down.setText(Strings.get("down"))
		memoryLabel.Text = if State.memory then Strings.get("studioSave") else ""
		refreshBanner()
	end)

	State.profileChanged:Connect(function()
		local profile = State.profile
		if not profile then
			return
		end
		if profile.coins > shownCoins and shownCoins > 0 then
			Anim.count(coinLabel, shownCoins, profile.coins, 0.8, Format.commas)
			Anim.pop(coinPill, 0.08)
		else
			coinLabel.Text = Format.commas(profile.coins)
		end
		shownCoins = profile.coins
		boostLabel.Text = utf8.char(0x1F43E) .. " " .. Format.multiplier(State.multiplier())
		memoryLabel.Text = if State.memory then Strings.get("studioSave") else ""
		refreshBanner()
	end)
	State.worldChanged:Connect(refreshBanner)
	State.languageChanged:Connect(Hud.refresh)
end

function Hud.bumpCargo()
	Anim.pop(cargoChip, 0.2)
end

function Hud.flashFull()
	Anim.shake(cargoChip, 8)
	cargoChip.BackgroundColor3 = C.Red
	task.delay(0.4, function()
		cargoChip.BackgroundColor3 = C.Navy
	end)
end

-- Per-frame readouts driven by State.dive.
local diveAlpha = 0
local lowPulse = 0
RunService.RenderStepped:Connect(function(dt: number)
	local d = State.dive
	local world = State.world
	local showDive = d.inWater or d.active
	diveAlpha += ((if showDive then 1 else 0) - diveAlpha) * math.clamp(dt * 6, 0, 1)
	dive.Visible = diveAlpha > 0.02
	gauge.Visible = diveAlpha > 0.02
	dive.Position = UDim2.new(0.5, 0, 1, -18 + (1 - diveAlpha) * 140)
	gauge.Position = UDim2.new(1, -20 + (1 - diveAlpha) * 160, 0.5, 20)

	local max = math.max(1, d.max)
	local ratio = math.clamp(d.oxygen / max, 0, 1)
	oxygenBar.fill.Size = UDim2.fromScale(ratio, 1)
	oxygenBar.fill.Visible = ratio > 0.01
	oxygenBar.label.Text = if d.active then Format.seconds(d.oxygen) else Format.seconds(max)
	local drain = Economy.oxygenDrain(world, math.max(0, d.depth))
	if d.active and drain >= 1.3 then
		pressureChip.Visible = true
		pressureLabel.Text = Strings.get("pressure", { x = Format.multiplier(drain) })
	else
		pressureChip.Visible = false
	end
	if d.active and ratio <= Config.Dive.OxygenDanger then
		lowPulse += dt * 8
		oxygenBar.setColors(C.Danger, C.RedDark)
		lowLabel.Text = Strings.get("lowOxygen")
		lowLabel.TextTransparency = 0.25 - math.sin(lowPulse) * 0.25
	elseif d.active and ratio <= Config.Dive.OxygenWarn then
		oxygenBar.setColors(C.Orange, C.RedDark)
		lowLabel.Text = ""
	else
		oxygenBar.setColors(C.Oxygen, C.OxygenDeep)
		lowLabel.Text = ""
	end

	local capacity = State.capacity()
	cargoLabel.Text = if d.cargo >= capacity then Strings.get("full") else string.format("%d/%d", d.cargo, capacity)
	local cargoStroke = cargoLabel:FindFirstChildOfClass("UIStroke")
	if cargoStroke then
		cargoStroke.Color = if d.cargo >= capacity then C.RedDark else C.Ink
	end

	local maxDepth = Economy.depthStuds(world)
	local depthRatio = math.clamp(d.depth / maxDepth, 0, 1)
	trackFill.Size = UDim2.fromScale(1, depthRatio)
	marker.Position = UDim2.new(0, -6, depthRatio, 0)
	markerLabel.Text = tostring(Economy.displayMeters(world, math.max(0, d.depth))) .. "m"
	gaugeBottom.Text = tostring(Worlds.get(world).meters) .. "m"
	gaugeTop.Text = "0m"
	trackGradient.Color = ColorSequence.new(Color.hex(Worlds.get(world).water), Color.darken(Color.hex(Worlds.get(world).water), 0.6))

	touchPad.Visible = Gui.isTouch() and d.swimming

	local bannerScale = Anim.scaleOf(banner)
	if chestPulse then
		bannerScale.Scale = 1 + math.sin(os.clock() * 5) * 0.03
	elseif bannerScale.Scale ~= 1 then
		bannerScale.Scale = 1
	end
end)

return Hud
