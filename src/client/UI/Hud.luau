--!strict
-- Heads-up display, kept small and out of the way:
--   top-left     wallet (coins with a "+" shop shortcut, pet boost)
--   top-centre   slim world chip with treasure progress (hidden while diving)
--   left         menu rail
--   bottom       one dive bar while in the water: oxygen, depth, backpack
-- Touch devices also get swim buttons in the bottom-right corner.

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
local MARGIN = 16
-- Touch screens get the HUD groups 20% bigger (each scales from its own anchor corner).
local TOUCH_SCALE = if Gui.isTouch() then 1.2 else 1

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

-- Wallet -----------------------------------------------------------------------------------------

local wallet = Kit.new("Frame", {
	Name = "Wallet",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(206, 84),
	Position = UDim2.fromOffset(MARGIN, 12),
	Parent = root,
})
local coinPill = Kit.pill({ Name = "Coins", Size = UDim2.fromOffset(206, 44), Outline = 2.5, Parent = wallet })
local coinIcon = Kit.Icons.coin(34, coinPill)
coinIcon.Position = UDim2.new(0, 5, 0.5, 0)
coinIcon.AnchorPoint = Vector2.new(0, 0.5)
coinIcon.ZIndex = 3
local coinLabel = Kit.text({
	Text = "0",
	TextSize = 26,
	Size = UDim2.new(1, -86, 1, 0),
	Position = UDim2.fromOffset(46, 0),
	XAlign = Enum.TextXAlignment.Left,
	Stroke = 2.5,
	Parent = coinPill,
})
Hud.coinTarget = coinIcon
local shownCoins = 0
local addCoins = Kit.button({
	Name = "AddCoins",
	Text = "+",
	TextSize = 24,
	Palette = "Green",
	Size = UDim2.fromOffset(32, 32),
	Position = UDim2.new(1, -6, 0.5, 0),
	AnchorPoint = Vector2.new(1, 0.5),
	Radius = 16,
	Stroke = 2,
	Parent = coinPill,
})

local boostChip = Kit.new("TextButton", {
	Name = "Boost",
	Text = "",
	AutoButtonColor = false,
	BackgroundColor3 = Color3.new(1, 1, 1),
	Size = UDim2.fromOffset(122, 30),
	Position = UDim2.fromOffset(10, 52),
	Parent = wallet,
}) :: TextButton
Kit.round(boostChip)
Kit.gradient(boostChip, Theme.Buttons.Pink[1], Theme.Buttons.Pink[2])
Kit.stroke(boostChip, Theme.Buttons.Pink[3], 2.5)
local boostLabel =
	Kit.text({ Text = "x1", TextSize = 16, Size = UDim2.fromScale(1, 1), Stroke = 2, StrokeColor = Theme.Buttons.Pink[3], Parent = boostChip })

-- World chip -------------------------------------------------------------------------------------

local banner = Kit.pill({
	Name = "WorldBanner",
	Size = UDim2.fromOffset(300, 52),
	Position = UDim2.new(0.5, 0, 0, 10),
	AnchorPoint = Vector2.new(0.5, 0),
	Transparency = 0.3,
	Outline = 2.5,
	Parent = root,
})
local worldTitle =
	Kit.text({ Text = "", TextSize = 18, Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 4), Stroke = 2, Parent = banner })
local progress = Kit.progress({
	Size = UDim2.new(1, -28, 0, 17),
	Position = UDim2.new(0.5, 0, 0, 28),
	AnchorPoint = Vector2.new(0.5, 0),
	Colors = { C.Gold, C.Orange },
	TextSize = 13,
	Outline = 2,
	LabelStroke = 1.6,
	Parent = banner,
})
local chestPulse = false

local function refreshBanner()
	local world = State.world
	local data = Worlds.get(world)
	worldTitle.Text = Strings.get("world", { n = world }) .. "  ·  " .. Strings.name(data.name)
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

-- Menu rail --------------------------------------------------------------------------------------

local MENU_BUTTON = 64
local MENU_GAP = 10
local menu = Kit.new("Frame", {
	Name = "Menu",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(MENU_BUTTON + 4, 5 * MENU_BUTTON + 4 * MENU_GAP),
	Position = UDim2.new(0, MARGIN, 0.5, if TOUCH_SCALE > 1 then 42 else 30),
	AnchorPoint = Vector2.new(0, 0.5),
	Parent = root,
})
Kit.list(menu, Enum.FillDirection.Vertical, MENU_GAP, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
local badges: { [string]: Frame } = {}
local menuLabels: { [string]: TextLabel } = {}

local function menuButton(key: string, emoji: string, palette: string, order: number, onClick: () -> ())
	local api = Kit.button({
		Name = key,
		Icon = emoji,
		IconSize = 28,
		Palette = palette,
		Size = UDim2.fromOffset(MENU_BUTTON, MENU_BUTTON),
		Radius = 16,
		Stroke = 2.5,
		LayoutOrder = order,
		Parent = menu,
		OnClick = onClick,
	})
	local content = api.button:FindFirstChild("Content") :: Frame?
	if content then
		content.Position = UDim2.fromOffset(0, -8)
	end
	local label = Kit.text({
		Text = "",
		TextSize = 13,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -18),
		ZIndex = 4,
		Stroke = 2,
		StrokeColor = (Theme.Buttons[palette] or Theme.Buttons.Blue)[3],
		Parent = api.button,
	})
	menuLabels[key] = label
	local badge = Kit.new("Frame", {
		Name = "Badge",
		BackgroundColor3 = C.Red,
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, -4, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 5,
		Parent = api.button,
	})
	Kit.round(badge)
	Kit.stroke(badge, C.White, 2)
	Kit.text({ Text = "!", TextSize = 14, Size = UDim2.fromScale(1, 1), ZIndex = 6, Stroke = 1.5, Parent = badge })
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

-- Dive bar ---------------------------------------------------------------------------------------

local dive = Kit.new("Frame", {
	Name = "Dive",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(560, 88),
	Position = UDim2.new(0.5, 0, 1, -14),
	AnchorPoint = Vector2.new(0.5, 1),
	Parent = root,
})
local oxygenBar = Kit.progress({
	Size = UDim2.fromOffset(250, 28),
	Position = UDim2.new(0, 34, 1, -4),
	AnchorPoint = Vector2.new(0, 1),
	Colors = { C.Oxygen, C.OxygenDeep },
	TextSize = 18,
	Outline = 2.5,
	LabelStroke = 2,
	Parent = dive,
})
local bubble = Kit.Icons.bubble(42, dive)
bubble.Position = UDim2.new(0, 4, 1, 3)
bubble.AnchorPoint = Vector2.new(0, 1)
bubble.ZIndex = 3

local depthChip = Kit.pill({
	Name = "Depth",
	Size = UDim2.fromOffset(136, 36),
	Position = UDim2.new(0, 296, 1, 0),
	AnchorPoint = Vector2.new(0, 1),
	Outline = 2.5,
	Parent = dive,
})
local depthRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = depthChip })
Kit.list(depthRow, Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
Kit.text({ Text = utf8.char(0x1F30A), TextSize = 17, Size = UDim2.fromOffset(22, 22), Stroke = 0, LayoutOrder = 1, Parent = depthRow })
local depthLabel =
	Kit.text({ Text = "0m", TextSize = 19, Size = UDim2.new(0, 0, 1, 0), AutoX = true, Stroke = 2, LayoutOrder = 2, Parent = depthRow })
local depthMax = Kit.text({
	Text = "",
	TextSize = 13,
	Color = Color.hex("#c4dcf2"),
	Size = UDim2.new(0, 0, 1, 0),
	AutoX = true,
	Stroke = 1.6,
	LayoutOrder = 3,
	Parent = depthRow,
})

local cargoChip = Kit.pill({
	Name = "Cargo",
	Size = UDim2.fromOffset(118, 36),
	Position = UDim2.new(0, 442, 1, 0),
	AnchorPoint = Vector2.new(0, 1),
	Outline = 2.5,
	Parent = dive,
})
local bag = Kit.Icons.bag(32, cargoChip)
bag.Position = UDim2.new(0, 6, 0.5, 0)
bag.AnchorPoint = Vector2.new(0, 0.5)
local cargoLabel = Kit.text({
	Text = "0/5",
	TextSize = 20,
	Size = UDim2.new(1, -48, 1, 0),
	Position = UDim2.fromOffset(42, 0),
	XAlign = Enum.TextXAlignment.Left,
	Stroke = 2,
	Parent = cargoChip,
})

local pressureChip = Kit.pill({
	Name = "Pressure",
	Size = UDim2.fromOffset(150, 24),
	Position = UDim2.new(0, 58, 1, -40),
	AnchorPoint = Vector2.new(0, 1),
	Outline = 2,
	Parent = dive,
})
local pressureLabel = Kit.text({ Text = "", TextSize = 14, Size = UDim2.fromScale(1, 1), Stroke = 1.6, Parent = pressureChip })
pressureChip.Visible = false
local lowLabel = Kit.text({
	Text = "",
	TextSize = 22,
	Color = Color.hex("#ffd0d4"),
	Size = UDim2.fromOffset(300, 28),
	Position = UDim2.new(0, 34, 1, -68),
	AnchorPoint = Vector2.new(0, 1),
	Stroke = 2.5,
	StrokeColor = C.RedDark,
	Parent = dive,
})

-- Touch swim buttons ------------------------------------------------------------------------------

local touchPad = Kit.new("Frame", {
	Name = "SwimPad",
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(260, 260),
	-- Roblox hides its jump button while the swim controller has Jumping disabled, so the pad
	-- takes that bottom-right corner.
	Position = UDim2.new(1, -12, 1, -12),
	AnchorPoint = Vector2.new(1, 1),
	Visible = false,
	Parent = root,
})
local touchButtons: { [string]: Kit.ButtonApi } = {}

if TOUCH_SCALE > 1 then
	for _, group in { wallet, menu, dive } :: { GuiObject } do
		local scale = Instance.new("UIScale")
		scale.Name = "TouchScale"
		scale.Scale = TOUCH_SCALE
		scale.Parent = group
	end
end

local memoryLabel = Kit.text({
	Text = "",
	TextSize = 14,
	Color = Color.hex("#ffe08a"),
	Size = UDim2.fromOffset(420, 18),
	Position = UDim2.new(0, MARGIN, 1, -8),
	AnchorPoint = Vector2.new(0, 1),
	XAlign = Enum.TextXAlignment.Left,
	Stroke = 2,
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
	addCoins.button.Activated:Connect(actions.openShop)

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
	dive.Position = UDim2.new(0.5, 0, 1, -14 + (1 - diveAlpha) * 120)
	-- The world chip steps aside while diving so the view stays clear.
	banner.Visible = diveAlpha < 0.5

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

	depthLabel.Text = tostring(Economy.displayMeters(world, math.max(0, d.depth))) .. "m"
	depthMax.Text = "/ " .. tostring(Worlds.get(world).meters) .. "m"

	touchPad.Visible = Gui.isTouch() and d.swimming

	-- The world chip's one UIScale carries both the touch size and the chest pulse.
	local bannerScale = Anim.scaleOf(banner)
	if chestPulse then
		bannerScale.Scale = TOUCH_SCALE * (1 + math.sin(os.clock() * 5) * 0.03)
	elseif bannerScale.Scale ~= TOUCH_SCALE then
		bannerScale.Scale = TOUCH_SCALE
	end
end)

return Hud
