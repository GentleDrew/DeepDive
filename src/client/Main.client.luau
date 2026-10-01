--!strict
-- Client entry point: loading screen, server handshake, then HUD, panels and controllers.

local LocalizationService = game:GetService("LocalizationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Strings = require(Shared.Strings)

local UI = script.Parent:WaitForChild("UI")
local Controllers = script.Parent:WaitForChild("Controllers")

local Gui = require(UI.Gui)
local Screens = require(UI.Screens)
Screens.showLoading()

local Anim = require(UI.Anim)
local Clear = require(UI.Clear)
local Effects = require(UI.Effects)
local Hatch = require(UI.Hatch)
local Hud = require(UI.Hud)
local Kit = require(UI.Kit)
local Panel = require(UI.Panel)
local Theme = require(UI.Theme)
local Toasts = require(UI.Toasts)
local Tutorial = require(UI.Tutorial)
local EggPanel = require(UI.Panels.Egg)
local ProfilePanel = require(UI.Panels.Profile)
local PlayerList = require(UI.PlayerList)
local Trade = require(UI.Trade)
local PetsPanel = require(UI.Panels.Pets)
local RewardsPanel = require(UI.Panels.Rewards)
local Offers = require(UI.Offers)
local RightRail = require(UI.RightRail)
local SettingsPanel = require(UI.Panels.Settings)
local ShopPanel = require(UI.Panels.Shop)
local GearPanel = require(UI.Panels.Gear)
local WorldsPanel = require(UI.Panels.Worlds)

local ClientNet = require(script.Parent.ClientNet)
local Music = require(script.Parent.Music)
local Sfx = require(script.Parent.Sfx)
local State = require(script.Parent.State)
local WorldFx = require(script.Parent.WorldFx)

local Ambience = require(Controllers.Ambience)
local Board = require(Controllers.Board)
local Dive = require(Controllers.Dive)
local Fish = require(Controllers.Fish)
local Hazards = require(Controllers.Hazards)
local Nameplates = require(Controllers.Nameplates)
local Pets = require(Controllers.Pets)
local Prompts = require(Controllers.Prompts)
local Relics = require(Controllers.Relics)
local Swim = require(Controllers.Swim)
local Trails = require(Controllers.Trails)
local WorldProps = require(Controllers.WorldProps)

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- Language and sound follow the saved settings; these run before any UI refresh.
-- "auto" picks Korean for Korean Roblox clients and English for everyone else.
local function resolveLanguage(lang: string): string
	if lang ~= "auto" then
		return lang
	end
	local ok, locale = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	return if ok and type(locale) == "string" and string.sub(string.lower(locale), 1, 2) == "ko" then "ko" else "en"
end
Strings.setLanguage(resolveLanguage(Config.DefaultLanguage))
State.languageChanged:Connect(function(lang)
	Strings.setLanguage(resolveLanguage(lang))
end)
State.settingsChanged:Connect(function(settings)
	Sfx.setEnabled(settings.sfx)
	Music.setEnabled(settings.music)
end)
Music.follow(function()
	return State.dive.inWater
end)

Kit.clickSound = function()
	Sfx.play("Click")
end
Kit.hoverSound = function()
	Sfx.play("Hover")
end
Hatch.sfx = Sfx.play

local app: any = {
	Gui = Gui,
	Kit = Kit,
	Theme = Theme,
	Anim = Anim,
	State = State,
	Net = ClientNet,
	Sfx = Sfx,
	Toasts = Toasts,
	Effects = Effects,
	Screens = Screens,
	Hud = Hud,
	Clear = Clear,
	Hatch = Hatch,
	Relics = Relics,
	WorldFx = WorldFx,
}

local panels: { [string]: any } = {}

function app.isUiBlocking(): boolean
	return Panel.current() ~= nil or Hatch.playing
end

function app.closePanels()
	Panel.closeAll()
end

function app.travel(world: number)
	if State.traveling then
		return
	end
	if State.dive.active then
		Toasts.show(Strings.get("err.diving"), "bad")
		Sfx.play("Error")
		return
	end
	local result = ClientNet.invoke("Teleport", { world = world })
	if not result.ok then
		State.traveling = false
		Screens.travelEnd()
		Sfx.play("Error")
		Toasts.show(Strings.get(result.err or "err.generic"), "bad")
	end
end

function app.setSetting(key: string, value: any)
	local profile = State.profile
	if profile then
		(profile.settings :: any)[key] = value
		if key == "lang" then
			State.languageChanged:Fire(value)
		elseif key == "sfx" then
			Sfx.setEnabled(value)
		elseif key == "music" then
			Music.setEnabled(value)
		end
	end
	ClientNet.invoke("Setting", { key = key, value = value })
end

function app.openWorlds()
	panels.worlds.open()
end
function app.openUpgrades()
	panels.upgrades.open()
end
function app.openPets()
	panels.pets.open()
end
function app.openShop()
	panels.shop.open()
end
function app.openSettings()
	panels.settings.open()
end
function app.openProfile()
	panels.profile.open()
end
function app.openRewards()
	panels.rewards.open()
end
function app.sell()
	local result = ClientNet.invoke("Sell")
	if not result.ok and result.err and result.err ~= "err.busy" then
		Sfx.play("Error")
		Toasts.show(Strings.get(result.err), "bad", utf8.char(0x1F392))
	end
end
-- Pays the unlock fee for a world; travels there on success when `go` is set.
function app.unlockWorld(world: number, go: boolean?): boolean
	local result = ClientNet.invoke("UnlockWorld", { world = world })
	if not result.ok then
		Sfx.play("Error")
		if result.err then
			Toasts.show(Strings.get(result.err), "bad", utf8.char(0x1F512))
		end
		if result.err == "notEnough" then
			Offers.trigger("unlock")
		end
		return false
	end
	Sfx.play("Unlock")
	Effects.confetti(60)
	Toasts.show(Strings.get("unlockedNext", { n = world }), "gold", utf8.char(0x1F513))
	if go then
		app.travel(world)
	end
	return true
end
function app.openEgg(world: number)
	if world ~= State.world then
		return
	end
	panels.egg.openWorld(world)
end

Hud.init({
	openWorlds = app.openWorlds,
	openUpgrades = app.openUpgrades,
	openPets = app.openPets,
	openShop = app.openShop,
	openSettings = app.openSettings,
	openProfile = app.openProfile,
	swimInput = Swim.setInput,
})

panels.worlds = WorldsPanel.new(app)
panels.upgrades = GearPanel.new(app)
panels.pets = PetsPanel.new(app)
panels.shop = ShopPanel.new(app)
panels.settings = SettingsPanel.new(app)
panels.egg = EggPanel.new(app)
panels.profile = ProfilePanel.new(app)
panels.rewards = RewardsPanel.new(app)
RewardsPanel.track(app)
for _, panel in panels do
	local previous = panel.onClose
	panel.onClose = function()
		Sfx.play("Close")
		if previous then
			previous()
		end
	end
end

app.Offers = Offers
Offers.init(app, function()
	return RightRail.starterLeft(app)
end)
RightRail.init(app, app.openRewards)
Dive.init(app)
Ambience.init(app)
Swim.init(app)
Relics.init(app)
Hazards.init(app)
Fish.init(app)
Pets.init(app)
WorldProps.init(app)
Prompts.init(app)
Tutorial.init(app)
Nameplates.init(app)
Trails.init()
Board.init(app)
app.Trade = Trade.init(app)
app.PlayerList = PlayerList.init(function(player)
	app.requestTrade(player.UserId)
end)
State.languageChanged:Connect(function()
	task.defer(app.PlayerList.refresh)
end)

-- Handshake: wait until the server has loaded our profile and world.
local view = nil
local started = os.clock()
while not view do
	local result = ClientNet.invoke("Ready")
	if result.ok then
		view = result.data
	else
		if os.clock() - started > 12 then
			Screens.setLoadingStatus(Strings.get("err.notReady"))
		end
		task.wait(0.5)
	end
end
State.applyView(view)
Hud.refresh()
task.wait(0.4)
Screens.hideLoading()

local profile = State.profile
if profile then
	Music.setEnabled(profile.settings.music)
end
if profile and profile.stats.dives > 0 then
	task.delay(1.2, function()
		Toasts.show(Strings.get("welcomeBack"), "blue", utf8.char(0x1F30A))
	end)
end
-- Returning divers (past the tutorial) see today's login reward straight away.
if profile and profile.tutorial >= 7 and RewardsPanel.anyReady(app) then
	task.delay(2.5, function()
		if not app.isUiBlocking() then
			app.openRewards()
		end
	end)
end

-- Menu badges: something affordable in upgrades, or an egg you can hatch.
task.spawn(function()
	while true do
		local p = State.profile
		if p then
			Hud.setBadge("upgrades", GearPanel.anyAffordable(p))
			local nextWorld = p.unlocked + 1
			local previous = p.worlds[tostring(p.unlocked)]
			Hud.setBadge(
				"worlds",
				nextWorld <= Config.WorldCount and previous ~= nil and previous.cleared and p.coins >= Economy.unlockCost(nextWorld)
			)
			Hud.setBadge("pets", p.coins >= Economy.eggCost(State.world) and next(p.pets) == nil)
		end
		task.wait(0.5)
	end
end)
