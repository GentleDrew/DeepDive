--!strict
-- Sound design built from the engine's bundled sounds (no uploaded audio needed). Each cue is a
-- layered sequence of { sound, pitch, delay, volume } steps with a little random pitch so repeats
-- never sound identical. Any cue can be swapped for a recording via Config.SoundIds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Sfx = {}

local S = Config.Sounds

-- Rising arpeggio of pings (a major chord: 1, 1.26, 1.5, 2).
local function chord(base: number, spacing: number, volume: number, steps: { number }): { { any } }
	local out = {}
	for i, ratio in steps do
		table.insert(out, { S.Ping :: any, base * ratio, (i - 1) * spacing, volume })
	end
	return out
end

local function concat(...: { { any } }): { { any } }
	local out = {}
	for _, list in { ... } do
		for _, step in list do
			table.insert(out, step)
		end
	end
	return out
end

local CUES: { [string]: { { any } } } = {
	Click = { { S.Button, 1.15, 0, 0.35 }, { S.Click, 1.6, 0, 0.18 } },
	Hover = { { S.Click, 2.1, 0, 0.1 } },
	Open = { { S.Swoosh, 1.5, 0, 0.22 }, { S.Ping, 2.2, 0.04, 0.12 } },
	Close = { { S.Swoosh, 1.15, 0, 0.18 } },
	Error = { { S.Button, 0.62, 0, 0.4 }, { S.Button, 0.55, 0.09, 0.35 } },
	Collect = { { S.Ping, 1.5, 0, 0.42 }, { S.Ping, 2.0, 0.05, 0.3 }, { S.Splash, 2.4, 0, 0.12 } },
	CollectRare = concat(chord(1.2, 0.06, 0.42, { 1, 1.26, 1.5, 2 }), { { S.Swoosh, 1.8, 0, 0.18 } }),
	Discover = concat(chord(1.0, 0.07, 0.45, { 1, 1.26, 1.5, 2, 2.52 }), { { S.Swoosh, 1.4, 0, 0.2 } }),
	Coin = { { S.Click, 2.3, 0, 0.2 }, { S.Ping, 3.0, 0, 0.08 } },
	Sell = concat({
		{ S.Button, 1.4, 0, 0.35 },
		{ S.Click, 2.0, 0.05, 0.3 },
		{ S.Click, 2.2, 0.1, 0.3 },
		{ S.Click, 2.4, 0.15, 0.3 },
	}, chord(1.3, 0.07, 0.42, { 1, 1.26, 1.5, 2 })),
	SellBig = concat(
		{ { S.Button, 1.2, 0, 0.4 }, { S.Swoosh, 1.2, 0, 0.25 } },
		chord(1.0, 0.07, 0.45, { 1, 1.26, 1.5, 2, 2.52, 3 }),
		chord(2.0, 0.05, 0.25, { 1, 1.5 })
	),
	Upgrade = concat(chord(0.9, 0.07, 0.45, { 1, 1.26, 1.5, 2 }), { { S.Swoosh, 1.7, 0.02, 0.22 }, { S.Button, 1.3, 0, 0.3 } }),
	Unlock = concat(chord(0.8, 0.1, 0.5, { 1, 1.26, 1.5, 2 }), { { S.Swoosh, 1.1, 0, 0.25 } }),
	Warning = { { S.Ping, 0.62, 0, 0.42 }, { S.Ping, 0.55, 0.2, 0.42 } },
	Splash = { { S.Splash, 1.0, 0, 0.65 }, { S.Splash, 1.45, 0.06, 0.3 }, { S.Swoosh, 0.7, 0, 0.18 } },
	SplashSmall = { { S.Splash, 1.35, 0, 0.35 }, { S.Splash, 1.8, 0.04, 0.15 } },
	Dash = { { S.Swoosh, 1.35, 0, 0.35 }, { S.Splash, 1.9, 0.02, 0.2 } },
	Hurt = { { S.Snap, 0.6, 0, 0.6 }, { S.Land, 0.8, 0, 0.4 }, { S.Ping, 0.45, 0.05, 0.3 } },
	EggShake = { { S.Snap, 1.3, 0, 0.3 }, { S.Land, 1.6, 0, 0.2 } },
	EggCrack = { { S.Snap, 0.85, 0, 0.55 }, { S.Swoosh, 1.6, 0.02, 0.3 }, { S.Ping, 1.4, 0.06, 0.35 } },
	Hatch = { { S.Snap, 0.85, 0, 0.55 }, { S.Swoosh, 1.6, 0.02, 0.3 } },
	Reveal = concat(chord(1.0, 0.08, 0.45, { 1, 1.26, 1.5, 2 }), { { S.Swoosh, 1.3, 0, 0.25 } }),
	Legendary = concat(chord(0.8, 0.1, 0.55, { 1, 1.26, 1.5, 2, 2.52 }), chord(1.6, 0.1, 0.35, { 1, 1.26, 1.5, 2 }), { { S.Swoosh, 0.9, 0, 0.3 } }),
	Clear = concat(
		chord(1.0, 0.12, 0.55, { 1, 1.26, 1.5, 2 }),
		chord(1.5, 0.1, 0.5, { 1, 1.33 }),
		chord(2.0, 0.1, 0.55, { 1, 1.26, 1.5 }),
		{ { S.Swoosh, 1.0, 0, 0.3 } }
	),
	Blackout = { { S.Ping, 0.45, 0, 0.5 }, { S.Ping, 0.4, 0.3, 0.45 }, { S.Swoosh, 0.5, 0, 0.3 } },
	Travel = { { S.Swoosh, 0.8, 0, 0.4 }, { S.Splash, 0.7, 0.05, 0.4 }, { S.Ping, 1.4, 0.25, 0.3 } },
	Chest = concat(chord(0.9, 0.1, 0.55, { 1, 1.26, 1.5, 2 }), { { S.Swoosh, 1.0, 0, 0.3 } }),
}

local enabled = true
local group = Instance.new("SoundGroup")
group.Name = "DeepDiveSfx"
group.Volume = 0.8
group.Parent = SoundService
-- A touch of room reverb makes the layered cues blend.
local reverb = Instance.new("ReverbSoundEffect")
reverb.DecayTime = 0.6
reverb.Density = 0.8
reverb.WetLevel = -14
reverb.DryLevel = 0
reverb.Parent = group

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
	local override = (Config.SoundIds :: any)[name]
	if type(override) == "string" and override ~= "" then
		local sound = acquire(override)
		sound.PlaybackSpeed = (pitchScale or 1) * (0.97 + math.random() * 0.06)
		sound.Volume = 0.6
		sound.TimePosition = 0
		sound:Play()
		return
	end
	local cue = CUES[name]
	if not cue then
		return
	end
	-- One random detune per cue keeps the chord intact but varies repeats.
	local detune = (pitchScale or 1) * (0.96 + math.random() * 0.08)
	for _, step in cue do
		local function fire()
			local sound = acquire(step[1])
			sound.PlaybackSpeed = step[2] * detune
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
