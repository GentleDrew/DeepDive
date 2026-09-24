--!strict
-- Sound cues built from the engine's bundled sounds (no uploaded audio). Each cue is a short
-- sequence of (sound, pitch, delay) steps so one sample can make several distinct effects.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Sfx = {}

local S = Config.Sounds

local CUES: { [string]: { { any } } } = {
	Click = { { S.Click, 1.0, 0, 0.5 } },
	Hover = { { S.Click, 1.7, 0, 0.18 } },
	Collect = { { S.Ping, 1.35, 0, 0.45 } },
	CollectRare = { { S.Ping, 1.1, 0, 0.5 }, { S.Ping, 1.4, 0.07, 0.5 }, { S.Ping, 1.75, 0.14, 0.5 } },
	Sell = { { S.Click, 1.4, 0, 0.5 }, { S.Click, 1.55, 0.06, 0.5 }, { S.Click, 1.7, 0.12, 0.5 }, { S.Ping, 1.6, 0.2, 0.5 } },
	Coin = { { S.Click, 2.0, 0, 0.25 } },
	Upgrade = { { S.Ping, 0.9, 0, 0.5 }, { S.Ping, 1.2, 0.08, 0.5 }, { S.Ping, 1.5, 0.16, 0.55 } },
	Unlock = { { S.Ping, 0.8, 0, 0.55 }, { S.Ping, 1.0, 0.1, 0.55 }, { S.Ping, 1.2, 0.2, 0.55 }, { S.Ping, 1.6, 0.3, 0.6 } },
	Warning = { { S.Ping, 0.55, 0, 0.45 }, { S.Ping, 0.55, 0.22, 0.45 } },
	Splash = { { S.Splash, 1.0, 0, 0.6 } },
	SplashSmall = { { S.Splash, 1.35, 0, 0.35 } },
	Dash = { { S.Splash, 1.8, 0, 0.3 } },
	Hurt = { { S.Snap, 0.6, 0, 0.6 }, { S.Ping, 0.5, 0.05, 0.3 } },
	Error = { { S.Click, 0.6, 0, 0.5 } },
	Open = { { S.Click, 1.25, 0, 0.35 }, { S.Ping, 1.9, 0.03, 0.18 } },
	Close = { { S.Click, 0.9, 0, 0.3 } },
	EggShake = { { S.Snap, 1.3, 0, 0.35 } },
	EggCrack = { { S.Snap, 0.9, 0, 0.5 }, { S.Ping, 1.2, 0.05, 0.4 } },
	Reveal = { { S.Ping, 1.0, 0, 0.5 }, { S.Ping, 1.25, 0.08, 0.5 }, { S.Ping, 1.5, 0.16, 0.5 }, { S.Ping, 2.0, 0.26, 0.55 } },
	Legendary = {
		{ S.Ping, 0.8, 0, 0.6 },
		{ S.Ping, 1.0, 0.1, 0.6 },
		{ S.Ping, 1.26, 0.2, 0.6 },
		{ S.Ping, 1.5, 0.3, 0.6 },
		{ S.Ping, 2.0, 0.42, 0.7 },
	},
	Clear = {
		{ S.Ping, 1.0, 0, 0.6 },
		{ S.Ping, 1.26, 0.12, 0.6 },
		{ S.Ping, 1.5, 0.24, 0.6 },
		{ S.Ping, 2.0, 0.4, 0.7 },
		{ S.Ping, 1.5, 0.6, 0.5 },
		{ S.Ping, 2.0, 0.72, 0.7 },
	},
	Blackout = { { S.Ping, 0.45, 0, 0.5 }, { S.Ping, 0.4, 0.3, 0.45 } },
	Travel = { { S.Splash, 0.7, 0, 0.5 }, { S.Ping, 1.4, 0.2, 0.35 } },
	Chest = { { S.Ping, 0.9, 0, 0.6 }, { S.Ping, 1.35, 0.1, 0.6 }, { S.Ping, 1.8, 0.2, 0.6 } },
}

local enabled = true
local group = Instance.new("SoundGroup")
group.Name = "DeepDiveSfx"
group.Volume = 0.8
group.Parent = SoundService

local pools: { [string]: { Sound } } = {}

local function acquire(id: string): Sound
	local pool = pools[id]
	if not pool then
		pool = {}
		pools[id] = pool
	end
	for _, sound in pool do
		if not sound.IsPlaying then
			return sound
		end
	end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.SoundGroup = group
	sound.Parent = SoundService
	table.insert(pool, sound)
	return sound
end

function Sfx.setEnabled(value: boolean)
	enabled = value
end

function Sfx.play(name: string, pitchScale: number?)
	if not enabled then
		return
	end
	local cue = CUES[name]
	if not cue then
		return
	end
	for _, step in cue do
		local function fire()
			local sound = acquire(step[1])
			sound.PlaybackSpeed = step[2] * (pitchScale or 1)
			sound.Volume = step[4] or 0.5
			sound.TimePosition = 0
			sound:Play()
		end
		if step[3] > 0 then
			task.delay(step[3], fire)
		else
			fire()
		end
	end
end

-- Looping swim-stroke bed while moving underwater.
local swimLoop: Sound? = nil
function Sfx.setSwimming(active: boolean, speedRatio: number?)
	if not swimLoop then
		local sound = Instance.new("Sound")
		sound.SoundId = S.Swim
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = group
		sound.Parent = SoundService
		swimLoop = sound
	end
	local loop = swimLoop :: Sound
	if active and enabled then
		if not loop.IsPlaying then
			loop:Play()
		end
		loop.Volume = 0.12 + 0.12 * math.clamp(speedRatio or 0, 0, 1)
		loop.PlaybackSpeed = 0.8 + 0.4 * math.clamp(speedRatio or 0, 0, 1)
	elseif loop.IsPlaying then
		loop:Stop()
	end
end

return Sfx
