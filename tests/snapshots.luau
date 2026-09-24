--!nocheck
-- Renders key UI states to HTML (tests/harness/html.luau) for visual review in a browser.
--   lune run tests/snapshots.luau <outDir> [--mobile] [--ko]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Engine = require("./harness/engine")
local Html = require("./harness/html")

local Vector3, Vector2, CFrame = roblox.Vector3, roblox.Vector2, roblox.CFrame

local outDir = process.args[1] or "snapshots"
local mobile = table.find(process.args, "--mobile") ~= nil
local korean = table.find(process.args, "--ko") ~= nil
local prefix = (if mobile then "mobile" else "desktop") .. (if korean then "_ko" else "")
fs.writeDir(outDir)

Engine.options.touch = mobile
Engine.options.viewport = if mobile then Vector2.new(844, 390) else Vector2.new(1280, 720)
Engine.allowWarning(".")
Engine.load("DeepDive.rbxlx")
Engine.startFrames()

local Shared = "ReplicatedStorage.Shared."
local Config = Engine.server.module(Shared .. "Config")
local Layout = Engine.server.module(Shared .. "Layout")
for _, realm in { Engine.server, Engine.client } do
	local c = realm.module(Shared .. "Config")
	c.Products[1].id = 111
	c.Passes[1].id = 222
	if korean then
		c.DefaultLanguage = "ko"
	end
end
Engine.installAnalyticTerrain(Layout, Config)

local function snap(name: string)
	Engine.wait(0.05)
	local html = Html.page(Engine.gui(), Engine.options.viewport, { wrap = Engine.wrap })
	fs.writeFile(outDir .. "/" .. prefix .. "_" .. name .. ".html", html)
	print("snap " .. prefix .. "_" .. name)
end

local rawGame = Engine.rawGame
local function worldFolder(world: number)
	return rawGame:GetService("Workspace").Worlds:FindFirstChild("World" .. world)
end

Engine.runServerScripts()
Engine.waitFor(function()
	local wf = worldFolder(1)
	return wf and wf:GetAttribute("Ready")
end, 60, "world 1")
Engine.wait(0.3)
local player = Engine.addPlayer("Diver", 1001)
local Sessions = Engine.server.module("ServerScriptService.Server.Sessions")
local Sync = Engine.server.module("ServerScriptService.Server.Sync")
Engine.waitFor(function()
	return Sessions.get(player) and Sessions.get(player).ready
end, 20, "session")
Engine.runClientScripts(player)
Engine.wait(0.25)
snap("01_loading")

local State = Engine.client.module("Players.Diver.PlayerScripts.Client.State")
local ClientNet = Engine.client.module("Players.Diver.PlayerScripts.Client.ClientNet")
Engine.waitFor(function()
	return State.profile ~= nil
end, 20, "profile")
Engine.wait(2.5)

local session = Sessions.get(player)
local function root()
	return Engine.rootOf(player)
end
local function moveTo(p: Vector3)
	root().CFrame = CFrame.new(p)
end

-- Some progress so the HUD and panels have content.
session.profile.coins = 48250
for _, key in { "tank1a", "tank1b", "tank2a", "pack1a", "pack1b", "fins1a", "magnet1a" } do
	session.profile.gear.owned[key] = true
end
session.profile.gear.equip = { tank = "tank2a", pack = "pack1b", fins = "fins1a", magnet = "magnet1a" }
session.profile.unlocked = 3
session.profile.worlds["3"] = { sold = 20, cleared = true, best = 0 }
session.profile.worlds["1"].sold = 9
session.profile.tutorial = 7
Sync.profile(session)
Engine.wait(0.6)
snap("02_hud_dock")

-- Diving with cargo.
moveTo(Layout.origin(1) + Vector3.new(0, -8, 0))
Engine.wait(0.6)
local http = Engine.service("HttpService")
local decoded = http:JSONDecode(worldFolder(1):GetAttribute("Points"))
local n = 0
for point in State.layout.relics do
	local p = decoded[point]
	moveTo(Vector3.new(p[1], p[2], p[3]))
	Engine.wait(0.12)
	n += 1
	if n >= 4 then
		break
	end
end
moveTo(Layout.origin(1) + Vector3.new(6, -24, 4))
Engine.wait(1.2)
snap("03_hud_diving")

-- Surface to sell (coin burst mid-flight).
moveTo(Layout.origin(1) + Vector3.new(6, -1.6, 4))
Engine.wait(0.9)
snap("04_sold")
Engine.wait(2.5)

-- Panels via the HUD menu.
local gui = Engine.gui()
local menu = gui:FindFirstChild("Menu", true)
local function openMenu(name: string)
	local button = menu:FindFirstChild(name)
	Engine.click(button)
	Engine.wait(0.8)
end
local function closePanels()
	local panels = gui:FindFirstChild("DeepDivePanels")
	for _, d in panels:GetDescendants() do
		if d:IsA("GuiButton") and d.Name == "Close" and Engine.isVisible(d) then
			Engine.click(d)
		end
	end
	Engine.wait(0.6)
end

-- A few pets for the pets panel.
session.profile.coins = 5e6
Sync.profile(session)
Engine.wait(0.2)
local dock = Layout.dock(1)
moveTo(Layout.origin(1) + dock.egg + Vector3.new(0, 3, 5))
Engine.wait(0.4)
for _ = 1, 3 do
	ClientNet.invoke("Hatch", { world = 1, count = 3 })
	Engine.wait(3.4)
end
session.profile.coins = 48250
-- Mutations on a few pets and some Lucky Enchants.
local mutated = 0
for _, pet in session.profile.pets do
	mutated += 1
	if mutated == 1 then
		pet.m = { "Gold", "Lava" }
	elseif mutated == 2 then
		pet.m = { "Galaxy" }
	elseif mutated == 3 then
		pet.m = { "GOAT", "Diamond", "Gold" }
	end
end
session.profile.enchants = 2
Sync.profile(session)
Engine.wait(0.5)

for index, name in { "worlds", "upgrades", "pets", "shop", "settings", "profile" } do
	openMenu(name)
	snap(string.format("%02d_panel_%s", 4 + index, name))
	closePanels()
end

-- Egg panel via its proximity prompt.
local eggPrompt
for _, d in worldFolder(1):GetDescendants() do
	if d.ClassName == "ProximityPrompt" and d:GetAttribute("Kind") == "Egg" then
		eggPrompt = d
	end
end
Engine.wait(0.4)
snap("10_prompt")
if eggPrompt then
	Engine.fire(Engine.service("ProximityPromptService"), "PromptTriggered", Engine.wrap(eggPrompt), player)
	Engine.wait(0.8)
	snap("11_panel_egg")
	closePanels()
end

-- Hatch sequence, started from the egg panel's own "Hatch x3" button.
session.profile.coins = 5e6
Sync.profile(session)
Engine.wait(0.3)
if eggPrompt then
	Engine.fire(Engine.service("ProximityPromptService"), "PromptTriggered", Engine.wrap(eggPrompt), player)
	Engine.wait(0.8)
	local panels = gui:FindFirstChild("DeepDivePanels")
	for _, d in panels:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "x3") and Engine.isVisible(d) then
			Engine.click(d:FindFirstAncestorWhichIsA("GuiButton"))
			break
		end
	end
	Engine.wait(1.3)
	snap("12_hatch")
	Engine.wait(2.2)
	snap("12b_hatch_reveal")
	Engine.wait(3)
	closePanels()
end

-- World clear popup.
local DiveService = Engine.server.module("ServerScriptService.Server.Services.DiveService")
session.profile.worlds["1"].sold = 12
DiveService.rollLayout(session)
Engine.wait(0.3)
moveTo(Layout.origin(1) + Vector3.new(0, -8, 0))
Engine.wait(0.5)
local chest = http:JSONDecode(worldFolder(1):GetAttribute("Chest"))
moveTo(Vector3.new(chest[1], chest[2], chest[3]))
Engine.wait(0.5)
moveTo(Layout.origin(1) + Vector3.new(0, -1.6, 0))
Engine.wait(2.2)
snap("13_clear")
do
	local overlayNow = gui:FindFirstChild("DeepDiveOverlay")
	local shown = overlayNow and overlayNow:FindFirstChild("Clear", true)
	if shown then
		Engine.destroyRaw(shown)
	end
	local Clear = Engine.client.module("Players.Diver.PlayerScripts.Client.UI.Clear")
	local Economy = Engine.client.module("ReplicatedStorage.Shared.Economy")
	Clear.show({ world = 3, reward = 5200, nextWorld = 4, unlockCost = Economy.unlockCost(4) }, function()
		return false
	end, function() end)
	Engine.wait(1.6)
	snap("13b_clear_unlock")
end

-- Blackout.
local overlay = gui:FindFirstChild("DeepDiveOverlay")
local popup = overlay and overlay:FindFirstChild("Clear", true)
if popup then
	Engine.destroyRaw(popup)
end
Engine.wait(0.5)
moveTo(Layout.origin(1) + Vector3.new(0, -14, 0))
Engine.wait(0.6)
session.oxygen = 0.05
Engine.wait(0.9)
snap("14_blackout")
Engine.wait(3)

-- Trading: an incoming request, then the trade window with offers on both sides.
local friend = Engine.addPlayer("Buddy", 1002)
local friendSession
for _ = 1, 100 do
	friendSession = Sessions.get(friend)
	if friendSession and friendSession.ready then
		break
	end
	Engine.wait(0.2)
end
friendSession.profile.pets = { P1 = { s = "p2.4", l = false, m = { "Diamond" } }, P2 = { s = "p1.5", l = false } }
Engine.invokeAs(friend, "TradeRequest", { userId = player.UserId })
Engine.wait(0.8)
snap("15_trade_request")
ClientNet.invoke("TradeRespond", { userId = 1002, accept = true })
Engine.wait(0.6)
local offer = {}
for id in session.profile.pets do
	if #offer < 2 then
		table.insert(offer, id)
	end
end
ClientNet.invoke("TradeOffer", { ids = offer })
Engine.invokeAs(friend, "TradeOffer", { ids = { "P1", "P2" } })
Engine.invokeAs(friend, "TradeReady", { ready = true })
Engine.wait(0.9)
snap("16_trade")

Engine.running = false
process.exit(0)
