--!strict
-- Minimal synchronous signal. Handlers run in connection order; a handler that errors
-- does not stop the others.

export type Connection = { Disconnect: (self: Connection) -> (), Connected: boolean }

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { _handlers: { [number]: any }, _nextId: number }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {}, _nextId = 0 }, Signal)
end

function Signal.Connect(self: Signal, handler: (...any) -> ()): Connection
	self._nextId += 1
	local id = self._nextId
	self._handlers[id] = handler
	local connection = { Connected = true } :: any
	function connection.Disconnect(conn)
		conn.Connected = false
		self._handlers[id] = nil
	end
	return connection
end

function Signal.Once(self: Signal, handler: (...any) -> ()): Connection
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal.Fire(self: Signal, ...: any)
	local ids = {}
	for id in self._handlers do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local handler = self._handlers[id]
		if handler then
			local ok, err = pcall(handler, ...)
			if not ok then
				warn("[Signal] handler error: " .. tostring(err))
			end
		end
	end
end

function Signal.Wait(self: Signal): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: Signal)
	table.clear(self._handlers)
end

return Signal
