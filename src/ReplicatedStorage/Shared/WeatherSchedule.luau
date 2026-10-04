--!strict
-- WeatherSchedule: the weather, worked out from the server clock so every
-- server (and every player on it) agrees without saving or sending
-- anything. Pure; shared by WeatherService (publishes it), the clients
-- (draw it) and tests.
--
--   * Time is cut into 4-minute slots. Each slot's weather comes from a
--     hash of its index: Clear 50, Cloudy 20, Rain 15, Storm 7, Fog 8.
--   * A slot's weather eases in over its first 40 s and out over its last
--     40 s, unless the slot next to it has the same weather (so two rainy
--     slots in a row are one long shower, not two).
--   * Fog only lies at night and in the early morning (a day is 24 real
--     minutes, so a slot is a sixth of a day): a fog slot is foggy from 21:00 to
--     08:30 in-game, burning off with the morning, and clear in between.
--     Those edges are clock hours, so a faster night does not move them.
--   * Each biome reads the weather its own way (ForBiome): rain falls as
--     snow on the Snowfields, storms are blizzards there and ashfall at the
--     Volcano, and up on the Aether Isles you are above the cloud and the
--     fog, in the wind.

local WorldTime = require(script.Parent.WorldTime)

local WeatherSchedule = {}

export type Kind = "Clear" | "Cloudy" | "Rain" | "Storm" | "Fog" | "Snow" | "Blizzard" | "Ashfall" | "Wind"

export type State = {
	kind: Kind,
	intensity: number, -- 0..1: how strongly it's showing right now
	slotStart: number, -- server time the slot began
	slotEnd: number, -- ... and ends
}

WeatherSchedule.SlotSeconds = 240
WeatherSchedule.EaseSeconds = 40

-- The weathers a slot can roll, with their weights (out of 100).
WeatherSchedule.Weights = {
	{ kind = "Clear" :: Kind, weight = 50 },
	{ kind = "Cloudy" :: Kind, weight = 20 },
	{ kind = "Rain" :: Kind, weight = 15 },
	{ kind = "Storm" :: Kind, weight = 7 },
	{ kind = "Fog" :: Kind, weight = 8 },
}

-- Fog's hours (in-game ClockTime): from FogFrom across midnight to FogTo,
-- thickening and thinning over FogRamp hours at each end.
WeatherSchedule.FogFrom = 21
WeatherSchedule.FogTo = 8.5
WeatherSchedule.FogRamp = 1

-- How each biome renames the weather.
WeatherSchedule.BiomeRules = {
	snow = { Rain = "Snow", Storm = "Blizzard" },
	volcano = { Storm = "Ashfall" },
	sky = { Cloudy = "Wind", Rain = "Wind", Fog = "Clear" },
} :: { [string]: { [string]: Kind } }

-- How windy each weather is at full strength (0 = still air, 1 = a gale).
-- WindSway and the GlobalWind gusts read this.
WeatherSchedule.Windiness = {
	Clear = 0.25,
	Cloudy = 0.4,
	Rain = 0.55,
	Storm = 1,
	Fog = 0.08,
	Snow = 0.35,
	Blizzard = 1.1,
	Ashfall = 0.7,
	Wind = 0.95,
} :: { [string]: number }

local SALT = 0x5EED1E

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- a * b mod 2^32 without losing bits to doubles (both under 2^32).
local function mul32(a: number, b: number): number
	local hi = (a * bit32.rshift(b, 16)) % 4294967296
	return (hi * 65536 + a * bit32.band(b, 0xFFFF)) % 4294967296
end

-- A well-mixed number in [0, 1) from an integer (any sign or size).
local function hash01(n: number): number
	local x = bit32.bxor(math.floor(n) % 4294967296, SALT)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x7FEB352D)
	x = bit32.bxor(x, bit32.rshift(x, 15))
	x = mul32(x, 0x846CA68B)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x / 4294967296
end

local totalWeight = 0
for _, w in ipairs(WeatherSchedule.Weights) do
	totalWeight += w.weight
end

-- The weather slot number `index` rolled (before fog hours and biomes).
function WeatherSchedule.SlotKind(index: number): Kind
	local roll = hash01(index) * totalWeight
	for _, w in ipairs(WeatherSchedule.Weights) do
		roll -= w.weight
		if roll < 0 then
			return w.kind
		end
	end
	return "Clear"
end

-- 0..1: how much fog the hour allows (0 at midday).
function WeatherSchedule.FogWindow(clockTime: number): number
	local from, to = WeatherSchedule.FogFrom, WeatherSchedule.FogTo
	local length = (to - from) % 24
	local since = (clockTime - from) % 24
	if since >= length then
		return 0
	end
	return smoothstep(math.min(since, length - since) / WeatherSchedule.FogRamp)
end

-- The weather at server time `t` (seconds, e.g. workspace:GetServerTimeNow()).
function WeatherSchedule.At(t: number): State
	local slotLength = WeatherSchedule.SlotSeconds
	local ease = WeatherSchedule.EaseSeconds
	local index = math.floor(t / slotLength)
	local slotStart = index * slotLength
	local slotEnd = slotStart + slotLength
	local kind = WeatherSchedule.SlotKind(index)
	local intensity = 1
	if WeatherSchedule.SlotKind(index - 1) ~= kind then
		intensity = math.min(intensity, smoothstep((t - slotStart) / ease))
	end
	if WeatherSchedule.SlotKind(index + 1) ~= kind then
		intensity = math.min(intensity, smoothstep((slotEnd - t) / ease))
	end
	if kind == "Fog" then
		local window = WeatherSchedule.FogWindow(WorldTime.ClockTime(t))
		if window <= 0 then
			return { kind = "Clear" :: Kind, intensity = 0, slotStart = slotStart, slotEnd = slotEnd }
		end
		intensity *= window
	end
	return { kind = kind :: Kind, intensity = intensity, slotStart = slotStart, slotEnd = slotEnd }
end

-- The same weather as `biomeId` shows it ("" or an unknown id = as is).
function WeatherSchedule.ForBiome(state: State, biomeId: string?): State
	local rules = if biomeId then WeatherSchedule.BiomeRules[biomeId] else nil
	local renamed = if rules then rules[state.kind] else nil
	if not renamed then
		return state
	end
	return {
		kind = renamed :: Kind,
		intensity = state.intensity,
		slotStart = state.slotStart,
		slotEnd = state.slotEnd,
	}
end

-- 0..~1: how windy `kind` is at `intensity` (it starts from a clear day's
-- breeze, so weather easing in never makes the wind jump).
function WeatherSchedule.Wind(kind: string, intensity: number): number
	local calm = WeatherSchedule.Windiness.Clear
	local full = WeatherSchedule.Windiness[kind] or calm
	return calm + (full - calm) * math.clamp(intensity, 0, 1)
end

-- True for weathers with something falling from the sky.
function WeatherSchedule.IsWet(kind: string): boolean
	return kind == "Rain" or kind == "Storm" or kind == "Snow" or kind == "Blizzard" or kind == "Ashfall"
end

-- WLD-05: the Rate for a map emitter (the waterfall's) from its
-- "BaseRate" attribute and the Quality tier's WeatherRate (1 on high, 0.5
-- on low). nil when the attribute isn't a usable number (leave it alone).
function WeatherSchedule.MapEmitterRate(baseRate: unknown, scale: number): number?
	if type(baseRate) ~= "number" or baseRate ~= baseRate or baseRate < 0 or baseRate == math.huge then
		return nil
	end
	return baseRate * math.clamp(scale, 0, 1)
end

-- The next `count` slots after the one at `t`: { kind, slotStart }.
-- (A forecast for the HUD; fog shows as Fog even if it only lies at night.)
function WeatherSchedule.Forecast(t: number, count: number): { { kind: Kind, slotStart: number } }
	local out = {}
	local index = math.floor(t / WeatherSchedule.SlotSeconds)
	for i = 1, count do
		table.insert(out, {
			kind = WeatherSchedule.SlotKind(index + i),
			slotStart = (index + i) * WeatherSchedule.SlotSeconds,
		})
	end
	return out
end

return WeatherSchedule
