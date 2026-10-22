--!strict
-- StumpLogic (T420): the rules of the stump a felled tree leaves, pure so
-- tests/TreeStump.spec pins them and SectionTrees / TreeArt only wire them.
--   * A cut lower than MinHeight (2.5 studs up the trunk) is a base cut: no
--     stump, the whole tree drops.
--   * Otherwise the stump is the same trunk below the cut: a tapered
--     segment whose bottom radius is the trunk's base radius and whose top
--     radius is the trunk's radius at the cut height. It is built from one
--     of 16 frustum shapes (top / base ratios 0.85, 0.86 ... 1.00): the one
--     nearest the trunk's real ratio. Each frustum is stood up from Steps
--     stacked discs (bottom disc = base radius, top disc = top radius), so
--     no uploaded mesh is needed. The cut is capped flush at its height by
--     an end-grain disc (the wood's core colour) inside a 0.1 stud ring
--     (RingHex).
--   * It weathers from WeatherStart seconds after the cut, fades between
--     FadeStart and FadeEnd while it sinks SinkDepth studs, and then goes.
--   * Re-cutting a stump at some height frees a normal log (at least
--     MinLog long), the cut moving down to keep that; a remainder too
--     short to keep (under the cut edge) goes with it.
--   * A felled tree falls toward the side that was cut.

local StumpLogic = {}

StumpLogic.MinHeight = 2.5
StumpLogic.MinLog = 2
StumpLogic.Steps = 4
StumpLogic.RingWidth = 0.1
StumpLogic.RingHex = "3C2814"
StumpLogic.CapThickness = 0.05
StumpLogic.WeatherStart = 90
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

export type Shape = {
	height: number,
	baseRadius: number,
	realTop: number, -- the trunk's radius at the cut
	ratio: number, -- the frustum chosen
	index: number, -- 1..16
	topRadius: number, -- baseRadius * ratio
}

export type Step = { y0: number, y1: number, radius: number }

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
				return s.thickness / 2
			end
			local u = math.clamp((h - y) / s.length, 0, 1)
			return (s.thickness + (nextSeg.thickness - s.thickness) * u) / 2
		end
		y = top
	end
	return 0
end

-- The stump for a cut `h` studs up a trunk made of `segs`.
function StumpLogic.Shape(segs: { Seg }, h: number): Shape
	local base = if segs[1] then segs[1].thickness / 2 else 0
	local realTop = StumpLogic.RadiusAt(segs, h)
	local real = if base > 0 then realTop / base else 1
	local ratio, index = StumpLogic.NearestRatio(real)
	return {
		height = h,
		baseRadius = base,
		realTop = realTop,
		ratio = ratio,
		index = index,
		topRadius = base * ratio,
	}
end

-- The discs a frustum is stood up from, bottom to top: the first is
-- exactly the base radius, the last exactly the top radius. A straight
-- stump (equal radii) is one disc.
function StumpLogic.Frustum(baseRadius: number, topRadius: number, height: number): { Step }
	local out: { Step } = {}
	if math.abs(baseRadius - topRadius) < 1e-9 then
		table.insert(out, { y0 = 0, y1 = height, radius = baseRadius })
		return out
	end
	local n = StumpLogic.Steps
	for i = 1, n do
		local u = (i - 1) / (n - 1)
		table.insert(out, {
			y0 = height * (i - 1) / n,
			y1 = height * i / n,
			radius = baseRadius + (topRadius - baseRadius) * u,
		})
	end
	return out
end

-- Seconds since the cut -> how weathered (0 until WeatherStart, 1 at FadeStart).
function StumpLogic.Weathering(age: number): number
	return math.clamp((age - StumpLogic.WeatherStart) / (StumpLogic.FadeStart - StumpLogic.WeatherStart), 0, 1)
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
