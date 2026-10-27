--!strict
-- CargoLock: when a loose wood piece may be welded to a truck bed.
-- The server is the only thing that locks or unlocks (TruckLoad). These
-- rules are the same on every truck and trailer: a piece settles when it
-- moves slower than RestSpeed relative to the bed for SettleSec, its
-- footprint is at least half on the bed (box math, never Touched), and
-- its bottom is on the bed or on cargo already locked there. A piece let
-- go of far from the truck never locks.

local CargoLock = {}

CargoLock.SettleSec = 0.2 -- stuck almost as soon as it is set down
CargoLock.RestSpeed = 0.6 -- studs/s, in bed space
CargoLock.ContactGap = 0.45 -- studs the bottom may sit above the surface
CargoLock.FarStuds = 18 -- a release farther than this from the bed never locks
CargoLock.MinInside = 0.5 -- more than half hanging off never locks
CargoLock.WeldName = "BedWeld"
CargoLock.LockedAttr = "CargoLocked" -- set on parts made massless for the weld
-- A headed drive (200 studs, two turns, a T409 grade) is a Studio playtest.
-- The rules below are the settle math that drive has to satisfy.
CargoLock.LiveDrive = "playtest"
CargoLock.DriveStuds = 200
CargoLock.DriveTurns = 2

export type Sample = { pos: Vector3, at: number, since: number? }

-- Support of a cylinder (length along local X, radius min(Y, Z) / 2) in
-- a unit direction, measured from its centre. Rolling about the length
-- does not change it: the corners of the bounding box do.
local function cylinderSupport(rel: CFrame, size: Vector3, axis: Vector3): number
	local along = math.abs(rel.XVector:Dot(axis))
	local halfLen = size.X / 2
	local radius = math.min(size.Y, size.Z) / 2
	local radial = math.sqrt(math.max(0, 1 - along * along))
	return along * halfLen + radius * radial
end

-- The footprint of `size` at `rel` (both in one box's space) that lies
-- inside that box's XZ rectangle, as a share of the footprint. Y is
-- ignored, so a stack still counts. `shape` "cylinder" uses the round
-- support instead of the eight corners.
function CargoLock.InsideShare(bedSize: Vector3, rel: CFrame, size: Vector3, shape: string?): number
	local minX, maxX, minZ, maxZ
	if shape == "cylinder" then
		local c = rel.Position
		local sx = cylinderSupport(rel, size, Vector3.xAxis)
		local sz = cylinderSupport(rel, size, Vector3.zAxis)
		minX, maxX = c.X - sx, c.X + sx
		minZ, maxZ = c.Z - sz, c.Z + sz
	else
		local half = size / 2
		minX, maxX = math.huge, -math.huge
		minZ, maxZ = math.huge, -math.huge
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local p = rel * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
					minX = math.min(minX, p.X)
					maxX = math.max(maxX, p.X)
					minZ = math.min(minZ, p.Z)
					maxZ = math.max(maxZ, p.Z)
				end
			end
		end
	end
	local area = (maxX - minX) * (maxZ - minZ)
	if area <= 1e-6 then
		return 0
	end
	local hx, hz = bedSize.X / 2, bedSize.Z / 2
	local ix0, ix1 = math.max(minX, -hx), math.min(maxX, hx)
	local iz0, iz1 = math.max(minZ, -hz), math.min(maxZ, hz)
	if ix1 <= ix0 or iz1 <= iz0 then
		return 0
	end
	return ((ix1 - ix0) * (iz1 - iz0)) / area
end

-- True when more than half the footprint hangs past the bed.
function CargoLock.Overhangs(bedSize: Vector3, rel: CFrame, size: Vector3, shape: string?): boolean
	return CargoLock.InsideShare(bedSize, rel, size, shape) < CargoLock.MinInside
end

local function extentY(rel: CFrame, size: Vector3): (number, number)
	local half = size / 2
	local lo, hi = math.huge, -math.huge
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local y = (rel * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)).Y
				lo = math.min(lo, y)
				hi = math.max(hi, y)
			end
		end
	end
	return lo, hi
end

function CargoLock.BottomY(rel: CFrame, size: Vector3, shape: string?): number
	if shape == "cylinder" then
		return rel.Position.Y - cylinderSupport(rel, size, Vector3.yAxis)
	end
	local lo = extentY(rel, size)
	return lo
end

-- The piece's underside is on the bed's top (the bed is `bedSize`, the
-- piece is `rel`/`size` in the bed's space).
function CargoLock.ContactsBed(bedSize: Vector3, rel: CFrame, size: Vector3, gap: number?, shape: string?): boolean
	local slack = gap or CargoLock.ContactGap
	local top = bedSize.Y / 2
	local bottom = CargoLock.BottomY(rel, size, shape)
	return bottom >= top - 0.2 and bottom <= top + slack
end

-- `rel` rests on another box (`other`, already locked) in the same space:
-- the bottoms meet and the footprints overlap.
function CargoLock.StackedOn(rel: CFrame, size: Vector3, other: CFrame, otherSize: Vector3, gap: number?): boolean
	local slack = gap or CargoLock.ContactGap
	local bottom = CargoLock.BottomY(rel, size)
	local _, top = extentY(other, otherSize)
	if bottom < top - 0.25 or bottom > top + slack then
		return false
	end
	local function span(cf: CFrame, sz: Vector3): (number, number, number, number)
		local h = sz / 2
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, sx in ipairs({ -1, 1 }) do
			for _, szs in ipairs({ -1, 1 }) do
				local p = cf * Vector3.new(sx * h.X, 0, szs * h.Z)
				minX = math.min(minX, p.X)
				maxX = math.max(maxX, p.X)
				minZ = math.min(minZ, p.Z)
				maxZ = math.max(maxZ, p.Z)
			end
		end
		return minX, maxX, minZ, maxZ
	end
	local a0, a1, b0, b1 = span(rel, size)
	local c0, c1, d0, d1 = span(other, otherSize)
	return math.min(a1, c1) > math.max(a0, c0) and math.min(b1, d1) > math.max(b0, d0)
end

-- Studs per second between two bed-space samples. dt <= 0 has not moved
-- yet (the first look, or two looks in the same moment).
function CargoLock.RelativeSpeed(from: Vector3, to: Vector3, dt: number): number
	if dt <= 0 then
		return 0
	end
	return (to - from).Magnitude / dt
end

-- The next rest sample, and whether it has been still long enough to lock.
-- A fast sample forgets the rest. A non-positive dt changes nothing.
function CargoLock.NoteRest(prev: Sample?, pos: Vector3, now: number): (Sample, boolean)
	if not prev then
		return { pos = pos, at = now, since = nil }, false
	end
	local dt = now - prev.at
	if dt <= 0 then
		return prev, false
	end
	if CargoLock.RelativeSpeed(prev.pos, pos, dt) > CargoLock.RestSpeed then
		return { pos = pos, at = now, since = nil }, false
	end
	local since = prev.since or prev.at
	local settled = now - since >= CargoLock.SettleSec
	return { pos = pos, at = now, since = since }, settled
end

-- All three: enough of it on the bed, touching the bed or a locked piece,
-- and not a release that happened far from the truck.
function CargoLock.MayLock(insideShare: number, touching: boolean, releasedFar: boolean): boolean
	return insideShare >= CargoLock.MinInside and touching and not releasedFar
end

return CargoLock
