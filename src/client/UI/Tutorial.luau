--!strict
-- First-time guidance: a banner with the next goal plus a bouncing 3D arrow over the target.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Layout = require(Shared.Layout)
local Strings = require(Shared.Strings)

local Anim = require(script.Parent.Anim)
local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)

local Tutorial = {}

local C = Theme.C

function Tutorial.init(app: any)
	local banner = Kit.new("Frame", {
		Name = "Tutorial",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(0, 58),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 1, -150),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = false,
		Parent = Gui.hud,
	}) :: Frame
	Kit.round(banner)
	Kit.gradient(banner, Theme.Buttons.Gold[1], Theme.Buttons.Gold[2])
	Kit.stroke(banner, Theme.Buttons.Gold[3], 4)
	Kit.padding(banner, 0, 24, 0, 18)
	local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = banner })
	Kit.list(row, Enum.FillDirection.Horizontal, 10)
	local arrow = Kit.text({ Text = utf8.char(0x1F449), TextSize = 32, Size = UDim2.fromOffset(40, 40), Stroke = 0, LayoutOrder = 1, Parent = row })
	local label = Kit.text({
		Text = "",
		TextSize = 24,
		Size = UDim2.new(0, 0, 1, 0),
		AutoX = true,
		StrokeColor = Theme.Buttons.Gold[3],
		LayoutOrder = 2,
		Parent = row,
	})
	local okButton = Kit.button({
		Text = "OK",
		TextSize = 20,
		Palette = "Green",
		Size = UDim2.fromOffset(70, 40),
		LayoutOrder = 3,
		Parent = row,
		OnClick = function()
			app.Net.invoke("Tutorial", { step = 7 })
		end,
	})
	okButton.button.Visible = false

	-- World-space arrow.
	local anchor = Instance.new("Part")
	anchor.Name = "TutorialArrow"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Parent = Workspace
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(90, 90)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchor
	billboard.Enabled = false
	billboard.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local arrow3d =
		Kit.text({ Text = utf8.char(0x2B07) .. utf8.char(0xFE0F), TextSize = 70, Size = UDim2.fromScale(1, 1), Stroke = 0, Parent = billboard })

	local lastText = ""
	local target: Vector3? = nil
	RunService.RenderStepped:Connect(function()
		local profile = app.State.profile
		local text = ""
		target = nil
		local showOk = false
		if profile and not app.State.traveling then
			local step = profile.tutorial
			local world = app.State.world
			local info = Layout.info(world)
			local dock = Layout.dock(world)
			if step == 1 then
				text = Strings.get("tutorial.1")
				target = Layout.at(world, 0, 3, info.radius - 4)
			elseif step == 2 or step == 3 then
				if app.State.dive.cargo > 0 then
					text = Strings.get("tutorial.3")
				else
					text = Strings.get("tutorial.2")
					if app.Relics then
						target = app.Relics.nearest()
					end
				end
			elseif step == 4 then
				text = Strings.get("tutorial.4")
				target = Layout.at(world, dock.kiosk.X, dock.kiosk.Y + 13, dock.kiosk.Z)
			elseif step == 5 then
				local cost = Economy.eggCost(world)
				text = Strings.get("tutorial.5")
				if profile.coins < cost then
					text ..= "  (" .. Format.short(cost) .. ")"
				end
				target = Layout.at(world, dock.egg.X, dock.egg.Y + 11, dock.egg.Z)
			elseif step == 6 then
				text = Strings.get("tutorial.6")
				showOk = true
			end
		end
		if text ~= lastText then
			lastText = text
			label.Text = text
			banner.Visible = text ~= ""
			if text ~= "" then
				Anim.appear(banner, 0.35)
			end
		end
		okButton.button.Visible = showOk
		local t = os.clock()
		arrow.Rotation = math.sin(t * 6) * 10
		if target then
			billboard.Enabled = true
			anchor.Position = target + Vector3.new(0, 2 + math.abs(math.sin(t * 4)) * 1.5, 0)
		else
			billboard.Enabled = false
		end
		banner.Position = UDim2.new(0.5, 0, 1, if app.State.dive.inWater or app.State.dive.active then -150 else -40)
	end)
	local _ = arrow3d
	local _c = C
end

return Tutorial
