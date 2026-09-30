--!strict
-- VehicleService: builds and owns player trucks.
-- Phase 1: the Rustbucket only. Driving is arcade-style CFrame movement while
-- seated; proper vehicle physics arrives in Phase 4.
-- Each player's truck spawns in its own "ParkingSlot" (built by MapBuilder),
-- so trucks never spawn inside each other.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local WoodData = require(ReplicatedStorage.Shared.WoodData)

local VehicleService = {}

local TRUCK_TAG = "Truck"
local SLOT_TAG = "ParkingSlot"
local DRIVE_SPEED = 26 -- studs/sec at full throttle
local TURN_RATE = 1.4 -- rad/sec at full steer
local WHEEL_CLEARANCE = 1.5 -- chassis pivot height above the ground; puts the wheels on it

export type BedEntry = { woodId: string, value: number }

type TruckRecord = {
	model: Model,
	seat: VehicleSeat,
	bedFloor: BasePart,
	bed: { BedEntry },
	bedFolder: Folder,
	capacity: number,
	driveConn: RBXScriptConnection?,
	slot: BasePart?,
}

local trucks: { [number]: TruckRecord } = {} -- [userId]
local slotOwner: { [BasePart]: number } = {}
local overflowCount = 0

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

-- Builds the Rustbucket around the origin, facing -Z, wheels touching y=0.
-- Open-top like a farm truck: seat behind a rusty hood, roll bar, wooden bed.
local function buildTruckModel(): (Model, BasePart, VehicleSeat, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Name = "Rustbucket"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams in whole, tailgate included

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
	local RUST_DARK = Color3.fromRGB(110, 55, 40)
	local WOOD = Color3.fromRGB(101, 67, 33)
	local WOOD2 = Color3.fromRGB(130, 90, 50)
	local DARK = Color3.fromRGB(60, 55, 55)

	-- Chassis (PrimaryPart), top at y=2. Front of truck faces -Z.
	local chassis =
		part("Chassis", Vector3.new(4, 1, 12), Vector3.new(0, 1.5, 0), Color3.fromRGB(80, 55, 35), Enum.Material.Wood)
	-- Hood + dashboard in front of an open seat.
	part("Hood", Vector3.new(4, 1.3, 2.6), Vector3.new(0, 2.65, -4.7), RUST, Enum.Material.Metal)
	part("Dash", Vector3.new(4, 0.9, 0.4), Vector3.new(0, 3.75, -3.5), RUST_DARK, Enum.Material.Metal)
	for _, x in ipairs({ -1.3, 1.3 }) do
		local lamp = part(
			"Headlight",
			Vector3.new(0.7, 0.45, 0.2),
			Vector3.new(x, 2.75, -6.05),
			Color3.fromRGB(255, 226, 150),
			Enum.Material.Neon
		)
		lamp.CanCollide = false
	end
	-- Roll bar behind the seat (the whole cab, really).
	for _, x in ipairs({ -1.85, 1.85 }) do
		part("RollBarPost", Vector3.new(0.3, 3, 0.3), Vector3.new(x, 3.5, -1.35), RUST_DARK, Enum.Material.Metal)
	end
	part("RollBarTop", Vector3.new(4, 0.3, 0.3), Vector3.new(0, 5.1, -1.35), RUST_DARK, Enum.Material.Metal)
	-- Bed (mismatched panels: held together by hope).
	local bedFloor = part("BedFloor", Vector3.new(4, 0.5, 7), Vector3.new(0, 2.25, 2.25), WOOD, Enum.Material.Wood)
	part("BedWallL", Vector3.new(0.3, 1.5, 7), Vector3.new(-1.85, 3.25, 2.25), WOOD2, Enum.Material.Wood)
	part("BedWallR", Vector3.new(0.3, 1.5, 7), Vector3.new(1.85, 3.25, 2.25), WOOD, Enum.Material.Wood)
	part("BedWallBack", Vector3.new(4, 1.5, 0.3), Vector3.new(0, 3.25, 5.6), WOOD2, Enum.Material.Wood)
	part("BedWallFront", Vector3.new(4, 1.5, 0.3), Vector3.new(0, 3.25, -1.1), RUST, Enum.Material.Wood)
	-- Exhaust pipe that puffs a little smoke while someone's driving.
	local exhaust = part("Exhaust", Vector3.new(0.4, 0.4, 0.8), Vector3.new(1.5, 1.2, 6.2), DARK, Enum.Material.Metal)
	exhaust.CanCollide = false
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(120, 115, 110)
	smoke.Opacity = 0.12
	smoke.Size = 0.6
	smoke.RiseVelocity = 2
	smoke.Enabled = false
	smoke.Parent = exhaust
	-- Wheels (visual only in Phase 1)
	for _, wx in ipairs({ -2.2, 2.2 }) do
		for _, wz in ipairs({ -4, 4 }) do
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
		end
	end
	-- Driver seat, open to the sky so the driver sits in it, not inside a box.
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.Position = Vector3.new(0, 2.5, -2.3)
	seat.Color = Color3.fromRGB(90, 60, 40)
	seat.Material = Enum.Material.Fabric
	seat.Anchored = true
	seat.CanCollide = false
	seat.Parent = model

	-- Where the client's "Load logs" prompt hangs: just behind the tailgate.
	local loadPoint = Instance.new("Attachment")
	loadPoint.Name = "LoadPoint"
	loadPoint.Position = Vector3.new(0, 1, 3.6)
	loadPoint.Parent = bedFloor

	-- Weld everything to the chassis (future-proofing for physics driving).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= chassis then
			weldTo(chassis, d)
		end
	end

	model.PrimaryPart = chassis
	return model, chassis, seat, bedFloor, exhaust
end

local function addDrivePrompt(seat: VehicleSeat, ownerName: string, exhaust: BasePart)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Drive"
	prompt.ObjectText = ownerName .. "'s Rustbucket"
	prompt.MaxActivationDistance = 7
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = seat
	prompt.Triggered:Connect(function(player: Player)
		local char = player.Character
		local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if humanoid and seat.Occupant == nil then
			seat:Sit(humanoid)
		end
	end)
	local smoke = exhaust:FindFirstChildOfClass("Smoke")
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupied = seat.Occupant ~= nil
		prompt.Enabled = not occupied -- no "Drive" prompt hovering over the driver
		if smoke then
			smoke.Enabled = occupied
		end
	end)
end

local function claimSlot(userId: number): BasePart?
	local slots: { BasePart } = {}
	for _, inst in ipairs(CollectionService:GetTagged(SLOT_TAG)) do
		if inst:IsA("BasePart") then
			table.insert(slots, inst)
		end
	end
	table.sort(slots, function(a, b)
		return ((a:GetAttribute("Index") :: number?) or 0) < ((b:GetAttribute("Index") :: number?) or 0)
	end)
	for _, slot in ipairs(slots) do
		if slotOwner[slot] == nil then
			slotOwner[slot] = userId
			return slot
		end
	end
	return nil
end

function VehicleService.SpawnTruck(player: Player, truckId: string): Model
	VehicleService.DespawnTruck(player)

	local def = ItemCatalog.GetTruck(truckId) or ItemCatalog.GetTruck("Rustbucket")
	assert(def, "[VehicleService] Rustbucket missing from ItemCatalog")

	local slot = claimSlot(player.UserId)
	local spawnCFrame: CFrame
	if slot then
		-- Measured from the ground under the pad, since arcade driving keeps
		-- the truck at a fixed height once it leaves the lot.
		local ground = slot.Position - Vector3.new(0, slot.Size.Y / 2, 0)
		spawnCFrame = CFrame.new(ground + Vector3.new(0, WHEEL_CLEARANCE, 0)) * slot.CFrame.Rotation
	else
		-- More players than parking slots: line the extras up west of spawn.
		overflowCount += 1
		spawnCFrame = CFrame.new(-16 - (overflowCount % 8) * 7, WHEEL_CLEARANCE, 50 - (overflowCount // 8) * 16)
		warn("[VehicleService] Out of parking slots; add more in MapBuilder")
	end

	local model, _chassis, seat, bedFloor, exhaust = buildTruckModel()
	model:PivotTo(spawnCFrame)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("BedCapacity", def.bedCapacity)
	model:SetAttribute("BedCount", 0)
	CollectionService:AddTag(model, TRUCK_TAG)
	model.Parent = workspace
	addDrivePrompt(seat, player.DisplayName, exhaust)

	local bedFolder = Instance.new("Folder")
	bedFolder.Name = "BedVisuals"
	bedFolder.Parent = model

	local rec: TruckRecord = {
		model = model,
		seat = seat,
		bedFloor = bedFloor,
		bed = {},
		bedFolder = bedFolder,
		capacity = def.bedCapacity,
		driveConn = nil,
		slot = slot,
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
	if rec.slot then
		slotOwner[rec.slot] = nil
	end
	rec.model:Destroy()
	trucks[player.UserId] = nil
end

function VehicleService.GetVehicle(player: Player): Model?
	local rec = trucks[player.UserId]
	return if rec then rec.model else nil
end

function VehicleService.GetBedCapacity(player: Player): number
	local rec = trucks[player.UserId]
	return if rec then rec.capacity else 0
end

function VehicleService.GetBedCount(player: Player): number
	local rec = trucks[player.UserId]
	return if rec then #rec.bed else 0
end

-- Adds a log to the bed (with a mini visual). False if full / no truck.
function VehicleService.AddBedLog(player: Player, entry: BedEntry): boolean
	local rec = trucks[player.UserId]
	if not rec or #rec.bed >= rec.capacity then
		return false
	end
	table.insert(rec.bed, entry)
	rec.model:SetAttribute("BedCount", #rec.bed)
	local slot = BED_SLOTS[#rec.bed]
	if slot then
		local wood = WoodData.Get(entry.woodId)
		local visual = Instance.new("Part")
		visual.Name = "BedLog"
		visual.Shape = Enum.PartType.Cylinder
		visual.Size = Vector3.new(3.2, 0.9, 0.9)
		visual.Color = if wood then wood.trunkColor else Color3.fromRGB(122, 82, 48)
		visual.Material = Enum.Material.Wood
		visual.Anchored = true
		visual.CanCollide = false
		visual.CanQuery = false
		visual.CFrame = rec.bedFloor.CFrame * CFrame.new(0, slot.y, slot.z)
		visual.Parent = rec.bedFolder
	end
	return true
end

-- Removes and returns all bed logs (used by SellLogs). Clears visuals.
function VehicleService.TakeBedLogs(player: Player): { BedEntry }
	local rec = trucks[player.UserId]
	if not rec then
		return {}
	end
	local out = rec.bed
	rec.bed = {}
	rec.model:SetAttribute("BedCount", 0)
	rec.bedFolder:ClearAllChildren()
	return out
end

return VehicleService
