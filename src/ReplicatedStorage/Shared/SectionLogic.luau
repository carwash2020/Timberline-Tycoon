--!strict
-- SectionLogic: the cut maths of the v2 section trees (V2_PLAN.md §2a, §3d,
-- §3e). Pure, so the specs pin it and SectionTrees / WoodService (M1.3)
-- only wire it to parts:
--   * Required(hardness, sx, sz): the damage that cuts through a section
--     sx by sz studs across: hardness * (sx/U) * (sz/U) * CutK, U being
--     GameConfig.WoodUnit. HitsToCut is that over an axe's damage, rounded up.
--   * ClampHeight(localY, length): where on a section a swing lands, kept
--     CutEdge from either end.
--   * AddHit(cuts, h, damage, userId): a hit within CutWindow of a cut on
--     that section adds to it; otherwise it starts a new one, at most
--     MaxCutsPerSection, a newer one replacing the cut with the least damage.
--   * SplitSection(section, h, newId): the section cut h studs up into its
--     low part (keeps its id and parent) and its high part (newId, takes its
--     children); their volumes add up to the whole.
--   * SplitGraph(graph, id, h, newId): cutting one section of a piece's
--     graph (a tree of sections) always leaves exactly two pieces.
--   * Volume (u³), IsChips (under MinPieceVolume), Value, and Owner (who
--     gets a freed piece: the top contributor to the finishing cut).

local ForestLogic = require(script.Parent.ForestLogic)
local GameConfig = require(script.Parent.GameConfig)

local SectionLogic = {}

-- A section of a piece or a standing tree: what the cut maths reads.
-- (TreeGen.Section fits it.)
export type Node = {
	id: number,
	parent: number?,
	children: { number },
	cf: CFrame, -- bottom centre, Y up the section
	length: number,
	thickness: number,
}

-- A piece's sections, by id.
export type Graph = { [number]: Node }

-- A cut in progress on one section.
export type Cut = {
	height: number, -- studs up from the section's bottom
	damage: number,
	damageBy: { [number]: number }, -- by UserId
}

-- The damage it takes to cut through a section `sx` by `sz` studs across.
function SectionLogic.Required(hardness: number, sx: number, sz: number): number
	local u = GameConfig.WoodUnit
	return hardness * (sx / u) * (sz / u) * GameConfig.CutK
end

-- Swings to cut a square section `thickness` studs a side with `damage` a
-- hit (math.huge when the axe can't dent it).
function SectionLogic.HitsToCut(hardness: number, thickness: number, damage: number): number
	if damage <= 0 then
		return math.huge
	end
	-- A hair under the exact ratio, so 7 / 0.2 is 35 swings, not 36.
	return math.max(1, math.ceil(SectionLogic.Required(hardness, thickness, thickness) / damage - 1e-9))
end

-- Seconds of swinging for `hits` with `cooldown` between them (the first
-- swing lands at once).
function SectionLogic.CutSeconds(hits: number, cooldown: number): number
	return math.max(0, hits - 1) * cooldown
end

-- Where a swing landing `localY` studs from a section's centre (along its
-- length) cuts it, measured from its bottom: kept CutEdge from both ends
-- (the middle of a section too short for that).
function SectionLogic.ClampHeight(localY: number, length: number, edge: number?): number
	local e = edge or GameConfig.CutEdge
	if length <= 2 * e then
		return length / 2
	end
	return math.clamp(localY + length / 2, e, length - e)
end

-- The cut within `window` studs of `h` (the nearest), or nil.
function SectionLogic.FindCut(cuts: { Cut }, h: number, window: number?): number?
	local w = window or GameConfig.CutWindow
	local best: number? = nil
	local bestD = math.huge
	for i, c in ipairs(cuts) do
		local d = math.abs(c.height - h)
		if d <= w + 1e-9 and d < bestD then
			best, bestD = i, d
		end
	end
	return best
end

-- Adds a hit of `damage` by `userId` at height `h` to a section's cuts.
-- Returns the cut it went into, and whether that cut replaced another.
function SectionLogic.AddHit(
	cuts: { Cut },
	h: number,
	damage: number,
	userId: number,
	maxCuts: number?,
	window: number?
): (Cut, boolean)
	local at = SectionLogic.FindCut(cuts, h, window)
	local replaced = false
	local cut: Cut
	if at then
		cut = cuts[at]
	else
		cut = { height = h, damage = 0, damageBy = {} }
		local most = maxCuts or GameConfig.MaxCutsPerSection
		if #cuts >= most then
			-- The cut with the least damage gives way.
			local least, li = math.huge, 1
			for i, c in ipairs(cuts) do
				if c.damage < least then
					least, li = c.damage, i
				end
			end
			cuts[li] = cut
			replaced = true
		else
			table.insert(cuts, cut)
		end
	end
	cut.damage += damage
	cut.damageBy[userId] = (cut.damageBy[userId] or 0) + damage
	return cut, replaced
end

-- Whether a cut's damage has gone through a section that needs `required`.
function SectionLogic.IsThrough(cut: Cut, required: number): boolean
	return cut.damage >= required - 1e-9
end

-- Volume in cubic timber units of a box sx by sy by sz studs.
function SectionLogic.Volume(sx: number, sy: number, sz: number): number
	local u = GameConfig.WoodUnit
	return sx * sy * sz / (u * u * u)
end

-- A section's volume in u³.
function SectionLogic.NodeVolume(node: Node): number
	return SectionLogic.Volume(node.thickness, node.length, node.thickness)
end

-- What `volume` u³ sells for at `price` $/u³.
function SectionLogic.Value(volume: number, price: number): number
	return volume * price
end

-- Too small to keep: it becomes chips.
function SectionLogic.IsChips(volume: number): boolean
	return volume < GameConfig.MinPieceVolume
end

-- The section cut `h` studs up (clamped inside it): `low` keeps its id,
-- parent and bottom; `high` (id `newId`) starts at the cut, has no parent
-- (the cut parted them) and takes the section's children.
function SectionLogic.SplitSection(section: Node, h: number, newId: number): (Node, Node)
	local cut = math.clamp(h, 0, section.length)
	local low: Node = {
		id = section.id,
		parent = section.parent,
		children = {},
		cf = section.cf,
		length = cut,
		thickness = section.thickness,
	}
	local high: Node = {
		id = newId,
		parent = nil,
		children = table.clone(section.children),
		cf = section.cf * CFrame.new(0, cut, 0),
		length = section.length - cut,
		thickness = section.thickness,
	}
	return low, high
end

-- Every id reachable from `start` along parent and child links.
function SectionLogic.Reach(graph: Graph, start: number): { [number]: boolean }
	local seen: { [number]: boolean } = {}
	local stack = { start }
	while #stack > 0 do
		local id = table.remove(stack) :: number
		local n = graph[id]
		if n and not seen[id] then
			seen[id] = true
			if n.parent and graph[n.parent] then
				table.insert(stack, n.parent)
			end
			for _, c in ipairs(n.children) do
				table.insert(stack, c)
			end
		end
	end
	return seen
end

-- Cuts section `id` of `graph` `h` studs up. Returns the two pieces'
-- graphs: A holds the low part and everything still joined to it, B the
-- high part (id `newId`) and everything above it. Every section lands in
-- exactly one; the cut section's children point at the high part after.
-- The graph given isn't changed.
function SectionLogic.SplitGraph(graph: Graph, id: number, h: number, newId: number): (Graph, Graph)
	local s = graph[id]
	assert(s, "SectionLogic.SplitGraph: no section " .. tostring(id))
	assert(graph[newId] == nil, "SectionLogic.SplitGraph: id " .. tostring(newId) .. " is taken")
	local low, high = SectionLogic.SplitSection(s, h, newId)
	local work: Graph = {}
	for k, n in pairs(graph) do
		work[k] = {
			id = n.id,
			parent = n.parent,
			children = table.clone(n.children),
			cf = n.cf,
			length = n.length,
			thickness = n.thickness,
		}
	end
	work[id] = low
	work[newId] = high
	for _, c in ipairs(high.children) do
		local child = work[c]
		if child then
			child.parent = newId
		end
	end
	local inA = SectionLogic.Reach(work, id)
	local inB = SectionLogic.Reach(work, newId)
	local a: Graph, b: Graph = {}, {}
	for k, n in pairs(work) do
		assert(not (inA[k] and inB[k]), "SectionLogic.SplitGraph: the graph had a loop")
		if inA[k] then
			a[k] = n
		elseif inB[k] then
			b[k] = n
		else
			error("SectionLogic.SplitGraph: section " .. tostring(k) .. " wasn't joined to the piece")
		end
	end
	return a, b
end

-- A piece's total volume in u³.
function SectionLogic.GraphVolume(graph: Graph): number
	local v = 0
	for _, n in pairs(graph) do
		v += SectionLogic.NodeVolume(n)
	end
	return v
end

-- The id of a piece's biggest section (what its parts weld to; the lowest
-- id on a tie).
function SectionLogic.Largest(graph: Graph): number?
	local best: number? = nil
	local most = -1
	for k, n in pairs(graph) do
		local v = SectionLogic.NodeVolume(n)
		if v > most + 1e-9 or (math.abs(v - most) <= 1e-9 and (best == nil or k < best)) then
			best, most = k, v
		end
	end
	return best
end

-- Who a freed piece belongs to: whoever did the most damage to the cut
-- that finished it, so a last swing can't steal it. The same rule as a
-- tree's feller (ForestLogic.Feller: the swinger keeps a tie, and only
-- players `isHere` count).
function SectionLogic.Owner(cut: Cut, swingerId: number, isHere: ((number) -> boolean)?): number
	return ForestLogic.Feller(cut.damageBy, swingerId, isHere or function(): boolean
		return true
	end)
end

---------------------------------------------------------------------------
-- Aiming a swing (M1.3: CutController aims, SectionTrees checks)
---------------------------------------------------------------------------

-- A swing at a standing trunk goes in between the knee and the chest,
-- measured from the HumanoidRootPart (about 3 studs above the feet on R15
-- and R6), so you never have to aim at your own feet.
SectionLogic.KneeAbove = -1.6
SectionLogic.ChestAbove = 1.2
-- A section whose axis is this close to straight up (its UpVector's Y) is
-- a trunk you swing at sideways; anything flatter (a limb, a log on the
-- ground) is cut where you point.
SectionLogic.Upright = 0.7
-- The server takes a hit point this far outside the section's box (the
-- piece may have moved a little since the client aimed).
SectionLogic.BoxMargin = 0.6

-- The height (world Y) a swing at a standing trunk goes in at: the
-- pointer's height (or the root part's, without one) kept between the
-- knee and the chest.
function SectionLogic.SwingHeight(rootY: number, pointerY: number?): number
	local y = pointerY or rootY
	return math.clamp(y, rootY + SectionLogic.KneeAbove, rootY + SectionLogic.ChestAbove)
end

-- The face of a section (`cf` its centre) that `dir` (world) points out
-- of most, among its four sides: the outward normal, in world space.
function SectionLogic.SideFacing(cf: CFrame, dir: Vector3): Vector3
	local x, z = cf.XVector:Dot(dir), cf.ZVector:Dot(dir)
	if math.abs(x) >= math.abs(z) then
		return if x >= 0 then cf.XVector else -cf.XVector
	end
	return if z >= 0 then cf.ZVector else -cf.ZVector
end

-- Where a swing from `from` (the root part) at a section (`cf` its
-- centre, `size` its size, its length along Y) lands, and the face it
-- cuts into: (hit point, outward normal), both world space.
--   * A standing trunk (SectionLogic.Upright): at SwingHeight on its axis
--     (kept CutEdge inside its ends), on the side facing `from` (or the
--     side `pointerNormal` names, when it's a side face).
--   * Anything flatter: where the pointer hit it (`pointer`), else the
--     point on its axis nearest `from`; the face toward `from`, unless the
--     pointer named one.
function SectionLogic.AimAt(
	cf: CFrame,
	size: Vector3,
	from: Vector3,
	pointer: Vector3?,
	pointerNormal: Vector3?
): (Vector3, Vector3)
	local axis = cf.UpVector
	local half = size.Y / 2
	local edge = math.min(GameConfig.CutEdge, half)
	local centre = cf.Position
	local side = math.min(size.X, size.Z) / 2
	if math.abs(axis.Y) >= SectionLogic.Upright then
		local y = SectionLogic.SwingHeight(from.Y, if pointer then pointer.Y else nil)
		local t = math.clamp((y - centre.Y) / axis.Y, -half + edge, half - edge)
		local onAxis = centre + axis * t
		local normal: Vector3
		if pointerNormal and math.abs(pointerNormal:Dot(axis)) < 0.5 then
			normal = SectionLogic.SideFacing(cf, pointerNormal)
		else
			normal = SectionLogic.SideFacing(cf, from - onAxis)
		end
		return onAxis + normal * side, normal
	end
	local along: number
	if pointer then
		along = (pointer - centre):Dot(axis)
	else
		along = (from - centre):Dot(axis)
	end
	along = math.clamp(along, -half + edge, half - edge)
	local onAxis = centre + axis * along
	if pointer and pointerNormal and math.abs(pointerNormal:Dot(axis)) < 0.5 then
		return pointer, SectionLogic.SideFacing(cf, pointerNormal)
	end
	local normal = SectionLogic.SideFacing(cf, from - onAxis)
	return onAxis + normal * side, normal
end

-- Whether `point` lies inside a section's box (`cf` its centre, `size`
-- its size) grown by `margin` studs every way.
function SectionLogic.InBox(cf: CFrame, size: Vector3, point: Vector3, margin: number?): boolean
	local m = margin or SectionLogic.BoxMargin
	local p = cf:PointToObjectSpace(point)
	local h = size / 2
	return math.abs(p.X) <= h.X + m and math.abs(p.Y) <= h.Y + m and math.abs(p.Z) <= h.Z + m
end

-- How far up a section (from its bottom) a world point is, along its axis.
function SectionLogic.HeightOn(cf: CFrame, size: Vector3, point: Vector3): number
	return cf:PointToObjectSpace(point).Y + size.Y / 2
end

-- Who is cutting a standing tree: the claim the first cut makes, renewed
-- by every hit of theirs (`at` = their last hit, on the server's clock).
export type Claim = { userId: number, at: number }

-- The holder of `claim` when it keeps `userId` off the tree (so they can't
-- take over someone's half-cut tree), else nil: no claim, their own, an
-- Elder (everyone helps fell those), a holder who has left (`isHere`
-- says who's in the server), or one who hasn't hit it for
-- GameConfig.TreeClaimSec.
function SectionLogic.ClaimBlocks(
	claim: Claim?,
	userId: number,
	now: number,
	elder: boolean?,
	isHere: (number) -> boolean
): number?
	if claim == nil or elder or claim.userId == userId then
		return nil
	end
	if now - claim.at >= GameConfig.TreeClaimSec or not isHere(claim.userId) then
		return nil
	end
	return claim.userId
end

-- The toast for a refused swing, or nil for none (a swing too soon is
-- just ignored; the client mirrors the cooldown). `name` is who holds a
-- claimed tree.
function SectionLogic.Message(reason: string?, name: string?): string?
	if reason == "claimed" then
		return string.format("%s is cutting this tree. Find another one.", name or "Someone")
	elseif reason == "far" then
		return "Too far away. Walk closer to cut."
	elseif reason == "noLOS" then
		return "Something's in the way."
	elseif reason == "tooHard" then
		return "Too hard for this axe."
	elseif reason == "noAxe" then
		return "Take out an axe to cut."
	end
	return nil
end

return SectionLogic
