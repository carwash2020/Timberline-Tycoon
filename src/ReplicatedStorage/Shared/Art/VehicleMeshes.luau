--!strict
-- Swaps a built truck (and its trailer) onto uploaded meshes when every
-- required mesh loads. A miss keeps the part-built body. Functional parts
-- stay: chassis, skids, ramps, seat, bed floors, bed hull, wheels, lights
-- and exhaust. Looks-only meshes are Massless and not queryable.
-- Wheels are one tyre mesh each, at the axle the part-built wheel already
-- uses.
--
-- WHERE EACH PIECE GOES (fixed 8 October 2026, "the vehicle models are messed
-- up"). Each role is its own mesh asset, and an asset carries no pivot: the
-- piece lands at its own bounds' centre, which tells us its size but not
-- where it sat in the assembly. The old rule put every piece's bounds' bottom
-- centre on the ground centre, which is right only for the Body (it is drawn
-- from the ground up). A Bed went to the ground, under the part-built bed
-- boards; the Glass and the Lights sank to the ground; the Hitch sat in the
-- middle of the truck. Now every role is placed from the part-built hull it
-- replaces (Place): the Bed on the BedFloor from the chassis bottom, the
-- Glass at the cab's glass, the Lights between the head and tail lamps, the
-- Hitch at the rear of the chassis (a trailer: the bed, the lamps, the
-- coupler). A piece whose import pivot DID survive (MeshPivot "authored") is
-- used as it is only when that lands within PivotTolerance of the hull's
-- place; otherwise the hull's place wins. Never a guess from the ground.

local MeshKit = require(script.Parent.MeshKit)
local VehicleModels = require(script.Parent.VehicleModels)

local VehicleMeshes = {}

-- Flatbed and Logging Rig keep more hull (stakes, tandem), so their mesh
-- build may use up to 80 parts. Every other truck is 30.
VehicleMeshes.TruckCap = 30
VehicleMeshes.LongCap = 80
-- 15 was the ask. The colliding hull (boards or stakes, gate, skid, ramps,
-- wheels, lights, bed zone) is already about that before the four look
-- meshes. Ranch is the heaviest: six stakes, four rails, and the front
-- board, which lands at 25. Dropping those rails would open the sides.
VehicleMeshes.TrailerCap = 25

local KEEP = {
	Chassis = true,
	Skid = true,
	Ramp = true,
	TrailerSkid = true,
	DriverSeat = true,
	BedFloor = true,
	TrailerBed = true,
	BedZone = true,
	Wheel = true,
	Headlight = true,
	Taillight = true,
	Exhaust = true,
	BedBoard = true,
	BedWall = true,
	BedPost = true,
	Tailgate = true,
	BedCap = true,
	BedFront = true,
	Stake = true,
	StakeRail = true,
	StakePocket = true,
	Stanchion = true,
	Chain = true,
	HeadacheRack = true,
	TrailerBoard = true,
	TrailerFront = true,
	TrailerGate = true,
	TrailerStake = true,
	TrailerRail = true,
	TrailerStanchion = true,
	Coupler = true,
	Tongue = true,
	-- Timber Classic: the owner's name and the load gauge stay on a meshed truck.
	DoorPlate = true,
	LoadGauge = true,
}

local TRUCK_ROLES = { "Body", "Glass", "Lights", "Bed", "Hitch" }
local TRAILER_ROLES = { "Body", "Lights", "Bed", "Hitch" }

function VehicleMeshes.PartCap(truckId: string): number
	if truckId == "Flatbed" or truckId == "LoggingRig" then
		return VehicleMeshes.LongCap
	end
	return VehicleMeshes.TruckCap
end

local function isTrailer(part: BasePart): boolean
	if part:GetAttribute("TrailerBody") == true or part:GetAttribute("RigHalf") == "trailer" then
		return true
	end
	if part.Name == "TrailerBed" or part.Name == "TrailerSkid" then
		return true
	end
	local parent: Instance? = part.Parent
	while parent and not parent:IsA("Model") do
		if parent.Name == "TrailerBed" or parent:GetAttribute("TrailerBody") == true then
			return true
		end
		parent = parent.Parent
	end
	return false
end

function VehicleMeshes.Counts(model: Model): (number, number)
	local truck, trailer = 0, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if isTrailer(d) then
				trailer += 1
			else
				truck += 1
			end
		end
	end
	return truck, trailer
end

local function wheelsOf(model: Model, trailer: boolean): { BasePart }
	local out: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Wheel" and d:GetAttribute("Radius") ~= nil and isTrailer(d) == trailer then
			table.insert(out, d)
		end
	end
	return out
end

-- An authored pivot is trusted only this close (studs) to where the hull says
-- the piece goes.
VehicleMeshes.PivotTolerance = 2

local function placeAtRoot(part: BasePart, size: Vector3, root: Vector3)
	if part:GetAttribute("MeshPivot") == "authored" then
		part:PivotTo(CFrame.new(root))
	else
		part.CFrame = CFrame.new(root + Vector3.new(0, size.Y / 2, 0))
	end
end

-- The hull parts a mesh piece is placed from, found before the part-built
-- cab and bed are dropped. All in the vehicle's local space.
-- A hull part as numbers (the part itself is dropped or moved after).
type Spot = { pos: Vector3, size: Vector3, name: string }
type Hull = {
	chassis: Spot?,
	bedFloor: Spot?,
	glass: Spot?, -- CabGlass, else Windshield
	seat: Spot?,
	lampLo: Vector3?, -- the truck's head and tail lamps: lowest corner
	lampHi: Vector3?,
	trailerBed: Spot?,
	coupler: Spot?,
}

local function hullOf(model: Model): Hull
	local hull: Hull = {}
	for _, d in ipairs(model:GetDescendants()) do
		if not d:IsA("BasePart") then
			continue
		end
		local name = d.Name
		local trailer = isTrailer(d)
		local spot: Spot = { pos = d.CFrame.Position, size = d.Size, name = name }
		if name == "Chassis" then
			hull.chassis = spot
		elseif name == "BedFloor" and not trailer then
			hull.bedFloor = spot
		elseif name == "CabGlass" or (name == "Windshield" and not (hull.glass and hull.glass.name == "CabGlass")) then
			hull.glass = spot
		elseif name == "DriverSeat" then
			hull.seat = spot
		elseif name == "TrailerBed" then
			hull.trailerBed = spot
		elseif name == "Coupler" then
			hull.coupler = spot
		elseif name == "Headlight" or name == "Taillight" then
			local p, h = spot.pos, spot.size / 2
			if not trailer then
				local lo, hi = p - h, p + h
				hull.lampLo = if hull.lampLo then hull.lampLo:Min(lo) else lo
				hull.lampHi = if hull.lampHi then hull.lampHi:Max(hi) else hi
			end
		end
	end
	return hull
end

-- Where the middle of a piece's bounds goes, from the hull, or nil when the
-- hull has nothing to place it from (the caller then uses the old root rule).
function VehicleMeshes.Place(hull: Hull, role: string, size: Vector3, trailer: boolean): Vector3?
	local half = size.Y / 2
	if trailer then
		local bed = hull.trailerBed
		if not bed then
			return nil
		end
		local bp, bs = bed.pos, bed.size
		if role == "Body" then
			return Vector3.new(bp.X, bp.Y + bs.Y / 2 - half, bp.Z)
		elseif role == "Bed" then
			return Vector3.new(bp.X, bp.Y - bs.Y / 2 + half, bp.Z)
		elseif role == "Lights" then
			-- The trailer's lights can stand as tall as its bed (marker lamps
			-- up the stakes): on the bed's bottom like the Bed, not on the lamp.
			return Vector3.new(bp.X, bp.Y - bs.Y / 2 + half, bp.Z)
		elseif role == "Hitch" then
			local frontZ = bp.Z - bs.Z / 2
			local tip = if hull.coupler then hull.coupler.pos else Vector3.new(0, bp.Y - 0.6, frontZ - 2)
			return Vector3.new(bp.X, tip.Y + 0.5, (tip.Z + frontZ) / 2)
		end
		return nil
	end
	local chassis = hull.chassis
	if not chassis then
		return nil
	end
	local cp, cs = chassis.pos, chassis.size
	local chassisBottom = cp.Y - cs.Y / 2
	if role == "Body" then
		return Vector3.new(0, half, 0)
	elseif role == "Bed" then
		local floor = hull.bedFloor
		if not floor then
			return nil
		end
		local fp = floor.pos
		return Vector3.new(fp.X, chassisBottom + half, fp.Z)
	elseif role == "Glass" then
		local glass = hull.glass
		if glass then
			local gp = glass.pos
			-- A bare windshield is a thin pane at the cab's front: the glass
			-- mesh (windows all round) stands behind it.
			local z = if glass.name == "CabGlass" then gp.Z else gp.Z + size.Z / 2 - 0.2
			return Vector3.new(0, gp.Y, z)
		end
		local seat = hull.seat
		if seat then
			local sp = seat.pos
			return Vector3.new(0, sp.Y + 1.6, sp.Z - 1.2)
		end
		return nil
	elseif role == "Lights" then
		local lo, hi = hull.lampLo, hull.lampHi
		if not lo or not hi then
			return nil
		end
		-- From the lowest lamp up, but never above the cab's roof (the tall
		-- Flatbed and Logging Rig light meshes reach the cab beacons).
		local bottom = lo.Y
		local glass = hull.glass
		if glass then
			local roof = glass.pos.Y + glass.size.Y / 2 + 0.5
			bottom = math.max(chassisBottom, math.min(bottom, roof - size.Y))
		end
		return Vector3.new(0, bottom + half, (lo.Z + hi.Z) / 2)
	elseif role == "Hitch" then
		return Vector3.new(0, cp.Y, cp.Z + cs.Z / 2 - size.Z / 2)
	end
	return nil
end

-- Puts `part` where the hull says, unless its own pivot survived and agrees.
local function placePiece(part: BasePart, role: string, size: Vector3, trailer: boolean, hull: Hull, root: Vector3)
	local want = VehicleMeshes.Place(hull, role, size, trailer)
	if want == nil then
		placeAtRoot(part, size, root)
		return
	end
	if part:GetAttribute("MeshPivot") == "authored" then
		part:PivotTo(CFrame.new(root))
		if (part.CFrame.Position - want).Magnitude <= VehicleMeshes.PivotTolerance then
			return
		end
	end
	part.CFrame = CFrame.new(want)
end

local function trailerRoot(model: Model): Vector3
	local sum = Vector3.zero
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and isTrailer(d) and d.Name ~= "BedZone" then
			sum += d.CFrame.Position
			n += 1
		end
	end
	if n == 0 then
		return Vector3.zero
	end
	local c = sum / n
	return Vector3.new(c.X, 0, c.Z)
end

local function fidelity(part: MeshPart, role: string)
	if role == "Body" or role == "Bed" or role == "Wheel" then
		MeshKit.Fidelity(part, Enum.RenderFidelity.Automatic)
	else
		MeshKit.Fidelity(part, Enum.RenderFidelity.Performance)
	end
end

type Made = { part: MeshPart, role: string, trailer: boolean, wheel: BasePart? }

local function destroyMade(made: { Made })
	for _, item in ipairs(made) do
		if item.part.Parent or item.part then
			item.part:Destroy()
		end
	end
end

local function addRole(
	made: { Made },
	spec: { [string]: VehicleModels.Piece },
	role: string,
	trailer: boolean,
	wheel: BasePart?
): boolean
	local piece = spec[role]
	if not piece or piece.meshId == 0 then
		return false
	end
	local name = if role == "Wheel" then "Wheel" else "Mesh" .. role
	-- A tyre is round. Box collision would be a cube around it.
	local collision = if role == "Wheel" then Enum.CollisionFidelity.Hull else Enum.CollisionFidelity.Box
	local part = MeshKit.Create(piece.meshId, name, piece.size, collision)
	if not part then
		return false
	end
	fidelity(part, role)
	if role ~= "Wheel" then
		MeshKit.Visual(part, piece.meshId)
	end
	table.insert(made, { part = part, role = role, trailer = trailer, wheel = wheel })
	return true
end

local function swapWheel(mesh: MeshPart, wheel: BasePart)
	mesh.CFrame = wheel.CFrame
	mesh.Color = wheel.Color
	mesh.Material = wheel.Material
	mesh.Anchored = wheel.Anchored
	mesh.Massless = true
	mesh.CanCollide = wheel.CanCollide
	mesh.CanTouch = wheel.CanTouch
	mesh.CanQuery = wheel.CanQuery
	for _, attr in ipairs({ "Radius", "Steer", "Rear", "TrailerBody" }) do
		local value = wheel:GetAttribute(attr)
		if value ~= nil then
			mesh:SetAttribute(attr, value)
		end
	end
	mesh:SetAttribute("RigHalf", if isTrailer(wheel) then "trailer" else "truck")
	mesh.Parent = wheel.Parent
	wheel:Destroy()
end

-- True when meshes replaced the decorative body. False leaves `model` as built.
function VehicleMeshes.Apply(model: Model, truckId: string, trailerId: string?): boolean
	local truck = VehicleModels.Truck(truckId)
	if not truck then
		return false
	end
	local made: { Made } = {}
	local function fail(): boolean
		destroyMade(made)
		return false
	end

	for _, role in ipairs(TRUCK_ROLES) do
		if truck[role] == nil then
			continue
		end
		if not addRole(made, truck, role, false, nil) then
			return fail()
		end
	end
	if not truck.Wheel then
		return fail()
	end
	for _, wheel in ipairs(wheelsOf(model, false)) do
		if not addRole(made, truck, "Wheel", false, wheel) then
			return fail()
		end
	end

	local trailerSpec = if trailerId then VehicleModels.Trailer(trailerId, truckId) else nil
	if trailerId then
		if not trailerSpec then
			return fail()
		end
		for _, role in ipairs(TRAILER_ROLES) do
			if trailerSpec[role] == nil then
				continue
			end
			if not addRole(made, trailerSpec, role, true, nil) then
				return fail()
			end
		end
		if not trailerSpec.Wheel then
			return fail()
		end
		for _, wheel in ipairs(wheelsOf(model, true)) do
			if not addRole(made, trailerSpec, "Wheel", true, wheel) then
				return fail()
			end
		end
	end

	local hull = hullOf(model)
	local drop: { Instance } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not KEEP[d.Name] and d:GetAttribute("VisualMesh") ~= true then
			table.insert(drop, d)
		end
	end
	for _, d in ipairs(drop) do
		if d.Parent then
			d:Destroy()
		end
	end

	local origin = Vector3.zero
	local trailerAt = trailerRoot(model)
	local bodyFolder = model:FindFirstChild("Body")
	local bed = model:FindFirstChild("TrailerBed")
	for _, item in ipairs(made) do
		local part = item.part
		if item.role == "Wheel" and item.wheel and item.wheel.Parent then
			swapWheel(part, item.wheel)
		else
			local root = if item.trailer then trailerAt else origin
			placePiece(part, item.role, part.Size, item.trailer, hull, root)
			if item.trailer then
				part:SetAttribute("TrailerBody", true)
				part:SetAttribute("RigHalf", "trailer")
				part.Parent = if bed and bed:IsA("BasePart") then bed else model
			else
				part:SetAttribute("RigHalf", "truck")
				part.Parent = if bodyFolder then bodyFolder else model
			end
		end
	end

	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("VehicleMesh", true)
	return true
end

return VehicleMeshes
