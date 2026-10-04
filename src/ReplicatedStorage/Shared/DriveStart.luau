--!strict
-- DriveStart: what a truck does the moment its owner sits down.
-- The chassis CFrame is the only heading. A camera look (shift lock,
-- first person) is not. Pitch and roll stay as parked; the drive loop
-- leans them with the ground afterwards. Steering waits for throttle or
-- steer, so a seat weld that tugs the chassis cannot turn it.

local Handling = require(script.Parent.Handling)

local DriveStart = {}

-- Below this, throttle and steer are idle (the same deadzone Handling.Speed uses).
DriveStart.Deadzone = 0.05

export type SeatLock = { saved: boolean? }

-- The orientation to lock, parked where the chassis is. `cameraLook` is
-- accepted so a caller can pass the camera and still get the chassis.
function DriveStart.Seed(chassisCF: CFrame, _cameraLook: Vector3?): CFrame
	return chassisCF - chassisCF.Position
end

-- AssemblyMass of the parked chassis. Lune's parts omit it; 1 still arms
-- the lock, and VehicleService's deferred step writes the welded mass.
local function assemblyMass(chassis: BasePart): number
	local ok, mass = pcall(function()
		return chassis.AssemblyMass
	end)
	if ok and type(mass) == "number" and mass == mass and mass > 0 and mass < math.huge then
		return mass
	end
	return 1
end

-- Point Heading at the parked rotation and give it torque. Call this
-- while the chassis is still anchored, before SetNetworkOwner.
function DriveStart.Arm(chassis: BasePart, heading: AlignOrientation, truckId: string?)
	heading.CFrame = DriveStart.Seed(chassis.CFrame)
	heading.MaxTorque = assemblyMass(chassis) * Handling.HoldTorque(Handling.For(truckId))
	heading.Enabled = true
end

function DriveStart.HasInput(throttle: number, steer: number): boolean
	return math.abs(throttle) >= DriveStart.Deadzone or math.abs(steer) >= DriveStart.Deadzone
end

-- While `locked`, ignore `turned` (a facing the drive math, or the camera,
-- would steer toward) until the driver throttles or steers. Returns the
-- facing to use and whether the hold is still on.
function DriveStart.Facing(
	locked: boolean,
	parked: Vector3,
	throttle: number,
	steer: number,
	turned: Vector3
): (Vector3, boolean)
	if locked and not DriveStart.HasInput(throttle, steer) then
		return parked, true
	end
	return turned, false
end

-- World studs/s along the truck's nose. Positive speed is forward, never
-- along the camera.
function DriveStart.Velocity(facing: Vector3, speed: number): Vector3
	return facing * speed
end

-- Remember AutoRotate, then turn it off for a VehicleSeat. Seated(false)
-- puts the saved value back. `saved` nil means we are not holding one
-- (a new character starts that way).
function DriveStart.OnSeated(lock: SeatLock, humanoid: Humanoid, active: boolean, vehicle: boolean)
	if active and vehicle then
		if lock.saved == nil then
			lock.saved = humanoid.AutoRotate
		end
		humanoid.AutoRotate = false
		return
	end
	if lock.saved ~= nil then
		humanoid.AutoRotate = lock.saved
		lock.saved = nil
	end
end

return DriveStart
