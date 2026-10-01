--!strict
-- Labels for the podium statues at the docks (built by StatueService): rank and
-- names on the podium front, and each diver's progress to their next ranking tier above them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared.Strings)

local TierStyle = require(script.Parent.Parent.UI.TierStyle)

local Statues = {}

local MEDALS = { utf8.char(0x1F947), utf8.char(0x1F948), utf8.char(0x1F949) }

function Statues.init(app: any)
	local Kit = app.Kit
	local signatures: { [BasePart]: string } = {}

	local function signature(part: BasePart): string
		return table.concat({
			tostring(part:GetAttribute("UserId")),
			tostring(part:GetAttribute("Display")),
			tostring(part:GetAttribute("Username")),
			tostring(part:GetAttribute("NextTier")),
			tostring(part:GetAttribute("NextSeconds")),
			Strings.get("director"),
			Strings.get("tierMax"),
		}, "|")
	end

	local function render(part: BasePart)
		for _, old in part:GetChildren() do
			if old.Name == "StatueFront" or old.Name == "StatueTitle" then
				old:Destroy()
			end
		end
		local rank = part:GetAttribute("Rank")
		local director = rank == 0
		local userId = part:GetAttribute("UserId")
		if not userId then
			return
		end
		local display = tostring(part:GetAttribute("Display") or "")
		local username = tostring(part:GetAttribute("Username") or "")

		local front = Instance.new("SurfaceGui")
		front.Name = "StatueFront"
		front.Face = Enum.NormalId.Front
		front.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		front.PixelsPerStud = 40
		front.LightInfluence = 0
		front.Parent = part
		local column = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = front })
		Kit.list(column, Enum.FillDirection.Vertical, 0, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
		local head = Kit.text({
			Text = if director then Strings.get("director") else (MEDALS[rank :: number] or ""),
			TextSize = if director then 30 else 34,
			Stroke = if director then 3 else 0,
			Size = UDim2.new(1, 0, 0, 38),
			LayoutOrder = 1,
			Parent = column,
		})
		if director then
			TierStyle.director(head)
		end
		local name = Kit.text({
			Text = display,
			TextSize = 26,
			Stroke = 3,
			Size = UDim2.new(1, -8, 0, 30),
			LayoutOrder = 2,
			Parent = column,
		})
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local user = Kit.text({
			Text = "@" .. username,
			TextSize = 18,
			Color = Color3.fromRGB(225, 236, 248),
			Stroke = 2,
			Size = UDim2.new(1, -8, 0, 22),
			LayoutOrder = 3,
			Parent = column,
		})
		user.TextTruncate = Enum.TextTruncate.AtEnd

		local title = Instance.new("BillboardGui")
		title.Name = "StatueTitle"
		title.Size = UDim2.fromOffset(260, 40)
		title.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 11, 0)
		title.LightInfluence = 0
		title.MaxDistance = 120
		title.Parent = part
		local nextTier = part:GetAttribute("NextTier")
		local seconds = part:GetAttribute("NextSeconds")
		local text = if director
			then Strings.get("director")
			elseif type(nextTier) == "number" and type(seconds) == "number" then Strings.get(
				"tierNext",
				{ n = nextTier, t = Strings.duration(seconds) }
			)
			else Strings.get("tierMax")
		local line = Kit.text({
			Text = text,
			TextSize = 22,
			Color = Color3.fromRGB(255, 236, 140),
			Stroke = 2.5,
			Size = UDim2.fromScale(1, 1),
			Parent = title,
		})
		if director then
			TierStyle.director(line)
		elseif type(nextTier) == "number" then
			local color = TierStyle.color(nextTier)
			if color then
				line.TextColor3 = color
			end
		end
	end

	-- Every world's podiums (not just the current one): labels drawn while visiting another world
	-- must follow language changes too.
	local function refresh()
		local worlds = Workspace:FindFirstChild("Worlds")
		if not worlds then
			return
		end
		for _, folder in worlds:GetChildren() do
			local statues = folder:FindFirstChild("Statues")
			if statues then
				for _, part in statues:GetChildren() do
					if part:IsA("BasePart") and part:GetAttribute("Rank") ~= nil then
						local sig = signature(part)
						if signatures[part] ~= sig or not part:FindFirstChild("StatueFront") then
							signatures[part] = sig
							render(part)
						end
					end
				end
			end
		end
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(1)
		end
	end)
	app.State.languageChanged:Connect(refresh)
end

return Statues
