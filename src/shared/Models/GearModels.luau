--!strict
-- Procedural diving gear: oxygen tanks (back), treasure bags (hip), flippers (feet) and
-- treasure magnets (hand), tinted with each world's colours. Pro pieces get twin parts, neon
-- trim and, in later worlds, a glow. `dress` welds the equipped set onto a character so every
-- player sees it.

local Color = require(script.Parent.Parent.Color)
local Gear = require(script.Parent.Parent.Data.Gear)
local Build = require(script.Parent.Build)

local GearModels = {}

local V = Vector3.new
local cf = CFrame.new
local ang = CFrame.Angles
local rad = math.rad

local METAL = Color3.fromRGB(214, 222, 232)
local DARK = Color3.fromRGB(40, 46, 60)

local function trim(part: BasePart, pro: boolean)
	if pro then
		part.Material = Enum.Material.Neon
	end
end

local BUILDERS: { [string]: (Model, Gear.Item, Color3, Color3) -> () } = {}

-- Upright tank(s) centred on the origin, valve on top.
BUILDERS.tank = function(m, item, c1, c2)
	local offsets: { number } = if item.pro then { -0.42, 0.42 } else { 0 }
	for _, x in offsets do
		Build.column(m, 1.8, 0.78, cf(x, 0, 0), c1)
		Build.ball(m, 0.78, cf(x, 0.9, 0), c1)
		Build.ball(m, 0.78, cf(x, -0.9, 0), c1)
		for _, y in { -0.45, 0.45 } do
			trim(Build.column(m, 0.14, 0.84, cf(x, y, 0), c2), item.pro)
		end
		Build.column(m, 0.3, 0.3, cf(x, 1.3, 0), METAL)
		Build.cylinder(m, 0.4, 0.14, cf(x, 1.36, 0), METAL)
	end
	if item.pro then
		Build.block(m, V(1.2, 0.2, 0.3), cf(0, 1.25, 0), METAL)
	end
	-- Harness plate that sits against the back.
	Build.block(m, V(if item.pro then 1.5 else 0.9, 1.3, 0.12), cf(0, 0, -0.45), DARK)
end

-- Treasure pouch on the hip.
BUILDERS.pack = function(m, item, c1, c2)
	local sides: { number } = if item.pro then { -1, 1 } else { 1 }
	for _, side in sides do
		local x = side * 1.05
		Build.block(m, V(0.5, 0.75, 0.85), cf(x, 0, 0), c1)
		Build.wedge(m, V(0.54, 0.25, 0.89), cf(x, 0.45, 0) * ang(0, rad(side * 90), 0), c2)
		local clasp = Build.ball(m, 0.22, cf(x + side * 0.26, 0.2, 0), if item.pro then c2 else Color3.fromRGB(255, 214, 90))
		clasp.Material = Enum.Material.Neon
	end
	-- Belt.
	Build.block(m, V(2.1, 0.22, 1.1), cf(0, 0.1, 0), DARK)
	trim(Build.block(m, V(0.36, 0.3, 0.1), cf(0, 0.1, -0.56), Color3.fromRGB(255, 214, 90)), item.pro)
end

-- One flipper, foot at the origin, blade reaching forward (-Z).
BUILDERS.fins = function(m, item, c1, c2)
	local length = if item.pro then 2.3 else 1.8
	Build.block(m, V(0.95, 0.35, 1.0), cf(0, 0, 0), c2)
	Build.block(m, V(1.05, 0.12, length), cf(0, -0.12, -0.5 - length / 2), c1)
	for _, x in { -0.5, 0.5 } do
		trim(Build.block(m, V(0.1, 0.18, length), cf(x, -0.1, -0.5 - length / 2), c2), item.pro)
	end
	if item.pro then
		Build.block(m, V(0.12, 0.16, length * 0.8), cf(0, -0.04, -0.5 - length * 0.45), c2)
	end
end

-- Horseshoe magnet held in the hand, prongs pointing forward (-Z).
BUILDERS.magnet = function(m, item, c1, c2)
	for _, x in { -0.32, 0.32 } do
		Build.block(m, V(0.26, 0.26, 0.9), cf(x, 0, -0.35), c1)
		local tip = Build.block(m, V(0.28, 0.28, 0.24), cf(x, 0, -0.9), if item.pro then c2 else METAL)
		trim(tip, item.pro)
	end
	Build.cylinder(m, 0.9, 0.3, cf(0, 0, 0.1), c1)
	if item.pro then
		local core = Build.ball(m, 0.3, cf(0, 0, -0.9), c2)
		core.Material = Enum.Material.Neon
		core.Transparency = 0.3
	end
end

function GearModels.build(key: string, size: number?): Model
	local item = Gear.get(key)
	local model = Build.model("Gear_" .. key)
	if not item then
		return model
	end
	local c1, c2 = Color.hex(item.color), Color.hex(item.accent)
	BUILDERS[item.slot](model, item, c1, c2)
	local root = model.PrimaryPart
	if root and item.pro and item.world >= 11 then
		Build.light(root, c1, 6, 1)
	end
	if root and item.pro and item.world >= 15 then
		Build.sparkles(root, c1, 3)
	end
	if size then
		Build.fit(model, size)
	end
	model:SetAttribute("GearKey", key)
	return model
end

-- Where each slot sits on the body: { R15 part, R6 part, offset in that part's space }.
-- Characters face -Z, so the back is +Z.
type Mount = { r15: string, r6: string, offset: CFrame, r6Offset: CFrame }
local MOUNTS: { [string]: { Mount } } = {
	tank = { { r15 = "UpperTorso", r6 = "Torso", offset = cf(0, 0, 0.98), r6Offset = cf(0, 0.1, 0.98) } },
	pack = { { r15 = "LowerTorso", r6 = "Torso", offset = cf(0, 0, 0), r6Offset = cf(0, -0.8, 0) } },
	fins = {
		{ r15 = "LeftFoot", r6 = "Left Leg", offset = cf(0, -0.05, -0.1), r6Offset = cf(0, -0.85, -0.1) },
		{ r15 = "RightFoot", r6 = "Right Leg", offset = cf(0, -0.05, -0.1), r6Offset = cf(0, -0.85, -0.1) },
	},
	magnet = { { r15 = "RightHand", r6 = "Right Arm", offset = cf(0, -0.25, -0.2), r6Offset = cf(0, -1.1, -0.2) } },
}
GearModels.Mounts = MOUNTS

-- Rebuilds the worn gear on a character from an equip map ({ slot = gearKey }).
function GearModels.dress(character: Model, equip: { [string]: string })
	local old = character:FindFirstChild("DeepDiveGear")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "DeepDiveGear"
	for _, slot in Gear.Slots do
		local key = equip[slot]
		if not key or not Gear.get(key) then
			continue
		end
		for _, mount in MOUNTS[slot] do
			local r15 = character:FindFirstChild(mount.r15)
			local bone = r15 or character:FindFirstChild(mount.r6)
			if not bone or not bone:IsA("BasePart") then
				continue
			end
			local model = GearModels.build(key)
			model:PivotTo(bone.CFrame * (if r15 then mount.offset else mount.r6Offset))
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = false
					part.Massless = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = bone
					weld.Part1 = part
					weld.Parent = part
				end
			end
			model.Parent = folder
		end
	end
	folder.Parent = character
end

return GearModels
