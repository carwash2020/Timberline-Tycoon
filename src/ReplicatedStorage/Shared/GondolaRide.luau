--!strict
-- GondolaRide: the rules of a gondola ride that don't need Roblox running,
-- shared by the server (GondolaService) and the rider's device
-- (GondolaController), so both put the cabin in the same place at the same
-- moment. Tested in tests/GondolaRide.spec.luau.
--   * How far along its route the cabin is, `elapsed` seconds after the
--     ride set off (Alpha): 0 to 1 over the ride's rideSec, with EaseSec of
--     speeding up out of the station and of slowing into the next one, so
--     it doesn't lurch off or stop dead. Door to door it still takes
--     rideSec.
--   * Where that is (Target): WorldPlan.AlongPath, which goes by length,
--     so the speed holds round the route's bends.
--   * Which way the cabin faces (Facing): level, from the route's first
--     point toward its last, the whole way.
--   * The ride as attributes on the cabin (Publish, Read): who rides it,
--     when it set off (workspace:GetServerTimeNow()), how long it takes and
--     its route, so the rider's device can move it.
--   * Where to have the world streamed in for a rider (StreamPoints): the
--     end of the route first, then points along it.
-- Uses only datatypes (no services). Facing comes from fromMatrix, never
-- lookAt, so Roblox and the Lune tests agree.

local WorldPlan = require(script.Parent.World.WorldPlan)

local GondolaRide = {}

GondolaRide.Tag = "GondolaCabin" -- CollectionService tag on every cabin
GondolaRide.EaseSec = 2 -- seconds of speeding up at the start, and of slowing down at the end

export type Ride = {
	riderId: number, -- the rider's UserId
	start: number, -- workspace:GetServerTimeNow() when it set off
	rideSec: number,
	path: { Vector3 }, -- where the cabin's pivot goes, start to end
}

-- The share (0 to 1) of the route's length covered `elapsed` seconds into a
-- ride of `rideSec`: steady speed in the middle, a steady pick-up over the
-- first EaseSec and a steady slow-down over the last (never more than a
-- quarter of the ride each), so the speed starts and ends at 0 and the
-- cruise is only a little faster than an even glide (1 / (1 - EaseSec /
-- rideSec) times). 0 before the start, 1 from rideSec on.
function GondolaRide.Alpha(elapsed: number, rideSec: number): number
	if rideSec <= 0 then
		return 1
	end
	local u = math.clamp(elapsed / rideSec, 0, 1)
	local ease = math.min(GondolaRide.EaseSec / rideSec, 0.25)
	if ease <= 0 then
		return u
	end
	local cruise = 1 / (1 - ease) -- routes per rideSec
	if u < ease then
		return 0.5 * cruise * u * u / ease
	elseif u > 1 - ease then
		local left = 1 - u
		return 1 - 0.5 * cruise * left * left / ease
	end
	return cruise * (u - 0.5 * ease)
end

-- Where the cabin's pivot is `elapsed` seconds into the ride along `path`.
function GondolaRide.Target(path: { Vector3 }, elapsed: number, rideSec: number): Vector3
	return WorldPlan.AlongPath(path, GondolaRide.Alpha(elapsed, rideSec))
end

-- The cabin's turn for the whole ride (a rotation, no position): upright,
-- its front (-Z, LookVector) level and toward the route's last point as
-- seen from its first. No turn for a route that goes straight up.
function GondolaRide.Facing(path: { Vector3 }): CFrame
	local from, to = path[1], path[#path]
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if flat.Magnitude <= 1 then
		return CFrame.identity
	end
	local look = flat.Unit
	local up = Vector3.new(0, 1, 0)
	return CFrame.fromMatrix(Vector3.zero, look:Cross(up), up, -look)
end

-- Writes `ride` onto the cabin as attributes (Read reads them back).
function GondolaRide.Publish(cabin: Instance, ride: Ride)
	cabin:SetAttribute("RiderId", ride.riderId)
	cabin:SetAttribute("RideStart", ride.start)
	cabin:SetAttribute("RideSec", ride.rideSec)
	cabin:SetAttribute("RidePoints", #ride.path)
	for i, point in ipairs(ride.path) do
		cabin:SetAttribute("RidePoint" .. i, point)
	end
end

-- The ride published on `cabin`, or nil if it isn't all there.
function GondolaRide.Read(cabin: Instance): Ride?
	local riderId = cabin:GetAttribute("RiderId")
	local start = cabin:GetAttribute("RideStart")
	local rideSec = cabin:GetAttribute("RideSec")
	local count = cabin:GetAttribute("RidePoints")
	if type(riderId) ~= "number" or type(start) ~= "number" or type(rideSec) ~= "number" then
		return nil
	end
	if type(count) ~= "number" or count < 2 then
		return nil
	end
	local path: { Vector3 } = {}
	for i = 1, count do
		local point = cabin:GetAttribute("RidePoint" .. i)
		if typeof(point) ~= "Vector3" then
			return nil
		end
		table.insert(path, point)
	end
	return { riderId = riderId, start = start, rideSec = rideSec, path = path }
end

-- The points to stream in around for a ride along `path`, in the order to
-- ask: the end (the station you arrive at) first, then points from the
-- start on, never more than `spacing` studs apart. The start, where the
-- rider already is, isn't in it.
function GondolaRide.StreamPoints(path: { Vector3 }, spacing: number): { Vector3 }
	local out = { path[#path] }
	local total = 0
	for i = 1, #path - 1 do
		total += (path[i + 1] - path[i]).Magnitude
	end
	local steps = math.max(1, math.ceil(total / math.max(spacing, 1)))
	for k = 1, steps - 1 do
		table.insert(out, WorldPlan.AlongPath(path, k / steps))
	end
	return out
end

return GondolaRide
