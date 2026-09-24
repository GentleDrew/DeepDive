--!strict
-- Settings: music, sound effects, low graphics, hide other pets, language.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)

local Kit = require(script.Parent.Parent.Kit)
local Panel = require(script.Parent.Parent.Panel)
local Theme = require(script.Parent.Parent.Theme)

local SettingsPanel = {}

local C = Theme.C

function SettingsPanel.new(app: any): Panel.PanelApi
	local panel = Panel.new({
		Parent = app.Gui.panels,
		Title = Strings.get("settingsTitle"),
		Icon = utf8.char(0x2699) .. utf8.char(0xFE0F),
		Palette = "Gray",
		Size = Vector2.new(640, 500),
	})
	local list =
		Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, -20), Position = UDim2.fromOffset(0, 22), Parent = panel.body })
	Kit.list(list, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	local labels: { [string]: TextLabel } = {}
	local toggles: { [string]: Kit.ToggleApi } = {}

	local function row(order: number): Frame
		local frame =
			Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -10, 0, 60), LayoutOrder = order, Parent = list })
		Kit.corner(frame, 16)
		Kit.stroke(frame, C.PanelLine, 3)
		Kit.gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(228, 243, 255))
		return frame
	end

	for order, key in { "music", "sfx", "lowFx", "hidePets" } do
		local frame = row(order)
		labels[key] = Kit.text({
			Text = "",
			TextSize = 24,
			Color = C.Navy,
			Stroke = 0,
			Size = UDim2.new(1, -140, 1, 0),
			Position = UDim2.fromOffset(20, 0),
			XAlign = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		toggles[key] = Kit.toggle({
			Value = true,
			Position = UDim2.new(1, -18, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = frame,
			OnChange = function(value)
				app.setSetting(key, value)
			end,
		})
	end

	local langRow = row(5)
	labels.language = Kit.text({
		Text = "",
		TextSize = 24,
		Color = C.Navy,
		Stroke = 0,
		Size = UDim2.new(0.4, 0, 1, 0),
		Position = UDim2.fromOffset(20, 0),
		XAlign = Enum.TextXAlignment.Left,
		Parent = langRow,
	})
	local langButtons: { [string]: Kit.ButtonApi } = {}
	for i, lang in { "en", "ko" } do
		langButtons[lang] = Kit.button({
			Text = if lang == "en" then "English" else "한국어",
			TextSize = 20,
			Palette = "Gray",
			Size = UDim2.fromOffset(130, 44),
			Position = UDim2.new(1, -18 - (2 - i) * 140, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = langRow,
			OnClick = function()
				app.setSetting("lang", lang)
			end,
		})
	end

	local help = Kit.text({
		Text = "",
		TextSize = 16,
		Color = C.Muted,
		Stroke = 0,
		Wrapped = true,
		Size = UDim2.new(1, -20, 0, 44),
		LayoutOrder = 6,
		Parent = list,
	})
	local version = Kit.text({
		Text = Config.Title .. "  v" .. Config.Version,
		TextSize = 14,
		Color = C.Muted,
		Stroke = 0,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 7,
		Parent = list,
	})
	local _ = version

	local function refresh()
		local settings = app.State.settings()
		panel.setTitle(Strings.get("settingsTitle"))
		for key, label in labels do
			label.Text = Strings.get("setting." .. key)
		end
		for key, toggle in toggles do
			toggle.set((settings :: any)[key] == true)
		end
		for lang, button in langButtons do
			-- Highlight the language in effect (the saved value may be "auto").
			button.setPalette(if Strings.language == lang then "Blue" else "Gray")
		end
		help.Text = Strings.get(if app.Gui.isTouch() then "controlsTouch" else "controlsPc")
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

return SettingsPanel
