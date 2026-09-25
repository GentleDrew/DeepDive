--!strict
-- Robux shop: game passes and coin packs. Items whose id is 0 show "Coming Soon".

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)

local Kit = require(script.Parent.Parent.Kit)
local Panel = require(script.Parent.Parent.Panel)
local Theme = require(script.Parent.Parent.Theme)

local ShopPanel = {}

local C = Theme.C

local ICONS = {
	DoubleCoins = utf8.char(0x1F4B0),
	LuckyEggs = utf8.char(0x1F340),
	PetSlots = utf8.char(0x1F43E),
	SwiftFins = utf8.char(0x1F42C),
	CoinsSmall = utf8.char(0x1FA99),
	CoinsMedium = utf8.char(0x1F4B0),
	CoinsLarge = utf8.char(0x1F451),
	LuckyEnchant = utf8.char(0x2728),
	VIPAura = utf8.char(0x1F451),
	UnlockBoost = utf8.char(0x1F513),
	AutoSell = utf8.char(0x1F4B8),
	SwimTrail = utf8.char(0x2728),
	BorderSilver = utf8.char(0x1F5BC) .. utf8.char(0xFE0F),
	BorderGold = utf8.char(0x1F5BC) .. utf8.char(0xFE0F),
	StarterPack = utf8.char(0x1F381),
	InstantUnlock = utf8.char(0x1F513),
	TimedBoost = utf8.char(0x26A1),
	PetReroll = utf8.char(0x1F3B2),
	GuaranteedMutation = utf8.char(0x1F52E),
	BackpackFill = utf8.char(0x1F392),
}

type Card = { key: string, kind: string, name: TextLabel, desc: TextLabel, buy: Kit.ButtonApi, def: any }

function ShopPanel.new(app: any): Panel.PanelApi
	local panel = Panel.new({
		Parent = app.Gui.panels,
		Title = Strings.get("shopTitle"),
		Icon = utf8.char(0x1F6D2),
		Palette = "Green",
		Size = Vector2.new(860, 540),
	})
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -10),
		Position = UDim2.fromOffset(0, 14),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 10,
		ScrollBarImageColor3 = C.NavySoft,
		BorderSizePixel = 0,
		Parent = panel.body,
	}) :: ScrollingFrame
	Kit.padding(scroll, 8, 16, 16, 8)
	Kit.list(scroll, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	local cards: { Card } = {}
	local headers: { [string]: TextLabel } = {}

	local function section(key: string, order: number): Frame
		headers[key] = Kit.text({
			Text = "",
			TextSize = 26,
			Color = C.Navy,
			Stroke = 0,
			Size = UDim2.new(1, 0, 0, 34),
			XAlign = Enum.TextXAlignment.Left,
			LayoutOrder = order,
			Parent = scroll,
		})
		local grid = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order + 1,
			Parent = scroll,
		})
		Kit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(250, 210),
			CellPadding = UDim2.fromOffset(14, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Parent = grid,
		})
		return grid
	end

	local function card(parent: Frame, def: any, kind: string, order: number)
		local color = Color.hex(def.color)
		local frame = Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), LayoutOrder = order, Parent = parent })
		Kit.corner(frame, 20)
		Kit.gradient(frame, Color.lighten(color, 0.45), color, 100)
		Kit.stroke(frame, Color.darken(color, 0.55), 4)
		Kit.text({
			Text = ICONS[def.key] or utf8.char(0x2B50),
			TextSize = 54,
			Size = UDim2.new(1, 0, 0, 64),
			Position = UDim2.fromOffset(0, 8),
			Stroke = 0,
			Parent = frame,
		})
		local name = Kit.text({
			Text = "",
			TextSize = 24,
			Size = UDim2.new(1, -12, 0, 28),
			Position = UDim2.new(0.5, 0, 0, 74),
			AnchorPoint = Vector2.new(0.5, 0),
			StrokeColor = Color.darken(color, 0.6),
			Parent = frame,
		})
		local desc = Kit.text({
			Text = "",
			TextSize = 16,
			Wrapped = true,
			Size = UDim2.new(1, -20, 0, 42),
			Position = UDim2.new(0.5, 0, 0, 104),
			AnchorPoint = Vector2.new(0.5, 0),
			StrokeColor = Color.darken(color, 0.6),
			Stroke = 2,
			Parent = frame,
		})
		local buy = Kit.button({
			Text = "",
			TextSize = 22,
			Palette = "Green",
			Size = UDim2.new(1, -30, 0, 48),
			Position = UDim2.new(0.5, 0, 1, -12),
			AnchorPoint = Vector2.new(0.5, 1),
			Parent = frame,
			OnClick = function()
				if def.id <= 0 then
					app.Toasts.show(Strings.get("comingSoon"), "info")
					return
				end
				local player = Players.LocalPlayer
				if kind == "pass" then
					if app.State.passes[def.key] then
						return
					end
					MarketplaceService:PromptGamePassPurchase(player, def.id)
				else
					MarketplaceService:PromptProductPurchase(player, def.id)
				end
			end,
		})
		table.insert(cards, { key = def.key, kind = kind, name = name, desc = desc, buy = buy, def = def })
	end

	local passGrid = section("passes", 1)
	for i, def in Config.Passes do
		card(passGrid, def, "pass", i)
	end
	local productGrid = section("products", 3)
	for i, def in Config.Products do
		card(productGrid, def, "product", i)
	end

	local function refresh()
		panel.setTitle(Strings.get("shopTitle"))
		headers.passes.Text = Strings.get("passes")
		headers.products.Text = Strings.get("products")
		local profile = app.State.profile
		local unlocked = if profile then profile.unlocked else 1
		for _, c in cards do
			if c.kind == "pass" then
				c.name.Text = Strings.get("pass." .. c.key)
				c.desc.Text = Strings.get("pass." .. c.key .. ".desc")
			else
				c.name.Text = Strings.get("product." .. c.key)
				c.desc.Text = if c.def.dives > 0
					then Strings.get("product.desc", { n = Format.short(Economy.productCoins(c.def.dives, unlocked)) })
					else Strings.get("product." .. c.key .. ".desc", { n = Config.TimedBoostMinutes })
			end
			if c.kind == "pass" and app.State.passes[c.key] then
				c.buy.setText(Strings.get("owned"))
				c.buy.setPalette("Gold")
			elseif c.def.id <= 0 then
				c.buy.setText(Strings.get("comingSoon"))
				c.buy.setPalette("Gray")
			else
				c.buy.setText("R$ " .. tostring(c.def.price))
				c.buy.setPalette("Green")
			end
		end
	end

	panel.onOpen = function()
		app.Sfx.play("Open")
		refresh()
	end
	app.State.profileChanged:Connect(function()
		if panel.isOpen then
			refresh()
		end
	end)
	app.State.languageChanged:Connect(refresh)
	return panel
end

return ShopPanel
