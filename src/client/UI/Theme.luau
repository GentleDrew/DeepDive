--!strict
-- Visual language: rounded FredokaOne everywhere, bold outlines, bright ocean colours.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Color = require(Shared.Color)
local Config = require(Shared.Config)

local Theme = {}

Theme.Font = Font.fromEnum(Enum.Font.FredokaOne)

local hex = Color.hex

Theme.C = {
	White = Color3.new(1, 1, 1),
	Ink = hex("#15263a"),
	Outline = hex("#10233a"),
	Navy = hex("#16324f"),
	NavySoft = hex("#1f4368"),
	Panel = hex("#f3fbff"),
	PanelAlt = hex("#dcf1ff"),
	PanelLine = hex("#b9dcf4"),
	Muted = hex("#6f87a0"),
	Cyan = hex("#34e0ff"),
	Blue = hex("#2f9bff"),
	DeepBlue = hex("#1f67d6"),
	Gold = hex("#ffd23f"),
	GoldDark = hex("#d99a12"),
	Orange = hex("#ffa53f"),
	Green = hex("#4fe07a"),
	GreenDark = hex("#23a84c"),
	Red = hex("#ff5a6a"),
	RedDark = hex("#d12f45"),
	Pink = hex("#ff7ad7"),
	Purple = hex("#b06bff"),
	Gray = hex("#a3b3c4"),
	GrayDark = hex("#6b7c8f"),
	Oxygen = hex("#3fd8ff"),
	OxygenDeep = hex("#2a86ff"),
	Danger = hex("#ff4b5c"),
}

-- Button palettes: top gradient, bottom gradient, outline.
Theme.Buttons = {
	Blue = { hex("#5cc3ff"), hex("#2a7fe8"), hex("#12417a") },
	Green = { hex("#7dee8f"), hex("#2fbf55"), hex("#146b2c") },
	Gold = { hex("#ffe27a"), hex("#ffb52e"), hex("#8a5a07") },
	Red = { hex("#ff8a8f"), hex("#e83a4f"), hex("#7a1523") },
	Pink = { hex("#ffa6e6"), hex("#f25ac6"), hex("#7a1a63") },
	Purple = { hex("#cf9bff"), hex("#9656f0"), hex("#4b2280") },
	Orange = { hex("#ffc37a"), hex("#ff8c2e"), hex("#8a4207") },
	Cyan = { hex("#8ff0ff"), hex("#2ec8f0"), hex("#0f5f7a") },
	Gray = { hex("#d6dee8"), hex("#9aaabb"), hex("#4a5a6b") },
	Navy = { hex("#3a6690"), hex("#1f4368"), hex("#0c1f33") },
}

Theme.Rarity = {} :: { [string]: Color3 }
for name, value in Config.RarityColors :: { [string]: string } do
	Theme.Rarity[name] = hex(value)
end

function Theme.rarityColor(index: number): Color3
	return Theme.Rarity[Config.Rarities[index] or "Common"] or Theme.C.Gray
end

Theme.Radius = { Small = 10, Medium = 16, Large = 22 }
Theme.TextStroke = 2.4

return Theme
