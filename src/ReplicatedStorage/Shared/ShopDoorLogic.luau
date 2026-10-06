--!strict
-- ShopDoorLogic: the front doors of the shops. Pure. There is ONE open or
-- closed rule, ShopHoursLogic.IsOpen (the shopkeeper's hours, the same
-- clock as the sky and the Studio override); this module only decides what
-- the door does with it:
--   * the blocker (DoorBlock) collides only while the shop is closed, nobody
--     holds the door open, and nobody stands in the doorway;
--   * a player inside who walks to a closed door touches the inside sensor
--     (DoorSensor), which holds the door open for ShopHoursLogic.ExitHold,
--     so nobody is ever shut in. The sensor sits beyond reach of anyone
--     outside: the blocker is between them.
-- The server owns the state (the DoorLocked and DoorOpen attributes on the
-- shop model); each client tweens the leaves to match (ShopDoorAnim).

local ShopHoursLogic = require(script.Parent.ShopHoursLogic)

local ShopDoorLogic = {}

-- Seconds a leaf takes to open or close on the client.
ShopDoorLogic.TweenSeconds = 0.9

-- How far past the blocker's volume a player still counts as standing in
-- the doorway (the door will not shut on them), in studs.
ShopDoorLogic.DoorwayPad = 2.5

-- The sensor stands this many studs inside the door plane and is this deep.
ShopDoorLogic.SensorInset = 3
ShopDoorLogic.SensorDepth = 4

-- Whether the blocker is up (the door is shut and blocks the way in).
-- `holding`: someone inside asked to leave and the hold has not run out.
-- `occupied`: a player stands in the doorway right now.
function ShopDoorLogic.Locked(shopId: string, hour: number, holding: boolean, occupied: boolean): boolean
	if ShopHoursLogic.IsOpen(shopId, hour) then
		return false
	end
	return not holding and not occupied
end

-- The shop is open by the shopkeeper's hours (the one rule).
function ShopDoorLogic.IsOpen(shopId: string, hour: number): boolean
	return ShopHoursLogic.IsOpen(shopId, hour)
end

-- Whether any of `points` is inside the doorway volume: the blocker's box
-- (`cf`, `size`) grown by DoorwayPad on every side.
function ShopDoorLogic.Occupied(points: { Vector3 }, cf: CFrame, size: Vector3): boolean
	local pad = ShopDoorLogic.DoorwayPad
	for _, point in ipairs(points) do
		local p = cf:PointToObjectSpace(point)
		if
			math.abs(p.X) <= size.X / 2 + pad
			and math.abs(p.Y) <= size.Y / 2 + pad
			and math.abs(p.Z) <= size.Z / 2 + pad
		then
			return true
		end
	end
	return false
end

-- The clock text on the closed sign. ONE place for the 12-hour format, so
-- swapping the clock display (the HUD clock is moving to AM/PM) is a change
-- to this function only: 7 -> "7 AM", 7.5 -> "7:30 AM", 0 -> "12 AM",
-- 12 -> "12 PM", 19 -> "7 PM".
function ShopDoorLogic.FormatClock(hour: number): string
	local h = hour % 24
	local whole = math.floor(h + 1e-6)
	local minutes = math.floor((h - whole) * 60 + 0.5)
	if minutes >= 60 then
		whole += 1
		minutes = 0
	end
	whole = whole % 24
	local suffix = if whole < 12 then "AM" else "PM"
	local twelve = whole % 12
	if twelve == 0 then
		twelve = 12
	end
	if minutes == 0 then
		return string.format("%d %s", twelve, suffix)
	end
	return string.format("%d:%02d %s", twelve, minutes, suffix)
end

-- "Closed - opens at 7 AM", or "" while the shop is open.
function ShopDoorLogic.ClosedText(shopId: string, hour: number): string
	if ShopHoursLogic.IsOpen(shopId, hour) then
		return ""
	end
	return "Closed - opens at " .. ShopDoorLogic.FormatClock(ShopHoursLogic.NextOpen(shopId, hour))
end

-- One step of a client tween: `alpha` (0 shut .. 1 open) moves toward
-- `target` by dt / TweenSeconds, never past it.
function ShopDoorLogic.StepAlpha(alpha: number, target: number, dt: number): number
	local step = dt / ShopDoorLogic.TweenSeconds
	if alpha < target then
		return math.min(target, alpha + step)
	end
	return math.max(target, alpha - step)
end

-- Smooth ease for the leaf poses.
function ShopDoorLogic.Ease(alpha: number): number
	local a = math.clamp(alpha, 0, 1)
	return a * a * (3 - 2 * a)
end

return ShopDoorLogic
