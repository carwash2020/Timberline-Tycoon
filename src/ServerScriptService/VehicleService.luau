--!strict
-- VehicleService: builds and owns player trucks.
--   * Every truck is built from its ItemCatalog entry (Shared/TruckLayout
--     says where each piece goes) in the player's own ParkingSlot, so
--     trucks never spawn inside each other.
--   * Driving, set by GameConfig.VehiclePhysics:
--       - Physics (default): a parked truck is anchored (parking brake).
--         When someone sits in the driver seat, the server unanchors it and
--         hands its physics to that player's device (network ownership),
--         where VehicleController steers it through two constraints: Drive
--         (a LinearVelocity: speed and grip) and Heading (an
--         AlignOrientation: direction, and staying upright). It collides
--         with trees and buildings. Getting out parks it again. A speed
--         check puts back a truck that moves faster than it can go (an
--         exploiter teleporting it).
--       - Arcade: the Phase 1 glide, moved by the server; passes through
--         things.
--   * The bed is a server-side list of logs, drawn as logs welded to it.
--   * Recall ("Truck to lot") and switching trucks rebuild the truck in the
--     player's slot, keeping the load when it fits.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DriveMath = require(ReplicatedStorage.Shared.DriveMath)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local TruckLayout = require(ReplicatedStorage.Shared.TruckLayout)
local WoodData = require(ReplicatedStorage.Shared.WoodData)

type TruckDef = ItemCatalog.TruckDef

local VehicleService = {}

local TRUCK_TAG = "Truck"
local SLOT_TAG = "ParkingSlot"
local WHEEL_CLEARANCE = 1.5 -- chassis pivot height above the ground; puts the wheels on it
local SPEED_CHECK_EVERY = 0.5 -- seconds
local SPEED_SLACK = 1.5 -- a truck may cover this many times its top speed (bumps, lag)
local SPEED_SLACK_STUDS = 8

local CHASSIS_COLOR = Color3.fromRGB(80, 55, 35)
local WOOD = Color3.fromRGB(101, 67, 33)
local WOOD2 = Color3.fromRGB(130, 90, 50)
local DARK = Color3.fromRGB(60, 55, 55)

export type BedEntry = { woodId: string, value: number }

type TruckRecord = {
	def: TruckDef,
	layout: TruckLayout.Layout,
	model: Model,
	chassis: BasePart,
	seat: VehicleSeat,
	bedFloor: BasePart?,
	drive: LinearVelocity,
	heading: AlignOrientation,
	bed: { BedEntry },
	bedFolder: Folder,
	slot: BasePart?,
	conns: { RBXScriptConnection },
	arcadeSpeed: number,
	-- Speed check (physics driving)
	lastGood: CFrame,
	lastCheck: number,
}

local trucks: { [number]: TruckRecord } = {} -- [userId]
local slotOwner: { [BasePart]: number } = {}
local lastRecall: { [number]: number } = {}
local overflowCount = 0

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

type Built = {
	model: Model,
	chassis: BasePart,
	seat: VehicleSeat,
	bedFloor: BasePart?,
	exhaust: BasePart,
	drive: LinearVelocity,
	heading: AlignOrientation,
}

-- Builds a truck around the origin, facing -Z, wheels touching y = 0.
-- Open-top like a farm truck: seat behind the hood, roll bar, then the bed.
local function buildTruckModel(def: TruckDef, layout: TruckLayout.Layout): Built
	local model = Instance.new("Model")
	model.Name = def.id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams in whole, tailgate included

	local function part(name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Position = pos
		p.Color = color
		p.Material = material
		p.CanCollide = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local W, L, front = layout.width, layout.length, layout.front
	local paint = Color3.fromHex(def.look.color)
	local trim = paint:Lerp(Color3.new(0, 0, 0), 0.3)
	local sideX = W / 2 - 0.15

	-- Chassis (PrimaryPart), top at y = 2.
	local chassis = part("Chassis", Vector3.new(W, 1, L), Vector3.new(0, 1.5, 0), CHASSIS_COLOR, Enum.Material.Wood)
	-- An invisible, frictionless skid under the chassis is what touches the
	-- ground (the wheels are only for looks); Drive supplies the grip.
	local skid = part("Skid", Vector3.new(W - 0.4, 1, L - 1), Vector3.new(0, 0.5, 0), DARK, Enum.Material.Plastic)
	skid.Transparency = 1
	skid.CanQuery = false
	skid.CanTouch = false
	skid.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)

	-- Cab: hood and dash in front of an open seat, roll bar behind it.
	part("Hood", Vector3.new(W, 1.3, 2.6), Vector3.new(0, 2.65, front + 1.3), paint, Enum.Material.Metal)
	part("Dash", Vector3.new(W, 0.9, 0.4), Vector3.new(0, 3.75, front + 2.8), trim, Enum.Material.Metal)
	for _, x in ipairs({ -(W / 2 - 0.7), W / 2 - 0.7 }) do
		local lamp = part(
			"Headlight",
			Vector3.new(0.7, 0.45, 0.2),
			Vector3.new(x, 2.75, front - 0.05),
			Color3.fromRGB(255, 226, 150),
			Enum.Material.Neon
		)
		lamp.CanCollide = false
	end
	local rollZ = front + TruckLayout.CabLength - 0.35
	for _, x in ipairs({ -sideX, sideX }) do
		part("RollBarPost", Vector3.new(0.3, 3, 0.3), Vector3.new(x, 3.5, rollZ), trim, Enum.Material.Metal)
	end
	part("RollBarTop", Vector3.new(W, 0.3, 0.3), Vector3.new(0, 5.1, rollZ), trim, Enum.Material.Metal)

	-- Bed, or the ATV's little rear rack.
	local bedFloor: BasePart? = nil
	local bedLength = layout.bedLength
	if bedLength > 0 then
		local floor = part(
			"BedFloor",
			Vector3.new(W, 0.5, bedLength),
			Vector3.new(0, 2.25, layout.bedCenterZ),
			WOOD,
			Enum.Material.Wood
		)
		bedFloor = floor
		local bedEnd = layout.bedStart + bedLength
		if def.look.bedWalls then
			part(
				"BedWallL",
				Vector3.new(0.3, 1.5, bedLength),
				Vector3.new(-sideX, 3.25, layout.bedCenterZ),
				WOOD2,
				Enum.Material.Wood
			)
			part(
				"BedWallR",
				Vector3.new(0.3, 1.5, bedLength),
				Vector3.new(sideX, 3.25, layout.bedCenterZ),
				WOOD,
				Enum.Material.Wood
			)
			part(
				"BedWallBack",
				Vector3.new(W, 1.5, 0.3),
				Vector3.new(0, 3.25, bedEnd - 0.15),
				WOOD2,
				Enum.Material.Wood
			)
			part(
				"BedWallFront",
				Vector3.new(W, 1.5, 0.3),
				Vector3.new(0, 3.25, layout.bedStart + 0.15),
				paint,
				Enum.Material.Metal
			)
		else
			-- A flat deck: a headboard and stake posts down both sides.
			part(
				"Headboard",
				Vector3.new(W, 2, 0.3),
				Vector3.new(0, 3.5, layout.bedStart + 0.15),
				paint,
				Enum.Material.Metal
			)
			local posts = math.max(2, math.floor(bedLength / 3) + 1)
			for i = 0, posts - 1 do
				local z = layout.bedStart + 0.3 + (bedLength - 0.6) * i / (posts - 1)
				for _, x in ipairs({ -sideX, sideX }) do
					part("Stake", Vector3.new(0.3, 2, 0.3), Vector3.new(x, 3.5, z), trim, Enum.Material.Metal)
				end
			end
		end
		-- Where the client's "Load logs" prompt hangs: just behind the tailgate.
		local loadPoint = Instance.new("Attachment")
		loadPoint.Name = "LoadPoint"
		loadPoint.Position = Vector3.new(0, 1, bedLength / 2 + 0.6)
		loadPoint.Parent = floor
	else
		part("Rack", Vector3.new(W - 0.4, 0.3, 1.2), Vector3.new(0, 2.6, L / 2 - 0.8), trim, Enum.Material.Metal)
	end

	-- Exhaust pipe that puffs a little smoke while someone's driving.
	local exhaust = part(
		"Exhaust",
		Vector3.new(0.4, 0.4, 0.8),
		Vector3.new(W / 2 - 0.5, 1.2, L / 2 + 0.2),
		DARK,
		Enum.Material.Metal
	)
	exhaust.CanCollide = false
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(120, 115, 110)
	smoke.Opacity = 0.12
	smoke.Size = 0.6
	smoke.RiseVelocity = 2
	smoke.Enabled = false
	smoke.Parent = exhaust

	-- Wheels (for looks: the skid carries the truck).
	for _, z in ipairs(layout.wheelZ) do
		for _, x in ipairs({ -layout.wheelX, layout.wheelX }) do
			local wheel = Instance.new("Part")
			wheel.Name = "Wheel"
			wheel.Shape = Enum.PartType.Cylinder
			wheel.Size = Vector3.new(0.8, 2, 2)
			wheel.Position = Vector3.new(x, 1, z)
			wheel.Color = DARK
			wheel.Material = Enum.Material.SmoothPlastic
			wheel.CanCollide = false
			wheel.Parent = model
		end
	end

	-- Driver seat, open to the sky so the driver sits in it, not inside a box.
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.Position = Vector3.new(0, 2.5, front + 3.9)
	seat.Color = Color3.fromRGB(90, 60, 40)
	seat.Material = Enum.Material.Fabric
	seat.CanCollide = false
	seat.Parent = model

	-- One rigid body: everything welded to the chassis, and only the chassis
	-- has mass. Parked = the chassis is anchored.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= chassis then
			d.Anchored = false
			d.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = chassis
			w.Part1 = d
			w.Parent = chassis
		end
	end
	chassis.Anchored = true

	-- Physics driving: the driver's VehicleController sets these each frame.
	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	attachment.Parent = chassis
	local drive = Instance.new("LinearVelocity")
	drive.Name = "Drive"
	drive.Attachment0 = attachment
	drive.RelativeTo = Enum.ActuatorRelativeTo.World
	drive.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane -- X/Z only; gravity keeps Y
	drive.PrimaryTangentAxis = Vector3.xAxis
	drive.SecondaryTangentAxis = Vector3.zAxis
	drive.PlaneVelocity = Vector2.zero
	drive.MaxForce = 0
	drive.Enabled = false
	drive.Parent = chassis
	local heading = Instance.new("AlignOrientation")
	heading.Name = "Heading"
	heading.Mode = Enum.OrientationAlignmentMode.OneAttachment
	heading.Attachment0 = attachment
	heading.Responsiveness = 30
	heading.MaxTorque = 0
	heading.Enabled = false
	heading.Parent = chassis

	model.PrimaryPart = chassis
	return {
		model = model,
		chassis = chassis,
		seat = seat,
		bedFloor = bedFloor,
		exhaust = exhaust,
		drive = drive,
		heading = heading,
	}
end

local function addBedVisual(rec: TruckRecord, entry: BedEntry, index: number)
	local floor = rec.bedFloor
	local slot = rec.layout.logSlots[index]
	if not floor or not slot then
		return
	end
	local wood = WoodData.Get(entry.woodId)
	local visual = Instance.new("Part")
	visual.Name = "BedLog"
	visual.Shape = Enum.PartType.Cylinder
	visual.Size = Vector3.new(rec.layout.logLength, TruckLayout.LogDiameter, TruckLayout.LogDiameter)
	visual.Color = if wood then wood.trunkColor else Color3.fromRGB(122, 82, 48)
	visual.Material = Enum.Material.Wood
	visual.CanCollide = false
	visual.CanQuery = false
	visual.CanTouch = false
	visual.Massless = true
	visual.CFrame = floor.CFrame * CFrame.new(slot)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = floor
	weld.Part1 = visual
	weld.Parent = visual
	visual.Parent = rec.bedFolder
end

---------------------------------------------------------------------------
-- Driving
---------------------------------------------------------------------------

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function onOccupantChanged(rec: TruckRecord, prompt: ProximityPrompt, smoke: Smoke?)
	local occupant = rec.seat.Occupant
	prompt.Enabled = occupant == nil -- no "Drive" prompt hovering over the driver
	if smoke then
		smoke.Enabled = occupant ~= nil
	end
	rec.arcadeSpeed = 0
	if not GameConfig.VehiclePhysics then
		return
	end
	if occupant then
		local driver = Players:GetPlayerFromCharacter(occupant.Parent)
		rec.chassis.Anchored = false
		if driver then
			rec.chassis:SetNetworkOwner(driver) -- the driver's device simulates it: smooth, no lag
		end
		rec.lastGood = rec.model:GetPivot()
		rec.lastCheck = os.clock()
		-- Size the forces to the truck plus its driver once the seat weld is in.
		task.defer(function()
			local mass = rec.chassis.AssemblyMass
			rec.drive.MaxForce = mass * 120
			rec.heading.MaxTorque = mass * 5000
			rec.heading.CFrame = rec.chassis.CFrame.Rotation
			rec.drive.PlaneVelocity = Vector2.zero
			rec.drive.Enabled = true
			rec.heading.Enabled = true
		end)
	else
		rec.drive.Enabled = false
		rec.heading.Enabled = false
		rec.drive.PlaneVelocity = Vector2.zero
		rec.chassis.Anchored = true -- parked; physics goes back to the server
	end
end

-- Physics driving: puts back a truck that moved further than it can drive.
local function speedCheck(rec: TruckRecord, ownerName: string)
	local now = os.clock()
	local elapsed = now - rec.lastCheck
	if elapsed < SPEED_CHECK_EVERY then
		return
	end
	rec.lastCheck = now
	local pivot = rec.model:GetPivot()
	local moved = flatDistance(pivot.Position, rec.lastGood.Position)
	if moved > rec.def.topSpeed * elapsed * SPEED_SLACK + SPEED_SLACK_STUDS then
		warn(
			string.format(
				"[AntiExploit] %s's truck moved %d studs in %.1fs; putting it back",
				ownerName,
				moved,
				elapsed
			)
		)
		rec.model:PivotTo(rec.lastGood)
		rec.chassis.AssemblyLinearVelocity = Vector3.zero
	else
		rec.lastGood = pivot
	end
end

-- Arcade driving: the server glides the (anchored) truck.
local function arcadeStep(rec: TruckRecord, dt: number)
	local seat = rec.seat
	rec.arcadeSpeed = DriveMath.Speed(rec.arcadeSpeed, seat.ThrottleFloat, rec.def.topSpeed, dt)
	local turn = DriveMath.Turn(rec.arcadeSpeed, seat.SteerFloat, rec.def.turnRate, dt)
	if math.abs(rec.arcadeSpeed) < 0.01 and turn == 0 then
		return
	end
	rec.model:PivotTo(rec.model:GetPivot() * CFrame.Angles(0, turn, 0) * CFrame.new(0, 0, -rec.arcadeSpeed * dt))
end

local function addDrivePrompt(rec: TruckRecord, ownerName: string, exhaust: BasePart)
	local seat = rec.seat
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Drive"
	prompt.ObjectText = string.format("%s's %s", ownerName, rec.def.displayName)
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
	table.insert(
		rec.conns,
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			onOccupantChanged(rec, prompt, smoke)
		end)
	)
end

---------------------------------------------------------------------------
-- Parking slots
---------------------------------------------------------------------------

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

local function slotCFrame(slot: BasePart?): CFrame
	if slot then
		local ground = slot.Position - Vector3.new(0, slot.Size.Y / 2, 0)
		return CFrame.new(ground + Vector3.new(0, WHEEL_CLEARANCE, 0)) * slot.CFrame.Rotation
	end
	-- More players than parking slots: line the extras up west of spawn.
	overflowCount += 1
	warn("[VehicleService] Out of parking slots; add more in MapBuilder")
	return CFrame.new(-20 - (overflowCount % 8) * 8, WHEEL_CLEARANCE, 56 - (overflowCount // 8) * 28)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

local function destroyTruck(rec: TruckRecord)
	for _, conn in ipairs(rec.conns) do
		conn:Disconnect()
	end
	rec.model:Destroy()
end

-- Builds the player's truck (replacing any they have) in their parking
-- slot. `load` refills the bed (a recall or a switch); returns how many of
-- those logs didn't fit.
function VehicleService.SpawnTruck(player: Player, truckId: string, load: { BedEntry }?): (Model, number)
	local def = ItemCatalog.GetTruck(truckId) or ItemCatalog.GetTruck("Rustbucket")
	assert(def, "[VehicleService] Rustbucket missing from ItemCatalog")

	local old = trucks[player.UserId]
	local slot = if old then old.slot else claimSlot(player.UserId)
	if old then
		destroyTruck(old)
	end

	local layout = TruckLayout.For(def)
	local built = buildTruckModel(def, layout)
	local model = built.model
	model:PivotTo(slotCFrame(slot))
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("TruckId", def.id)
	model:SetAttribute("BedCapacity", def.bedCapacity)
	model:SetAttribute("BedCount", 0)
	model:SetAttribute("TopSpeed", def.topSpeed) -- read by VehicleController
	model:SetAttribute("TurnRate", def.turnRate)
	CollectionService:AddTag(model, TRUCK_TAG)

	local bedFolder = Instance.new("Folder")
	bedFolder.Name = "BedVisuals"
	bedFolder.Parent = model
	model.Parent = workspace

	local rec: TruckRecord = {
		def = def,
		layout = layout,
		model = model,
		chassis = built.chassis,
		seat = built.seat,
		bedFloor = built.bedFloor,
		drive = built.drive,
		heading = built.heading,
		bed = {},
		bedFolder = bedFolder,
		slot = slot,
		conns = {},
		arcadeSpeed = 0,
		lastGood = model:GetPivot(),
		lastCheck = os.clock(),
	}
	trucks[player.UserId] = rec
	addDrivePrompt(rec, player.DisplayName, built.exhaust)
	table.insert(
		rec.conns,
		RunService.Heartbeat:Connect(function(dt: number)
			local occupant = rec.seat.Occupant
			if not occupant or not occupant.Parent then
				return
			end
			if GameConfig.VehiclePhysics then
				speedCheck(rec, player.Name)
			else
				arcadeStep(rec, dt)
			end
		end)
	)

	local dropped = 0
	for _, entry in ipairs(load or {}) do
		if not VehicleService.AddBedLog(player, entry) then
			dropped += 1
		end
	end
	player:SetAttribute("EquippedTruck", def.id)
	return model, dropped
end

function VehicleService.DespawnTruck(player: Player)
	local rec = trucks[player.UserId]
	if not rec then
		return
	end
	destroyTruck(rec)
	if rec.slot then
		slotOwner[rec.slot] = nil
	end
	trucks[player.UserId] = nil
	lastRecall[player.UserId] = nil
end

-- True if this player is sitting in their own truck's driver seat.
local function isDriving(player: Player, rec: TruckRecord): boolean
	local occupant = rec.seat.Occupant
	return occupant ~= nil and player.Character ~= nil and occupant.Parent == player.Character
end

-- "Truck to lot": rebuilds the player's truck in their parking slot, load
-- and all. Returns false and why not when it can't.
function VehicleService.Recall(player: Player): (boolean, string?)
	local rec = trucks[player.UserId]
	if not rec then
		return false, nil
	end
	if isDriving(player, rec) then
		return false, "Hop out first."
	end
	local now = os.clock()
	local wait = GameConfig.TruckRecallCooldown - (now - (lastRecall[player.UserId] or -math.huge))
	if wait > 0 then
		return false, string.format("Your truck's on its way. Try again in %d s.", math.ceil(wait))
	end
	lastRecall[player.UserId] = now
	VehicleService.SpawnTruck(player, rec.def.id, rec.bed)
	return true, nil
end

-- Swaps the player's truck for another they own (the Dealership). Refuses
-- while they drive, or when the load wouldn't fit in the new bed.
function VehicleService.Equip(player: Player, truckId: string): (boolean, string?)
	local def = ItemCatalog.GetTruck(truckId)
	local rec = trucks[player.UserId]
	if not def then
		return false, nil
	end
	if rec and isDriving(player, rec) then
		return false, "Hop out of your truck first."
	end
	if rec and #rec.bed > def.bedCapacity then
		return false, "Sell your load first: it won't fit in the " .. def.displayName .. "."
	end
	VehicleService.SpawnTruck(player, def.id, if rec then rec.bed else nil)
	return true, nil
end

function VehicleService.GetVehicle(player: Player): Model?
	local rec = trucks[player.UserId]
	return if rec then rec.model else nil
end

-- Where the "Load logs" prompt is (behind the tailgate), or nil for a truck
-- without a bed.
function VehicleService.GetLoadPoint(player: Player): Vector3?
	local rec = trucks[player.UserId]
	local floor = if rec then rec.bedFloor else nil
	local point = if floor then floor:FindFirstChild("LoadPoint") else nil
	return if point and point:IsA("Attachment") then point.WorldPosition else nil
end

function VehicleService.GetBedCapacity(player: Player): number
	local rec = trucks[player.UserId]
	return if rec then rec.def.bedCapacity else 0
end

function VehicleService.GetBedCount(player: Player): number
	local rec = trucks[player.UserId]
	return if rec then #rec.bed else 0
end

-- Adds a log to the bed (with a log you can see). False if full / no truck.
function VehicleService.AddBedLog(player: Player, entry: BedEntry): boolean
	local rec = trucks[player.UserId]
	if not rec or #rec.bed >= rec.def.bedCapacity then
		return false
	end
	table.insert(rec.bed, entry)
	rec.model:SetAttribute("BedCount", #rec.bed)
	addBedVisual(rec, entry, #rec.bed)
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
