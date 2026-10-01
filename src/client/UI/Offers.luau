--!strict
-- Purchase offers: a small card that slides in from the right when an item is relevant
-- (backpack full, blacked out, short on coins) plus an occasional rotating suggestion. Rate
-- limited by Config.OfferGap / OfferRepeat / OfferMaxPerSession, and never over an open panel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)

local Anim = require(script.Parent.Anim)
local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)
local Purchase = require(script.Parent.Purchase)
local Theme = require(script.Parent.Theme)

local Offers = {}

local C = Theme.C
local SHOW_FOR = 14
local WIDTH = 340

-- reason -> { item key, headline string key, icon }
local REASONS: { [string]: { key: string, line: string, icon: string } } = {
	full = { key = "AutoSell", line = "offer.full", icon = utf8.char(0x1F4B8) },
	blackout = { key = "SwiftFins", line = "offer.blackout", icon = utf8.char(0x1F42C) },
	unlock = { key = "UnlockBoost", line = "offer.unlock", icon = utf8.char(0x1F513) },
	starter = { key = "StarterPack", line = "offer.starter", icon = utf8.char(0x1F381) },
	double = { key = "DoubleCoins", line = "offer.double", icon = utf8.char(0x1F4B0) },
	boost = { key = "TimedBoost", line = "offer.boost", icon = utf8.char(0x26A1) },
	eggs = { key = "LuckyEggs", line = "offer.eggs", icon = utf8.char(0x1F340) },
}
local ROTATION = { "starter", "double", "boost", "eggs" }

function Offers.init(app: any, starterLeft: () -> number?)
	local card = Kit.new("Frame", {
		Name = "Offer",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(WIDTH, 132),
		Position = UDim2.new(1, WIDTH + 40, 0.5, -30),
		AnchorPoint = Vector2.new(1, 0.5),
		Visible = false,
		ZIndex = 10,
		Parent = Gui.hud,
	}) :: Frame
	Kit.corner(card, 18)
	Kit.gradient(card, Color3.fromRGB(255, 255, 255), Color3.fromRGB(214, 238, 255))
	Kit.stroke(card, C.Outline, 3)
	if Gui.isTouch() then
		local scale = Instance.new("UIScale")
		scale.Scale = 1.1
		scale.Parent = card
	end
	local icon = Kit.text({
		Text = "",
		TextSize = 46,
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.fromOffset(10, 14),
		Stroke = 0,
		ZIndex = 11,
		Parent = card,
	})
	local line = Kit.text({
		Text = "",
		TextSize = 15,
		Color = C.Pink,
		Stroke = 0,
		Size = UDim2.new(1, -120, 0, 20),
		Position = UDim2.fromOffset(80, 10),
		XAlign = Enum.TextXAlignment.Left,
		ZIndex = 11,
		Parent = card,
	})
	local name = Kit.text({
		Text = "",
		TextSize = 22,
		Color = C.Navy,
		Stroke = 0,
		Size = UDim2.new(1, -96, 0, 26),
		Position = UDim2.fromOffset(80, 30),
		XAlign = Enum.TextXAlignment.Left,
		ZIndex = 11,
		Parent = card,
	})
	local desc = Kit.text({
		Text = "",
		TextSize = 14,
		Color = C.Muted,
		Stroke = 0,
		Wrapped = true,
		Size = UDim2.new(1, -96, 0, 34),
		Position = UDim2.fromOffset(80, 56),
		XAlign = Enum.TextXAlignment.Left,
		YAlign = Enum.TextYAlignment.Top,
		ZIndex = 11,
		Parent = card,
	})

	local current: string? = nil
	local token = 0

	local function hide()
		if not card.Visible then
			return
		end
		token += 1
		local mine = token
		Anim.tween(card, 0.25, { Position = UDim2.new(1, WIDTH + 40, 0.5, -30) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.3, function()
			if mine == token then
				card.Visible = false
			end
		end)
	end

	local buy = Kit.button({
		Name = "Buy",
		Text = "",
		TextSize = 18,
		Palette = "Green",
		Size = UDim2.fromOffset(150, 34),
		Position = UDim2.new(1, -12, 1, -10),
		AnchorPoint = Vector2.new(1, 1),
		Radius = 12,
		Stroke = 2,
		ZIndex = 11,
		Parent = card,
		OnClick = function()
			local key = current
			hide()
			if key and not Purchase.prompt(key, app.State.passes) then
				app.Toasts.show(Strings.get("comingSoon"), "info")
			end
		end,
	})
	buy.button.ZIndex = 11
	local close = Kit.button({
		Name = "Close",
		Text = "X",
		TextSize = 16,
		Palette = "Gray",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -8, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		Radius = 14,
		Stroke = 2,
		ZIndex = 12,
		Parent = card,
		OnClick = hide,
	})
	close.button.ZIndex = 12

	local lastShown = -math.huge
	local lastByKey: { [string]: number } = {}
	local shownCount = 0

	local function eligible(reason: string): boolean
		local spec = REASONS[reason]
		local def = spec and Purchase.find(spec.key)
		if not def or def.id <= 0 or app.State.passes[spec.key] then
			return false
		end
		local profile = app.State.profile
		if not profile then
			return false
		end
		if spec.key == "StarterPack" and profile.starterPackGranted then
			return false
		end
		if spec.key == "TimedBoost" and profile.boostUntil > os.time() then
			return false
		end
		return true
	end

	-- Shows the offer for `reason` if it is relevant and the rate limits allow it.
	function Offers.trigger(reason: string): boolean
		local now = os.clock()
		if
			not eligible(reason)
			or shownCount >= Config.OfferMaxPerSession
			or now - lastShown < Config.OfferGap
			or now - (lastByKey[REASONS[reason].key] or -math.huge) < Config.OfferRepeat
			or app.isUiBlocking()
			or app.State.traveling
		then
			return false
		end
		local spec = REASONS[reason]
		local found, kind = Purchase.find(spec.key)
		local def = found :: Purchase.Def
		lastShown = now
		lastByKey[spec.key] = now
		shownCount += 1
		current = spec.key
		icon.Text = spec.icon
		local left = if spec.key == "StarterPack" then starterLeft() else nil
		line.Text = if left then Strings.get("endsIn", { t = Format.clock(left) }) else Strings.get(spec.line)
		name.Text = Strings.get(tostring(kind) .. "." .. spec.key)
		desc.Text = Strings.get(tostring(kind) .. "." .. spec.key .. ".desc", { n = Config.TimedBoostMinutes })
		buy.setText("R$ " .. tostring(def.price))
		token += 1
		local mine = token
		card.Visible = true
		card.Position = UDim2.new(1, WIDTH + 40, 0.5, -30)
		Anim.tween(card, 0.4, { Position = UDim2.new(1, -16, 0.5, -30) }, Enum.EasingStyle.Back)
		if app.Sfx then
			app.Sfx.play("Open")
		end
		task.delay(SHOW_FOR, function()
			if mine == token then
				hide()
			end
		end)
		return true
	end

	-- The occasional suggestion: first after OfferFirstDelay, then roughly every OfferGap.
	task.spawn(function()
		local index = 0
		task.wait(Config.OfferFirstDelay)
		while true do
			for _ = 1, #ROTATION do
				index = index % #ROTATION + 1
				if Offers.trigger(ROTATION[index]) then
					break
				end
			end
			task.wait(Config.OfferGap + math.random(0, 60))
		end
	end)
end

return Offers
