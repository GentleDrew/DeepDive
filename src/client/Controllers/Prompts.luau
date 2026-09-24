--!strict
-- Custom ProximityPrompt UI in the game's rounded style, with touch support, routing each
-- prompt kind to its panel.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)

local Prompts = {}

local KIND_TEXT = { Egg = "prompt.egg", Kiosk = "prompt.upgrades", Portal = "prompt.portal" }
local KIND_PALETTE = { Egg = "Purple", Kiosk = "Orange", Portal = "Blue" }

function Prompts.init(app: any)
	local Kit = app.Kit
	local Theme = app.Theme
	local shown: { [ProximityPrompt]: BillboardGui } = {}

	local function objectText(prompt: ProximityPrompt): string
		local kind = prompt:GetAttribute("Kind")
		local world = prompt:GetAttribute("World")
		if kind == "Egg" and type(world) == "number" then
			return Strings.name(Worlds.get(world).egg.name)
		elseif kind == "Kiosk" then
			return Strings.get("menu.upgrades")
		elseif kind == "Portal" then
			return Strings.get("menu.worlds")
		end
		return prompt.ObjectText
	end

	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom or shown[prompt] then
			return
		end
		local kind = prompt:GetAttribute("Kind")
		local palette = Theme.Buttons[KIND_PALETTE[kind] or "Blue"]
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "DeepDivePrompt"
		billboard.AlwaysOnTop = true
		billboard.Size = UDim2.fromOffset(300, 78)
		billboard.StudsOffset = Vector3.new(0, 1, 0)
		billboard.LightInfluence = 0
		billboard.Active = true
		billboard.Adornee = prompt.Parent :: Instance
		billboard.Parent = app.Gui.promptParent

		local pill = Kit.new(
			"TextButton",
			{ Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Parent = billboard }
		)
		Kit.round(pill)
		Kit.gradient(pill, palette[1], palette[2])
		Kit.stroke(pill, palette[3], 4)
		local key = Kit.new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			Size = UDim2.fromOffset(58, 58),
			Position = UDim2.new(0, 10, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			Parent = pill,
		})
		Kit.round(key)
		Kit.stroke(key, palette[3], 3)
		local keyText = if inputType == Enum.ProximityPromptInputType.Touch
			then utf8.char(0x1F446)
			elseif inputType == Enum.ProximityPromptInputType.Gamepad then "X"
			else UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
		Kit.text({ Text = keyText, TextSize = 32, Color = palette[3], Stroke = 0, Size = UDim2.fromScale(1, 1), Parent = key })
		Kit.text({
			Text = Strings.get(KIND_TEXT[kind] or "prompt.egg"),
			TextSize = 30,
			Size = UDim2.new(1, -86, 0, 34),
			Position = UDim2.fromOffset(78, 6),
			XAlign = Enum.TextXAlignment.Left,
			StrokeColor = palette[3],
			Parent = pill,
		})
		Kit.text({
			Text = objectText(prompt),
			TextSize = 20,
			Color = Color3.fromRGB(235, 245, 255),
			Size = UDim2.new(1, -86, 0, 26),
			Position = UDim2.fromOffset(78, 42),
			XAlign = Enum.TextXAlignment.Left,
			StrokeColor = palette[3],
			Parent = pill,
		})
		app.Anim.appear(pill, 0.3)
		pill.Activated:Connect(function()
			prompt:InputHoldBegin()
			task.wait()
			prompt:InputHoldEnd()
		end)
		shown[prompt] = billboard
	end)

	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		local billboard = shown[prompt]
		if billboard then
			shown[prompt] = nil
			billboard:Destroy()
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local kind = prompt:GetAttribute("Kind")
		local world = prompt:GetAttribute("World")
		app.Sfx.play("Click")
		if kind == "Egg" and type(world) == "number" then
			app.openEgg(world)
		elseif kind == "Kiosk" then
			app.openUpgrades()
		elseif kind == "Portal" then
			app.openWorlds()
		end
	end)
end

return Prompts
