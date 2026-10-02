--!nocheck
-- Runtime smoke test. Boots the built place inside the Lune engine emulator (tests/harness) and
-- plays the whole game loop while collecting every runtime error, invalid property write, bad
-- remote payload and failed assertion.
--
--   rojo build default.project.json -o DeepDive.rbxlx
--   lune run tests/smoke.luau            (desktop, full scenario)
--   lune run tests/smoke.luau --mobile   (touch device, small screen)

local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Engine = require("./harness/engine")

local Vector3, Vector2, CFrame = roblox.Vector3, roblox.Vector2, roblox.CFrame
local Enum = roblox.Enum

local mobile = table.find(process.args, "--mobile") ~= nil
local quick = table.find(process.args, "--quick") ~= nil
local placePath = "DeepDive.rbxlx"
for _, arg in process.args do
	if string.find(arg, "%.rbxlx$") then
		placePath = arg
	end
end

Engine.options.touch = mobile
Engine.options.viewport = if mobile then Vector2.new(844, 390) else Vector2.new(1280, 760)
-- Expected, informational warnings.
Engine.allowWarning("^%[DeepDive%] World %d+ built")

local failures = 0
local function check(condition: any, message: string)
	if not condition then
		failures += 1
		Engine.report("assert", message)
	end
end

local stepStarted = os.clock()
local function step(name: string, fn: () -> ())
	print(string.format("\27[36m== %s\27[0m", name))
	stepStarted = os.clock()
	local ok, err = xpcall(fn, function(e)
		return debug.traceback(tostring(e), 2)
	end)
	if not ok then
		Engine.report("step", name .. ": " .. tostring(err))
	end
	print(string.format("   (%.1fs)", os.clock() - stepStarted))
end

local game = Engine.load(placePath)
local rawGame = Engine.rawGame
Engine.startFrames()

local Shared = "ReplicatedStorage.Shared."
local Config = Engine.server.module(Shared .. "Config")
-- Desktop: real purchase ids, English default. Mobile: the shipped "Coming soon" ids and the
-- "auto" language on a Korean client (should boot straight into Korean).
for _, realm in { Engine.server, Engine.client } do
	local realmConfig = realm.module(Shared .. "Config")
	if mobile then
		realmConfig.DefaultLanguage = "auto"
	else
		realmConfig.Products[1].id = 111
		realmConfig.Passes[1].id = 222
		local productIds = {
			UnlockBoost = 333,
			InstantUnlock = 501,
			TimedBoost = 502,
			PetReroll = 503,
			GuaranteedMutation = 504,
			BackpackFill = 505,
			GodShark = 506,
		}
		for _, product in realmConfig.Products do
			if productIds[product.key] then
				product.id = productIds[product.key]
			end
		end
		local passIds = { VIPAura = 444, AutoSell = 601, SwimTrail = 602, BorderSilver = 603, BorderGold = 604, StarterPack = 605 }
		for _, pass in realmConfig.Passes do
			if passIds[pass.key] then
				pass.id = passIds[pass.key]
			end
		end
	end
end
if mobile then
	Engine.options.locale = "ko-kr"
end
local Layout = Engine.server.module(Shared .. "Layout")
local Economy = Engine.server.module(Shared .. "Economy")
local Worlds = Engine.server.module(Shared .. "Data.Worlds")

Engine.installAnalyticTerrain(Layout, Config)

local function worldFolder(world: number)
	local worlds = rawGame:GetService("Workspace"):FindFirstChild("Worlds")
	return worlds and worlds:FindFirstChild("World" .. world)
end

local player
local State, ClientNet
local Sessions, ProfileStore, Sync, DiveService

local function session()
	return Sessions.get(player)
end

local function root()
	return Engine.rootOf(player)
end

local function moveTo(position: Vector3)
	local r = root()
	if r then
		r.CFrame = CFrame.new(position)
	end
end

local function lagoon(world: number, lx: number, depth: number, lz: number): Vector3
	return Layout.origin(world) + Vector3.new(lx, -depth, lz)
end

local function invoke(action: string, payload: any?)
	local result = ClientNet.invoke(action, payload)
	return result
end

-- Scans every text object for untranslated keys ("hud.coins") and unfilled "{placeholders"}.
-- Returns how many texts contain Hangul.
local function auditTexts(language: string): number
	local hangul = 0
	local function scan(container)
		for _, d in container:GetDescendants() do
			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				local text = d.Text
				check(not string.find(text, "^%l+%.[%w%.]+$"), string.format("[%s] raw string key shown: %s (%s)", language, text, d:GetFullName()))
				check(not string.find(text, "{%a+}"), string.format("[%s] unfilled placeholder: %s (%s)", language, text, d:GetFullName()))
				if Engine.isVisible(d) then
					for _, code in utf8.codes(text) do
						if code >= 0xAC00 and code <= 0xD7A3 then
							hangul += 1
							if language == "en" and text ~= "한국어" then
								print("   still Korean: " .. text .. "  (" .. d:GetFullName() .. ")")
							end
							break
						end
					end
				end
			end
		end
	end
	scan(Engine.gui())
	scan(rawGame:GetService("Workspace"))
	return hangul
end

---------------------------------------------------------------------------------------------------

step("boot server", function()
	-- A place saved mid-play keeps a stale "Worlds" folder with only World 1; the server must
	-- clear it, or clients find it first and never see the worlds built this session.
	local workspace = rawGame:GetService("Workspace")
	local staleWorlds = roblox.Instance.new("Folder")
	staleWorlds.Name = "Worlds"
	local staleWorld1 = roblox.Instance.new("Folder")
	staleWorld1.Name = "World1"
	staleWorld1.Parent = staleWorlds
	staleWorlds.Parent = workspace
	Engine.runServerScripts()
	check(
		Engine.waitFor(function()
			local wf = worldFolder(1)
			return wf and wf:GetAttribute("Ready") == true
		end, 60, "World 1 ready"),
		"World 1 did not finish building"
	)
	Engine.wait(0.3)
	Sessions = Engine.server.module("ServerScriptService.Server.Sessions")
	ProfileStore = Engine.server.module("ServerScriptService.Server.ProfileStore")
	Sync = Engine.server.module("ServerScriptService.Server.Sync")
	DiveService = Engine.server.module("ServerScriptService.Server.Services.DiveService")
	check(rawGame:GetService("ReplicatedStorage"):FindFirstChild("Remotes"), "Remotes folder missing")
	local worldsFolders = 0
	for _, child in workspace:GetChildren() do
		if child.Name == "Worlds" then
			worldsFolders += 1
		end
	end
	check(worldsFolders == 1 and staleWorlds.Parent == nil, "stale saved Worlds folder was not cleared")
end)

step("join + client boot", function()
	player = Engine.addPlayer("Diver", 1001)
	check(
		Engine.waitFor(function()
			return session() ~= nil and session().ready
		end, 20, "server session"),
		"session never became ready"
	)
	check(
		Engine.waitFor(function()
			return root() ~= nil
		end, 10, "character"),
		"character never spawned"
	)
	Engine.runClientScripts(player)
	check(
		Engine.waitFor(function()
			for _, entry in Engine.traffic do
				if entry.dir == "s2c-return" and entry.request[1] == "Ready" and entry.args[1] and entry.args[1].ok then
					return true
				end
			end
			return false
		end, 20, "Ready handshake"),
		"client handshake failed"
	)
	State = Engine.client.module("Players.Diver.PlayerScripts.Client.State")
	ClientNet = Engine.client.module("Players.Diver.PlayerScripts.Client.ClientNet")
	Engine.wait(1.5)
	check(State.profile ~= nil, "client has no profile")
	check(State.world == 1, "client world should be 1")
	local spawnAt = Layout.spawnCFrame(1).Position
	check((root().Position - spawnAt).Magnitude < 8, "character should stand at the World 1 spawn")
	local pad = Engine.gui():FindFirstChild("SwimPad", true)
	check(pad ~= nil and not pad.Visible, "swim pad should stay hidden on land")
end)

step("fonts are rounded everywhere", function()
	local fredoka = roblox.Font.fromEnum(Enum.Font.FredokaOne).Family
	local checked, wrong = 0, {}
	local function scan(container)
		for _, d in container:GetDescendants() do
			if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
				checked += 1
				if d.FontFace.Family ~= fredoka then
					table.insert(wrong, d:GetFullName() .. " (" .. d.FontFace.Family .. ")")
				end
			end
		end
	end
	scan(Engine.gui())
	scan(rawGame:GetService("Workspace"))
	check(checked > 50, "expected many text objects, found " .. checked)
	local bootHangul = auditTexts("boot")
	if mobile then
		check(bootHangul >= 8, 'a Korean client on the "auto" language should boot in Korean (' .. bootHangul .. ")")
	else
		check(bootHangul == 0, "the default UI should be English (" .. bootHangul .. " Hangul texts)")
	end
	check(#wrong == 0, "non-rounded fonts: " .. table.concat(wrong, ", ", 1, math.min(#wrong, 8)))
	print("   text objects checked: " .. checked)
end)

step("every pet, relic, chest and egg builds cleanly", function()
	local PetModels = Engine.client.module(Shared .. "Models.PetModels")
	local RelicModels = Engine.client.module(Shared .. "Models.RelicModels")
	local built = 0
	local function inspect(model, label: string)
		local raw = Engine.unwrap(model)
		check(raw.PrimaryPart ~= nil, label .. " has no PrimaryPart")
		local parts = 0
		for _, d in raw:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				local position = d.CFrame.Position
				check(position == position, label .. " has a NaN part (" .. d.Name .. ")")
				check(not d.CanCollide, label .. " has a colliding part (" .. d.Name .. ")")
				check(d.Anchored, label .. " has an unanchored part (" .. d.Name .. ")")
			end
		end
		check(parts >= 3, label .. " has only " .. parts .. " parts")
		local _, size = model:GetBoundingBox()
		check(size.Magnitude > 1 and size.Magnitude < 30, label .. " has an odd size " .. tostring(size))
		built += 1
		model:Destroy()
	end
	for key, pet in Worlds.pets do
		inspect(PetModels.build(key), "pet " .. key .. " (" .. pet.shape .. ")")
	end
	for key, relic in Worlds.relics do
		inspect(RelicModels.build(key), "relic " .. key .. " (" .. relic.shape .. ")")
	end
	for world = 1, Config.WorldCount do
		inspect(RelicModels.buildChest(world), "chest " .. world)
		inspect(RelicModels.buildEgg(world), "egg " .. world)
	end
	local GearModels = Engine.client.module(Shared .. "Models.GearModels")
	local Gear = Engine.client.module(Shared .. "Data.Gear")
	for _, item in Gear.list do
		inspect(GearModels.build(item.key), "gear " .. item.key)
	end
	local Mutations = Engine.client.module(Shared .. "Models.Mutations")
	for _, mutation in Config.Mutations do
		local model = PetModels.build("p5.5")
		Mutations.apply(model, { "Gold", mutation.key })
		check(model:GetAttribute("Mutation") == mutation.key or mutation.key == "Gold", "mutation look " .. mutation.key)
		inspect(model, "mutated pet " .. mutation.key)
	end
	local key, list = Mutations.parse("p1.2|Gold,Lava")
	check(key == "p1.2" and #list == 2 and list[2] == "Lava", "follower mutation parse")
	print("   models built: " .. built)
end)

step("dive, collect, surface", function()
	local layout = State.layout
	check(layout and layout.id > 0, "no relic layout on the client")
	local s = session()
	moveTo(lagoon(1, 0, 8, 0))
	check(
		Engine.waitFor(function()
			return s.mode == "Diving"
		end, 3, "dive start"),
		"server did not start the dive"
	)
	check(
		Engine.waitFor(function()
			return State.dive.active
		end, 3, "client dive state"),
		"client did not enter dive state"
	)
	Engine.wait(0.2)
	local pad = Engine.gui():FindFirstChild("SwimPad", true)
	check(pad and pad.Visible == mobile, "swim pad should show underwater only on touch devices")
	local wf = worldFolder(1)
	local points = game:GetService("HttpService"):JSONDecode(wf:GetAttribute("Points"))
	local capacity = Economy.stat(s.profile.gear.equip, "pack")
	local collected = 0
	for point in State.layout.relics do
		if collected >= capacity then
			break
		end
		local p = points[point]
		moveTo(Vector3.new(p[1], p[2], p[3]))
		Engine.wait(0.12)
		collected += 1
	end
	check(
		Engine.waitFor(function()
			return #s.profile.backpack == collected
		end, 3, "backpack"),
		string.format("server backpack %d, expected %d", #s.profile.backpack, collected)
	)
	check(State.dive.cargo == #s.profile.backpack, "client backpack count mismatch")
	check(s.profile.stats.relics == collected, "lifetime relic count should track pickups")
	check(player:GetAttribute("Relics") == collected, "Relics attribute not published")
	local coinsBefore = s.profile.coins
	local since = os.clock()
	moveTo(lagoon(1, 0, 1.6, 0))
	check(
		Engine.waitFor(function()
			return s.mode == "Dock"
		end, 3, "surface"),
		"server did not end the dive on surfacing"
	)
	local surfaced = Engine.lastPush("surfaced", since)
	check(surfaced and surfaced.gathered == collected and not surfaced.rescued, "surfaced push missing")
	check(s.profile.coins == coinsBefore, "surfacing must not sell any more")
	check(#s.profile.backpack == collected, "treasure should stay in the backpack after surfacing")
	-- The Sell prompt from too far away is refused; stepping onto the gold pad sells.
	local far = invoke("Sell")
	check(not far.ok and far.err == "sellFar", "selling away from the stand must fail (" .. tostring(far.err) .. ")")
	local spot = Layout.origin(1) + Layout.dock(1).sell
	since = os.clock()
	moveTo(spot + Vector3.new(0, 3, 0))
	check(
		Engine.waitFor(function()
			return Engine.lastPush("sold", since) ~= nil
		end, 3, "sale at the stand"),
		"standing on the sell pad did not sell"
	)
	local sold = Engine.lastPush("sold", since)
	check(sold and sold.count == collected and sold.payout > 0, "sold push missing or empty")
	check(s.profile.coins > coinsBefore, "coins did not increase")
	check(#s.profile.backpack == 0, "backpack should be empty after selling")
	check(s.profile.worlds["1"].sold == collected, "treasure progress should count the sale")
	local empty = invoke("Sell")
	check(not empty.ok and empty.err == "nothingToSell", "selling an empty backpack must fail")
	Engine.wait(0.5)
	check(State.profile.coins == s.profile.coins, "client coins not synced")
	check(player:GetAttribute("Coins") == s.profile.coins, "Coins attribute not published")
	check(State.dive.cargo == 0, "client backpack should read empty")
end)

step("nameplates, player list, leaderboard", function()
	local gui = Engine.gui()
	-- New divers see the starter pack advertised bottom-right (only when it has a real id).
	local starter = gui:FindFirstChild("StarterOffer", true)
	check(starter ~= nil, "starter pack card missing from the HUD")
	if starter and not mobile then
		check(
			Engine.waitFor(function()
				return starter.Visible
			end, 3, "starter card"),
			"starter pack card should show for a new diver"
		)
	end
	-- The right-hand column: the limited GOD Shark is always on sale, laid out like the left rail.
	local shark = gui:FindFirstChild("GodSharkButton", true)
	check(shark ~= nil and shark.Visible, "GOD Shark button missing from the HUD")
	local rail = gui:FindFirstChild("RightRail", true)
	local grid = rail and rail:FindFirstChildOfClass("UIGridLayout")
	check(grid ~= nil, "right rail should be a grid like the left menu")
	if grid and not mobile then
		check(grid.FillDirectionMaxCells >= 4, "desktop right rail should be a single column")
	end
	if rail and mobile then
		-- Phones: the block must end above Roblox's jump button (which reaches 90px up on small screens).
		-- The rail hangs from its bottom edge, in canvas units below the HUD (which starts under the
		-- 58px top bar and is scaled by the canvas UIScale).
		local canvasScale = rail.Parent and rail.Parent:FindFirstChildOfClass("UIScale")
		local s = if canvasScale then canvasScale.Scale else 1
		local bottom = 58 + rail.Position.Y.Offset * s
		check(
			rail.Position.Y.Scale == 0 and bottom <= Engine.options.viewport.Y - 90,
			"touch right rail overlaps the jump button (bottom " .. bottom .. ")"
		)
	end
	-- Every dock has a GOD Shark stand with a buy prompt and the big floating shark.
	local dockFolder = worldFolder(1):FindFirstChild("Dock")
	local anchor = dockFolder and dockFolder:FindFirstChild("GodSharkAnchor")
	check(anchor ~= nil and anchor:FindFirstChild("GodSharkPrompt") ~= nil, "GOD Shark stand prompt missing")
	check(dockFolder ~= nil and dockFolder:FindFirstChild("GodSharkDisplay") ~= nil, "GOD Shark display missing")
	local plate = gui:FindFirstChild("DeepDiveNameplate")
	check(plate ~= nil, "no nameplate above the diver")
	local list = gui:FindFirstChild("PlayerList", true)
	check(list ~= nil and list:FindFirstChild(player.Name) ~= nil, "player list has no row for the diver")
	check(
		Engine.waitFor(function()
			local value = rawGame:GetService("ReplicatedStorage"):FindFirstChild("LeaderboardData")
			return value and string.find(value.Value, tostring(player.UserId), 1, true) ~= nil
		end, 20, "leaderboard entry"),
		"leaderboard never listed the diver"
	)
	local board = worldFolder(1):FindFirstChild("BoardScreen", true)
	local boardGui = Engine.gui():FindFirstChild("LeaderboardGui")
	check(board ~= nil and boardGui ~= nil and boardGui.Adornee == board, "dock leaderboard board not drawn")
end)

if not quick then
	step("gear shop and worn gear", function()
		local s = session()
		s.profile.coins = 1e7
		Sync.profile(s)
		Engine.wait(0.2)
		local oxygenBefore = s.oxygenMax
		for _, key in { "tank1b", "pack1a", "fins1a", "magnet1b" } do
			local result = invoke("BuyGear", { key = key })
			check(result.ok, "BuyGear " .. key .. " failed: " .. tostring(result.err))
			check(s.profile.gear.owned[key] and result.data and result.data.equipped, key .. " not owned/equipped")
		end
		check(s.oxygenMax > oxygenBefore, "a better tank should raise max oxygen")
		check(invoke("BuyGear", { key = "tank1a" }).ok, "buying a lower tier should still work")
		check(s.profile.gear.equip.tank == "tank1b", "a worse piece must not replace the worn one")
		check(invoke("EquipGear", { key = "tank1a" }).ok and s.profile.gear.equip.tank == "tank1a", "EquipGear failed")
		check(invoke("EquipGear", { key = "tank1b" }).ok, "re-equip failed")
		local owned = invoke("BuyGear", { key = "tank1b" })
		check(not owned.ok and owned.err == "gearOwned", "buying owned gear must fail")
		local locked = invoke("BuyGear", { key = "tank5a" })
		check(not locked.ok and locked.err == "err.locked", "gear of a locked world must not sell")
		check(not invoke("BuyGear", { key = "rocket9" }).ok, "unknown gear accepted")
		check(not invoke("EquipGear", { key = "fins3a" }).ok, "equipping unowned gear accepted")
		Engine.wait(0.3)
		local character = Engine.unwrap(player).Character
		local worn = character and character:FindFirstChild("DeepDiveGear")
		check(worn ~= nil, "gear is not worn on the avatar")
		if worn then
			local models, welded = 0, true
			for _, model in worn:GetChildren() do
				models += 1
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") and (d.Anchored or not d.Massless or d.CanCollide or not d:FindFirstChildOfClass("WeldConstraint")) then
						welded = false
					end
				end
			end
			check(models == 5, "expected 5 worn gear models (two flippers), got " .. models)
			check(welded, "worn gear must be welded, massless and non-colliding")
		end
		check(State.profile.gear.equip.pack == "pack1a", "client did not get the gear")
	end)

	step("eggs and pets", function()
		local s = session()
		local dock = Layout.dock(1)
		moveTo(Layout.origin(1) + dock.egg + Vector3.new(0, 3, 4))
		Engine.wait(0.3)
		local one = invoke("Hatch", { world = 1, count = 1 })
		check(one.ok, "Hatch x1 failed: " .. tostring(one.err))
		local three = invoke("Hatch", { world = 1, count = 3 })
		check(three.ok, "Hatch x3 failed: " .. tostring(three.err))
		Engine.wait(4)
		s.profile.coins += Economy.eggCost(1) * 5
		local five = invoke("Hatch", { world = 1, count = 5 })
		check(five.ok and five.data and #five.data.results == 5, "Hatch x5 failed: " .. tostring(five.err))
		check(not invoke("Hatch", { world = 1, count = 4 }).ok, "only x1, x3 and x5 hatches are allowed")
		check(Engine.gui():FindFirstChild("StopAutoHatch", true) ~= nil, "auto-hatch stop button missing")
		Engine.wait(4)
		local count = 0
		local anyId
		for id in s.profile.pets do
			count += 1
			anyId = id
		end
		check(count == 9, "expected 9 pets, got " .. count)
		check(#s.profile.equipped >= 1, "hatched pets should auto-equip")
		check(invoke("EquipBest").ok, "EquipBest failed")
		check(invoke("UnequipAll").ok and #s.profile.equipped == 0, "UnequipAll failed")
		check(invoke("Equip", { id = anyId, on = true }).ok, "Equip failed")
		check(invoke("SetLock", { id = anyId, locked = true }).ok, "SetLock failed")
		check(not invoke("DeletePet", { id = anyId }).ok, "locked pet must not be deletable")
		check(invoke("SetLock", { id = anyId, locked = false }).ok, "unlock failed")
		check(invoke("DeletePet", { id = anyId }).ok, "DeletePet failed")
		check(s.profile.pets[anyId] == nil, "pet not deleted")
		local far = Layout.spawnCFrame(1).Position + Vector3.new(0, 0, 60)
		moveTo(far)
		Engine.wait(0.2)
		check(not invoke("Hatch", { world = 1, count = 1 }).ok, "hatching far from the egg must fail")
		Engine.wait(1)
		local pets = game:GetService("HttpService"):JSONDecode(player:GetAttribute("Pets") or "[]")
		check(#pets == #s.profile.equipped, "Pets attribute does not match the equipped pets")

		-- Enchanting: coins add a random new mutation; Lucky Enchants roll Galaxy or better.
		local petId = next(s.profile.pets)
		check(invoke("Equip", { id = petId, on = true }).ok, "equip before enchanting")
		s.profile.coins = 1e9
		local first = invoke("Mutate", { id = petId })
		check(first.ok and #s.profile.pets[petId].m == 1, "Mutate failed: " .. tostring(first.err))
		check(first.data and Economy.Mutations[first.data.mutation] ~= nil, "Mutate returned no mutation")
		local noLucky = invoke("Mutate", { id = petId, lucky = true })
		check(not noLucky.ok and noLucky.err == "noLucky", "lucky enchant without tokens must fail")
		s.profile.enchants = 1
		local lucky = invoke("Mutate", { id = petId, lucky = true })
		check(lucky.ok and table.find(Config.LuckyMutations, lucky.data.mutation) ~= nil, "lucky enchant must roll Galaxy+")
		check(s.profile.enchants == 0, "lucky token not spent")
		for _ = 1, 3 do
			check(invoke("Mutate", { id = petId }).ok, "enchant until full")
		end
		local full = invoke("Mutate", { id = petId })
		check(not full.ok and full.err == "mutateMax", "enchanting past every mutation must fail")
		check(Economy.mutationMultiplier(s.profile.pets[petId].m) == 20, "a fully mutated pet is x20")
		Engine.wait(0.5)
		local followers = game:GetService("HttpService"):JSONDecode(player:GetAttribute("Pets") or "[]")
		local tagged = false
		for _, entry in followers do
			tagged = tagged or string.find(entry, "|", 1, true) ~= nil
		end
		check(tagged, "followers should carry the mutation tag")
	end)

	step("pet trading", function()
		local s = session()
		local friend = Engine.addPlayer("Buddy", 1002)
		local friendSession
		check(
			Engine.waitFor(function()
				friendSession = Sessions.get(friend)
				return friendSession ~= nil and friendSession.ready
			end, 20, "friend session"),
			"second player never loaded"
		)
		friendSession.profile.petSeq += 1
		friendSession.profile.pets["P1"] = { s = "p1.3", l = false }
		local myPet = s.profile.equipped[1]
		local myKey = s.profile.pets[myPet].s
		local myMutations = #s.profile.pets[myPet].m
		local since = os.clock()
		local request = invoke("TradeRequest", { userId = 1002 })
		check(request.ok and not request.data.started, "trade request failed: " .. tostring(request.err))
		check(Engine.lastPush("tradeRequest", since, friend) ~= nil, "friend got no trade request")
		local accept = Engine.invokeAs(friend, "TradeRespond", { userId = 1001, accept = true })
		check(accept.ok, "accepting the trade failed: " .. tostring(accept.err))
		Engine.wait(0.3)
		check(s.trade ~= nil and friendSession.trade == s.trade, "trade did not open for both")
		local Strings = Engine.client.module(Shared .. "Strings")
		local panel = Engine.gui():FindFirstChild("Panel_" .. Strings.get("tradeTitle"), true)
		check(panel ~= nil and panel.Visible, "trade window did not open")
		check(not invoke("TradeOffer", { ids = { "P999" } }).ok, "offering a pet you do not own must fail")
		check(invoke("TradeOffer", { ids = { myPet } }).ok, "TradeOffer failed")
		check(Engine.invokeAs(friend, "TradeOffer", { ids = { "P1" } }).ok, "friend TradeOffer failed")
		check(invoke("TradeReady", { ready = true }).ok, "TradeReady failed")
		-- Changing an offer clears both ready flags.
		check(Engine.invokeAs(friend, "TradeOffer", { ids = {} }).ok and not s.trade.ready[player], "offer change must reset ready")
		check(Engine.invokeAs(friend, "TradeOffer", { ids = { "P1" } }).ok, "friend re-offer failed")
		check(invoke("TradeReady", { ready = true }).ok, "TradeReady failed")
		check(Engine.invokeAs(friend, "TradeReady", { ready = true }).ok, "friend TradeReady failed")
		since = os.clock()
		check(
			Engine.waitFor(function()
				return Engine.lastPush("tradeClosed", since) ~= nil
			end, Config.TradeCountdown + 3, "trade done"),
			"trade never completed"
		)
		local closed = Engine.lastPush("tradeClosed", since)
		check(closed and closed.reason == "done" and closed.got == 1, "trade result push wrong")
		check(s.profile.pets[myPet] == nil and table.find(s.profile.equipped, myPet) == nil, "traded pet still owned")
		local gotBack, gaveAway = false, false
		for _, pet in s.profile.pets do
			gotBack = gotBack or pet.s == "p1.3"
		end
		for _, pet in friendSession.profile.pets do
			gaveAway = gaveAway or (pet.s == myKey and pet.m ~= nil and #pet.m == myMutations)
		end
		check(gotBack, "did not receive the friend's pet")
		check(gaveAway, "friend did not receive the pet with its mutations")
		check(s.trade == nil and friendSession.trade == nil, "trade not cleaned up")
		-- A second trade cancelled by leaving.
		check(invoke("TradeRequest", { userId = 1002 }).ok, "second request failed")
		check(Engine.invokeAs(friend, "TradeRequest", { userId = 1001 }).ok and s.trade ~= nil, "mutual request should open a trade")
		since = os.clock()
		Engine.removePlayer(friend)
		Engine.wait(0.5)
		local left = Engine.lastPush("tradeClosed", since)
		check(left and left.reason == "left" and s.trade == nil, "leaving must cancel the trade")
		Engine.wait(0.5)
	end)

	step("chest and world clear", function()
		local s = session()
		local progress = s.profile.worlds["1"]
		progress.sold = Economy.goal(1)
		DiveService.rollLayout(s)
		Engine.wait(0.3)
		check(State.layout.chest == true, "chest should be active after reaching the goal")
		moveTo(lagoon(1, 0, 8, 0))
		check(
			Engine.waitFor(function()
				return s.mode == "Diving"
			end, 3, "dive start"),
			"dive did not start"
		)
		local chest = game:GetService("HttpService"):JSONDecode(worldFolder(1):GetAttribute("Chest"))
		moveTo(Vector3.new(chest[1], chest[2], chest[3]))
		check(
			Engine.waitFor(function()
				return s.chestCarried
			end, 3, "chest pickup"),
			"chest was not picked up"
		)
		local since = os.clock()
		moveTo(lagoon(1, 0, 1.6, 0))
		check(
			Engine.waitFor(function()
				return Engine.lastPush("cleared", since) ~= nil
			end, 4, "cleared push"),
			"world clear not pushed"
		)
		check(s.profile.worlds["1"].cleared, "World 1 should be cleared")
		check(s.profile.unlocked == 1, "clearing must not unlock World 2 for free")
		local clearedPush = Engine.lastPush("cleared", since)
		check(clearedPush and clearedPush.nextWorld == 2 and clearedPush.unlockCost == Economy.unlockCost(2), "cleared push should offer World 2")
		-- The celebration popup appears; dismiss it with "Stay" like a player would.
		local Strings = Engine.client.module(Shared .. "Strings")
		local overlay = Engine.gui():FindFirstChild("DeepDiveOverlay")
		local popup
		check(
			Engine.waitFor(function()
				popup = overlay and overlay:FindFirstChild("Clear", true)
				return popup ~= nil
			end, 3, "clear popup"),
			"world clear popup did not appear"
		)
		if popup then
			Engine.wait(1)
			for _, d in popup:GetDescendants() do
				if d:IsA("TextLabel") and d.Text == Strings.get("stay") then
					local button = d:FindFirstAncestorWhichIsA("GuiButton")
					if button then
						Engine.click(button)
					end
				end
			end
			check(
				Engine.waitFor(function()
					return popup.Parent == nil
				end, 3, "popup close"),
				"Stay did not close the clear popup"
			)
		end
		-- Unlocking World 2 costs coins.
		check(not invoke("UnlockWorld", { world = 3 }).ok, "skipping a world must fail")
		s.profile.coins = Economy.unlockCost(2) - 1
		local poor = invoke("UnlockWorld", { world = 2 })
		check(not poor.ok and poor.err == "notEnough", "unlocking without enough coins must fail")
		s.profile.coins = Economy.unlockCost(2) + 500
		local paid = invoke("UnlockWorld", { world = 2 })
		check(paid.ok and s.profile.unlocked == 2, "UnlockWorld failed: " .. tostring(paid.err))
		check(s.profile.coins == 500, "the unlock fee was not charged")
		check(not invoke("UnlockWorld", { world = 2 }).ok, "unlocking twice must fail")
		Engine.wait(1)
	end)

	step("travel to World 2", function()
		local s = session()
		local result = invoke("Teleport", { world = 2 })
		check(result.ok, "Teleport failed: " .. tostring(result.err))
		check(
			Engine.waitFor(function()
				return State.world == 2 and not State.traveling
			end, 10, "client in World 2"),
			"client did not arrive in World 2"
		)
		check(s.world == 2, "server world should be 2")
		check((root().Position - Layout.spawnCFrame(2).Position).Magnitude < 8, "character should be at the World 2 spawn")
		check(not invoke("Teleport", { world = 5 }).ok, "locked world teleport must fail")
		Engine.wait(1)
	end)

	step("hazard and blackout", function()
		local s = session()
		moveTo(lagoon(2, 0, 10, 0))
		check(
			Engine.waitFor(function()
				return s.mode == "Diving"
			end, 3, "dive start"),
			"dive did not start in World 2"
		)
		local built = Engine.server.module("ServerScriptService.Server.World.WorldBuilder").get(2)
		if #built.hazards > 0 then
			local before = s.oxygen
			ClientNet.hazard(1)
			Engine.wait(0.3)
			check(before - s.oxygen >= s.oxygenMax * Config.Dive.HazardPenalty * 0.95 or s.oxygen == 0, "a hazard hit should cost 20% of max oxygen")
		end
		-- grab one relic so the rescue has something to halve
		local points = game:GetService("HttpService"):JSONDecode(worldFolder(2):GetAttribute("Points"))
		for point in State.layout.relics do
			local p = points[point]
			moveTo(Vector3.new(p[1], p[2], p[3]))
			Engine.wait(0.2)
			break
		end
		local since = os.clock()
		s.oxygen = 0.05
		check(
			Engine.waitFor(function()
				return State.dive.blackout
			end, 3, "blackout"),
			"client never showed the blackout"
		)
		check(
			Engine.waitFor(function()
				return s.mode == "Dock"
			end, 5, "rescue"),
			"rescue did not finish"
		)
		local surfaced = Engine.lastPush("surfaced", since)
		check(surfaced and surfaced.rescued and surfaced.lost == 1, "rescue should drop half of this dive's treasure")
		check((root().Position - Layout.spawnCFrame(2).Position).Magnitude < 8, "rescued diver should be back at spawn")
		Engine.wait(2)
		check(not State.dive.blackout, "blackout overlay should clear")
	end)

	step("death and respawn", function()
		local oldRoot = root()
		moveTo(lagoon(2, 0, 10, 0))
		Engine.wait(0.5)
		Engine.kill(player)
		check(
			Engine.waitFor(function()
				return root() ~= nil and root() ~= oldRoot
			end, 6, "respawn"),
			"player did not respawn"
		)
		Engine.wait(0.5)
		check((root().Position - Layout.spawnCFrame(2).Position).Magnitude < 8, "respawn should happen at the current world spawn")
		check(session().mode == "Dock", "session should be back on the dock after death")
	end)

	step("settings and Korean UI", function()
		check(invoke("Setting", { key = "lang", value = "ko" }).ok, "language setting failed")
		check(invoke("Setting", { key = "music", value = false }).ok, "music setting failed")
		check(invoke("Setting", { key = "sfx", value = false }).ok, "sfx setting failed")
		check(not invoke("Setting", { key = "lang", value = "fr" }).ok, "unsupported language accepted")
		Engine.wait(1)
		check(session().profile.settings.lang == "ko", "language not saved")
		check(State.profile.settings.lang == "ko", "client did not pick up the language")
		local koreanHangul = auditTexts("ko")
		check(koreanHangul >= 8, "Korean mode should translate the HUD (" .. koreanHangul .. ")")
		check(invoke("Setting", { key = "lang", value = "en" }).ok, "switching to English failed")
		Engine.wait(1)
		local englishHangul = auditTexts("en")
		check(englishHangul == 0, "English mode still shows " .. englishHangul .. " Korean texts")
		print(string.format("   texts with Hangul: ko %d, en %d", koreanHangul, englishHangul))
	end)

	step("purchases", function()
		local s = session()
		local market = game:GetService("MarketplaceService")
		local processReceipt = Engine.callback(market, "ProcessReceipt")
		check(type(processReceipt) == "function", "ProcessReceipt not bound")
		if mobile then
			-- Shipped config: every id is 0, so nothing is purchasable and nothing is prompted.
			local decision = processReceipt({ PlayerId = 1001, ProductId = 0, PurchaseId = "x" })
			check(decision == Enum.ProductPurchaseDecision.NotProcessedYet, "id 0 must never be granted")
			check(#Engine.purchasePrompts == 0, "a purchase prompt opened for an unconfigured id")
			return
		end
		local before = s.profile.coins
		local receipt = { PlayerId = 1001, ProductId = 111, PurchaseId = "receipt-1", CurrencySpent = 25, PlaceIdWherePurchased = 0 }
		local decision = processReceipt(receipt)
		check(decision == Enum.ProductPurchaseDecision.PurchaseGranted, "first receipt not granted")
		local after = s.profile.coins
		check(after > before, "product did not grant coins")
		local again = processReceipt(receipt)
		check(again == Enum.ProductPurchaseDecision.PurchaseGranted, "repeat receipt should still be acknowledged")
		check(s.profile.coins == after, "repeat receipt granted coins twice")
		local unknown = processReceipt({ PlayerId = 999, ProductId = 111, PurchaseId = "receipt-2" })
		check(unknown == Enum.ProductPurchaseDecision.NotProcessedYet, "receipt for an absent player must wait")
		Engine.ownedPasses[222] = true
		Engine.fire(market, "PromptGamePassPurchaseFinished", player, 222, true)
		Engine.wait(0.5)
		check(s.passes.DoubleCoins == true, "game pass purchase not applied")
		local shopConfig = Engine.client.module(Shared .. "Config")
		check(shopConfig.Products[1].id == 111, "client realm should see the configured product id")

		-- UnlockBoost grants exactly the next world's unlock fee.
		local wantFee = Economy.unlockCost(s.profile.unlocked + 1)
		local beforeBoost = s.profile.coins
		local boostDecision = processReceipt({ PlayerId = 1001, ProductId = 333, PurchaseId = "receipt-boost" })
		check(boostDecision == Enum.ProductPurchaseDecision.PurchaseGranted, "UnlockBoost receipt not granted")
		check(s.profile.coins == beforeBoost + wantFee, "UnlockBoost should grant exactly the next unlock fee")

		-- VIPAura is cosmetic: sets the replicated VIP attribute (crown + aura on other clients).
		check(player:GetAttribute("VIP") ~= true, "VIP attribute set before buying the pass")
		Engine.ownedPasses[444] = true
		Engine.fire(market, "PromptGamePassPurchaseFinished", player, 444, true)
		Engine.wait(0.5)
		check(s.passes.VIPAura == true and player:GetAttribute("VIP") == true, "VIPAura purchase did not set the VIP attribute")

		-- Cosmetic passes: AutoSell (functional), SwimTrail and the two border tiers (attributes).
		check(not s.passes.AutoSell, "AutoSell should not start owned")
		Engine.ownedPasses[601] = true
		Engine.fire(market, "PromptGamePassPurchaseFinished", player, 601, true)
		Engine.ownedPasses[602] = true
		Engine.fire(market, "PromptGamePassPurchaseFinished", player, 602, true)
		Engine.ownedPasses[604] = true
		Engine.fire(market, "PromptGamePassPurchaseFinished", player, 604, true)
		Engine.wait(0.5)
		check(s.passes.AutoSell and s.passes.SwimTrail and s.passes.BorderGold, "cosmetic/convenience passes not applied")
		check(player:GetAttribute("Trail") == true, "Trail attribute not set")
		check(player:GetAttribute("Border") == "Gold", "Border attribute should read the best owned tier")

		-- StarterPack: a one-time bundle, granted exactly once even if the event fires again.
		local beforeStarter = s.profile.coins
		Engine.ownedPasses[605] = true
		Engine.fire(market, "PromptGamePassPurchaseFinished", player, 605, true)
		Engine.wait(0.5)
		check(s.profile.coins == beforeStarter + Config.StarterPackReward.coins, "StarterPack coins not granted")
		check(s.profile.gear.owned[Config.StarterPackReward.gearKey], "StarterPack gear not granted")
		check(s.profile.starterPackGranted, "starterPackGranted flag not set")
		local afterFirstGrant = s.profile.coins
		Engine.fire(market, "PromptGamePassPurchaseFinished", player, 605, true)
		Engine.wait(0.3)
		check(s.profile.coins == afterFirstGrant, "StarterPack must not grant its bundle twice")

		-- InstantUnlock: eligible (the current frontier world cleared) unlocks the next world for
		-- free; force that here since it may or may not already be cleared at this point.
		local frontier = s.profile.unlocked
		s.profile.worlds[tostring(frontier)] = { sold = 0, cleared = true, best = 0 }
		check(
			processReceipt({ PlayerId = 1001, ProductId = 501, PurchaseId = "instant-1" }) == Enum.ProductPurchaseDecision.PurchaseGranted,
			"InstantUnlock receipt not granted"
		)
		check(s.profile.unlocked == frontier + 1, "InstantUnlock should unlock the next world for free")
		-- Bought again with no next world ready to unlock: must still grant something (coins).
		local beforeSecondInstant = s.profile.coins
		check(
			processReceipt({ PlayerId = 1001, ProductId = 501, PurchaseId = "instant-2" }) == Enum.ProductPurchaseDecision.PurchaseGranted,
			"InstantUnlock fallback not granted"
		)
		check(s.profile.coins > beforeSecondInstant, "InstantUnlock fallback should grant coins")

		-- TimedBoost: doubles the coin multiplier for its duration.
		check(s.profile.boostUntil <= os.time(), "boostUntil should start inactive")
		check(
			processReceipt({ PlayerId = 1001, ProductId = 502, PurchaseId = "boost-1" }) == Enum.ProductPurchaseDecision.PurchaseGranted,
			"TimedBoost receipt not granted"
		)
		check(s.profile.boostUntil > os.time(), "TimedBoost did not set boostUntil")

		-- PetReroll: rerolls the weakest unlocked pet into a new species from the same world
		-- (mutations reset - that's the reliable signal, since the species could coincidentally
		-- roll the same key).
		local rerollTarget
		for id, pet in s.profile.pets do
			if not pet.l then
				rerollTarget = id
				break
			end
		end
		check(rerollTarget ~= nil, "sanity: at least one unlocked pet to reroll")
		check(
			processReceipt({ PlayerId = 1001, ProductId = 503, PurchaseId = "reroll-1" }) == Enum.ProductPurchaseDecision.PurchaseGranted,
			"PetReroll receipt not granted"
		)
		check(s.profile.pets[rerollTarget :: string].m == nil, "a rerolled pet's mutations should reset")

		-- GuaranteedMutation: adds the rarest missing mutation to whichever eligible pet the
		-- server picks (not necessarily a specific one), so count mutations across every pet.
		local function totalMutations(): number
			local total = 0
			for _, pet in s.profile.pets do
				total += #(pet.m or {})
			end
			return total
		end
		local beforeMutations = totalMutations()
		check(
			processReceipt({ PlayerId = 1001, ProductId = 504, PurchaseId = "mutate-1" }) == Enum.ProductPurchaseDecision.PurchaseGranted,
			"GuaranteedMutation receipt not granted"
		)
		check(totalMutations() == beforeMutations + 1, "GuaranteedMutation did not add exactly one mutation")

		-- BackpackFill: tops the backpack off with commons of the current world.
		table.clear(s.profile.backpack)
		local capacity = math.floor(Economy.stat(s.profile.gear.equip, "pack"))
		check(
			processReceipt({ PlayerId = 1001, ProductId = 505, PurchaseId = "fill-1" }) == Enum.ProductPurchaseDecision.PurchaseGranted,
			"BackpackFill receipt not granted"
		)
		check(#s.profile.backpack == capacity, "BackpackFill should top the backpack up to capacity")
		-- Bought again with a full backpack: must still grant something (coins fallback).
		local beforeFillFallback = s.profile.coins
		check(
			processReceipt({ PlayerId = 1001, ProductId = 505, PurchaseId = "fill-2" }) == Enum.ProductPurchaseDecision.PurchaseGranted,
			"BackpackFill fallback not granted"
		)
		check(s.profile.coins > beforeFillFallback, "a full backpack should fall back to a coin grant")
		table.clear(s.profile.backpack)
		-- Limited GOD Shark: delivered with its x8 GOD enchant even past the inventory cap.
		check(
			processReceipt({ PlayerId = 1001, ProductId = 506, PurchaseId = "shark-1" }) == Enum.ProductPurchaseDecision.PurchaseGranted,
			"GodShark receipt not granted"
		)
		local shark = nil
		for _, pet in s.profile.pets do
			if pet.s == "godShark" then
				shark = pet
			end
		end
		check(shark ~= nil and shark.m ~= nil and shark.m[1] == "GOD", "GOD Shark not delivered with its GOD enchant")
	end)

	step("promo codes", function()
		local s = session()
		local before = s.profile.coins
		local ok = invoke("RedeemCode", { code = " launch " })
		check(ok.ok, "RedeemCode LAUNCH failed: " .. tostring(ok.err))
		check(s.profile.coins == before + 2000, "LAUNCH code should grant 2000 coins")
		check(s.profile.redeemed.LAUNCH == true, "code not recorded as redeemed")
		local again = invoke("RedeemCode", { code = "LAUNCH" })
		check(not again.ok and again.err == "codeUsed", "redeeming the same code twice must fail")
		local bogus = invoke("RedeemCode", { code = "NOPE12345" })
		check(not bogus.ok and bogus.err == "codeInvalid", "an unknown code must fail")
		local empty = invoke("RedeemCode", { code = "" })
		check(not empty.ok, "an empty code must fail")
	end)

	step("rewards, offers and music", function()
		local Panel = Engine.client.module("Players.Diver.PlayerScripts.Client.UI.Panel")
		local s = session()
		local before = s.profile.coins
		local daily = invoke("ClaimDaily")
		check(daily.ok and daily.data and daily.data.day == 1, "ClaimDaily failed: " .. tostring(daily.err))
		check(s.profile.coins > before, "the daily reward should pay coins")
		local again = invoke("ClaimDaily")
		check(not again.ok and again.err == "rewardClaimed", "the daily reward must not pay twice in a day")
		local early = invoke("ClaimPlaytime", { tier = 2 })
		check(not early.ok and early.err == "rewardLocked", "playtime tier 2 must be locked this early")
		s.profile.play.seconds = Config.PlaytimeRewards[2].minutes * 60 + 1
		local tier = invoke("ClaimPlaytime", { tier = 2 })
		check(tier.ok, "ClaimPlaytime tier 2 failed: " .. tostring(tier.err))
		local twice = invoke("ClaimPlaytime", { tier = 2 })
		check(not twice.ok and twice.err == "rewardClaimed", "a playtime tier must not pay twice")
		check(not invoke("ClaimPlaytime", { tier = "x" }).ok, "a junk playtime tier must be rejected")

		local button = Engine.gui():FindFirstChild("RewardsButton", true)
		check(button ~= nil, "Rewards button missing from the HUD")
		if button then
			Engine.click(button)
			Engine.wait(0.6)
			local panelApi = Panel.current()
			check(panelApi ~= nil and panelApi.root:FindFirstChild("ClaimDaily", true) ~= nil, "Rewards panel did not open from the HUD")
			Engine.wait(1.2)
			Panel.closeAll()
			Engine.wait(0.4)
		end
		check(Engine.gui():FindFirstChild("Offer", true) ~= nil, "offer card missing")

		local track = rawGame:GetService("SoundService"):FindFirstChild("Track")
		check(track ~= nil and string.find(track.SoundId, "rbxassetid://", 1, true) ~= nil, "background music is not playing")
	end)

	step("rankings, statues and community", function()
		local Strings = Engine.client.module(Shared .. "Strings")
		local s = session()
		local folder = worldFolder(s.world)
		local podium = nil
		check(
			Engine.waitFor(function()
				local statues = folder and folder:FindFirstChild("Statues")
				podium = statues and statues:FindFirstChild("Podium1")
				return podium ~= nil
					and podium:GetAttribute("weekly_UserId") == player.UserId
					and podium:FindFirstChild("Statue_weekly") ~= nil
					and podium:FindFirstChild("Statue_monthly") ~= nil
			end, 20, "podium statue"),
			"the top diver's statue never stood on the first podium"
		)
		if podium then
			check(
				Engine.waitFor(function()
					return podium:FindFirstChild("StatueFront") ~= nil and podium:FindFirstChild("StatueTitle") ~= nil
				end, 3, "statue labels"),
				"statue labels not drawn"
			)
			check(podium:GetAttribute("weekly_Display") ~= nil and podium:GetAttribute("weekly_Username") ~= nil, "statue names missing")
			-- Assembled avatar: only the root is anchored, so the joints hold the body together.
			local statue = podium:FindFirstChild("Statue_weekly")
			local root = statue and statue:FindFirstChild("HumanoidRootPart")
			local head = statue and statue:FindFirstChild("Head")
			check(root ~= nil and root.Anchored and head ~= nil and not head.Anchored, "statue should hang on its anchored root")
			-- The board opens on weekly; its arrow switches to monthly and the statues follow.
			local function hiddenWeekly(): boolean
				local part = statue and statue:FindFirstChild("UpperTorso")
				return part ~= nil and part.LocalTransparencyModifier == 1
			end
			check(not hiddenWeekly(), "weekly statues should show first")
			local BoardModule = Engine.client.module("Players.Diver.PlayerScripts.Client.Controllers.Board")
			local screen = folder and folder:FindFirstChild("BoardScreen", true)
			check(screen ~= nil and screen.CanQuery, "the board screen must be queryable so its arrows take clicks")
			check(BoardModule.selected == "weekly", "the board should open on the weekly ranking")
			if screen then
				-- The front face looks down -Z: the viewer's left (the "<" arrow) is +X, top is +Y.
				local size = screen.Size
				local top = size.Y / 2 - 0.6
				check(BoardModule.arrowAt(Vector3.new(size.X / 2 - 0.8, top, -size.Z / 2), size) == -1, "left arrow hit area")
				check(BoardModule.arrowAt(Vector3.new(-size.X / 2 + 0.8, top, -size.Z / 2), size) == 1, "right arrow hit area")
				check(BoardModule.arrowAt(Vector3.new(0, top, -size.Z / 2), size) == nil, "the title is not an arrow")
				check(BoardModule.arrowAt(Vector3.new(size.X / 2 - 0.8, 0, -size.Z / 2), size) == nil, "rows are not arrows")
			end
			BoardModule.pick(1)
			check(BoardModule.selected == "monthly", "the right arrow should step to the monthly ranking")
			check(Engine.waitFor(hiddenWeekly, 3, "board switch"), "picking another board should switch the statues")
			local title = Engine.gui():FindFirstChild("LeaderboardGui")
			local found = false
			for _, d in (if title then title:GetDescendants() else {}) do
				if d:IsA("TextLabel") and string.find(d.Text, Strings.get("board.monthly"), 1, true) then
					found = true
				end
			end
			check(found, "the board should show the monthly ranking after the arrow")
			BoardModule.pick(-1)
			check(BoardModule.selected == "weekly", "the left arrow should step back to weekly")
		end
		local statues = folder and folder:FindFirstChild("Statues")
		-- The podiums stand in one straight row, clear of decoration and dock structures.
		local p1 = statues and statues:FindFirstChild("Podium1")
		local p2 = statues and statues:FindFirstChild("Podium2")
		local p3 = statues and statues:FindFirstChild("Podium3")
		if p1 and p2 and p3 then
			local row = p1.CFrame
			for _, other in { p2, p3 } do
				local offset = row:PointToObjectSpace(other.CFrame.Position)
				check(math.abs(offset.Z) < 0.01 and other.CFrame.LookVector:Dot(row.LookVector) > 0.999, "podiums should stand in one straight row")
				check(math.abs((other.CFrame.Y - other.Size.Y / 2) - (p1.CFrame.Y - p1.Size.Y / 2)) < 0.01, "podiums should share a base height")
			end
			for _, child in folder:GetDescendants() do
				local readable, position = pcall(function()
					return child.CFrame.Position
				end)
				if readable and child:IsA("BasePart") and not child:IsDescendantOf(statues) and child.Transparency < 1 then
					for _, pod in { p1, p2, p3 } do
						local localPoint = pod.CFrame:PointToObjectSpace(position)
						local inside = math.abs(localPoint.X) < pod.Size.X / 2 + 0.5 and math.abs(localPoint.Z) < pod.Size.Z / 2 + 0.5
						check(not inside, "something overlaps a statue podium: " .. child:GetFullName())
					end
				end
			end
		end
		local director = statues and statues:FindFirstChild("DirectorPodium")
		check(director ~= nil, "Director podium missing behind the egg stand")
		local board = game:GetService("HttpService"):JSONDecode(rawGame:GetService("ReplicatedStorage").LeaderboardData.Value)
		for _, name in { "weekly", "monthly", "alltime" } do
			check(board.boards[name] ~= nil and #board.boards[name].entries > 0, name .. " board empty")
		end
		local row = Engine.gui():FindFirstChild("PlayerList", true)
		row = row and row:FindFirstChild(player.Name)
		local tag = row and row:FindFirstChild("RankTag")
		check(
			Engine.waitFor(function()
				return tag ~= nil and tag.Text == "#1"
			end, 3, "rank tag"),
			"player list should tag the weekly #1"
		)
		check(player:GetAttribute("Tier") ~= nil, "Tier attribute not set")

		-- Community: the group reward needs membership; friend invites open Roblox's dialog.
		Config.GroupId = 777
		local notMember = invoke("ClaimGroup")
		check(not notMember.ok and notMember.err == "notInGroup", "group reward must require membership")
		Config.GroupId = 0
		local invite = Engine.gui():FindFirstChild("InviteButton", true)
		check(invite ~= nil, "invite button missing")
		if invite then
			local before = Engine.invitePrompts
			Engine.click(invite)
			Engine.wait(0.3)
			check(Engine.invitePrompts > before, "invite button did not open the invite dialog")
		end
	end)

	step("profile panel and playtime", function()
		local Strings = Engine.client.module(Shared .. "Strings")
		local Panel = Engine.client.module("Players.Diver.PlayerScripts.Client.UI.Panel")
		Engine.wait(1.2)
		check(session().profile.stats.playtime > 0, "playtime should accumulate while connected")
		local profileButton = Engine.gui():FindFirstChild("profile", true)
		check(profileButton ~= nil and profileButton:IsA("GuiButton"), "profile menu button missing")
		Engine.click(profileButton)
		Engine.wait(0.5)
		-- Looked up by the live PanelApi rather than "Panel_<title>" (the frame's Name is fixed
		-- at creation, which may be a different language than whatever is active now).
		local panelApi = Panel.current()
		check(panelApi ~= nil, "profile panel did not open from the menu")
		if not panelApi then
			return
		end
		local panel = panelApi.root
		local relicsTab
		for _, d in panel:GetDescendants() do
			if d:IsA("TextLabel") and d.Text == Strings.get("profileTabRelics") then
				relicsTab = d:FindFirstAncestorWhichIsA("GuiButton")
			end
		end
		check(relicsTab ~= nil, "relics tab button not found")
		Engine.click(relicsTab)
		Engine.wait(0.3)
		local dexTitle
		local want = Strings.get("world", { n = State.world })
		for _, d in panel:GetDescendants() do
			if d:IsA("TextLabel") and string.find(d.Text, want, 1, true) then
				dexTitle = d
			end
		end
		check(dexTitle ~= nil, "relic index content did not show after switching tabs")
		Panel.closeAll()
		Engine.wait(0.4)
	end)

	step("UI monkey test", function()
		local gui = Engine.gui()
		local seen, clicks = {}, 0
		local function visibleButtons(container)
			local out = {}
			for _, d in container:GetDescendants() do
				if d:IsA("GuiButton") and Engine.isVisible(d) then
					table.insert(out, d)
				end
			end
			return out
		end
		local function press(button)
			if button.Parent and Engine.isVisible(button) then
				seen[button] = true
				clicks += 1
				Engine.click(button)
				Engine.wait(0.04)
			end
		end
		local hud = gui:FindFirstChild("DeepDiveHud")
		local panels = gui:FindFirstChild("DeepDivePanels")
		local menu = hud and hud:FindFirstChild("Menu", true)
		check(menu ~= nil, "HUD menu not found")
		-- Sweep every panel: open it from the menu, press everything inside, reopen if it closed.
		for _, entry in (menu and menu:GetChildren() or {}) do
			if entry:IsA("GuiButton") then
				press(entry)
				Engine.wait(0.3)
				for _, button in visibleButtons(panels) do
					press(button)
					if not next(visibleButtons(panels)) then
						press(entry)
						Engine.wait(0.3)
					end
				end
				Engine.wait(0.3)
			end
		end
		-- Then a seeded random walk over whatever is on screen.
		math.randomseed(7)
		for _ = 1, 160 do
			local buttons = visibleButtons(gui)
			if #buttons == 0 then
				break
			end
			press(buttons[math.random(1, #buttons)])
		end
		local unique = 0
		for _ in seen do
			unique += 1
		end
		print(string.format("   %d clicks, %d distinct buttons", clicks, unique))
		check(unique > 40, "monkey test reached only " .. unique .. " buttons")
		Engine.wait(3)
	end)
end

step("all 20 worlds", function()
	check(
		Engine.waitFor(function()
			for world = 1, Config.WorldCount do
				local wf = worldFolder(world)
				if not (wf and wf:GetAttribute("Ready")) then
					return false
				end
			end
			return true
		end, 240, "all worlds built"),
		"not every world finished building"
	)
	local WorldBuilder = Engine.server.module("ServerScriptService.Server.World.WorldBuilder")
	-- Every lagoon must actually hold water, whichever way the engine treats Water fills that
	-- overlap solid terrain, with solid ground under the spawn.
	for world = 1, Config.WorldCount do
		local info = Layout.info(world)
		local o = info.origin
		local dock = Layout.dock(world)
		local samples = {
			{ "lagoon centre", o + Vector3.new(0, -2, 0), "Water" },
			{ "deep pit", o + Vector3.new(0, -(info.depth + info.midDepth) / 2, 0), "Water" },
			{ "middle terrace", o + Vector3.new(-(info.deepRadius + info.midRadius) / 2, -(info.shelfDepth + info.midDepth) / 2, 0), "Water" },
			{ "shelf", o + Vector3.new(0, -info.shelfDepth / 2, -(info.midRadius + info.radius) / 2), "Water" },
			{ "beach inlet", o + Vector3.new(0, -2, info.radius + 1), "Water" },
			{ "under the diving board", o + Vector3.new(dock.pierEnd.X, -2, dock.pierEnd.Z), "Water" },
			{ "air above the lagoon", o + Vector3.new(0, 1, 0), "Air" },
		}
		for _, rule in { "empty", "replace" } do
			for _, sample in samples do
				local got = Engine.terrainAt(sample[2], rule)
				check(got == sample[3], string.format("World %d %s: expected %s, got %s (water rule %s)", world, sample[1], sample[3], got, rule))
			end
			local ground = Engine.terrainAt(o + Vector3.new(0, info.landY - 1, info.radius + 30), rule)
			check(ground ~= "Air" and ground ~= "Water", string.format("World %d has no ground under the spawn (%s)", world, ground))
		end
	end
	for world = 1, Config.WorldCount do
		local built = WorldBuilder.get(world)
		if built then
			check(#built.points >= Config.Dive.ActiveRelics, string.format("World %d has only %d relic points", world, #built.points))
			local expected = 0
			for _, spec in Worlds.get(world).hazards do
				expected += spec.count
			end
			check(#built.hazards >= math.floor(expected * 0.6), string.format("World %d placed %d of %d hazards", world, #built.hazards, expected))
			check(built.spawn and built.spawn.Parent ~= nil, "World " .. world .. " has no spawn")
		else
			check(false, "World " .. world .. " missing")
		end
	end
	if not quick then
		local s = session()
		s.profile.unlocked = Config.WorldCount
		Sync.profile(s)
		Engine.wait(0.3)
		for world = 3, Config.WorldCount do
			local result = invoke("Teleport", { world = world })
			check(result.ok, "Teleport to " .. world .. " failed: " .. tostring(result.err))
			check(
				Engine.waitFor(function()
					return State.world == world and not State.traveling
				end, 8, "arrive in " .. world),
				"did not arrive in World " .. world
			)
			moveTo(lagoon(world, 5, 12, 5))
			Engine.wait(0.6)
			moveTo(lagoon(world, 5, 1.6, 5))
			Engine.wait(0.6)
		end
	end
end)

step("leave, save and rejoin", function()
	local s = session()
	local coins = s.profile.coins
	local unlocked = s.profile.unlocked
	Engine.removePlayer(player)
	local store
	check(
		Engine.waitFor(function()
			store = Engine.dataStores[Config.DataStoreName]
			local record = store and store.data["p_1001"]
			return record and record.lock == nil
		end, 5, "released save"),
		"profile was not saved with its lock released"
	)
	local record = store and store.data["p_1001"]
	check(record and record.data.coins == coins, "saved coins do not match")
	check(record and record.data.unlocked == unlocked, "saved unlock does not match")
	local equip = table.clone(s.profile.gear.equip)
	-- Come back as a Director: red DIR tag, every world open and the limited GOD Shark granted.
	for _, realm in { Engine.server, Engine.client } do
		realm.module(Shared .. "Config").AdminUserIds = { 1001 }
	end
	local again = Engine.addPlayer("Diver2", 1001)
	player = again
	check(
		Engine.waitFor(function()
			return Sessions.get(again) ~= nil and Sessions.get(again).ready
		end, 10, "rejoin session"),
		"rejoin failed"
	)
	local loaded = Sessions.get(again)
	check(loaded and loaded.profile.coins == coins, "rejoined profile lost coins")
	check(loaded and loaded.profile.unlocked >= unlocked, "rejoined profile lost unlocks")
	if loaded then
		for slot, key in equip do
			check(loaded.profile.gear.equip[slot] == key, "gear in slot " .. slot .. " was unequipped by rejoining")
		end
		check(again:GetAttribute("Operator") == true, "a Director should be flagged as Operator")
		check(loaded.profile.unlocked == Config.WorldCount, "a Director should have every world open")
		local sharks = 0
		for _, pet in loaded.profile.pets do
			if pet.s == "godShark" then
				sharks += 1
			end
		end
		check(sharks >= 1, "a Director should own the GOD Shark")
	end
	if next(equip) then
		check(
			Engine.waitFor(function()
				local character = again.Character
				local gear = character and character:FindFirstChild("DeepDiveGear")
				return gear ~= nil and #gear:GetChildren() > 0
			end, 5, "worn gear"),
			"worn gear missing after rejoining"
		)
	end
	Engine.shutdown()
	Engine.wait(0.5)
	check(store.data["p_1001"].lock == nil, "BindToClose should release the lock")
end)

Engine.running = false
local errors = #Engine.errors
print("")
print(
	string.format(
		"smoke (%s): %d problem(s), %d assertion failure(s), %d remote messages, %d terrain ops",
		if mobile then "mobile" else "desktop",
		errors,
		failures,
		#Engine.traffic,
		Engine.terrainCalls
	)
)
process.exit(if errors == 0 then 0 else 1)
