--!strict
-- Rewards: the 7-day daily login streak and today's playtime reward tiers. The server checks
-- every claim; this panel only shows what it expects and asks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Rewards = require(Shared.Rewards)
local Strings = require(Shared.Strings)

local Kit = require(script.Parent.Parent.Kit)
local Panel = require(script.Parent.Parent.Panel)
local Theme = require(script.Parent.Parent.Theme)

local RewardsPanel = {}

local C = Theme.C
local ENCHANT = utf8.char(0x2728)
local BOOST = utf8.char(0x26A1)

-- Today's playtime as the client estimates it: the last synced value plus time since that sync.
local syncedAt = os.clock()

function RewardsPanel.track(app: any)
	app.State.profileChanged:Connect(function()
		syncedAt = os.clock()
	end)
end

function RewardsPanel.playSeconds(app: any): (number, { number })
	local profile = app.State.profile
	if not profile or profile.play.day ~= Rewards.dayOf(os.time()) then
		return 0, {}
	end
	return profile.play.seconds + (os.clock() - syncedAt), profile.play.claimed
end

-- Is anything claimable right now? (Drives the HUD badge.)
function RewardsPanel.anyReady(app: any): boolean
	local profile = app.State.profile
	if not profile then
		return false
	end
	local now = os.time()
	if Rewards.daily(profile, now).claimable then
		return true
	end
	local seconds, claimed = RewardsPanel.playSeconds(app)
	for tier in Config.PlaytimeRewards do
		if Rewards.tierStatus(tier, seconds, claimed) == "ready" then
			return true
		end
	end
	return false
end

-- Seconds until the next playtime tier unlocks (nil when every tier is unlocked or claimed).
function RewardsPanel.nextUnlock(app: any): number?
	local seconds, claimed = RewardsPanel.playSeconds(app)
	for tier, entry in Config.PlaytimeRewards do
		if Rewards.tierStatus(tier, seconds, claimed) == "locked" then
			return entry.minutes * 60 - seconds
		end
	end
	return nil
end

local function extras(reward: Rewards.Payout): string
	local parts = {}
	if reward.enchants > 0 then
		table.insert(parts, ENCHANT .. "+" .. reward.enchants)
	end
	if reward.boostMinutes > 0 then
		table.insert(parts, BOOST .. Strings.get("boostShort", { n = reward.boostMinutes }))
	end
	return table.concat(parts, " ")
end

type Card = {
	frame: Frame,
	stroke: UIStroke,
	title: TextLabel,
	coins: TextLabel,
	extra: TextLabel,
	status: TextLabel,
	button: Kit.ButtonApi?,
}

function RewardsPanel.new(app: any): Panel.PanelApi
	local panel = Panel.new({
		Parent = app.Gui.panels,
		Title = Strings.get("rewardsTitle"),
		Icon = utf8.char(0x1F381),
		Palette = "Pink",
		Size = Vector2.new(760, 480),
	})
	local body = panel.body
	Kit.list(body, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	Kit.padding(body, 20, 0, 0, 0)

	local function header(order: number): (TextLabel, TextLabel)
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order, Parent = body })
		local title = Kit.text({
			Text = "",
			TextSize = 24,
			Color = C.Navy,
			Stroke = 0,
			Size = UDim2.new(0.5, 0, 1, 0),
			XAlign = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local info = Kit.text({
			Text = "",
			TextSize = 17,
			Color = C.Muted,
			Stroke = 0,
			Size = UDim2.new(0.5, 0, 1, 0),
			Position = UDim2.fromScale(0.5, 0),
			XAlign = Enum.TextXAlignment.Right,
			Parent = row,
		})
		return title, info
	end

	local function cardRow(order: number, height: number): Frame
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height), LayoutOrder = order, Parent = body })
		Kit.list(row, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		return row
	end

	local function card(parent: Frame, width: number, height: number, order: number, withButton: boolean, onClick: (() -> ())?): Card
		local frame = Kit.new("Frame", {
			Name = "Card" .. order,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(width, height),
			LayoutOrder = order,
			Parent = parent,
		}) :: Frame
		Kit.corner(frame, 14)
		local stroke = Kit.stroke(frame, C.PanelLine, 3)
		Kit.gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(222, 240, 255))
		local title = Kit.text({
			Text = "",
			TextSize = 17,
			Color = C.Navy,
			Stroke = 0,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 6),
			Parent = frame,
		})
		local coinRow =
			Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 30), Parent = frame })
		Kit.list(coinRow, Enum.FillDirection.Horizontal, 4)
		local coin = Kit.Icons.coin(20, coinRow)
		coin.LayoutOrder = 1
		local coins =
			Kit.text({ Text = "", TextSize = 18, Size = UDim2.new(0, 0, 1, 0), AutoX = true, Stroke = 2, LayoutOrder = 2, Parent = coinRow })
		local extra = Kit.text({
			Text = "",
			TextSize = 12,
			Color = C.Purple,
			Stroke = 0,
			Wrapped = true,
			Size = UDim2.new(1, -6, 0, 28),
			Position = UDim2.fromOffset(3, 56),
			YAlign = Enum.TextYAlignment.Top,
			Parent = frame,
		})
		local status = Kit.text({
			Text = "",
			TextSize = 16,
			Color = C.GreenDark,
			Stroke = 0,
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.new(1, -4, 0, 4),
			AnchorPoint = Vector2.new(1, 0),
			Parent = frame,
		})
		local button: Kit.ButtonApi? = nil
		if withButton then
			button = Kit.button({
				Name = "Claim",
				Text = "",
				TextSize = 16,
				Palette = "Green",
				Size = UDim2.new(1, -12, 0, 30),
				Position = UDim2.new(0.5, 0, 1, -6),
				AnchorPoint = Vector2.new(0.5, 1),
				Radius = 10,
				Stroke = 2,
				Parent = frame,
				OnClick = onClick,
			})
		end
		return { frame = frame, stroke = stroke, title = title, coins = coins, extra = extra, status = status, button = button }
	end

	local function claimed(text: string)
		app.Sfx.play("Unlock")
		app.Toasts.show(text, "gold", utf8.char(0x1F381))
	end

	local function failed(err: string?)
		app.Sfx.play("Error")
		app.Toasts.show(Strings.get(err or "err.generic"), "bad")
	end

	local refresh: () -> () = function() end

	-- Daily login ------------------------------------------------------------------------------
	local dailyTitle, dailyInfo = header(1)
	local dailyRow = cardRow(2, 96)
	local dayCards: { Card } = {}
	for day in Config.DailyRewards do
		dayCards[day] = card(dailyRow, 96, 92, day, false)
	end
	local claimDaily = Kit.button({
		Name = "ClaimDaily",
		Text = "",
		TextSize = 20,
		Palette = "Gold",
		Size = UDim2.fromOffset(300, 44),
		LayoutOrder = 3,
		Parent = body,
		OnClick = function()
			local result = app.Net.invoke("ClaimDaily")
			if result.ok then
				claimed(Strings.get("rewardGot", { n = Format.commas(result.data.coins) }))
			else
				failed(result.err)
			end
			refresh()
		end,
	})

	-- Playtime ---------------------------------------------------------------------------------
	local spacer = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 4), LayoutOrder = 4, Parent = body })
	local _ = spacer
	local playTitle, playInfo = header(5)
	local playRow = cardRow(6, 128)
	local tierCards: { Card } = {}
	for tier in Config.PlaytimeRewards do
		tierCards[tier] = card(playRow, 112, 124, tier, true, function()
			local result = app.Net.invoke("ClaimPlaytime", { tier = tier })
			if result.ok then
				claimed(Strings.get("rewardGot", { n = Format.commas(result.data.coins) }))
			else
				failed(result.err)
			end
			refresh()
		end)
	end

	refresh = function()
		local profile = app.State.profile
		if not profile then
			return
		end
		local now = os.time()
		panel.setTitle(Strings.get("rewardsTitle"))
		local daily = Rewards.daily(profile, now)
		dailyTitle.Text = Strings.get("dailyTitle")
		dailyInfo.Text = Strings.get("dailyStreak", { n = if daily.claimable then daily.streak - 1 else daily.streak })
			.. "  ·  "
			.. Strings.get("dailyReset", { t = Format.clock(Rewards.untilReset(now)) })
		for day, c in dayCards do
			local reward = Rewards.dailyPayout(day, profile.unlocked)
			c.title.Text = Strings.get("dailyDay", { n = day })
			c.coins.Text = Format.short(reward.coins)
			c.extra.Text = extras(reward)
			local done = day < daily.day or (day == daily.day and not daily.claimable)
			local today = day == daily.day and daily.claimable
			c.status.Text = if done then utf8.char(0x2714) else ""
			c.stroke.Color = if today then C.Gold elseif done then C.Green else C.PanelLine
			c.stroke.Thickness = if today then 4 else 3
			c.frame.BackgroundTransparency = if day > daily.day then 0.35 else 0
		end
		claimDaily.setText(if daily.claimable then Strings.get("dailyClaim", { n = daily.day }) else Strings.get("dailyDone"))
		claimDaily.setPalette(if daily.claimable then "Gold" else "Gray")
		claimDaily.setEnabled(daily.claimable)

		local seconds, claimedTiers = RewardsPanel.playSeconds(app)
		local h, m = Format.hoursMinutes(seconds)
		playTitle.Text = Strings.get("playTitle")
		playInfo.Text = Strings.get("playToday", { h = h, m = m })
		for tier, c in tierCards do
			local entry = Config.PlaytimeRewards[tier]
			local reward = Rewards.playtimePayout(tier, profile.unlocked)
			c.title.Text = Strings.get("playMinutes", { n = entry.minutes })
			c.coins.Text = Format.short(reward.coins)
			c.extra.Text = extras(reward)
			local status = Rewards.tierStatus(tier, seconds, claimedTiers)
			local button = c.button :: Kit.ButtonApi
			if status == "ready" then
				button.button.Visible = true
				button.setText(Strings.get("claim"))
				button.setPalette("Green")
				button.setEnabled(true)
				c.stroke.Color = C.Gold
			elseif status == "claimed" then
				button.button.Visible = false
				c.status.Text = utf8.char(0x2714)
				c.stroke.Color = C.Green
			else
				button.button.Visible = true
				button.setText(Format.clock(entry.minutes * 60 - seconds))
				button.setPalette("Gray")
				button.setEnabled(false)
				c.stroke.Color = C.PanelLine
			end
			if status ~= "claimed" then
				c.status.Text = ""
			end
		end
	end

	panel.onOpen = function()
		refresh()
		task.spawn(function()
			while panel.isOpen do
				task.wait(1)
				if panel.isOpen then
					refresh()
				end
			end
		end)
	end
	app.State.profileChanged:Connect(function()
		if panel.isOpen then
			refresh()
		end
	end)
	app.State.languageChanged:Connect(function()
		task.defer(refresh)
	end)
	return panel
end

return RewardsPanel
