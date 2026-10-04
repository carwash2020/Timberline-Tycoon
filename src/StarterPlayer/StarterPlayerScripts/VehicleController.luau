--!strict
-- VehicleController: driving, on the driver's device.
--   * Physics driving (GameConfig.VehiclePhysics): while you sit in your
--     truck's driver seat, the server hands you its physics. Every physics
--     step (RunService.PreSimulation, before the solver runs) this turns the
--     seat's throttle and steer (WASD / arrow keys, the touch thumbstick, a
--     gamepad's stick) into a speed and heading (Shared/DriveMath), then
--     sets the truck's Drive (LinearVelocity) and Heading (AlignOrientation).
--     Heading follows the ground: four rays at the chassis corners give the
--     slope (Shared/VehicleLogic.GroundUp), never more than 30 degrees, so
--     the truck rides hills and bumps instead of nosing into them. Long
--     trucks turn wider circles: DriveMath.MinTurnRadius of the truck's
--     wheelbase (TruckLayout.Wheelbase).
--   * "Send truck home" side button (Y on a gamepad): sends your truck back
--     to your parking slot when it's far away (left somewhere, or stuck).
--     It shows only while you're on foot, away from the truck, and the
--     truck is more than 42 studs from its own spot (the server's
--     TruckSlotDistance attribute; HudRules.SendHome), so it isn't on
--     screen while the truck sits in the lot. The load comes along only
--     from town; otherwise the server leaves it on the ground where the
--     truck stood (VehicleService).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClassicGauge = require(ReplicatedStorage.Shared.ClassicGauge)
local DriveMath = require(ReplicatedStorage.Shared.DriveMath)
local DriveStart = require(ReplicatedStorage.Shared.DriveStart)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Handling = require(ReplicatedStorage.Shared.Handling)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local TruckLayout = require(ReplicatedStorage.Shared.TruckLayout)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local HUD = require(script.Parent.HUD)
local HudRules = require(script.Parent.HudRules)
local UITheme = require(script.Parent.UITheme)

local VehicleController = {}

local player = Players.LocalPlayer

local MAX_TILT = math.rad(30) -- the steepest a loose truck leans to follow the ground
local RAY_UP = 2.5 -- corner rays start this far above the chassis...
local RAY_DOWN = 9 -- ...and look this far down

type Session = {
	truck: Model,
	seat: VehicleSeat,
	chassis: BasePart,
	drive: LinearVelocity,
	heading: AlignOrientation,
	topSpeed: number,
	turnRate: number,
	minRadius: number?, -- tightest turning circle (DriveMath.MinTurnRadius, wider while towing)
	feel: Handling.Profile,
	speed: number,
	facing: Vector3, -- flat unit vector the truck is steering toward
	up: Vector3, -- the ground's up under the truck, smoothed
	parkedUp: Vector3, -- the slope it was parked on; held until the first input
	holding: boolean, -- parked facing, until the first throttle or steer
	corners: { Vector3 }, -- chassis-local ray starts (VehicleLogic.CornerOffsets)
	rayParams: RaycastParams,
}

local session: Session? = nil
local callButton: UITheme.Button? = nil
-- AutoRotate saved while we sit, so exit and Seated(false) can put it back.
local seatLock: DriveStart.SeatLock = { saved = nil }

local function startDriving(seat: VehicleSeat)
	local truck = seat.Parent
	if not truck or not truck:IsA("Model") or not CollectionService:HasTag(truck, "Truck") then
		return
	end
	local chassis = truck.PrimaryPart
	local drive = if chassis then chassis:FindFirstChild("Drive") else nil
	local heading = if chassis then chassis:FindFirstChild("Heading") else nil
	if
		not chassis
		or not drive
		or not drive:IsA("LinearVelocity")
		or not heading
		or not heading:IsA("AlignOrientation")
	then
		return
	end
	-- Long trucks turn wider circles (from the wheelbase; a trailer doesn't
	-- change it). Unknown truck: no limit beyond turnRate.
	local truckId = truck:GetAttribute("TruckId")
	local def = if type(truckId) == "string" then ItemCatalog.GetTruck(truckId) else nil
	local feel = Handling.For(if type(truckId) == "string" then truckId else nil)
	local hitched = type(truck:GetAttribute("TrailerId")) == "string" and truck:GetAttribute("TrailerId") ~= ""
	local minRadius = if def
		then Handling.TowRadius(DriveMath.MinTurnRadius(TruckLayout.Wheelbase(TruckLayout.For(def))), hitched)
		else nil
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { truck, player.Character :: Instance }
	params.RespectCanCollide = true
	-- The chassis as it sits, not the camera. Held until the driver steers.
	local parked = DriveStart.Seed(chassis.CFrame)
	session = {
		truck = truck,
		seat = seat,
		chassis = chassis,
		drive = drive,
		heading = heading,
		topSpeed = (truck:GetAttribute("TopSpeed") :: number?) or 26,
		turnRate = (truck:GetAttribute("TurnRate") :: number?) or 1.4,
		minRadius = minRadius,
		feel = feel,
		speed = 0,
		facing = VehicleLogic.FlatFacing(parked.LookVector),
		up = parked.UpVector,
		parkedUp = parked.UpVector,
		holding = true,
		corners = VehicleLogic.CornerOffsets(chassis.Size.X, chassis.Size.Z),
		rayParams = params,
	}
end

-- The ground's up under the truck, from a ray down at each corner.
local function groundUp(s: Session): Vector3
	local cf = s.chassis.CFrame
	local points: { Vector3? } = {}
	local normals: { Vector3? } = {}
	for i, offset in ipairs(s.corners) do
		local origin = cf:PointToWorldSpace(offset) + Vector3.new(0, RAY_UP, 0)
		local hit = workspace:Raycast(origin, Vector3.new(0, -(RAY_UP + RAY_DOWN), 0), s.rayParams)
		if hit then
			points[i] = hit.Position
			normals[i] = hit.Normal
		end
	end
	return VehicleLogic.GroundUp(points, normals, MAX_TILT)
end

local function step(dt: number)
	local s = session
	if not s then
		return
	end
	if not s.truck.Parent or not s.chassis.Parent then
		session = nil -- the truck was rebuilt or removed
		return
	end
	local velocity = s.chassis.AssemblyLinearVelocity
	local throttle = s.seat.ThrottleFloat
	local steer = s.seat.SteerFloat
	local actual = Vector3.new(velocity.X, 0, velocity.Z):Dot(s.facing)
	s.speed = Handling.Speed(s.speed, throttle, s.topSpeed, dt, actual, s.feel)
	local turn = Handling.Turn(s.speed, steer, s.turnRate, dt, s.minRadius, s.feel, s.topSpeed)
	local turned = VehicleLogic.FlatFacing(CFrame.Angles(0, turn, 0):VectorToWorldSpace(s.facing))
	-- Parked heading until the first real input, so a camera-facing tug
	-- on the chassis does not become the steer target.
	local facing, locked = DriveStart.Facing(s.holding, s.facing, throttle, steer, turned)
	s.facing = facing
	s.holding = locked

	-- Lean with the ground, pulled upright by this truck's tip resistance.
	-- Yaw stays the truck's; pitch and roll follow these rays, clamped.
	-- Not while holding: that lean eases a parked slope toward level
	-- (a high tipResist, in about a second) before the driver has steered.
	if s.holding then
		s.up = s.parkedUp
	else
		local target = Handling.Lean(groundUp(s), s.feel.tipResist, MAX_TILT)
		local alpha = 1 - math.exp(-s.feel.suspension * dt)
		s.up = s.up:Lerp(target, alpha)
		if s.up.Magnitude > 1e-4 then
			s.up = s.up.Unit
		end
	end
	s.heading.CFrame = VehicleLogic.HeadingCFrame(s.facing, s.up)
	local move = DriveStart.Velocity(s.facing, s.speed)
	s.drive.PlaneVelocity = Vector2.new(move.X, move.Z)
end

local function myTruck(): Model?
	for _, inst in ipairs(CollectionService:GetTagged("Truck")) do
		if inst:IsA("Model") and inst:GetAttribute("OwnerId") == player.UserId then
			return inst
		end
	end
	return nil
end

local function refreshCallButton()
	local button = callButton
	if not button then
		return
	end
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local truck = myTruck()
	-- A truck far away may not be streamed in at all: that counts as far.
	local truckPart = if truck then truck.PrimaryPart else nil
	local fromYou = if hrp and truckPart then (hrp.Position - truckPart.Position).Magnitude else nil
	local sendHome = HudRules.SendHome(hrp ~= nil and session == nil, fromYou, player:GetAttribute("TruckSlotDistance"))
	local show, text = HudRules.TruckButton(player:GetAttribute("OwnsTruck") == true, sendHome)
	button.root.Visible = show
	button:SetText(text)
end

local function buildButton()
	callButton = HUD.SideButton({
		name = "CallTruck",
		text = "Send truck home",
		style = "blue",
		order = 4,
		key = Enum.KeyCode.ButtonY,
		onPress = function()
			Net.Remote("CallTruck"):FireServer()
		end,
	})
	player:GetAttributeChangedSignal("TruckSlotDistance"):Connect(refreshCallButton)
	player:GetAttributeChangedSignal("OwnsTruck"):Connect(refreshCallButton)
	refreshCallButton()
end

-- The Classic's dash estimate shows only while you sit in your own
-- driver seat. Passengers and other trucks stay hidden. Enabled is local,
-- so other players still see the server's hidden gauge.
local function refreshGauges()
	if typeof(CollectionService.GetTagged) ~= "function" then
		return
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local seat = if humanoid then humanoid.SeatPart else nil
	for _, inst in ipairs(CollectionService:GetTagged("Truck")) do
		if inst:IsA("Model") then
			local part = inst:FindFirstChild("LoadGauge", true)
			local gui = if part then part:FindFirstChild("GaugeGui") else nil
			if gui and gui:IsA("SurfaceGui") then
				local truckId = inst:GetAttribute("TruckId")
				local ownerId = inst:GetAttribute("OwnerId")
				local driving = seat ~= nil and seat.Name == "DriverSeat" and seat:IsDescendantOf(inst)
				gui.Enabled = driving
					and ClassicGauge.Show(
						if type(truckId) == "string" then truckId else "",
						if type(ownerId) == "number" then ownerId else 0,
						player.UserId
					)
			end
		end
	end
end

local function watchCharacter(char: Model)
	session = nil
	seatLock.saved = nil -- the previous body is gone; this one has its own AutoRotate
	local humanoid = char:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Seated:Connect(function(active: boolean, seatPart: BasePart?)
		-- Off while sitting, so AutoRotate (and shift lock / first person,
		-- which face the camera) cannot twist the seat weld and the truck.
		local vehicle = active and seatPart ~= nil and seatPart:IsA("VehicleSeat")
		DriveStart.OnSeated(seatLock, humanoid, active, vehicle == true)
		if vehicle then
			if GameConfig.VehiclePhysics then
				startDriving(seatPart :: VehicleSeat)
			end
		else
			session = nil
		end
		refreshGauges()
	end)
end

-- Runs `fn(dt)` every physics step, before the solver: PreSimulation where
-- the engine has it, else Stepped.
local function everyPhysicsStep(fn: (number) -> ())
	local ok, signal = pcall(function(): RBXScriptSignal<number>
		return RunService.PreSimulation
	end)
	if ok and signal then
		signal:Connect(fn)
	else
		RunService.Stepped:Connect(function(_time: number, dt: number)
			fn(dt)
		end)
	end
end

function VehicleController.Start()
	buildButton()
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	everyPhysicsStep(step)
	local sinceRefresh = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceRefresh += dt
		if sinceRefresh >= 0.5 then
			sinceRefresh = 0
			refreshCallButton()
			refreshGauges()
		end
	end)
end

return VehicleController
