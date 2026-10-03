--!strict
-- EnvironmentData: how the world looks and feels at every hour, in every
-- biome and every weather (GAME_DESIGN §12, §13, §16). Pure data and
-- functions, so the client draws it, the tests check it, and tuning it is
-- editing this file:
--
--   * Lighting: keyframes over the day (dawn, midday, golden hour, dusk,
--     night), then per-biome and per-weather overrides on top. Blend()
--     turns (clock, biome, weather, intensity) into one LightingState that
--     LightingController eases toward.
--   * Daylight(clock): 0 at night, 1 by day, smooth in between (ambience,
--     critters, music).
--   * Decor: what grows around you per biome (AmbientLife scatters it per
--     64-stud cell), and DecorSpots(), the deterministic scatter itself.
--   * Critters: who is out and about (CritterPlan), by biome, hour,
--     weather and the grove's vitality (thriving groves come alive).
--   * NearestWater(x, z): where the river or lake is (water sounds, fish).
--
-- All the numbers are "tune by eye in Studio" starting points.

local BiomeData = require(script.Parent.BiomeData)
local Kit = require(script.Parent.Art.Kit)
local TerrainGen = require(script.Parent.World.TerrainGen)
local WorldLayout = require(script.Parent.World.WorldLayout)

local EnvironmentData = {}

local rgb = Color3.fromRGB

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

---------------------------------------------------------------------------
-- Lighting
---------------------------------------------------------------------------

-- Everything LightingController sets (besides the clock). Colours are
-- Color3s, the rest numbers; names say which instance they go to.
export type LightingState = {
	-- Lighting
	brightness: number,
	exposure: number, -- ExposureCompensation
	ambient: Color3, -- indoors / out of the sky's reach
	outdoorAmbient: Color3,
	colorShiftTop: Color3, -- tint of sunlit faces
	-- Atmosphere
	atmosphereDensity: number,
	atmosphereOffset: number,
	atmosphereColor: Color3,
	atmosphereDecay: Color3,
	atmosphereGlare: number,
	atmosphereHaze: number,
	-- ColorCorrection
	saturation: number,
	contrast: number,
	tint: Color3,
	-- SunRays
	sunRaysIntensity: number,
	sunRaysSpread: number,
	-- Bloom
	bloomIntensity: number,
	bloomSize: number,
	bloomThreshold: number,
	-- Clouds (under workspace.Terrain)
	cloudCover: number,
	cloudDensity: number,
	cloudColor: Color3,
	-- DepthOfField far blur (0 = off)
	dofFar: number,
}

EnvironmentData.NumberKeys = {
	"brightness",
	"exposure",
	"atmosphereDensity",
	"atmosphereOffset",
	"atmosphereGlare",
	"atmosphereHaze",
	"saturation",
	"contrast",
	"sunRaysIntensity",
	"sunRaysSpread",
	"bloomIntensity",
	"bloomSize",
	"bloomThreshold",
	"cloudCover",
	"cloudDensity",
	"dofFar",
}

EnvironmentData.ColorKeys = {
	"ambient",
	"outdoorAmbient",
	"colorShiftTop",
	"atmosphereColor",
	"atmosphereDecay",
	"tint",
	"cloudColor",
}

-- The legal range of each number (Roblox's own limits, or what still looks
-- sane); Blend clamps into these.
EnvironmentData.Ranges = {
	brightness = { 0, 10 },
	exposure = { -3, 3 },
	atmosphereDensity = { 0, 1 },
	atmosphereOffset = { 0, 1 },
	atmosphereGlare = { 0, 10 },
	atmosphereHaze = { 0, 10 },
	saturation = { -1, 1 },
	contrast = { -1, 1 },
	sunRaysIntensity = { 0, 1 },
	sunRaysSpread = { 0, 1 },
	bloomIntensity = { 0, 1.5 },
	bloomSize = { 0, 56 },
	bloomThreshold = { 0, 4 },
	cloudCover = { 0, 1 },
	cloudDensity = { 0, 1 },
	dofFar = { 0, 1 },
} :: { [string]: { number } }

-- A keyframe: the full state at an in-game hour.
export type Keyframe = { hour: number, name: string, state: LightingState }

local function key(
	hour: number,
	name: string,
	s: {
		brightness: number,
		exposure: number,
		ambient: Color3,
		outdoor: Color3,
		shift: Color3,
		density: number,
		offset: number,
		color: Color3,
		decay: Color3,
		glare: number,
		haze: number,
		saturation: number,
		tint: Color3,
		rays: number,
		spread: number,
		bloom: number,
		threshold: number,
		clouds: Color3,
	}
): Keyframe
	return {
		hour = hour,
		name = name,
		state = {
			brightness = s.brightness,
			exposure = s.exposure,
			ambient = s.ambient,
			outdoorAmbient = s.outdoor,
			colorShiftTop = s.shift,
			atmosphereDensity = s.density,
			atmosphereOffset = s.offset,
			atmosphereColor = s.color,
			atmosphereDecay = s.decay,
			atmosphereGlare = s.glare,
			atmosphereHaze = s.haze,
			saturation = s.saturation,
			contrast = 0.05,
			tint = s.tint,
			sunRaysIntensity = s.rays,
			sunRaysSpread = s.spread,
			bloomIntensity = s.bloom,
			bloomSize = 24,
			bloomThreshold = s.threshold,
			cloudCover = 0.5,
			cloudDensity = 0.25,
			cloudColor = s.clouds,
			dofFar = 0,
		},
	}
end

-- Cozy days, golden evenings, nights dark enough that lanterns and lit
-- windows matter. The night holds from 22:00 to 04:00. WLD-06 lifted it
-- (from brightness 0.6, ambient 26,28,46, outdoor 55,65,105) so a trunk
-- still reads at 30 studs without a lantern, in the Hills too; Gloam
-- Hollow's override keeps it the darkest place, and never black.
local NIGHT = {
	brightness = 0.8,
	exposure = -0.2,
	ambient = rgb(34, 36, 58),
	outdoor = rgb(72, 82, 125),
	shift = rgb(30, 40, 80),
	density = 0.36,
	offset = 0.1,
	color = rgb(90, 100, 140),
	decay = rgb(40, 45, 80),
	glare = 0,
	haze = 0.5,
	saturation = -0.05,
	tint = rgb(210, 220, 255),
	rays = 0,
	spread = 0.4,
	bloom = 0.75,
	threshold = 1.2,
	clouds = rgb(120, 130, 165),
}

EnvironmentData.Keyframes = {
	key(4, "Night", NIGHT),
	key(6, "Dawn", {
		brightness = 1.8,
		exposure = 0,
		ambient = rgb(62, 54, 64),
		outdoor = rgb(150, 125, 140),
		shift = rgb(150, 110, 90),
		density = 0.34,
		offset = 0.15,
		color = rgb(255, 195, 165),
		decay = rgb(120, 95, 115),
		glare = 0.6,
		haze = 2,
		saturation = 0.1,
		tint = rgb(255, 240, 230),
		rays = 0.1,
		spread = 0.6,
		bloom = 0.6,
		threshold = 1.6,
		clouds = rgb(255, 228, 218),
	}),
	key(13, "Midday", {
		brightness = 2.6,
		exposure = 0,
		ambient = rgb(70, 70, 76),
		outdoor = rgb(135, 135, 140),
		shift = rgb(40, 38, 34),
		density = 0.28,
		offset = 0.2,
		color = rgb(200, 212, 222),
		decay = rgb(106, 122, 142),
		glare = 0.2,
		haze = 1,
		saturation = 0.12,
		tint = rgb(255, 255, 255),
		rays = 0.05,
		spread = 0.5,
		bloom = 0.6,
		threshold = 1.6,
		clouds = rgb(255, 255, 255),
	}),
	key(17.5, "Golden", {
		brightness = 2.2,
		exposure = 0,
		ambient = rgb(76, 62, 56),
		outdoor = rgb(160, 130, 110),
		shift = rgb(170, 110, 60),
		density = 0.32,
		offset = 0.15,
		color = rgb(255, 200, 150),
		decay = rgb(150, 100, 90),
		glare = 1.2,
		haze = 2.2,
		saturation = 0.15,
		tint = rgb(255, 235, 215),
		rays = 0.12,
		spread = 0.7,
		bloom = 0.6,
		threshold = 1.6,
		clouds = rgb(255, 214, 180),
	}),
	key(19.25, "Dusk", {
		brightness = 1.1,
		exposure = -0.1,
		ambient = rgb(50, 44, 62),
		outdoor = rgb(112, 96, 130),
		shift = rgb(90, 60, 90),
		density = 0.34,
		offset = 0.12,
		color = rgb(210, 150, 170),
		decay = rgb(85, 65, 110),
		glare = 0.4,
		haze = 1.6,
		saturation = 0.06,
		tint = rgb(240, 225, 250),
		rays = 0.03,
		spread = 0.5,
		bloom = 0.7,
		threshold = 1.4,
		clouds = rgb(205, 170, 200),
	}),
	key(22, "Night", NIGHT),
} :: { Keyframe }

-- An override nudges the state: numbers multiplied (mul), added (add) or
-- pulled toward a value (set); colours multiplied channel by channel
-- (tint, so a night stays dark) or pulled toward a colour (paint). It is
-- applied with a weight: 1 for the biome you're in, the weather's
-- intensity for weather.
export type Override = {
	mul: { [string]: number }?,
	add: { [string]: number }?,
	set: { [string]: number }?,
	tint: { [string]: Color3 }?,
	paint: { [string]: Color3 }?,
}

local function scale(r: number, g: number, b: number): Color3
	return Color3.new(r, g, b)
end

EnvironmentData.BiomeOverrides = {
	-- Warm greens and honey light.
	starter = { add = { saturation = 0.03 } },
	hills = { add = { saturation = 0.02, contrast = 0.02 } },
	-- Cool and bright: pale blues, white drifts, cool rim light, and a cold,
	-- frosty white-blue haze (phase 12). Its air is a floor more than an
	-- extra (x0.7 then +0.17): a clear midday's 0.28 comes out at 0.37, but
	-- a night that is already thick only gets a little thicker, so a clear
	-- night here stays under the Fog weather's 0.55.
	snow = {
		mul = { brightness = 1.12, atmosphereDensity = 0.7 },
		add = { exposure = 0.1, saturation = -0.05, atmosphereDensity = 0.17, atmosphereHaze = 1 },
		tint = {
			outdoorAmbient = scale(0.95, 1.0, 1.12),
			atmosphereColor = scale(1.05, 1.08, 1.12),
			atmosphereDecay = scale(1.1, 1.15, 1.22),
			colorShiftTop = scale(0.8, 0.9, 1.1),
		},
		paint = { tint = rgb(235, 245, 255) },
	},
	-- Charred rock, ember-orange glow, ash in the air, and its signature: a
	-- thick red fog (phase 12). Its air is set, not added, so it is the
	-- same at any hour: 0.55 (the Fog weather's thickness: a tree still
	-- shows 60-100 studs off) and hazy, red-orange toward the sun and deep
	-- red away from it (tints, so its nights stay dark). The midday tint
	-- comes out at (255, 215, 190), the air (255, 140, 100) and the decay
	-- (201, 61, 33).
	volcano = {
		set = { atmosphereDensity = 0.55, atmosphereHaze = 3 },
		add = { saturation = 0.02, bloomIntensity = 0.1 },
		tint = {
			tint = scale(1, 0.843, 0.745),
			atmosphereDecay = scale(1.9, 0.5, 0.23),
			atmosphereColor = scale(1.3, 0.66, 0.45),
			outdoorAmbient = scale(1.15, 0.9, 0.8),
			cloudColor = scale(0.75, 0.6, 0.55),
		},
	},
	-- Deep purples and teal glow, darker than anywhere, and a low violet
	-- swamp mist hanging in the hollow at any hour (phase 12): its air is
	-- set to 0.53 (thicker than any clear night out in the country, under
	-- the Fog weather's 0.55), hazy, tinted violet.
	grove = {
		mul = { brightness = 0.6 },
		set = { atmosphereDensity = 0.53 },
		add = { exposure = -0.15, atmosphereHaze = 1.2, bloomIntensity = 0.2 },
		tint = {
			tint = scale(0.745, 0.706, 1),
			outdoorAmbient = scale(0.75, 0.65, 1),
			atmosphereColor = scale(0.8, 0.66, 1.15),
			atmosphereDecay = scale(0.78, 0.56, 1.25),
		},
	},
	-- White-gold light above the clouds, the whole map spread out below.
	-- Bloom only +0.1 (WLD-17; it was +0.3, which melted the Lumenwood's
	-- glowing crowns into white blobs).
	sky = {
		set = { atmosphereDensity = 0.2, atmosphereOffset = 0.4, dofFar = 0.08 },
		add = { saturation = 0.2, bloomIntensity = 0.1, brightness = 0.3, atmosphereGlare = 0.5 },
	},
} :: { [string]: Override }

EnvironmentData.WeatherOverrides = {
	Clear = {},
	Cloudy = {
		mul = { brightness = 0.85, sunRaysIntensity = 0.4, atmosphereGlare = 0.5 },
		add = { saturation = -0.03, atmosphereDensity = 0.03 },
		set = { cloudCover = 0.78, cloudDensity = 0.4 },
	},
	Rain = {
		mul = { brightness = 0.7, sunRaysIntensity = 0, atmosphereGlare = 0.2 },
		add = { atmosphereDensity = 0.1, saturation = -0.1, atmosphereHaze = 0.8, exposure = -0.05 },
		set = { cloudCover = 0.88, cloudDensity = 0.55 },
		tint = {
			cloudColor = scale(0.72, 0.74, 0.78),
			atmosphereColor = scale(0.85, 0.88, 0.92),
			outdoorAmbient = scale(0.88, 0.9, 0.95),
		},
	},
	Storm = {
		mul = { brightness = 0.5, sunRaysIntensity = 0, atmosphereGlare = 0 },
		add = { atmosphereDensity = 0.15, saturation = -0.15, atmosphereHaze = 1.2, exposure = -0.1, contrast = 0.05 },
		set = { cloudCover = 0.96, cloudDensity = 0.8 },
		tint = {
			cloudColor = scale(0.5, 0.52, 0.58),
			atmosphereColor = scale(0.65, 0.68, 0.75),
			atmosphereDecay = scale(0.6, 0.62, 0.7),
			outdoorAmbient = scale(0.75, 0.78, 0.86),
		},
	},
	Fog = {
		mul = { atmosphereGlare = 0.3, sunRaysIntensity = 0.3 },
		add = { saturation = -0.05 },
		set = { atmosphereDensity = 0.55, atmosphereOffset = 0.05, atmosphereHaze = 3, cloudCover = 0.6 },
	},
	Snow = {
		mul = { brightness = 0.9, sunRaysIntensity = 0.2 },
		add = { atmosphereDensity = 0.12, atmosphereHaze = 1, saturation = -0.05 },
		set = { cloudCover = 0.85, cloudDensity = 0.45 },
		tint = { atmosphereColor = scale(1.05, 1.05, 1.08) },
	},
	Blizzard = {
		mul = { brightness = 0.65, sunRaysIntensity = 0, atmosphereGlare = 0 },
		add = { atmosphereDensity = 0.3, saturation = -0.12 },
		set = { atmosphereOffset = 0.03, atmosphereHaze = 4, cloudCover = 0.95, cloudDensity = 0.7 },
		tint = { atmosphereColor = scale(1.1, 1.1, 1.15), cloudColor = scale(0.8, 0.82, 0.86) },
	},
	Ashfall = {
		mul = { brightness = 0.55, sunRaysIntensity = 0 },
		add = { atmosphereDensity = 0.25, atmosphereHaze = 2, saturation = -0.1 },
		set = { cloudCover = 0.9, cloudDensity = 0.65 },
		tint = {
			atmosphereColor = scale(0.75, 0.6, 0.55),
			atmosphereDecay = scale(0.7, 0.45, 0.4),
			tint = scale(1, 0.9, 0.85),
			cloudColor = scale(0.45, 0.38, 0.36),
		},
	},
	Wind = {
		add = { atmosphereHaze = 0.3 },
		set = { cloudCover = 0.62, cloudDensity = 0.3 },
	},
} :: { [string]: Override }

-- 0 at night, 1 by day, easing through dawn (5-7) and dusk (17.5-19.5).
function EnvironmentData.Daylight(clockTime: number): number
	local h = clockTime % 24
	if h < 12 then
		return smoothstep((h - 5) / 2)
	end
	return 1 - smoothstep((h - 17.5) / 2)
end

-- The night fog (STY-05; phase 12 made it a real fog), the classic
-- lumber-game way: the air thickens late in the evening (from 22:00, full
-- by 23:00), holds through the night and lifts through the morning (from
-- 06:30, clear by 09:30). MistWeight(clock) is how much of Mist.override
-- Blend applies at that hour: after the hour's own light, before the biome
-- and the weather (so the Fog weather and a biome's own air still set
-- theirs). Its colour, a cool grey-blue (Mist.colour), comes with the dark
-- (MistColourWeight), so dawn lights the morning fog its own colour. Only
-- the air: the night's light (brightness, ambient, WLD-06) is what it was,
-- so a trunk still reads at 30 studs. Never on the isles (above the
-- clouds), and never by day: 09:30 to 22:00 looks exactly as it did, so a
-- phone's horizon stays clear.
EnvironmentData.Mist = {
	thickFrom = 22,
	thick = 23,
	liftFrom = 6.5,
	clear = 9.5,
	-- A clear night out in the country is 0.52 thick and 2.0 hazy now (the
	-- Fog weather is 0.55 and 3); STY-05's mist added 0.07 and 0.6.
	override = { add = { atmosphereDensity = 0.16, atmosphereHaze = 1.5 } } :: Override,
	-- As dark as the night's own blue (90, 100, 140 and 40, 45, 80), greyer.
	colour = {
		paint = { atmosphereColor = rgb(94, 102, 124), atmosphereDecay = rgb(44, 49, 66) },
	} :: Override,
}

-- 0..1: how thick the night fog is at `clockTime` (0..24).
function EnvironmentData.MistWeight(clockTime: number): number
	local h = clockTime % 24
	local m = EnvironmentData.Mist
	if h >= m.thickFrom then
		return smoothstep((h - m.thickFrom) / (m.thick - m.thickFrom))
	elseif h < m.liftFrom then
		return 1
	end
	return 1 - smoothstep((h - m.liftFrom) / (m.clear - m.liftFrom))
end

-- 0..1: how much of the night fog's colour shows at `clockTime`: the fog's
-- own weight while it is dark, fading out as the day comes (05:00-07:00),
-- so the morning fog (thick until 06:30) takes dawn's colour.
function EnvironmentData.MistColourWeight(clockTime: number): number
	return EnvironmentData.MistWeight(clockTime) * (1 - EnvironmentData.Daylight(clockTime))
end

local NUMBER_SET: { [string]: boolean } = {}
for _, k in ipairs(EnvironmentData.NumberKeys) do
	NUMBER_SET[k] = true
end
local COLOR_SET: { [string]: boolean } = {}
for _, k in ipairs(EnvironmentData.ColorKeys) do
	COLOR_SET[k] = true
end

-- Every key an override names must exist (a typo would silently do nothing).
local function checkOverride(name: string, o: Override)
	local function numbers(part: { [string]: number }?)
		for k in pairs(part or {}) do
			assert(NUMBER_SET[k], string.format("[EnvironmentData] %s: unknown number %q", name, k))
		end
	end
	local function colors(part: { [string]: Color3 }?)
		for k in pairs(part or {}) do
			assert(COLOR_SET[k], string.format("[EnvironmentData] %s: unknown colour %q", name, k))
		end
	end
	numbers(o.mul)
	numbers(o.add)
	numbers(o.set)
	colors(o.tint)
	colors(o.paint)
end
for name, o in pairs(EnvironmentData.BiomeOverrides) do
	checkOverride(name, o)
end
for name, o in pairs(EnvironmentData.WeatherOverrides) do
	checkOverride(name, o)
end
checkOverride("Mist", EnvironmentData.Mist.override)
checkOverride("Mist colour", EnvironmentData.Mist.colour)

local function copy(s: LightingState): LightingState
	return table.clone(s)
end

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- The state between a and b (t = 0 gives a, 1 gives b).
function EnvironmentData.Lerp(a: LightingState, b: LightingState, t: number): LightingState
	local out = copy(a) :: any
	local fa, fb = a :: any, b :: any
	for _, k in ipairs(EnvironmentData.NumberKeys) do
		out[k] = lerpNumber(fa[k], fb[k], t)
	end
	for _, k in ipairs(EnvironmentData.ColorKeys) do
		out[k] = (fa[k] :: Color3):Lerp(fb[k], t)
	end
	return out :: LightingState
end

local function clampColor(c: Color3): Color3
	return Color3.new(math.clamp(c.R, 0, 1), math.clamp(c.G, 0, 1), math.clamp(c.B, 0, 1))
end

-- Applies an override with weight w (0 = no change) to s, in place.
function EnvironmentData.Apply(s: LightingState, o: Override, w: number)
	if w <= 0 then
		return
	end
	w = math.min(w, 1)
	local f = s :: any
	local none: { [string]: number } = {}
	local noColors: { [string]: Color3 } = {}
	for k, m in pairs(o.mul or none) do
		f[k] *= 1 + (m - 1) * w
	end
	for k, a in pairs(o.add or none) do
		f[k] += a * w
	end
	for k, v in pairs(o.set or none) do
		f[k] = lerpNumber(f[k], v, w)
	end
	local white = Color3.new(1, 1, 1)
	for k, c in pairs(o.tint or noColors) do
		local m = white:Lerp(c, w)
		local base = f[k] :: Color3
		f[k] = Color3.new(base.R * m.R, base.G * m.G, base.B * m.B)
	end
	for k, c in pairs(o.paint or noColors) do
		f[k] = (f[k] :: Color3):Lerp(c, w)
	end
end

-- Keeps every value inside its legal range, in place.
function EnvironmentData.Clamp(s: LightingState)
	local f = s :: any
	for _, k in ipairs(EnvironmentData.NumberKeys) do
		local r = EnvironmentData.Ranges[k]
		f[k] = math.clamp(f[k], r[1], r[2])
	end
	for _, k in ipairs(EnvironmentData.ColorKeys) do
		f[k] = clampColor(f[k])
	end
end

-- The day's own light at `clockTime` (0..24), before biome and weather.
function EnvironmentData.TimeOfDay(clockTime: number): LightingState
	local frames = EnvironmentData.Keyframes
	local h = clockTime % 24
	-- Find the keyframes either side, wrapping past midnight.
	local n = #frames
	local prev, nextFrame = frames[n], frames[1]
	local prevHour, nextHour = frames[n].hour - 24, frames[1].hour
	for i = 1, n do
		local f = frames[i]
		if f.hour <= h then
			prev, prevHour = f, f.hour
			local following = frames[i + 1]
			if following then
				nextFrame, nextHour = following, following.hour
			else
				nextFrame, nextHour = frames[1], frames[1].hour + 24
			end
		end
	end
	local span = nextHour - prevHour
	local t = if span > 0 then smoothstep((h - prevHour) / span) else 0
	return EnvironmentData.Lerp(prev.state, nextFrame.state, t)
end

-- The full picture: the hour's light and its night fog (and the fog's
-- colour while it's dark), then the biome you're in ("" or nil = open
-- country), then the weather at `intensity` (0..1).
function EnvironmentData.Blend(clockTime: number, biomeId: string?, weather: string?, intensity: number?): LightingState
	local s = EnvironmentData.TimeOfDay(clockTime)
	if biomeId ~= "sky" then
		local mist = EnvironmentData.Mist
		EnvironmentData.Apply(s, mist.override, EnvironmentData.MistWeight(clockTime))
		EnvironmentData.Apply(s, mist.colour, EnvironmentData.MistColourWeight(clockTime))
	end
	local biome = if biomeId then EnvironmentData.BiomeOverrides[biomeId] else nil
	if biome then
		EnvironmentData.Apply(s, biome, 1)
	end
	local w = if weather then EnvironmentData.WeatherOverrides[weather] else nil
	if w then
		EnvironmentData.Apply(s, w, math.clamp(intensity or 1, 0, 1))
	end
	EnvironmentData.Clamp(s)
	return s
end

---------------------------------------------------------------------------
-- Write throttle (WLD-18): how often LightingController touches Lighting
---------------------------------------------------------------------------

-- LightingController eases and writes the look 10 times a second (the
-- frames between add their dt up), and writes a property only when its
-- value has moved past one of these since the last write. The lightning
-- flash is the one per-frame write (ExposureCompensation only).
EnvironmentData.WriteEvery = 0.1 -- seconds between eased writes
EnvironmentData.NumberEpsilon = 1e-3
EnvironmentData.ColorEpsilon = 1 / 255 -- one 8-bit step in any channel
-- The sun is written every frame it moves (long shadows at dusk and dawn
-- step visibly at anything coarser); this only skips frames where the
-- clock stands still. 1e-4 in-game hours is 5 ms of a 20-minute day.
EnvironmentData.ClockEpsilon = 1e-4

-- Adds a frame's `dt` to the time `pending` since the last write. Returns
-- whether to write now, the time to ease by (all of it, so the ease is
-- the same at any frame rate), and what is left pending.
function EnvironmentData.WriteTick(pending: number, dt: number): (boolean, number, number)
	local total = pending + math.max(dt, 0)
	-- A hair under WriteEvery, so six 1/60 s frames (0.0999...) count.
	if total >= EnvironmentData.WriteEvery - 1e-6 then
		return true, total, 0
	end
	return false, 0, total
end

-- Whether a number property should be rewritten: never written yet, or
-- moved more than NumberEpsilon (or `epsilon`) from what was last written.
function EnvironmentData.NumberMoved(last: number?, value: number, epsilon: number?): boolean
	if last == nil then
		return true
	end
	return math.abs(value - last) > (epsilon or EnvironmentData.NumberEpsilon)
end

-- Whether a Color3 property should be rewritten: never written yet, or a
-- channel moved by at least one 8-bit step (ColorEpsilon).
function EnvironmentData.ColorMoved(last: Color3?, value: Color3): boolean
	if last == nil then
		return true
	end
	-- A hair under one step, so a full 1/255 step (with float error) counts.
	local eps = EnvironmentData.ColorEpsilon - 1e-6
	return math.abs(value.R - last.R) >= eps or math.abs(value.G - last.G) >= eps or math.abs(value.B - last.B) >= eps
end

-- Whether Lighting.ClockTime should be rewritten: moved more than
-- ClockEpsilon around the 24-hour dial (23.999 to 0.001 is 0.002 h).
function EnvironmentData.ClockMoved(last: number?, value: number): boolean
	if last == nil then
		return true
	end
	local d = math.abs(value - last) % 24
	return math.min(d, 24 - d) > EnvironmentData.ClockEpsilon
end

---------------------------------------------------------------------------
-- Grove vitality (GAME_DESIGN §16): what a thriving grove adds
---------------------------------------------------------------------------

EnvironmentData.DefaultVitality = 60

-- "Thinning" | "Healthy" | "Thriving" | "OldGrowth"
function EnvironmentData.VitalityTier(v: number): string
	if v >= 90 then
		return "OldGrowth"
	elseif v >= 75 then
		return "Thriving"
	elseif v >= 35 then
		return "Healthy"
	end
	return "Thinning"
end

-- How much more life a grove of this vitality shows (1 = normal).
EnvironmentData.TierLife = { Thinning = 0.5, Healthy = 1, Thriving = 1.6, OldGrowth = 2 } :: { [string]: number }

function EnvironmentData.LifeFactor(v: number): number
	return EnvironmentData.TierLife[EnvironmentData.VitalityTier(v)]
end

---------------------------------------------------------------------------
-- Ground decoration (AmbientLife scatters it around you)
---------------------------------------------------------------------------

-- One kind of decoration in a biome. `kind` is a PropArt builder name;
-- AmbientLife knows how to call each. `lush` (0..1) is how strongly its
-- numbers follow the grove's vitality (flowers 1, rocks 0). `enabled =
-- false` marks a slot waiting for its PropArt model (the nature workstream
-- is adding them); AmbientLife skips those until someone wires them up.
export type DecorKind = {
	kind: string,
	weight: number,
	lush: number?,
	variants: number, -- how many looks are built and pooled
	palette: string?, -- EnvironmentData.DecorPalettes key
	size: { number }?, -- min, max (Rock, Bush, Crystal, SnowPile, LavaRock)
	glowing: boolean?, -- Mushroom
	sink: number?, -- studs pushed into the ground (rocks)
	enabled: boolean?,
	-- Ground cover: this row belongs to the cover layer (DecorCoverSpots, a
	-- second scatter with its own rng), never to DecorSpots. Cover rows come
	-- last in their table, so the first layer's rows keep their indices.
	cover: boolean?,
}

EnvironmentData.DecorPalettes = {
	meadowFlowers = { rgb(250, 214, 80), rgb(255, 255, 245), rgb(240, 140, 180), rgb(170, 130, 230) },
	forestFlowers = { rgb(255, 236, 120), rgb(255, 250, 240), rgb(250, 160, 190), rgb(255, 170, 90) },
	hillFlowers = { rgb(120, 150, 240), rgb(170, 120, 220), rgb(255, 220, 90), rgb(255, 255, 250) },
	groveFlowers = { rgb(150, 120, 240), rgb(90, 230, 210), rgb(200, 170, 255) },
	greens = { rgb(84, 140, 60), rgb(104, 160, 70), rgb(70, 120, 52) },
	hillGreens = { rgb(64, 120, 52), rgb(84, 136, 60), rgb(110, 150, 70) },
	frostGreens = { rgb(120, 160, 160), rgb(150, 190, 200), rgb(220, 235, 245) },
	groveGreens = { rgb(70, 50, 110), rgb(90, 64, 140), rgb(52, 90, 110) },
	stone = { rgb(140, 134, 126), rgb(120, 116, 110), rgb(158, 150, 140) },
	snowStone = { rgb(232, 238, 245), rgb(200, 208, 218), rgb(150, 150, 156) },
	darkStone = { rgb(58, 52, 50), rgb(44, 40, 40), rgb(72, 64, 60) },
	ice = { rgb(170, 222, 245) },
	ember = { rgb(255, 120, 40) },
	amethyst = { rgb(170, 120, 255) },
} :: { [string]: { Color3 } }

type DecorExtra = {
	lush: number?,
	variants: number?,
	palette: string?,
	size: { number }?,
	glowing: boolean?,
	sink: number?,
	enabled: boolean?,
	cover: boolean?,
}

local function decor(kind: string, weight: number, extra: DecorExtra?): DecorKind
	local e: DecorExtra = extra or {}
	return {
		kind = kind,
		weight = weight,
		lush = e.lush,
		variants = e.variants or 4,
		palette = e.palette,
		size = e.size,
		glowing = e.glowing,
		sink = e.sink,
		enabled = e.enabled,
		cover = e.cover,
	}
end

-- A ground-cover row (see DecorKind.cover).
local function cover(kind: string, weight: number, extra: DecorExtra?): DecorKind
	local row = decor(kind, weight, extra)
	row.cover = true
	return row
end

-- What grows where ("meadow" = the open country between biomes, "shore"
-- = the water's edge anywhere). Each kind has a builder in AmbientLife; a
-- row with `enabled = false` is skipped.
EnvironmentData.Decor = {
	meadow = {
		decor("Flowers", 5, { lush = 1, palette = "meadowFlowers" }),
		decor("Bush", 2, { lush = 0.4, palette = "greens", size = { 2, 3.6 } }),
		decor("Rock", 1.5, { palette = "stone", size = { 0.9, 2.2 }, sink = 0.25 }),
		decor("Mushroom", 0.6, { lush = 0.5 }),
		decor("GrassTuft", 6, { lush = 0.3 }),
		decor("Pebbles", 2),
		decor("BerryBush", 1, { lush = 1 }),
		-- Ground cover (DecorCoverSpots): the open country was the barest
		-- ground on the map, so it gets the most.
		cover("GroundCover", 5, { lush = 0.3, palette = "meadowFlowers" }),
		cover("Wildflowers", 3, { lush = 1, palette = "meadowFlowers" }),
		cover("LowBush", 1.5, { lush = 0.4, palette = "greens" }),
		cover("Pebbles", 1),
	},
	starter = {
		decor("Flowers", 4, { lush = 1, palette = "forestFlowers" }),
		decor("Bush", 3, { lush = 0.5, palette = "greens", size = { 2, 4 } }),
		decor("Mushroom", 1.5, { lush = 0.7 }),
		decor("Rock", 1, { palette = "stone", size = { 0.8, 2 }, sink = 0.25 }),
		decor("Fern", 4, { lush = 0.6 }),
		decor("GrassTuft", 4, { lush = 0.3 }),
		decor("FallenLog", 0.6),
		decor("Stump", 0.6),
		decor("BerryBush", 1, { lush = 1 }),
		cover("FernClump", 4, { lush = 0.6 }),
		cover("MushroomCluster", 1.5, { lush = 0.7 }),
		cover("GroundCover", 2, { lush = 0.3, palette = "forestFlowers" }),
		cover("Wildflowers", 1.5, { lush = 1, palette = "forestFlowers" }),
	},
	hills = {
		decor("Bush", 3, { lush = 0.4, palette = "hillGreens", size = { 2.2, 4.2 } }),
		decor("Rock", 2.5, { palette = "stone", size = { 1, 2.8 }, sink = 0.3 }),
		decor("Flowers", 3, { lush = 1, palette = "hillFlowers" }),
		decor("Mushroom", 1, { lush = 0.6 }),
		decor("Fern", 3, { lush = 0.6 }),
		decor("GrassTuft", 4, { lush = 0.3 }),
		decor("FallenLog", 0.8),
		decor("Stump", 0.6),
		cover("FernClump", 2.5, { lush = 0.6 }),
		cover("MushroomCluster", 1, { lush = 0.6 }),
		cover("GroundCover", 2.5, { lush = 0.3, palette = "hillFlowers" }),
		cover("Wildflowers", 1.5, { lush = 1, palette = "hillFlowers" }),
		cover("LowBush", 1.5, { lush = 0.4, palette = "hillGreens" }),
	},
	snow = {
		decor("Rock", 3, { palette = "snowStone", size = { 1, 2.6 }, sink = 0.3 }),
		decor("Crystal", 1.5, { palette = "ice", size = { 1, 2.2 } }),
		decor("Bush", 1.5, { lush = 0.5, palette = "frostGreens", size = { 1.8, 3 } }),
		decor("SnowPile", 4, { size = { 1.4, 3 } }),
		decor("DeadBranch", 1),
	},
	volcano = {
		decor("Rock", 4, { palette = "darkStone", size = { 1, 3 }, sink = 0.3 }),
		decor("Crystal", 1, { palette = "ember", size = { 0.8, 1.6 } }),
		decor("LavaRock", 3, { size = { 0.9, 2 } }),
		decor("DeadBranch", 1.5),
	},
	grove = {
		decor("Mushroom", 4, { lush = 0.8, glowing = true }),
		decor("Flowers", 2, { lush = 1, palette = "groveFlowers" }),
		decor("Bush", 2, { lush = 0.4, palette = "groveGreens", size = { 2, 3.4 } }),
		decor("Crystal", 1, { palette = "amethyst", size = { 0.8, 1.8 } }),
		decor("Fern", 3, { lush = 0.6 }),
		decor("DeadBranch", 1),
		cover("FernClump", 3, { lush = 0.6 }),
		cover("LowBush", 1.5, { lush = 0.4, palette = "groveGreens" }),
		cover("Wildflowers", 1, { lush = 1, palette = "groveFlowers" }),
	},
	-- By the water's edge, any biome: reeds and cattails on the bank, lily
	-- pads on still water (DecorSpots picks this table near the water).
	shore = {
		decor("Reeds", 4),
		decor("Cattails", 2),
		decor("LilyPad", 2),
	},
} :: { [string]: { DecorKind } }

-- Candidate spots per 64-stud cell, before vitality and the ground rules.
EnvironmentData.DecorCell = 64
EnvironmentData.DecorCandidates = { meadow = 18, starter = 26, hills = 22, snow = 14, volcano = 12, grove = 22 } :: {
	[string]: number,
}
EnvironmentData.DecorAcceptance = 0.6 -- share of candidates kept at Healthy vitality
-- Ground-cover candidates per cell (DecorCoverSpots; the biomes with cover
-- rows). AmbientLife loads this layer on the high quality tier only.
EnvironmentData.DecorCoverCandidates = { meadow = 12, starter = 8, hills = 9, grove = 6 } :: {
	[string]: number,
}

export type DecorSpot = {
	biome: string, -- the Decor table it came from ("meadow" for open country)
	index: number, -- row in that table
	kind: string,
	variant: number, -- 1..variants: which pooled look
	x: number,
	y: number,
	z: number,
	yaw: number,
}

-- Which Decor table applies at (x, z) ("meadow" between biomes; nil where
-- nothing grows: the isles' biome only exists high up).
function EnvironmentData.DecorBiomeAt(x: number, z: number): string
	local def = BiomeData.At(x, z)
	local id = if def then def.id else "meadow"
	if EnvironmentData.Decor[id] == nil then
		return "meadow"
	end
	return id
end

local SKYROOT_CLEAR = 95 -- the giant trunk, its roots and the gondola station
local skyArea = (function()
	local def = BiomeData.Get("sky")
	return if def then def.area else nil
end)()

-- True where nothing should be scattered: buildings, roads, water, the
-- Skyroot's foot, the volcano's cone, high mountains.
function EnvironmentData.DecorBlocked(x: number, z: number): boolean
	if WorldLayout.FlatWeight(x, z) > 0 then
		return true
	end
	if TerrainGen.RoadClearance(x, z) < 2.5 then
		return true
	end
	if skyArea then
		local dx, dz = x - skyArea.x, z - skyArea.z
		if dx * dx + dz * dz < SKYROOT_CLEAR * SKYROOT_CLEAR then
			return true
		end
	end
	local cone = WorldLayout.VolcanoCone
	local cx, cz = x - cone.x, z - cone.z
	if cx * cx + cz * cz < (cone.radius * 0.55) ^ 2 then
		return true
	end
	if math.abs(x) > WorldLayout.WorldHalf - 20 or math.abs(z) > WorldLayout.WorldHalf - 20 then
		return true
	end
	return TerrainGen.WaterLevelAt(x, z) ~= nil
end

local SHORE_STUDS = 6 -- this close to the water counts as the bank

-- Whether a "shore" row suits the spot: lily pads only on the water,
-- everything else only on land. (Rows of other tables always fit.)
local function shoreFits(kind: string, shoreKind: string?): boolean
	if shoreKind == nil then
		return true
	end
	return (kind == "LilyPad") == (shoreKind == "water")
end

-- The cover layer's rng is salted past every first-layer seed in the world.
local COVER_SALT = 50000017

-- One layer of a cell's scatter. The first layer (`coverLayer` false) is
-- DecorSpots exactly as it always was: the same seed, the same six draws
-- per candidate, the same picks among the rows without `cover`. The cover
-- layer has its own seed and picks only among `cover` rows, and stays off
-- the water and its bank (the reeds' place).
local function scatter(
	cellX: number,
	cellZ: number,
	vitalityOf: (biomeId: string) -> number,
	coverLayer: boolean
): { DecorSpot }
	local size = EnvironmentData.DecorCell
	local out: { DecorSpot } = {}
	local seed = (cellX + 4096) * 8209 + (cellZ + 4096) + 11
	local rng = Kit.rng(if coverLayer then seed + COVER_SALT else seed)
	local cx, cz = (cellX + 0.5) * size, (cellZ + 0.5) * size
	local cellBiome = EnvironmentData.DecorBiomeAt(cx, cz)
	local candidates = if coverLayer
		then EnvironmentData.DecorCoverCandidates[cellBiome] or 0
		else EnvironmentData.DecorCandidates[cellBiome] or 10
	for _ = 1, candidates do
		-- Always draw the same numbers per candidate, so the rest of the
		-- cell doesn't reshuffle when one spot is rejected.
		local x = cellX * size + rng:next() * size
		local z = cellZ * size + rng:next() * size
		local kindRoll = rng:next()
		local keepRoll = rng:next()
		local variantRoll = rng:next()
		local yaw = rng:next() * math.pi * 2
		local biome = EnvironmentData.DecorBiomeAt(x, z)
		-- The water's edge: reeds and cattails on the bank, lily pads on
		-- still water (the lake and the pond, not the river).
		local water = TerrainGen.WaterLevelAt(x, z)
		local shoreKind: string? = nil
		local _, distance, waterKind = EnvironmentData.NearestWater(x, z)
		if water ~= nil then
			if waterKind == "river" or WorldLayout.FlatWeight(x, z) > 0 then
				continue -- open river water, or a pond in town
			end
			shoreKind = "water"
		elseif distance < SHORE_STUDS then
			shoreKind = "bank"
		end
		if shoreKind then
			if coverLayer then
				continue
			end
			biome = "shore"
		end
		local list = EnvironmentData.Decor[biome]
		local total = 0
		local last = 0 -- the fallback pick: this layer's last row
		for i, d in ipairs(list) do
			if (d.cover == true) == coverLayer then
				last = i
				if shoreFits(d.kind, shoreKind) then
					total += d.weight
				end
			end
		end
		if total <= 0 then
			continue -- no rows of this layer here (only the cover layer)
		end
		local roll = kindRoll * total
		local pickIndex = last
		for i, d in ipairs(list) do
			if (d.cover == true) == coverLayer and shoreFits(d.kind, shoreKind) then
				roll -= d.weight
				if roll < 0 then
					pickIndex = i
					break
				end
			end
		end
		local pick = list[pickIndex]
		if pick.enabled == false or not shoreFits(pick.kind, shoreKind) then
			continue
		end
		local life = if biome == "meadow" or biome == "shore"
			then EnvironmentData.LifeFactor(vitalityOf("starter"))
			else EnvironmentData.LifeFactor(vitalityOf(biome))
		local lush = pick.lush or 0
		local keep = EnvironmentData.DecorAcceptance * (1 + (life - 1) * lush)
		if keepRoll >= keep then
			continue
		end
		local y
		if shoreKind == "water" then
			y = water :: number -- floating on the surface
		else
			if EnvironmentData.DecorBlocked(x, z) then
				continue
			end
			y = TerrainGen.HeightAt(x, z)
			if y > 100 then
				continue -- mountain peaks stay bare
			end
		end
		table.insert(out, {
			biome = biome,
			index = pickIndex,
			kind = pick.kind,
			variant = math.min(pick.variants, 1 + math.floor(variantRoll * pick.variants)),
			x = x,
			y = if shoreKind == "water" then y else y - (pick.sink or 0.1),
			z = z,
			yaw = yaw,
		})
	end
	return out
end

-- The deterministic decoration of cell (cellX, cellZ): every player sees
-- the same meadow. `vitalityOf(biomeId)` gives each grove's vitality
-- (0..100); thriving groves grow more flowers. Trees aren't avoided here
-- (they come and go); AmbientLife skips spots too close to one.
function EnvironmentData.DecorSpots(
	cellX: number,
	cellZ: number,
	vitalityOf: (biomeId: string) -> number
): { DecorSpot }
	return scatter(cellX, cellZ, vitalityOf, false)
end

-- The cell's ground cover: grass patches, wildflowers, low bushes, fern
-- clumps and mushroom clusters (the `cover` rows) on top of DecorSpots,
-- from a second rng, so adding it moved nothing DecorSpots places. Never
-- on the water or its bank. The same spot shape; `index` is the row in
-- Decor[biome], as for DecorSpots.
function EnvironmentData.DecorCoverSpots(
	cellX: number,
	cellZ: number,
	vitalityOf: (biomeId: string) -> number
): { DecorSpot }
	return scatter(cellX, cellZ, vitalityOf, true)
end

---------------------------------------------------------------------------
-- Critters (AmbientLife)
---------------------------------------------------------------------------

export type CritterKind =
	"Flock"
	| "PerchedBird"
	| "Butterfly"
	| "Fireflies"
	| "Rabbit"
	| "Deer"
	| "Duck"
	| "Fish"
	| "Wisp"
	| "EmberSprite"

-- How many animated models each critter is (the flock is several birds).
EnvironmentData.CritterCost = {
	Flock = 5,
	PerchedBird = 1,
	Butterfly = 1,
	Fireflies = 1,
	Rabbit = 1,
	Deer = 1,
	Duck = 1,
	Fish = 1,
	Wisp = 1,
	EmberSprite = 1,
} :: { [string]: number }

EnvironmentData.MaxCritters = 16 -- animated models near the player, all kinds together

export type CritterContext = {
	biomeId: string, -- "" for open country
	daylight: number, -- EnvironmentData.Daylight
	weather: string, -- after WeatherSchedule.ForBiome
	intensity: number,
	vitality: number, -- the biome's (open country uses the Starter Forest's)
	nearPond: boolean, -- the starter pond is close
	nearWater: boolean, -- a river or lake is close
}

export type CritterWant = { kind: CritterKind, count: number }

local LEAFY: { [string]: boolean } = { [""] = true, starter = true, hills = true }

-- Who is out right now, most special first (AmbientLife fills up to
-- MaxCritters in this order). Thriving groves bring more butterflies,
-- deer and fireflies; rain sends the butterflies home; night brings out
-- fireflies, and the Gloam Hollow's wisps.
function EnvironmentData.CritterPlan(ctx: CritterContext): { CritterWant }
	local out: { CritterWant } = {}
	local function want(kind: CritterKind, count: number)
		local n = math.floor(count + 0.5)
		if n > 0 then
			table.insert(out, { kind = kind, count = n })
		end
	end
	local day = ctx.daylight > 0.55
	local night = ctx.daylight < 0.3
	local wet = (
		ctx.weather == "Rain"
		or ctx.weather == "Storm"
		or ctx.weather == "Blizzard"
		or ctx.weather == "Ashfall"
	) and ctx.intensity > 0.35
	local stormy = (ctx.weather == "Storm" or ctx.weather == "Blizzard") and ctx.intensity > 0.35
	local life = EnvironmentData.LifeFactor(ctx.vitality)
	local biome = ctx.biomeId
	local leafy = LEAFY[biome] == true

	if ctx.nearPond then
		want("Duck", if night then 2 else 3)
	end
	if ctx.nearWater and not stormy then
		want("Fish", 1)
	end
	if biome == "grove" and night then
		want("Wisp", 3 + life)
	end
	if biome == "volcano" then
		want("EmberSprite", if ctx.weather == "Ashfall" then 4 else 3)
	end
	if leafy and not stormy and ctx.daylight > 0.25 and biome ~= "" then
		want("Deer", life) -- a deer at Healthy, two Thriving, a little herd in old growth
	end
	if (leafy or biome == "snow") and not stormy and not night then
		want("Rabbit", if biome == "snow" then 1 else 1 + life * 0.6)
	end
	if leafy and day and not wet then
		want("Butterfly", 1 + life * 2)
	end
	if (leafy or biome == "snow") and day and not wet then
		want("PerchedBird", if biome == "snow" then 1 else 1 + life * 0.5)
	end
	if leafy and day and not stormy then
		want("Flock", 1)
	end
	if leafy and night and not wet then
		want("Fireflies", if life >= 1.6 then 3 elseif life >= 1 then 2 else 1)
	end
	return out
end

---------------------------------------------------------------------------
-- Water (sounds by the river and lake, jumping fish)
---------------------------------------------------------------------------

local function nearestOnLine(points: { Vector2 }, x: number, z: number): (number, number, number)
	local best, bx, bz = math.huge, x, z
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local abx, abz = b.X - a.X, b.Y - a.Y
		local len2 = abx * abx + abz * abz
		local t = if len2 > 1e-6 then math.clamp(((x - a.X) * abx + (z - a.Y) * abz) / len2, 0, 1) else 0
		local px, pz = a.X + abx * t, a.Y + abz * t
		local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		if d < best then
			best, bx, bz = d, px, pz
		end
	end
	return best, bx, bz
end

-- The nearest point of open water (river, lake outflow, Mirror Lake, the
-- pond) to (x, z) at the water's surface, how far it is from the bank
-- there, and which water it is.
function EnvironmentData.NearestWater(x: number, z: number): (Vector3, number, string)
	local level = WorldLayout.LakeLevel
	local bestD, bestX, bestZ, bestKind = math.huge, x, z, "river"
	local function consider(d: number, px: number, pz: number, kind: string)
		if d < bestD then
			bestD, bestX, bestZ, bestKind = d, px, pz, kind
		end
	end
	local river = WorldLayout.River
	local d, px, pz = nearestOnLine(river.points, x, z)
	consider(math.max(0, d - river.width / 2), px, pz, "river")
	local outflow = WorldLayout.LakeOutflow
	d, px, pz = nearestOnLine(outflow.points, x, z)
	consider(math.max(0, d - outflow.width / 2), px, pz, "river")
	for _, pool in ipairs({ { p = WorldLayout.Lake, kind = "lake" }, { p = WorldLayout.Pond, kind = "pond" } }) do
		local p = pool.p
		local dx, dz = x - p.x, z - p.z
		local dist = math.sqrt(dx * dx + dz * dz)
		local edge = math.max(0, dist - p.radius)
		if dist > 1e-3 then
			local r = math.min(dist, p.radius * 0.85)
			consider(edge, p.x + dx / dist * r, p.z + dz / dist * r, pool.kind)
		else
			consider(0, p.x, p.z, pool.kind)
		end
	end
	return Vector3.new(bestX, level, bestZ), bestD, bestKind
end

-- Falling leaves a second, and river glints in view. Low is nothing: phones
-- already spend their budget on the trees.
function EnvironmentData.LeafRate(tier: string): number
	if tier == "high" then
		return 6
	elseif tier == "medium" then
		return 3
	end
	return 0
end

function EnvironmentData.RiverMotes(tier: string): number
	if tier == "high" then
		return 4
	elseif tier == "medium" then
		return 2
	end
	return 0
end

-- Chimney puffs a second. Low keeps the chimney, without the particles.
function EnvironmentData.ChimneyRate(tier: string): number
	if tier == "high" then
		return 8
	elseif tier == "medium" then
		return 4
	end
	return 0
end

return EnvironmentData
