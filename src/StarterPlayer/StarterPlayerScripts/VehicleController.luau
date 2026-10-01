--!strict
-- VehicleController: driving, on the driver's device.
--   * Physics driving (GameConfig.VehiclePhysics): while you sit in a
--     truck's driver seat, the server hands you its physics. Every frame
--     this turns the seat's throttle and steer (WASD / arrow keys, the
--     touch thumbstick, a gamepad's stick) into a speed and heading
--     (Shared/DriveMath), then sets the truck's Drive (LinearVelocity) and
--     Heading (AlignOrientation, tilted to match the ground).
--   * "Truck to lot" side button (Y on a gamepad): sends your truck back to
--     your parking slot, load and all, when it's far away (left somewhere,
--     or stuck).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DriveMath = require(ReplicatedStorage.Shared.DriveMath)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local HUD = require(script.Parent.HUD)
local UITheme = require(script.Parent.UITheme)

local VehicleController = {}

local player = Players.LocalPlayer

local CALL_BUTTON_DISTANCE = 40 -- studs: show "Truck to lot" when your truck is this far away

type Session = {
	truck: Model,
	seat: VehicleSeat,
	chassis: BasePart,
	drive: LinearVelocity,
	heading: AlignOrientation,
	topSpeed: number,
	turnRate: number,
	speed: number,
	facing: Vector3, -- flat unit vector the truck is steering toward
	rayParams: RaycastParams,
}

local session: Session? = nil
local callButton: UITheme.Button? = nil

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

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
		speed = 0,
		facing = flat(chassis.CFrame.LookVector),
		rayParams = params,
	}
end

local function step(dt: number)
	local s = session
	if not s then
		return
	end
	if not s.truck.Parent then
		session = nil -- the truck was rebuilt or removed
		return
	end
	local velocity = s.chassis.AssemblyLinearVelocity
	local actual = Vector3.new(velocity.X, 0, velocity.Z):Dot(s.facing)
	s.speed = DriveMath.Speed(s.speed, s.seat.ThrottleFloat, s.topSpeed, dt, actual)
	local turn = DriveMath.Turn(s.speed, s.seat.SteerFloat, s.turnRate, dt)
	s.facing = flat(CFrame.Angles(0, turn, 0):VectorToWorldSpace(s.facing))

	-- Sit level with the ground under the truck (slopes, later biomes).
	local hit = workspace:Raycast(s.chassis.Position + Vector3.new(0, 2, 0), Vector3.new(0, -12, 0), s.rayParams)
	local up = if hit then hit.Normal else Vector3.yAxis
	local look = (s.facing - up * s.facing:Dot(up)).Unit
	s.heading.CFrame = CFrame.lookAt(Vector3.zero, look, up)
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
	local far = truckPart == nil
		or (hrp ~= nil and (hrp.Position - truckPart.Position).Magnitude > CALL_BUTTON_DISTANCE)
	button.root.Visible = hrp ~= nil and session == nil and far
end

local function buildButton()
	callButton = HUD.SideButton({
		name = "CallTruck",
		text = "Truck to lot",
		style = "blue",
		order = 4,
		key = Enum.KeyCode.ButtonY,
		onPress = function()
			Net.Remote("CallTruck"):FireServer()
		end,
	})
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

function VehicleController.Start()
	buildButton()
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	RunService.Heartbeat:Connect(step)
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
