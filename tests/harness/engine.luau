--!nocheck
-- Minimal Roblox engine emulation for runtime smoke tests under Lune.
--
-- Loads the built place, runs server Scripts and client LocalScripts in separate module realms,
-- and wraps every instance scripts can reach in a canonical proxy. The proxy layer:
--   * validates property names, value types and read-only access against the reflection database
--   * provides engine events, callbacks and computed properties (Position, AbsoluteSize, ...)
--   * stubs the engine services the game uses (terrain, raycasts, DataStores, tweens, ...)
-- Client and server talk through loopback remotes that enforce Roblox's serialization rules, so
-- mixed tables, sparse arrays or functions in payloads are reported instead of silently dropped.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local lunetask = require("@lune/task")

local Vector3, Vector2, CFrame, Color3 = roblox.Vector3, roblox.Vector2, roblox.CFrame, roblox.Color3
local Enum = roblox.Enum

local Engine = {}
Engine.options = { studio = false, viewport = Vector2.new(1280, 760), touch = false, latency = 0.02, locale = "en-us" }
Engine.errors = {}
Engine.errorCounts = {}
Engine.warnings = {}
Engine.traffic = {}
Engine.time = 0
Engine.running = true
Engine.localPlayer = nil
Engine.ownedPasses = {}
Engine.prompts = {}
Engine.purchasePrompts = {}
Engine.boundActions = {}
Engine.closeCallbacks = {}
Engine.raycastHook = nil :: ((Vector3, Vector3, any) -> any)?
Engine.terrainCalls = 0
Engine.dataStoreFailures = 0

local db = roblox.getReflectionDatabase()

---------------------------------------------------------------------------------------------------
-- Reporting

local function report(kind: string, message: string)
	local key = kind .. "|" .. message
	local count = Engine.errorCounts[key]
	if count then
		Engine.errorCounts[key] = count + 1
		return
	end
	Engine.errorCounts[key] = 1
	table.insert(Engine.errors, { kind = kind, message = message })
	print(string.format("\27[31m[%s]\27[0m %s", kind, message))
end
Engine.report = report

local function traceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

local function protect(label: string, fn: (...any) -> ...any, ...: any)
	local ok, err = xpcall(fn, traceback, ...)
	if not ok then
		report("error", label .. ": " .. tostring(err))
	end
end

local warnAllow = {}
function Engine.allowWarning(pattern: string)
	table.insert(warnAllow, pattern)
end

local function onWarn(realm: string, ...: any)
	local parts = table.pack(...)
	for i = 1, parts.n do
		parts[i] = tostring(parts[i])
	end
	local message = table.concat(parts, " ", 1, parts.n)
	table.insert(Engine.warnings, message)
	for _, pattern in warnAllow do
		if string.find(message, pattern) then
			print(string.format("\27[33m[warn:%s]\27[0m %s", realm, message))
			return
		end
	end
	report("warn:" .. realm, message)
end

---------------------------------------------------------------------------------------------------
-- Reflection helpers

local chainCache: { [string]: { string } } = {}
local function classChain(className: string): { string }
	local chain = chainCache[className]
	if chain then
		return chain
	end
	chain = {}
	local current: string? = className
	while current do
		table.insert(chain, current)
		local def = db:GetClass(current)
		current = def and def.Superclass or nil
	end
	chainCache[className] = chain
	return chain
end

local propCache: { [string]: { [string]: any } } = {}
local function propInfo(className: string, name: string): any
	local perClass = propCache[className]
	if not perClass then
		perClass = {}
		propCache[className] = perClass
	end
	local cached = perClass[name]
	if cached ~= nil then
		return cached or nil
	end
	for _, c in classChain(className) do
		local def = db:GetClass(c)
		local info = def and def.Properties[name]
		if info then
			perClass[name] = info
			return info
		end
	end
	perClass[name] = false
	return nil
end

local function hasTag(info: any, tag: string): boolean
	for _, t in info.Tags or {} do
		if t == tag then
			return true
		end
	end
	return false
end

local function defaultFor(datatype: string): any
	if datatype == "Vector3" then
		return Vector3.zero
	elseif datatype == "Vector2" then
		return Vector2.zero
	elseif datatype == "CFrame" then
		return CFrame.identity
	elseif datatype == "Bool" then
		return false
	elseif datatype == "String" or datatype == "ContentId" or datatype == "Content" then
		return ""
	elseif datatype == "Color3" or datatype == "Color3uint8" then
		return Color3.new()
	elseif datatype == "UDim2" then
		return roblox.UDim2.new()
	elseif datatype == "UDim" then
		return roblox.UDim.new()
	elseif datatype == "Ref" then
		return nil
	elseif string.find(datatype, "^Enum%.") then
		local enum = Enum[string.sub(datatype, 6)]
		return enum and enum:GetEnumItems()[1]
	elseif string.find(datatype, "Float") or string.find(datatype, "Int") then
		return 0
	end
	return nil
end

---------------------------------------------------------------------------------------------------
-- Signals

local Connection = {}
Connection.__index = Connection
function Connection:Disconnect()
	self.Connected = false
end

local Signal = {}
Signal.__index = Signal
Signal.__type = "RBXScriptSignal"

function Signal.new(label: string)
	return setmetatable({ label = label, connections = {}, waiting = {} }, Signal)
end

-- Which realm connected: found by walking the caller's stack for a script location.
local function callerRealm(): string?
	for level = 3, 14 do
		local source = debug.info(level, "s")
		if source == nil then
			break
		end
		if string.find(source, "PlayerScripts", 1, true) then
			return "client"
		elseif string.find(source, "ServerScriptService", 1, true) then
			return "server"
		end
	end
	return nil
end

function Signal:Connect(fn)
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 2)
	end
	local connection = setmetatable({ Connected = true, fn = fn, realm = callerRealm() }, Connection)
	table.insert(self.connections, connection)
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end

function Signal:Fire(...)
	local live = {}
	for _, connection in self.connections do
		if connection.Connected then
			table.insert(live, connection)
		end
	end
	self.connections = live
	for _, connection in live do
		if not (Engine.clientStopped and connection.realm == "client") then
			lunetask.spawn(protect, self.label, connection.fn, ...)
		end
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, thread in waiting do
		lunetask.spawn(thread, ...)
	end
end

Engine.Signal = Signal

---------------------------------------------------------------------------------------------------
-- Proxies

local rawToProxy = {}
local proxyToRaw = {}
local destroyed = {}
local ProxyMeta = {}

local function isProxy(v: any): boolean
	return type(v) == "table" and proxyToRaw[v] ~= nil
end

local function wrap(v: any): any
	if typeof(v) == "Instance" then
		local p = rawToProxy[v]
		if not p then
			p = setmetatable({}, ProxyMeta)
			rawToProxy[v] = p
			proxyToRaw[p] = v
		end
		return p
	end
	return v
end

local function unwrap(v: any): any
	if type(v) == "table" then
		local raw = proxyToRaw[v]
		if raw then
			return raw
		end
	end
	return v
end

local function wrapDeep(v: any): any
	if typeof(v) == "Instance" then
		return wrap(v)
	elseif type(v) == "table" and not proxyToRaw[v] and getmetatable(v) == nil then
		local out = {}
		for k, x in v do
			out[k] = wrapDeep(x)
		end
		return out
	end
	return v
end

local function wrapResults(...: any): ...any
	local n = select("#", ...)
	if n == 1 then
		return wrapDeep((...))
	end
	local out = table.pack(...)
	for i = 1, n do
		out[i] = wrapDeep(out[i])
	end
	return table.unpack(out, 1, n)
end

Engine.wrap, Engine.unwrap, Engine.isProxy = wrap, unwrap, isProxy

-- Custom members, looked up through the class hierarchy.
local methods: { [string]: { [string]: any } } = {}
local getters: { [string]: { [string]: any } } = {}
local setters: { [string]: { [string]: any } } = {}
local eventNames: { [string]: { [string]: boolean } } = {}
local callbackNames: { [string]: { [string]: boolean } } = {}

local function method(className: string, name: string, fn)
	methods[className] = methods[className] or {}
	methods[className][name] = fn
end
local function getter(className: string, name: string, fn)
	getters[className] = getters[className] or {}
	getters[className][name] = fn
end
local function setter(className: string, name: string, fn)
	setters[className] = setters[className] or {}
	setters[className][name] = fn
end

local lookupCache: { [any]: { [string]: { [string]: any } } } = {}
local function findCustom(registry, className: string, key: string): any
	local byRegistry = lookupCache[registry]
	if not byRegistry then
		byRegistry = {}
		lookupCache[registry] = byRegistry
	end
	local byClass = byRegistry[className]
	if not byClass then
		byClass = {}
		byRegistry[className] = byClass
	end
	local cached = byClass[key]
	if cached ~= nil then
		return cached or nil
	end
	for _, c in classChain(className) do
		local entries = registry[c]
		local found = entries and entries[key]
		if found ~= nil then
			byClass[key] = found
			return found
		end
	end
	byClass[key] = false
	return nil
end

local signalStore = {}
local function signalOf(proxy, name: string)
	local perInstance = signalStore[proxy]
	if not perInstance then
		perInstance = {}
		signalStore[proxy] = perInstance
	end
	local signal = perInstance[name]
	if not signal then
		local raw = proxyToRaw[proxy]
		signal = Signal.new(raw.ClassName .. "." .. name)
		perInstance[name] = signal
	end
	return signal
end
Engine.signalOf = signalOf

function Engine.fire(proxy, name: string, ...: any)
	signalOf(proxy, name):Fire(...)
end

local function peekSignal(proxy, name: string)
	local perInstance = signalStore[proxy]
	return perInstance and perInstance[name]
end

local callbackStore = {}
function Engine.callback(proxy, name: string)
	local perInstance = callbackStore[proxy]
	return perInstance and perInstance[name]
end

local builtinWrappers = {}
local function builtinMethod(key: string)
	local w = builtinWrappers[key]
	if not w then
		w = function(selfProxy, ...)
			local raw = proxyToRaw[selfProxy]
			if not raw then
				error("Expected ':' not '.' calling member function " .. key, 2)
			end
			local args = table.pack(...)
			for i = 1, args.n do
				args[i] = unwrap(args[i])
			end
			return wrapResults(raw[key](raw, table.unpack(args, 1, args.n)))
		end
		builtinWrappers[key] = w
	end
	return w
end

local deprecatedSeen = {}
local function noteDeprecated(what: string)
	if not deprecatedSeen[what] then
		deprecatedSeen[what] = true
		report("deprecated", what)
	end
end

ProxyMeta.__index = function(proxy, key)
	local raw = proxyToRaw[proxy]
	local className = raw.ClassName
	if type(key) ~= "string" then
		error("invalid key to Instance index", 2)
	end
	local custom = findCustom(methods, className, key)
	if custom then
		return custom
	end
	local get = findCustom(getters, className, key)
	if get then
		return get(proxy)
	end
	if findCustom(eventNames, className, key) then
		return signalOf(proxy, key)
	end
	if findCustom(callbackNames, className, key) then
		error(key .. " is a callback member of " .. className .. "; you can only set the callback value, get is not available", 2)
	end
	local info = propInfo(className, key)
	if info then
		if info.Scriptability == "None" then
			error(key .. " is not a valid member of " .. className, 2)
		end
		if hasTag(info, "Deprecated") then
			noteDeprecated(className .. "." .. key)
		end
		local ok, value = pcall(function()
			return raw[key]
		end)
		if ok then
			return wrap(value)
		end
		return defaultFor(info.Datatype)
	end
	local ok, value = pcall(function()
		return raw[key]
	end)
	if ok and value ~= nil then
		if type(value) == "function" then
			return builtinMethod(key)
		end
		return wrap(value)
	end
	local child = raw:FindFirstChild(key)
	if child then
		return wrap(child)
	end
	error(string.format('%s is not a valid member of %s "%s"', key, className, raw:GetFullName()), 2)
end

local INT_TYPES = { Int32 = true, Int64 = true }

ProxyMeta.__newindex = function(proxy, key, value)
	local raw = proxyToRaw[proxy]
	local className = raw.ClassName
	local set = findCustom(setters, className, key)
	if set then
		set(proxy, value)
		local changed = peekSignal(proxy, "prop:" .. key)
		if changed then
			changed:Fire()
		end
		return
	end
	if findCustom(callbackNames, className, key) then
		if value ~= nil and type(value) ~= "function" then
			error(key .. " must be a function", 2)
		end
		callbackStore[proxy] = callbackStore[proxy] or {}
		callbackStore[proxy][key] = value
		return
	end
	local info = propInfo(className, key)
	if not info then
		error(string.format("%s is not a valid member of %s", tostring(key), className), 2)
	end
	if key == "Parent" and destroyed[raw] then
		local newParent = unwrap(value)
		error(
			string.format(
				"The Parent property of %s is locked, current parent: NULL, new parent %s",
				raw.Name,
				if newParent then newParent.Name else "NULL"
			),
			2
		)
	end
	if info.Scriptability == "Read" or info.Scriptability == "None" or hasTag(info, "ReadOnly") then
		error(string.format("Unable to assign property %s. Property is read only (%s)", key, className), 2)
	end
	if hasTag(info, "Deprecated") then
		noteDeprecated(className .. "." .. key)
	end
	local v = unwrap(value)
	if INT_TYPES[info.Datatype] and type(v) == "number" then
		v = math.floor(v)
	end
	if v ~= v then
		report("nan", string.format("NaN assigned to %s.%s\n%s", className, key, debug.traceback("", 2)))
	end
	local ok, err = pcall(function()
		raw[key] = v
	end)
	if not ok then
		error(string.format("%s.%s: %s", className, key, tostring(err)), 2)
	end
	local changed = peekSignal(proxy, "prop:" .. key)
	if changed then
		changed:Fire()
	end
	local anyChange = peekSignal(proxy, "Changed")
	if anyChange then
		anyChange:Fire(key)
	end
end

ProxyMeta.__tostring = function(proxy)
	return proxyToRaw[proxy].Name
end

---------------------------------------------------------------------------------------------------
-- Datatype shims missing from Lune

local function strictRecord(typeName: string, fields: { [string]: any }, methodsTable: { [string]: any }?)
	local store = table.clone(fields)
	local known = {}
	for k in fields do
		known[k] = true
	end
	return setmetatable({}, {
		__type = typeName,
		__index = function(_, key)
			if methodsTable and methodsTable[key] then
				return methodsTable[key]
			end
			if not known[key] then
				error(tostring(key) .. " is not a valid member of " .. typeName, 2)
			end
			return store[key]
		end,
		__newindex = function(_, key, value)
			if not known[key] then
				error(tostring(key) .. " is not a valid member of " .. typeName, 2)
			end
			store[key] = value
		end,
	})
end

local RaycastParamsShim = {}
function RaycastParamsShim.new()
	local params
	params = strictRecord("RaycastParams", {
		FilterType = Enum.RaycastFilterType.Exclude,
		FilterDescendantsInstances = {},
		IgnoreWater = false,
		CollisionGroup = "Default",
		RespectCanCollide = false,
		BruteForceAllSlow = false,
	}, {
		AddToFilter = function(self, value)
			local list = self.FilterDescendantsInstances
			if type(value) == "table" and not isProxy(value) then
				for _, v in value do
					table.insert(list, v)
				end
			else
				table.insert(list, value)
			end
			self.FilterDescendantsInstances = list
		end,
	})
	return params
end

local OverlapParamsShim = {}
function OverlapParamsShim.new()
	return strictRecord("OverlapParams", {
		FilterType = Enum.RaycastFilterType.Exclude,
		FilterDescendantsInstances = {},
		CollisionGroup = "Default",
		RespectCanCollide = false,
		MaxParts = 0,
		BruteForceAllSlow = false,
	})
end

local TweenInfoShim = {}
function TweenInfoShim.new(time, style, direction, repeatCount, reverses, delayTime)
	if time ~= nil and type(time) ~= "number" then
		error("TweenInfo.new: time must be a number", 2)
	end
	if style ~= nil and (typeof(style) ~= "EnumItem" or style.EnumType ~= Enum.EasingStyle) then
		error("TweenInfo.new: invalid EasingStyle", 2)
	end
	if direction ~= nil and (typeof(direction) ~= "EnumItem" or direction.EnumType ~= Enum.EasingDirection) then
		error("TweenInfo.new: invalid EasingDirection", 2)
	end
	return setmetatable({
		Time = time or 1,
		EasingStyle = style or Enum.EasingStyle.Quad,
		EasingDirection = direction or Enum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	}, { __type = "TweenInfo" })
end

local RandomShim = {}
RandomShim.__index = RandomShim
RandomShim.__type = "Random"
local randomCounter = 0
function RandomShim.new(seed: number?)
	randomCounter += 1
	local s = if seed then math.floor(seed) else math.floor(os.clock() * 1e6) + randomCounter * 7919
	s = s % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	return setmetatable({ state = s }, RandomShim)
end
function RandomShim:_next(): number
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end
function RandomShim:NextNumber(min: number?, max: number?): number
	local lo, hi = min or 0, max or 1
	return lo + (hi - lo) * self:_next()
end
function RandomShim:NextInteger(min: number, max: number): number
	if type(min) ~= "number" or type(max) ~= "number" then
		error("Random:NextInteger expects two numbers", 2)
	end
	if max < min then
		error("Random:NextInteger: max must be >= min", 2)
	end
	return math.min(max, min + math.floor((max - min + 1) * self:_next()))
end
function RandomShim:NextUnitVector()
	local v = Vector3.new(self:_next() - 0.5, self:_next() - 0.5, self:_next() - 0.5)
	return if v.Magnitude > 1e-6 then v.Unit else Vector3.xAxis
end
function RandomShim:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
function RandomShim:Clone()
	return setmetatable({ state = self.state }, RandomShim)
end

local DateTimeShim = {}
function DateTimeShim.now()
	local now = os.time()
	return { UnixTimestamp = now, UnixTimestampMillis = now * 1000 }
end

local function typeofShim(v: any): string
	if isProxy(v) then
		return "Instance"
	end
	if type(v) == "table" then
		local mt = getmetatable(v)
		if type(mt) == "table" and rawget(mt, "__type") then
			return mt.__type
		end
	end
	return typeof(v)
end
Engine.typeof = typeofShim

---------------------------------------------------------------------------------------------------
-- Remote / DataStore serialization rules

local function wireCopy(value: any, path: string, context: string, seen: { [any]: boolean }?): any
	local t = type(value)
	if t == "function" or t == "thread" then
		report(context, string.format("%s at %s cannot be sent (Roblox drops it)", t, path))
		return nil
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			report(context, string.format("non-finite number at %s", path))
		end
		return value
	elseif t ~= "table" then
		return value
	end
	if isProxy(value) then
		if context == "datastore" then
			report(context, "Instance stored at " .. path)
		end
		return value
	end
	if getmetatable(value) ~= nil then
		report(context, "table with a metatable at " .. path .. " (metatables are stripped)")
	end
	local visited = seen or {}
	if visited[value] then
		report(context, "cyclic table at " .. path)
		return nil
	end
	visited[value] = true
	local count, stringKeys, maxIndex = 0, 0, 0
	for k in value do
		count += 1
		if type(k) == "string" then
			stringKeys += 1
		elseif type(k) == "number" and k == math.floor(k) and k >= 1 then
			maxIndex = math.max(maxIndex, k)
		else
			report(context, string.format("unsupported key type %s at %s", type(k), path))
		end
	end
	local out = {}
	if count > 0 and stringKeys == 0 then
		if maxIndex ~= count then
			report(context, string.format("sparse array at %s (%d entries, max index %d): Roblox truncates at the first nil", path, count, maxIndex))
		end
		for i = 1, maxIndex do
			out[i] = wireCopy(value[i], path .. "[" .. i .. "]", context, visited)
		end
	else
		if stringKeys ~= count then
			report(context, string.format("mixed table at %s (%d string keys, %d other): Roblox drops keys", path, stringKeys, count - stringKeys))
		end
		for k, v in value do
			out[k] = wireCopy(v, path .. "." .. tostring(k), context, visited)
		end
	end
	visited[value] = nil
	return out
end
Engine.wireCopy = wireCopy

local function copyArgs(args, label: string)
	local out = { n = args.n }
	for i = 1, args.n do
		out[i] = wireCopy(args[i], label .. "#" .. i, "remote")
	end
	return out
end

local function deepCopy(v: any): any
	if type(v) ~= "table" or isProxy(v) then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end
Engine.deepCopy = deepCopy

---------------------------------------------------------------------------------------------------
-- Place + realms

function Engine.load(path: string)
	Engine.rawGame = roblox.deserializePlace(fs.readFile(path))
	Engine.game = wrap(Engine.rawGame)
	local rawWorkspace = Engine.rawGame:GetService("Workspace")
	Engine.workspace = wrap(rawWorkspace)
	if not rawWorkspace:FindFirstChild("Terrain") then
		local terrain = roblox.Instance.new("Terrain")
		terrain.Name = "Terrain"
		terrain.Parent = rawWorkspace
	end
	Engine.terrain = wrap(rawWorkspace:FindFirstChild("Terrain"))
	Engine.startedAt = os.clock()
	return Engine.game
end

function Engine.service(name: string)
	return wrap(Engine.rawGame:GetService(name))
end

local taskShim = {
	wait = lunetask.wait,
	cancel = lunetask.cancel,
	spawn = function(f, ...)
		if type(f) == "thread" then
			return lunetask.spawn(f, ...)
		end
		return lunetask.spawn(protect, "task.spawn", f, ...)
	end,
	defer = function(f, ...)
		if type(f) == "thread" then
			return lunetask.defer(f, ...)
		end
		return lunetask.defer(protect, "task.defer", f, ...)
	end,
	delay = function(t, f, ...)
		if type(f) == "thread" then
			return lunetask.delay(t, f, ...)
		end
		return lunetask.delay(t, protect, "task.delay", f, ...)
	end,
	synchronize = function() end,
	desynchronize = function() end,
}

local InstanceShim = {}
function InstanceShim.new(className: string, parent: any?)
	if type(className) ~= "string" then
		error("Instance.new expects a class name", 2)
	end
	local def = db:GetClass(className)
	if not def then
		error('Unable to create an Instance of type "' .. className .. '"', 2)
	end
	for _, tag in def.Tags or {} do
		if tag == "NotCreatable" or tag == "Service" then
			error('Unable to create an Instance of type "' .. className .. '"', 2)
		end
		if tag == "Deprecated" then
			noteDeprecated('Instance.new("' .. className .. '")')
		end
	end
	local p = wrap(roblox.Instance.new(className))
	if parent ~= nil then
		noteDeprecated("Instance.new parent argument")
		p.Parent = parent
	end
	return p
end
function InstanceShim.fromExisting(instance)
	return wrap(unwrap(instance):Clone())
end

local function makeRealm(name: string)
	local realm = { name = name, cache = {}, loading = {}, shared = {}, G = {} }

	local env
	function realm.require(target)
		if type(target) == "string" then
			error("require by string path is not supported in Roblox scripts: " .. target, 2)
		end
		local raw = unwrap(target)
		if typeof(raw) ~= "Instance" or not raw:IsA("ModuleScript") then
			error("Attempted to call require with invalid argument(s).", 2)
		end
		local cached = realm.cache[raw]
		if cached then
			return cached.value
		end
		if realm.loading[raw] then
			error("Requested module was required recursively: " .. raw:GetFullName(), 2)
		end
		realm.loading[raw] = true
		local fn = realm.compile(raw)
		local results = table.pack(fn())
		realm.loading[raw] = nil
		if results.n ~= 1 then
			error("Module code did not return exactly one value: " .. raw:GetFullName(), 2)
		end
		realm.cache[raw] = { value = results[1] }
		return results[1]
	end

	function realm.env(scriptRaw)
		return {
			game = Engine.game,
			workspace = Engine.workspace,
			script = wrap(scriptRaw),
			require = realm.require,
			Instance = InstanceShim,
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			Vector3int16 = roblox.Vector3int16,
			Vector2int16 = roblox.Vector2int16,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			NumberRange = roblox.NumberRange,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
			Rect = roblox.Rect,
			BrickColor = roblox.BrickColor,
			Font = roblox.Font,
			Ray = roblox.Ray,
			Region3 = roblox.Region3,
			PhysicalProperties = roblox.PhysicalProperties,
			Faces = roblox.Faces,
			Axes = roblox.Axes,
			Enum = roblox.Enum,
			TweenInfo = TweenInfoShim,
			RaycastParams = RaycastParamsShim,
			OverlapParams = OverlapParamsShim,
			Random = RandomShim,
			DateTime = DateTimeShim,
			typeof = typeofShim,
			task = taskShim,
			print = function(...)
				print("[" .. name .. "]", ...)
			end,
			warn = function(...)
				onWarn(name, ...)
			end,
			tick = function()
				noteDeprecated("tick()")
				return os.clock()
			end,
			time = function()
				return Engine.time
			end,
			elapsedTime = os.clock,
			wait = function(t)
				noteDeprecated("wait()")
				return lunetask.wait(t)
			end,
			delay = function(t, f)
				noteDeprecated("delay()")
				return taskShim.delay(t, f)
			end,
			spawn = function(f)
				noteDeprecated("spawn()")
				return taskShim.defer(f)
			end,
			shared = realm.shared,
			_G = realm.G,
			version = function()
				return "0.728.0"
			end,
		}
	end

	function realm.compile(raw)
		local source = raw.Source
		local ok, fn = pcall(luau.load, source, { debugName = raw:GetFullName(), environment = realm.env(raw) })
		if not ok then
			error("Compile error in " .. raw:GetFullName() .. ": " .. tostring(fn), 0)
		end
		return fn
	end

	function realm.run(raw)
		local ok, fn = pcall(realm.compile, raw)
		if not ok then
			report("compile", tostring(fn))
			return
		end
		lunetask.spawn(protect, raw:GetFullName(), fn)
	end

	-- Access a realm module from the test (same cache the scripts use).
	function realm.module(path: string)
		local current = Engine.rawGame
		for part in string.gmatch(path, "[^%.]+") do
			current = current:FindFirstChild(part)
			if not current then
				error("module path not found: " .. path)
			end
		end
		return realm.require(wrap(current))
	end

	return realm
end

Engine.server = makeRealm("server")
Engine.client = makeRealm("client")

function Engine.runServerScripts()
	local sss = Engine.rawGame:GetService("ServerScriptService")
	for _, d in sss:GetDescendants() do
		if d.ClassName == "Script" and not d.Disabled then
			Engine.server.run(d)
		end
	end
end

function Engine.runClientScripts(playerProxy)
	local player = unwrap(playerProxy)
	local playerScripts = player:FindFirstChild("PlayerScripts")
	local starter = Engine.rawGame:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	if starter then
		for _, child in starter:GetChildren() do
			child:Clone().Parent = playerScripts
		end
	end
	local starterGui = Engine.rawGame:GetService("StarterGui")
	for _, child in starterGui:GetChildren() do
		child:Clone().Parent = player:FindFirstChild("PlayerGui")
	end
	for _, d in playerScripts:GetDescendants() do
		if d.ClassName == "LocalScript" and not d.Disabled then
			Engine.client.run(d)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Players and characters

function Engine.addPlayer(name: string, userId: number)
	local raw = roblox.Instance.new("Player")
	raw.Name = name
	raw.UserId = userId
	local gui = roblox.Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = raw
	local scripts = roblox.Instance.new("PlayerScripts")
	scripts.Name = "PlayerScripts"
	scripts.Parent = raw
	local backpack = roblox.Instance.new("Backpack")
	backpack.Name = "Backpack"
	backpack.Parent = raw
	raw.Parent = Engine.rawGame:GetService("Players")
	local proxy = wrap(raw)
	Engine.localPlayer = Engine.localPlayer or proxy
	Engine.fire(Engine.service("Players"), "PlayerAdded", proxy)
	return proxy
end

function Engine.removePlayer(playerProxy)
	local players = Engine.service("Players")
	Engine.fire(players, "PlayerRemoving", playerProxy)
	lunetask.wait(0.05)
	local raw = unwrap(playerProxy)
	if playerProxy == Engine.localPlayer then
		-- The departed player's client is gone: stop delivering frames and events to it.
		Engine.clientStopped = true
	end
	local character = raw.Character
	if character then
		Engine.destroyRaw(character)
	end
	raw.Parent = nil
end

local humanoidState = {}

function Engine.spawnCharacter(playerProxy)
	local player = unwrap(playerProxy)
	local old = player.Character
	if old then
		Engine.fire(playerProxy, "CharacterRemoving", wrap(old))
		Engine.destroyRaw(old)
	end
	local model = roblox.Instance.new("Model")
	model.Name = player.Name
	local function part(partName: string, size: Vector3, offset: Vector3)
		local p = roblox.Instance.new("Part")
		p.Name = partName
		p.Size = size
		p.CFrame = CFrame.new(offset)
		p.Parent = model
		return p
	end
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero)
	root.Transparency = 1
	part("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 0.4, 0))
	part("LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, -0.8, 0))
	part("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.8, 0))
	local humanoid = roblox.Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.WalkSpeed = 16
	humanoid.Parent = model
	local animator = roblox.Instance.new("Animator")
	animator.Parent = humanoid
	model.PrimaryPart = root
	local target = CFrame.new(0, 5, 0)
	local spawnLocation = player.RespawnLocation
	if spawnLocation then
		target = spawnLocation.CFrame + Vector3.new(0, spawnLocation.Size.Y / 2 + 3, 0)
	end
	wrap(model):PivotTo(target)
	model.Parent = Engine.rawGame:GetService("Workspace")
	player.Character = model
	humanoidState[wrap(humanoid)] = { enabled = {}, state = Enum.HumanoidStateType.Running }
	Engine.fire(playerProxy, "CharacterAdded", wrap(model))
	return wrap(model)
end

function Engine.kill(playerProxy)
	local character = unwrap(playerProxy).Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		wrap(humanoid).Health = 0
	end
end

---------------------------------------------------------------------------------------------------
-- Frame loop, proximity prompts

local function rootOf(playerProxy)
	local character = playerProxy and unwrap(playerProxy).Character
	return character and character:FindFirstChild("HumanoidRootPart")
end
Engine.rootOf = function(playerProxy)
	local root = rootOf(playerProxy)
	return root and wrap(root)
end

local promptCache, promptCacheAt = {}, -1
local shownPrompts = {}
local function proximityStep()
	local player = Engine.localPlayer
	local root = rootOf(player)
	if not root then
		return
	end
	if os.clock() - promptCacheAt > 1 then
		promptCacheAt = os.clock()
		promptCache = {}
		for _, d in Engine.rawGame:GetService("Workspace"):GetDescendants() do
			if d.ClassName == "ProximityPrompt" then
				table.insert(promptCache, d)
			end
		end
	end
	local service = Engine.service("ProximityPromptService")
	local position = root.CFrame.Position
	for _, prompt in promptCache do
		local parent = prompt.Parent
		local at: Vector3? = nil
		if parent and parent:IsA("BasePart") then
			at = parent.CFrame.Position
		elseif parent and parent:IsA("Attachment") then
			local owner = parent.Parent
			at = owner and owner:IsA("BasePart") and (owner.CFrame * parent.CFrame).Position or nil
		end
		local p = wrap(prompt)
		local inRange = at ~= nil and prompt.Enabled and prompt.Parent ~= nil and (position - at).Magnitude <= prompt.MaxActivationDistance
		if inRange and not shownPrompts[p] then
			shownPrompts[p] = true
			Engine.fire(service, "PromptShown", p, Enum.ProximityPromptInputType.Keyboard)
			Engine.fire(p, "PromptShown", Enum.ProximityPromptInputType.Keyboard)
		elseif not inRange and shownPrompts[p] then
			shownPrompts[p] = nil
			Engine.fire(service, "PromptHidden", p)
			Engine.fire(p, "PromptHidden")
		end
	end
end

function Engine.startFrames()
	local runService = Engine.service("RunService")
	lunetask.spawn(function()
		local last = os.clock()
		while Engine.running do
			lunetask.wait(1 / 60)
			local now = os.clock()
			local dt = math.min(0.1, now - last)
			last = now
			Engine.time += dt
			local render = not Engine.clientStopped and peekSignal(runService, "RenderStepped")
			if render then
				render:Fire(dt)
			end
			local stepped = peekSignal(runService, "Stepped")
			if stepped then
				stepped:Fire(Engine.time, dt)
			end
			local heartbeat = peekSignal(runService, "Heartbeat")
			if heartbeat then
				heartbeat:Fire(dt)
			end
			local ok, err = pcall(proximityStep)
			if not ok then
				report("engine", "proximity: " .. tostring(err))
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------
-- Events and callbacks

local EVENTS = {
	Instance = {
		"Destroying",
		"AncestryChanged",
		"ChildAdded",
		"ChildRemoved",
		"DescendantAdded",
		"DescendantRemoving",
		"Changed",
		"AttributeChanged",
	},
	DataModel = { "Loaded", "Close" },
	GuiButton = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click" },
	GuiObject = { "MouseEnter", "MouseLeave", "MouseMoved", "InputBegan", "InputEnded", "InputChanged", "SelectionGained", "SelectionLost" },
	TextBox = { "FocusLost", "Focused" },
	Players = { "PlayerAdded", "PlayerRemoving" },
	Player = { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted" },
	Humanoid = { "Died", "StateChanged", "Running", "HealthChanged", "Jumping", "Swimming", "MoveToFinished" },
	ProximityPromptService = {
		"PromptTriggered",
		"PromptShown",
		"PromptHidden",
		"PromptButtonHoldBegan",
		"PromptButtonHoldEnded",
		"PromptTriggerEnded",
	},
	ProximityPrompt = { "Triggered", "TriggerEnded", "PromptShown", "PromptHidden", "PromptButtonHoldBegan", "PromptButtonHoldEnded" },
	MarketplaceService = { "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished", "PromptPurchaseFinished" },
	RemoteEvent = { "OnServerEvent", "OnClientEvent" },
	UnreliableRemoteEvent = { "OnServerEvent", "OnClientEvent" },
	BindableEvent = { "Event" },
	RunService = { "Heartbeat", "RenderStepped", "Stepped", "PreSimulation", "PostSimulation", "PreRender", "PreAnimation" },
	UserInputService = {
		"InputBegan",
		"InputEnded",
		"InputChanged",
		"LastInputTypeChanged",
		"TouchStarted",
		"TouchEnded",
		"TouchMoved",
		"JumpRequest",
		"WindowFocused",
		"WindowFocusReleased",
	},
	BasePart = { "Touched", "TouchEnded" },
	Sound = { "Ended", "Loaded", "Played", "Stopped" },
	ClickDetector = { "MouseClick" },
	Animator = { "AnimationPlayed" },
}
for className, names in EVENTS do
	eventNames[className] = eventNames[className] or {}
	for _, n in names do
		eventNames[className][n] = true
	end
end

local CALLBACKS = {
	RemoteFunction = { "OnServerInvoke", "OnClientInvoke" },
	BindableFunction = { "OnInvoke" },
	MarketplaceService = { "ProcessReceipt" },
}
for className, names in CALLBACKS do
	callbackNames[className] = callbackNames[className] or {}
	for _, n in names do
		callbackNames[className][n] = true
	end
end

---------------------------------------------------------------------------------------------------
-- Instance methods

method("Instance", "WaitForChild", function(self, childName, timeout)
	local raw = proxyToRaw[self]
	if type(childName) ~= "string" then
		error("WaitForChild expects a string", 2)
	end
	local child = raw:FindFirstChild(childName)
	if child then
		return wrap(child)
	end
	local limit = if type(timeout) == "number" then timeout else 15
	local started = os.clock()
	while os.clock() - started < limit do
		lunetask.wait(0.03)
		child = raw:FindFirstChild(childName)
		if child then
			return wrap(child)
		end
	end
	if timeout == nil then
		report("yield", string.format('Infinite yield possible on %s:WaitForChild("%s")', raw:GetFullName(), childName))
	end
	return nil
end)

local ATTRIBUTE_TYPES = {
	["nil"] = true,
	boolean = true,
	number = true,
	string = true,
	UDim = true,
	UDim2 = true,
	BrickColor = true,
	Color3 = true,
	Vector2 = true,
	Vector3 = true,
	CFrame = true,
	NumberSequence = true,
	ColorSequence = true,
	NumberRange = true,
	Rect = true,
	Font = true,
	EnumItem = true,
}

method("Instance", "SetAttribute", function(self, attribute, value)
	local raw = proxyToRaw[self]
	if type(attribute) ~= "string" or #attribute == 0 or #attribute > 100 or string.find(attribute, "[^%w_]") then
		error("Invalid attribute name: " .. tostring(attribute), 2)
	end
	if string.sub(attribute, 1, 3) == "RBX" then
		error("Attribute names beginning with RBX are reserved", 2)
	end
	local kind = typeofShim(value)
	if not ATTRIBUTE_TYPES[kind] then
		error(string.format("SetAttribute(%s): %s is not a supported attribute type", attribute, kind), 2)
	end
	local old = raw:GetAttribute(attribute)
	raw:SetAttribute(attribute, value)
	if old ~= value then
		local specific = peekSignal(self, "attr:" .. attribute)
		if specific then
			specific:Fire()
		end
		local any = peekSignal(self, "AttributeChanged")
		if any then
			any:Fire(attribute)
		end
	end
end)

method("Instance", "GetAttributeChangedSignal", function(self, attribute)
	return signalOf(self, "attr:" .. tostring(attribute))
end)

method("Instance", "GetPropertyChangedSignal", function(self, property)
	local raw = proxyToRaw[self]
	if not propInfo(raw.ClassName, property) and not findCustom(getters, raw.ClassName, property) then
		error(string.format("%s is not a valid property name.", tostring(property)), 2)
	end
	return signalOf(self, "prop:" .. property)
end)

-- Roblox semantics: Destroy fires Destroying, disconnects the instance's connections, destroys
-- every child and locks Parent, but properties stay readable/writable afterwards.
local function destroyRaw(raw)
	for _, child in raw:GetChildren() do
		destroyRaw(child)
	end
	local proxy = rawToProxy[raw]
	if proxy then
		local destroying = peekSignal(proxy, "Destroying")
		if destroying then
			destroying:Fire()
		end
		signalStore[proxy] = nil
	end
	raw.Parent = nil
	destroyed[raw] = true
end
Engine.destroyRaw = destroyRaw

method("Instance", "Destroy", function(self)
	destroyRaw(proxyToRaw[self])
end)

method("Instance", "ClearAllChildren", function(self)
	for _, child in proxyToRaw[self]:GetChildren() do
		destroyRaw(child)
	end
end)

method("Instance", "Remove", function(self)
	noteDeprecated("Instance:Remove")
	proxyToRaw[self].Parent = nil
end)

---------------------------------------------------------------------------------------------------
-- Geometry (PVInstance, BasePart, Model)

local function descendantsOfClass(raw, className: string)
	local out = {}
	for _, d in raw:GetDescendants() do
		if d:IsA(className) then
			table.insert(out, d)
		end
	end
	return out
end

getter("BasePart", "Position", function(self)
	return proxyToRaw[self].CFrame.Position
end)
setter("BasePart", "Position", function(self, v)
	if typeof(v) ~= "Vector3" then
		error("Position must be a Vector3", 3)
	end
	local raw = proxyToRaw[self]
	raw.CFrame = CFrame.new(v) * raw.CFrame.Rotation
end)
getter("BasePart", "Orientation", function(self)
	local rx, ry, rz = proxyToRaw[self].CFrame:ToOrientation()
	return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
end)
setter("BasePart", "Orientation", function(self, v)
	if typeof(v) ~= "Vector3" then
		error("Orientation must be a Vector3", 3)
	end
	local raw = proxyToRaw[self]
	raw.CFrame = CFrame.new(raw.CFrame.Position) * CFrame.fromOrientation(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end)
getter("BasePart", "Rotation", function(self)
	local rx, ry, rz = proxyToRaw[self].CFrame:ToEulerAnglesXYZ()
	return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
end)
setter("BasePart", "Rotation", function(self, v)
	local raw = proxyToRaw[self]
	raw.CFrame = CFrame.new(raw.CFrame.Position) * CFrame.fromEulerAnglesXYZ(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end)
getter("BasePart", "AssemblyMass", function(self)
	local s = proxyToRaw[self].Size
	return s.X * s.Y * s.Z * 0.7
end)

local modelScale = {}

local function pivotOf(raw): CFrame
	if raw:IsA("BasePart") then
		return raw.CFrame * raw.PivotOffset
	end
	local primary = raw.PrimaryPart
	if primary then
		return primary.CFrame * primary.PivotOffset
	end
	return raw.WorldPivot
end

method("PVInstance", "GetPivot", function(self)
	return pivotOf(proxyToRaw[self])
end)

method("PVInstance", "PivotTo", function(self, target)
	if typeof(target) ~= "CFrame" then
		error("PivotTo expects a CFrame", 2)
	end
	local raw = proxyToRaw[self]
	if raw:IsA("BasePart") then
		raw.CFrame = target * raw.PivotOffset:Inverse()
		return
	end
	local delta = target * pivotOf(raw):Inverse()
	for _, part in descendantsOfClass(raw, "BasePart") do
		part.CFrame = delta * part.CFrame
	end
	if not raw.PrimaryPart then
		raw.WorldPivot = target
	end
end)

local function boundingBox(raw): (CFrame, Vector3)
	local minV, maxV = nil, nil
	for _, part in descendantsOfClass(raw, "BasePart") do
		local cf, size = part.CFrame, part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)
					minV = if minV then minV:Min(corner) else corner
					maxV = if maxV then maxV:Max(corner) else corner
				end
			end
		end
	end
	if not minV then
		return pivotOf(raw), Vector3.zero
	end
	return CFrame.new((minV + maxV) / 2), maxV - minV
end

method("Model", "GetBoundingBox", function(self)
	return boundingBox(proxyToRaw[self])
end)
method("Model", "GetExtentsSize", function(self)
	local _, size = boundingBox(proxyToRaw[self])
	return size
end)
method("Model", "GetScale", function(self)
	return modelScale[self] or 1
end)
method("Model", "ScaleTo", function(self, scale)
	if type(scale) ~= "number" or scale <= 0 then
		error("ScaleTo expects a positive number", 2)
	end
	local raw = proxyToRaw[self]
	local factor = scale / (modelScale[self] or 1)
	local pivot = pivotOf(raw)
	for _, part in descendantsOfClass(raw, "BasePart") do
		local relative = pivot:ToObjectSpace(part.CFrame)
		part.Size *= factor
		part.CFrame = pivot * (CFrame.new(relative.Position * factor) * relative.Rotation)
	end
	modelScale[self] = scale
end)
method("Model", "SetPrimaryPartCFrame", function(self, cf)
	noteDeprecated("Model:SetPrimaryPartCFrame")
	self:PivotTo(cf)
end)
method("Model", "GetPrimaryPartCFrame", function(self)
	noteDeprecated("Model:GetPrimaryPartCFrame")
	return self:GetPivot()
end)
method("Model", "MoveTo", function(self, position)
	local pivot = self:GetPivot()
	self:PivotTo(CFrame.new(position) * pivot.Rotation)
end)

method("BasePart", "GetMass", function(self)
	local s = proxyToRaw[self].Size
	return s.X * s.Y * s.Z * 0.7
end)
method("BasePart", "SetNetworkOwner", function() end)
method("BasePart", "SetNetworkOwnershipAuto", function() end)
method("BasePart", "GetNetworkOwner", function()
	return nil
end)
method("BasePart", "CanSetNetworkOwnership", function()
	return true
end)
method("BasePart", "ApplyImpulse", function(self, impulse)
	local raw = proxyToRaw[self]
	raw.AssemblyLinearVelocity += impulse / math.max(0.1, raw.Size.X * raw.Size.Y * raw.Size.Z * 0.7)
end)
method("BasePart", "GetConnectedParts", function()
	return {}
end)
method("BasePart", "GetTouchingParts", function()
	return {}
end)

---------------------------------------------------------------------------------------------------
-- Workspace, terrain

local TERRAIN_MATERIALS = {}
for _, n in
	{
		"Air",
		"Asphalt",
		"Basalt",
		"Brick",
		"Cobblestone",
		"Concrete",
		"CrackedLava",
		"Glacier",
		"Grass",
		"Ground",
		"Ice",
		"LeafyGrass",
		"Limestone",
		"Mud",
		"Pavement",
		"Rock",
		"Salt",
		"Sand",
		"Sandstone",
		"Slate",
		"Snow",
		"Water",
		"WoodPlanks",
	}
do
	TERRAIN_MATERIALS[n] = true
end

local function checkTerrainMaterial(material, fn: string)
	if typeof(material) ~= "EnumItem" or material.EnumType ~= Enum.Material then
		error(fn .. ": expected an Enum.Material, got " .. typeofShim(material), 3)
	end
	if not TERRAIN_MATERIALS[material.Name] then
		error(fn .. ": " .. material.Name .. " is not a terrain material", 3)
	end
end

local function checkType(value, expected: string, fn: string, argName: string)
	if typeofShim(value) ~= expected then
		error(string.format("%s: %s must be a %s (got %s)", fn, argName, expected, typeofShim(value)), 3)
	end
	if expected == "number" and (value ~= value or value == math.huge) then
		error(string.format("%s: %s is not finite", fn, argName), 3)
	end
end

-- Every fill is recorded as a shape so tests can ask what material ends up at a point
-- (Engine.terrainAt replays the fills in order).
Engine.terrainOps = {}
local function recordFill(material, center: Vector3, bound: number, contains: (Vector3) -> boolean)
	Engine.terrainCalls += 1
	table.insert(Engine.terrainOps, { material = material.Name, center = center, bound = bound, contains = contains })
end

method("Terrain", "FillBlock", function(_, cf, size, material)
	checkType(cf, "CFrame", "FillBlock", "cframe")
	checkType(size, "Vector3", "FillBlock", "size")
	checkTerrainMaterial(material, "FillBlock")
	local half = size / 2
	recordFill(material, cf.Position, half.Magnitude, function(p)
		local l = cf:PointToObjectSpace(p)
		return math.abs(l.X) <= half.X and math.abs(l.Y) <= half.Y and math.abs(l.Z) <= half.Z
	end)
end)
method("Terrain", "FillBall", function(_, center, radius, material)
	checkType(center, "Vector3", "FillBall", "center")
	checkType(radius, "number", "FillBall", "radius")
	checkTerrainMaterial(material, "FillBall")
	recordFill(material, center, radius, function(p)
		return (p - center).Magnitude <= radius
	end)
end)
method("Terrain", "FillCylinder", function(_, cf, height, radius, material)
	checkType(cf, "CFrame", "FillCylinder", "cframe")
	checkType(height, "number", "FillCylinder", "height")
	checkType(radius, "number", "FillCylinder", "radius")
	checkTerrainMaterial(material, "FillCylinder")
	recordFill(material, cf.Position, math.sqrt(radius * radius + height * height / 4), function(p)
		local l = cf:PointToObjectSpace(p)
		return math.abs(l.Y) <= height / 2 and l.X * l.X + l.Z * l.Z <= radius * radius
	end)
end)
method("Terrain", "FillWedge", function(_, cf, size, material)
	checkType(cf, "CFrame", "FillWedge", "cframe")
	checkType(size, "Vector3", "FillWedge", "size")
	checkTerrainMaterial(material, "FillWedge")
	-- Same shape as a WedgePart: full height at +Z, thinning to the bottom edge at -Z.
	local half = size / 2
	recordFill(material, cf.Position, half.Magnitude, function(p)
		local l = cf:PointToObjectSpace(p)
		if math.abs(l.X) > half.X or math.abs(l.Z) > half.Z or l.Y < -half.Y then
			return false
		end
		return l.Y <= -half.Y + size.Y * (l.Z + half.Z) / size.Z
	end)
end)

-- Material at `p` after replaying every fill. rule "empty": Water only fills empty space (what
-- Roblox does); rule "replace": Water overwrites solids too. Robust terrain code works under both.
function Engine.terrainAt(p: Vector3, rule: string?): string
	local material = "Air"
	for _, op in Engine.terrainOps do
		if (p - op.center).Magnitude <= op.bound and op.contains(p) then
			if op.material == "Water" then
				if rule == "replace" or material == "Air" then
					material = "Water"
				end
			else
				material = op.material
			end
		end
	end
	return material
end
method("Terrain", "FillRegion", function(_, region, resolution, material)
	checkType(region, "Region3", "FillRegion", "region")
	checkTerrainMaterial(material, "FillRegion")
	Engine.terrainCalls += 1
end)
method("Terrain", "Clear", function() end)
local materialColors = {}
method("Terrain", "SetMaterialColor", function(_, material, color)
	checkTerrainMaterial(material, "SetMaterialColor")
	checkType(color, "Color3", "SetMaterialColor", "color")
	materialColors[material] = color
end)
method("Terrain", "GetMaterialColor", function(_, material)
	checkTerrainMaterial(material, "GetMaterialColor")
	return materialColors[material] or Color3.new(0.5, 0.5, 0.5)
end)

method("WorldRoot", "Raycast", function(_, origin, direction, params)
	checkType(origin, "Vector3", "Raycast", "origin")
	checkType(direction, "Vector3", "Raycast", "direction")
	if params ~= nil and typeofShim(params) ~= "RaycastParams" then
		error("Raycast: params must be RaycastParams", 2)
	end
	if Engine.raycastHook then
		return Engine.raycastHook(origin, direction, params)
	end
	return nil
end)
method("WorldRoot", "Spherecast", function()
	return nil
end)
method("WorldRoot", "Blockcast", function()
	return nil
end)
method("WorldRoot", "GetPartBoundsInRadius", function()
	return {}
end)
method("WorldRoot", "GetPartBoundsInBox", function()
	return {}
end)
method("WorldRoot", "GetPartsInPart", function()
	return {}
end)
method("WorldRoot", "BulkMoveTo", function(_, parts, cframes, mode)
	if type(parts) ~= "table" or type(cframes) ~= "table" or #parts ~= #cframes then
		error("BulkMoveTo: parts and cframes must be arrays of equal length", 2)
	end
	if mode ~= nil and (typeof(mode) ~= "EnumItem" or mode.EnumType ~= Enum.BulkMoveMode) then
		error("BulkMoveTo: invalid BulkMoveMode", 2)
	end
	for i, p in parts do
		local raw = unwrap(p)
		if typeof(raw) ~= "Instance" or not raw:IsA("BasePart") then
			error("BulkMoveTo: entry " .. i .. " is not a BasePart", 2)
		end
		raw.CFrame = cframes[i]
	end
end)
method("Workspace", "GetServerTimeNow", function()
	return 1.7e9 + os.clock()
end)
method("Workspace", "FindPartOnRay", function()
	noteDeprecated("Workspace:FindPartOnRay")
	return nil
end)

getter("Workspace", "CurrentCamera", function(self)
	local raw = proxyToRaw[self]
	local camera = raw:FindFirstChildOfClass("Camera")
	if not camera then
		camera = roblox.Instance.new("Camera")
		camera.Name = "Camera"
		camera.CFrame = CFrame.new(0, 20, 40)
		camera.Parent = raw
	end
	return wrap(camera)
end)
getter("Workspace", "DistributedGameTime", function()
	return Engine.time
end)
getter("Camera", "ViewportSize", function()
	return Engine.options.viewport
end)
method("Camera", "WorldToViewportPoint", function(_, position)
	return Vector3.new(Engine.options.viewport.X / 2, Engine.options.viewport.Y / 2, 10), true
end)
method("Camera", "WorldToScreenPoint", function(_, position)
	return Vector3.new(Engine.options.viewport.X / 2, Engine.options.viewport.Y / 2, 10), true
end)
method("Camera", "ScreenPointToRay", function(self)
	local cf = proxyToRaw[self].CFrame
	return roblox.Ray.new(cf.Position, cf.LookVector)
end)
method("Camera", "ViewportPointToRay", function(self)
	local cf = proxyToRaw[self].CFrame
	return roblox.Ray.new(cf.Position, cf.LookVector)
end)

---------------------------------------------------------------------------------------------------
-- GUI metrics

local function absoluteSize(raw): Vector2
	if raw:IsA("LayerCollector") then
		if raw:IsA("BillboardGui") or raw:IsA("SurfaceGui") then
			local size = raw:IsA("BillboardGui") and raw.Size or roblox.UDim2.fromOffset(800, 600)
			return Vector2.new(size.X.Offset + size.X.Scale * 100, size.Y.Offset + size.Y.Scale * 100)
		end
		-- ScreenGuis inside the safe insets lose the 58px Roblox top bar.
		if raw:IsA("ScreenGui") and not raw.IgnoreGuiInset and raw.ScreenInsets ~= Enum.ScreenInsets.None then
			return Engine.options.viewport - Vector2.new(0, 58)
		end
		return Engine.options.viewport
	end
	if not raw:IsA("GuiObject") then
		return Engine.options.viewport
	end
	local parent = raw.Parent
	local parentSize = if parent and (parent:IsA("GuiObject") or parent:IsA("LayerCollector")) then absoluteSize(parent) else Engine.options.viewport
	local size = raw.Size
	return Vector2.new(parentSize.X * size.X.Scale + size.X.Offset, parentSize.Y * size.Y.Scale + size.Y.Offset)
end

local function absolutePosition(raw): Vector2
	if not raw:IsA("GuiObject") then
		return Vector2.zero
	end
	local parent = raw.Parent
	local parentPos, parentSize = Vector2.zero, Engine.options.viewport
	if parent and parent:IsA("GuiObject") then
		parentPos, parentSize = absolutePosition(parent), absoluteSize(parent)
	end
	local position, anchor, size = raw.Position, raw.AnchorPoint, absoluteSize(raw)
	return parentPos
		+ Vector2.new(parentSize.X * position.X.Scale + position.X.Offset, parentSize.Y * position.Y.Scale + position.Y.Offset)
		- Vector2.new(size.X * anchor.X, size.Y * anchor.Y)
end

getter("GuiBase2d", "AbsoluteSize", function(self)
	return absoluteSize(proxyToRaw[self])
end)
getter("GuiBase2d", "AbsolutePosition", function(self)
	return absolutePosition(proxyToRaw[self])
end)
getter("GuiBase2d", "AbsoluteRotation", function()
	return 0
end)

local function textBounds(self)
	local raw = proxyToRaw[self]
	local text = raw.ContentText ~= "" and raw.ContentText or raw.Text
	local size = raw.TextSize
	local width = (utf8.len(text) or #text) * size * 0.55
	local lines = 1
	for _ in string.gmatch(text, "\n") do
		lines += 1
	end
	return Vector2.new(width, size * lines)
end
for _, className in { "TextLabel", "TextButton", "TextBox" } do
	getter(className, "TextBounds", textBounds)
	getter(className, "TextFits", function()
		return true
	end)
	getter(className, "ContentText", function(self)
		return proxyToRaw[self].Text
	end)
end

getter("UIGridStyleLayout", "AbsoluteContentSize", function(self)
	local raw = proxyToRaw[self]
	local parent = raw.Parent
	if not parent then
		return Vector2.zero
	end
	local horizontal = raw:IsA("UIListLayout") and raw.FillDirection == Enum.FillDirection.Horizontal
	local total, cross = 0, 0
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			local size = absoluteSize(child)
			if horizontal then
				total += size.X
				cross = math.max(cross, size.Y)
			else
				total += size.Y
				cross = math.max(cross, size.X)
			end
		end
	end
	return if horizontal then Vector2.new(total, cross) else Vector2.new(cross, total)
end)
getter("ScrollingFrame", "AbsoluteCanvasSize", function(self)
	local raw = proxyToRaw[self]
	local canvas, size = raw.CanvasSize, absoluteSize(raw)
	return Vector2.new(size.X * canvas.X.Scale + canvas.X.Offset, size.Y * canvas.Y.Scale + canvas.Y.Offset)
end)
getter("ScrollingFrame", "AbsoluteWindowSize", function(self)
	return absoluteSize(proxyToRaw[self])
end)

method("GuiObject", "TweenSize", function(self, size)
	proxyToRaw[self].Size = size
	return true
end)
method("GuiObject", "TweenPosition", function(self, position)
	proxyToRaw[self].Position = position
	return true
end)
method("GuiObject", "TweenSizeAndPosition", function(self, size, position)
	proxyToRaw[self].Size = size
	proxyToRaw[self].Position = position
	return true
end)
method("TextBox", "CaptureFocus", function() end)
method("TextBox", "ReleaseFocus", function() end)
method("TextBox", "IsFocused", function()
	return false
end)

---------------------------------------------------------------------------------------------------
-- Humanoid, animation, effects

local function stateOf(humanoid)
	local state = humanoidState[humanoid]
	if not state then
		state = { enabled = {}, state = Enum.HumanoidStateType.Running }
		humanoidState[humanoid] = state
	end
	return state
end

local function checkState(state, fn: string)
	if typeof(state) ~= "EnumItem" or state.EnumType ~= Enum.HumanoidStateType then
		error(fn .. ": expected a HumanoidStateType", 3)
	end
end

method("Humanoid", "SetStateEnabled", function(self, state, enabled)
	checkState(state, "SetStateEnabled")
	stateOf(self).enabled[state] = enabled == true
end)
method("Humanoid", "GetStateEnabled", function(self, state)
	checkState(state, "GetStateEnabled")
	local value = stateOf(self).enabled[state]
	return value == nil or value
end)
method("Humanoid", "ChangeState", function(self, state)
	checkState(state, "ChangeState")
	local s = stateOf(self)
	local old = s.state
	s.state = state
	Engine.fire(self, "StateChanged", old, state)
end)
method("Humanoid", "GetState", function(self)
	return stateOf(self).state
end)
method("Humanoid", "Move", function() end)
method("Humanoid", "MoveTo", function() end)
method("Humanoid", "UnequipTools", function() end)
method("Humanoid", "TakeDamage", function(self, amount)
	self.Health = math.max(0, proxyToRaw[self].Health - amount)
end)
getter("Humanoid", "MoveDirection", function()
	return Vector3.zero
end)
getter("Humanoid", "RootPart", function(self)
	local model = proxyToRaw[self].Parent
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return root and wrap(root)
end)
getter("Humanoid", "SeatPart", function()
	return nil
end)
getter("Humanoid", "FloorMaterial", function()
	return Enum.Material.Air
end)
setter("Humanoid", "Health", function(self, value)
	local raw = proxyToRaw[self]
	local wasAlive = raw.Health > 0
	raw.Health = math.clamp(value, 0, raw.MaxHealth)
	Engine.fire(self, "HealthChanged", raw.Health)
	if wasAlive and raw.Health <= 0 then
		stateOf(self).state = Enum.HumanoidStateType.Dead
		Engine.fire(self, "Died")
	end
end)

local function newTrack(animation)
	local raw = unwrap(animation)
	if typeof(raw) ~= "Instance" or raw.ClassName ~= "Animation" then
		error("LoadAnimation requires an Animation object", 3)
	end
	if not string.find(raw.AnimationId, "^rbxassetid://%d+$") and not string.find(raw.AnimationId, "^http") then
		error("LoadAnimation: invalid AnimationId " .. raw.AnimationId, 3)
	end
	local track = {
		Animation = animation,
		IsPlaying = false,
		Looped = false,
		Priority = Enum.AnimationPriority.Core,
		Speed = 1,
		Length = 1,
		TimePosition = 0,
		WeightCurrent = 0,
		WeightTarget = 1,
		Stopped = Signal.new("AnimationTrack.Stopped"),
		Ended = Signal.new("AnimationTrack.Ended"),
		DidLoop = Signal.new("AnimationTrack.DidLoop"),
		KeyframeReached = Signal.new("AnimationTrack.KeyframeReached"),
	}
	function track:Play(fade, weight, speed)
		self.IsPlaying = true
		if speed then
			self.Speed = speed
		end
	end
	function track:Stop()
		if self.IsPlaying then
			self.IsPlaying = false
			self.Stopped:Fire()
		end
	end
	function track:AdjustSpeed(speed)
		if type(speed) ~= "number" or speed ~= speed then
			error("AdjustSpeed expects a number", 2)
		end
		self.Speed = speed
	end
	function track:AdjustWeight(weight)
		self.WeightTarget = weight
	end
	function track:GetMarkerReachedSignal()
		return Signal.new("AnimationTrack.Marker")
	end
	function track:Destroy()
		self.IsPlaying = false
	end
	return track
end

method("Animator", "LoadAnimation", function(_, animation)
	return newTrack(animation)
end)
method("Humanoid", "LoadAnimation", function(_, animation)
	noteDeprecated("Humanoid:LoadAnimation")
	return newTrack(animation)
end)
method("AnimationController", "LoadAnimation", function(_, animation)
	noteDeprecated("AnimationController:LoadAnimation")
	return newTrack(animation)
end)
method("Animator", "GetPlayingAnimationTracks", function()
	return {}
end)

method("ParticleEmitter", "Emit", function(_, count)
	if count ~= nil and type(count) ~= "number" then
		error("Emit expects a number", 2)
	end
end)
method("ParticleEmitter", "Clear", function() end)
method("Trail", "Clear", function() end)
method("Beam", "SetTextureOffset", function() end)
method("Sound", "Play", function(self)
	local raw = proxyToRaw[self]
	if raw.SoundId == "" then
		report("sound", "Sound:Play() with an empty SoundId (" .. raw:GetFullName() .. ")")
	end
	raw.Playing = true
end)
method("Sound", "Stop", function(self)
	proxyToRaw[self].Playing = false
end)
method("Sound", "Pause", function(self)
	proxyToRaw[self].Playing = false
end)
method("Sound", "Resume", function(self)
	proxyToRaw[self].Playing = true
end)
getter("Sound", "IsPlaying", function(self)
	return proxyToRaw[self].Playing
end)
getter("Sound", "IsLoaded", function()
	return true
end)
getter("Sound", "TimeLength", function()
	return 1
end)
getter("Sound", "PlaybackLoudness", function()
	return 0
end)

---------------------------------------------------------------------------------------------------
-- Remotes

local function logTraffic(direction: string, remote, args)
	table.insert(Engine.traffic, { t = os.clock(), dir = direction, remote = proxyToRaw[remote].Name, args = args })
end

local function sendToServer(self, ...)
	local args = copyArgs(table.pack(...), proxyToRaw[self].Name .. ":FireServer")
	logTraffic("c2s", self, args)
	lunetask.delay(Engine.options.latency, function()
		Engine.fire(self, "OnServerEvent", Engine.localPlayer, table.unpack(args, 1, args.n))
	end)
end

local function sendToClient(self, player, ...)
	if not isProxy(player) or proxyToRaw[player].ClassName ~= "Player" then
		error("FireClient: player argument must be a Player", 2)
	end
	local args = copyArgs(table.pack(...), proxyToRaw[self].Name .. ":FireClient")
	logTraffic("s2c", self, args)
	if player ~= Engine.localPlayer then
		return
	end
	lunetask.delay(Engine.options.latency, function()
		Engine.fire(self, "OnClientEvent", table.unpack(args, 1, args.n))
	end)
end

for _, className in { "RemoteEvent", "UnreliableRemoteEvent" } do
	method(className, "FireServer", sendToServer)
	method(className, "FireClient", sendToClient)
	method(className, "FireAllClients", function(self, ...)
		if Engine.localPlayer then
			sendToClient(self, Engine.localPlayer, ...)
		end
	end)
end

method("RemoteFunction", "InvokeServer", function(self, ...)
	local name = proxyToRaw[self].Name
	local args = copyArgs(table.pack(...), name .. ":InvokeServer")
	logTraffic("c2s", self, args)
	lunetask.wait(Engine.options.latency)
	local waited = 0
	local callback = Engine.callback(self, "OnServerInvoke")
	while not callback do
		lunetask.wait(0.05)
		waited += 0.05
		if waited > 15 then
			report("remote", name .. ":InvokeServer never got an OnServerInvoke handler")
			return nil
		end
		callback = Engine.callback(self, "OnServerInvoke")
	end
	local results = table.pack(pcall(callback, Engine.localPlayer, table.unpack(args, 1, args.n)))
	lunetask.wait(Engine.options.latency)
	if not results[1] then
		error(results[2], 2)
	end
	local out = { n = results.n - 1 }
	for i = 2, results.n do
		out[i - 1] = wireCopy(results[i], name .. ":InvokeServer return #" .. (i - 1), "remote")
	end
	table.insert(Engine.traffic, { t = os.clock(), dir = "s2c-return", remote = name, args = out, request = args })
	return table.unpack(out, 1, out.n)
end)
method("RemoteFunction", "InvokeClient", function()
	report("remote", "InvokeClient is unsafe (a client can hang the server)")
	return nil
end)
method("BindableEvent", "Fire", function(self, ...)
	Engine.fire(self, "Event", ...)
end)
method("BindableFunction", "Invoke", function(self, ...)
	local callback = Engine.callback(self, "OnInvoke")
	if not callback then
		error("BindableFunction has no OnInvoke", 2)
	end
	return callback(...)
end)

---------------------------------------------------------------------------------------------------
-- Services

method("DataModel", "BindToClose", function(_, fn)
	if type(fn) ~= "function" then
		error("BindToClose expects a function", 2)
	end
	table.insert(Engine.closeCallbacks, fn)
end)
method("DataModel", "IsLoaded", function()
	return true
end)
getter("DataModel", "JobId", function()
	return if Engine.options.studio then "" else "test-job-1"
end)
getter("DataModel", "PlaceId", function()
	return 0
end)
getter("DataModel", "GameId", function()
	return 0
end)
getter("DataModel", "CreatorId", function()
	return 0
end)
getter("DataModel", "PlaceVersion", function()
	return 1
end)

method("RunService", "IsStudio", function()
	return Engine.options.studio
end)
method("RunService", "IsServer", function()
	return true
end)
method("RunService", "IsClient", function()
	return true
end)
method("RunService", "IsRunning", function()
	return true
end)
method("RunService", "IsRunMode", function()
	return true
end)
local renderBindings = {}
method("RunService", "BindToRenderStep", function(self, bindName, priority, fn)
	if type(fn) ~= "function" then
		error("BindToRenderStep expects a function", 2)
	end
	renderBindings[bindName] = signalOf(self, "RenderStepped"):Connect(fn)
end)
method("RunService", "UnbindFromRenderStep", function(_, bindName)
	local c = renderBindings[bindName]
	if c then
		c:Disconnect()
		renderBindings[bindName] = nil
	end
end)

method("Players", "GetPlayers", function(self)
	local out = {}
	for _, child in proxyToRaw[self]:GetChildren() do
		if child.ClassName == "Player" then
			table.insert(out, wrap(child))
		end
	end
	return out
end)
method("Players", "GetPlayerByUserId", function(self, userId)
	for _, child in proxyToRaw[self]:GetChildren() do
		if child.ClassName == "Player" and child.UserId == userId then
			return wrap(child)
		end
	end
	return nil
end)
method("Players", "GetPlayerFromCharacter", function(self, character)
	local rawCharacter = unwrap(character)
	for _, child in proxyToRaw[self]:GetChildren() do
		if child.ClassName == "Player" and child.Character == rawCharacter then
			return wrap(child)
		end
	end
	return nil
end)
getter("Players", "LocalPlayer", function()
	return Engine.localPlayer
end)

method("Player", "LoadCharacterAsync", function(self)
	lunetask.wait(0.05)
	if not proxyToRaw[self].Parent then
		error("LoadCharacterAsync: player has left", 2)
	end
	Engine.spawnCharacter(self)
end)
method("Player", "LoadCharacter", function(self)
	noteDeprecated("Player:LoadCharacter")
	Engine.spawnCharacter(self)
end)
method("Player", "Kick", function(self, message)
	report("kick", tostring(proxyToRaw[self].Name) .. " kicked: " .. tostring(message))
	lunetask.defer(Engine.removePlayer, self)
end)
method("Player", "GetMouse", function()
	return { Hit = CFrame.identity, Target = nil, X = 0, Y = 0, Icon = "" }
end)
method("Player", "IsInGroup", function()
	return false
end)
method("Player", "GetRankInGroup", function()
	return 0
end)

getter("UserInputService", "TouchEnabled", function()
	return Engine.options.touch
end)
getter("UserInputService", "KeyboardEnabled", function()
	return not Engine.options.touch
end)
getter("UserInputService", "MouseEnabled", function()
	return not Engine.options.touch
end)
getter("UserInputService", "GamepadEnabled", function()
	return false
end)
getter("UserInputService", "VREnabled", function()
	return false
end)
getter("UserInputService", "AccelerometerEnabled", function()
	return Engine.options.touch
end)
getter("UserInputService", "GyroscopeEnabled", function()
	return Engine.options.touch
end)
method("UserInputService", "GetStringForKeyCode", function(_, keyCode)
	if typeof(keyCode) ~= "EnumItem" or keyCode.EnumType ~= Enum.KeyCode then
		error("GetStringForKeyCode expects a KeyCode", 2)
	end
	return keyCode.Name
end)
method("UserInputService", "GetMouseLocation", function()
	return Engine.options.viewport / 2
end)
method("UserInputService", "IsKeyDown", function()
	return false
end)
method("UserInputService", "IsMouseButtonPressed", function()
	return false
end)
method("UserInputService", "GetLastInputType", function()
	return if Engine.options.touch then Enum.UserInputType.Touch else Enum.UserInputType.Keyboard
end)
method("UserInputService", "GetConnectedGamepads", function()
	return {}
end)
method("UserInputService", "GetGamepadConnected", function()
	return false
end)
method("UserInputService", "GetFocusedTextBox", function()
	return nil
end)
method("UserInputService", "GetKeysPressed", function()
	return {}
end)

local function bindAction(actionName, fn, createTouchButton, priority, ...)
	if type(actionName) ~= "string" or type(fn) ~= "function" then
		error("BindAction: invalid arguments", 3)
	end
	local inputs = table.pack(...)
	for i = 1, inputs.n do
		local input = inputs[i]
		if
			typeof(input) ~= "EnumItem"
			or (input.EnumType ~= Enum.KeyCode and input.EnumType ~= Enum.UserInputType and input.EnumType ~= Enum.PlayerActions)
		then
			error("BindAction: input " .. i .. " must be a KeyCode or UserInputType", 3)
		end
	end
	Engine.boundActions[actionName] = { fn = fn, inputs = inputs, priority = priority }
end
method("ContextActionService", "BindAction", function(_, actionName, fn, createTouchButton, ...)
	bindAction(actionName, fn, createTouchButton, nil, ...)
end)
method("ContextActionService", "BindActionAtPriority", function(_, actionName, fn, createTouchButton, priority, ...)
	if type(priority) ~= "number" then
		error("BindActionAtPriority: priority must be a number", 2)
	end
	bindAction(actionName, fn, createTouchButton, priority, ...)
end)
method("ContextActionService", "UnbindAction", function(_, actionName)
	Engine.boundActions[actionName] = nil
end)
method("ContextActionService", "GetButton", function()
	return nil
end)
for _, n in { "SetTitle", "SetImage", "SetPosition", "SetDescription" } do
	method("ContextActionService", n, function() end)
end

method("StarterGui", "SetCoreGuiEnabled", function(_, coreType, enabled)
	if typeof(coreType) ~= "EnumItem" or coreType.EnumType ~= Enum.CoreGuiType then
		error("SetCoreGuiEnabled expects a CoreGuiType", 2)
	end
end)
method("StarterGui", "GetCoreGuiEnabled", function()
	return true
end)
method("StarterGui", "SetCore", function() end)
method("StarterGui", "GetCore", function()
	return nil
end)
method("GuiService", "GetGuiInset", function()
	return Vector2.new(0, 36), Vector2.zero
end)
method("GuiService", "IsTenFootInterface", function()
	return false
end)
method("SoundService", "PlayLocalSound", function() end)
method("SoundService", "SetListener", function() end)
method("ContentProvider", "PreloadAsync", function() end)
method("Debris", "AddItem", function(_, item, lifetime)
	lunetask.delay(lifetime or 10, function()
		pcall(function()
			item:Destroy()
		end)
	end)
end)
method("TextService", "GetTextSize", function(_, text, size, font, frameSize)
	checkType(text, "string", "GetTextSize", "text")
	checkType(size, "number", "GetTextSize", "size")
	return Vector2.new((utf8.len(text) or #text) * size * 0.55, size)
end)
getter("LocalizationService", "RobloxLocaleId", function()
	return Engine.options.locale
end)
getter("LocalizationService", "SystemLocaleId", function()
	return Engine.options.locale
end)

method("HttpService", "JSONEncode", function(_, value)
	local copy = wireCopy(value, "JSONEncode", "json")
	return serde.encode("json", copy)
end)
method("HttpService", "JSONDecode", function(_, text)
	checkType(text, "string", "JSONDecode", "text")
	return serde.decode("json", text)
end)
method("HttpService", "GenerateGUID", function(_, braces)
	local id = string.format(
		"%08x-%04x-%04x-%04x-%012x",
		math.random(0, 0x7fffffff),
		math.random(0, 0xffff),
		math.random(0, 0xffff),
		math.random(0, 0xffff),
		math.random(0, 0x7fffffff)
	)
	return if braces == false then id else "{" .. id .. "}"
end)

-- DataStores ------------------------------------------------------------------------------------

Engine.dataStores = {}
local function fakeStore(name: string)
	local store = Engine.dataStores[name]
	if store then
		return store
	end
	store = { name = name, data = {}, writes = 0, reads = 0 }
	local function maybeFail()
		if Engine.dataStoreFailures > 0 then
			Engine.dataStoreFailures -= 1
			error("502: API Services rejected request (simulated)", 3)
		end
	end
	local function checkKey(key)
		if type(key) ~= "string" or #key == 0 or #key > 50 then
			error("DataStore key must be a 1-50 character string", 3)
		end
	end
	local function commit(key, value)
		local copy = wireCopy(value, name .. "/" .. key, "datastore")
		local encoded = serde.encode("json", copy)
		if #encoded > 4 * 1024 * 1024 then
			report("datastore", "value too large for " .. key)
		end
		store.data[key] = serde.decode("json", encoded)
		store.writes += 1
	end
	function store:GetAsync(key)
		checkKey(key)
		maybeFail()
		lunetask.wait(0.01)
		store.reads += 1
		return deepCopy(store.data[key])
	end
	function store:SetAsync(key, value)
		checkKey(key)
		maybeFail()
		lunetask.wait(0.01)
		commit(key, value)
	end
	function store:UpdateAsync(key, transform)
		checkKey(key)
		if type(transform) ~= "function" then
			error("UpdateAsync expects a transform function", 2)
		end
		maybeFail()
		lunetask.wait(0.01)
		local current = deepCopy(store.data[key])
		local thread = coroutine.create(transform)
		local ok, result = coroutine.resume(thread, current, nil)
		if coroutine.status(thread) ~= "dead" then
			error("UpdateAsync transform function yielded (not allowed)", 2)
		end
		if not ok then
			error(result, 2)
		end
		if result ~= nil then
			commit(key, result)
		end
		return deepCopy(result)
	end
	function store:RemoveAsync(key)
		checkKey(key)
		maybeFail()
		local old = store.data[key]
		store.data[key] = nil
		return old
	end
	Engine.dataStores[name] = store
	return store
end

method("DataStoreService", "GetDataStore", function(_, name, scope)
	checkType(name, "string", "GetDataStore", "name")
	if Engine.options.studio then
		error("Studio access to API services is not enabled (simulated)", 2)
	end
	return fakeStore(name .. (if scope then "/" .. scope else ""))
end)
Engine.orderedStores = {}
method("DataStoreService", "GetOrderedDataStore", function(_, name)
	checkType(name, "string", "GetOrderedDataStore", "name")
	if Engine.options.studio then
		error("Studio access to API services is not enabled (simulated)", 2)
	end
	local store = Engine.orderedStores[name]
	if store then
		return store
	end
	store = { name = name, data = {} }
	function store:SetAsync(key, value)
		if type(key) ~= "string" or #key == 0 or #key > 50 then
			error("OrderedDataStore key must be a 1-50 character string", 2)
		end
		if type(value) ~= "number" or value ~= math.floor(value) then
			error("OrderedDataStore values must be integers (got " .. tostring(value) .. ")", 2)
		end
		lunetask.wait(0.01)
		store.data[key] = value
	end
	function store:GetSortedAsync(ascending, pageSize)
		if type(ascending) ~= "boolean" or type(pageSize) ~= "number" or pageSize < 1 or pageSize > 100 then
			error("GetSortedAsync(ascending: boolean, pageSize: 1-100)", 2)
		end
		lunetask.wait(0.01)
		local list = {}
		for key, value in store.data do
			table.insert(list, { key = key, value = value })
		end
		table.sort(list, function(a, b)
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
		local page = {}
		for i = 1, math.min(pageSize, #list) do
			page[i] = list[i]
		end
		return {
			IsFinished = #list <= pageSize,
			GetCurrentPage = function()
				return page
			end,
			AdvanceToNextPageAsync = function() end,
		}
	end
	Engine.orderedStores[name] = store
	return store
end)
method("Players", "GetNameFromUserIdAsync", function(_, userId)
	checkType(userId, "number", "GetNameFromUserIdAsync", "userId")
	return "User" .. tostring(userId)
end)

method("DataStoreService", "GetRequestBudgetForRequestType", function(_, requestType)
	if typeof(requestType) ~= "EnumItem" or requestType.EnumType ~= Enum.DataStoreRequestType then
		error("GetRequestBudgetForRequestType expects a DataStoreRequestType", 2)
	end
	return 60
end)

-- Marketplace -----------------------------------------------------------------------------------

method("MarketplaceService", "UserOwnsGamePassAsync", function(_, userId, passId)
	checkType(userId, "number", "UserOwnsGamePassAsync", "userId")
	checkType(passId, "number", "UserOwnsGamePassAsync", "passId")
	if passId <= 0 then
		error("UserOwnsGamePassAsync: invalid game pass id " .. passId, 2)
	end
	lunetask.wait(0.01)
	return Engine.ownedPasses[passId] == true
end)
method("MarketplaceService", "PromptGamePassPurchase", function(_, player, passId)
	checkType(passId, "number", "PromptGamePassPurchase", "passId")
	if passId <= 0 then
		report("purchase", "PromptGamePassPurchase with id " .. passId)
	end
	table.insert(Engine.purchasePrompts, { kind = "pass", id = passId, player = player })
end)
method("MarketplaceService", "PromptProductPurchase", function(_, player, productId)
	checkType(productId, "number", "PromptProductPurchase", "productId")
	if productId <= 0 then
		report("purchase", "PromptProductPurchase with id " .. productId)
	end
	table.insert(Engine.purchasePrompts, { kind = "product", id = productId, player = player })
end)
method("MarketplaceService", "GetProductInfo", function(_, id)
	return { Name = "Item " .. tostring(id), PriceInRobux = 99, IconImageAssetId = 0 }
end)

-- Tweens ----------------------------------------------------------------------------------------

method("TweenService", "Create", function(_, instance, info, goals)
	if not isProxy(instance) then
		error("TweenService:Create: instance must be an Instance", 2)
	end
	if typeofShim(info) ~= "TweenInfo" then
		error("TweenService:Create: second argument must be a TweenInfo", 2)
	end
	if type(goals) ~= "table" then
		error("TweenService:Create: goals must be a table", 2)
	end
	local raw = proxyToRaw[instance]
	for property, value in goals do
		local info2 = propInfo(raw.ClassName, property) or findCustom(setters, raw.ClassName, property)
		if not info2 then
			error(string.format("TweenService:Create no property named '%s' for object '%s'", tostring(property), raw.Name), 2)
		end
		local kind = typeofShim(value)
		if kind == "boolean" or kind == "string" or kind == "EnumItem" then
			error(string.format("TweenService:Create property named '%s' cannot be tweened due to type mismatch (%s)", property, kind), 2)
		end
	end
	local tween = {
		Instance = instance,
		TweenInfo = info,
		PlaybackState = Enum.PlaybackState.Begin,
		Completed = Signal.new("Tween.Completed"),
	}
	local token = 0
	function tween:Play()
		token += 1
		local mine = token
		self.PlaybackState = Enum.PlaybackState.Playing
		for property, value in goals do
			local ok, err = pcall(function()
				instance[property] = value
			end)
			if not ok then
				report("tween", tostring(err))
			end
		end
		lunetask.delay(info.Time + info.DelayTime, function()
			if mine == token and self.PlaybackState == Enum.PlaybackState.Playing then
				self.PlaybackState = Enum.PlaybackState.Completed
				self.Completed:Fire(Enum.PlaybackState.Completed)
			end
		end)
	end
	function tween:Cancel()
		if self.PlaybackState == Enum.PlaybackState.Playing then
			self.PlaybackState = Enum.PlaybackState.Cancelled
			self.Completed:Fire(Enum.PlaybackState.Cancelled)
		end
	end
	function tween:Pause()
		self.PlaybackState = Enum.PlaybackState.Paused
	end
	function tween:Destroy()
		token += 1
	end
	return tween
end)
method("TweenService", "GetValue", function(_, alpha)
	return alpha
end)

-- Proximity prompts -----------------------------------------------------------------------------

local function trigger(prompt)
	local service = Engine.service("ProximityPromptService")
	Engine.fire(service, "PromptTriggered", prompt, Engine.localPlayer)
	Engine.fire(prompt, "Triggered", Engine.localPlayer)
end
method("ProximityPrompt", "InputHoldBegin", function(self)
	table.insert(Engine.prompts, self)
	if proxyToRaw[self].HoldDuration <= 0 then
		trigger(self)
	end
end)
method("ProximityPrompt", "InputHoldEnd", function(self)
	if proxyToRaw[self].HoldDuration > 0 then
		trigger(self)
	end
end)

-- Collection service ----------------------------------------------------------------------------

method("CollectionService", "GetTagged", function(_, tag)
	local out = {}
	for _, d in Engine.rawGame:GetDescendants() do
		if d:HasTag(tag) then
			table.insert(out, wrap(d))
		end
	end
	return out
end)
method("CollectionService", "AddTag", function(_, instance, tag)
	unwrap(instance):AddTag(tag)
end)
method("CollectionService", "RemoveTag", function(_, instance, tag)
	unwrap(instance):RemoveTag(tag)
end)
method("CollectionService", "HasTag", function(_, instance, tag)
	return unwrap(instance):HasTag(tag)
end)
method("CollectionService", "GetInstanceAddedSignal", function(self, tag)
	return signalOf(self, "tagAdded:" .. tag)
end)
method("CollectionService", "GetInstanceRemovedSignal", function(self, tag)
	return signalOf(self, "tagRemoved:" .. tag)
end)
method("PhysicsService", "RegisterCollisionGroup", function() end)
method("PhysicsService", "CollisionGroupSetCollidable", function() end)
method("PhysicsService", "IsCollisionGroupRegistered", function()
	return true
end)
method("Lighting", "GetMinutesAfterMidnight", function()
	return 14 * 60
end)
method("Lighting", "SetMinutesAfterMidnight", function() end)

---------------------------------------------------------------------------------------------------
-- Analytic terrain

-- Stand-in for the voxel terrain the server builds: the terraced lagoon, beach ramp, island and
-- ocean floor, answering the downward raycasts the game makes.
function Engine.installAnalyticTerrain(Layout, Config)
	local function floorY(x: number, z: number): number
		local world = Layout.worldAt(Vector3.new(x, 0, z))
		if not world then
			return -Config.OceanDepth
		end
		local info = Layout.info(world)
		local dx, dz = x - info.origin.X, z - info.origin.Z
		local r = math.sqrt(dx * dx + dz * dz)
		if r <= info.deepRadius then
			return -info.depth
		elseif r <= info.midRadius then
			return -info.midDepth
		elseif r <= info.radius then
			return -info.shelfDepth
		elseif math.abs(dx) <= 21 and dz <= info.radius + 14 then
			local t = math.clamp((dz - info.radius) / 14, 0, 1)
			return -info.shelfDepth + (info.landY + info.shelfDepth) * t
		elseif r <= info.islandRadius then
			return info.landY
		end
		return -Config.OceanDepth
	end
	Engine.floorY = floorY
	local resultMeta = { __type = "RaycastResult" }
	Engine.raycastHook = function(origin, direction, params)
		if direction.Y > -0.01 or math.abs(direction.X) + math.abs(direction.Z) > 0.05 * math.abs(direction.Y) then
			return nil
		end
		if params and params.FilterType == Enum.RaycastFilterType.Include then
			local includesTerrain = false
			for _, instance in params.FilterDescendantsInstances do
				if instance == Engine.terrain then
					includesTerrain = true
				end
			end
			if not includesTerrain then
				return nil
			end
		end
		local y = floorY(origin.X, origin.Z)
		if origin.Y < y or origin.Y + direction.Y > y then
			return nil
		end
		return setmetatable({
			Position = Vector3.new(origin.X, y, origin.Z),
			Normal = Vector3.yAxis,
			Instance = Engine.terrain,
			Material = Enum.Material.Sand,
			Distance = origin.Y - y,
		}, resultMeta)
	end
end

---------------------------------------------------------------------------------------------------
-- Test helpers

function Engine.wait(seconds: number)
	lunetask.wait(seconds)
end

function Engine.waitFor(predicate: () -> any, timeout: number, label: string): boolean
	local started = os.clock()
	while os.clock() - started < timeout do
		local ok, value = pcall(predicate)
		if ok and value then
			return true
		end
		lunetask.wait(0.05)
	end
	report("timeout", "timed out waiting for " .. label)
	return false
end

-- Traffic entries after `since` that match a remote/kind.
function Engine.pushes(kind: string, since: number?)
	local out = {}
	for _, entry in Engine.traffic do
		if entry.dir == "s2c" and entry.args[1] == kind and (not since or entry.t >= since) then
			table.insert(out, entry.args[2])
		end
	end
	return out
end

function Engine.lastPush(kind: string, since: number?)
	local list = Engine.pushes(kind, since)
	return list[#list]
end

function Engine.gui()
	return unwrap(Engine.localPlayer):FindFirstChild("PlayerGui")
end

-- Visible = the object and every GuiObject ancestor are visible, and its ScreenGui is enabled.
function Engine.isVisible(raw): boolean
	local current = raw
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("LayerCollector") then
			return current.Enabled
		end
		current = current.Parent
	end
	return false
end

function Engine.click(buttonRaw)
	local proxy = wrap(buttonRaw)
	local enter = peekSignal(proxy, "MouseEnter")
	if enter then
		enter:Fire(0, 0)
	end
	Engine.fire(proxy, "MouseButton1Down", 0, 0)
	Engine.fire(proxy, "MouseButton1Up", 0, 0)
	Engine.fire(proxy, "Activated", nil, 1)
	Engine.fire(proxy, "MouseButton1Click")
	local leave = peekSignal(proxy, "MouseLeave")
	if leave then
		leave:Fire(0, 0)
	end
end

function Engine.pressAction(actionName: string, down: boolean)
	local action = Engine.boundActions[actionName]
	if not action then
		return false
	end
	local state = if down then Enum.UserInputState.Begin else Enum.UserInputState.End
	lunetask.spawn(protect, "action " .. actionName, action.fn, actionName, state, { KeyCode = action.inputs[1], UserInputState = state })
	return true
end

function Engine.shutdown()
	for _, fn in Engine.closeCallbacks do
		protect("BindToClose", fn)
	end
end

return Engine
