--!strict
-- MudLogic: the Bayou's mud (Lane R). Pure. A player standing inside a mud
-- disc walks at 0.6x unless they own Wader Boots; the road, the log landing,
-- the boardwalk and the Bait Shack are dry whatever the discs say. BiomeService
-- calls Factor inside its WalkSpeed step (a disc check on its tick, not a
-- Touched event and not a second timer).

local BayouData = require(script.Parent.BayouData)

local MudLogic = {}

MudLogic.Slow = 0.6
MudLogic.Boots = "WaderBoots"

export type Disc = { x: number, z: number, radius: number }

local function inDisc(x: number, z: number, d: Disc): boolean
	local dx, dz = x - d.x, z - d.z
	return dx * dx + dz * dz <= d.radius * d.radius
end

-- Is (x, z) inside any of the discs?
function MudLogic.InMud(x: number, z: number, discs: { Disc }?): boolean
	for _, d in ipairs(discs or BayouData.MudZones) do
		if inDisc(x, z, d) then
			return true
		end
	end
	return false
end

-- Is (x, z) on ground that is always full speed: the junction's circle, the
-- log landing, the boardwalk's ring (its planks and a stud either side) or
-- the Bait Shack's footprint?
function MudLogic.IsDry(x: number, z: number): boolean
	if inDisc(x, z, BayouData.Junction) then
		return true
	end
	local l = BayouData.Landing
	if math.abs(x - l.x) <= l.sx / 2 and math.abs(z - l.z) <= l.sz / 2 then
		return true
	end
	local b = BayouData.Boardwalk
	local d = math.sqrt((x - b.x) ^ 2 + (z - b.z) ^ 2)
	if math.abs(d - b.radius) <= b.width / 2 + 1 then
		return true
	end
	local s = BayouData.Shack
	if math.abs(x - s.x) <= s.width / 2 + 1 and math.abs(z - s.z) <= s.depth / 2 + 1 then
		return true
	end
	return false
end

-- Is (x, z) inside the Bayou's disc? Boots only matter there.
function MudLogic.InBayou(x: number, z: number): boolean
	return inDisc(x, z, { x = BayouData.Centre.x, z = BayouData.Centre.z, radius = BayouData.Radius })
end

-- The walk-speed multiplier at (x, z): 1, or Slow in a mud disc with no
-- boots. The boots give 1.0x only inside the Bayou, which is the only place
-- there is mud. `gear` is a set of gear ids.
function MudLogic.Factor(x: number, z: number, gear: { [string]: boolean }, discs: { Disc }?): number
	if x ~= x or z ~= z then
		return 1
	end
	if not MudLogic.InBayou(x, z) then
		return 1
	end
	if gear[MudLogic.Boots] == true then
		return 1
	end
	if MudLogic.IsDry(x, z) then
		return 1
	end
	if MudLogic.InMud(x, z, discs) then
		return MudLogic.Slow
	end
	return 1
end

return MudLogic
