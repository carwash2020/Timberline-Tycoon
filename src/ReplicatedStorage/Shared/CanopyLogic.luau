--!strict
-- CanopyLogic: the rules behind CanopyFade (leaves never hide you), pure so
-- tests can check them.
--   * Which parts of a tree are canopy: WindSway's names (Leaves and Frond
--     parts, every part of a pine's Tier models, a frostwood's top-level
--     snow-cap Facets). The trunk, branches and roots never are.
--   * Which trees can be in the way: those whose trunk stands within Reach
--     (sideways, on the ground plane) of the line from the camera to you.
--     Reach covers every wood's widest canopy at every size, an Elder's too,
--     with room to spare for wind sway and a hit wobble
--     (tests/CanopyLogic.spec.luau builds them all).
--   * The ray loop's bookkeeping (Trace): each ray leaves out every tree an
--     earlier one hit, so each ray finds a new tree, until one gets through
--     or MaxCasts rays have gone.
--   * The fade: in the way, a canopy goes to Fade within FadeInTime; once
--     it's been out of the way for Hold seconds it eases back to 0 over
--     FadeOutTime.
--   * Who owns a part's LocalTransparencyModifier (Owns): CanopyFade only
--     writes a part that is still where it left it, or at 0. Anything else
--     (TreeFX's felled fade to 1) belongs to someone else.

local CanopyLogic = {}

CanopyLogic.Every = 0.1 -- seconds between looks (10 Hz)
CanopyLogic.MaxCasts = 6 -- rays per target per look, at most
CanopyLogic.Fade = 0.7 -- LocalTransparencyModifier of a canopy in the way
CanopyLogic.Hold = 0.3 -- seconds out of the way before it comes back
CanopyLogic.FadeInTime = 0.1 -- seconds from 0 to Fade
CanopyLogic.FadeOutTime = 0.4 -- seconds from Fade back to 0
CanopyLogic.Reach = 24 -- studs from a trunk's axis: the widest canopy (an Elder emberwood's, ~19) plus room for sway
CanopyLogic.EyeRadius = 0.75 -- a canopy this close around the camera counts as in the way
CanopyLogic.MinSightline = 2 -- studs: a target closer than this to the camera (first person) is skipped
CanopyLogic.Slack = 1e-3 -- LocalTransparencyModifier is a 32-bit float: 0.7 reads back 0.69999999

local NAMED: { [string]: boolean } = { Leaves = true, Frond = true }

-- Whether `part` (somewhere inside `tree`) is canopy, as WindSway sees it.
function CanopyLogic.IsCanopyPart(part: Instance, tree: Instance): boolean
	if not part:IsA("BasePart") or not part:IsDescendantOf(tree) then
		return false
	end
	if NAMED[part.Name] then
		return true
	end
	local parent = part.Parent
	if parent == nil then
		return false
	end
	if parent ~= tree and parent:IsA("Model") and parent.Name == "Tier" then
		return true -- a pine's tier faces
	end
	return part.Name == "Facet" and parent == tree -- a frostwood's snow caps
end

-- Every canopy part of a tree.
function CanopyLogic.CanopyParts(tree: Instance): { BasePart }
	local out: { BasePart } = {}
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("BasePart") and CanopyLogic.IsCanopyPart(d, tree) then
			table.insert(out, d)
		end
	end
	return out
end

-- How far `point` is from the segment a-b, on the ground plane (X and Z).
function CanopyLogic.DistanceXZ(point: Vector3, a: Vector3, b: Vector3): number
	local px, pz = point.X - a.X, point.Z - a.Z
	local dx, dz = b.X - a.X, b.Z - a.Z
	local len2 = dx * dx + dz * dz
	local s = if len2 > 1e-9 then math.clamp((px * dx + pz * dz) / len2, 0, 1) else 0
	local ex, ez = px - dx * s, pz - dz * s
	return math.sqrt(ex * ex + ez * ez)
end

-- Whether a tree whose trunk stands at `trunk` could have its canopy
-- between the camera (`eye`) and `target`.
function CanopyLogic.NearSightline(trunk: Vector3, eye: Vector3, target: Vector3): boolean
	return CanopyLogic.DistanceXZ(trunk, eye, target) <= CanopyLogic.Reach
end

-- The ray loop. `cast(exclude)` fires one ray that skips the trees in
-- `exclude` and returns the tree it hit (nil when the way is clear) and
-- whether it hit that tree's canopy. Each tree hit is left out of the next
-- ray. Returns the trees whose canopy was in the way, nearest first.
function CanopyLogic.Trace<T>(cast: (exclude: { [T]: boolean }) -> (T?, boolean), maxCasts: number?): { T }
	local exclude: { [T]: boolean } = {}
	local hits: { T } = {}
	for _ = 1, maxCasts or CanopyLogic.MaxCasts do
		local tree, canopy = cast(exclude)
		if tree == nil or exclude[tree] then
			break -- clear (or a ray that ignored the list: never loop on it)
		end
		exclude[tree] = true
		if canopy then
			table.insert(hits, tree)
		end
	end
	return hits
end

-- The canopy's fade `sinceHit` seconds after it was last in the way, one
-- frame (`dt` seconds) on from `alpha`.
function CanopyLogic.Step(alpha: number, sinceHit: number, dt: number): number
	if sinceHit < CanopyLogic.Hold then
		return math.min(CanopyLogic.Fade, alpha + dt * CanopyLogic.Fade / CanopyLogic.FadeInTime)
	end
	return math.max(0, alpha - dt * CanopyLogic.Fade / CanopyLogic.FadeOutTime)
end

-- Whether CanopyFade may write a part whose LocalTransparencyModifier is
-- `current`, having last written `written` to it: only if it's still
-- there, or at 0 (nobody has faded it).
function CanopyLogic.Owns(current: number, written: number): boolean
	return math.abs(current - written) <= CanopyLogic.Slack or math.abs(current) <= CanopyLogic.Slack
end

return CanopyLogic
