--!strict
-- GondolaController: your own gondola ride, on your device (WLD-07).
-- GondolaService builds each rider a cabin, tags it GondolaCabin with the
-- ride written on it (Shared/GondolaRide: who rides it, when it set off by
-- the server's clock, how long it takes, its route) and hands its physics
-- to the rider's device, the way a truck goes to its driver's. Every
-- physics step (PreSimulation, before the solver runs) this aims your
-- cabin's RidePosition at where the ride says it is now; the rigid
-- constraint carries the cabin, and you in it, there. The server's clock
-- is read once when the cabin arrives (workspace:GetServerTimeNow()) and
-- then followed on os.clock, so a clock correction can't make it jitter.
-- Everyone else sees the cabin glide through Roblox's interpolated physics
-- replication; other riders' cabins are left alone here. The server ends
-- the ride (and puts you on the platform), and a jump ends it early.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GondolaRide = require(ReplicatedStorage.Shared.GondolaRide)

local GondolaController = {}

local player = Players.LocalPlayer

type Session = {
	cabin: Model,
	position: AlignPosition,
	ride: GondolaRide.Ride,
	offset: number, -- the server's clock minus os.clock()
}

local session: Session? = nil

-- A cabin streamed in: if it's yours, drive it. (A cabin streams in whole,
-- but its parts get a moment in case they're a beat behind.)
local function track(inst: Instance)
	if not inst:IsA("Model") or inst:GetAttribute("RiderId") ~= player.UserId then
		return
	end
	task.spawn(function()
		local ride = GondolaRide.Read(inst)
		local floor = inst:WaitForChild("Floor", 5)
		local position = if floor then floor:WaitForChild("RidePosition", 5) else nil
		if not ride or not inst.Parent or not position or not position:IsA("AlignPosition") then
			return
		end
		session = {
			cabin = inst,
			position = position,
			ride = ride,
			offset = workspace:GetServerTimeNow() - os.clock(),
		}
	end)
end

local function untrack(inst: Instance)
	if session and session.cabin == inst then
		session = nil
	end
end

local function step()
	local s = session
	if not s then
		return
	end
	if not s.cabin.Parent or not s.position.Parent then
		session = nil -- the ride is over
		return
	end
	local elapsed = os.clock() + s.offset - s.ride.start
	s.position.Position = GondolaRide.Target(s.ride.path, elapsed, s.ride.rideSec)
end

-- Runs `fn` every physics step, before the solver: PreSimulation where the
-- engine has it, else Stepped (as VehicleController does).
local function everyPhysicsStep(fn: () -> ())
	local ok, signal = pcall(function(): RBXScriptSignal<number>
		return RunService.PreSimulation
	end)
	if ok and signal then
		signal:Connect(fn)
	else
		RunService.Stepped:Connect(fn)
	end
end

function GondolaController.Start()
	CollectionService:GetInstanceAddedSignal(GondolaRide.Tag):Connect(track)
	CollectionService:GetInstanceRemovedSignal(GondolaRide.Tag):Connect(untrack)
	for _, inst in ipairs(CollectionService:GetTagged(GondolaRide.Tag)) do
		track(inst)
	end
	everyPhysicsStep(step)
end

return GondolaController
