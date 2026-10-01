--!strict
-- Background music: Config.MusicTracks shuffled and played back to back, forever. A new shuffle
-- never starts with the track that just ended. Quieter underwater; silent when Music is off.

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Music = {}

local LOAD_TIMEOUT = 10

local group = Instance.new("SoundGroup")
group.Name = "DeepDiveMusic"
group.Volume = Config.MusicVolume
group.Parent = SoundService

local sound = Instance.new("Sound")
sound.Name = "Track"
sound.Looped = false
sound.SoundGroup = group
sound.Parent = SoundService

local enabled = true
local started = false
local queue: { string } = {}
local last: string? = nil
local token = 0

local function reshuffle()
	queue = table.clone(Config.MusicTracks)
	for i = #queue, 2, -1 do
		local j = math.random(1, i)
		queue[i], queue[j] = queue[j], queue[i]
	end
	if #queue > 1 and queue[1] == last then
		queue[1], queue[#queue] = queue[#queue], queue[1]
	end
end

local function playNext()
	if not enabled or #Config.MusicTracks == 0 then
		return
	end
	if #queue == 0 then
		reshuffle()
	end
	local id = table.remove(queue, 1) :: string
	last = id
	token += 1
	local mine = token
	sound.SoundId = id
	sound.TimePosition = 0
	sound:Play()
	-- A track that never loads (deleted, not approved yet) is skipped instead of stalling.
	task.delay(LOAD_TIMEOUT, function()
		if mine == token and enabled and not sound.IsLoaded then
			playNext()
		end
	end)
end

sound.Ended:Connect(function()
	playNext()
end)

-- Watchdog: Ended is not guaranteed (e.g. a track that stops early), so a loaded track that has
-- sat silent for a couple of seconds also moves the playlist on.
task.spawn(function()
	local silentFor = 0
	while true do
		task.wait(1)
		if enabled and started and sound.IsLoaded and not sound.IsPlaying then
			silentFor += 1
			if silentFor >= 2 then
				silentFor = 0
				playNext()
			end
		else
			silentFor = 0
		end
	end
end)

function Music.setEnabled(on: boolean)
	if on == enabled and started then
		return
	end
	enabled = on
	started = true
	if on then
		if sound.SoundId ~= "" and sound.TimePosition > 0 then
			sound:Resume()
		else
			playNext()
		end
	else
		sound:Pause()
	end
end

-- Underwater the music sits back so the dive ambience comes through.
function Music.follow(underwater: () -> boolean)
	RunService.Heartbeat:Connect(function(dt: number)
		local target = if underwater() then Config.MusicUnderwaterVolume else Config.MusicVolume
		group.Volume += (target - group.Volume) * math.clamp(dt * 2, 0, 1)
	end)
end

return Music
