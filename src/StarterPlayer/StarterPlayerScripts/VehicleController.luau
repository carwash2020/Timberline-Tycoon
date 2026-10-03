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

local DriveMath = require(ReplicatedStorage.Shared.DriveMath)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local TruckLayout = require(ReplicatedStorage.Shared.TruckLayout)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local HUD = require(script.Parent.HUD)
local HudRules = require(script.Parent.HudRules)
local UITheme = require(script.Parent.UITheme)

local VehicleController = {}

local player = Players.LocalPlayer

local MAX_TILT = math.rad(30) -- the steepest the truck leans to follow the ground
local RAY_UP = 2.5 -- corner rays start this far above the chassis...
local RAY_DOWN = 9 -- ...and look this far down
local UP_SMOOTHING = 12 -- how fast the truck's lean follows the ground (per second)

type Session = {
	truck: Model,
	seat: VehicleSeat,
	chassis: BasePart,
	drive: LinearVelocity,
	heading: AlignOrientation,
	topSpeed: number,
	turnRate: number,
	minRadius: number?, -- tightest turning circle (DriveMath.MinTurnRadius)
	speed: number,
	facing: Vector3, -- flat unit vector the truck is steering toward
	up: Vector3, -- the ground's up under the truck, smoothed
	corners: { Vector3 }, -- chassis-local ray starts (VehicleLogic.CornerOffsets)
	rayParams: RaycastParams,
}

local session: Session? = nil
local callButton: UITheme.Button? = nil

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
	local minRadius = if def then DriveMath.MinTurnRadius(TruckLayout.Wheelbase(TruckLayout.For(def))) else nil
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { truck, player.Character :: Instance }
	params.RespectCanCollide = true
	session = {
		truck = truck,
		seat = seat,
		chassis = chassis,
		drive = drive,
		heading = heading,
		topSpeed = (truck:GetAttribute("TopSpeed") :: number?) or 26,
		turnRate = (truck:GetAttribute("TurnRate") :: number?) or 1.4,
		minRadius = minRadius,
		speed = 0,
		facing = VehicleLogic.FlatFacing(chassis.CFrame.LookVector),
		up = chassis.CFrame.UpVector,
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
	local actual = Vector3.new(velocity.X, 0, velocity.Z):Dot(s.facing)
	s.speed = DriveMath.Speed(s.speed, s.seat.ThrottleFloat, s.topSpeed, dt, actual)
	local turn = DriveMath.Turn(s.speed, s.seat.SteerFloat, s.turnRate, dt, s.minRadius)
	s.facing = VehicleLogic.FlatFacing(CFrame.Angles(0, turn, 0):VectorToWorldSpace(s.facing))

	-- Lean with the ground, smoothly (slopes, bumps, later biomes).
	local target = groundUp(s)
	local alpha = 1 - math.exp(-UP_SMOOTHING * dt)
	s.up = VehicleLogic.ClampTilt(s.up:Lerp(target, alpha), MAX_TILT)
	s.heading.CFrame = VehicleLogic.HeadingCFrame(s.facing, s.up)
	local move = s.facing * s.speed
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

local function watchCharacter(char: Model)
	session = nil
	local humanoid = char:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Seated:Connect(function(active: boolean, seatPart: BasePart?)
		if active and seatPart and seatPart:IsA("VehicleSeat") then
			if GameConfig.VehiclePhysics then
				startDriving(seatPart)
			end
		else
			session = nil
		end
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
		end
	end)
end

return VehicleController
