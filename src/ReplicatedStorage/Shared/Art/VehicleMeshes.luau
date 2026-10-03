--!strict
-- Swaps a built truck (and its trailer) onto uploaded meshes when every
-- required mesh loads. A miss keeps the part-built body. Functional parts
-- stay: chassis, skids, ramps, seat, bed floors, bed hull, wheels, lights
-- and exhaust. Looks-only meshes are Massless and not queryable.
-- Wheels are one tyre mesh each, at the axle the part-built wheel already
-- uses. Body, glass, lights, bed and hitch share the vehicle root (ground
-- centre, front -Z). A MeshPart whose import pivot survived is PivotTo'd
-- there; otherwise the bounds' bottom centre sits on that root.

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

local function placeAtRoot(part: BasePart, size: Vector3, root: Vector3)
	if part:GetAttribute("MeshPivot") == "authored" then
		part:PivotTo(CFrame.new(root))
	else
		part.CFrame = CFrame.new(root + Vector3.new(0, size.Y / 2, 0))
	end
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
	local part = MeshKit.Create(piece.meshId, name, piece.size)
	if not part then
		return false
	end
	fidelity(part, role)
	if role ~= "Wheel" then
		MeshKit.Visual(part)
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
			placeAtRoot(part, part.Size, root)
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
