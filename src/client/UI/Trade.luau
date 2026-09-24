--!strict
-- Pet trading UI: an incoming-request popup and the trade window (both offers side by side,
-- your pets underneath to add or remove, Ready / Cancel and the final countdown).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Format = require(Shared.Format)
local Strings = require(Shared.Strings)
local Worlds = require(Shared.Data.Worlds)
local Mutations = require(Shared.Models.Mutations)

local Anim = require(script.Parent.Anim)
local Kit = require(script.Parent.Kit)
local Panel = require(script.Parent.Panel)
local Theme = require(script.Parent.Theme)
local Viewport = require(script.Parent.Viewport)

local Trade = {}

local C = Theme.C

type PetInfo = { id: string, s: string, m: { string }? }

local function petCell(parent: Instance, info: PetInfo, order: number, onClick: (() -> ())?): TextButton
	local data = Worlds.pets[info.s]
	local rarity = Config.Rarities[if data then data.rarity else 1]
	local color = Theme.Rarity[rarity]
	local cell = Kit.new("TextButton", {
		Name = info.id,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		Parent = parent,
	}) :: TextButton
	Kit.corner(cell, 14)
	Kit.gradient(cell, color:Lerp(Color3.new(1, 1, 1), 0.55), color, 90)
	Kit.stroke(cell, color:Lerp(Color3.new(0, 0, 0), 0.5), 3)
	local view = Viewport.new(cell, UDim2.new(1, -8, 1, -30), UDim2.new(0.5, 0, 0, 3), Vector2.new(0.5, 0))
	view.setModel(Viewport.pet(info.s, info.m))
	local top = Mutations.top(info.m)
	if top then
		local dot = Kit.new("Frame", {
			BackgroundColor3 = Mutations.color(top),
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.fromOffset(5, 5),
			ZIndex = 4,
			Parent = cell,
		})
		Kit.round(dot)
		Kit.stroke(dot, C.Outline, 2)
	end
	Kit.text({
		Text = Format.multiplier(1 + Economy.petPower(info.s, info.m)),
		TextSize = 15,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -25),
		StrokeColor = color:Lerp(Color3.new(0, 0, 0), 0.6),
		Parent = cell,
	})
	if onClick then
		cell.Activated:Connect(onClick)
	end
	return cell
end

local function clearCells(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

function Trade.init(app: any)
	local current: any = nil -- latest trade view from the server
	local offered: { string } = {}

	-- Incoming request popup -----------------------------------------------------------------------
	local popup = Kit.new("Frame", {
		Name = "TradeRequest",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromOffset(420, 124),
		Position = UDim2.new(0.5, 0, 0, 132),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		ZIndex = 30,
		Parent = app.Gui.hud,
	}) :: Frame
	Kit.corner(popup, 20)
	Kit.gradient(popup, Theme.Buttons.Cyan[1], Theme.Buttons.Blue[2])
	Kit.stroke(popup, C.Outline, 3)
	local popupText = Kit.text({
		Text = "",
		TextSize = 22,
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 8),
		ZIndex = 31,
		Parent = popup,
	})
	local popupTimer = Kit.progress({
		Size = UDim2.new(1, -40, 0, 10),
		Position = UDim2.fromOffset(20, 46),
		Colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 240, 255) },
		TextSize = 1,
		Parent = popup,
	})
	local popupButtons = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 0, 50),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 31,
		Parent = popup,
	})
	Kit.list(popupButtons, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center)
	local pending: { userId: number, expires: number, seconds: number }? = nil
	local function respond(accept: boolean)
		local request = pending
		pending = nil
		popup.Visible = false
		if not request then
			return
		end
		local result = app.Net.invoke("TradeRespond", { userId = request.userId, accept = accept })
		if not result.ok and result.err then
			app.Toasts.show(Strings.get(result.err), "bad")
		end
	end
	local acceptButton = Kit.button({
		Text = "",
		TextSize = 20,
		Palette = "Green",
		Size = UDim2.fromOffset(170, 46),
		LayoutOrder = 1,
		ZIndex = 32,
		Parent = popupButtons,
		OnClick = function()
			respond(true)
		end,
	})
	local declineButton = Kit.button({
		Text = "",
		TextSize = 20,
		Palette = "Red",
		Size = UDim2.fromOffset(170, 46),
		LayoutOrder = 2,
		ZIndex = 32,
		Parent = popupButtons,
		OnClick = function()
			respond(false)
		end,
	})
	RunService.Heartbeat:Connect(function()
		local request = pending
		if request then
			local left = request.expires - os.clock()
			if left <= 0 then
				pending = nil
				popup.Visible = false
			else
				popupTimer.set(left / request.seconds, "")
			end
		end
	end)

	-- Trade window ---------------------------------------------------------------------------------
	local panel = Panel.new({
		Parent = app.Gui.panels,
		Title = Strings.get("tradeTitle"),
		Icon = utf8.char(0x1F91D),
		Palette = "Cyan",
		Size = Vector2.new(940, 610),
	})
	local body = panel.body

	local function offerBox(x: number, anchor: number): (TextLabel, Frame, Frame)
		local box = Kit.new("Frame", {
			BackgroundColor3 = C.PanelAlt,
			Size = UDim2.new(0.5, -8, 0, 262),
			Position = UDim2.new(x, 0, 0, 20),
			AnchorPoint = Vector2.new(anchor, 0),
			Parent = body,
		}) :: Frame
		Kit.corner(box, 16)
		local stroke = Kit.stroke(box, C.PanelLine, 3)
		stroke.Name = "Border"
		local title = Kit.text({
			Text = "",
			TextSize = 20,
			Size = UDim2.new(1, -120, 0, 34),
			Position = UDim2.fromOffset(12, 4),
			XAlign = Enum.TextXAlignment.Left,
			StrokeColor = C.Navy,
			Parent = box,
		})
		local readyChip = Kit.new("Frame", {
			BackgroundColor3 = C.Gray,
			Size = UDim2.fromOffset(104, 28),
			Position = UDim2.new(1, -10, 0, 7),
			AnchorPoint = Vector2.new(1, 0),
			Parent = box,
		}) :: Frame
		Kit.round(readyChip)
		Kit.stroke(readyChip, C.Outline, 2)
		Kit.text({ Name = "Label", Text = "", TextSize = 15, Size = UDim2.fromScale(1, 1), Parent = readyChip })
		local grid = Kit.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -20, 1, -48),
			Position = UDim2.fromOffset(10, 42),
			Parent = box,
		}) :: Frame
		Kit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(98, 100),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Parent = grid,
		})
		return title, readyChip, grid
	end
	local myTitle, myReady, myGrid = offerBox(0, 0)
	local theirTitle, theirReady, theirGrid = offerBox(1, 1)

	local status = Kit.text({
		Text = "",
		TextSize = 22,
		Color = C.Ink,
		Stroke = 0,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 288),
		Parent = body,
	})
	local inventoryLabel = Kit.text({
		Text = "",
		TextSize = 17,
		Color = C.Muted,
		Stroke = 0,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(4, 320),
		XAlign = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local inventory = Kit.new("ScrollingFrame", {
		BackgroundColor3 = C.PanelAlt,
		BackgroundTransparency = 0.2,
		Size = UDim2.new(1, 0, 0, 124),
		Position = UDim2.fromOffset(0, 344),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = C.NavySoft,
		BorderSizePixel = 0,
		Parent = body,
	}) :: ScrollingFrame
	Kit.corner(inventory, 14)
	Kit.padding(inventory, 8, 8, 12, 8)
	Kit.list(inventory, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)

	local buttons = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.new(0, 0, 1, -4),
		AnchorPoint = Vector2.new(0, 1),
		Parent = body,
	})
	Kit.list(buttons, Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Center)
	local readyButton = Kit.button({
		Text = "",
		TextSize = 22,
		Palette = "Green",
		Size = UDim2.fromOffset(240, 54),
		LayoutOrder = 1,
		Parent = buttons,
		OnClick = function()
			if current then
				local result = app.Net.invoke("TradeReady", { ready = not current.myReady })
				app.Sfx.play(if result.ok then "Click" else "Error")
			end
		end,
	})
	local cancelButton = Kit.button({
		Text = "",
		TextSize = 22,
		Palette = "Red",
		Size = UDim2.fromOffset(200, 54),
		LayoutOrder = 2,
		Parent = buttons,
		OnClick = function()
			panel.close()
		end,
	})

	local function setReady(chip: Frame, ready: boolean)
		chip.BackgroundColor3 = if ready then C.Green else C.Gray
		local label = chip:FindFirstChild("Label") :: TextLabel?
		if label then
			label.Text = if ready then utf8.char(0x2714) .. " " .. Strings.get("tradeReady") else Strings.get("tradeWaiting")
		end
	end

	local function sendOffer(ids: { string })
		local result = app.Net.invoke("TradeOffer", { ids = ids })
		if not result.ok then
			app.Sfx.play("Error")
			if result.err then
				app.Toasts.show(Strings.get(result.err), "bad")
			end
		else
			app.Sfx.play("Click")
		end
	end

	local function render()
		local view = current
		if not view then
			return
		end
		panel.setTitle(Strings.get("tradeWith", { name = view.partner.name }))
		myTitle.Text = Strings.get("tradeYours")
		theirTitle.Text = Strings.get("tradeTheirs", { name = view.partner.name })
		setReady(myReady, view.myReady)
		setReady(theirReady, view.theirReady)
		readyButton.setText(if view.myReady then Strings.get("tradeUnready") else Strings.get("tradeReadyButton"))
		readyButton.setPalette(if view.myReady then "Gray" else "Green")
		cancelButton.setText(Strings.get("cancel"))
		inventoryLabel.Text = Strings.get("tradePick", { n = Config.TradeMaxPets })

		offered = {}
		clearCells(myGrid)
		for order, info in view.mine do
			table.insert(offered, info.id)
			petCell(myGrid, info, order, function()
				local ids = table.clone(offered)
				local index = table.find(ids, info.id)
				if index then
					table.remove(ids, index)
				end
				sendOffer(ids)
			end)
		end
		clearCells(theirGrid)
		for order, info in view.theirs do
			petCell(theirGrid, info, order)
		end

		clearCells(inventory)
		local profile = app.State.profile
		if profile then
			local ids = {}
			for id, pet in profile.pets do
				if not table.find(offered, id) and not pet.l then
					table.insert(ids, id)
				end
			end
			table.sort(ids, function(a, b)
				local pa, pb = profile.pets[a], profile.pets[b]
				return Economy.petPower(pa.s, pa.m) > Economy.petPower(pb.s, pb.m)
			end)
			for order, id in ids do
				local pet = profile.pets[id]
				local cell = petCell(inventory, { id = id, s = pet.s, m = pet.m }, order, function()
					local next = table.clone(offered)
					table.insert(next, id)
					sendOffer(next)
				end)
				cell.Size = UDim2.fromOffset(92, 100)
			end
		end
	end

	RunService.Heartbeat:Connect(function()
		local view = current
		if not view or not panel.isOpen then
			return
		end
		if view.countdownEnds then
			local left = math.max(0, view.countdownEnds - os.clock())
			status.Text = Strings.get("tradeCountdown", { n = math.ceil(left) })
			status.TextColor3 = C.GreenDark
		elseif view.myReady and not view.theirReady then
			status.Text = Strings.get("tradeWaitingFor", { name = view.partner.name })
			status.TextColor3 = C.Muted
		else
			status.Text = Strings.get("tradeHint")
			status.TextColor3 = C.Muted
		end
	end)

	panel.onClose = function()
		if current then
			current = nil
			app.Net.invoke("TradeCancel")
		end
	end

	app.Net.on("tradeRequest", function(payload: any)
		if current then
			return
		end
		pending = { userId = payload.userId, expires = os.clock() + (payload.seconds or 20), seconds = payload.seconds or 20 }
		popupText.Text = Strings.get("tradeAsk", { name = payload.name })
		acceptButton.setText(Strings.get("accept"))
		declineButton.setText(Strings.get("decline"))
		popup.Visible = true
		Anim.pop(popup, 0.12)
		app.Sfx.play("Open")
	end)

	app.Net.on("trade", function(payload: any)
		local first = current == nil
		current = payload
		if payload.countdown then
			payload.countdownEnds = os.clock() + payload.countdown
		end
		pending = nil
		popup.Visible = false
		if first then
			app.closePanels()
			panel.open()
			app.Sfx.play("Open")
		end
		render()
	end)

	app.Net.on("tradeClosed", function(payload: any)
		current = nil
		if panel.isOpen then
			panel.close()
		end
		if payload.reason == "done" then
			app.Sfx.play("Legendary")
			app.Effects.confetti(50)
			app.Toasts.show(Strings.get("tradeDone", { n = payload.got or 0 }), "gold", utf8.char(0x1F91D))
		elseif payload.reason == "left" then
			app.Toasts.show(Strings.get("tradeLeft", { name = payload.partner or "" }), "bad")
		else
			app.Toasts.show(Strings.get("tradeCancelled"), "info")
		end
	end)

	app.State.profileChanged:Connect(function()
		if panel.isOpen then
			render()
		end
	end)
	app.State.languageChanged:Connect(render)

	-- Sends a trade request (from the player list).
	function app.requestTrade(userId: number)
		local result = app.Net.invoke("TradeRequest", { userId = userId })
		if result.ok then
			if not (result.data and result.data.started) then
				app.Toasts.show(Strings.get("tradeSent"), "info", utf8.char(0x1F91D))
			end
		else
			app.Sfx.play("Error")
			if result.err then
				app.Toasts.show(Strings.get(result.err), "bad")
			end
		end
	end

	return { panel = panel }
end

return Trade
