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
	ChopTooHard = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.5, speed = { 2.4, 2.6 }, rolloff = 60 },
	TreeCreak = { id = "", volume = 0.6, rolloff = 120 },
	TreeFall = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 0.35, speed = { 0.5, 0.6 }, rolloff = 160 },
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
	-- Ambience (loops)
	Rain = { id = "rbxassetid://1516791621", volume = 0.35, looped = true },
	River = { id = "rbxassetid://6564308795", volume = 0.4, rolloff = 70, looped = true },
	-- Music (loops; the Settings toggle turns it off)
	MusicDay = { id = "rbxassetid://1841461968", volume = 0.18, looped = true },
	MusicNight = { id = "rbxassetid://1848183670", volume = 0.14, looped = true },
} :: { [string]: SoundDef }

-- Player settings (the Settings menu flips these).
SoundData.SfxEnabled = true
SoundData.MusicEnabled = true

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
	s.Parent = holder
	s:Play()
	Debris:AddItem(holder, math.max(2, s.TimeLength / math.max(0.1, s.PlaybackSpeed) + 1))
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
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 6)
end

return SoundData
