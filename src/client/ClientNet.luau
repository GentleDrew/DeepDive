--!strict
-- Client networking: typed wrappers around the remotes and a push dispatcher.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Signal)

local ClientNet = {}

local folder = ReplicatedStorage:WaitForChild(Remotes.Folder, 60) :: Folder
local invoke = folder:WaitForChild(Remotes.Invoke) :: RemoteFunction
local collect = folder:WaitForChild(Remotes.Collect) :: RemoteEvent
local hazard = folder:WaitForChild(Remotes.Hazard) :: RemoteEvent
local push = folder:WaitForChild(Remotes.Push) :: RemoteEvent

local handlers: { [string]: any } = {}
ClientNet.pushed = Signal.new()

export type Result = { ok: boolean, err: string?, data: any }

function ClientNet.invoke(action: string, payload: any?): Result
	local ok, result = pcall(function()
		return invoke:InvokeServer(action, payload)
	end)
	if not ok or type(result) ~= "table" then
		return { ok = false, err = "err.generic", data = nil }
	end
	return result
end

function ClientNet.collect(layoutId: number, point: number)
	collect:FireServer(layoutId, point)
end

function ClientNet.hazard(index: number)
	hazard:FireServer(index)
end

function ClientNet.on(kind: string, handler: (any) -> ())
	local list = handlers[kind]
	if not list then
		list = {}
		handlers[kind] = list
	end
	table.insert(list, handler)
end

push.OnClientEvent:Connect(function(kind: string, payload: any)
	local list = handlers[kind]
	if list then
		for _, handler in list do
			task.spawn(handler, payload)
		end
	end
	ClientNet.pushed:Fire(kind, payload)
end)

return ClientNet
