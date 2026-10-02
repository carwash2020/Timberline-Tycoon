--!strict
-- TreeGen: the skeleton of a section tree (V2_PLAN.md §3a, §3b). Pure and
-- deterministic: the same wood, seed and scale give the same tree on every
-- server, in the specs, in tools/economy and in tools/preview, and
-- TreeArt.FromSkeleton turns it into parts.
--
--   * A tree is sections (square blocks, length up their Y axis) joined
--     parent to child, plus "dress" hung on them: leaf clusters, conifer
--     tiers, fronds, root flares, bark marks. Every dress entry names the
--     section it rides on and how many parts it becomes, so a tree's part
--     count (PartCount) is known before a single part exists, and the
--     generator keeps it inside the wood's budget (TreeGen.Budgets).
--   * Skeleton(woodId, seed, scale, opts?): a mature tree. `scale` is the
--     size roll (SizeLo 0.85 / 1 / SizeHi 1.15; an Elder passes
--     { elder = true } and ForestData.Elder.scale). The height always lands
--     inside the wood's band (WoodData v2.shape.height), small trees low in
--     it and large ones high; the base thickness is trunkThickness * scale.
--   * AtStage(skel, s): the same tree s (0.25, 0.5, 0.75) of the way grown:
--     sections deeper than (maxDepth + trunkSegments) * s are hidden, the
--     rest shrink by s, and the leaves gather on the tips that show.
--   * Every section's `cf` is its bottom centre, Y up the section, in the
--     tree's own space (the base of the trunk at the origin, the ground at
--     y = 0). Randomness only from Kit.rng(seed + k); frames only from
--     CFrame.fromMatrix.

local ForestData = require(script.Parent.ForestData)
local Kit = require(script.Parent.Art.Kit)
local WoodData = require(script.Parent.WoodData)

type Shape = WoodData.TreeShape
type Rng = Kit.Rng

local TreeGen = {}

-- One dress entry. `cf` and `size` are in the tree's space; what they mean
-- depends on the kind:
--   leaves, wisp   cf = the cluster's centre (yawed), size = its box
--   tier, cap      cf = the cone's base centre (Y up), size = (2r, h, 2r), sides
--   frond          points = { root, bend, tip }, size.X = its width
--   coconut, pod   cf = the ball's centre, size = its box (a pod's stem above it)
--   flare          cf = the wedge's centre (its slope facing out), size = the wedge
--   mark, crack, vein, ring   cf = the strip's centre on the bark, size = the strip
export type Dress = {
	kind: string,
	section: number,
	cf: CFrame,
	size: Vector3,
	parts: number,
	seed: number,
	sides: number?,
	glow: boolean?,
	flat: boolean?, -- leaves: lay its parts flat (a tiered crown's discs)
	grain: number?, -- leaves: its parts at most this big
	points: { Vector3 }?,
	tips: { number }?, -- leaves: the tip sections this cluster dresses
}

export type Section = {
	id: number,
	parent: number?,
	children: { number },
	depth: number, -- 0 at the root; < trunkSegments is the trunk
	cf: CFrame, -- bottom centre, Y up the section
	length: number,
	thickness: number, -- the square cross-section's side
	dress: { Dress },
}

export type Skeleton = {
	woodId: string,
	seed: number,
	scale: number,
	stage: number, -- 1 = mature
	elder: boolean,
	trunkSegments: number,
	maxDepth: number, -- branch levels after the trunk (an Elder's bonus included)
	sections: { Section },
	height: number, -- the top of everything, studs above the base
	width: number, -- the widest horizontal extent of the crown
	stretch: number, -- how much the lengths were stretched to fit the height band
}

export type Options = { elder: boolean? }

-- Parts per tree, sections and dress together, for every seed and size, an
-- Elder included. V2_PLAN §3c's maxima (oak 46, birch 40, pine 56, maple 52,
-- palm 32, frost 66, ember 46, gloam 48, lumen 44) would put the world at
-- about 34.8k parts with today's 512 tree spots (161 of them pines); these
-- keep it under §16's 31k (the TreeArtSections spec checks the estimate).
TreeGen.Budgets = {
	oak = 38,
	birch = 32,
	pine = 44,
	maple = 44,
	palmwood = 32,
	frostwood = 60,
	emberwood = 42,
	phantomwood = 44,
	lumenwood = 40,
} :: { [string]: number }
TreeGen.DefaultBudget = 48

TreeGen.HardCap = 40 -- sections, whatever maxSections says
TreeGen.FirstBranchMin = 8 -- studs: no limb lower than a truck's roof
TreeGen.MinEndY = 0.5 -- no section ends lower than this
TreeGen.SizeLo = 0.85 -- the size roll's small and large scales (the height band's ends)
TreeGen.SizeHi = 1.15
TreeGen.Stages = { 0.25, 0.5, 0.75, 1 }
-- The scale for each of TreeLogic's size classes in the v2 loop.
TreeGen.SizeScales = { small = 0.85, normal = 1, large = 1.15 } :: { [string]: number }
TreeGen.WispSize = 4.2 -- a gloamwood wisp's size at scale 1
TreeGen.TierOverlap = 0.42 -- of a conifer tier's height, inside the next one up

-- The look of each canopy, beyond the shape data (art tuning, not balance).
-- A leafy crown is a few leaf masses, each a lumpy blob of parts sized to
-- cover the branch tips it dresses (a lone tip's mass is one cluster):
--   leafShare  of the parts left after the details, kept for leaves
--   size       a lone tip's cluster size over the shape's leafSize
--   clusterY   a mass's height over its width
--   lift       a mass's centre sits this much of its height above its tips
--   merge      tips closer than this many cluster sizes share a mass
--   massParts  parts per mass, at least (masses merge until they can have it)
--   maxParts   ... and at most
--   maxGrow    a mass is at most this many cluster sizes across
--   flatten    masses' heights pulled this far (0-1) toward their average:
--              a flat-topped crown
--   layers     a tiered crown's flat discs (glowtiers)
--   fill       spare masses go on branch joints (and along a leader) at
--              least this many cluster sizes from every other mass
--   rise       side branches bend this far toward the sky (0-1)
--   out        ... and this far away from the trunk
type Look = {
	leafShare: number,
	size: number,
	clusterY: number,
	lift: number,
	merge: number,
	massParts: number,
	maxParts: number,
	maxGrow: number,
	flatten: number,
	layers: number,
	fill: number,
	rise: number,
	out: number,
}

local LOOKS: { [string]: Look } = {
	oak = {
		leafShare = 0.64,
		size = 1.2,
		clusterY = 0.78,
		lift = 0.2,
		merge = 0.8,
		massParts = 6,
		maxParts = 8,
		maxGrow = 1.9,
		flatten = 0.3,
		layers = 0,
		fill = 0.75,
		rise = 0.24,
		out = 0.06,
	},
	birch = {
		leafShare = 0.66,
		size = 1.15,
		clusterY = 1.05,
		lift = 0.1,
		merge = 0.6,
		massParts = 4,
		maxParts = 6,
		maxGrow = 1.5,
		flatten = 0,
		layers = 0,
		fill = 0.55,
		rise = 0.55,
		out = 0,
	},
	maple = {
		leafShare = 0.66,
		size = 1.2,
		clusterY = 0.72,
		lift = 0.12,
		merge = 0.95,
		massParts = 6,
		maxParts = 8,
		maxGrow = 1.8,
		flatten = 0.75,
		layers = 0,
		fill = 0.75,
		rise = 0.3,
		out = 0.14,
	},
	emberwood = {
		leafShare = 0.62,
		size = 1.15,
		clusterY = 0.8,
		lift = 0.2,
		merge = 0.7,
		massParts = 6,
		maxParts = 8,
		maxGrow = 1.8,
		flatten = 0.2,
		layers = 0,
		fill = 0.8,
		rise = 0.22,
		out = 0.08,
	},
	phantomwood = {
		leafShare = 0,
		size = 1,
		clusterY = 0.8,
		lift = 0,
		merge = 0,
		massParts = 2,
		maxParts = 2,
		maxGrow = 1,
		flatten = 0,
		layers = 0,
		fill = 99,
		rise = 0.08,
		out = 0.22,
	},
	lumenwood = {
		leafShare = 0.62,
		size = 1.3,
		clusterY = 0.24,
		lift = 0.1,
		merge = 0.7,
		massParts = 5,
		maxParts = 8,
		maxGrow = 2.6,
		flatten = 0,
		layers = 3,
		fill = 0.7,
		rise = 0.02,
		out = 0.4,
	},
}
local DEFAULT_LOOK: Look = LOOKS.oak

local UP = Vector3.yAxis

---------------------------------------------------------------------------
-- Vector helpers
---------------------------------------------------------------------------

-- v turned `angle` radians about the unit `axis` (Rodrigues).
local function rotate(v: Vector3, axis: Vector3, angle: number): Vector3
	local c, s = math.cos(angle), math.sin(angle)
	return v * c + axis:Cross(v) * s + axis * axis:Dot(v) * (1 - c)
end

-- Some unit vector at right angles to the unit `v`.
local function perpendicular(v: Vector3): Vector3
	local ref = if math.abs(v.Y) < 0.9 then UP else Vector3.xAxis
	return v:Cross(ref).Unit
end

-- `ref` with its part along the unit `d` taken out (a unit vector at right
-- angles to d), or any perpendicular if ref runs along d.
local function across(ref: Vector3, d: Vector3): Vector3
	local x = ref - d * ref:Dot(d)
	if x.Magnitude < 1e-4 then
		return perpendicular(d)
	end
	return x.Unit
end

-- `dir` tipped `angle` radians toward the direction `az` radians round it
-- from `ref` (a unit vector at right angles to dir).
local function tip(dir: Vector3, angle: number, az: number, ref: Vector3): Vector3
	local toward = rotate(ref, dir, az)
	return (dir * math.cos(angle) + toward * math.sin(angle)).Unit
end

-- A frame at `pos` with Y along the unit `d` and X as close to `ref` as it
-- can be, then turned `yaw` radians about Y.
local function frame(pos: Vector3, d: Vector3, ref: Vector3, yaw: number): CFrame
	local x = rotate(across(ref, d), d, yaw)
	return CFrame.fromMatrix(pos, x, d, x:Cross(d))
end

local function deg(a: number): number
	return math.rad(a)
end

---------------------------------------------------------------------------
-- The height band
---------------------------------------------------------------------------

-- How tall a mature tree of this wood, seed and scale stands (studs): inside
-- the wood's band for every size from SizeLo to SizeHi (small trees low in
-- it, large ones high, a little jitter by seed), in proportion beyond it,
-- and an Elder at its normal height times its scale, capped.
function TreeGen.TargetHeight(shape: Shape, seed: number, scale: number, elder: boolean?): number
	local lo, hi = shape.height[1], shape.height[2]
	local jitter = Kit.rng(seed + 3):range(-1, 1)
	local function band(s: number): number
		local u = math.clamp((s - TreeGen.SizeLo) / (TreeGen.SizeHi - TreeGen.SizeLo), 0, 1)
		return lo + (hi - lo) * (0.06 + 0.88 * u + 0.05 * jitter)
	end
	if elder then
		return math.min(ForestData.Elder.maxHeight, band(1) * scale)
	elseif scale > TreeGen.SizeHi then
		return band(TreeGen.SizeHi) * scale / TreeGen.SizeHi
	elseif scale < TreeGen.SizeLo then
		return band(TreeGen.SizeLo) * scale / TreeGen.SizeLo
	end
	return band(scale)
end

---------------------------------------------------------------------------
-- Building: a topology from the rng, laid out at a stretch k
---------------------------------------------------------------------------

-- A section before it's laid out: its direction, its roll about its own
-- axis, and its length before the stretch.
type Proto = {
	id: number,
	parent: number?,
	children: { number },
	depth: number,
	dir: Vector3,
	yaw: number,
	length: number,
	thickness: number,
}

-- The laid-out sections: frames, tops, axes.
type Layout = { cf: { CFrame }, top: { Vector3 }, length: { number } }

-- The details (non-leaf dress) a wood always carries, and how many parts.
local function detailParts(shape: Shape): number
	local n = (shape.flares or 0) + (shape.barkMarks or 0) + (shape.cracks or 0) + (shape.veins or 0)
	if shape.canopy == "fronds" then
		n += (shape.fronds or 0) * 2 + (shape.coconuts or 0) + (shape.rings or 0)
	elseif shape.canopy == "wisps" then
		n += (shape.wisps or 0) * 2 + (shape.pods or 0) * 2
	end
	return n
end

local function isConifer(shape: Shape): boolean
	return shape.canopy == "tiers" or shape.canopy == "snowtiers"
end

local function trunkProtos(shape: Shape, scale: number, rng: Rng): { Proto }
	local out: { Proto } = {}
	local n = shape.trunkSegments
	local segment = shape.trunkLength * scale / n
	local twist = (shape.twistiness or 0) / 2
	local leanAz = rng:range(0, math.pi * 2)
	local dir = UP
	local t = shape.trunkThickness * scale
	for i = 1, n do
		if shape.lean then
			-- A palm bends more the higher it gets (its foot stands upright).
			local h = shape.lean * 3 * (i - 1) / math.max(1, n - 1)
			dir = Vector3.new(math.cos(leanAz) * h, 1, math.sin(leanAz) * h).Unit
		elseif i > 1 and twist > 0 then
			dir = tip(dir, deg(rng:range(0, twist)), rng:range(0, math.pi * 2), perpendicular(dir))
			-- The trunk never wanders far from upright.
			dir = (dir + UP * 0.6).Unit
		end
		table.insert(out, {
			id = i,
			parent = if i > 1 then i - 1 else nil,
			children = {},
			depth = i - 1,
			dir = dir,
			yaw = deg(rng:range(-10, 10)),
			length = segment,
			thickness = t,
		})
		if i > 1 then
			table.insert(out[i - 1].children, i)
		end
		t *= shape.taper
	end
	return out
end

-- Lays the protos out with every length times k, the trunk stretched
-- further if it must to reach `minTrunk` studs up. Children start on their
-- parent's top, sunk in by half their width's tilt so the joint closes.
local function layoutAt(protos: { Proto }, k: number, trunkK: number, trunkSegments: number): Layout
	local cfs: { CFrame } = {}
	local tops: { Vector3 } = {}
	local lengths: { number } = {}
	for i, p in ipairs(protos) do
		local len = p.length * (if p.depth < trunkSegments then trunkK else k)
		local base: Vector3
		local ref: Vector3
		if p.parent then
			local parentCf = cfs[p.parent]
			local pd = parentCf.YVector
			local sin = math.sqrt(math.max(0, 1 - pd:Dot(p.dir) ^ 2))
			base = tops[p.parent] - pd * (p.thickness / 2 * sin)
			ref = parentCf.XVector
		else
			base = Vector3.zero
			ref = Vector3.xAxis
		end
		local cf = frame(base, p.dir, ref, p.yaw)
		cfs[i] = cf
		tops[i] = base + p.dir * len
		lengths[i] = len
	end
	return { cf = cfs, top = tops, length = lengths }
end

local function layout(protos: { Proto }, k: number, trunkSegments: number, minTrunk: number): Layout
	local trunkK = k
	local lay = layoutAt(protos, k, trunkK, trunkSegments)
	local last = math.min(trunkSegments, #protos)
	for _ = 1, 4 do
		local y = lay.top[last].Y
		if minTrunk <= 0 or y >= minTrunk then
			break
		end
		trunkK *= minTrunk / y + 1e-4
		lay = layoutAt(protos, k, trunkK, trunkSegments)
	end
	return lay
end

-- The branches of a broadleaf: breadth first from the trunk's top, so a
-- section cap trims the outer twigs evenly instead of one whole limb.
local function growBranches(
	protos: { Proto },
	shape: Shape,
	look: Look,
	scale: number,
	maxDepth: number,
	cap: number,
	minT: number,
	rng: Rng
)
	local trunkSegments = shape.trunkSegments
	local queue = { #protos }
	local head = 1
	local twist = shape.twistiness or 0
	local jitter = shape.angleJitter or 10
	local angle = shape.branchAngle or 30
	local decay = shape.lengthDecay or { 0.7, 0.8 }
	-- Each branch's end, for the ground check (unstretched, from the base).
	local ends: { [number]: Vector3 } = {}
	local starts: { [number]: Vector3 } = {}
	local pos = Vector3.zero
	for _, p in ipairs(protos) do
		starts[p.id] = pos
		pos += p.dir * p.length
		ends[p.id] = pos
	end
	while head <= #queue do
		local s = protos[queue[head]]
		head += 1
		local level = s.depth - trunkSegments + 1 -- the trunk's top is level 0
		if level >= maxDepth or #protos >= cap or s.thickness < minT then
			continue
		end
		local chance = if shape.splitChance then shape.splitChance[level + 1] or 0 else 0
		local split = rng:next() < chance
		local n = if split then rng:int(shape.minSplits or 2, shape.maxSplits or 2) else 1
		n = math.min(n, cap - #protos)
		if n <= 0 then
			continue
		end
		local ref = perpendicular(s.dir)
		local start = rng:range(0, math.pi * 2)
		-- Away from the trunk, flat: where an outward branch wants to go.
		local flat = Vector3.new(ends[s.id].X, 0, ends[s.id].Z)
		local outward = if flat.Magnitude > 0.05 then flat.Unit else Vector3.zero
		local sides = if split and shape.leader then n - 1 else n
		local side = 0
		for i = 1, n do
			local dir: Vector3
			local thickness: number
			local leading = not split or (shape.leader == true and i == 1)
			if leading then
				-- Carry on: twist noise, plus a crooked wood's elbow.
				local bend = rng:range(0, twist) + (if shape.elbow then rng:range(0.5, 1) * shape.elbow else 0)
				dir = tip(s.dir, deg(bend), rng:range(0, math.pi * 2), ref)
				if shape.leader then
					dir = (dir + UP * 0.8).Unit
				end
				thickness = s.thickness * 0.85
			else
				side += 1
				local a = deg(angle + rng:range(-jitter, jitter))
				local az = start + (side - 1) / sides * math.pi * 2 + rng:range(-0.25, 0.25)
				dir = tip(s.dir, a, az, ref)
				if shape.elbow then
					dir = tip(dir, deg(rng:range(0, shape.elbow) * 0.5), rng:range(0, math.pi * 2), perpendicular(dir))
				end
				-- Reach for the light and out of the crown.
				dir = (dir + UP * look.rise + outward * look.out).Unit
				thickness = s.thickness * (shape.thicknessDecay or 0.7)
			end
			local length = if level == 0
				then (shape.firstBranchLength or s.length) * scale * rng:range(0.88, 1.12)
				else s.length * rng:range(decay[1], decay[2])
			-- Nothing ends near the ground, and nothing points down much.
			if dir.Y < -0.15 then
				dir = Vector3.new(dir.X, -0.15, dir.Z).Unit
			end
			local from = ends[s.id]
			local to = from + dir * length
			if to.Y < TreeGen.MinEndY + thickness then
				continue
			end
			local id = #protos + 1
			table.insert(protos, {
				id = id,
				parent = s.id,
				children = {},
				depth = s.depth + 1,
				dir = dir,
				yaw = rng:range(0, math.pi / 2),
				length = length,
				thickness = thickness,
			})
			table.insert(s.children, id)
			starts[id] = from
			ends[id] = to
			table.insert(queue, id)
		end
	end
end

-- A conifer's spire: one thin section on the trunk's top.
local function addSpire(protos: { Proto }, shape: Shape, scale: number, rng: Rng)
	if not shape.spire then
		return
	end
	local top = protos[#protos]
	local id = #protos + 1
	table.insert(protos, {
		id = id,
		parent = top.id,
		children = {},
		depth = top.depth + 1,
		dir = top.dir,
		yaw = rng:range(0, math.pi / 2),
		length = shape.spire * scale,
		thickness = math.max(0.3 * scale, top.thickness * 0.62),
	})
	table.insert(top.children, id)
end

---------------------------------------------------------------------------
-- Dress
---------------------------------------------------------------------------

-- A point on a section's bark: `along` (0-1) up it, on side `face` (0-3:
-- +X, +Z, -X, -Z), `slide` (-1..1) across that face, `out` past the bark.
-- Returns a frame there whose Y runs up the section and whose -Z points
-- out of the face.
local function onFace(
	cf: CFrame,
	length: number,
	thickness: number,
	along: number,
	face: number,
	slide: number,
	out: number
): CFrame
	local h = thickness / 2
	local a = face * math.pi / 2
	local normal = Vector3.new(math.cos(a), 0, math.sin(a))
	local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
	local p = Vector3.new(0, along * length, 0) + normal * (h + out) + tangent * (slide * h)
	-- Local axes: X along the face, Y up the section, Z into the bark.
	return cf * CFrame.fromMatrix(p, tangent, UP, -normal)
end

-- Root flares round the first section's foot: wedges against each side,
-- their slopes running down and out (the wedge's -Z is its low edge).
local function flares(root: Section, count: number, rng: Rng): { Dress }
	local out: { Dress } = {}
	local t = root.thickness
	local start = rng:range(0, math.pi * 2)
	for i = 1, count do
		local a = start + (i - 1) / count * math.pi * 2 + rng:range(-0.2, 0.2)
		-- The distance from the axis to the square's side in that direction.
		local reach = t / 2 / math.max(math.abs(math.cos(a)), math.abs(math.sin(a)))
		local tall = t * rng:range(0.55, 0.85)
		local long = t * rng:range(0.5, 0.75)
		local wide = t * rng:range(0.34, 0.46)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local pos = dir * (reach + long / 2 - 0.12) + UP * (tall / 2 - 0.3)
		-- -Z points out (the wedge's low edge), Y up.
		local cf = root.cf * CFrame.fromMatrix(pos, UP:Cross(-dir), UP, -dir)
		table.insert(out, {
			kind = "flare",
			section = root.id,
			cf = cf,
			size = Vector3.new(wide, tall, long),
			parts = 1,
			seed = rng:int(1, 1e6),
		})
	end
	return out
end

-- Strips on the trunk's bark (birch marks, ember cracks, lumen veins),
-- spread over the trunk's sections and faces.
local function barkStrips(
	sections: { Section },
	trunkSegments: number,
	kind: string,
	count: number,
	rng: Rng
): { Dress }
	local out: { Dress } = {}
	for i = 1, count do
		local s = sections[(i - 1) % trunkSegments + 1]
		local t = s.thickness
		local w: number, h: number, along: number
		if kind == "mark" then
			w, h = t * rng:range(0.35, 0.6), rng:range(0.14, 0.3)
			along = rng:range(0.12, 0.9)
		elseif kind == "crack" then
			w, h = math.max(0.16, t * 0.09), math.min(s.length * 0.7, rng:range(2.2, 4.2) * t / 2)
			along = rng:range(0.42, 0.58)
		else -- vein
			w, h = math.max(0.14, t * 0.07), s.length * rng:range(0.5, 0.8)
			along = rng:range(0.4, 0.6)
		end
		local face = (i + rng:int(0, 3)) % 4
		local cf = onFace(s.cf, s.length, t, along, face, rng:range(-0.45, 0.45), 0.03)
		if kind ~= "mark" then
			cf *= CFrame.Angles(0, 0, rng:range(-0.3, 0.3))
		end
		table.insert(out, {
			kind = kind,
			section = s.id,
			cf = cf,
			size = Vector3.new(w, h, 0.1),
			parts = 1,
			seed = rng:int(1, 1e6),
		})
	end
	return out
end

-- Leaf masses: tips close together share one, then the closest masses
-- merge until each can have `minParts` of the `leafBudget`.
-- `along` (0-1) and `side` (in the section's own axes) place a filler
-- mass partway up its one section instead of on its top.
type Group = { tips: { number }, at: Vector3, along: number?, side: Vector3? }

local function groupTips(
	sections: { Section },
	tips: { number },
	mergeDist: number,
	minParts: number,
	leafBudget: number
): { Group }
	local groups: { Group } = {}
	for _, id in ipairs(tips) do
		local s = sections[id]
		local top = s.cf * Vector3.new(0, s.length, 0)
		local best, bestD = nil :: Group?, mergeDist
		for _, g in ipairs(groups) do
			local d = (g.at - top).Magnitude
			if d < bestD then
				best, bestD = g, d
			end
		end
		if best then
			table.insert(best.tips, id)
			best.at = best.at + (top - best.at) / #best.tips
		else
			table.insert(groups, { tips = { id }, at = top })
		end
	end
	while #groups > 1 and #groups * minParts > leafBudget do
		local bi, bj, bd = 1, 2, math.huge
		for i = 1, #groups do
			for j = i + 1, #groups do
				local d = (groups[i].at - groups[j].at).Magnitude
				if d < bd then
					bi, bj, bd = i, j, d
				end
			end
		end
		local a, b = groups[bi], groups[bj]
		local na, nb = #a.tips, #b.tips
		a.at = (a.at * na + b.at * nb) / (na + nb)
		for _, id in ipairs(b.tips) do
			table.insert(a.tips, id)
		end
		table.remove(groups, bj)
	end
	return groups
end

-- The tip a group hangs on: the one whose top is nearest its centre.
local function anchorOf(sections: { Section }, g: Group, at: Vector3): number
	local best, bestD = g.tips[1], math.huge
	for _, id in ipairs(g.tips) do
		local s = sections[id]
		local d = ((s.cf * Vector3.new(0, s.length, 0)) - at).Magnitude
		if d < bestD then
			best, bestD = id, d
		end
	end
	return best
end

-- The leaf mass for a group of tips, at the current layout: a box round
-- the tips' tops, at least one cluster (`size`) across, at most maxGrow.
local function clusterFor(
	sections: { Section },
	g: Group,
	size: number,
	look: Look,
	parts: number,
	seed: number,
	kind: string
): Dress
	local lo = Vector3.one * math.huge
	local hi = -lo
	for _, id in ipairs(g.tips) do
		local s = sections[id]
		local side = g.side or Vector3.zero
		local p = s.cf * Vector3.new(side.X, s.length * (g.along or 1), side.Z)
		lo = lo:Min(p)
		hi = hi:Max(p)
	end
	local span = hi - lo
	local w = math.min(size * look.maxGrow, size + math.max(span.X, span.Z) * 0.8)
	local tall = math.min(w * look.clusterY * 1.3, size * look.clusterY + span.Y * 0.7)
	local box = Vector3.new(w, tall, w)
	local mid = (lo + hi) / 2
	local at = mid + UP * (if g.along then 0 else box.Y * look.lift)
	local yaw = Kit.rng(seed):range(0, math.pi * 2)
	return {
		kind = kind,
		section = anchorOf(sections, g, at),
		cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0),
		size = box,
		parts = parts,
		seed = seed,
		tips = table.clone(g.tips),
		grain = size * 0.62,
	}
end

-- A conifer's cone tiers (and a frostwood's snow caps) up the trunk from
-- firstTierAt to just over the spire's top. Side counts drop on the top
-- tiers (never under 3) until the tree fits its budget.
local function coniferDress(sections: { Section }, shape: Shape, scale: number, room: number, rng: Rng): { Dress }
	local out: { Dress } = {}
	local spire = sections[#sections]
	local apex = (spire.cf * Vector3.new(0, spire.length, 0)).Y + 0.3 * scale
	local n = shape.tiers or 4
	local radius = shape.tierRadius or { 8, 3 }
	local tierHeight = (shape.tierHeight or radius[1] * 0.95) * scale
	local base0 = (shape.firstTierAt or 10) * scale
	local capsOn = if shape.canopy == "snowtiers" then shape.snowCaps or 0 else 0
	-- A capped tier's cap has its sides (and turn and jitter), so it wraps it.
	local sides: { number } = {}
	for i = 1, n do
		sides[i] = shape.tierSides or 5
	end
	local function total(): number
		local sum = 0
		for i = 1, n do
			sum += sides[i] * 2 * (if i > n - capsOn then 2 else 1)
		end
		return sum
	end
	local i = n
	while total() > room and i >= 1 do
		if sides[i] > 3 then
			sides[i] -= 1
		end
		i -= 1
		if i < 1 then
			i = n
			if sides[n] <= 3 and sides[1] <= 3 then
				break
			end
		end
	end
	-- Each tier overlaps the one under it by TierOverlap of its height, and
	-- the stack fills the trunk from firstTierAt to the apex: the cones are
	-- as tall as that takes (at least tierHeight).
	local shrink: { number } = {}
	local sum = 0
	for k = 1, n do
		shrink[k] = 1 - 0.07 * (k - 1)
		sum += shrink[k] * (if k < n then 1 - TreeGen.TierOverlap else 1)
	end
	local h0 = math.max(tierHeight * 0.6, (apex - base0) / sum)
	local heights: { number } = {}
	local bases: { number } = {}
	local y = base0
	for k = 1, n do
		heights[k] = h0 * shrink[k]
		bases[k] = y
		y += heights[k] * (1 - TreeGen.TierOverlap)
	end
	-- The top tier ends on the apex exactly.
	bases[n] = apex - heights[n]
	local trunkTop = shape.trunkSegments
	for k = 1, n do
		local u = if n > 1 then (k - 1) / (n - 1) else 0
		local baseY = bases[k]
		local r = (radius[1] + (radius[2] - radius[1]) * u) * scale
		-- The trunk section this tier's base sits on.
		local on = trunkTop
		for id = 1, trunkTop do
			local s = sections[id]
			local y0 = s.cf.Position.Y
			local y1 = (s.cf * Vector3.new(0, s.length, 0)).Y
			if baseY >= y0 and baseY < y1 then
				on = id
				break
			end
		end
		local axis = sections[on]
		local p = axis.cf.Position + axis.cf.YVector * ((baseY - axis.cf.Position.Y) / math.max(axis.cf.YVector.Y, 0.2))
		local cf = CFrame.new(p) * CFrame.Angles(0, rng:range(0, math.pi * 2), 0)
		local tierSeed = rng:int(1, 1e6)
		table.insert(out, {
			kind = "tier",
			section = on,
			cf = cf,
			size = Vector3.new(r * 2, heights[k], r * 2),
			parts = sides[k] * 2,
			sides = sides[k],
			seed = tierSeed,
		})
		if k > n - capsOn then
			-- A snow cap over the tier's upper part, a hair proud of it so it
			-- lies on the tier, blue showing below it. Under the next tier's
			-- skirt only its visible band shows, so it reads as snow lying on
			-- each layer; the top tier's covers its tip.
			local h = heights[k]
			local capFrom = h * (if k == n then 0.5 else 0.34)
			local capR = r * (1 - capFrom / h) * 1.06
			table.insert(out, {
				kind = "cap",
				section = on,
				cf = cf * CFrame.new(0, capFrom, 0),
				size = Vector3.new(capR * 2, h - capFrom + 0.15 * scale, capR * 2),
				parts = sides[k] * 2,
				sides = sides[k],
				seed = tierSeed,
			})
		end
	end
	return out
end

-- A palm's crown: fronds arching up and out, then drooping; coconuts under
-- them; rings at the trunk's joints.
local function palmDress(sections: { Section }, shape: Shape, scale: number, rng: Rng): { Dress }
	local out: { Dress } = {}
	local crown = sections[shape.trunkSegments]
	local top = crown.cf * Vector3.new(0, crown.length, 0)
	local n = shape.fronds or 7
	local len = (shape.frondLength or 10) * scale
	local start = rng:range(0, math.pi * 2)
	for i = 1, n do
		local a = start + (i - 1) / n * math.pi * 2 + rng:range(-0.18, 0.18)
		local flat = Vector3.new(math.cos(a), 0, math.sin(a))
		local droop = rng:range(0.28, 0.45)
		local bend = top + flat * len * 0.42 + UP * len * rng:range(0.12, 0.2)
		local tipAt = top + flat * len * 0.88 - UP * len * droop
		table.insert(out, {
			kind = "frond",
			section = crown.id,
			cf = CFrame.new(top),
			size = Vector3.new(1.7 * scale, 0.16, len),
			parts = 2,
			seed = rng:int(1, 1e6),
			points = { top, bend, tipAt },
		})
	end
	for i = 1, shape.coconuts or 0 do
		local a = start + i * 2.1
		local d = 0.95 * scale
		local at = top
			+ Vector3.new(math.cos(a) * crown.thickness * 0.42, -0.55 * scale, math.sin(a) * crown.thickness * 0.42)
		table.insert(out, {
			kind = "coconut",
			section = crown.id,
			cf = CFrame.new(at),
			size = Vector3.one * d,
			parts = 1,
			seed = rng:int(1, 1e6),
		})
	end
	local rings = shape.rings or 0
	for i = 1, rings do
		-- On the joints between the upper segments.
		local s = sections[math.clamp(shape.trunkSegments - rings + i - 1, 1, shape.trunkSegments)]
		local t = s.thickness * 1.14
		table.insert(out, {
			kind = "ring",
			section = s.id,
			cf = s.cf * CFrame.new(0, s.length - 0.12 * scale, 0),
			size = Vector3.new(t, 0.3 * scale, t),
			parts = 1,
			seed = rng:int(1, 1e6),
		})
	end
	return out
end

-- The section tips (no children), outermost first in build order.
local function tipsOf(sections: { Section }): { number }
	local out: { number } = {}
	for _, s in ipairs(sections) do
		if #s.children == 0 and s.depth > 0 then
			table.insert(out, s.id)
		end
	end
	return out
end

-- A tiered crown (lumenwood): flat glowing discs stacked up the crown from
-- the trunk's top to the highest tip, each as wide as the limbs at its
-- height (narrowing up), hung on the section whose top is nearest.
local function layerDress(
	sections: { Section },
	shape: Shape,
	look: Look,
	scale: number,
	budget: number,
	seed: number
): { Dress }
	local out: { Dress } = {}
	local layers = math.max(1, look.layers)
	local trunkTop = TreeGen.TopOf(sections[shape.trunkSegments])
	local lo, hi = trunkTop.Y, trunkTop.Y
	for _, s in ipairs(sections) do
		hi = math.max(hi, TreeGen.TopOf(s).Y)
	end
	local span = math.max(hi - lo, 1)
	local size = (shape.leafSize or 6) * scale * look.size
	local left = budget
	for l = 1, layers do
		local u = if layers > 1 then (l - 1) / (layers - 1) else 1
		local y = lo + span * (0.08 + 0.9 * u)
		-- The limbs near this height: how far out they reach.
		local reach = 0
		local sum, n = Vector3.zero, 0
		for _, s in ipairs(sections) do
			if s.depth >= shape.trunkSegments then
				local a, b = s.cf.Position, TreeGen.TopOf(s)
				for _, p in ipairs({ a, b, (a + b) / 2 }) do
					if math.abs(p.Y - y) < span / layers then
						reach = math.max(reach, Vector3.new(p.X, 0, p.Z).Magnitude)
						sum += p
						n += 1
					end
				end
			end
		end
		local centre = if n > 0 then Vector3.new(sum.X / n * 0.5, y, sum.Z / n * 0.5) else Vector3.new(0, y, 0)
		local w = math.clamp(reach * 2 + size * 0.5, size * 0.9, size * look.maxGrow) * (1 - 0.26 * (l - 1))
		local box = Vector3.new(w, math.min(w * look.clusterY, size * 0.3), w)
		local parts = math.min(look.maxParts, math.floor(left / (layers - l + 1)))
		left -= parts
		-- The section whose top is nearest the disc's centre.
		local best, bestD = sections[shape.trunkSegments].id, math.huge
		for _, s in ipairs(sections) do
			local d = (TreeGen.TopOf(s) - centre).Magnitude
			if s.depth >= shape.trunkSegments - 1 and d < bestD then
				best, bestD = s.id, d
			end
		end
		local dseed = seed * 31 + l
		table.insert(out, {
			kind = "leaves",
			section = best,
			cf = CFrame.new(centre) * CFrame.Angles(0, Kit.rng(dseed):range(0, math.pi * 2), 0),
			size = box,
			parts = parts,
			seed = dseed,
			glow = l % 2 == 1,
			flat = true,
			tips = { best },
		})
	end
	return out
end

-- Gloamwood: violet wisps on some tips, glowing pods hanging from others.
local function wispDress(sections: { Section }, shape: Shape, scale: number, rng: Rng): { Dress }
	local out: { Dress } = {}
	local tips = tipsOf(sections)
	-- Highest tips first, so the wisps crown the tree.
	table.sort(tips, function(a: number, b: number): boolean
		local sa, sb = sections[a], sections[b]
		return (sa.cf * Vector3.new(0, sa.length, 0)).Y > (sb.cf * Vector3.new(0, sb.length, 0)).Y
	end)
	local size = TreeGen.WispSize * scale
	for i = 1, math.min(shape.wisps or 0, #tips) do
		local s = sections[tips[i]]
		local top = s.cf * Vector3.new(0, s.length, 0)
		table.insert(out, {
			kind = "wisp",
			section = s.id,
			cf = CFrame.new(top + UP * size * 0.15) * CFrame.Angles(0, rng:range(0, math.pi * 2), 0),
			size = Vector3.new(size, size * 0.8, size),
			parts = 2,
			seed = rng:int(1, 1e6),
			tips = { s.id },
		})
	end
	local pods = shape.pods or 0
	local used = 0
	for i = #tips, 1, -1 do
		if used >= pods then
			break
		end
		local s = sections[tips[i]]
		local top = s.cf * Vector3.new(0, s.length, 0)
		local d = 0.85 * scale
		local stem = 1.2 * scale
		if top.Y - stem - d > 1.5 then
			used += 1
			table.insert(out, {
				kind = "pod",
				section = s.id,
				cf = CFrame.new(top - UP * (stem + d / 2)),
				size = Vector3.new(d, d + stem, d),
				parts = 2,
				seed = rng:int(1, 1e6),
			})
		end
	end
	return out
end

-- The top of a dress entry (studs above the base).
local function dressTop(d: Dress): number
	if d.points then
		local top = -math.huge
		for _, p in ipairs(d.points) do
			top = math.max(top, p.Y + d.size.Y)
		end
		return top
	elseif d.kind == "tier" or d.kind == "cap" then
		return d.cf.Position.Y + d.size.Y
	end
	local cf, s = d.cf, d.size
	return cf.Position.Y
		+ (math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z) / 2
end

-- How far a dress entry reaches out from the trunk's axis.
local function dressReach(d: Dress): number
	if d.points then
		local far = 0
		for _, p in ipairs(d.points) do
			far = math.max(far, Vector3.new(p.X, 0, p.Z).Magnitude + d.size.X / 2)
		end
		return far
	elseif d.kind == "tier" or d.kind == "cap" then
		local p = d.cf.Position
		return Vector3.new(p.X, 0, p.Z).Magnitude + d.size.X / 2
	end
	local p = d.cf.Position
	return Vector3.new(p.X, 0, p.Z).Magnitude + math.max(d.size.X, d.size.Z) / 2
end

local function sectionTop(s: Section): number
	local h = s.thickness / 2
	local top = -math.huge
	for _, y in ipairs({ 0, s.length }) do
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				top = math.max(top, (s.cf * Vector3.new(sx * h, y, sz * h)).Y)
			end
		end
	end
	return top
end

-- Height and crown width of a dressed tree.
local function measure(sections: { Section }): (number, number)
	local top, reach = 0, 0
	for _, s in ipairs(sections) do
		top = math.max(top, sectionTop(s))
		local e = s.cf * Vector3.new(0, s.length, 0)
		reach = math.max(reach, Vector3.new(e.X, 0, e.Z).Magnitude + s.thickness / 2)
		for _, d in ipairs(s.dress) do
			if d.kind ~= "flare" then
				top = math.max(top, dressTop(d))
				reach = math.max(reach, dressReach(d))
			end
		end
	end
	return top, reach * 2
end

---------------------------------------------------------------------------
-- The skeleton
---------------------------------------------------------------------------

local function shapeOf(woodId: string): Shape
	local def = WoodData.Get(woodId)
	local v2 = def and def.v2
	local shape = v2 and v2.shape
	assert(shape, "TreeGen: no v2 shape for wood " .. tostring(woodId))
	return shape
end

-- Builds every section and its dress from the protos at stretch k.
-- `groups` (the leaf clusters' tips and parts) is decided once at k = 1 so
-- the stretch can't regroup them.
type Plan = {
	shape: Shape,
	look: Look,
	scale: number,
	seed: number,
	protos: { Proto },
	minTrunk: number,
	groups: { Group }?,
	groupParts: { number }?,
	budget: number,
}

local function dressUp(plan: Plan, k: number): { Section }
	local shape = plan.shape
	local lay = layout(plan.protos, k, shape.trunkSegments, plan.minTrunk)
	local sections: { Section } = {}
	for i, p in ipairs(plan.protos) do
		sections[i] = {
			id = p.id,
			parent = p.parent,
			children = table.clone(p.children),
			depth = p.depth,
			cf = lay.cf[i],
			length = lay.length[i],
			thickness = p.thickness,
			dress = {},
		}
	end
	local rng = Kit.rng(plan.seed + 2)
	local all: { Dress } = {}
	local function add(list: { Dress })
		for _, d in ipairs(list) do
			table.insert(all, d)
		end
	end
	if (shape.flares or 0) > 0 then
		add(flares(sections[1], shape.flares or 0, rng))
	end
	if shape.barkMarks then
		add(barkStrips(sections, shape.trunkSegments, "mark", shape.barkMarks, rng))
	end
	if shape.cracks then
		add(barkStrips(sections, shape.trunkSegments, "crack", shape.cracks, rng))
	end
	if shape.veins then
		add(barkStrips(sections, shape.trunkSegments, "vein", shape.veins, rng))
	end
	if isConifer(shape) then
		add(coniferDress(sections, shape, plan.scale, plan.budget - #sections - detailParts(shape), rng))
	elseif shape.canopy == "fronds" then
		add(palmDress(sections, shape, plan.scale, rng))
	elseif shape.canopy == "wisps" then
		add(wispDress(sections, shape, plan.scale, rng))
	elseif shape.canopy == "glowtiers" then
		add(layerDress(sections, shape, plan.look, plan.scale, plan.budget - #sections - detailParts(shape), plan.seed))
	elseif plan.groups and plan.groupParts then
		local parts = plan.groupParts
		local masses: { Dress } = {}
		for i, g in ipairs(plan.groups) do
			local d = clusterFor(
				sections,
				g,
				(shape.leafSize or 6) * plan.scale * plan.look.size,
				plan.look,
				parts[i],
				plan.seed * 31 + i,
				"leaves"
			)
			if shape.canopy == "embers" then
				d.glow = true
			elseif shape.canopy == "glowtiers" then
				d.glow = i % 2 == 1
			end
			table.insert(masses, d)
		end
		-- A flat-topped crown: every mass pulled toward the masses' mean height.
		local f = plan.look.flatten
		if f > 0 and #masses > 1 then
			local mean = 0
			for _, d in ipairs(masses) do
				mean += d.cf.Position.Y
			end
			mean /= #masses
			for _, d in ipairs(masses) do
				local y = d.cf.Position.Y
				d.cf = d.cf + Vector3.new(0, (mean - y) * f, 0)
			end
		end
		for _, d in ipairs(masses) do
			table.insert(all, d)
		end
	end
	for _, d in ipairs(all) do
		table.insert(sections[d.section].dress, d)
	end
	return sections
end

-- Decides the leaf masses: which tips share one; then, with parts to
-- spare, more on branch joints (and along a leader) far from the others,
-- so the crown fills in; and how many parts each gets (the budget shared
-- out, massParts to maxParts each).
local function planLeaves(plan: Plan)
	local shape = plan.shape
	local look = plan.look
	local sections = dressUp(plan, 1)
	local tips = tipsOf(sections)
	local leafBudget = plan.budget - #sections - detailParts(shape)
	local size = (shape.leafSize or 6) * plan.scale * look.size
	local groups = groupTips(sections, tips, size * look.merge, look.massParts, leafBudget)
	-- Joints from the top down: the trunk's top and every branch that forks.
	local fills: { Group } = {}
	for _, s in ipairs(sections) do
		if #s.children > 0 and s.depth >= shape.trunkSegments - 1 then
			table.insert(fills, { tips = { s.id }, at = TreeGen.TopOf(s) })
		end
	end
	-- A leader wood's leaves hug the leader too, left and right in turn,
	-- from the trunk's last segment up.
	if shape.leader then
		local id: number? = shape.trunkSegments
		local turn = 1
		while id do
			local s = sections[id]
			local off = Vector3.new((s.thickness * 0.6 + size * 0.2) * turn, 0, s.thickness * 0.4 * turn)
			table.insert(fills, {
				tips = { s.id },
				at = s.cf * Vector3.new(off.X, s.length * 0.55, off.Z),
				along = 0.55,
				side = off,
			})
			turn = -turn
			id = s.children[1]
		end
	end
	table.sort(fills, function(a: Group, b: Group): boolean
		return a.at.Y > b.at.Y
	end)
	for _, f in ipairs(fills) do
		if (#groups + 1) * look.massParts > leafBudget then
			break
		end
		local near = math.huge
		for _, g in ipairs(groups) do
			near = math.min(near, (g.at - f.at).Magnitude)
		end
		if near >= size * look.fill then
			table.insert(groups, f)
		end
	end
	-- Share the budget out, the biggest masses first.
	local counts: { number } = {}
	local order: { number } = {}
	for i in ipairs(groups) do
		counts[i] = 0
		table.insert(order, i)
	end
	table.sort(order, function(a: number, b: number): boolean
		local na, nb = #groups[a].tips, #groups[b].tips
		if na ~= nb then
			return na > nb
		end
		return a < b
	end)
	local left = leafBudget
	local progress = true
	while left > 0 and progress do
		progress = false
		for _, i in ipairs(order) do
			if left > 0 and counts[i] < look.maxParts then
				counts[i] += 1
				left -= 1
				progress = true
			end
		end
	end
	plan.groups = groups
	plan.groupParts = counts
end

-- The stretch k at which top(k) lands on `target` (within 0.02 studs):
-- secant steps from a proportional guess, then, if those wander off,
-- regula falsi (Illinois) bracketed in [0.5, 2.2]. top(k) rises with k.
local function solveStretch(topAt: (number) -> number, target: number): number
	local TOL = 0.02
	local k0, f0 = 1, topAt(1) - target
	if math.abs(f0) < TOL then
		return k0
	end
	local k1 = math.clamp(target / (f0 + target), 0.5, 2.2)
	local f1 = topAt(k1) - target
	for _ = 1, 6 do
		if math.abs(f1) < TOL then
			return k1
		end
		local denom = f1 - f0
		if math.abs(denom) < 1e-9 then
			break
		end
		local k2 = math.clamp(k1 - f1 * (k1 - k0) / denom, 0.5, 2.2)
		k0, f0 = k1, f1
		k1, f1 = k2, topAt(k2) - target
	end
	if math.abs(f1) < TOL then
		return k1
	end
	local lo, hi = 0.5, 2.2
	local flo, fhi = topAt(lo) - target, topAt(hi) - target
	if flo >= 0 then
		return lo
	elseif fhi <= 0 then
		return hi
	end
	local k = 1
	local side = 0
	for _ = 1, 24 do
		k = (lo * fhi - hi * flo) / (fhi - flo)
		local fk = topAt(k) - target
		if math.abs(fk) < TOL then
			break
		elseif fk < 0 then
			lo, flo = k, fk
			if side == -1 then
				fhi /= 2
			end
			side = -1
		else
			hi, fhi = k, fk
			if side == 1 then
				flo /= 2
			end
			side = 1
		end
	end
	return k
end

-- One try at a mature tree: the topology from Kit.rng(seed + 1 + salt),
-- then the stretch that lands the top on the target height.
local function attempt(woodId: string, seed: number, scale: number, elder: boolean, salt: number): Skeleton
	local shape = shapeOf(woodId)
	local look = LOOKS[woodId] or DEFAULT_LOOK
	local budget = TreeGen.Budgets[woodId] or TreeGen.DefaultBudget
	local rng = Kit.rng(seed + 1 + salt)
	local protos = trunkProtos(shape, scale, rng)
	local maxDepth = shape.maxDepth
	if elder and maxDepth > 0 then
		maxDepth += ForestData.Elder.depthBonus
	end
	local minTrunk = 0
	if isConifer(shape) then
		addSpire(protos, shape, scale, rng)
	elseif maxDepth > 0 then
		local details = detailParts(shape)
		local leafShare = if shape.canopy == "wisps" then 0 else look.leafShare
		local room = budget - details
		local cap = math.min(shape.maxSections, TreeGen.HardCap, room - math.ceil(room * leafShare))
		local minT = (shape.minThickness or 0.5) * (if elder then 1 else scale)
		growBranches(protos, shape, look, scale, maxDepth, cap, minT, rng)
		minTrunk = TreeGen.FirstBranchMin
	end
	local plan: Plan = {
		shape = shape,
		look = look,
		scale = scale,
		seed = seed + salt,
		protos = protos,
		minTrunk = minTrunk,
		budget = budget,
	}
	local leafy = not isConifer(shape)
		and shape.canopy ~= "fronds"
		and shape.canopy ~= "wisps"
		and shape.canopy ~= "glowtiers"
	if leafy then
		planLeaves(plan)
	end
	-- Stretch the lengths until the top lands on the target height.
	local target = TreeGen.TargetHeight(shape, seed, scale, elder)
	local function topAt(k: number): number
		local h = measure(dressUp(plan, k))
		return h
	end
	local k = solveStretch(topAt, target)
	local sections = dressUp(plan, k)
	local height, width = measure(sections)
	return {
		woodId = woodId,
		seed = seed,
		scale = scale,
		stage = 1,
		elder = elder,
		trunkSegments = shape.trunkSegments,
		maxDepth = maxDepth,
		sections = sections,
		height = height,
		width = width,
		stretch = k,
	}
end

-- How wide the leaves spread for the tree's height: the larger of the
-- crown's X and Z extents, taking each leaf mass at CrownInset of its box
-- (its parts reach most of the way out), over the height.
function TreeGen.CrownRatio(skel: Skeleton): number
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, s in ipairs(skel.sections) do
		for _, d in ipairs(s.dress) do
			if d.kind == "leaves" or d.kind == "wisp" then
				local half = d.size * (TreeGen.CrownInset / 2)
				lo = lo:Min(d.cf.Position - half)
				hi = hi:Max(d.cf.Position + half)
			end
		end
	end
	if lo.X > hi.X then
		return 0
	end
	local span = hi - lo
	return math.max(span.X, span.Z) / math.max(skel.height, 1e-6)
end
TreeGen.CrownInset = 0.8

-- The silhouette each leafy wood must keep (V2_PLAN §3j, with a margin for
-- how far the parts reach in their boxes): crown width over height.
TreeGen.CrownBands = {
	oak = { 0.78, math.huge },
	maple = { 0.95, math.huge },
	birch = { 0, 0.42 },
} :: { [string]: { number } }
TreeGen.Rerolls = 6

-- A mature tree of `woodId` (see the header). A wood with a silhouette band
-- rerolls a seed whose crown misses it (up to Rerolls times, keeping the
-- closest), the way the plan rejects bad limbs.
function TreeGen.Skeleton(woodId: string, seed: number, scale: number, opts: Options?): Skeleton
	local elder = opts ~= nil and opts.elder == true
	local band = TreeGen.CrownBands[woodId]
	local best = attempt(woodId, seed, scale, elder, 0)
	if not band then
		return best
	end
	local function miss(skel: Skeleton): number
		local r = TreeGen.CrownRatio(skel)
		return math.max(0, band[1] - r, r - band[2])
	end
	local bestMiss = miss(best)
	local try = 1
	while bestMiss > 0 and try <= TreeGen.Rerolls do
		local skel = attempt(woodId, seed, scale, elder, try * 7919)
		local m = miss(skel)
		if m < bestMiss then
			best, bestMiss = skel, m
		end
		try += 1
	end
	return best
end

-- The v2 scale of a size class by its name ("small", "normal", "large"; an
-- unknown name is normal).
function TreeGen.ScaleFor(sizeName: string): number
	return TreeGen.SizeScales[sizeName] or 1
end

-- Sections plus every dress part: what FromSkeleton will build.
function TreeGen.PartCount(skel: Skeleton): number
	local n = 0
	for _, s in ipairs(skel.sections) do
		n += 1
		for _, d in ipairs(s.dress) do
			n += d.parts
		end
	end
	return n
end

-- The top of a section (its axis's end), in the tree's space.
function TreeGen.TopOf(s: Section): Vector3
	return s.cf * Vector3.new(0, s.length, 0)
end

---------------------------------------------------------------------------
-- Growth stages
---------------------------------------------------------------------------

local function scaledCf(cf: CFrame, s: number): CFrame
	return CFrame.new(cf.Position * s) * cf.Rotation
end

local function scaledDress(d: Dress, s: number, section: number): Dress
	local points: { Vector3 }? = nil
	if d.points then
		local p: { Vector3 } = {}
		for i, v in ipairs(d.points) do
			p[i] = v * s
		end
		points = p
	end
	return {
		kind = d.kind,
		section = section,
		cf = scaledCf(d.cf, s),
		size = d.size * s,
		parts = d.parts,
		seed = d.seed,
		sides = d.sides,
		glow = d.glow,
		flat = d.flat,
		grain = d.grain,
		points = points,
		tips = d.tips,
	}
end

-- Leaves on a young tree are bigger for its size than on an old one.
function TreeGen.StageLeafScale(s: number): number
	return math.clamp(0.42 + 0.58 * s, 0, 1)
end

-- The tree `skel`, `s` of the way grown (TreeGen.Stages; 1 is the tree
-- itself). Sections deeper than (maxDepth + trunkSegments) * s are hidden,
-- every length, thickness and position shrinks by s, and the hidden
-- branches' leaves gather into one cluster on each tip that shows (sized
-- by StageLeafScale). Tiers shrink in place; details on hidden sections go.
function TreeGen.AtStage(skel: Skeleton, s: number): Skeleton
	if s >= 1 then
		return skel
	end
	local limit = (skel.maxDepth + skel.trunkSegments) * s
	local visible: { [number]: boolean } = {}
	for _, sec in ipairs(skel.sections) do
		visible[sec.id] = sec.id == 1 or sec.depth <= limit
	end
	-- Ids stay as they are on the mature tree, packed in order.
	local remap: { [number]: number } = {}
	local out: { Section } = {}
	for _, sec in ipairs(skel.sections) do
		if visible[sec.id] then
			local id = #out + 1
			remap[sec.id] = id
			table.insert(out, {
				id = id,
				parent = if sec.parent then remap[sec.parent] else nil,
				children = {},
				depth = sec.depth,
				cf = scaledCf(sec.cf, s),
				length = sec.length * s,
				thickness = sec.thickness * s,
				dress = {},
			})
		end
	end
	for _, sec in ipairs(out) do
		if sec.parent then
			table.insert(out[sec.parent].children, sec.id)
		end
	end
	-- The visible ancestor of every mature section.
	local function shown(id: number): number
		local cur: number? = id
		while cur and not visible[cur] do
			cur = skel.sections[cur].parent
		end
		return remap[cur or 1]
	end
	local shape = shapeOf(skel.woodId)
	local look = LOOKS[skel.woodId] or DEFAULT_LOOK
	local leafScale = TreeGen.StageLeafScale(s)
	-- Leaf clusters and wisps, gathered by the tip that shows (a cluster
	-- counts for every tip it dressed).
	local gathered: { [number]: Dress } = {}
	local order: { number } = {}
	local leafy = false
	for _, sec in ipairs(skel.sections) do
		for _, d in ipairs(sec.dress) do
			if d.kind == "leaves" or d.kind == "wisp" then
				leafy = leafy or d.kind == "leaves"
				for _, tipId in ipairs(d.tips or { d.section }) do
					local at = shown(tipId)
					local have = gathered[at]
					if have then
						have.parts = math.max(have.parts, d.parts)
						have.glow = have.glow or d.glow
					else
						gathered[at] = scaledDress(d, 1, at)
						table.insert(order, at)
					end
				end
			elseif d.kind == "tier" or d.kind == "cap" or d.kind == "flare" then
				local on = shown(d.section)
				table.insert(out[on].dress, scaledDress(d, s, on))
			elseif d.kind == "frond" or d.kind == "coconut" then
				-- The crown rides down onto the top segment that shows.
				local on = shown(d.section)
				local was = skel.sections[d.section]
				local now = out[on]
				local shift = TreeGen.TopOf(now) - TreeGen.TopOf(was) * s
				local moved = scaledDress(d, s, on)
				moved.cf = moved.cf + shift
				if moved.points then
					for i, p in ipairs(moved.points) do
						moved.points[i] = p + shift
					end
				end
				table.insert(now.dress, moved)
			elseif visible[d.section] then
				table.insert(out[remap[d.section]].dress, scaledDress(d, s, remap[d.section]))
			end
		end
	end
	-- A leafy tree's every tip that shows gets leaves, even one whose
	-- clusters hung on a neighbour's branch.
	if leafy then
		local minParts = (shape.clusterParts or { 3, 4 })[1]
		for _, sec in ipairs(out) do
			if #sec.children == 0 and sec.depth > 0 and not gathered[sec.id] then
				gathered[sec.id] = {
					kind = "leaves",
					section = sec.id,
					cf = CFrame.identity,
					size = Vector3.one,
					parts = minParts,
					seed = skel.seed * 17 + sec.id,
					glow = shape.canopy == "embers",
				}
				table.insert(order, sec.id)
			end
		end
	end
	for _, at in ipairs(order) do
		local d = gathered[at]
		local tipSec = out[at]
		local base = if d.kind == "wisp" then TreeGen.WispSize else (shape.leafSize or 6) * look.size
		local w = base * skel.scale * leafScale
		local box = if d.kind == "wisp" then Vector3.new(w, w * 0.8, w) else Vector3.new(w, w * look.clusterY, w)
		local top = TreeGen.TopOf(tipSec)
		local lift = if d.kind == "wisp" then 0.15 else look.lift
		d.cf = CFrame.new(top + UP * (box.Y * lift)) * d.cf.Rotation
		d.size = box
		d.tips = { at }
		table.insert(tipSec.dress, d)
	end
	-- Never over the mature tree's budget: trim the biggest clusters.
	local budget = TreeGen.Budgets[skel.woodId] or TreeGen.DefaultBudget
	local staged: Skeleton = {
		woodId = skel.woodId,
		seed = skel.seed,
		scale = skel.scale,
		stage = s,
		elder = skel.elder,
		trunkSegments = skel.trunkSegments,
		maxDepth = skel.maxDepth,
		sections = out,
		height = 0,
		width = 0,
		stretch = skel.stretch,
	}
	local over = TreeGen.PartCount(staged) - budget
	while over > 0 do
		local most: Dress? = nil
		for _, at in ipairs(order) do
			local d = gathered[at]
			if d.parts > 2 and (most == nil or d.parts > most.parts) then
				most = d
			end
		end
		if not most then
			break
		end
		most.parts -= 1
		over -= 1
	end
	local height, width = measure(out)
	staged.height = height
	staged.width = width
	return staged
end

return TreeGen
