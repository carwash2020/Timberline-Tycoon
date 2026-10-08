--!strict
-- SoundData: every sound in the game, by name, in one table, plus helpers
-- to play them in the world (3D) or in your ears (2D). Clients only.
--
-- Picking sounds: since Roblox's 2022 audio privacy change only Roblox's
-- own uploads and your own are guaranteed to play. The defaults below are
-- either built into every Roblox client (rbxasset://sounds/...) or used in
-- Roblox's official tutorials. To swap one: in Studio open the Toolbox ->
-- Audio, filter Creator = Roblox, pick a sound, right-click -> Copy Asset ID,
-- and paste it as "rbxassetid://<id>" below. An id that fails to load just
-- stays silent (a warning in Output), it never breaks the game.
-- GameConfig.ChopSoundId / FellSoundId still override Chop / TreeFall.

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local FellSound = require(script.Parent.FellSound)
local GameConfig = require(script.Parent.GameConfig)

local SoundData = {}

export type SoundDef = {
	id: string,
	volume: number,
	speed: { number }?, -- random playback speed between [1] and [2]
	rolloff: number?, -- studs until it's silent (3D sounds)
	looped: boolean?,
}

SoundData.Sounds = {
	-- Chopping and felling
	Chop = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.6, speed = { 1.45, 1.7 }, rolloff = 90 },
	ChopFinal = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.8, speed = { 1.05, 1.15 }, rolloff = 100 },
	Swing = { id = "rbxasset://sounds/swordslash.wav", volume = 0.25, speed = { 0.75, 0.9 } },
	LuxSwing = { id = "rbxasset://sounds/swordlunge.wav", volume = 0.32, speed = { 0.9, 1.05 } },
	ChopTooHard = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.5, speed = { 2.4, 2.6 }, rolloff = 60 },
	TreeCreak = { id = "", volume = 0.6, rolloff = 120 },
	TreeFall = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.35, speed = { 0.5, 0.6 }, rolloff = 160 },
	-- The hammer's knock when a piece goes down (HammerController): a dull
	-- thud, a touch higher than a chop so it reads as wood on wood.
	HammerKnock = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.7, speed = { 0.95, 1.1 }, rolloff = 90 },
	-- Logs, trucks, selling
	LogPickup = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.45, speed = { 0.75, 0.85 }, rolloff = 50 },
	LogLoad = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.6, speed = { 0.8, 0.9 }, rolloff = 60 },
	Splash = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.6, rolloff = 80 },
	Sell = { id = "rbxassetid://4110925712", volume = 0.7 },
	Buy = { id = "rbxassetid://4110925712", volume = 0.6, speed = { 1.2, 1.2 } },
	-- The Living Forest
	SeedPop = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.7, speed = { 1.3, 1.5 } },
	Plant = { id = "rbxasset://sounds/action_get_up.mp3", volume = 0.5, speed = { 1.2, 1.3 }, rolloff = 50 },
	FigureReveal = { id = "rbxassetid://4110925712", volume = 0.9, speed = { 0.85, 0.85 } },
	Thunder = {
		id = "rbxasset://sounds/impact_explosion_03.mp3",
		volume = 0.55,
		speed = { 0.35, 0.45 },
		rolloff = 1500,
	},
	-- UI
	UIClick = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.5 },
	Equip = { id = "rbxassetid://282906960", volume = 0.4 },
	-- Townsfolk murmur when the dialogue box opens for them (NPCController).
	NPCChatter = { id = "rbxasset://sounds/button.wav", volume = 0.2, speed = { 1.3, 1.6 }, rolloff = 40 },
	-- A truck's engine loop (VehicleFX sets the pitch per truck). Silent
	-- until an id is picked: Toolbox > Audio, Creator = Roblox, "engine".
	Engine = { id = "", volume = 0.35, looped = true, rolloff = 80 },
	-- Ambience (loops). River and the waterfall are public-domain Creator
	-- Store sounds (Pro Sound Effects: "River Water 1", "Waterfall
	-- Background Water Roar 1"). 6564308795 was a private upload Studio
	-- refuses ("experience doesn't have access permission").
	Rain = { id = "rbxassetid://1516791621", volume = 0.35, looped = true },
	River = { id = "rbxassetid://9118187543", volume = 0.4, rolloff = 70, looped = true },
	-- The living world (AmbientSound, AmbientLife, WeatherController). Empty
	-- ids are slots waiting for a sound picked in Studio (Toolbox -> Audio,
	-- Creator = Roblox): until then they stay silent and nothing breaks.
	-- Same public Pro Sound Effects pack as River (9118…) and the waterfall.
	BirdsDay = { id = "rbxassetid://9116970949", volume = 0.28, looped = true }, -- morning forest birds
	CricketsNight = { id = "", volume = 0.25, looped = true }, -- crickets and frogs, at night
	Owl = { id = "rbxassetid://9117181540", volume = 0.2, looped = true }, -- a hoot in the woods at night
	WindHowl = { id = "", volume = 0.35, looped = true }, -- the Snowfields, the isles, storms
	LavaRumble = { id = "", volume = 0.4, looped = true }, -- a low rumble at the Volcano
	WaterfallRoar = { id = "rbxassetid://9120549564", volume = 0.7, rolloff = 260, looped = true },
	FishSplash = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.22, speed = { 1.5, 1.8 }, rolloff = 60 },
	Wings = { id = "", volume = 0.4, rolloff = 60 }, -- a flock taking off
	Quack = { id = "", volume = 0.35, rolloff = 50 },
	StormCrackle = { id = "", volume = 0.5, rolloff = 200 }, -- the air crackles before a bolt
	-- Music (loops; the Settings toggle turns it off)
	MusicDay = { id = "rbxassetid://1841461968", volume = 0.18, looped = true },
	MusicNight = { id = "rbxassetid://1848183670", volume = 0.14, looped = true },
} :: { [string]: SoundDef }

-- Player settings (the Settings menu flips these).
SoundData.SfxEnabled = true
SoundData.MusicEnabled = true
SoundData.SfxVolume = 1 -- 0 to 1, the Settings stepper (mute is SfxEnabled)
SoundData.MusicVolume = 1

-- The swing for an axe. The Lux Axe has its own; everything else shares Swing.
function SoundData.SwingFor(axeId: unknown): string
	if axeId == GameConfig.LuxAxeId then
		return "LuxSwing"
	end
	return "Swing"
end

local function idFor(name: string, def: SoundDef): string
	if name == "Chop" and GameConfig.ChopSoundId ~= "" then
		return GameConfig.ChopSoundId
	elseif name == "TreeFall" and GameConfig.FellSoundId ~= "" then
		return GameConfig.FellSoundId
	end
	return def.id
end

-- A Sound for `name` (not playing yet), or nil if it has no id. Callers
-- parent it; looped sounds are theirs to stop.
function SoundData.Make(name: string): Sound?
	local def = SoundData.Sounds[name]
	if not def then
		return nil
	end
	local id = idFor(name, def)
	if id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.Volume = def.volume
	s.Looped = def.looped == true
	local speed = def.speed
	if speed then
		s.PlaybackSpeed = speed[1] + (speed[2] - speed[1]) * math.random()
	end
	if def.rolloff then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = def.rolloff
	end
	return s
end

-- Destroys a one-shot sound's `holder` (the sound or what it's in) once
-- it has played. A new Sound's TimeLength is 0 until its asset loads,
-- which is usually after Play, so this waits for Ended (slowed-down thunder
-- and tree falls run several seconds), with a fallback for one that never
-- loads or never ends.
local function removeWhenDone(s: Sound, holder: Instance)
	s.Ended:Once(function()
		holder:Destroy()
	end)
	local length = s.TimeLength / math.max(0.1, s.PlaybackSpeed)
	Debris:AddItem(holder, if s.IsLoaded and length > 0 then length + 1 else 20)
end

-- Plays a one-shot sound at a point in the world.
function SoundData.PlayAt(name: string, position: Vector3)
	if not SoundData.SfxEnabled then
		return
	end
	local s = SoundData.Make(name)
	if not s then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Name = "Sound_" .. name
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	s.Volume *= SoundData.SfxVolume
	s.Parent = holder
	s:Play()
	removeWhenDone(s, holder)
end

-- True when Connor has uploaded his own fell sound (GameConfig.FellSoundId):
-- it then replaces the procedural layers and plays once at the landing.
function SoundData.FellOverridden(): boolean
	return GameConfig.FellSoundId ~= ""
end

local function playLayer(layer: FellSound.Layer, position: Vector3)
	local s = Instance.new("Sound")
	s.Name = layer.name
	s.SoundId = layer.id
	s.Volume = layer.volume * SoundData.SfxVolume
	s.PlaybackSpeed = layer.speed
	-- 3D, positional, from the tree.
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 10
	s.RollOffMaxDistance = layer.rolloff
	local eq = layer.eq
	if eq then
		local e = Instance.new("EqualizerSoundEffect")
		e.LowGain, e.MidGain, e.HighGain = eq.low, eq.mid, eq.high
		e.Parent = s
	end
	if layer.octave then
		local pitch = Instance.new("PitchShiftSoundEffect")
		pitch.Octave = layer.octave
		pitch.Parent = s
	end
	local reverb = layer.reverb
	if reverb then
		local r = Instance.new("ReverbSoundEffect")
		r.DecayTime = reverb.decay
		r.WetLevel = reverb.wet
		r.Parent = s
	end
	local holder = Instance.new("Attachment")
	holder.Name = "Sound_" .. layer.name
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	s.Parent = holder
	s:Play()
	local length = layer.maxSec or 3
	Debris:AddItem(holder, length + 1.5)
	task.delay(length, function()
		if s.Parent then
			s:Stop()
		end
	end)
end

-- Plays a stage of the layered tree-fall ("start": the cut goes through;
-- "land": it hits the ground) at `position`. With FellSoundId set, that
-- one sound plays at the landing and nothing at the start.
function SoundData.PlayFell(stage: "start" | "land", position: Vector3, mass: number, fallSec: number?)
	if not SoundData.SfxEnabled then
		return
	end
	if SoundData.FellOverridden() then
		if stage == "land" then
			SoundData.PlayAt("TreeFall", position)
		end
		return
	end
	local layers = if stage == "start" then FellSound.Start(mass, fallSec) else FellSound.Land(mass)
	for _, layer in ipairs(layers) do
		if layer.at <= 0 then
			playLayer(layer, position)
		else
			task.delay(layer.at, playLayer, layer, position)
		end
	end
end

-- Plays a one-shot sound in the player's ears (UI, rewards).
function SoundData.Play(name: string)
	if not SoundData.SfxEnabled then
		return
	end
	local s = SoundData.Make(name)
	if not s then
		return
	end
	s.Volume *= SoundData.SfxVolume
	s.Parent = SoundService
	s:Play()
	removeWhenDone(s, s)
end

return SoundData
