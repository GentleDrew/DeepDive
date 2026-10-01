--!strict
-- Client side of the dive loop: reacts to server pushes (dive start, oxygen, pickups, sales,
-- blackouts, clears, travel) with feedback, and predicts oxygen smoothly between syncs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Layout = require(Shared.Layout)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)

local Dive = {}

function Dive.init(app: any)
	local State = app.State
	local Net = app.Net
	local dive = State.dive

	Net.on("profile", function(view: any)
		State.applyView(view)
	end)

	Net.on("layout", function(layout: any)
		if type(layout) ~= "table" then
			return
		end
		local relics = {}
		for _, pair in layout.relics or {} do
			relics[pair[1]] = pair[2]
		end
		State.layout = { id = layout.id, world = layout.world, relics = relics, chest = layout.chest == true }
		State.layoutChanged:Fire(State.layout)
	end)

	Net.on("dive", function(payload: any)
		if payload.state == "start" then
			dive.active = true
			dive.blackout = false
			dive.oxygen = payload.oxygen
			dive.max = payload.max
			dive.chestCarried = false
			State.diveChanged:Fire()
		elseif payload.state == "blackout" then
			dive.blackout = true
			app.Sfx.play("Blackout")
			app.Screens.blackout()
			State.diveChanged:Fire()
			task.delay(4, function()
				app.Offers.trigger("blackout")
			end)
		end
	end)

	Net.on("oxygen", function(payload: any)
		if not dive.active then
			return
		end
		dive.max = payload.max
		if payload.hit then
			dive.oxygen = payload.value
			app.Sfx.play("Hurt")
			app.Effects.flash(Color3.fromRGB(255, 60, 80), 0.45, 0.5)
			app.Toasts.show(Strings.get("hazardHit", { n = math.floor(Config.Dive.HazardPenalty * 100 + 0.5) }), "bad", utf8.char(0x1F4A5))
		elseif math.abs(payload.value - dive.oxygen) > 1.5 then
			dive.oxygen = payload.value
		else
			dive.oxygen += (payload.value - dive.oxygen) * 0.5
		end
	end)

	Net.on("collected", function(payload: any)
		if payload.chest then
			dive.chestCarried = true
			app.Sfx.play("Chest")
			app.Effects.flash(Color3.fromRGB(255, 220, 120), 0.5, 0.6)
			app.Toasts.show(Strings.get("chestGot"), "gold", utf8.char(0x1F451))
			return
		end
		dive.cargo = payload.cargo
		app.Relics.confirm(payload.point)
		app.Hud.bumpCargo()
		local relic = Worlds.relics[payload.key]
		if payload.discovered and relic then
			app.Sfx.play("Discover")
			app.Toasts.show(Strings.get("newRelic") .. "  " .. Strings.name(relic.name), "rare", utf8.char(0x2728))
		end
		if payload.capacity and payload.cargo >= payload.capacity then
			app.Toasts.show(Strings.get("backpackFull"), "blue", utf8.char(0x1F392))
			app.Offers.trigger("full")
		end
	end)

	-- A point you emptied earlier in this dive just refilled with a new relic.
	Net.on("relicSpawn", function(payload: any)
		app.Relics.spawn(payload.point, payload.key)
	end)

	Net.on("reject", function(payload: any)
		app.Relics.restore(payload.point)
		if payload.reason == "full" then
			app.Hud.flashFull()
		end
	end)

	-- Dive over: treasure stays in the backpack until it is sold at the sell stand.
	Net.on("surfaced", function(payload: any)
		dive.active = false
		dive.chestCarried = false
		dive.cargo = payload.cargo or dive.cargo
		dive.blackout = false
		State.diveChanged:Fire()
		if payload.rescued then
			local text = Strings.get("rescued")
			if (payload.lost or 0) > 0 then
				text ..= "  (" .. Strings.get("lostTreasure", { n = payload.lost }) .. ")"
			end
			app.Screens.rescued(text)
		elseif (payload.cargo or 0) > 0 and not payload.chest then
			app.Toasts.show(Strings.get("carrying", { n = payload.cargo }), "gold", utf8.char(0x1F392))
		end
		if payload.record then
			app.Toasts.show(Strings.get("depthRecord", { n = payload.record }), "blue", utf8.char(0x1F3C6))
		end
		if payload.chestLost then
			app.Toasts.show(Strings.get("chestLost"), "bad")
		end
	end)

	Net.on("sold", function(payload: any)
		dive.cargo = 0
		app.Hud.bumpCargo()
		local world = State.world
		local spot = Layout.origin(world) + Layout.dock(world).sell
		app.WorldFx.coinFountain(spot + Vector3.new(0, 0.5, 0), math.clamp(payload.count + 6, 8, 22))
		app.Sfx.play(if payload.count >= 10 then "SellBig" else "Sell")
		app.Effects.flash(Color3.fromRGB(255, 226, 120), 0.35, 0.35)
		app.Effects.floatText("+" .. Format.commas(payload.payout), Color3.fromRGB(255, 226, 90), UDim2.fromScale(0.5, 0.58), 48)
		local coins = math.clamp(math.floor(payload.count * 1.5) + 6, 8, 26)
		app.Effects.coinBurst(coins, Vector2.new(0.5, 0.62), app.Hud.coinTarget, function()
			app.Sfx.play("Coin", 0.9 + math.random() * 0.3)
		end)
		app.Toasts.show(Strings.get("sold", { n = payload.count }), "gold", utf8.char(0x1F4B0))
		if payload.chestReady then
			task.delay(1.2, function()
				app.Sfx.play("Unlock")
				app.Toasts.show(Strings.get("chestReady"), "gold", utf8.char(0x1F451))
			end)
		end
	end)

	Net.on("cleared", function(payload: any)
		task.delay(0.8, function()
			app.Clear.show(payload, app.unlockWorld, app.Sfx.play)
		end)
	end)

	Net.on("travel", function(payload: any)
		if payload.state == "start" then
			State.traveling = true
			app.closePanels()
			app.Sfx.play("Travel")
			app.Screens.travelStart(payload.world)
		else
			State.traveling = false
			app.Screens.travelEnd()
		end
	end)

	Net.on("toast", function(payload: any)
		local args = payload.args
		if payload.key == "grantedReroll" and args and args.key then
			local pet = Worlds.pets[args.key]
			args = { name = if pet then Strings.name(pet.name) else args.key }
		end
		app.Toasts.show(Strings.get(payload.key, args), payload.kind or "info")
	end)

	Net.on("saved", function()
		app.Hud.showSaved()
	end)

	Net.on("purchase", function(payload: any)
		if (payload.coins or 0) <= 0 then
			app.Sfx.play("Legendary")
			app.Toasts.show(Strings.get("luckyGot", { n = payload.enchants or 0 }), "gold", utf8.char(0x2728))
			return
		end
		app.Effects.coinBurst(24, Vector2.new(0.5, 0.5), app.Hud.coinTarget, function()
			app.Sfx.play("Coin", 1.1)
		end)
		app.Effects.floatText("+" .. Format.commas(payload.coins), Color3.fromRGB(255, 226, 90), UDim2.fromScale(0.5, 0.5), 50)
	end)

	-- Oxygen prediction and warnings.
	local warned = false
	local lastBeat = 0
	RunService.RenderStepped:Connect(function(dt: number)
		if dive.active and not dive.blackout then
			dive.oxygen = math.max(0, dive.oxygen - Economy.oxygenDrain(State.world, math.max(0, dive.depth)) * dt)
		elseif not dive.active then
			dive.max = State.upgrade("tank")
			dive.oxygen = dive.max
		end
		local ratio = if dive.max > 0 then dive.oxygen / dive.max else 1
		local now = os.clock()
		if dive.active and not dive.blackout then
			if ratio <= Config.Dive.OxygenWarn and not warned then
				warned = true
				app.Sfx.play("Warning")
			end
			if ratio <= Config.Dive.OxygenDanger and now - lastBeat > 1.1 then
				lastBeat = now
				app.Sfx.play("Warning", 1.2)
			end
			local strength = 0
			if ratio <= Config.Dive.OxygenDanger then
				strength = 0.45 + math.sin(now * 7) * 0.2
			elseif ratio <= Config.Dive.OxygenWarn then
				strength = 0.18
			end
			app.Effects.setVignette(strength)
		else
			warned = false
			app.Effects.setVignette(0)
		end
	end)
end

return Dive
