--!strict
-- TreeLogic: the rules behind standing and falling trees, pure so tests
-- can check them (TreeService and TreeFX use them).
--   * Size classes: a forest of identical trees looks cloned, so each tree
--     is small, normal or large. Big trees take more chopping and give an
--     extra log; small ones the reverse. The weights keep the average HP
--     and logs equal to WoodData's, so the economy model still holds.
--   * The fall: a tree tips away from whoever felled it (a little random),
--     so it never lands on the player, and the logs lie along that line.
--   * Chips and leaves (TreeFX): no physics, so nothing falls through the
--     ground or bumps anyone. Each piece flies a path worked out when it
--     spawns, lands on the ground under it, lies there, then fades.

local TreeLogic = {}

export type SizeClass = {
	name: string, -- "small" | "normal" | "large"
	scale: number, -- model scale (1 = WoodData size)
	hpMul: number,
	logDelta: number, -- logs added to (or taken from) logsPerTree
	weight: number, -- relative chance
}

TreeLogic.Sizes = {
	{ name = "small", scale = 0.82, hpMul = 0.75, logDelta = -1, weight = 25 },
	{ name = "normal", scale = 1, hpMul = 1, logDelta = 0, weight = 50 },
	{ name = "large", scale = 1.22, hpMul = 1.25, logDelta = 1, weight = 25 },
} :: { SizeClass }

-- The size class for a roll in [0, 1).
function TreeLogic.SizeFor(roll: number): SizeClass
	local total = 0
	for _, s in ipairs(TreeLogic.Sizes) do
		total += s.weight
	end
	local acc = 0
	for _, s in ipairs(TreeLogic.Sizes) do
		acc += s.weight / total
		if roll < acc then
			return s
		end
	end
	return TreeLogic.Sizes[#TreeLogic.Sizes]
end

-- Logs a felled tree of this size drops (never fewer than 1).
function TreeLogic.LogCount(logsPerTree: number, size: SizeClass, multiplier: number?): number
	return math.max(1, logsPerTree + size.logDelta) * (multiplier or 1)
end

-- HP of a tree of this size (whole numbers, so hit counts stay readable).
function TreeLogic.MaxHP(treeHP: number, size: SizeClass): number
	return math.max(1, math.floor(treeHP * size.hpMul + 0.5))
end

-- Flat unit vector a felled tree falls along: away from the feller, turned
-- by `jitter` radians (callers pass a small random angle).
function TreeLogic.FallDirection(base: Vector3, feller: Vector3?, jitter: number): Vector3
	local away = Vector3.new(1, 0, 0)
	if feller then
		local v = Vector3.new(base.X - feller.X, 0, base.Z - feller.Z)
		if v.Magnitude > 0.05 then
			away = v.Unit
		end
	end
	local c, s = math.cos(jitter), math.sin(jitter)
	return Vector3.new(away.X * c - away.Z * s, 0, away.X * s + away.Z * c)
end

-- CFrames for n logs (cylinder axis = the CFrame's X) lying end to end
-- along `dir` from the stump, in side-by-side rows when the trunk is too
-- short to hold them in one line. `length` / `diameter` are the log size,
-- `gap` the space between logs.
function TreeLogic.LogLayout(
	base: Vector3,
	dir: Vector3,
	trunkLength: number,
	n: number,
	length: number,
	diameter: number,
	gap: number
): { CFrame }
	local step = length + gap
	local perRow = math.max(1, math.floor(trunkLength / step))
	local rows = math.ceil(n / perRow)
	local side = dir:Cross(Vector3.yAxis)
	local out: { CFrame } = {}
	for i = 0, n - 1 do
		local row = i // perRow
		local col = i % perRow
		local pos = base
			+ dir * (diameter * 1.8 + col * step)
			+ side * ((row - (rows - 1) / 2) * (diameter + 0.3))
			+ Vector3.new(0, diameter / 2, 0)
		table.insert(out, CFrame.fromMatrix(pos, dir, Vector3.yAxis))
	end
	return out
end

-- Seconds the fall takes, and the angle it ends at (nearly flat: a full
-- 90 would sink the trunk into the ground).
TreeLogic.FallTime = 1.1
TreeLogic.FallAngle = math.rad(86)

-- How far a tree has tipped `t` seconds into its fall: slow at first, then
-- gathering speed, with a small bounce as it lands (0 = upright, 1 = down).
function TreeLogic.FallProgress(t: number): number
	local x = math.clamp(t / TreeLogic.FallTime, 0, 1)
	if x < 0.86 then
		local u = x / 0.86
		return u * u * u -- a slow lean that gathers speed
	end
	local u = (x - 0.86) / 0.14
	return 1 - math.sin(u * math.pi) * 0.035 -- the thump and settle
end

-- Once it's down, a felled tree fades out on every client (TreeFX sets its
-- parts' LocalTransparencyModifier to this, t seconds into the fall), into
-- the logs the server lays when it hides the tree (FallTime + 0.35, and
-- they reach a client a little later): it starts 0.1 s after the landing
-- and is gone at FallTime + 0.4, about when the logs show up.
TreeLogic.FellFadeStart = TreeLogic.FallTime + 0.1
TreeLogic.FellFadeTime = 0.3

function TreeLogic.FellFade(t: number): number
	return math.clamp((t - TreeLogic.FellFadeStart) / TreeLogic.FellFadeTime, 0, 1)
end

---------------------------------------------------------------------------
-- Chips and leaves (TreeFX)
---------------------------------------------------------------------------

-- How one kind of piece flies.
export type Debris = {
	gravity: number, -- studs/s² pulling it down
	drag: number, -- per second: 0 flies a plain arc, more drifts like a leaf
	up: { number }, -- launch speed upward: min, max
	side: { number }, -- launch speed sideways: min, max
	lift: number, -- its centre rests this far above the ground
	rest: number, -- seconds it lies on the ground before fading
	fade: number, -- seconds the fade takes
}

-- Wood chips knocked off the bark by a swing: a short hop out from the cut,
-- then about a second on the ground. Gravity is lighter than the world's
-- (196.2), so the arc is long enough to see.
TreeLogic.Chip = {
	gravity = 120,
	drag = 0,
	up = { 12, 20 },
	side = { 4, 8 },
	lift = 0.1,
	rest = 0.9,
	fade = 0.4,
} :: Debris

-- Leaves shaken loose when a tree lands: a burst up, then a drift down at
-- about gravity / drag (5 studs/s).
TreeLogic.Leaf = {
	gravity = 10,
	drag = 2,
	up = { 8, 14 },
	side = { 3, 6 },
	lift = 0.05,
	rest = 0.5,
	fade = 0.5,
} :: Debris

-- One piece in the air: where it starts, how fast, where it comes to rest
-- (its centre's height) and when (seconds after it spawned).
export type Flight = {
	kind: Debris,
	origin: Vector3,
	velocity: Vector3,
	restY: number,
	landT: number,
}

-- How far a piece has moved along one axis after t seconds, starting at
-- speed v with g pulling against it (0 sideways) and linear drag k.
local function travel(v: number, g: number, k: number, t: number): number
	if k <= 0 then
		return v * t - 0.5 * g * t * t
	end
	local terminal = -g / k
	return terminal * t + (v - terminal) * (1 - math.exp(-k * t)) / k
end

-- When a piece thrown up at vy from `height` above its rest height comes
-- back down to it: the later crossing, on the way down. 0 if it never
-- gets up there (it starts below the ground and can't climb that far).
local function landTime(vy: number, g: number, k: number, height: number): number
	if k <= 0 then
		local disc = vy * vy + 2 * g * height
		if disc < 0 then
			return 0
		end
		return math.max(0, (vy + math.sqrt(disc)) / g)
	end
	-- With drag it rises to one apex and then falls for ever, so the way
	-- down crosses the rest height once: bisect it.
	local terminal = -g / k
	local apex = if vy > 0 then math.log((vy - terminal) / -terminal) / k else 0
	if height + travel(vy, g, k, apex) < 0 then
		return 0
	end
	local lo, hi = apex, apex + 1
	for _ = 1, 30 do
		if height + travel(vy, g, k, hi) <= 0 then
			break
		end
		lo, hi = hi, hi * 2
	end
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		if height + travel(vy, g, k, mid) > 0 then
			lo = mid
		else
			hi = mid
		end
	end
	return hi
end

-- A piece of `kind` leaving `origin` at `velocity`, to rest on the ground
-- at height `groundY`.
function TreeLogic.Flight(kind: Debris, origin: Vector3, velocity: Vector3, groundY: number): Flight
	assert(kind.gravity > 0, "a piece needs gravity to land")
	local restY = groundY + kind.lift
	return {
		kind = kind,
		origin = origin,
		velocity = velocity,
		restY = restY,
		landT = landTime(velocity.Y, kind.gravity, kind.drag, origin.Y - restY),
	}
end

-- A piece of `kind` thrown out along the flat direction `dir`, turned up to
-- `spread` radians either way, at speeds inside the kind's ranges. r1, r2,
-- r3 are random numbers in [0, 1): upward speed, sideways speed, turn.
function TreeLogic.Launch(
	kind: Debris,
	origin: Vector3,
	dir: Vector3,
	spread: number,
	groundY: number,
	r1: number,
	r2: number,
	r3: number
): Flight
	local up = kind.up[1] + (kind.up[2] - kind.up[1]) * r1
	local side = kind.side[1] + (kind.side[2] - kind.side[1]) * r2
	local a = (r3 * 2 - 1) * spread
	local c, s = math.cos(a), math.sin(a)
	local flat = Vector3.new(dir.X * c - dir.Z * s, 0, dir.X * s + dir.Z * c)
	return TreeLogic.Flight(kind, origin, flat * side + Vector3.new(0, up, 0), groundY)
end

-- Where the piece's centre is t seconds after it spawned. It never goes
-- below its rest height, and once it has landed it stays put.
function TreeLogic.FlightAt(f: Flight, t: number): Vector3
	local k = f.kind
	local tt = math.clamp(t, 0, f.landT)
	local x = f.origin.X + travel(f.velocity.X, 0, k.drag, tt)
	local z = f.origin.Z + travel(f.velocity.Z, 0, k.drag, tt)
	if t >= f.landT then
		return Vector3.new(x, f.restY, z)
	end
	return Vector3.new(x, math.max(f.restY, f.origin.Y + travel(f.velocity.Y, k.gravity, k.drag, tt)), z)
end

-- Its transparency t seconds after it spawned: solid in the air and while it
-- rests, then fading out to 1.
function TreeLogic.FlightFade(f: Flight, t: number): number
	return math.clamp((t - f.landT - f.kind.rest) / f.kind.fade, 0, 1)
end

-- Seconds from spawning until it has faded out.
function TreeLogic.FlightLife(f: Flight): number
	return f.landT + f.kind.rest + f.kind.fade
end

-- A rotation that turns "up" (+Y) to the ground's `normal`, so a piece lies
-- flat on a slope instead of half in it.
function TreeLogic.Upright(normal: Vector3): CFrame
	if normal.Magnitude < 1e-6 then
		return CFrame.identity
	end
	local n = normal.Unit
	local axis = Vector3.new(0, 1, 0):Cross(n)
	if axis.Magnitude < 1e-6 then
		return if n.Y >= 0 then CFrame.identity else CFrame.Angles(math.pi, 0, 0)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(n.Y, -1, 1)))
end

return TreeLogic
