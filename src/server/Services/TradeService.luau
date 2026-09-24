--!strict
-- Pet trading between two players on the same server.
--   1. A sends a request; B accepts (or both request each other).
--   2. Each side picks up to Config.TradeMaxPets pets. Any change clears both "ready" flags.
--   3. When both are ready a short countdown runs; the swap happens only if nothing changed.
-- The swap re-validates ownership and inventory space, moves the pets (with their mutations)
-- under fresh ids, and saves both profiles immediately.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Profile = require(Shared.Profile)

local Net = require(script.Parent.Parent.Net)
local ProfileStore = require(script.Parent.Parent.ProfileStore)
local Sessions = require(script.Parent.Parent.Sessions)
local Sync = require(script.Parent.Parent.Sync)

local TradeService = {}

type Session = Sessions.Session
export type Trade = {
	a: Session,
	b: Session,
	offers: { [Player]: { string } },
	ready: { [Player]: boolean },
	token: number,
	countdownEnds: number?,
	closed: boolean,
}

-- requests[target][from] = expiry (os.clock)
local requests: { [Player]: { [Player]: number } } = {}
local lastRequest: { [Player]: number } = {}

local function partnerOf(trade: Trade, player: Player): Session
	return if trade.a.player == player then trade.b else trade.a
end

local function petList(profile: Profile.Data, ids: { string }): { any }
	local out = {}
	for _, id in ids do
		local pet = profile.pets[id]
		if pet then
			table.insert(out, { id = id, s = pet.s, m = pet.m })
		end
	end
	return out
end

local function view(trade: Trade, player: Player): any
	local me = if trade.a.player == player then trade.a else trade.b
	local other = partnerOf(trade, player)
	return {
		partner = { userId = other.player.UserId, name = other.player.DisplayName },
		mine = petList(me.profile, trade.offers[player]),
		theirs = petList(other.profile, trade.offers[other.player]),
		myReady = trade.ready[player] == true,
		theirReady = trade.ready[other.player] == true,
		countdown = if trade.countdownEnds then math.max(0, trade.countdownEnds - os.clock()) else nil,
	}
end

local function broadcast(trade: Trade)
	for _, session in { trade.a, trade.b } do
		Net.push(session.player, "trade", view(trade, session.player))
	end
end

local function close(trade: Trade, reason: string, extra: { [Player]: any }?)
	if trade.closed then
		return
	end
	trade.closed = true
	trade.token += 1
	for _, session in { trade.a, trade.b } do
		if session.trade == trade then
			session.trade = nil
		end
		local payload = { reason = reason, partner = partnerOf(trade, session.player).player.DisplayName }
		if extra and extra[session.player] then
			for key, value in extra[session.player] do
				(payload :: any)[key] = value
			end
		end
		Net.push(session.player, "tradeClosed", payload)
	end
end

local function changed(trade: Trade)
	trade.token += 1
	trade.ready = {}
	trade.countdownEnds = nil
end

-- Moves the listed pets from one profile to another under fresh ids.
local function move(from: Session, to: Session, ids: { string })
	for _, id in ids do
		local pet = from.profile.pets[id]
		from.profile.pets[id] = nil
		local index = table.find(from.profile.equipped, id)
		if index then
			table.remove(from.profile.equipped, index)
		end
		to.profile.petSeq += 1
		local newId = "P" .. tostring(to.profile.petSeq)
		to.profile.pets[newId] = { s = pet.s, l = false, m = if pet.m then table.clone(pet.m) else nil }
		to.profile.index[pet.s] = true
	end
end

local function valid(session: Session, ids: { string }): boolean
	for _, id in ids do
		local pet = session.profile.pets[id]
		if not pet or pet.l then
			return false
		end
	end
	return true
end

local function finalize(trade: Trade)
	local a, b = trade.a, trade.b
	local giveA, giveB = trade.offers[a.player], trade.offers[b.player]
	if not valid(a, giveA) or not valid(b, giveB) then
		changed(trade)
		broadcast(trade)
		return
	end
	if
		Profile.petCount(a.profile) - #giveA + #giveB > Config.PetInventoryCap
		or Profile.petCount(b.profile) - #giveB + #giveA > Config.PetInventoryCap
	then
		changed(trade)
		for _, session in { a, b } do
			Net.push(session.player, "toast", { key = "tradeFull", kind = "bad" })
		end
		broadcast(trade)
		return
	end
	if #giveA == 0 and #giveB == 0 then
		close(trade, "cancelled")
		return
	end
	move(a, b, giveA)
	move(b, a, giveB)
	close(trade, "done", { [a.player] = { got = #giveB, gave = #giveA }, [b.player] = { got = #giveA, gave = #giveB } })
	for _, session in { a, b } do
		Sessions.publishPets(session)
		Sync.profile(session)
		task.spawn(ProfileStore.save, session.player, false)
	end
end

local function start(a: Session, b: Session)
	local trade: Trade = {
		a = a,
		b = b,
		offers = { [a.player] = {}, [b.player] = {} },
		ready = {},
		token = 0,
		countdownEnds = nil,
		closed = false,
	}
	a.trade = trade
	b.trade = trade
	broadcast(trade)
end

local function sessionOf(player: Player): Session?
	local session = Sessions.get(player)
	if session and session.ready then
		return session
	end
	return nil
end

local function targetFrom(payload: any): Player?
	local userId = if type(payload) == "table" then tonumber(payload.userId) else nil
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

local function request(player: Player, payload: any): (boolean, string?, any)
	local session = sessionOf(player)
	local target = targetFrom(payload)
	local other = target and sessionOf(target)
	if not session or not target or not other or target == player then
		return false, "err.generic"
	end
	if session.trade or other.trade then
		return false, "tradeBusy"
	end
	-- They already asked us: accepting by asking back.
	local incoming = requests[player]
	if incoming and incoming[target] and incoming[target] > os.clock() then
		incoming[target] = nil
		start(session, other)
		return true, nil, { started = true }
	end
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < 3 then
		return false, "err.busy"
	end
	lastRequest[player] = now
	local pending = requests[target] or {}
	requests[target] = pending
	pending[player] = now + Config.TradeRequestSeconds
	Net.push(target, "tradeRequest", { userId = player.UserId, name = player.DisplayName, seconds = Config.TradeRequestSeconds })
	return true, nil, { started = false }
end

local function respond(player: Player, payload: any): (boolean, string?, any)
	local session = sessionOf(player)
	local from = targetFrom(payload)
	local pending = requests[player]
	if not session or not from or not pending or not pending[from] then
		return false, "tradeExpired"
	end
	local expired = pending[from] < os.clock()
	pending[from] = nil
	if expired then
		return false, "tradeExpired"
	end
	if payload.accept ~= true then
		Net.push(from, "toast", { key = "tradeDeclined", kind = "bad" })
		return true
	end
	local other = sessionOf(from)
	if not other then
		return false, "tradeExpired"
	end
	if session.trade or other.trade then
		return false, "tradeBusy"
	end
	start(other, session)
	return true
end

local function offer(player: Player, payload: any): (boolean, string?, any)
	local session = sessionOf(player)
	local trade: Trade? = session and session.trade
	if not session or not trade or type(payload) ~= "table" or type(payload.ids) ~= "table" then
		return false, "err.generic"
	end
	local ids: { string } = {}
	for _, id in payload.ids do
		if type(id) ~= "string" or table.find(ids, id) then
			return false, "err.generic"
		end
		local pet = session.profile.pets[id]
		if not pet then
			return false, "err.generic"
		end
		if pet.l then
			return false, "tradeLocked"
		end
		table.insert(ids, id)
	end
	if #ids > Config.TradeMaxPets then
		return false, "tradeMax"
	end
	trade.offers[player] = ids
	changed(trade)
	broadcast(trade)
	return true
end

local function ready(player: Player, payload: any): (boolean, string?, any)
	local session = sessionOf(player)
	local trade: Trade? = session and session.trade
	if not session or not trade or type(payload) ~= "table" or type(payload.ready) ~= "boolean" then
		return false, "err.generic"
	end
	trade.ready[player] = payload.ready
	trade.token += 1
	trade.countdownEnds = nil
	local other = partnerOf(trade, player)
	if trade.ready[player] and trade.ready[other.player] then
		local token = trade.token
		trade.countdownEnds = os.clock() + Config.TradeCountdown
		task.delay(Config.TradeCountdown, function()
			if not trade.closed and trade.token == token then
				finalize(trade)
			end
		end)
	end
	broadcast(trade)
	return true
end

local function cancel(player: Player): (boolean, string?, any)
	local session = sessionOf(player)
	local trade: Trade? = session and session.trade
	if trade then
		close(trade, "cancelled")
	end
	return true
end

function TradeService.onLeave(session: Session)
	local trade: Trade? = session.trade
	if trade then
		close(trade, "left")
	end
	requests[session.player] = nil
	lastRequest[session.player] = nil
	for _, pending in requests do
		pending[session.player] = nil
	end
end

function TradeService.init()
	Net.on("TradeRequest", request)
	Net.on("TradeRespond", respond)
	Net.on("TradeOffer", offer)
	Net.on("TradeReady", ready)
	Net.on("TradeCancel", cancel)
end

return TradeService
