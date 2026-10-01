--!strict
-- TreeLogic: the rules behind standing and falling trees, pure so tests
-- can check them (TreeService and TreeFX use them).
--   * Size classes: a forest of identical trees looks cloned, so each tree
--     is small, normal or large. Big trees take more chopping and give an
--     extra log; small ones the reverse. The weights keep the average HP
--     and logs equal to WoodData's, so the economy model still holds.
--   * The fall: a tree tips away from whoever felled it (a little random),
--     so it never lands on the player, and the logs lie along that line.

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

return TreeLogic
