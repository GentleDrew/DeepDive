--!strict
-- Dive shop: oxygen tank, backpack, flippers and treasure magnet upgrades.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)

local Anim = require(script.Parent.Parent.Anim)
local Kit = require(script.Parent.Parent.Kit)
local Panel = require(script.Parent.Parent.Panel)
local Theme = require(script.Parent.Parent.Theme)

local UpgradesPanel = {}

local C = Theme.C

type Row = {
	frame: Frame,
	name: TextLabel,
	desc: TextLabel,
	level: TextLabel,
	value: TextLabel,
	bar: Kit.ProgressApi,
	buy: Kit.ButtonApi,
}

local function formatValue(track: string, value: number): string
	if track == "fins" or track == "magnet" then
		return string.format("%.1f", value)
	end
	return tostring(math.floor(value))
end

function UpgradesPanel.new(app: any): Panel.PanelApi
	local panel = Panel.new({
		Parent = app.Gui.panels,
		Title = Strings.get("menu.upgrades"),
		Icon = utf8.char(0x1F93F),
		Palette = "Orange",
		Size = Vector2.new(780, 520),
	})
	local list =
		Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -16), Position = UDim2.fromOffset(0, 20), Parent = panel.body })
	Kit.list(list, Enum.FillDirection.Vertical, 12, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	local rows: { [string]: Row } = {}
	for order, def in Config.Upgrades do
		local color = Color.hex(def.color)
		local frame =
			Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -8, 0, 98), LayoutOrder = order, Parent = list }) :: Frame
		Kit.corner(frame, 18)
		Kit.gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(226, 242, 255))
		Kit.stroke(frame, C.PanelLine, 3)
		local iconBack = Kit.new("Frame", {
			BackgroundColor3 = color,
			Size = UDim2.fromOffset(76, 76),
			Position = UDim2.new(0, 12, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = frame,
		})
		Kit.round(iconBack)
		Kit.gradient(iconBack, Color.lighten(color, 0.35), color)
		Kit.stroke(iconBack, Color.darken(color, 0.5), 3)
		local icon: GuiObject
		if def.id == "tank" then
			icon = Kit.Icons.bubble(50, iconBack)
		elseif def.id == "pack" then
			icon = Kit.Icons.bag(50, iconBack)
		elseif def.id == "fins" then
			icon = Kit.Icons.emoji(utf8.char(0x1F42C), 40, iconBack)
		else
			icon = Kit.Icons.emoji(utf8.char(0x1F9F2), 40, iconBack)
		end
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)

		local name = Kit.text({
			Text = "",
			TextSize = 26,
			Size = UDim2.fromOffset(330, 30),
			Position = UDim2.fromOffset(102, 10),
			XAlign = Enum.TextXAlignment.Left,
			StrokeColor = Color.darken(color, 0.55),
			Parent = frame,
		})
		local desc = Kit.text({
			Text = "",
			TextSize = 16,
			Color = C.Muted,
			Stroke = 0,
			Size = UDim2.fromOffset(330, 20),
			Position = UDim2.fromOffset(104, 40),
			XAlign = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local bar = Kit.progress({
			Size = UDim2.fromOffset(250, 20),
			Position = UDim2.fromOffset(104, 66),
			Colors = { Color.lighten(color, 0.3), color },
			TextSize = 14,
			Parent = frame,
		})
		local level = Kit.text({
			Text = "",
			TextSize = 18,
			Size = UDim2.fromOffset(90, 22),
			Position = UDim2.fromOffset(362, 65),
			XAlign = Enum.TextXAlignment.Left,
			StrokeColor = Color.darken(color, 0.55),
			Parent = frame,
		})
		local value = Kit.text({
			Text = "",
			TextSize = 22,
			Size = UDim2.fromOffset(170, 30),
			Position = UDim2.new(1, -196, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = C.Ink,
			Stroke = 0,
			Parent = frame,
		})
		local buy = Kit.button({
			Text = "",
			Icon = nil,
			TextSize = 22,
			Palette = "Green",
			Size = UDim2.fromOffset(170, 62),
			Position = UDim2.new(1, -14, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = frame,
			OnClick = function()
				local result = app.Net.invoke("BuyUpgrade", { track = def.id })
				if result.ok then
					app.Sfx.play("Upgrade")
					Anim.pop(frame, 0.05)
					Anim.pop(iconBack, 0.35)
					app.Toasts.show(Strings.get("upgraded", { name = Strings.get("upgrade." .. def.id) }), "good", utf8.char(0x2B06))
				else
					app.Sfx.play("Error")
					Anim.shake(frame, 6)
					if result.err then
						app.Toasts.show(Strings.get(result.err), "bad")
					end
				end
			end,
		})
		local coin = Kit.Icons.coin(28, buy.button:FindFirstChild("Content") :: Instance)
		coin.LayoutOrder = 0
		rows[def.id] = { frame = frame, name = name, desc = desc, level = level, value = value, bar = bar, buy = buy }
	end

	local function refresh()
		local profile = app.State.profile
		if not profile then
			return
		end
		panel.setTitle(Strings.get("menu.upgrades"))
		for _, def in Config.Upgrades do
			local row = rows[def.id]
			local lvl = profile.upgrades[def.id] or 1
			local current = Economy.upgradeValue(def.id, lvl)
			local cost = Economy.upgradeCost(def.id, lvl)
			row.name.Text = Strings.get("upgrade." .. def.id)
			row.desc.Text = Strings.get("upgrade." .. def.id .. ".desc")
			row.level.Text = Strings.get("level", { n = lvl })
			row.bar.set(lvl / def.max, "")
			local coinIcon = row.buy.button:FindFirstChild("Content")
				and (row.buy.button:FindFirstChild("Content") :: Instance):FindFirstChild("Coin")
			if cost then
				local nextValue = Economy.upgradeValue(def.id, lvl + 1)
				row.value.Text = formatValue(def.id, current) .. "  >  " .. formatValue(def.id, nextValue)
				row.buy.setText(Format.short(cost))
				local affordable = profile.coins >= cost
				row.buy.setPalette(if affordable then "Green" else "Gray")
				row.buy.setEnabled(true)
				if coinIcon then
					(coinIcon :: Frame).Visible = true
				end
			else
				row.value.Text = formatValue(def.id, current)
				row.buy.setText(Strings.get("max"))
				row.buy.setPalette("Gold")
				row.buy.setEnabled(false)
				if coinIcon then
					(coinIcon :: Frame).Visible = false
				end
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

-- True when at least one upgrade is affordable (drives the HUD badge).
function UpgradesPanel.anyAffordable(profile: any): boolean
	if not profile then
		return false
	end
	for _, def in Config.Upgrades do
		local cost = Economy.upgradeCost(def.id, profile.upgrades[def.id] or 1)
		if cost and profile.coins >= cost then
			return true
		end
	end
	return false
end

return UpgradesPanel
