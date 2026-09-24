--!strict
-- Diving gear: every world sells two pieces (standard and "Pro") for each of the four slots,
-- 160 items in all. Gear replaces stat upgrades: the equipped piece in a slot sets that stat,
-- and every piece is worn on the avatar. Pure data (names, colours, tiers); prices and stats
-- live in Economy.

local Worlds = if script then require(script.Parent.Worlds) else require("./Worlds")

local Gear = {}

export type Item = {
	key: string,
	slot: string, -- "tank" | "pack" | "fins" | "magnet"
	world: number,
	pro: boolean,
	tier: number, -- 1..40 within the slot (2 per world)
	theme: { en: string, ko: string },
	color: string,
	accent: string,
}

Gear.Slots = { "tank", "pack", "fins", "magnet" }
Gear.PerWorld = 2
Gear.Tiers = 40

-- Theme word per world (item names read "<theme> <slot>", e.g. "Kelp Tank Pro").
local THEMES = {
	{ "Sunny", "햇살" },
	{ "Seagrass", "해초" },
	{ "Kelp", "다시마" },
	{ "Tidepool", "조수" },
	{ "Rainbow", "무지개" },
	{ "Bubblegum", "풍선껌" },
	{ "Glowing", "발광" },
	{ "Coral", "산호" },
	{ "Shipwreck", "난파선" },
	{ "Pirate", "해적" },
	{ "Temple", "신전" },
	{ "Atlantis", "아틀란티스" },
	{ "Frost", "서리" },
	{ "Crystal", "수정" },
	{ "Volcanic", "화산" },
	{ "Magma", "마그마" },
	{ "Twilight", "황혼" },
	{ "Midnight", "한밤" },
	{ "Abyssal", "심연" },
	{ "Leviathan", "리바이어던" },
}

Gear.list = {} :: { Item }
Gear.byKey = {} :: { [string]: Item }
Gear.bySlot = {} :: { [string]: { Item } } -- ordered by tier

for _, slot in Gear.Slots do
	Gear.bySlot[slot] = {}
end

for world = 1, #THEMES do
	local data = Worlds.get(world)
	for _, slot in Gear.Slots do
		for index = 1, Gear.PerWorld do
			local pro = index == 2
			local item: Item = {
				key = slot .. world .. (if pro then "b" else "a"),
				slot = slot,
				world = world,
				pro = pro,
				tier = (world - 1) * Gear.PerWorld + index,
				theme = { en = THEMES[world][1], ko = THEMES[world][2] },
				color = data.accent[1],
				accent = data.accent[2],
			}
			table.insert(Gear.list, item)
			Gear.byKey[item.key] = item
			table.insert(Gear.bySlot[slot], item)
		end
	end
end

function Gear.get(key: string?): Item?
	if not key then
		return nil
	end
	return Gear.byKey[key]
end

-- Tier of a gear key (0 = starter gear / nothing equipped).
function Gear.tier(key: string?): number
	local item = Gear.get(key)
	return if item then item.tier else 0
end

return Gear
