--!strict
-- VehicleService: builds and owns player trucks.
--   * Every truck is drawn by Shared/Art/TruckArt from its ItemCatalog entry
--     (Shared/TruckLayout says where each piece goes) in the player's own
--     ParkingSlot, so trucks never spawn inside each other. TruckArt.Rig
--     makes it one rigid body: the invisible chassis is its only massive
--     part, every other part is massless and welded to it, and each wheel
--     hangs on a Motor6D that VehicleFX spins and steers on every client.
--   * Driving, set by GameConfig.VehiclePhysics:
--       - Physics (default): a parked truck is anchored (parking brake).
--         When its owner sits in the driver seat, the server unanchors it
--         and hands its physics to their device (network ownership), where
--         VehicleController steers it through two constraints: Drive (a
--         LinearVelocity: speed and grip) and Heading (an AlignOrientation:
--         direction, and staying upright). It collides with trees and
--         buildings. Getting out brakes it and lets it settle, then parks it
--         upright on the ground. A speed check puts back a truck that moves
--         further than it can drive (an exploiter teleporting it), judged
--         against the last position it accepted, so a network stall doesn't
--         rubber-band an honest driver (Shared/VehicleLogic).
--       - Arcade: the Phase 1 glide, moved by the server; passes through
--         things.
--   * Only the owner drives. The Drive prompt refuses anyone else, and
--     anyone who ends up in the seat some other way is put out beside it.
--   * A hitched trailer (ItemCatalog.Trailers) is built onto the truck as
--     one rigid rig, and adds its bed to the truck's. A truck without a bed
--     (the Scout ATV) doesn't tow.
--   * The bed is a server-side list of logs, drawn as TreeArt logs welded to
--     it (the truck bed fills first, then the trailer). It's saved in
--     profile.truckBed on every change, so leaving the game never loses a
--     load: the first truck a player gets on joining is loaded from it.
--   * BedCount / BedCapacity are attributes on the truck AND on the player
--     (the HUD keeps working while the truck is streamed out).
--   * Recall ("Truck to lot") and switching trucks rebuild the truck in the
--     player's slot, keeping the load when it fits.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DriveMath = require(ReplicatedStorage.Shared.DriveMath)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local TruckArt = require(ReplicatedStorage.Shared.Art.TruckArt)
local TruckLayout = require(ReplicatedStorage.Shared.TruckLayout)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local ProfileService = require(script.Parent.ProfileService)

type TruckDef = ItemCatalog.TruckDef
type TrailerDef = ItemCatalog.TrailerDef

local VehicleService = {}

local TRUCK_TAG = "Truck"
local SLOT_TAG = "ParkingSlot"
local WHEEL_CLEARANCE = TruckLayout.ChassisY -- chassis pivot height above the ground; puts the wheels on it
local SPEED_CHECK_EVERY = 0.5 -- seconds
local SETTLE_MAX = 1.5 -- seconds a truck may roll after its driver gets out
local SETTLE_SPEED = 1.5 -- studs/s: slower than this counts as stopped
local PARK_TILT = math.rad(30) -- the steepest slope a truck parks on
local EXIT_GAP = 2 -- studs beside the truck where the driver steps out

export type BedEntry = VehicleLogic.BedEntry

type TruckRecord = {
	owner: Player,
	def: TruckDef,
	layout: TruckLayout.Layout,
	trailer: TrailerDef?, -- hitched and towing (nil for a truck that can't tow)
	trailerLayout: TruckLayout.TrailerLayout?,
	trailerBed: BasePart?,
	capacity: number, -- truck bed + trailer bed
	loadPoint: Attachment?,
	model: Model,
	chassis: BasePart,
	seat: VehicleSeat,
	prompt: ProximityPrompt,
	bedFloor: BasePart?,
	drive: LinearVelocity,
	heading: AlignOrientation,
	bed: { BedEntry },
	bedFolder: Folder,
	slot: BasePart?,
	overflowIndex: number?, -- an overflow spot, when every ParkingSlot is taken
	conns: { RBXScriptConnection },
	arcadeSpeed: number,
	driver: Humanoid?, -- the owner, while they sit in the driver seat
	settleToken: number, -- bumped to cancel a settle in progress
	-- Speed check (physics driving)
	lastGood: CFrame, -- the last position it accepted
	lastGoodAt: number, -- when (os.clock)
	lastCheck: number,
}

local trucks: { [number]: TruckRecord } = {} -- [userId]
local slotOwner: { [BasePart]: number } = {}
local overflowUsed: { [number]: boolean } = {}
local lastRecall: { [number]: number } = {}

local notify: ((Player, string) -> ())? = nil

-- A toast for `player` (GameServer's notify once Init has run).
local function tell(player: Player, message: string)
	local fn = notify
	if fn then
		fn(player, message)
	else
		warn(string.format("[VehicleService] (to %s) %s", player.Name, message))
	end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

type Built = {
	model: Model,
	chassis: BasePart,
	seat: VehicleSeat,
	bedFloor: BasePart?,
	trailerBed: BasePart?,
	loadPoint: Attachment?,
	drive: LinearVelocity,
	heading: AlignOrientation,
}

local function partNamed(model: Model, name: string): BasePart?
	local inst = model:FindFirstChild(name)
	return if inst and inst:IsA("BasePart") then inst else nil
end

-- Builds a truck (and trailer) around the origin, facing -Z, wheels on
-- y = 0: TruckArt's model, rigged, with the driving constraints.
local function buildTruckModel(
	def: TruckDef,
	layout: TruckLayout.Layout,
	trailer: TrailerDef?,
	trailerLayout: TruckLayout.TrailerLayout?
): Built
	local model = TruckArt.Build(def, layout, trailer, trailerLayout)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- streams in whole, trailer included
	TruckArt.Rig(model)

	local chassis = model.PrimaryPart
	local seatInst = model:FindFirstChild("DriverSeat")
	assert(chassis, "[VehicleService] TruckArt built no Chassis")
	assert(seatInst and seatInst:IsA("VehicleSeat"), "[VehicleService] TruckArt built no DriverSeat")
	local seat: VehicleSeat = seatInst
	seat.HeadsUpDisplay = false -- our HUD shows the speed, not Roblox's

	local point = model:FindFirstChild("LoadPoint", true)
	local loadPoint = if point and point:IsA("Attachment") then point else nil

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

	return {
		model = model,
		chassis = chassis,
		seat = seat,
		bedFloor = partNamed(model, "BedFloor"),
		trailerBed = partNamed(model, "TrailerBed"),
		loadPoint = loadPoint,
		drive = drive,
		heading = heading,
	}
end

-- Draws bed log `index` (the truck bed fills first, then the trailer): a
-- TreeArt log with its end caps, welded to the bed, massless, out of the way.
local function addBedVisual(rec: TruckRecord, entry: BedEntry, index: number)
	local floor: BasePart?, slot: Vector3?
	local truckSlots = #rec.layout.logSlots
	if index <= truckSlots then
		floor, slot = rec.bedFloor, rec.layout.logSlots[index]
	elseif rec.trailerLayout then
		floor, slot = rec.trailerBed, rec.trailerLayout.logSlots[index - truckSlots]
	end
	local wood = WoodData.Get(entry.woodId) or WoodData.Get("oak")
	if not floor or not slot or not wood then
		return
	end
	local log = TruckArt.BedLog(floor, slot, wood, rec.layout.logLength, index)
	log:SetAttribute("WoodId", entry.woodId)
	if entry.figure then
		log:SetAttribute("Figure", entry.figure) -- the Living Forest may mark figured logs
	end
	local logPart = log.PrimaryPart
	for _, d in ipairs(log:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	if logPart then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = floor
		weld.Part1 = logPart
		weld.Parent = logPart
	end
	log.Parent = rec.bedFolder
end

-- The bed's numbers, on the truck and on its owner.
local function publishBed(rec: TruckRecord)
	rec.model:SetAttribute("BedCount", #rec.bed)
	rec.owner:SetAttribute("BedCount", #rec.bed)
	rec.owner:SetAttribute("BedCapacity", rec.capacity)
end

-- Saves the bed into the owner's profile (ProfileStore writes it out).
local function saveBed(rec: TruckRecord)
	local profile = ProfileService.GetProfile(rec.owner)
	if profile then
		profile.truckBed = VehicleLogic.CopyBed(rec.bed)
	end
end

---------------------------------------------------------------------------
-- Getting in and out
---------------------------------------------------------------------------

-- Ray params that see the world but not this truck or any character.
local function worldParams(rec: TruckRecord, extra: Instance?): RaycastParams
	local skip: { Instance } = { rec.model }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	if extra then
		table.insert(skip, extra)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	params.RespectCanCollide = true -- skip leaves, zones, decoration
	return params
end

-- Puts someone who just left the seat on the ground beside the driver's
-- door (the left), when that spot is clear; else leaves them where the
-- seat's jump put them.
local function stepOut(rec: TruckRecord, humanoid: Humanoid)
	local char = humanoid.Parent
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not char or not char:IsA("Model") or not root or not root:IsA("BasePart") then
		return
	end
	if humanoid.Health <= 0 or humanoid.Sit or not rec.model.Parent then
		return
	end
	local seatCF = rec.seat.CFrame
	local door = seatCF * CFrame.new(-(rec.layout.width / 2 + EXIT_GAP), 0, 0)
	local params = worldParams(rec)
	local across = door.Position - seatCF.Position
	if workspace:Raycast(seatCF.Position, across, params) then
		return -- a wall or a tree on that side
	end
	local ground = workspace:Raycast(door.Position + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), params)
	if not ground then
		return
	end
	local height = if humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight + root.Size.Y / 2 else 3
	local facing = VehicleLogic.FlatFacing(seatCF.LookVector)
	local at = ground.Position + Vector3.new(0, height + 0.1, 0)
	char:PivotTo(CFrame.lookAt(at, at + facing))
end

-- Throws a stranger out of someone else's truck.
local function ejectStranger(rec: TruckRecord, humanoid: Humanoid, stranger: Player?)
	local weld = rec.seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	humanoid.Sit = false
	if stranger then
		tell(
			stranger,
			string.format("That's %s's %s. Yours waits in the parking lot.", rec.owner.DisplayName, rec.def.displayName)
		)
	end
	task.defer(stepOut, rec, humanoid)
end

-- True when the truck rests on something solid.
local function grounded(rec: TruckRecord): boolean
	local origin = rec.chassis.Position
	local hit = workspace:Raycast(origin, -rec.chassis.CFrame.UpVector * (WHEEL_CLEARANCE + 1), worldParams(rec))
	return hit ~= nil
end

-- Parks the truck where it is: upright on the ground under it, anchored.
local function park(rec: TruckRecord)
	rec.drive.Enabled = false
	rec.heading.Enabled = false
	rec.drive.PlaneVelocity = Vector2.zero
	local pivot = rec.chassis.CFrame
	local hit = workspace:Raycast(pivot.Position + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), worldParams(rec))
	local target = if hit
		then VehicleLogic.ParkedCFrame(hit.Position, hit.Normal, pivot.LookVector, WHEEL_CLEARANCE, PARK_TILT)
		else VehicleLogic.HeadingCFrame(pivot.LookVector, Vector3.yAxis) + pivot.Position
	rec.chassis.AssemblyLinearVelocity = Vector3.zero
	rec.chassis.AssemblyAngularVelocity = Vector3.zero
	rec.model:PivotTo(target)
	rec.chassis.Anchored = true -- parked; physics goes back to the server
end

-- Holds the truck's current direction, upright (the driver's device aimed
-- Heading every frame, but those changes never reached the server, so the
-- server's copy still points wherever the truck faced when they got in).
local function holdHeading(rec: TruckRecord)
	local cf = rec.chassis.CFrame
	rec.heading.CFrame = VehicleLogic.HeadingCFrame(cf.LookVector, VehicleLogic.ClampTilt(cf.UpVector, PARK_TILT))
end

-- After the driver gets out: brake to a stop (Drive holds zero speed,
-- Heading keeps it upright, the server simulates it), wait until it's
-- slow and on the ground (at most SETTLE_MAX), then park it. A new driver
-- or a rebuild cancels it.
local function settle(rec: TruckRecord)
	rec.settleToken += 1
	local token = rec.settleToken
	rec.drive.PlaneVelocity = Vector2.zero
	holdHeading(rec)
	pcall(function()
		rec.chassis:SetNetworkOwner(nil)
	end)
	local started = os.clock()
	while os.clock() - started < SETTLE_MAX do
		task.wait(0.1)
		if rec.settleToken ~= token or not rec.model.Parent or rec.chassis.Anchored then
			return
		end
		holdHeading(rec)
		if rec.chassis.AssemblyLinearVelocity.Magnitude < SETTLE_SPEED and grounded(rec) then
			break
		end
	end
	if rec.settleToken ~= token or not rec.model.Parent then
		return
	end
	park(rec)
end

-- The owner sat down: physics goes to their device, sized to the truck.
local function startDriving(rec: TruckRecord, driver: Player)
	rec.settleToken += 1 -- a settle in progress stops here
	rec.chassis.Anchored = false
	rec.chassis:SetNetworkOwner(driver) -- the driver's device simulates it: smooth, no lag
	rec.lastGood = rec.model:GetPivot()
	rec.lastGoodAt = os.clock()
	rec.lastCheck = os.clock()
	-- Size the forces to the truck plus its driver once the seat weld is in.
	task.defer(function()
		if rec.driver == nil or not rec.model.Parent then
			return
		end
		local mass = rec.chassis.AssemblyMass
		rec.drive.MaxForce = mass * 120
		rec.heading.MaxTorque = mass * 5000
		rec.heading.CFrame = rec.chassis.CFrame.Rotation
		rec.drive.PlaneVelocity = Vector2.zero
		rec.drive.Enabled = true
		rec.heading.Enabled = true
	end)
end

local function onOccupantChanged(rec: TruckRecord)
	local occupant = rec.seat.Occupant
	rec.prompt.Enabled = occupant == nil -- no "Drive" prompt hovering over the driver
	rec.arcadeSpeed = 0
	if occupant then
		local player = Players:GetPlayerFromCharacter(occupant.Parent)
		if player ~= rec.owner then
			ejectStranger(rec, occupant, player)
			return
		end
		rec.driver = occupant
		if GameConfig.VehiclePhysics and player then
			startDriving(rec, player)
		end
		return
	end
	local driver = rec.driver
	rec.driver = nil
	if not driver then
		return -- a stranger was put out
	end
	if GameConfig.VehiclePhysics then
		task.spawn(settle, rec)
	end
	task.defer(stepOut, rec, driver)
end

-- Physics driving: puts back a truck that moved further than it can drive.
local function speedCheck(rec: TruckRecord)
	local now = os.clock()
	if now - rec.lastCheck < SPEED_CHECK_EVERY then
		return
	end
	rec.lastCheck = now
	local pivot = rec.model:GetPivot()
	local verdict =
		VehicleLogic.JudgeMove(rec.lastGood.Position, pivot.Position, now - rec.lastGoodAt, rec.def.topSpeed)
	if verdict == "ok" then
		rec.lastGood = pivot
		rec.lastGoodAt = now
	elseif verdict == "tooFar" then
		warn(
			string.format(
				"[AntiExploit] %s's truck moved %d studs in %.1fs; putting it back",
				rec.owner.Name,
				math.floor((pivot.Position - rec.lastGood.Position).Magnitude),
				now - rec.lastGoodAt
			)
		)
		rec.model:PivotTo(rec.lastGood)
		rec.chassis.AssemblyLinearVelocity = Vector3.zero
		rec.lastGoodAt = now
	end
	-- "still": nothing new arrived (or it's parked); keep the clock running.
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

local function makeDrivePrompt(seat: VehicleSeat, owner: Player, def: TruckDef): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DrivePrompt"
	prompt.ActionText = "Drive"
	prompt.ObjectText = string.format("%s's %s", owner.DisplayName, def.displayName)
	prompt.MaxActivationDistance = 7
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OwnerId", owner.UserId) -- VehicleFX hides it from everyone else
	prompt.Parent = seat
	return prompt
end

-- Only the owner gets in; anyone else hears whose truck it is.
local function onDrivePrompt(rec: TruckRecord, player: Player)
	if player ~= rec.owner then
		tell(
			player,
			string.format("That's %s's %s. Yours waits in the parking lot.", rec.owner.DisplayName, rec.def.displayName)
		)
		return
	end
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if humanoid and humanoid.Health > 0 and rec.seat.Occupant == nil then
		rec.seat:Sit(humanoid)
	end
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

-- More players than parking slots: a spot in the overflow rows, held
-- until the player leaves (so rebuilding never walks it along).
local function claimOverflow(): number
	local index = VehicleLogic.NextFreeIndex(overflowUsed)
	overflowUsed[index] = true
	warn("[VehicleService] Out of parking slots; add more in MapBuilder")
	return index
end

local function slotCFrame(slot: BasePart?, overflowIndex: number?): CFrame
	if slot then
		local ground = slot.Position - Vector3.new(0, slot.Size.Y / 2, 0)
		return CFrame.new(ground + Vector3.new(0, WHEEL_CLEARANCE, 0)) * slot.CFrame.Rotation
	end
	local spot = VehicleLogic.OverflowSpot(overflowIndex or 0)
	return CFrame.new(spot.X, WHEEL_CLEARANCE, spot.Z)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- `notifyFn` shows a toast (GameServer's notify). Without it, messages for
-- players go to Output.
function VehicleService.Init(notifyFn: (Player, string) -> ())
	notify = notifyFn
end

local function destroyTruck(rec: TruckRecord)
	rec.settleToken += 1
	for _, conn in ipairs(rec.conns) do
		conn:Disconnect()
	end
	rec.model:Destroy()
end

-- The trailer a truck actually tows: none for a truck without a bed.
local function towedTrailer(def: TruckDef, trailerId: string?): TrailerDef?
	if def.bedCapacity <= 0 or not trailerId or trailerId == "" then
		return nil
	end
	return ItemCatalog.GetTrailer(trailerId)
end

local function capacityOf(def: TruckDef, trailer: TrailerDef?): number
	return def.bedCapacity + (if trailer then trailer.extraCapacity else 0)
end

-- What was in this player's bed when they last played (profile.truckBed).
local function savedBed(player: Player, capacity: number): ({ BedEntry }, number)
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return {}, 0
	end
	return VehicleLogic.CleanBed(profile.truckBed, function(woodId: string): boolean
		return WoodData.Get(woodId) ~= nil
	end, capacity)
end

-- Builds the player's truck (replacing any they have) in their parking
-- slot, with `trailerId` hitched behind if it can tow. `load` refills the
-- bed (a recall or a switch); with no `load`, the bed comes back from the
-- player's save. Returns the model and how many logs didn't fit.
function VehicleService.SpawnTruck(
	player: Player,
	truckId: string,
	load: { BedEntry }?,
	trailerId: string?
): (Model, number)
	local def = ItemCatalog.GetTruck(truckId) or ItemCatalog.GetTruck("Rustbucket")
	assert(def, "[VehicleService] Rustbucket missing from ItemCatalog")

	local old = trucks[player.UserId]
	local slot = if old then old.slot else claimSlot(player.UserId)
	local overflowIndex = if old then old.overflowIndex else nil
	if not slot and overflowIndex == nil then
		overflowIndex = claimOverflow()
	end
	if old then
		destroyTruck(old)
	end

	local layout = TruckLayout.For(def)
	local trailer = towedTrailer(def, trailerId)
	local trailerLayout = if trailer then TruckLayout.ForTrailer(trailer, layout) else nil
	local capacity = capacityOf(def, trailer)
	local dropped = 0
	if load == nil then
		local restored, lost = savedBed(player, capacity)
		load, dropped = restored, lost
		if lost > 0 then
			warn(string.format("[VehicleService] %s: %d saved bed log(s) couldn't be restored", player.Name, lost))
		end
	end

	local built = buildTruckModel(def, layout, trailer, trailerLayout)
	local model = built.model
	-- Centre the whole rig (truck + trailer) on the parking slot.
	local rigShift = if trailerLayout then trailerLayout.length / 2 else 0
	model:PivotTo(slotCFrame(slot, overflowIndex) * CFrame.new(0, 0, -rigShift))
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("TruckId", def.id)
	model:SetAttribute("TrailerId", if trailer then trailer.id else "")
	model:SetAttribute("BedCapacity", capacity)
	model:SetAttribute("BedCount", 0)
	model:SetAttribute("TopSpeed", def.topSpeed) -- read by VehicleController
	model:SetAttribute("TurnRate", def.turnRate)
	CollectionService:AddTag(model, TRUCK_TAG)

	local bedFolder = Instance.new("Folder")
	bedFolder.Name = "BedVisuals"
	bedFolder.Parent = model
	-- Everything clients look for is in place before the truck replicates.
	local prompt = makeDrivePrompt(built.seat, player, def)
	model.Parent = workspace

	local now = os.clock()
	local rec: TruckRecord = {
		owner = player,
		def = def,
		layout = layout,
		trailer = trailer,
		trailerLayout = trailerLayout,
		trailerBed = built.trailerBed,
		capacity = capacity,
		loadPoint = built.loadPoint,
		model = model,
		chassis = built.chassis,
		seat = built.seat,
		prompt = prompt,
		bedFloor = built.bedFloor,
		drive = built.drive,
		heading = built.heading,
		bed = {},
		bedFolder = bedFolder,
		slot = slot,
		overflowIndex = overflowIndex,
		conns = {},
		arcadeSpeed = 0,
		driver = nil,
		settleToken = 0,
		lastGood = model:GetPivot(),
		lastGoodAt = now,
		lastCheck = now,
	}
	trucks[player.UserId] = rec
	table.insert(
		rec.conns,
		rec.prompt.Triggered:Connect(function(who: Player)
			onDrivePrompt(rec, who)
		end)
	)
	table.insert(
		rec.conns,
		rec.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			onOccupantChanged(rec)
		end)
	)
	table.insert(
		rec.conns,
		RunService.Heartbeat:Connect(function(dt: number)
			if not rec.driver or not rec.driver.Parent then
				return
			end
			if GameConfig.VehiclePhysics then
				speedCheck(rec)
			else
				arcadeStep(rec, dt)
			end
		end)
	)

	for _, entry in ipairs(load or {}) do
		if not VehicleService.AddBedLog(player, entry) then
			dropped += 1
		end
	end
	publishBed(rec)
	saveBed(rec) -- the save matches what's really in the bed now
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
	if rec.overflowIndex then
		overflowUsed[rec.overflowIndex] = nil
	end
	trucks[player.UserId] = nil
	lastRecall[player.UserId] = nil
	player:SetAttribute("BedCount", 0)
	player:SetAttribute("BedCapacity", 0)
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
	local remaining = GameConfig.TruckRecallCooldown - (now - (lastRecall[player.UserId] or -math.huge))
	if remaining > 0 then
		return false, string.format("Your truck's on its way. Try again in %d s.", math.ceil(remaining))
	end
	lastRecall[player.UserId] = now
	VehicleService.SpawnTruck(player, rec.def.id, rec.bed, if rec.trailer then rec.trailer.id else nil)
	return true, nil
end

-- Swaps the player's rig (the Dealership): truck `truckId` towing
-- `trailerId` ("" or nil for none). Refuses while they drive, or when the
-- load wouldn't fit the new bed space.
function VehicleService.Equip(player: Player, truckId: string, trailerId: string?): (boolean, string?)
	local def = ItemCatalog.GetTruck(truckId)
	local rec = trucks[player.UserId]
	if not def then
		return false, nil
	end
	if rec and isDriving(player, rec) then
		return false, "Hop out of your truck first."
	end
	if rec and #rec.bed > capacityOf(def, towedTrailer(def, trailerId)) then
		return false, "Sell your load first: it won't fit."
	end
	VehicleService.SpawnTruck(player, def.id, if rec then rec.bed else nil, trailerId)
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
	local point = if rec then rec.loadPoint else nil
	return if point then point.WorldPosition else nil
end

function VehicleService.GetBedCapacity(player: Player): number
	local rec = trucks[player.UserId]
	return if rec then rec.capacity else 0
end

function VehicleService.GetBedCount(player: Player): number
	local rec = trucks[player.UserId]
	return if rec then #rec.bed else 0
end

-- Adds a log to the bed (with a log you can see). False if full / no truck.
function VehicleService.AddBedLog(player: Player, entry: BedEntry): boolean
	local rec = trucks[player.UserId]
	if not rec or #rec.bed >= rec.capacity then
		return false
	end
	local clean: BedEntry = { woodId = entry.woodId, value = entry.value, figure = entry.figure }
	table.insert(rec.bed, clean)
	addBedVisual(rec, clean, #rec.bed)
	publishBed(rec)
	saveBed(rec)
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
	rec.bedFolder:ClearAllChildren()
	publishBed(rec)
	saveBed(rec)
	return out
end

return VehicleService
