--!strict
-- VehicleService: builds and owns player trucks.
--   * Every truck is drawn by Shared/Art/TruckArt from its ItemCatalog entry
--     (Shared/TruckLayout says where each piece goes). A truck is only ever
--     built on its own spawn pad (a pad in profile.plot.pads, from the box
--     the truck was bought in): pressing the pad's button, "Send truck
--     home", and switching trucks all put it there. A player with no pad
--     for a truck gets a toast and no truck: there is no road-edge
--     delivery pad and no public bay. TruckArt.Rig makes it one rigid body:
--     the invisible chassis is its only massive part, every other part is
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
--   * Recall ("Send truck home") and switching trucks rebuild the truck on its
--     pad. The load comes along (when it fits) only if the truck
--     was already in town (VehicleLogic.InTown); from further out it's
--     left on the ground where the truck stood, as the player's logs, so
--     nobody skips the haul home. Left-behind logs still lying out when the
--     player leaves are saved (profile.leftLoad, GameServer) and put back
--     where they lay on rejoin (RestoreLeftLoad).
--   * The v2 loop carries loose wood on the beds instead (TruckLoad),
--     through three hooks (VehicleService.Hooks, nil under v1): the driver
--     changing, a truck being rebuilt, and how many pieces ride on a bed.
--   * TruckSlotDistance on the player: how far their truck is from its own
--     spawn pad, in whole studs (Shared/TruckHome), checked twice a
--     second and sent only when it moves a couple of studs; nil with no
--     truck. VehicleController shows "Send truck home" from it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClassicGauge = require(ReplicatedStorage.Shared.ClassicGauge)
local InputKit = require(ReplicatedStorage.Shared.InputKit)
local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local DriveMath = require(ReplicatedStorage.Shared.DriveMath)
local DriveStart = require(ReplicatedStorage.Shared.DriveStart)
local Handling = require(ReplicatedStorage.Shared.Handling)
local PaintShop = require(ReplicatedStorage.Shared.PaintShop)
local ForestArt = require(ReplicatedStorage.Shared.Art.ForestArt)
local StreamAhead = require(ReplicatedStorage.Shared.StreamAhead)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local TruckArt = require(ReplicatedStorage.Shared.Art.TruckArt)
local TruckHome = require(ReplicatedStorage.Shared.TruckHome)
local TruckLayout = require(ReplicatedStorage.Shared.TruckLayout)
local Util = require(ReplicatedStorage.Shared.Util)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)
local EconomyService = require(script.Parent.EconomyService)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local GrabLogic = require(ReplicatedStorage.Shared.GrabLogic)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local DealershipLot = require(ReplicatedStorage.Shared.Art.DealershipLot)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local PermissionLogic = require(ReplicatedStorage.Shared.PermissionLogic)
local TerrainBuilder = require(script.Parent.TerrainBuilder)
local TreeService = require(script.Parent.TreeService)

type TruckDef = ItemCatalog.TruckDef
type TrailerDef = ItemCatalog.TrailerDef

local VehicleService = {}

local TRUCK_TAG = "Truck"
local WHEEL_CLEARANCE = TruckLayout.ChassisY -- chassis pivot height above the ground; puts the wheels on it
local SPEED_CHECK_EVERY = 0.5 -- seconds
local SETTLE_MAX = 1.5 -- seconds a truck may roll after its driver gets out
local SETTLE_GIVE_UP = 6 -- seconds a truck in the air may take to land before it's set down
local SETTLE_SPEED = 1.5 -- studs/s: slower than this counts as stopped
local PARK_TILT = math.rad(30) -- the steepest slope a truck parks on
local PARK_RAY = 40 -- studs below a tipped truck that parking looks for the ground
local HOLD_SECONDS = 1 -- a truck the speed check put back stays the server's this long
local EXIT_GAP = 3.4 -- studs beside the truck where the driver steps out (clear of the wheels: 2 before M1.5, 2.6 before phase 12)
local WORLD_LOG_LENGTH = 3 -- TreeService's world logs (a load left behind)
local SPILL_RAY = 60 -- studs down from above a truck that a load left behind looks for the ground

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
	homeCF: CFrame, -- where its spawn pad put it: "home" for the Send truck home button
	conns: { RBXScriptConnection },
	arcadeSpeed: number,
	driver: Humanoid?, -- the owner, while they sit in the driver seat
	settleToken: number, -- bumped to cancel a settle in progress
	holdToken: number, -- bumped by each put-back (the server holds the truck's physics)
	-- Speed check (physics driving)
	lastGood: CFrame, -- the last position it accepted
	lastGoodAt: number, -- when (os.clock)
	lastCheck: number,
	-- Streaming ahead of a loaded truck (Shared/StreamAhead). The place's
	-- stream radius and pause mode stay as PlaceCheck set them.
	lastStreamAt: number,
	streamBusy: boolean,
}

local trucks: { [number]: TruckRecord } = {} -- [userId]
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
	-- A truck is about to be destroyed (despawn, slot switch, recall).
	-- Drop cargo welds first so the load isn't dragged away with it.
	onDespawn: ((player: Player, truck: Model) -> ())?,
	-- Tests: when set, SpawnTruck builds nothing and leaves the old truck.
	blockSpawn: boolean?,
	-- The tutorial: a pad went down ("padPlaced") or a pad's button brought
	-- a truck out ("truckSpawned"). GameServer forwards it to QuestService.
	padEvent: ((player: Player, event: string) -> ())?,
	-- Tow Service: true means this recall is free (GameServer).
	freeRecall: ((player: Player) -> boolean)?,
	-- 2x Cash, for the Classic's dash estimate (GameServer).
	saleMultiplier: ((player: Player) -> number)?,
	-- Tests send toasts here when Init has not installed GameServer's notify.
	notify: ((Player, string) -> ())?,
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
	trailerLayout: TruckLayout.TrailerLayout?,
	extras: TruckArt.BuildExtras?
): Built
	local model = TruckArt.Build(def, layout, trailer, trailerLayout, extras)
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

-- The Classic's dash: v1 bed worth plus loose wood (TruckLoad's LooseValue),
-- then 2x Cash once. No gauge on any other truck.
local function refreshClassicGauge(model: Model, owner: Player)
	if model:FindFirstChild("LoadGauge", true) == nil then
		return
	end
	local pieces: { number } = {}
	local loose = model:GetAttribute("LooseValue")
	local bed = model:GetAttribute("V1BedValue")
	if type(loose) == "number" then
		table.insert(pieces, loose)
	end
	if type(bed) == "number" then
		table.insert(pieces, bed)
	end
	local mult = 1
	local sale = VehicleService.Hooks.saleMultiplier
	if sale then
		local n = sale(owner)
		if type(n) == "number" then
			mult = n
		end
	end
	ClassicGauge.Apply(model, ClassicGauge.Estimate(pieces, mult))
end

-- The bed's numbers, on the truck and on its owner.
local function publishBed(rec: TruckRecord)
	rec.model:SetAttribute("BedCount", #rec.bed)
	rec.owner:SetAttribute("BedCount", #rec.bed)
	rec.owner:SetAttribute("BedCapacity", rec.capacity)
	local worth = 0
	for _, entry in ipairs(rec.bed) do
		if type(entry.value) == "number" then
			worth += math.max(0, entry.value)
		end
	end
	rec.model:SetAttribute("V1BedValue", worth)
	refreshClassicGauge(rec.model, rec.owner)
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
-- Heading is armed while the chassis is still anchored. Unanchoring first
-- left it disabled until the deferred step, and in that gap AutoRotate
-- (shift lock, first person) turned the welded root toward the camera
-- and dragged the truck with it.
local function startDriving(rec: TruckRecord, driver: Player)
	rec.settleToken += 1 -- a settle in progress stops here
	DriveStart.Arm(rec.chassis, rec.heading, rec.def.id)
	rec.chassis.Anchored = false
	rec.chassis:SetNetworkOwner(driver) -- the driver's device simulates it: smooth, no lag
	rec.lastGood = rec.model:GetPivot()
	rec.lastGoodAt = os.clock()
	rec.lastCheck = os.clock()
	-- Size the forces to the truck plus its driver once the seat weld is in.
	-- Do not read the chassis orientation again: it may already have been tugged.
	task.defer(function()
		if rec.driver == nil or not rec.model.Parent then
			return
		end
		local mass = rec.chassis.AssemblyMass
		local feel = Handling.For(rec.def.id)
		rec.drive.MaxForce = mass * Handling.DriveForce(feel)
		rec.heading.MaxTorque = mass * Handling.HoldTorque(feel)
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
	-- The load is already welded, so this pivot carries it. Ownership
	-- goes back to the driver only after the truck (and its cargo) is home.
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
local STREAM_TIMEOUT = 10 -- seconds one RequestStreamAroundAsync may take (the gondola uses the same)

-- The bed's saved logs, or loose wood riding on it (the v2 hook).
local function truckLoaded(rec: TruckRecord): boolean
	if #rec.bed > 0 then
		return true
	end
	local countLoose = VehicleService.Hooks.loadCount
	if not countLoose then
		return false
	end
	local ok, n = pcall(countLoose, rec.model)
	return ok and type(n) == "number" and n > 0
end

-- While the owner drives a loaded truck, ask their client to stream the
-- point a few seconds ahead along the velocity. Once a second, one request
-- at a time, and a failure never touches the drive. Same shape as the
-- gondola's RequestStreamAroundAsync.
local function streamLoadedTruck(rec: TruckRecord)
	local player = rec.owner
	if player.Parent == nil or rec.chassis.Parent == nil then
		return
	end
	local velocity = if GameConfig.VehiclePhysics
		then rec.chassis.AssemblyLinearVelocity
		else rec.chassis.CFrame.LookVector * rec.arcadeSpeed
	if velocity.Magnitude < StreamAhead.MinSpeed then
		return
	end
	local since = os.clock() - rec.lastStreamAt
	if not StreamAhead.Due(true, truckLoaded(rec), since, rec.streamBusy, StreamAhead.Every) then
		return
	end
	local ahead = StreamAhead.Ahead(rec.chassis.Position, velocity, StreamAhead.Seconds)
	rec.lastStreamAt = os.clock()
	rec.streamBusy = true
	task.spawn(function()
		pcall(function(): any
			player:RequestStreamAroundAsync(ahead, STREAM_TIMEOUT)
			return nil
		end)
		rec.streamBusy = false
	end)
end

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
	local feel = Handling.For(rec.def.id)
	local hitched = rec.trailer ~= nil
	local radius = Handling.TowRadius(DriveMath.MinTurnRadius(TruckLayout.Wheelbase(rec.layout)), hitched)
	rec.arcadeSpeed = Handling.Speed(rec.arcadeSpeed, seat.ThrottleFloat, rec.def.topSpeed, dt, nil, feel)
	local turn = Handling.Turn(rec.arcadeSpeed, seat.SteerFloat, rec.def.turnRate, dt, radius, feel, rec.def.topSpeed)
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
	InputKit.PromptDefaults(prompt, "Interact")
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
-- Footprints
---------------------------------------------------------------------------

-- How far forward a rig's pivot (the truck's middle) sits from the rig's
-- own middle: the trailer is behind it.
local function rigShiftOf(trailerLayout: TruckLayout.TrailerLayout?): number
	return if trailerLayout then trailerLayout.length / 2 else 0
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
	return inTown(trustedCFrame(rec).Position, rec.homeCF.Position)
end

-- What a log left on the ground mustn't land on: people, trucks, trees
-- and other logs.
local function spillParams(): RaycastParams
	local skip: { Instance } = CollectionService:GetTagged(TRUCK_TAG)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	local map = workspace:FindFirstChild("TimberlineMap")
	if map then
		for _, name in ipairs({ "Trees", "Logs", "Stumps" }) do
			local folder = map:FindFirstChild(name)
			if folder then
				table.insert(skip, folder)
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	params.RespectCanCollide = true -- skip leaves, zones, decoration
	return params
end

-- Leaves `load` on the ground where a truck stood (`at`) as `player`'s
-- world logs (TreeService), each keeping its worth and its figure: rows
-- lying across the truck's line, centred on where it stood, each log on
-- the ground under it (the terrain's height when no ray finds it).
local function spillLoad(player: Player, load: { BedEntry }, at: CFrame)
	local frame = VehicleLogic.HeadingCFrame(at.LookVector, Vector3.yAxis) + at.Position
	local params = spillParams()
	local radius = TreeService.LogDiameter / 2
	for i, offset in ipairs(VehicleLogic.SpillSpots(#load, WORLD_LOG_LENGTH, TreeService.LogDiameter)) do
		local entry = load[i]
		local def = WoodData.Get(entry.woodId)
		if not def then
			continue
		end
		local spot = frame * offset
		local hit = workspace:Raycast(spot + Vector3.new(0, 10, 0), Vector3.new(0, -SPILL_RAY, 0), params)
		local y = if hit then hit.Position.Y else TerrainGen.HeightAt(spot.X, spot.Z)
		local model, uid =
			TreeService.SpawnLog(def, frame.Rotation + Vector3.new(spot.X, y + radius, spot.Z), player.UserId, {
				graceSec = GameConfig.LeftLoadGraceSec, -- time to drive back for it
				despawnSec = GameConfig.LeftLoadDespawnSec,
			})
		local log = TreeService.GetLog(uid)
		if log then
			log.value = entry.value
			log.tags.leftBehind = true -- saved if its owner leaves before collecting it; not new work to load
			model:SetAttribute("Value", entry.value)
			if entry.figure then
				log.tags.figure = entry.figure
				model:SetAttribute("Figure", entry.figure)
				local part = model.PrimaryPart
				if part then
					ForestArt.FigureBand(part, entry.figure) -- the same band it wore in the bed
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Puts left-behind logs saved when the player last left (profile.leftLoad)
-- back where they lay, theirs again for LeftLoadGraceSec. Returns how many.
function VehicleService.RestoreLeftLoad(player: Player, saved: { any }): number
	local restored = 0
	for _, raw in ipairs(saved) do
		local entry = VehicleLogic.CleanLeftLog(raw, function(id: string): boolean
			return WoodData.Get(id) ~= nil
		end)
		local def = if entry then WoodData.Get(entry.woodId) else nil
		if entry and def then
			local model, uid = TreeService.SpawnLog(def, CFrame.new(entry.x, entry.y, entry.z), player.UserId, {
				graceSec = GameConfig.LeftLoadGraceSec,
				despawnSec = GameConfig.LeftLoadDespawnSec,
			})
			local log = TreeService.GetLog(uid)
			if log then
				log.value = entry.value
				log.tags.leftBehind = true
				model:SetAttribute("Value", entry.value)
				if entry.figure then
					log.tags.figure = entry.figure
					model:SetAttribute("Figure", entry.figure)
					local part = model.PrimaryPart
					if part then
						ForestArt.FigureBand(part, entry.figure)
					end
				end
				restored += 1
			end
		end
	end
	return restored
end

-- Mirrors how far this truck is from its own spawn pad (where the
-- rig's pivot sat when it was built there) on its owner's TruckSlotDistance.
local function publishSlotDistance(rec: TruckRecord)
	local distance = TruckHome.Distance(trustedCFrame(rec).Position, rec.homeCF.Position)
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
	-- FindFirstChild, never WaitForChild: a missing remote must not hang tests.
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = if folder then folder:FindFirstChild("SpawnPadPress") else nil
	if remote and remote:IsA("RemoteEvent") then
		VehicleService.BindPad(remote)
	end
end

local function destroyTruck(rec: TruckRecord)
	rec.settleToken += 1
	local drop = VehicleService.Hooks.onDespawn
	if drop then
		local owner, model = rec.owner, rec.model
		guarded("onDespawn", function()
			drop(owner, model)
		end)
	end
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

-- Where a truck goes: the top of a spawn pad (`cf` its slab, `baseY` where the
-- wheels' ground sits on it), and the paint the pad's record asks for.
export type PadSpot = {
	cf: CFrame,
	baseY: number,
	paintFrom: string?,
	paintTo: string?,
}

-- This player's pad for `truckId` (a pad in their plot, from the box the truck
-- came in), or nil when they have none. Set below, once the pad code exists.
local padFor: (player: Player, truckId: string) -> PadSpot?
-- The saved record of that pad (profile.plot.pads), where `presses` counts how
-- many times its vehicle has been spawned. Set below with padFor.
local padRecordFor: (player: Player, truckId: string) -> any?

local function applyPadColor(model: Model, fromHex: string, toHex: string)
	local from = Kit.hex(fromHex)
	local to = Kit.hex(toHex)
	if from == to then
		model:SetAttribute("PaintHex", toHex)
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Color == from then
			d.Color = to
		end
	end
	model:SetAttribute("PaintHex", toHex)
end

local function liftModel(model: Model, baseY: number)
	local ok, boxCf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or typeof(boxCf) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return
	end
	local bottom = boxCf.Position.Y - size.Y / 2
	local delta = baseY - bottom
	if math.abs(delta) > 1e-3 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, delta, 0))
	end
end

-- A CFrame on `pad` (its ground), wheels down, nudged along the pad so the
-- rig's box doesn't sit on another truck or a player.
local function padParking(pad: CFrame, rel: CFrame, size: Vector3): CFrame
	local ground = pad.Position - Vector3.new(0, 0.1, 0)
	local y = TerrainBuilder.LiftOnto(ground.X, ground.Y, ground.Z)
	local base = CFrame.new(ground.X, y + WHEEL_CLEARANCE, ground.Z) * pad.Rotation
	local function clear(cf: CFrame): boolean
		local box = cf * rel
		return #trucksInBox(box, size) == 0 and not peopleInBox(box, size + Vector3.new(0, 4, 0))
	end
	if clear(base) then
		return base
	end
	for n = 1, 6 do
		local shift = n * 10
		for _, sign in ipairs({ -1, 1 }) do
			local cf = base * CFrame.new(sign * shift, 0, 0)
			if clear(cf) then
				return cf
			end
		end
	end
	return base * CFrame.new(70, 0, 0)
end

-- The recall fee for this player: Tow Service makes it 0. The same number
-- is what a failed spawn refunds, so a free recall never pays cash back.
local function respawnFee(player: Player, def: TruckDef): number
	-- The first spawn and the first respawn of each truck are free.
	local record = padRecordFor(player, def.id)
	local spawns = if record and type(record.presses) == "number" then record.presses else 0
	if spawns < VehicleLogic.FreeSpawns then
		return 0
	end
	local ownsTow = false
	local free = VehicleService.Hooks.freeRecall
	if free then
		ownsTow = free(player) == true
	end
	return ShopLogic.RecallFee(def, CoreLoop.Active(), ownsTow)
end

-- 5% of its price to bring a truck back (the first two spawns free; Tow Service
-- free). A
-- profile with no wallet (tests) is not charged. Returns false when the
-- wallet is short.
local function chargeRespawn(player: Player, def: TruckDef): (boolean, string?)
	local fee = respawnFee(player, def)
	if fee <= 0 then
		return true, nil
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or type(profile.cash) ~= "number" then
		return true, nil
	end
	local short = string.format("You need %s to bring your %s back.", Util.formatCash(fee), def.displayName)
	if profile.cash < fee or not EconomyService.SpendCash(player, fee, "respawned " .. def.displayName, def.id) then
		return false, short
	end
	return true, nil
end

-- Gives a fee back when the truck never appeared. A profile with no wallet
-- (tests) was never charged, so there is nothing to return.
local function refundRespawn(player: Player, def: TruckDef)
	local fee = respawnFee(player, def)
	if fee <= 0 then
		return
	end
	local profile = ProfileService.GetProfile(player)
	if not profile or type(profile.cash) ~= "number" then
		return
	end
	EconomyService.Refund(player, fee, "refunded a failed respawn", def.id)
end

-- Paint and the Classic door name. Defined below, after isDriving's neighbors;
-- SpawnTruck calls it once the function exists.
local truckExtras: (Player, TruckDef) -> TruckArt.BuildExtras?

-- Builds the player's truck (replacing any they have) on its spawn pad: the
-- `pad` given (a pad button press) or the player's own pad for this truck.
-- No pad, no truck: nothing is built and nothing replaced, and the caller
-- says why. Nothing is built for an id the player doesn't have a
-- catalog entry for (no starter fallback). `load` refills the bed (a
-- recall or a switch); with no `load`, the bed comes back from the
-- player's save. Either way the load only comes along if the truck was in
-- town (keepsLoad, or the saved spot); otherwise it's left on the ground
-- where the truck was. Returns the model and how many logs didn't fit.
function VehicleService.SpawnTruck(
	player: Player,
	truckId: string,
	load: { BedEntry }?,
	trailerId: string?,
	padSpot: PadSpot?
): (Model?, number)
	if VehicleService.Hooks.blockSpawn then
		return nil, 0
	end
	local def = ItemCatalog.GetTruck(truckId)
	if not def then
		return nil, 0
	end
	local spot = padSpot or padFor(player, def.id)
	if not spot then
		return nil, 0
	end
	local pad = spot.cf
	local layout = TruckLayout.For(def)
	local trailer = towedTrailer(def, trailerId)
	local trailerLayout = if trailer then TruckLayout.ForTrailer(trailer, layout) else nil

	local old = trucks[player.UserId]
	-- Where it will park, for a joining player's saved spot.
	local homeAt = pad.Position
	-- Where a load out of town is left (the truck's last spot).
	local leaveAt: CFrame? = nil
	-- The v2 loop's loose load (TruckLoad): told before the old truck goes,
	-- handed the new one once it's built.
	local onRebuild = VehicleService.Hooks.onRebuild
	local carry: ((Model) -> ())? = nil
	if old then
		if load and #load > 0 and not keepsLoad(old) then
			leaveAt = trustedCFrame(old) * CFrame.new(0, 0, rigShiftOf(old.trailerLayout)) -- the rig's middle
		end
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
		-- Joining: the save says where the truck was (old saves don't, and
		-- keep their load).
		local was = savedSpot(player)
		if not old and #restored > 0 and was and not inTown(was, homeAt) then
			leaveAt = CFrame.new(was)
		end
	end
	if leaveAt and #entries > 0 then
		spillLoad(player, entries, leaveAt)
		entries = {}
		local profile = ProfileService.GetProfile(player)
		if profile then
			profile.truckBed = {} -- on the ground now: never restored twice
		end
		tell(
			player,
			if load
				then "Your load was left where your truck stood."
				else "Your last load is waiting where you left your truck."
		)
	end

	local built = buildTruckModel(def, layout, trailer, trailerLayout, truckExtras(player, def))
	local model = built.model
	-- The whole rig (truck + trailer) on its pad, nudged along it once no
	-- other truck or person is in the way, and sat on the pad's top.
	local rel, size = footprint(model)
	local parked = padParking(pad, rel, size)
	model:PivotTo(parked)
	liftModel(model, spot.baseY)
	if spot.paintFrom and spot.paintTo then
		applyPadColor(model, spot.paintFrom, spot.paintTo)
	end
	local homeCF = model:GetPivot()
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
		homeCF = homeCF,
		conns = {},
		arcadeSpeed = 0,
		driver = nil,
		settleToken = 0,
		holdToken = 0,
		lastGood = model:GetPivot(),
		lastGoodAt = now,
		lastCheck = now,
		lastStreamAt = 0,
		streamBusy = false,
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
			streamLoadedTruck(rec)
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
	trucks[player.UserId] = nil
	lastRecall[player.UserId] = nil
	slotShown[player.UserId] = nil
	player:SetAttribute("BedCount", 0)
	player:SetAttribute("BedCapacity", 0)
	player:SetAttribute("TruckSlotDistance", nil)
end

-- Paint and the Classic's door name. Paint applies only while the Paint
-- Shop pass is on the save (the backup still works if the live check failed).
function truckExtras(player: Player, def: TruckDef): TruckArt.BuildExtras?
	local profile = ProfileService.GetProfile(player)
	local paint: string? = nil
	if profile and type(profile.passes) == "table" and profile.passes.PaintShop == true then
		local saved = if type(profile.truckPaint) == "table" then profile.truckPaint[def.id] else nil
		local color = PaintShop.Normalize(saved)
		if color and PaintShop.InPalette(color) then
			paint = color
		end
	end
	local doorName: string? = nil
	if def.classic == true then
		local display = (player :: any).DisplayName
		local name = player.Name
		doorName = if type(display) == "string" and display ~= ""
			then display
			elseif type(name) == "string" then name
			else ""
	end
	if paint == nil and doorName == nil then
		return nil
	end
	return { paint = paint, doorName = doorName }
end

-- True if this player is sitting in their own truck's driver seat.
local function isDriving(player: Player, rec: TruckRecord): boolean
	local occupant = rec.seat.Occupant
	return occupant ~= nil and player.Character ~= nil and occupant.Parent == player.Character
end

VehicleService.NoPadText = "Open your truck's box on your plot and place its pad first."

-- A spawn happened for this truck's pad: the next one is closer to costing.
local function noteSpawn(player: Player, truckId: string)
	local record = padRecordFor(player, truckId)
	if record then
		record.presses = (if type(record.presses) == "number" then record.presses else 0) + 1
	end
end

-- "Send truck home": rebuilds the player's truck on its own spawn pad. The
-- load comes along from town only; from further out it's left where the
-- truck stood (SpawnTruck). Returns false and why not when it can't.
function VehicleService.Recall(player: Player): (boolean, string?)
	local rec = trucks[player.UserId]
	local now = os.clock()
	local remaining = GameConfig.TruckRecallCooldown - (now - (lastRecall[player.UserId] or -math.huge))
	if remaining > 0 then
		return false, string.format("Your truck's on its way. Try again in %d s.", math.ceil(remaining))
	end
	if not rec then
		local profile = ProfileService.GetProfile(player)
		local id = if profile then profile.equippedTruck else ""
		local def = if type(id) == "string" then ItemCatalog.GetTruck(id) else nil
		local owns = def ~= nil and profile ~= nil and table.find(profile.ownedTrucks, id) ~= nil
		if not owns or not def or not profile then
			return false, "Buy a truck at the dealership"
		end
		if padFor(player, def.id) == nil then
			return false, VehicleService.NoPadText
		end
		local paid, why = chargeRespawn(player, def)
		if not paid then
			return false, why
		end
		local model = VehicleService.SpawnTruck(player, id, nil, profile.equippedTrailer)
		if not model then
			refundRespawn(player, def)
			return false, nil
		end
		noteSpawn(player, def.id)
		lastRecall[player.UserId] = now
		return true, nil
	end
	if isDriving(player, rec) then
		return false, "Hop out first."
	end
	if padFor(player, rec.def.id) == nil then
		return false, VehicleService.NoPadText
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
	local paid, whyNot = chargeRespawn(player, rec.def)
	if not paid then
		return false, whyNot
	end
	local model = VehicleService.SpawnTruck(player, rec.def.id, rec.bed, if rec.trailer then rec.trailer.id else nil)
	if not model then
		refundRespawn(player, rec.def)
		return false, nil
	end
	noteSpawn(player, rec.def.id)
	lastRecall[player.UserId] = now
	return true, nil
end

VehicleService.UnloadFirstText = "Unload the wood on your truck first (sell it, or drag it off)."

-- Swaps the player's rig (the Dealership): truck `truckId` towing
-- `trailerId` ("" or nil for none), built on that truck's own pad. Refuses
-- while they drive, with no pad for the truck, or when the load would come
-- along (the truck is in town) and wouldn't fit the new bed space.
function VehicleService.Equip(player: Player, truckId: string, trailerId: string?): (boolean, string?)
	local def = ItemCatalog.GetTruck(truckId)
	local rec = trucks[player.UserId]
	if not def then
		return false, nil
	end
	if rec and isDriving(player, rec) then
		return false, "Hop out of your truck first."
	end
	if padFor(player, def.id) == nil then
		return false, VehicleService.NoPadText
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
	-- Swapping to another truck is a spawn like any other: it costs that
	-- truck's respawn fee after its first two (so swapping about is not free).
	local paid, why = chargeRespawn(player, def)
	if not paid then
		return false, why
	end
	local model = VehicleService.SpawnTruck(player, def.id, if rec then rec.bed else nil, trailerId)
	if model == nil then
		refundRespawn(player, def)
		return false, nil
	end
	noteSpawn(player, def.id)
	return true, nil
end

-- Recolors the truck where it stands. Rebuilding it would park it in a bay
-- and leave an out-of-town load behind, which is a free recall.
function VehicleService.Repaint(player: Player, truckId: string)
	local rec = trucks[player.UserId]
	if not rec or rec.def.id ~= truckId then
		return
	end
	local profile = ProfileService.GetProfile(player)
	local saved = if profile and type(profile.truckPaint) == "table" then profile.truckPaint[truckId] else nil
	local color = PaintShop.Normalize(saved)
	if not color or not PaintShop.InPalette(color) then
		return
	end
	local model = rec.model
	local current = model:GetAttribute("PaintHex")
	local fromHex = if type(current) == "string" then current else rec.def.look.color
	local from = Color3.fromHex(fromHex)
	local to = Color3.fromHex(color)
	if from ~= to then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Color == from then
				d.Color = to
			end
		end
	end
	model:SetAttribute("PaintHex", color)
end

function VehicleService.GetVehicle(player: Player): Model?
	local rec = trucks[player.UserId]
	return if rec then rec.model else nil
end

-- The Index of the parking bay this player's rig parks in (painted on the
-- bay), or nil without a truck or in an overflow spot.
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

---------------------------------------------------------------------------
-- Spawn pads (B07). One Allow for SpawnPadPress, here. EventService does
-- not connect that remote.
---------------------------------------------------------------------------

local padBound = false
local builtPads: { [string]: Model } = {}

VehicleService.PadPresses = 0

local function toast(player: Player, message: string)
	local fn: ((Player, string) -> ())? = notify
	if fn == nil then
		fn = VehicleService.Hooks.notify
	end
	if fn then
		fn(player, message)
	end
end

local function onPadPress(player: Player, pad: unknown)
	if not RateLimiter.Allow(player, "SpawnPadPress") then
		return
	end
	VehicleService.PadPresses += 1
	VehicleService.Press(player, pad)
end

function VehicleService.BindPad(remote: any)
	if padBound or type(remote) ~= "table" then
		return
	end
	local event = remote.OnServerEvent
	if type(event) ~= "table" or type(event.Connect) ~= "function" then
		return
	end
	padBound = true
	event:Connect(onPadPress)
end

local function activeLoop(): number
	local ok, n = pcall(CoreLoop.Active)
	if ok and (n == 1 or n == 2) then
		return n
	end
	return if GameConfig.CoreLoop == 2 then 2 else 1
end

local function vehicleSpan(kind: string, id: string): (number, number)
	if kind == "Trailer" then
		local trailer = ItemCatalog.GetTrailer(id)
		local truck = ItemCatalog.GetTruck("Pickup")
		if trailer and truck then
			local lay = TruckLayout.ForTrailer(trailer, TruckLayout.For(truck))
			return math.max(lay.width, 2 * lay.wheelX + lay.tyreWidth), lay.length
		end
	end
	local def = ItemCatalog.GetTruck(id)
	if def then
		local lay = TruckLayout.For(def)
		return math.max(lay.width, 2 * lay.wheelX + lay.tyreWidth), lay.length
	end
	return 8, 16
end

local function playerAttr(player: Player, name: string): unknown
	if type((player :: any).GetAttribute) ~= "function" then
		return nil
	end
	return (player :: any):GetAttribute(name)
end

local function plotOf(profile: any): any
	local plot = if profile then profile.plot else nil
	if type(plot) ~= "table" or plot.claimed ~= true then
		return nil
	end
	return plot
end

local function padList(plot: any): { any }
	if type(plot.pads) ~= "table" then
		plot.pads = {}
	end
	return plot.pads
end

local function homeOf(player: Player): Vector2?
	local index = playerAttr(player, "PlotSlot")
	if type(index) ~= "number" then
		return nil
	end
	return PlotData.Slots[index]
end

local function yardHalf(plot: any): number
	local tier = plot.tier
	local row = if type(tier) == "number" then PlotData.Tiers[tier] else nil
	local size = if row then row.size else PlotData.Tiers[1].size
	return size / 2
end

local function blockersOf(plot: any): { VehicleLogic.Foot }
	local out: { VehicleLogic.Foot } = {}
	if type(plot.placed) == "table" then
		for _, item in ipairs(plot.placed) do
			if type(item) == "table" and type(item.blueprintId) == "string" then
				local bp = PlotData.Blueprint(item.blueprintId)
				if bp and type(item.x) == "number" and type(item.z) == "number" then
					local w, d = PlotLogic.Footprint(bp, if type(item.rot) == "number" then item.rot else 0)
					table.insert(out, { x = item.x, z = item.z, sx = w, sz = d })
				end
			end
		end
	end
	if type(plot.pads) == "table" then
		for _, pad in ipairs(plot.pads) do
			if type(pad) == "table" and type(pad.x) == "number" and type(pad.z) == "number" then
				local width, length = vehicleSpan(if type(pad.kind) == "string" then pad.kind else "Truck", pad.id)
				local size = VehicleLogic.PadSize(length, width)
				table.insert(out, VehicleLogic.PlaceFoot(pad.x, pad.z, size))
			end
		end
	end
	return out
end

local function groundY(x: number, z: number): number
	local ok, hit = pcall(function()
		return workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0))
	end)
	if ok and typeof(hit) == "RaycastResult" then
		return hit.Position.Y
	end
	return -math.huge
end

local function showGhost(cf: CFrame, size: Vector3, okPlace: boolean)
	local ghost = Instance.new("Part")
	ghost.Name = "PadGhost"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.Size = size
	ghost.CFrame = cf
	ghost.Color = VehicleLogic.GhostTint(okPlace)
	ghost.Transparency = 0.45
	ghost.Material = Enum.Material.Neon
	pcall(function()
		ghost.Parent = workspace
	end)
	pcall(function()
		task.delay(1.5, function()
			ghost:Destroy()
		end)
	end)
end

local function paintOf(kind: string, id: string): string
	if kind == "Trailer" then
		local trailer = ItemCatalog.GetTrailer(id)
		return if trailer then trailer.look.color else "#7A5A3A"
	end
	local truck = ItemCatalog.GetTruck(id)
	return if truck then truck.look.color else "#2F6DB5"
end

local function rollColor(player: Player, kind: string, id: string): string
	local seed = math.floor(math.abs(player.UserId * 17 + os.clock() * 1000)) % 100000 + 1
	local rng = Kit.rng(seed)
	return VehicleLogic.RollPaint(paintOf(kind, id), function()
		return rng:next()
	end)
end

local function worldPad(home: Vector2, x: number, z: number, thick: number): CFrame
	local y = groundY(home.X + x, home.Y + z)
	if y == -math.huge then
		y = 0
	end
	return CFrame.new(home.X + x, y + thick / 2, home.Y + z)
end

local function rememberOwned(profile: any, kind: string, id: string)
	if kind == "Trailer" then
		if type(profile.ownedTrailers) ~= "table" then
			profile.ownedTrailers = {}
		end
		if not table.find(profile.ownedTrailers, id) then
			table.insert(profile.ownedTrailers, id)
		end
		return
	end
	if type(profile.ownedTrucks) ~= "table" then
		profile.ownedTrucks = {}
	end
	if not table.find(profile.ownedTrucks, id) then
		table.insert(profile.ownedTrucks, id)
	end
end

local function hookPrompt(button: BasePart, padModel: Model)
	local prompt = button:FindFirstChild("PadPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		pcall(function()
			prompt.Triggered:Connect(function(who: Player)
				onPadPress(who, padModel)
			end)
		end)
	end
end

local function buildPadModel(player: Player, home: Vector2, pad: any): Model?
	local uid = pad.uid
	if type(uid) ~= "string" then
		return nil
	end
	local existing = builtPads[uid]
	if existing and existing.Parent then
		return existing
	end
	local kind = if type(pad.kind) == "string" then pad.kind else "Truck"
	local id = pad.id
	local width, length = vehicleSpan(kind, id)
	local size = VehicleLogic.PadSize(length, width)
	local cf = worldPad(home, pad.x, pad.z, size.Y)
	local color = Kit.hex(if type(pad.color) == "string" then pad.color else paintOf(kind, id))
	local model = DealershipLot.BuildPad(workspace, cf, color, length, width)
	model:SetAttribute("PadUid", uid)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("ItemId", id)
	model:SetAttribute("Category", kind)
	local button = model:FindFirstChild("PadButton")
	if button and button:IsA("BasePart") then
		hookPrompt(button, model)
	end
	builtPads[uid] = model
	return model
end

-- After a load: trucks with no stored or placed box, while storage is
-- full, are waiting. No new save field. Also finishes a mint if a slot
-- opened since the last join.
function VehicleService.AnnounceWaiting(player: Player, profile: any)
	if type(profile) ~= "table" then
		return
	end
	ProfileSchema.MintTruckBoxes(profile)
	local storage = profile.storage
	if type(storage) ~= "table" or #storage < ProfileSchema.StorageCap then
		return
	end
	for _, id in ipairs(ProfileSchema.WaitingTrucks(profile)) do
		local truck = ItemCatalog.GetTruck(id)
		local name = if truck then truck.displayName else id
		toast(player, string.format("Your %s is waiting. Free a storage slot to get its box.", name))
	end
end

function VehicleService.RestorePads(player: Player, profile: any)
	local plot = plotOf(profile)
	local home = homeOf(player)
	if not plot or not home or type(plot.pads) ~= "table" then
		return
	end
	for _, pad in ipairs(plot.pads) do
		if type(pad) == "table" then
			buildPadModel(player, home, pad)
		end
	end
end

-- Places a pad for a paid truck or trailer box. False leaves the box.
function VehicleService.TryPlaceFromBox(player: Player, rec: any): boolean
	local kind = rec.itemKind
	local id = rec.itemId
	if type(id) ~= "string" or not VehicleLogic.CanHavePad(id) then
		toast(player, "That one stays in town.")
		return false
	end
	local profile = ProfileService.GetProfile(player)
	local plot = plotOf(profile)
	local home = homeOf(player)
	if not profile or not plot or not home then
		toast(player, "Open it on your plot.")
		return false
	end
	local part = rec.part
	local world = if part and typeof(part.CFrame) == "CFrame" then part.CFrame.Position else nil
	if world == nil then
		toast(player, "Open it on your plot.")
		return false
	end
	local localX, localZ = world.X - home.X, world.Z - home.Y
	-- A quarter square (10 studs), not a whole one: on an 80 plot a 40 grid left
	-- the plot's centre as the only spot a pad could sit.
	local snappedX, snappedZ = VehicleLogic.Snap(localX, localZ, GameConfig.PlotSquare / 4)
	local width, length = vehicleSpan(kind, id)
	local size = VehicleLogic.PadSize(length, width)
	local foot = VehicleLogic.PlaceFoot(snappedX, snappedZ, size)
	local okPlace = VehicleLogic.Placement(foot, blockersOf(plot), yardHalf(plot))
	local cf = worldPad(home, snappedX, snappedZ, size.Y)
	if not okPlace then
		local ghostCf = cf * CFrame.new(-VehicleLogic.ButtonX / 2, 0, -VehicleLogic.ButtonZ / 2)
		showGhost(ghostCf, Vector3.new(foot.sx, size.Y, foot.sz), false)
		toast(player, "That spot is taken. The pad would sit on something, or off your land.")
		return false
	end
	local pads = padList(plot)
	local record = {
		uid = rec.uid,
		id = id,
		kind = kind,
		x = snappedX,
		z = snappedZ,
		rot = 0,
		presses = 0,
		color = rollColor(player, kind, id),
	}
	table.insert(pads, record)
	rememberOwned(profile, kind, id)
	buildPadModel(player, home, record)
	toast(player, "The pad is down. Press it to bring the vehicle out.")
	local report = VehicleService.Hooks.padEvent
	if report then
		guarded("padEvent", function()
			report(player, "padPlaced")
		end)
	end
	return true
end

local function findPadRecord(profile: any, uid: string): any
	local plot = if profile then profile.plot else nil
	if type(plot) ~= "table" or type(plot.pads) ~= "table" then
		return nil
	end
	for _, pad in ipairs(plot.pads) do
		if type(pad) == "table" and pad.uid == uid then
			return pad
		end
	end
	return nil
end

local function ownerProfile(player: Player, ownerId: number): any
	if player.UserId == ownerId then
		return ProfileService.GetProfile(player)
	end
	local ok, players = pcall(function()
		return game:GetService("Players")
	end)
	if not ok or players == nil or type((players :: any).GetPlayerByUserId) ~= "function" then
		return nil
	end
	local owner = (players :: any):GetPlayerByUserId(ownerId)
	if owner == nil then
		return nil
	end
	return ProfileService.GetProfile(owner)
end

local function visitorAllowed(player: Player, ownerId: number, padInst: Instance): boolean
	local grabOk, grab = pcall(function()
		return require(script.Parent.GrabService)
	end)
	if grabOk and grab and type(grab.Hooks) == "table" and type(grab.Hooks.permission) == "function" then
		local allowed = grab.Hooks.permission(player, padInst :: any)
		if allowed == true then
			return true
		end
		if allowed == false then
			return false
		end
	end
	local profile = ownerProfile(player, ownerId)
	local permissions = if profile then profile.permissions else nil
	if type(permissions) ~= "table" then
		return false
	end
	return PermissionLogic.Allows(permissions, player.UserId, "interact")
		or PermissionLogic.Allows(permissions, player.UserId, "drive")
end

local function ownsTow(player: Player): boolean
	local free = VehicleService.Hooks.freeRecall
	if free and free(player) == true then
		return true
	end
	local ok, monetization = pcall(function()
		return require(script.Parent.MonetizationService)
	end)
	if ok and monetization and type(monetization.WaivesRespawn) == "function" then
		return monetization.WaivesRespawn(player) == true
	end
	return false
end

-- Where a truck goes on a built pad model: its slab, and the ground under it.
local function padSpotOf(padInst: Instance, color: string?): PadSpot
	local slab = padInst:FindFirstChild("Slab")
	local padCf = if slab and slab:IsA("BasePart")
		then slab.CFrame
		elseif padInst:IsA("Model") then padInst:GetPivot()
		else CFrame.new()
	local padTop = padCf.Position.Y
		+ (if slab and slab:IsA("BasePart") then slab.Size.Y / 2 else VehicleLogic.PadThick / 2)
	local kind = padInst:GetAttribute("Category")
	local id = padInst:GetAttribute("ItemId")
	local paintFrom: string? = nil
	if color and type(kind) == "string" and type(id) == "string" then
		paintFrom = paintOf(kind, id)
	end
	return {
		cf = padCf,
		baseY = VehicleLogic.SpawnBaseY(padTop, groundY(padCf.Position.X, padCf.Position.Z)),
		paintFrom = paintFrom,
		paintTo = color,
	}
end

padRecordFor = function(player: Player, truckId: string): any?
	local profile = ProfileService.GetProfile(player)
	local plot = plotOf(profile)
	if not plot or type(plot.pads) ~= "table" then
		return nil
	end
	for _, pad in ipairs(plot.pads) do
		if type(pad) == "table" and pad.id == truckId and (pad.kind == nil or pad.kind == "Truck") then
			return pad
		end
	end
	return nil
end

padFor = function(player: Player, truckId: string): PadSpot?
	local profile = ProfileService.GetProfile(player)
	local plot = plotOf(profile)
	if not plot or type(plot.pads) ~= "table" then
		return nil
	end
	for _, pad in ipairs(plot.pads) do
		if type(pad) == "table" and pad.id == truckId and (pad.kind == nil or pad.kind == "Truck") then
			local color = if type(pad.color) == "string" then pad.color else nil
			local model = if type(pad.uid) == "string" then builtPads[pad.uid] else nil
			if model and model.Parent then
				return padSpotOf(model, color)
			end
			local home = homeOf(player)
			if home and type(pad.x) == "number" and type(pad.z) == "number" then
				local width, length = vehicleSpan("Truck", truckId)
				local size = VehicleLogic.PadSize(length, width)
				local cf = worldPad(home, pad.x, pad.z, size.Y)
				return {
					cf = cf,
					baseY = VehicleLogic.SpawnBaseY(cf.Position.Y + size.Y / 2, groundY(cf.Position.X, cf.Position.Z)),
					paintFrom = if color then paintOf("Truck", truckId) else nil,
					paintTo = color,
				}
			end
		end
	end
	return nil
end

function VehicleService.Press(player: Player, padInst: unknown)
	if typeof(padInst) ~= "Instance" then
		return
	end
	local uid = padInst:GetAttribute("PadUid")
	local ownerId = padInst:GetAttribute("OwnerId")
	local itemId = padInst:GetAttribute("ItemId")
	local kind = padInst:GetAttribute("Category")
	if type(uid) ~= "string" or type(ownerId) ~= "number" or type(itemId) ~= "string" then
		return
	end
	-- B15: stand at the button. The prompt (12 studs) enforces this for a
	-- tap, but the remote does not, so check here: the prompt's reach plus
	-- the server's tolerance. A pad without a button (a test rig) skips it.
	local button = if padInst:IsA("Model") then padInst:FindFirstChild("PadButton") else nil
	if button and button:IsA("BasePart") then
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if not root or not root:IsA("BasePart") then
			return
		end
		if (root.Position - button.Position).Magnitude > 12 + GameConfig.RangeTolerance + 4 then
			return
		end
	end
	local kindName = if type(kind) == "string" then kind else "Truck"
	local allowed = GrabLogic.CanPressPad({
		userId = player.UserId,
		ownerId = ownerId,
		plotAllows = if player.UserId == ownerId then true else visitorAllowed(player, ownerId, padInst),
	})
	local profile = ownerProfile(player, ownerId)
	local record = findPadRecord(profile, uid)
	local presses = if record and type(record.presses) == "number" then record.presses else 0
	local price = VehicleLogic.CatalogPrice(kindName, itemId, activeLoop())
	local cash = 0
	local payer = ProfileService.GetProfile(player)
	if payer and type(payer.cash) == "number" then
		cash = payer.cash
	end
	local plan = VehicleLogic.PressPlan(allowed, presses, price, cash, ownsTow(player), VehicleLogic.RespawnRate())
	if not plan.spawn then
		if not allowed then
			toast(player, "That pad isn't yours.")
		elseif plan.broke then
			toast(player, string.format("You need %s to bring it back.", Util.formatCash(plan.fee)))
		end
		return
	end
	if plan.fee > 0 then
		local spent = EconomyService.SpendCash(player, plan.fee, "respawned " .. itemId, itemId)
		if not spent then
			return
		end
	end
	if kindName == "Truck" then
		local spot = padSpotOf(padInst, if record and type(record.color) == "string" then record.color else nil)
		local model = VehicleService.SpawnTruck(player, itemId, nil, nil, spot)
		if model == nil then
			if plan.fee > 0 then
				EconomyService.Refund(player, plan.fee, "refunded a failed respawn", itemId)
			end
			return
		end
		local report = VehicleService.Hooks.padEvent
		if report then
			guarded("padEvent", function()
				report(player, "truckSpawned")
			end)
		end
	end
	if record then
		record.presses = presses + 1
	end
end

return VehicleService
