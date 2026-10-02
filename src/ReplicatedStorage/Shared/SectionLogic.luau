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

return SectionLogic
