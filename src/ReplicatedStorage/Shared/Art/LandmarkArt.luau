--!strict
-- LandmarkArt: the open country's landmarks, a little toward Lumber
-- Tycoon 2's look (phase 10, STY-03 and STY-04): brown boulders for the
-- clusters scattered over the grass. Pure (see Kit), so tools/preview
-- draws exactly what MapBuilder builds (scenes "landmarks" and "roads").
--
-- Every builder returns a Model built around the origin: ground at y = 0,
-- the front facing -Z. What players stand on or bump into collides; the
-- rest is Kit.decor, and parts under a stud cast no shadow.

local PropArt = require(script.Parent.PropArt)

local LandmarkArt = {}

-- Brown rock (STY-03): LT2's boulders are brown, not grey. Two tones, so a
-- field of clusters isn't one flat colour: a warm brown and a greyer umber.
LandmarkArt.ROCK_TONES = {
	{ Color3.fromRGB(132, 102, 78), Color3.fromRGB(116, 90, 70), Color3.fromRGB(148, 118, 90) },
	{ Color3.fromRGB(118, 100, 84), Color3.fromRGB(102, 88, 76), Color3.fromRGB(134, 116, 98) },
} :: { { Color3 } }
local MOSS = Color3.fromRGB(104, 146, 66)

-- One brown boulder `size` studs across (PropArt.Rock, as the lone
-- boulders: its three "Rock" blocks collide, its pebbles and moss are
-- looks only), in tone 1 or 2, with a mossy cap when `mossy`.
function LandmarkArt.BrownRock(size: number, seed: number, tone: number, mossy: boolean): Model
	local tones = LandmarkArt.ROCK_TONES
	local palette = tones[math.clamp(math.floor(tone), 1, #tones)]
	return PropArt.Rock(size, seed, palette, if mossy then MOSS else nil)
end

return LandmarkArt
