--!strict
-- Geometry: the world-wide collision lint (T409 rule 2b) and the invisible-blocker rule.
-- Pure: takes a root Instance (the built map), returns plain data and lines. The lune spec
-- (tests/GeometryLint.spec) and the cloud runner (tests/cloud/entry) are thin callers, so the
-- rule is one piece of code in both places.
--
--   Pieces: the root's children are the pieces; a Folder is not a piece, its children are (so
--   Scenery/Outcrop#5 and Crate#3 are pieces, ToolShed is one piece with all its parts).
--   Two parts of the same piece never count (a wall and the counter it stands against, welded
--   decks and plinths): only pairs from different pieces do.
--   A part counts when CanCollide is on. A WedgePart is judged as the wedge it is (Clearance.Wedge, a
--   convex SAT, not its bounding box); a cylinder or ball counts as its inscribed box.
--   Rule 2b: two parts of different pieces overlap by more than MinDepth (0.05 studs, the
--   smallest overlap along the 15 SAT axes of Clearance.BoxDepth) and the pair is not in the
--   allowlist.
--   Rule 2c: a part with Transparency 1 and CanCollide on is an invisible wall: it needs the
--   attribute InvisibleBlocker = true and a non-empty InvisibleBlockerReason, or it is a hit.
--
-- The allowlist is a list of { a, b, reason } (tests/geometry_allow.json): a and b are piece ids
-- ("Crate#3", "Scenery/Outcrop#5") or "*" for any piece. An entry without a reason fails, and so
-- does an entry no hit uses any more (the list stays true).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Clearance = require(ReplicatedStorage.Shared.World.Clearance)

local Geometry = {}

Geometry.MinDepth = 0.05

export type AllowEntry = { a: string, b: string, reason: string? }
export type Hit = { a: string, b: string, partA: string, partB: string, at: Vector3, depth: number, rule: string }
export type Result = { hits: { Hit }, failures: { string }, parts: number, pieces: number }

local function siblingIds(parent: Instance, prefix: string): { [Instance]: string }
	local total: { [string]: number } = {}
	for _, child in ipairs(parent:GetChildren()) do
		total[child.Name] = (total[child.Name] or 0) + 1
	end
	local seen: { [string]: number } = {}
	local out: { [Instance]: string } = {}
	for _, child in ipairs(parent:GetChildren()) do
		local n = (seen[child.Name] or 0) + 1
		seen[child.Name] = n
		out[child] = prefix .. child.Name .. (if (total[child.Name] :: number) > 1 then "#" .. n else "")
	end
	return out
end

-- Every piece under root: id -> the piece's instance.
function Geometry.Pieces(root: Instance): ({ string }, { [string]: Instance })
	local ids: { string } = {}
	local byId: { [string]: Instance } = {}
	local function walk(parent: Instance, prefix: string)
		for child, id in pairs(siblingIds(parent, prefix)) do
			if child:IsA("Folder") then
				walk(child, id .. "/")
			elseif child:IsA("Model") or child:IsA("BasePart") then
				table.insert(ids, id)
				byId[id] = child
			end
		end
	end
	walk(root, "")
	table.sort(ids)
	return ids, byId
end

function Geometry.Solid(part: BasePart): boolean
	return part.CanCollide
end

local function collidingParts(piece: Instance): { BasePart }
	local out: { BasePart } = {}
	if piece:IsA("BasePart") and Geometry.Solid(piece) then
		table.insert(out, piece)
	end
	for _, d in ipairs(piece:GetDescendants()) do
		if d:IsA("BasePart") and Geometry.Solid(d) then
			table.insert(out, d)
		end
	end
	return out
end

-- The box a part stands for. A round part is its inscribed box (a cylinder's round faces are its
-- Y and Z, a ball is round all over), so a corner of the bounding box never makes a hit.
function Geometry.BoxOf(part: BasePart): Clearance.Shape
	if part:IsA("WedgePart") then
		return Clearance.Wedge(part.CFrame, part.Size)
	end
	local size = part.Size
	if part:IsA("Part") then
		if part.Shape == Enum.PartType.Cylinder then
			size = Vector3.new(size.X, size.Y * 0.7071, size.Z * 0.7071)
		elseif part.Shape == Enum.PartType.Ball then
			size = size * 0.5774
		end
	end
	return Clearance.Box(part.CFrame, size)
end

local function overlapCentre(a: Clearance.Shape, b: Clearance.Shape): Vector3
	local x = (math.max(a.x0, b.x0) + math.min(a.x1, b.x1)) / 2
	local z = (math.max(a.z0, b.z0) + math.min(a.z1, b.z1)) / 2
	local y = (math.max(a.y0 :: number, b.y0 :: number) + math.min(a.y1 :: number, b.y1 :: number)) / 2
	return Vector3.new(x, y, z)
end

-- "*" is any piece; a trailing "*" is a prefix ("WorldEdge#*"); otherwise the id exactly.
local function matches(pattern: string, id: string): boolean
	if pattern == "*" or pattern == id then
		return true
	end
	if string.sub(pattern, -1) == "*" then
		return string.sub(id, 1, #pattern - 1) == string.sub(pattern, 1, -2)
	end
	return false
end

-- Whether the allowlist names this pair of pieces (either order).
function Geometry.Allowed(list: { AllowEntry }, ida: string, idb: string): boolean
	for _, entry in ipairs(list) do
		if (matches(entry.a, ida) and matches(entry.b, idb)) or (matches(entry.a, idb) and matches(entry.b, ida)) then
			return true
		end
	end
	return false
end

function Geometry.Line(hit: Hit): string
	return string.format(
		"[GeometryLint] %s (%s) x %s (%s) at (%.1f, %.1f, %.1f), depth %.2f, rule %s",
		hit.partA,
		hit.a,
		hit.partB,
		hit.b,
		hit.at.X,
		hit.at.Y,
		hit.at.Z,
		hit.depth,
		hit.rule
	)
end

-- Rule 2b over everything under `root`. `allow` is the allowlist, `minDepth` defaults to 0.05.
-- `options.skipStale`: do not fail an allowlist entry that hits nothing (a run over part of the
-- world, like the cloud test's town, cannot see every entry's pieces).
function Geometry.Run(
	root: Instance,
	allow: { AllowEntry }?,
	minDepth: number?,
	options: { skipStale: boolean? }?
): Result
	local list = allow or {}
	local skipStale = options ~= nil and options.skipStale == true
	local limit = minDepth or Geometry.MinDepth
	local failures: { string } = {}
	local hits: { Hit } = {}

	for i, entry in ipairs(list) do
		if type(entry.reason) ~= "string" or entry.reason == "" then
			table.insert(
				failures,
				string.format(
					"[GeometryLint] allowlist entry %d (%s x %s) has no reason",
					i,
					tostring(entry.a),
					tostring(entry.b)
				)
			)
		end
	end

	local ids, byId = Geometry.Pieces(root)
	local grid = Clearance.NewGrid()
	local pieceOf: { [Clearance.Entry]: string } = {}
	local partCount = 0
	for _, id in ipairs(ids) do
		for _, part in ipairs(collidingParts(byId[id])) do
			partCount += 1
			local entry = Clearance.Add(grid, part.Name, "part", Geometry.BoxOf(part), part)
			pieceOf[entry] = id
		end
	end

	local used: { [number]: boolean } = {}
	local raw = Clearance.BoxHits(grid, limit, function(a, b)
		return pieceOf[a] == pieceOf[b]
	end)
	for _, h in ipairs(raw) do
		local ida, idb = pieceOf[h.a], pieceOf[h.b]
		local allowed = false
		for i, entry in ipairs(list) do
			if
				(matches(entry.a, ida) and matches(entry.b, idb)) or (matches(entry.a, idb) and matches(entry.b, ida))
			then
				allowed = true
				used[i] = true
			end
		end
		if not allowed then
			table.insert(hits, {
				a = ida,
				b = idb,
				partA = h.a.id,
				partB = h.b.id,
				at = overlapCentre(h.a.shape, h.b.shape),
				depth = h.depth,
				rule = "2b",
			})
		end
	end
	for i, entry in ipairs(list) do
		if not used[i] and not skipStale then
			table.insert(
				failures,
				string.format(
					"[GeometryLint] allowlist entry %d (%s x %s) hits nothing now: remove it",
					i,
					entry.a,
					entry.b
				)
			)
		end
	end

	-- Rule 2c: invisible walls need a name and a reason.
	for _, id in ipairs(ids) do
		for _, part in ipairs(collidingParts(byId[id])) do
			if part.Transparency >= 1 then
				local reason = part:GetAttribute("InvisibleBlockerReason")
				if part:GetAttribute("InvisibleBlocker") ~= true or type(reason) ~= "string" or reason == "" then
					table.insert(hits, {
						a = id,
						b = id,
						partA = part.Name,
						partB = part.Name,
						at = part.CFrame.Position,
						depth = 0,
						rule = "2c",
					})
				end
			end
		end
	end

	for _, hit in ipairs(hits) do
		if hit.rule == "2c" then
			table.insert(
				failures,
				string.format(
					"[GeometryLint] %s (%s) is Transparency 1 with CanCollide on at (%.1f, %.1f, %.1f) and has no InvisibleBlocker + InvisibleBlockerReason, rule 2c",
					hit.partA,
					hit.a,
					hit.at.X,
					hit.at.Y,
					hit.at.Z
				)
			)
		else
			table.insert(failures, Geometry.Line(hit))
		end
	end
	return { hits = hits, failures = failures, parts = partCount, pieces = #ids }
end

return Geometry
