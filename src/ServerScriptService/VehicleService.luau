-- VehicleService: builds and owns player trucks.
-- Phase 1: the Rustbucket only (bed capacity 6). Driving is arcade-style
-- CFrame movement while seated; proper vehicle physics arrives in Phase 4.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local VehicleService = {}

local TRUCK_TAG = "Truck"
local DRIVE_SPEED = 26 -- studs/sec at full throttle
local TURN_RATE = 1.4 -- rad/sec at full steer

-- [userId] -> { model, seat, bedFloor, bed = { {woodId, value} }, bedFolder, driveConn }
local trucks: { [number]: any } = {}

-- Bed visual slots (y/z offsets relative to the bed floor CFrame), 6 total.
local BED_SLOTS = {
	{ y = 0.85, z = -2 },
	{ y = 0.85, z = 0 },
	{ y = 0.85, z = 2 },
	{ y = 1.75, z = -1 },
	{ y = 1.75, z = 1 },
	{ y = 2.65, z = 0 },
}

local function weldTo(root: BasePart, part: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = part
	w.Parent = root
end

-- Builds the Rustbucket at the origin, facing -Z. Returns model + key parts.
local function buildTruckModel(): (Model, BasePart, VehicleSeat, BasePart)
	local model = Instance.new("Model")
	model.Name = "Rustbucket"

	local function part(name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Position = pos
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local RUST = Color3.fromRGB(150, 72, 48)
	local WOOD = Color3.fromRGB(101, 67, 33)
	local WOOD2 = Color3.fromRGB(130, 90, 50)
	local DARK = Color3.fromRGB(60, 55, 55)

	-- Chassis (PrimaryPart). Front of truck faces -Z.
	local chassis = part("Chassis", Vector3.new(4, 1, 12), Vector3.new(0, 1.5, 0),
		Color3.fromRGB(80, 55, 35), Enum.Material.Wood)
	-- Cab
	part("Cab", Vector3.new(4, 2.5, 3.5), Vector3.new(0, 3.25, -3.75), RUST, Enum.Material.Metal)
	part("CabRoof", Vector3.new(4.2, 0.4, 3.7), Vector3.new(0, 4.7, -3.75), WOOD2, Enum.Material.Wood)
	-- Bed (mismatched panels: held together by hope)
	local bedFloor = part("BedFloor", Vector3.new(4, 0.5, 7), Vector3.new(0, 2.25, 2.25), WOOD, Enum.Material.Wood)
	part("BedWallL", Vector3.new(0.3, 1.5, 7), Vector3.new(-1.85, 3.25, 2.25), WOOD2, Enum.Material.Wood)
	part("BedWallR", Vector3.new(0.3, 1.5, 7), Vector3.new(1.85, 3.25, 2.25), WOOD, Enum.Material.Wood)
	part("BedWallBack", Vector3.new(4, 1.5, 0.3), Vector3.new(0, 3.25, 5.6), WOOD2, Enum.Material.Wood)
	part("BedWallFront", Vector3.new(4, 1.5, 0.3), Vector3.new(0, 3.25, -1.1), RUST, Enum.Material.Wood)
	-- Wheels (visual only in Phase 1)
	for _, wx in ipairs({ -2.2, 2.2 }) do
		for _, wz in ipairs({ -3.5, 3.5 }) do
			local wheel = Instance.new("Part")
			wheel.Name = "Wheel"
			wheel.Shape = Enum.PartType.Cylinder
			wheel.Size = Vector3.new(0.8, 2, 2)
			wheel.Position = Vector3.new(wx, 1, wz)
			wheel.Color = DARK
			wheel.Material = Enum.Material.SmoothPlastic
			wheel.Anchored = true
			wheel.CanCollide = false
			wheel.Parent = model
			weldTo(chassis, wheel)
		end
	end
	-- Driver seat
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.Position = Vector3.new(0, 3.4, -3.75)
	seat.Color = Color3.fromRGB(90, 60, 40)
	seat.Material = Enum.Material.Fabric
	seat.Anchored = true
	seat.CanCollide = false
	seat.Parent = model
	weldTo(chassis, seat)

	-- Weld static body parts to the chassis (future-proofing for physics driving).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= chassis and d.Name ~= "Wheel" and not d:IsA("VehicleSeat") then
			weldTo(chassis, d)
		end
	end

	model.PrimaryPart = chassis
	return model, chassis, seat, bedFloor
end

local function addDrivePrompt(seat: VehicleSeat)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Drive"
	prompt.MaxActivationDistance = 8
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat
	prompt.Triggered:Connect(function(player: Player)
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid and seat.Occupant == nil then
			seat:Sit(humanoid)
		end
	end)
end

function VehicleService.SpawnTruck(player: Player, cframe: CFrame): Model
	VehicleService.DespawnTruck(player)

	local model, _chassis, seat, bedFloor = buildTruckModel()
	model:PivotTo(cframe)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("BedCapacity", 6)
	model.Parent = workspace
	CollectionService:AddTag(model, TRUCK_TAG)
	addDrivePrompt(seat)

	local bedFolder = Instance.new("Folder")
	bedFolder.Name = "BedVisuals"
	bedFolder.Parent = model

	local rec = {
		model = model,
		seat = seat,
		bedFloor = bedFloor,
		bed = {},
		bedFolder = bedFolder,
		driveConn = nil,
	}
	rec.driveConn = RunService.Heartbeat:Connect(function(dt: number)
		local occupant = seat.Occupant
		if not occupant or not occupant.Parent then
			return
		end
		local throttle = seat.Throttle
		local steer = seat.Steer
		if math.abs(throttle) < 0.02 and math.abs(steer) < 0.02 then
			return
		end
		local speed = throttle * DRIVE_SPEED
		local turn = -steer * TURN_RATE * dt * math.clamp(math.abs(speed) / 12, 0, 1)
		if speed < 0 then
			turn = -turn
		end
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, turn, 0) * CFrame.new(0, 0, -speed * dt))
	end)

	trucks[player.UserId] = rec
	return model
end

function VehicleService.DespawnTruck(player: Player)
	local rec = trucks[player.UserId]
	if not rec then
		return
	end
	if rec.driveConn then
		rec.driveConn:Disconnect()
	end
	if rec.model then
		rec.model:Destroy()
	end
	trucks[player.UserId] = nil
end

function VehicleService.GetVehicle(player: Player): Model?
	local rec = trucks[player.UserId]
	if rec then
		return rec.model
	end
	return nil
end

function VehicleService.GetBedCapacity(player: Player): number
	local rec = trucks[player.UserId]
	if not rec then
		return 0
	end
	return rec.model:GetAttribute("BedCapacity") or 6
end

function VehicleService.GetBedCount(player: Player): number
	local rec = trucks[player.UserId]
	if rec then
		return #rec.bed
	end
	return 0
end

-- Adds a log to the bed (with a mini visual). False if full / no truck.
function VehicleService.AddBedLog(player: Player, entry: { woodId: string, value: number }): boolean
	local rec = trucks[player.UserId]
	if not rec then
		return false
	end
	local capacity = rec.model:GetAttribute("BedCapacity") or 6
	if #rec.bed >= capacity then
		return false
	end
	table.insert(rec.bed, entry)
	local slot = BED_SLOTS[#rec.bed]
	if slot then
		local visual = Instance.new("Part")
		visual.Name = "BedLog"
		visual.Shape = Enum.PartType.Cylinder
		visual.Size = Vector3.new(3.2, 0.9, 0.9)
		visual.Color = Color3.fromRGB(122, 82, 48)
		visual.Material = Enum.Material.Wood
		visual.Anchored = true
		visual.CanCollide = false
		visual.CFrame = rec.bedFloor.CFrame * CFrame.new(0, slot.y, slot.z)
		visual.Parent = rec.bedFolder
	end
	return true
end

-- Removes and returns all bed logs (used by SellLogs). Clears visuals.
function VehicleService.TakeBedLogs(player: Player): { any }
	local rec = trucks[player.UserId]
	if not rec then
		return {}
	end
	local out = rec.bed
	rec.bed = {}
	rec.bedFolder:ClearAllChildren()
	return out
end

return VehicleService
