-- DeepDive Studio plugin: shows the procedurally-generated map while editing.
--
-- DeepDive's map (ocean, island, dock, decor) is built entirely by code in
-- src/server/World, so opening DeepDive.rbxlx in Studio without pressing Play
-- leaves Workspace empty. This plugin builds a World 1 preview into Workspace
-- as soon as the place is opened for editing, reusing the exact same
-- generator code the real server runs, so what you see matches Play.
-- Pressing Play always rebuilds the map from scratch (see WorldBuilder.init),
-- so this preview never affects real gameplay.
--
-- Install: copy this file into your local Roblox "Plugins" folder (Plugins
-- ribbon tab -> Plugins Folder) and restart Studio.

local RunService = game:GetService("RunService")
if not RunService:IsEdit() then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local shared = ReplicatedStorage:WaitForChild("Shared", 5)
local server = ServerScriptService:WaitForChild("Server", 5)
local worldFolder = server and server:WaitForChild("World", 5)

if not (shared and worldFolder and worldFolder:FindFirstChild("WorldBuilder")) then
	-- Not the DeepDive place (or the project layout changed): do nothing.
	return
end

-- Requires a throwaway clone of src/server/World so every build starts from
-- empty module state (and picks up any unsaved edits made in Studio's script
-- editor) instead of reusing a cached WorldBuilder that thinks World 1 is
-- already built.
local function loadWorldBuilder()
	local clone = worldFolder:Clone()
	clone.Parent = ServerScriptService
	local ok, result = pcall(require, clone:FindFirstChild("WorldBuilder"))
	clone:Destroy()
	if not ok then
		error(result, 0)
	end
	return result
end

local function buildPreview()
	local existing = Workspace:FindFirstChild("Worlds")
	if existing then
		existing:Destroy()
	end
	local ok, err = pcall(function()
		local WorldBuilder = loadWorldBuilder()
		WorldBuilder.init()
		WorldBuilder.ensure(1)
	end)
	if not ok then
		warn("[DeepDive Preview] failed to build map preview: " .. tostring(err))
	end
end

if not Workspace:FindFirstChild("Worlds") then
	buildPreview()
end

local toolbar = plugin:CreateToolbar("Deep Dive")
local button =
	toolbar:CreateButton("RebuildDeepDivePreview", "Rebuild the World 1 map preview in Workspace (edit mode only)", "", "Rebuild Map Preview")
button.Click:Connect(buildPreview)
