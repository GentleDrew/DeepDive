--!strict
-- Server networking: creates the remotes, routes client actions to handlers with rate limits
-- and error isolation, and pushes state to clients.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Net = {}

type Handler = (player: Player, payload: any) -> (boolean, string?, any)
type Bucket = { tokens: number, updated: number }

local handlers: { [string]: Handler } = {}
local eventHandlers: { [string]: (Player, ...any) -> () } = {}
local buckets: { [Player]: { [string]: Bucket } } = {}

local folder: Folder
local invoke: RemoteFunction
local push: RemoteEvent

local RATE = { default = { rate = 6, burst = 10 }, Collect = { rate = 16, burst = 24 }, Hazard = { rate = 3, burst = 4 } }

local function allow(player: Player, name: string): boolean
	local limits = RATE[name] or RATE.default
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[name]
	local now = os.clock()
	if not bucket then
		bucket = { tokens = limits.burst, updated = now }
		perPlayer[name] = bucket
	end
	bucket.tokens = math.min(limits.burst, bucket.tokens + (now - bucket.updated) * limits.rate)
	bucket.updated = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function Net.init()
	local existing = ReplicatedStorage:FindFirstChild(Remotes.Folder)
	if existing then
		existing:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = Remotes.Folder

	invoke = Instance.new("RemoteFunction")
	invoke.Name = Remotes.Invoke
	invoke.Parent = folder

	push = Instance.new("RemoteEvent")
	push.Name = Remotes.Push
	push.Parent = folder

	for _, name in { Remotes.Collect, Remotes.Hazard } do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		remote.OnServerEvent:Connect(function(player, ...)
			local handler = eventHandlers[name]
			if handler and allow(player, name) then
				local ok, err = pcall(handler :: any, player, ...)
				if not ok then
					warn("[Net] " .. name .. " failed: " .. tostring(err))
				end
			end
		end)
	end

	invoke.OnServerInvoke = function(player: Player, action: any, payload: any)
		if type(action) ~= "string" or not Remotes.Actions[action] then
			return { ok = false, err = "err.generic" }
		end
		if not allow(player, action) then
			return { ok = false, err = "err.busy" }
		end
		local handler = handlers[action]
		if not handler then
			return { ok = false, err = "err.generic" }
		end
		local called, ok, err, data = pcall(handler, player, payload)
		if not called then
			warn("[Net] action " .. action .. " errored: " .. tostring(ok))
			return { ok = false, err = "err.generic" }
		end
		return { ok = ok == true, err = err, data = data }
	end

	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

function Net.on(action: string, handler: Handler)
	handlers[action] = handler
end

function Net.onEvent(name: string, handler: (Player, ...any) -> ())
	eventHandlers[name] = handler
end

function Net.push(player: Player, kind: string, payload: any?)
	if player.Parent then
		push:FireClient(player, kind, payload)
	end
end

function Net.pushAll(kind: string, payload: any?)
	push:FireAllClients(kind, payload)
end

return Net
