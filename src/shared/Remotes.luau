--!strict
-- Remote names. The server creates them under ReplicatedStorage.Remotes at startup.

local Remotes = {}

Remotes.Folder = "Remotes"
Remotes.Invoke = "Invoke" -- RemoteFunction: (action, payload) -> { ok, err?, data? }
Remotes.Collect = "Collect" -- RemoteEvent client -> server: (layoutId, point)
Remotes.Hazard = "Hazard" -- RemoteEvent client -> server: (hazardIndex)
Remotes.Push = "Push" -- RemoteEvent server -> client: (kind, payload)

Remotes.Actions = {
	Teleport = true,
	BuyUpgrade = true,
	Hatch = true,
	Equip = true,
	EquipBest = true,
	UnequipAll = true,
	SetLock = true,
	DeletePet = true,
	Setting = true,
	Tutorial = true,
	Ready = true,
}

return Remotes
