--!strict
-- StumpLogic (T420): the rules of the stump a felled tree leaves, pure so
-- tests/TreeStump.spec pins them and SectionTrees / TreeArt only wire them.
--   * A cut lower than MinHeight (2.5 studs up the trunk) is a base cut: no
--     stump, the whole tree drops.
--   * Otherwise the stump is the same trunk below the cut: a tapered
--     segment whose bottom radius is the trunk's base radius and whose top
--     radius is the trunk's radius at the cut height. It is one of 16
--     uploaded frustum meshes (StumpMeshIds: 16 tapers 0.85 ... 1.00, each in
--     3, 5 and 8 stud heights): the taper nearest the trunk's real ratio and
--     the height bucket by stretch (Bucket), scaled so its base radius is the
--     trunk's base radius exactly and it stands as tall as the cut. A stump is
--     never clamped: over SleeveMax it stacks sleeves. The cut is capped flush at its height by an end-grain disc (the
--     wood's core colour) inside a 0.1 stud ring (RingHex).
--   * Trunks are round (T420): a section's square side `t` is the old
--     hitbox and the volume the prices use; its round radius is
--     RoundRadius(t) = t / sqrt(pi), the same cross-section area.
--   * It weathers from WeatherStart (90 s) after the cut, fully by
--     WeatherFull (170 s): the cut face lerps 40% toward #8A8172 and the bark
--     darkens 30% (the ring stays #3C2814). From FadeStart (180 s) it fades
--     for 10 s to FadeEnd (190 s) while it sinks SinkDepth (0.3) studs, and
--     then goes.
--   * Re-cutting a stump at some height frees a normal log (at least
--     MinLog long), the cut moving down to keep that; a remainder too
--     short to keep (under the cut edge) goes with it.
--   * A felled tree falls toward the side that was cut.

local StumpLogic = {}

StumpLogic.MinHeight = 2.5
StumpLogic.MinLog = 2
StumpLogic.RingWidth = 0.1
StumpLogic.RingHex = "3C2814"
StumpLogic.CapThickness = 0.05
StumpLogic.WeatherStart = 90
StumpLogic.WeatherFull = 170 -- fully weathered by here
StumpLogic.CapWeatherHex = "8A8172" -- the cut face weathers toward this
StumpLogic.CapWeatherShare = 0.4 -- by 40% when fully weathered
StumpLogic.BarkDarken = 0.3 -- the bark darkens 30% when fully weathered
StumpLogic.FadeStart = 180
StumpLogic.FadeEnd = 190
StumpLogic.SinkDepth = 0.3
-- A stump the cut edge would leave shorter than this (GameConfig.CutEdge)
-- is not kept: the whole stump comes away.
StumpLogic.Edge = 0.5

-- The 16 frustum ratios: 0.85 to 1.00 in 0.01 steps.
StumpLogic.Ratios = {} :: { number }
for i = 0, 15 do
	table.insert(StumpLogic.Ratios, (85 + i) / 100)
end

-- A segment of the trunk, bottom to top.
export type Seg = { length: number, thickness: number }

-- One mesh of a stump, bottom to top: it spans y0..y1 up the stump, starts
-- at baseRadius and ends at topRadius = baseRadius * ratio (ratio = one of
-- the 16 tapers, `index` 1..16), and is the `bucket` (3, 5 or 8 studs tall)
-- mesh stretched to the sleeve's height.
export type Sleeve = {
	set: string, -- "R13" or "R22": the radius set of its mesh
	y0: number,
	y1: number,
	baseRadius: number,
	topRadius: number,
	ratio: number,
	index: number,
	bucket: number,
}

export type Shape = {
	set: string, -- the radius set (StumpLogic.SetFor of the base radius)
	height: number, -- the cut height: never clamped
	baseRadius: number, -- the trunk's base radius, exactly
	realTop: number, -- the trunk's radius at the cut
	ratio: number, -- topRadius / baseRadius (the whole stump)
	index: number, -- the first sleeve's taper, 1..16
	topRadius: number, -- where the last sleeve ends (within 0.05 of realTop)
	sleeves: { Sleeve },
}

-- The height bucket by stretch. A mesh of native height H (3, 5 or 8) is
-- stretched by h / H. The boundaries make the stretch consistent: 3.87 is
-- 3 x 1.29 (H3 up to 1.29), 6.32 is 5 x 1.264 (H5 up to 1.264, and from
-- 3.87 / 5 = 0.774), and a sleeve of 6.32 to 10.4 is H8 (from 0.79 up to
-- 10.4 / 8 = 1.3). Inclusive at the top of each bucket: h <= 3.87 is H3,
-- 3.87 < h <= 6.32 is H5, h > 6.32 is H8.
StumpLogic.Bucket3Max = 3.87
StumpLogic.Bucket5Max = 6.32
StumpLogic.SleeveMax = 10.4 -- 8 x 1.3: a taller stump stacks sleeves

-- The two radius sets. R22's UVs are set up for a reference stump with base
-- radius 2.2; R13's reference radius is not stated anywhere, so it is
-- assumed to be 1.3: the radius the split implies (1.69 = 1.3 x 1.3 is the
-- most a 1.3 reference can be stretched, and 2.2 / 1.3 = 1.692 is the least
-- the 2.2 reference can be squeezed to: the sets meet at the split).
-- A stump whose base radius is at most SplitRadius uses R13, above it R22.
StumpLogic.RefRadius = { R13 = 1.3, R22 = 2.2 } :: { [string]: number }
StumpLogic.SplitRadius = 1.69
StumpLogic.StretchMax = 1.3 -- a mesh may be stretched by 1/1.3 to 1.3, round and up

function StumpLogic.SetFor(baseRadius: number): string
	return if baseRadius <= StumpLogic.SplitRadius then "R13" else "R22"
end

-- How far a sleeve of `set` is stretched from the mesh as made: round it
-- (its base radius over the set's reference radius) and up it (its height
-- over the bucket's mesh height).
function StumpLogic.BarkStretch(sleeve: Sleeve, set: string): (number, number)
	return sleeve.baseRadius / StumpLogic.RefRadius[set], (sleeve.y1 - sleeve.y0) / sleeve.bucket
end

-- Whether a stretch (round, up) is inside 1/1.3 to 1.3 both ways.
function StumpLogic.StretchOk(round: number, up: number): boolean
	local lo, hi = 1 / StumpLogic.StretchMax - 1e-9, StumpLogic.StretchMax + 1e-9
	return round >= lo and round <= hi and up >= lo and up <= hi
end

function StumpLogic.Bucket(h: number): number
	if h <= StumpLogic.Bucket3Max then
		return 3
	elseif h <= StumpLogic.Bucket5Max then
		return 5
	end
	return 8
end

-- The vertical stretch a mesh of `bucket` studs gets to stand `h` tall.
function StumpLogic.Stretch(h: number, bucket: number): number
	return h / bucket
end

-- The radius of a round trunk whose old square side was `thickness`: the
-- same cross-section area (pi r^2 = t^2), so volume and price don't move.
function StumpLogic.RoundRadius(thickness: number): number
	return thickness / math.sqrt(math.pi)
end

-- Whether a cut `height` studs up is a base cut (no stump).
function StumpLogic.IsBaseCut(height: number): boolean
	return height < StumpLogic.MinHeight - 1e-6
end

-- The frustum (of the 16) whose ratio is nearest `real`, and its index. A
-- ratio outside 0.85 to 1.00 takes the nearest end.
function StumpLogic.NearestRatio(real: number): (number, number)
	local best, bestI, bestD = StumpLogic.Ratios[1], 1, math.huge
	for i, r in ipairs(StumpLogic.Ratios) do
		local d = math.abs(r - real)
		if d < bestD - 1e-12 then
			best, bestI, bestD = r, i, d
		end
	end
	return best, bestI
end

-- The trunk's radius `h` studs up: each segment tapers in a straight line
-- from its own thickness at its bottom to the next segment's at its top;
-- the last holds its thickness.
function StumpLogic.RadiusAt(segs: { Seg }, h: number): number
	local y = 0
	for i, s in ipairs(segs) do
		local top = y + s.length
		local nextSeg = segs[i + 1]
		if h <= top + 1e-9 or nextSeg == nil then
			if nextSeg == nil or s.length <= 0 then
				return StumpLogic.RoundRadius(s.thickness)
			end
			local u = math.clamp((h - y) / s.length, 0, 1)
			return StumpLogic.RoundRadius(s.thickness + (nextSeg.thickness - s.thickness) * u)
		end
		y = top
	end
	return 0
end

-- The stump for a cut `h` studs up a trunk made of `segs`. Never clamped:
-- over SleeveMax studs it stacks equal sleeves (each at most SleeveMax tall,
-- and more of them when the trunk narrows faster than a 0.85 taper over one
-- sleeve), so the total is the real cut height. The taper runs across the whole
-- stump: the first sleeve starts at the trunk's base radius, each next one
-- starts exactly where the one below ended (no step), and every sleeve picks
-- the nearest of the 16 tapers to reach the trunk's own radius at the top of
-- that sleeve from where it stands, so the stack ends within one taper step
-- (0.005 x radius) of the trunk's radius at h.
function StumpLogic.Shape(segs: { Seg }, h: number): Shape
	local base = if segs[1] then StumpLogic.RoundRadius(segs[1].thickness) else 0
	local set = StumpLogic.SetFor(base)
	local function stack(n: number): ({ Sleeve }, boolean)
		local each = h / n
		local sleeves: { Sleeve } = {}
		local current = base
		local clamped = false
		for i = 1, n do
			local y1 = each * i
			local target = StumpLogic.RadiusAt(segs, y1)
			local real = if current > 0 then target / current else 1
			if real < StumpLogic.Ratios[1] - 1e-9 then
				clamped = true -- steeper than the 0.85 taper reaches
			end
			local ratio, index = StumpLogic.NearestRatio(real)
			local top = current * ratio
			table.insert(sleeves, {
				set = set,
				y0 = each * (i - 1),
				y1 = y1,
				baseRadius = current,
				topRadius = top,
				ratio = ratio,
				index = index,
				bucket = StumpLogic.Bucket(each),
			})
			current = top
		end
		return sleeves, clamped
	end
	-- At least enough sleeves to stay under SleeveMax; more when a trunk
	-- narrows faster than one 0.85 taper over a sleeve can follow.
	local n = math.max(1, math.ceil(h / StumpLogic.SleeveMax - 1e-9))
	local sleeves, clamped = stack(n)
	local tries = 0
	while clamped and tries < 40 do
		tries += 1
		n += 1
		sleeves, clamped = stack(n)
	end
	local top = sleeves[#sleeves].topRadius
	return {
		set = set,
		height = h,
		baseRadius = base,
		realTop = StumpLogic.RadiusAt(segs, h),
		ratio = if base > 0 then top / base else 1,
		index = sleeves[1].index,
		topRadius = top,
		sleeves = sleeves,
	}
end

-- Seconds since the cut -> how weathered (0 until WeatherStart, 1 at WeatherFull).
function StumpLogic.Weathering(age: number): number
	return math.clamp((age - StumpLogic.WeatherStart) / (StumpLogic.WeatherFull - StumpLogic.WeatherStart), 0, 1)
end

-- The bark `fresh` at weathering `w` (0..1): darkened up to BarkDarken.
function StumpLogic.BarkColor(fresh: Color3, w: number): Color3
	return fresh:Lerp(Color3.new(0, 0, 0), StumpLogic.BarkDarken * math.clamp(w, 0, 1))
end

-- The cut face `fresh` at weathering `w`: up to CapWeatherShare toward #8A8172.
-- (The ring is never recoloured.)
function StumpLogic.CapColor(fresh: Color3, w: number): Color3
	return fresh:Lerp(Color3.fromHex(StumpLogic.CapWeatherHex), StumpLogic.CapWeatherShare * math.clamp(w, 0, 1))
end

export type BarkMap = {
	repeatBase: number, -- bark tiles round the stump's foot
	repeatTop: number, -- and round its top
	repeatV: number, -- tiles up its height
	offsetV: number, -- where the pattern starts (the trunk's, 0 at its foot)
}

-- How a tiling bark texture of `studsPerTile` studs a tile would be laid on
-- the stump so it carries on from the trunk above the cut: the pattern runs
-- up from the trunk's foot (offset 0 there too), so at any height h it is
-- at h / studsPerTile, the trunk's own phase; and the tiles round the stump
-- are circumference / studsPerTile, the trunk's at the cut. (The trunks have
-- no SurfaceAppearance today: the stump copies the trunk's Material and
-- Color, and the engine tiles a Material in world space, so there is no seam.
-- This is the mapping for the day a bark SurfaceAppearance is added.)
function StumpLogic.BarkMapping(studsPerTile: number, baseRadius: number, topRadius: number, height: number): BarkMap
	local tile = math.max(studsPerTile, 1e-6)
	return {
		repeatBase = 2 * math.pi * baseRadius / tile,
		repeatTop = 2 * math.pi * topRadius / tile,
		repeatV = height / tile,
		offsetV = 0,
	}
end

-- 0 until FadeStart, 1 at FadeEnd.
function StumpLogic.Fade(age: number): number
	return math.clamp((age - StumpLogic.FadeStart) / (StumpLogic.FadeEnd - StumpLogic.FadeStart), 0, 1)
end

-- Studs it has sunk (SinkDepth by FadeEnd).
function StumpLogic.SinkAt(age: number): number
	return StumpLogic.Fade(age) * StumpLogic.SinkDepth
end

function StumpLogic.Gone(age: number): boolean
	return age >= StumpLogic.FadeEnd - 1e-9
end

export type Recut = {
	whole: boolean, -- the whole stump comes away as a log
	cutAt: number, -- where it is cut (0 when whole)
	logLength: number,
	remainder: number, -- the stump left (0 when whole)
}

-- A stump `height` tall cut at `at` studs up. The log is at least MinLog
-- long (the cut moves down to height - MinLog); if that leaves less than
-- the cut edge, or the stump is too short for a log, it all comes away.
function StumpLogic.Recut(height: number, at: number): Recut
	local cutAt = math.min(math.clamp(at, 0, height), height - StumpLogic.MinLog)
	if cutAt < StumpLogic.Edge - 1e-9 then
		return { whole = true, cutAt = 0, logLength = height, remainder = 0 }
	end
	return { whole = false, cutAt = cutAt, logLength = height - cutAt, remainder = cutAt }
end

-- The flat unit direction a tree falls: toward the face that was cut
-- (`normal`, world space). nil for a normal with no sideways part.
function StumpLogic.FallDirection(normal: Vector3): Vector3?
	local flat = Vector3.new(normal.X, 0, normal.Z)
	if flat.Magnitude < 0.05 then
		return nil
	end
	return flat.Unit
end

return StumpLogic
