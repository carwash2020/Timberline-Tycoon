--!strict
-- FellSound: the layered, procedural sound of a tree coming down, built
-- from Roblox's own built-in sounds (rbxasset://sounds/...) bent with
-- pitch, EQ and reverb, so it needs no uploaded audio. Pure: it only says
-- which layers to play and when; SoundData.PlayFell makes the Sounds.
--
--   Start (the cut goes through): a groan from the wood, a sharp crack,
--     then a rushing whoosh while it tips and falls.
--   Land (the trunk reaches the ground): a heavy thud, a low sub boom and
--     a short reverb tail. The dust is WoodFX's.
--
-- To use a real recording instead, set GameConfig.FellSoundId to your
-- uploaded "rbxassetid://<id>": it then replaces every layer here with
-- that one sound, played at the landing.

local FellSound = {}

export type Eq = { low: number, mid: number, high: number }
export type Layer = {
	name: string,
	id: string,
	at: number, -- seconds after the stage starts
	volume: number,
	speed: number, -- playback speed (pitch and length together)
	rolloff: number, -- studs until silent
	eq: Eq?, -- EqualizerSoundEffect gains in dB
	octave: number?, -- PitchShiftSoundEffect (1 = none)
	reverb: { decay: number, wet: number }?,
	maxSec: number?, -- cut the layer off after this long
}

FellSound.Creak = "rbxasset://sounds/swordlunge.wav"
FellSound.Crack = "rbxasset://sounds/action_jump_land.mp3"
FellSound.Whoosh = "rbxasset://sounds/swordslash.wav"
FellSound.Boom = "rbxasset://sounds/impact_explosion_03.mp3"
FellSound.MaxLayers = 4

-- 0 (a sapling's worth) to 1 (a giant): how heavy the felled wood is.
function FellSound.Weight(mass: number): number
	if mass ~= mass then
		return 0.5
	end
	return math.clamp(mass / 60, 0, 1)
end

-- The layers played when the cut goes through. `fallSec` is how long the
-- trunk is expected to take to come down.
function FellSound.Start(mass: number, fallSec: number?): { Layer }
	local w = FellSound.Weight(mass)
	local fall = math.clamp(fallSec or 1.8, 0.8, 4)
	local rolloff = 120 + 80 * w
	return {
		{
			name = "FellCreak",
			id = FellSound.Creak,
			at = 0,
			volume = 0.28 + 0.12 * w,
			speed = 0.42 - 0.08 * w,
			rolloff = rolloff,
			eq = { low = 4, mid = 2, high = -14 },
			maxSec = 1.4,
		},
		{
			name = "FellCrack",
			id = FellSound.Crack,
			at = 0.35,
			volume = 0.7 + 0.2 * w,
			speed = 1.9 - 0.4 * w,
			rolloff = rolloff,
			eq = { low = -6, mid = 3, high = 6 },
			maxSec = 0.7,
		},
		{
			name = "FellWhoosh",
			id = FellSound.Whoosh,
			at = 0.6,
			volume = 0.3 + 0.2 * w,
			speed = 0.38,
			rolloff = rolloff,
			eq = { low = 2, mid = -2, high = -10 },
			maxSec = fall,
		},
	}
end

-- The layers played when it lands.
function FellSound.Land(mass: number): { Layer }
	local w = FellSound.Weight(mass)
	local rolloff = 140 + 100 * w
	return {
		{
			name = "FellThud",
			id = FellSound.Boom,
			at = 0,
			volume = 0.45 + 0.25 * w,
			speed = 0.62 - 0.17 * w,
			rolloff = rolloff,
			eq = { low = 8, mid = -2, high = -12 },
			reverb = { decay = 1.4, wet = -8 },
			maxSec = 2.5,
		},
		{
			name = "FellSub",
			id = FellSound.Crack,
			at = 0.02,
			volume = 0.55 + 0.2 * w,
			speed = 0.5 - 0.15 * w,
			rolloff = rolloff,
			eq = { low = 10, mid = -6, high = -20 },
			maxSec = 1.2,
		},
	}
end

return FellSound
