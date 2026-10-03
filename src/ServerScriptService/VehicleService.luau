--!strict
-- VehicleService: builds and owns player trucks.
--   * Every truck is drawn by Shared/Art/TruckArt from its ItemCatalog entry
--     (Shared/TruckLayout says where each piece goes) in the player's own
--     ParkingSlot. The bays come in sizes (WorldPlan.ParkingBays, phase
--     12): each rig takes the smallest free one it fits, centred in it
--     (VehicleLogic.BayChoices), and a rebuild (a recall, a switch at the
--     Dealership) moves it to a better fit when there is one. A rig longer
--     than every free bay parks with its tail at a bay's tail and its nose
--     out over the pull-out; with no bay at all, in an overflow spot.
--     Trucks never spawn inside each other: a truck parked in the way is
--     sent back to its own spot, else the rig takes its next choice that's
--     clear. TruckArt.Rig makes it one rigid body: the
--     invisible chassis is its only massive part, every other part is
--     massless and welded to it, and each wheel hangs on a Motor6D that
--     VehicleFX spins and steers on every client.
--   * Driving, set by GameConfig.VehiclePhysics:
--       - Physics (default): a parked truck is anchored (parking brake).
--         When its owner sits in the driver seat, the server unanchors it
--         and hands its physics to their device (network ownership), where
--         VehicleController steers it through two constraints: Drive (a
--         LinearVelocity on the rear axle: speed and grip, so the truck
--         turns about its rear wheels) and Heading (an AlignOrientation:
--         direction, and staying upright). It collides with trees and
--         buildings. Getting out brakes it and lets it settle, then parks it
--         where it comes to rest (set upright on the ground under its
--         corners only if it tipped over, or never landed). A speed check
--         puts back a truck that moves further than it can drive (an
--         exploiter teleporting it), judged against the last position it
--         accepted, so a short network stall doesn't rubber-band an honest
--         driver (Shared/VehicleLogic). It runs every half second, and right
--         away when the position matters: the driver getting out, and the
--         sale (TrustedTruckPosition). A truck it puts back is stopped and
--         simulated by the server for a moment.
--       - Arcade: the Phase 1 glide, moved by the server; passes through
--         things.
--   * Only the owner drives. The Drive prompt refuses anyone else, and
--     anyone who ends up in the seat some other way is put out beside it.
--   * A hitched trailer (ItemCatalog.Trailers) is built onto the truck as
--     one rigid rig, and adds its bed to the truck's. A truck without a bed
--     (the Scout ATV) doesn't tow.
--   * The bed is a server-side list of logs, drawn as TreeArt logs welded to
--     it (the truck bed fills first, then the trailer). It's saved in
--     profile.truckBed on every change, and where the truck is in
--     profile.truckAt (also as it drives), so leaving the game never loses
--     a load: on joining it's loaded back into the truck if the truck was
--     in town, or waits on the ground where the truck was.
--   * BedCount / BedCapacity are attributes on the truck AND on the player
--     (the HUD keeps working while the truck is streamed out).
--   * Recall ("Send truck home") and switching trucks rebuild the truck in the
--     player's slot. Loose wood on the beds is TruckLoad's (the hooks
--     below). Old bed-slot logs in profile.truckBed, if a save still has
--     them, come back on the truck; MigrateV2 buys that list back into
--     cash before the first spawn.
--   * Loose wood rides on the beds (TruckLoad) through three hooks
--     (VehicleService.Hooks): the driver changing, a truck being rebuilt,
--     and how many pieces ride on a bed.
--   * TruckSlotDistance on the player: how far their truck is from its own
--     parking spot, in whole studs (Shared/TruckHome), checked twice a
--     second and sent only when it moves a couple of studs; nil with no
--     truck. VehicleController shows "Send truck home" from it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DriveMath = require(ReplicatedStorage.Shared.DriveMath)
local ForestArt = require(ReplicatedStorage.Shared.Art.ForestArt)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local TruckArt = require(ReplicatedStorage.Shared.Art.TruckArt)
local TruckHome = require(ReplicatedStorage.Shared.TruckHome)
local TruckLayout = require(ReplicatedStorage.Shared.TruckLayout)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local ProfileService = require(script.Parent.ProfileService)
local TerrainBuilder = require(script.Parent.TerrainBuilder)

type TruckDef = ItemCatalog.TruckDef
type TrailerDef = ItemCatalog.TrailerDef

local VehicleService = {}

local TRUCK_TAG = "Truck"
local SLOT_TAG = "ParkingSlot"
local WHEEL_CLEARANCE = TruckLayout.ChassisY -- chassis pivot height above the ground; puts the wheels on it
local SPEED_CHECK_EVERY = 0.5 -- seconds
local SETTLE_MAX = 1.5 -- seconds a truck may roll after its driver gets out
local SETTLE_GIVE_UP = 6 -- seconds a truck in the air may take to land before it's set down
local SETTLE_SPEED = 1.5 -- studs/s: slower than this counts as stopped
local PARK_TILT = math.rad(30) -- the steepest slope a truck parks on
local PARK_RAY = 40 -- studs below a tipped truck that parking looks for the ground
local HOLD_SECONDS = 1 -- a truck the speed check put back stays the server's this long
local EXIT_GAP = 3.4 -- studs beside the truck where the driver steps out (clear of the wheels: 2 before M1.5, 2.6 before phase 12)
local OVERFLOW_SEARCH = 31 -- overflow spots tried when every free slot is blocked

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
	holdToken: number, -- bumped by each put-back (the server holds the truck's physics)
	-- Speed check (physics driving)
	lastGood: CFrame, -- the last position it accepted
	lastGoodAt: number, -- when (os.clock)
	lastCheck: number,
}

local trucks: { [number]: TruckRecord } = {} -- [userId]
local slotOwner: { [BasePart]: number } = {}
local overflowUsed: { [number]: boolean } = {}
local lastRecall: { [number]: number } = {}
local LEAVE_CONFIRM_SECONDS = 6
local leaveAsked: { [number]: number } = {} -- [userId] = when Recall warned about leaving the load
local slotShown: { [number]: number } = {} -- [userId] = the TruckSlotDistance last sent
local slotWarned = false

local notify: ((Player, string) -> ())? = nil

-- The v2 loop's hooks for TruckLoad (V2_PLAN.md §4b, M1.6): loose wood
-- riding on the beds. GameServer sets them only under the v2 loop; under
-- v1 they stay nil and nothing below changes. None of them touch the
-- truck's own physics, and each runs guarded (an error is logged, never
-- breaks driving or spawning).
--   onDriverChanged(truck, driver?): the owner sat in the driver seat
--     (driver, after its physics went to their device) or got out (nil,
--     as it starts to settle).
--   onRebuild(player, old?, keepsLoad, at?): a truck is about to be built
--     for `player`: `old` is the truck a recall or a switch replaces (nil
--     when it's the first truck since joining), `keepsLoad` whether its
--     load comes along (in town, VehicleLogic.InTown; on joining, whether
--     the saved spot was), `at` where it stands (or stood when they left;
--     nil when the save doesn't say). It may return a function that gets
--     the new truck once it's built and parked.
--   loadCount(truck): loose pieces riding on its beds (Recall warns before
--     leaving them out of town, as it does for the v1 bed's logs).
export type Hooks = {
	onDriverChanged: ((truck: Model, driver: Player?) -> ())?,
	onRebuild: ((player: Player, old: Model?, keepsLoad: boolean, at: CFrame?) -> ((Model) -> ())?)?,
	loadCount: ((truck: Model) -> number)?,
}
VehicleService.Hooks = {} :: Hooks

local function guarded(name: string, fn: () -> ())
	local ok, err = pcall(function(): any
		fn()
		return nil
	end)
	if not ok then
		warn(string.format("[VehicleService] hook %s failed: %s", name, tostring(err)))
	end
end

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
	-- DriveAttachment sits on the rear axle (TruckLayout.DriveAxleZ; the
	-- chassis is centred on the truck, so truck-local z is chassis-local z),
	-- at the chassis's own height and unrotated. Drive holds that point's
	-- velocity along the heading, so the truck turns about its rear wheels
	-- and the tail follows instead of sliding out. Heading only uses the
	-- attachment's axes, which are the chassis's.
	local attachment = Instance.new("Attachment")
	attachment.Name = "DriveAttachment"
	attachment.CFrame = CFrame.new(0, 0, TruckLayout.DriveAxleZ(layout))
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
	local logPart = log.PrimaryPart
	if entry.figure then
		log:SetAttribute("Figure", entry.figure)
		if logPart then
			ForestArt.FigureBand(logPart, entry.figure) -- the same band it wore in the world
		end
	end
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

-- Where the truck is, as far as the server can vouch: while its driver's
-- device runs its physics, the last position the speed check accepted;
-- otherwise (parked, settling, arcade) where the server has it. A truck
-- whose parts fell out of the world is where it was last accepted.
local function trustedCFrame(rec: TruckRecord): CFrame
	if (rec.driver ~= nil and GameConfig.VehiclePhysics) or rec.chassis.Parent == nil then
		return rec.lastGood
	end
	return rec.model:GetPivot()
end

-- Remembers where the truck is in the owner's save (profile.truckAt), so a
-- rejoin knows whether the load was in town.
local function noteSpot(rec: TruckRecord)
	local profile = ProfileService.GetProfile(rec.owner)
	if profile then
		profile.truckAt = VehicleLogic.SaveSpot(trustedCFrame(rec).Position)
	end
end

-- Saves the bed into the owner's profile, with where the truck is
-- (ProfileStore writes them out).
local function saveBed(rec: TruckRecord)
	local profile = ProfileService.GetProfile(rec.owner)
	if profile then
		profile.truckBed = VehicleLogic.CopyBed(rec.bed)
	end
	noteSpot(rec)
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

-- Ground-ray points under the whole rig (chassis-local): the truck's
-- front corners, the back corners (the trailer's, when one is hitched)
-- and both sides halfway along.
local function rigCorners(rec: TruckRecord): { Vector3 }
	local rear = rec.layout.length / 2 + (if rec.trailerLayout then rec.trailerLayout.length else 0)
	return VehicleLogic.RigCorners(rec.layout.width, rec.layout.front, rear)
end

-- True when the truck rests on something solid: a short ray down from the
-- chassis, at its middle or under any corner of the rig, finds it.
local function grounded(rec: TruckRecord): boolean
	local cf = rec.chassis.CFrame
	local down = -cf.UpVector * (WHEEL_CLEARANCE + 1)
	local params = worldParams(rec)
	if workspace:Raycast(cf.Position, down, params) then
		return true
	end
	for _, corner in ipairs(rigCorners(rec)) do
		if workspace:Raycast(cf * corner, down, params) then
			return true
		end
	end
	return false
end

-- Where a tipped or airborne truck is set down: on the ground under the
-- rig's corners, tilted to it (at most PARK_TILT) and lifted so no corner
-- sinks into a slope. Nil when no ray finds ground, unless `anywhere`:
-- then the terrain's own height under it (TerrainGen), never mid-air.
local function restingCFrame(rec: TruckRecord, anywhere: boolean): CFrame?
	local pivot = rec.chassis.CFrame
	local facing = VehicleLogic.FlatFacing(pivot.LookVector)
	local flat = VehicleLogic.HeadingCFrame(facing, Vector3.yAxis) + pivot.Position
	local corners = rigCorners(rec)
	local params = worldParams(rec)
	local hits: { Vector3? } = {}
	local normals: { Vector3? } = {}
	local found = false
	for i, corner in ipairs(corners) do
		local hit = workspace:Raycast(flat * corner + Vector3.new(0, 3, 0), Vector3.new(0, -PARK_RAY, 0), params)
		if hit then
			hits[i], normals[i], found = hit.Position, hit.Normal, true
		end
	end
	if not found then
		if not anywhere then
			return nil
		end
		for i, corner in ipairs(corners) do
			local p = flat * corner
			hits[i], normals[i] = Vector3.new(p.X, TerrainGen.HeightAt(p.X, p.Z), p.Z), Vector3.yAxis
		end
	end
	local up = VehicleLogic.GroundUp(hits, normals, PARK_TILT)
	return VehicleLogic.RestingCFrame(pivot.Position, up, facing, WHEEL_CLEARANCE, PARK_TILT, corners, hits)
end

-- Parks the truck, anchored (physics goes back to the server). On its
-- wheels and no steeper than PARK_TILT, it stays exactly where physics
-- left it, resting on the ground. Tipped over (or still in the air), it's
-- set down upright (restingCFrame). False if there's no ground under it
-- yet (only when not `anywhere`).
local function park(rec: TruckRecord, anywhere: boolean): boolean
	local onWheels = grounded(rec) and rec.chassis.CFrame.UpVector.Y >= math.cos(PARK_TILT)
	local target: CFrame? = nil
	if not onWheels then
		target = restingCFrame(rec, anywhere)
		if not target then
			return false
		end
	end
	rec.drive.Enabled = false
	rec.heading.Enabled = false
	rec.drive.PlaneVelocity = Vector2.zero
	rec.chassis.AssemblyLinearVelocity = Vector3.zero
	rec.chassis.AssemblyAngularVelocity = Vector3.zero
	if target then
		rec.model:PivotTo(target)
	end
	rec.chassis.Anchored = true -- parked; physics goes back to the server
	rec.lastGood = rec.model:GetPivot()
	rec.lastGoodAt = os.clock()
	noteSpot(rec)
	return true
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
-- slow and on the ground (or has rolled on the ground for SETTLE_MAX),
-- then park it. A truck still in the air waits to land, up to
-- SETTLE_GIVE_UP, instead of parking mid-air. A new driver or a rebuild
-- cancels it.
local function settle(rec: TruckRecord)
	rec.settleToken += 1
	local token = rec.settleToken
	rec.drive.PlaneVelocity = Vector2.zero
	holdHeading(rec)
	pcall(function()
		rec.chassis:SetNetworkOwner(nil)
	end)
	local started = os.clock()
	while true do
		task.wait(0.1)
		if rec.settleToken ~= token or not rec.model.Parent or not rec.chassis.Parent or rec.chassis.Anchored then
			return
		end
		holdHeading(rec)
		local waited = os.clock() - started
		local slow = rec.chassis.AssemblyLinearVelocity.Magnitude < SETTLE_SPEED
		if (slow or waited >= SETTLE_MAX) and grounded(rec) and park(rec, false) then
			return
		end
		if waited >= SETTLE_GIVE_UP then
			park(rec, true)
			return
		end
	end
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

-- Puts a truck that moved too far back where it was last accepted:
-- stopped and upright, its physics taken back by the server for
-- HOLD_SECONDS (so the driver's device can't just move it again at once),
-- then handed back to the driver if they're still in the seat.
local function putBack(rec: TruckRecord)
	rec.holdToken += 1
	local token = rec.holdToken
	local free = not rec.chassis.Anchored
	if free then
		pcall(function()
			rec.chassis:SetNetworkOwner(nil)
		end)
	end
	rec.model:PivotTo(rec.lastGood)
	rec.chassis.AssemblyLinearVelocity = Vector3.zero
	rec.chassis.AssemblyAngularVelocity = Vector3.zero
	rec.drive.PlaneVelocity = Vector2.zero
	holdHeading(rec)
	rec.lastGoodAt = os.clock()
	if not free then
		return
	end
	task.delay(HOLD_SECONDS, function()
		if rec.holdToken ~= token or rec.driver == nil or not rec.model.Parent or rec.chassis.Anchored then
			return
		end
		pcall(function()
			rec.chassis:SetNetworkOwner(rec.owner)
		end)
	end)
end

-- Physics driving: judges where the truck is now against the last position
-- it accepted (Shared/VehicleLogic.JudgeMove), and returns where it can be
-- trusted to be. A truck further away than it can drive (an exploiter
-- teleporting it) is put back. With `accept` (the half-second check,
-- getting out), a fair move becomes the new last good position; without
-- (a sale asking), it's only looked at, so asking more often never
-- stretches the allowance (every judgement allows SlackStuds more).
-- "still": nothing new arrived (or it's parked); the clock keeps running.
local function judgeNow(rec: TruckRecord, accept: boolean): CFrame
	local now = os.clock()
	if accept then
		rec.lastCheck = now
	end
	local pivot = rec.model:GetPivot()
	local verdict =
		VehicleLogic.JudgeMove(rec.lastGood.Position, pivot.Position, now - rec.lastGoodAt, rec.def.topSpeed)
	if verdict == "ok" then
		if accept then
			rec.lastGood = pivot
			rec.lastGoodAt = now
			noteSpot(rec)
		end
		return pivot
	elseif verdict == "tooFar" then
		warn(
			string.format(
				"[AntiExploit] %s's truck moved %d studs in %.1fs; putting it back",
				rec.owner.Name,
				math.floor((pivot.Position - rec.lastGood.Position).Magnitude),
				now - rec.lastGoodAt
			)
		)
		putBack(rec)
	end
	return rec.lastGood
end

-- While driving: judges the truck every SPEED_CHECK_EVERY seconds.
local function speedCheck(rec: TruckRecord)
	if os.clock() - rec.lastCheck >= SPEED_CHECK_EVERY then
		judgeNow(rec, true)
	end
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
		local onDriver = VehicleService.Hooks.onDriverChanged
		if onDriver and player then
			guarded("onDriverChanged", function()
				onDriver(rec.model, player)
			end)
		end
		return
	end
	local driver = rec.driver
	rec.driver = nil
	if not driver then
		return -- a stranger was put out
	end
	if GameConfig.VehiclePhysics then
		-- Judge where it is before the server takes its physics back, so a
		-- truck teleported in the moment its driver got out is put back.
		judgeNow(rec, true)
		task.spawn(settle, rec)
	else
		noteSpot(rec)
	end
	local onDriver = VehicleService.Hooks.onDriverChanged
	if onDriver then
		guarded("onDriverChanged", function()
			onDriver(rec.model, nil)
		end)
	end
	task.defer(stepOut, rec, driver)
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
	local now = os.clock()
	if now - rec.lastCheck >= SPEED_CHECK_EVERY then
		rec.lastCheck = now
		noteSpot(rec) -- the server moves it, so where it is is where it is
	end
end

local function makeDrivePrompt(seat: VehicleSeat, owner: Player, def: TruckDef): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DrivePrompt"
	prompt.ActionText = "Drive"
	prompt.ObjectText = string.format("%s's %s", owner.DisplayName, def.displayName)
	prompt.MaxActivationDistance = 9 -- from beside the cab of the biggest truck, to its seat (7 before phase 12)
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

-- Every ParkingSlot, in claim order (Index 1, 2, ...).
local function sortedSlots(): { BasePart }
	local slots: { BasePart } = {}
	for _, inst in ipairs(CollectionService:GetTagged(SLOT_TAG)) do
		if inst:IsA("BasePart") then
			table.insert(slots, inst)
		end
	end
	table.sort(slots, function(a, b)
		return ((a:GetAttribute("Index") :: number?) or 0) < ((b:GetAttribute("Index") :: number?) or 0)
	end)
	return slots
end

local function slotIndex(slot: BasePart): number
	local index = slot:GetAttribute("Index")
	return if type(index) == "number" then index else 0
end

-- The slots a rig `length` x `width` (TruckLayout.RigSize) should park in,
-- best first (VehicleLogic.BayChoices): the smallest free one it fits,
-- or, with none, the longest it may overhang. `current`, the slot its
-- player holds now, counts as free for them, and stays first while it's
-- as good as any. Slots it can't take aren't listed.
local function bayChoices(length: number, width: number, current: BasePart?): { BasePart }
	local infos: { VehicleLogic.BayInfo } = {}
	local byIndex: { [number]: BasePart } = {}
	for _, slot in ipairs(sortedSlots()) do
		if slotOwner[slot] == nil or slot == current then
			local index = slotIndex(slot)
			table.insert(infos, { index = index, length = slot.Size.Z, width = slot.Size.X })
			byIndex[index] = slot
		end
	end
	local out: { BasePart } = {}
	local currentIndex = if current then slotIndex(current) else nil
	for _, index in ipairs(VehicleLogic.BayChoices(infos, length, width, currentIndex)) do
		table.insert(out, byIndex[index])
	end
	return out
end

local function slotCFrame(slot: BasePart?, overflowIndex: number?): CFrame
	if slot then
		local ground = slot.Position - Vector3.new(0, slot.Size.Y / 2, 0)
		-- On the drawn ground if it is above the slot (never parked buried).
		local y = TerrainBuilder.LiftOnto(ground.X, ground.Y, ground.Z)
		return CFrame.new(ground.X, y + WHEEL_CLEARANCE, ground.Z) * slot.CFrame.Rotation
	end
	local spot = VehicleLogic.OverflowSpot(overflowIndex or 0)
	return CFrame.new(spot.X, TerrainBuilder.LiftOnto(spot.X, 0, spot.Z) + WHEEL_CLEARANCE, spot.Z)
end

-- How far forward a rig's pivot (the truck's middle) sits from the rig's
-- own middle: the trailer is behind it.
local function rigShiftOf(trailerLayout: TruckLayout.TrailerLayout?): number
	return if trailerLayout then trailerLayout.length / 2 else 0
end

-- How far forward of its spot's middle a rig's pivot parks: the whole rig
-- (truck + trailer) centred on its bay, or, when the rig is longer than
-- the bay, its tail at the bay's tail and its nose out past the head over
-- the bay's pull-out (VehicleLogic.OverhangShift). An overflow spot has no
-- bay: the rig is centred on it.
local function homeShift(slot: BasePart?, layout: TruckLayout.Layout, trailerLayout: TruckLayout.TrailerLayout?): number
	local shift = rigShiftOf(trailerLayout)
	if slot then
		local length = TruckLayout.RigSize(layout, trailerLayout)
		shift += VehicleLogic.OverhangShift(slot.Size.Z, length)
	end
	return shift
end

-- A model's bounding box relative to its pivot, so it can be checked at a
-- spot before it moves there; a stud smaller each way (touching isn't
-- being in the way).
local function footprint(model: Model): (CFrame, Vector3)
	local box, size = model:GetBoundingBox()
	return model:GetPivot():ToObjectSpace(box), size - Vector3.new(1, 1, 1)
end

-- The trucks (but `skip`) with a part inside a box.
local function trucksInBox(box: CFrame, size: Vector3, skip: TruckRecord?): { TruckRecord }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged(TRUCK_TAG)
	local found: { TruckRecord } = {}
	for _, part in ipairs(workspace:GetPartBoundsInBox(box, size, params)) do
		for _, rec in pairs(trucks) do
			if rec ~= skip and rec.model:IsAncestorOf(part) and not table.find(found, rec) then
				table.insert(found, rec)
			end
		end
	end
	return found
end

-- Whether any player's character has a part in the box.
local function peopleInBox(box: CFrame, size: Vector3): boolean
	local chars: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	if #chars == 0 then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = chars
	return #workspace:GetPartBoundsInBox(box, size, params) > 0
end

-- Moves a parked, empty truck that's in someone else's way back onto its
-- owner's own spot, when that's clear of trucks and people. True if it
-- moved.
local function sendHome(other: TruckRecord): boolean
	if other.seat.Occupant ~= nil or not other.chassis.Anchored or not other.model.Parent then
		return false
	end
	local shift = homeShift(other.slot, other.layout, other.trailerLayout)
	local home = slotCFrame(other.slot, other.overflowIndex) * CFrame.new(0, 0, -shift)
	local rel, size = footprint(other.model)
	if #trucksInBox(home * rel, size, other) > 0 then
		return false
	end
	-- Nobody standing in its home spot, or on the truck itself (loading at
	-- the tailgate): the move would drop it on them or carry them off.
	if
		peopleInBox(home * rel, size + Vector3.new(0, 4, 0))
		or peopleInBox(other.model:GetPivot() * rel, size + Vector3.new(2, 6, 2))
	then
		return false
	end
	other.model:PivotTo(home)
	other.lastGood = home
	other.lastGoodAt = os.clock()
	noteSpot(other)
	tell(
		other.owner,
		string.format("Your %s was in someone else's parking spot. It's back in yours.", other.def.displayName)
	)
	return true
end

-- Where a new rig goes (`layout`/`trailerLayout`, its footprint
-- `rel`/`size` about its pivot): the first of `choices` (bayChoices: the
-- bays it fits best first, its player's own among them while that's as
-- good as any) with no other truck in the rig's footprint there. A parked,
-- empty truck in the way of the first choice is sent home first. With no
-- choice clear (or none at all: every bay that takes the rig is taken),
-- the player's overflow spot if they hold one, else the first clear
-- overflow spot. Claims what it returns and gives the player's old slot or
-- overflow spot (`oldSlot`, `oldOverflow`) up if it moved.
local function clearSpot(
	userId: number,
	choices: { BasePart },
	oldSlot: BasePart?,
	oldOverflow: number?,
	layout: TruckLayout.Layout,
	trailerLayout: TruckLayout.TrailerLayout?,
	rel: CFrame,
	size: Vector3
): (BasePart?, number?)
	local function blocked(s: BasePart?, o: number?): { TruckRecord }
		local shift = homeShift(s, layout, trailerLayout)
		return trucksInBox(slotCFrame(s, o) * CFrame.new(0, 0, -shift) * rel, size)
	end
	local function take(s: BasePart?, o: number?): (BasePart?, number?)
		if oldSlot and oldSlot ~= s then
			slotOwner[oldSlot] = nil
		end
		if oldOverflow and oldOverflow ~= o then
			overflowUsed[oldOverflow] = nil
		end
		if s then
			slotOwner[s] = userId
		end
		if o then
			overflowUsed[o] = true
		end
		return s, o
	end
	for i, s in ipairs(choices) do
		local owner = slotOwner[s]
		if owner ~= nil and owner ~= userId then
			continue -- someone claimed it meanwhile (a hook yielded)
		end
		local inWay = blocked(s, nil)
		if #inWay > 0 and i == 1 then
			for _, other in ipairs(inWay) do
				sendHome(other)
			end
			inWay = blocked(s, nil)
		end
		if #inWay == 0 then
			return take(s, nil)
		end
	end
	if #choices == 0 then
		warn("[VehicleService] No free parking bay fits this rig; parking it in an overflow spot")
	end
	if oldOverflow and #blocked(nil, oldOverflow) == 0 then
		return take(nil, oldOverflow)
	end
	for i = 0, OVERFLOW_SEARCH do
		if not overflowUsed[i] and #blocked(nil, i) == 0 then
			return take(nil, i)
		end
	end
	warn("[VehicleService] No clear parking spot; building the truck where it was meant to go anyway")
	local first = choices[1]
	if first then
		return take(first, nil)
	end
	if oldSlot then
		return take(oldSlot, nil)
	end
	return take(nil, oldOverflow or VehicleLogic.NextFreeIndex(overflowUsed))
end

---------------------------------------------------------------------------
-- Loads left behind
---------------------------------------------------------------------------

-- Town, for VehicleLogic.InTown: the Town flat zone (the sawmill, shops,
-- lot and spawn), cut off at the parking lot's south edge so the Starter
-- Forest just beyond isn't town.
local TOWN_RECT: VehicleLogic.Rect = (function()
	for _, zone in ipairs(WorldLayout.FlatZones) do
		if zone.name == "Town" then
			return {
				x0 = zone.x0,
				x1 = zone.x1,
				z0 = math.max(zone.z0, WorldLayout.ParkingLot.z0 - 4),
				z1 = zone.z1,
			}
		end
	end
	return { x0 = -125, x1 = 140, z0 = -22, z1 = 205 }
end)()

local function inTown(at: Vector3, home: Vector3): boolean
	return VehicleLogic.InTown(at, TOWN_RECT, home)
end

-- True if a rebuild keeps this truck's load: the truck is in town.
local function keepsLoad(rec: TruckRecord): boolean
	return inTown(trustedCFrame(rec).Position, slotCFrame(rec.slot, rec.overflowIndex).Position)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Mirrors how far this truck is from its own parking spot (where the
-- rig's pivot sits when parked there) on its owner's TruckSlotDistance.
local function publishSlotDistance(rec: TruckRecord)
	local shift = homeShift(rec.slot, rec.layout, rec.trailerLayout)
	local home = slotCFrame(rec.slot, rec.overflowIndex) * CFrame.new(0, 0, -shift)
	local distance = TruckHome.Distance(trustedCFrame(rec).Position, home.Position)
	local userId = rec.owner.UserId
	if TruckHome.ShouldPublish(slotShown[userId], distance) then
		slotShown[userId] = distance
		rec.owner:SetAttribute("TruckSlotDistance", distance)
	end
end

local function slotDistanceLoop()
	while true do
		task.wait(TruckHome.Every)
		for _, rec in pairs(trucks) do
			local ok, err = pcall(function(): any
				publishSlotDistance(rec)
				return nil
			end)
			if not ok and not slotWarned then
				slotWarned = true -- once: this runs twice a second
				warn("[VehicleService] TruckSlotDistance failed: " .. tostring(err))
			end
		end
	end
end

-- `notifyFn` shows a toast (GameServer's notify). Without it, messages for
-- players go to Output.
function VehicleService.Init(notifyFn: (Player, string) -> ())
	notify = notifyFn
	task.spawn(slotDistanceLoop)
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

-- Where this player's truck was when they last played (profile.truckAt),
-- or nil if the save doesn't say.
local function savedSpot(player: Player): Vector3?
	local profile = ProfileService.GetProfile(player)
	return if profile then VehicleLogic.CleanSpot(profile.truckAt) else nil
end

-- Builds the player's truck (replacing any they have) in their parking
-- slot, with `trailerId` hitched behind if it can tow. `load` refills the
-- bed (a recall or a switch); with no `load`, the bed comes back from the
-- player's save. Returns the model and how many logs didn't fit. Loose
-- wood out of town is TruckLoad's decision (onRebuild), not a ground spill.
function VehicleService.SpawnTruck(
	player: Player,
	truckId: string,
	load: { BedEntry }?,
	trailerId: string?
): (Model, number)
	local def = ItemCatalog.GetTruck(truckId) or ItemCatalog.GetTruck("Rustbucket")
	assert(def, "[VehicleService] Rustbucket missing from ItemCatalog")
	local layout = TruckLayout.For(def)
	local trailer = towedTrailer(def, trailerId)
	local trailerLayout = if trailer then TruckLayout.ForTrailer(trailer, layout) else nil

	-- The bay this rig parks in (phase 12): the smallest free one it fits.
	-- A rebuild (a recall, a switch at the Dealership) keeps the player's
	-- bay while it's as good a fit as any, else moves them (clearSpot).
	local old = trucks[player.UserId]
	local oldSlot = if old then old.slot else nil
	local oldOverflow = if old then old.overflowIndex else nil
	local rigLength, rigWidth = TruckLayout.RigSize(layout, trailerLayout)
	local choices = bayChoices(rigLength, rigWidth, oldSlot)
	-- Where it will most likely park, for a joining player's saved spot.
	local homeSlot = choices[1] or oldSlot
	local homeAt = slotCFrame(
		homeSlot,
		if homeSlot then nil else (oldOverflow or VehicleLogic.NextFreeIndex(overflowUsed))
	).Position
	-- Loose wood (TruckLoad): told before the old truck goes, handed the
	-- new one once it's built.
	local onRebuild = VehicleService.Hooks.onRebuild
	local carry: ((Model) -> ())? = nil
	if old then
		if onRebuild then
			local oldModel, keeps, at = old.model, keepsLoad(old), trustedCFrame(old)
			guarded("onRebuild", function()
				carry = onRebuild(player, oldModel, keeps, at)
			end)
		end
		destroyTruck(old)
	elseif onRebuild then
		-- Joining: was the truck in town when they left? (Old saves don't
		-- say, and keep their load.)
		local was = savedSpot(player)
		local keeps = was == nil or inTown(was, homeAt)
		guarded("onRebuild", function()
			carry = onRebuild(player, nil, keeps, if was then CFrame.new(was) else nil)
		end)
	end

	local capacity = capacityOf(def, trailer)
	local dropped = 0
	local entries: { BedEntry }
	if load then
		entries = load
	else
		local restored, lost = savedBed(player, capacity)
		entries, dropped = restored, lost
		if lost > 0 then
			warn(string.format("[VehicleService] %s: %d saved bed log(s) couldn't be restored", player.Name, lost))
		end
	end

	local built = buildTruckModel(def, layout, trailer, trailerLayout)
	local model = built.model
	-- The whole rig (truck + trailer) centred on its bay, or its nose out
	-- past the head of one it's longer than (homeShift), once no other
	-- truck is in the way.
	local rel, size = footprint(model)
	local slot, overflowIndex =
		clearSpot(player.UserId, choices, oldSlot, oldOverflow, layout, trailerLayout, rel, size)
	model:PivotTo(slotCFrame(slot, overflowIndex) * CFrame.new(0, 0, -homeShift(slot, layout, trailerLayout)))
	if old and slot ~= oldSlot then
		-- Moved to a bay that fits (or out of the lot): say where.
		tell(
			player,
			if slot
				then string.format("Your %s parks in bay %d now.", def.displayName, slotIndex(slot))
				else string.format(
					"Every parking bay that fits your %s is taken: it waits west of the spawn.",
					def.displayName
				)
		)
	end
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
		holdToken = 0,
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

	for _, entry in ipairs(entries) do
		if not VehicleService.AddBedLog(player, entry) then
			dropped += 1
		end
	end
	publishBed(rec)
	saveBed(rec) -- the save matches what's really in the bed now, and where the truck is
	local onBuilt = carry
	if onBuilt then
		guarded("onRebuild (new truck)", function()
			onBuilt(model)
		end)
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
	leaveAsked[player.UserId] = nil
	if rec.slot then
		slotOwner[rec.slot] = nil
	end
	if rec.overflowIndex then
		overflowUsed[rec.overflowIndex] = nil
	end
	trucks[player.UserId] = nil
	lastRecall[player.UserId] = nil
	slotShown[player.UserId] = nil
	player:SetAttribute("BedCount", 0)
	player:SetAttribute("BedCapacity", 0)
	player:SetAttribute("TruckSlotDistance", nil)
end

-- True if this player is sitting in their own truck's driver seat.
local function isDriving(player: Player, rec: TruckRecord): boolean
	local occupant = rec.seat.Occupant
	return occupant ~= nil and player.Character ~= nil and occupant.Parent == player.Character
end

-- "Send truck home": rebuilds the player's truck in their parking slot. The
-- load comes along from town only; from further out it's left where the
-- truck stood (SpawnTruck). Returns false and why not when it can't.
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
	-- A load out of town stays where the truck stands: say so, and only go
	-- ahead on a second press within a few seconds (a stray tap mustn't
	-- strand a full bed in the Volcano). The v2 loop's loose pieces count
	-- too (Hooks.loadCount).
	local onBed = #rec.bed
	local countLoose = VehicleService.Hooks.loadCount
	if countLoose then
		guarded("loadCount", function()
			onBed += countLoose(rec.model)
		end)
	end
	if onBed > 0 and not keepsLoad(rec) then
		local asked = leaveAsked[player.UserId]
		if not asked or now - asked > LEAVE_CONFIRM_SECONDS then
			leaveAsked[player.UserId] = now
			return false,
				string.format(
					"Your %d log%s will be left where your truck stands. Press Send truck home again to go ahead.",
					onBed,
					if onBed == 1 then "" else "s"
				)
		end
	end
	leaveAsked[player.UserId] = nil
	lastRecall[player.UserId] = now
	VehicleService.SpawnTruck(player, rec.def.id, rec.bed, if rec.trailer then rec.trailer.id else nil)
	return true, nil
end

VehicleService.UnloadFirstText = "Unload the wood on your truck first (sell it, or drag it off)."

-- Swaps the player's rig (the Dealership): truck `truckId` towing
-- `trailerId` ("" or nil for none). Refuses while they drive, or when the
-- load would come along (the truck is in town) and wouldn't fit the new
-- bed space.
function VehicleService.Equip(player: Player, truckId: string, trailerId: string?): (boolean, string?)
	local def = ItemCatalog.GetTruck(truckId)
	local rec = trucks[player.UserId]
	if not def then
		return false, nil
	end
	if rec and isDriving(player, rec) then
		return false, "Hop out of your truck first."
	end
	if rec and #rec.bed > capacityOf(def, towedTrailer(def, trailerId)) and keepsLoad(rec) then
		return false, "Sell your load first: it won't fit."
	end
	-- The v2 loop's loose wood (Hooks.loadCount) would be squeezed onto the
	-- new beds and could be flung: unload first.
	local countLoose = VehicleService.Hooks.loadCount
	if rec and countLoose and keepsLoad(rec) then
		local loose = 0
		guarded("loadCount", function()
			loose = countLoose(rec.model)
		end)
		if loose > 0 then
			return false, VehicleService.UnloadFirstText
		end
	end
	VehicleService.SpawnTruck(player, def.id, if rec then rec.bed else nil, trailerId)
	return true, nil
end

function VehicleService.GetVehicle(player: Player): Model?
	local rec = trucks[player.UserId]
	return if rec then rec.model else nil
end

-- The Index of the parking bay this player's rig parks in (painted on the
-- bay), or nil without a truck or in an overflow spot.
function VehicleService.GetBayIndex(player: Player): number?
	local rec = trucks[player.UserId]
	local slot = if rec then rec.slot else nil
	return if slot then slotIndex(slot) else nil
end

-- Where this player's truck is, as far as the server can vouch (nil
-- without one). While they drive it, it's judged right now (not just on
-- the half-second check), so a truck teleported onto the sell pad a moment
-- ago is put back and doesn't count.
function VehicleService.TrustedTruckPosition(player: Player): Vector3?
	local rec = trucks[player.UserId]
	if not rec or not rec.model.Parent then
		return nil
	end
	if rec.driver and GameConfig.VehiclePhysics then
		return judgeNow(rec, false).Position
	end
	return trustedCFrame(rec).Position
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

-- What the logs in the bed are worth together (read-only; before any
-- sale multiplier).
function VehicleService.GetBedValue(player: Player): number
	local rec = trucks[player.UserId]
	return if rec then VehicleLogic.BedValue(rec.bed) else 0
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
