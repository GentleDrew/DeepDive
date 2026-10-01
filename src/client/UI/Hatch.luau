--!strict
-- Egg hatching sequence: eggs drop in, wobble harder and harder, burst in a flash and reveal
-- the pet with a rarity-coloured sunburst, name and NEW! badge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)

local Anim = require(script.Parent.Anim)
local Effects = require(script.Parent.Effects)
local Gui = require(script.Parent.Gui)
local Kit = require(script.Parent.Kit)
local Theme = require(script.Parent.Theme)
local Viewport = require(script.Parent.Viewport)

local Hatch = {}

local C = Theme.C

Hatch.sfx = function(_name: string) end
Hatch.playing = false

local function sunburst(parent: GuiObject, color: Color3, size: number): Frame
	local holder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 1,
		Parent = parent,
	}) :: Frame
	for i = 0, 11 do
		local ray = Kit.new("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = 0.45,
			Size = UDim2.new(0, size * 0.09, 0.5, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 1),
			Rotation = i * 30,
			ZIndex = 1,
			Parent = holder,
		})
		Kit.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0.1), Parent = ray })
	end
	local glow = Kit.new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(0.55, 0.55),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 1,
		Parent = holder,
	})
	Kit.round(glow)
	Kit.new("UIGradient", { Transparency = NumberSequence.new(0, 0.9), Parent = glow })
	return holder
end

function Hatch.play(world: number, results: { { id: string, key: string, new: boolean } }, onDone: () -> ())
	Hatch.playing = true
	local root = Kit.new("TextButton", {
		Name = "Hatch",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(6, 16, 34),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 80,
		Parent = Gui.overlay,
	}) :: TextButton
	Anim.tween(root, 0.3, { BackgroundTransparency = 0.25 })

	local count = #results
	local slotSize = if count == 1 then 320 elseif count <= 3 then 240 else 200
	local row = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(count * (slotSize + 30), slotSize + 140),
		Position = UDim2.fromScale(0.5, 0.48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 81,
		Parent = root,
	})
	Kit.list(row, Enum.FillDirection.Horizontal, 30)

	type Slot = { frame: Frame, view: Viewport.ViewApi, result: any }
	local slots: { Slot } = {}
	for i, result in results do
		local frame = Kit.new(
			"Frame",
			{ BackgroundTransparency = 1, Size = UDim2.fromOffset(slotSize, slotSize + 130), LayoutOrder = i, ZIndex = 81, Parent = row }
		) :: Frame
		local view = Viewport.new(frame, UDim2.fromOffset(slotSize, slotSize), UDim2.new(0.5, 0, 0, -400), Vector2.new(0.5, 0))
		view.frame.ZIndex = 3
		view.setModel(Viewport.egg(world))
		table.insert(slots, { frame = frame, view = view, result = result })
		Anim.tween(view.frame, 0.55, { Position = UDim2.new(0.5, 0, 0, 0) }, Enum.EasingStyle.Bounce)
	end

	local finished = false
	local canSkip = false
	local function finish()
		if finished or not canSkip then
			return
		end
		finished = true
		Anim.tween(root, 0.25, { BackgroundTransparency = 1 })
		for _, slot in slots do
			Anim.tween(Anim.scaleOf(slot.frame), 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		end
		task.delay(0.3, function()
			root:Destroy()
			Hatch.playing = false
			onDone()
		end)
	end
	root.Activated:Connect(finish)

	task.spawn(function()
		task.wait(0.6)
		-- Wobble with rising intensity.
		for shake = 1, 3 do
			Hatch.sfx("EggShake")
			local amplitude = 8 + shake * 7
			local start = os.clock()
			while os.clock() - start < 0.32 do
				local t = (os.clock() - start) / 0.32
				for _, slot in slots do
					slot.view.frame.Rotation = math.sin(t * math.pi * 4) * amplitude
				end
				RunService.RenderStepped:Wait()
			end
			for _, slot in slots do
				slot.view.frame.Rotation = 0
			end
			task.wait(0.18)
		end
		local best = 1
		for _, slot in slots do
			local pet = Worlds.pets[slot.result.key]
			if pet and pet.rarity > best then
				best = pet.rarity
			end
		end
		Hatch.sfx("EggCrack")
		Effects.flash(Color3.new(1, 1, 1), if best >= 5 then 0.95 else 0.8, 0.6)
		for _, slot in slots do
			local pet = Worlds.pets[slot.result.key]
			local rarity = Config.Rarities[pet.rarity]
			local color = Theme.Rarity[rarity]
			local burst = sunburst(slot.frame, color, slotSize * 1.5)
			burst.Position = UDim2.new(0.5, 0, 0, slotSize / 2)
			task.spawn(function()
				while burst.Parent do
					burst.Rotation += 0.6
					RunService.RenderStepped:Wait()
				end
			end)
			slot.view.setModel(Viewport.pet(slot.result.key))
			slot.view.setSpin(true)
			Anim.appear(slot.view.frame, 0.5)
			local name = Kit.text({
				Text = Strings.name(pet.name),
				TextSize = if count == 1 then 40 elseif count <= 3 then 30 else 24,
				Size = UDim2.new(1, 60, 0, 46),
				Position = UDim2.new(0.5, 0, 0, slotSize + 4),
				AnchorPoint = Vector2.new(0.5, 0),
				ZIndex = 5,
				Stroke = 4,
				StrokeColor = color:Lerp(Color3.new(0, 0, 0), 0.6),
				Parent = slot.frame,
			})
			Anim.appear(name, 0.4)
			local chip = Kit.new("Frame", {
				BackgroundColor3 = color,
				Size = UDim2.fromOffset(170, 36),
				Position = UDim2.new(0.5, 0, 0, slotSize + 54),
				AnchorPoint = Vector2.new(0.5, 0),
				ZIndex = 5,
				Parent = slot.frame,
			})
			Kit.round(chip)
			Kit.stroke(chip, color:Lerp(Color3.new(0, 0, 0), 0.5), 3)
			Kit.text({ Text = Strings.get("rarity." .. rarity), TextSize = 22, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = chip })
			if slot.result.new then
				local badge = Kit.new("Frame", {
					BackgroundColor3 = C.Red,
					Size = UDim2.fromOffset(90, 40),
					Position = UDim2.new(1, -10, 0, 20),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Rotation = 12,
					ZIndex = 7,
					Parent = slot.frame,
				})
				Kit.round(badge)
				Kit.stroke(badge, C.White, 3)
				Kit.text({ Text = Strings.get("newPet"), TextSize = 22, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = badge })
				task.delay(0.3, function()
					Anim.pop(badge, 0.5)
				end)
			end
		end
		if best >= 5 then
			Hatch.sfx("Legendary")
			Effects.confetti(120)
		else
			Hatch.sfx("Reveal")
		end
		local hint = Kit.text({
			Text = Strings.get("tapToContinue"),
			TextSize = 22,
			Color = Color3.fromRGB(200, 230, 255),
			Size = UDim2.fromOffset(500, 30),
			Position = UDim2.new(0.5, 0, 1, -40),
			AnchorPoint = Vector2.new(0.5, 1),
			ZIndex = 82,
			Parent = root,
		})
		hint.TextTransparency = 1
		task.wait(0.9)
		canSkip = true
		Anim.tween(hint, 0.3, { TextTransparency = 0 })
		task.wait(2.6)
		finish()
	end)
end

return Hatch
