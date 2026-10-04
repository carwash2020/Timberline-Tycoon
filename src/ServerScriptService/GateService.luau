--!strict
-- GateService: the toll line. One connection on TollPay (payment is a later
-- batch; this handler only budgets the call). About twice a second the
-- server samples each character and each vehicle. An unpaid move from
-- south of the line to on or past it, anywhere in x -400..400, is pushed
-- back to the south bank, onto the ground there. A seated player takes
-- the whole assembly. The character sample updates every step, seated or
-- not, so a driver who paid, crossed, and then got out is not treated as
-- a fresh crossing when the window expires.
--
-- Anyone who ends up in the gorge (the floor trigger, or this same pass)
-- is sent to that same landing.
--
-- tollPaidUntil is not a save field. It lives on the server, keyed by
-- UserId, and is cleared when that player leaves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RateLimiter = require(script.Parent.RateLimiter)
local TollLogic = require(ReplicatedStorage.Shared.TollLogic)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)

local GateService = {}

local UNPAID_LINE = "The toll booth opens soon."

local tollPaidUntil: { [number]: number } = {}
GateService.TollPaidUntil = tollPaidUntil

-- Optional stand-in for Remotes.Notify, so a spec can read the toast
-- without the live remote existing yet.
GateService.Notify = nil :: ((Player, string) -> ())?

-- Last sample. Characters by UserId. Vehicles are weak-keyed so a
-- destroyed truck drops out; Destroying clears it too when that signal
-- exists.
local charSample: { [number]: Vector3 } = {}
local vehicleSample: { [Model]: Vector3 } = {}
setmetatable(vehicleSample, { __mode = "k" })
GateService.VehicleSample = vehicleSample

local watched: { [Model]: boolean } = {}
setmetatable(watched, { __mode = "k" })

local bound = false
local gorgeBound = false

local CHECK_SECONDS = 0.5 -- TBD (Builder) about 2 Hz

local function toast(player: Player)
	local notify = GateService.Notify
	if notify then
		notify(player, UNPAID_LINE)
	end
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = if folder then folder:FindFirstChild("Notify") else nil
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, UNPAID_LINE)
	end
end

local function paid(userId: number, now: number): boolean
	local untilAt = tollPaidUntil[userId]
	return untilAt ~= nil and untilAt > now
end

function GateService.Init(remoteEvent: RemoteEvent?)
	if bound or remoteEvent == nil then
		return
	end
	bound = true
	remoteEvent.OnServerEvent:Connect(function(player: Player)
		RateLimiter.Allow(player, "TollPay")
	end)
end

function GateService.PlayerRemoving(player: Player)
	tollPaidUntil[player.UserId] = nil
	charSample[player.UserId] = nil
end

local function zeroAssembly(inst: Instance)
	local function stop(part: BasePart)
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end
	if inst:IsA("BasePart") then
		stop(inst)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			stop(d)
		end
	end
end

-- Move `inst` so the point we measured (a pivot, or a part's position)
-- lands on the south bank, then kill the velocity PivotTo left behind.
local function placeAtLanding(inst: Instance, from: Vector3)
	local land = TollLogic.Landing()
	local delta = land - from
	if inst:IsA("Model") then
		inst:PivotTo(inst:GetPivot() + delta)
	elseif inst:IsA("BasePart") then
		inst.CFrame = inst.CFrame + delta
	end
	zeroAssembly(inst)
end

local function hasSeat(model: Model): boolean
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("VehicleSeat") then
			return true
		end
	end
	return false
end

-- The gorge trigger, and Step, both call this. Anchored map parts
-- (the bridge, the walls) are left where they are.
function GateService.RescueHit(hit: BasePart)
	if hit.Anchored then
		return
	end
	local model = hit:FindFirstAncestorOfClass("Model")
	local target: Instance = hit
	local from = hit.CFrame.Position
	if model then
		local name = model.Name
		if name == "NorthStrip" or name == "TollBridge" or name == "TollBooth" or name == "GorgeWalls" then
			return
		end
		if model:FindFirstChildOfClass("Humanoid") or hasSeat(model) or not hit.Anchored then
			target = model
			from = model:GetPivot().Position
		end
	end
	placeAtLanding(target, from)
end

local function watchVehicle(vehicle: Model)
	if watched[vehicle] then
		return
	end
	watched[vehicle] = true
	local ok, signal = pcall(function()
		return (vehicle :: any).Destroying
	end)
	if not ok or signal == nil then
		return
	end
	local connect = (signal :: any).Connect
	if type(connect) == "function" then
		connect(signal, function()
			vehicleSample[vehicle] = nil
		end)
	end
end

local function driverPaid(vehicle: Model, now: number): boolean
	local Players = game:GetService("Players")
	for _, desc in ipairs(vehicle:GetDescendants()) do
		if desc:IsA("VehicleSeat") and desc.Occupant then
			local char = desc.Occupant.Parent
			if char and char:IsA("Model") then
				local player = Players:GetPlayerFromCharacter(char)
				if player and paid(player.UserId, now) then
					return true
				end
			end
		end
	end
	return false
end

local function bindGorge()
	if gorgeBound then
		return
	end
	local ok, ws = pcall(function()
		return game:GetService("Workspace")
	end)
	if not ok or ws == nil then
		return
	end
	local foundOk, found = pcall(function()
		return ws:FindFirstChild("GorgeFloor", true)
	end)
	if not foundOk or found == nil or not found:IsA("BasePart") then
		return
	end
	gorgeBound = true
	pcall(function()
		found.Touched:Connect(function(other)
			if other:IsA("BasePart") then
				GateService.RescueHit(other)
			end
		end)
	end)
end

-- One pass. `now` is injectable so a spec can freeze the clock.
function GateService.Step(now: number?)
	local clock = now or os.clock()
	local Players = game:GetService("Players")
	bindGorge()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if not (root and root:IsA("BasePart") and humanoid and char) then
			continue
		end
		local pos = root.CFrame.Position
		local prev = charSample[player.UserId]
		-- Seated or not. Skipping this while they drive is what sent a
		-- paid driver back south the moment they climbed out.
		charSample[player.UserId] = pos

		local seat = humanoid.SeatPart
		local vehicle = if seat and seat:IsA("BasePart") then seat:FindFirstAncestorOfClass("Model") else nil
		if vehicle and TollLogic.MovesWholeAssembly(true) then
			watchVehicle(vehicle)
			local vpos = vehicle:GetPivot().Position
			local vprev = vehicleSample[vehicle]
			vehicleSample[vehicle] = vpos
			local inCut = WorldLayout.InGorge(vpos.X, vpos.Z) or WorldLayout.InGorge(pos.X, pos.Z)
			if inCut or (vprev and TollLogic.Crossed(vprev.Z, vpos.Z, vpos.X) and not driverPaid(vehicle, clock)) then
				if not inCut then
					toast(player)
				end
				placeAtLanding(vehicle, vpos)
				local landed = vehicle:GetPivot().Position
				vehicleSample[vehicle] = landed
				local delta = landed - vpos
				if char:IsA("Model") then
					char:PivotTo(char:GetPivot() + delta)
				end
				charSample[player.UserId] = root.CFrame.Position
			end
		else
			if WorldLayout.InGorge(pos.X, pos.Z) then
				placeAtLanding(char, pos)
				charSample[player.UserId] = root.CFrame.Position
			elseif prev and TollLogic.Crossed(prev.Z, pos.Z, pos.X) and not paid(player.UserId, clock) then
				placeAtLanding(char, pos)
				charSample[player.UserId] = root.CFrame.Position
				toast(player)
			end
		end
	end
end

local elapsed = 0
pcall(function()
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < CHECK_SECONDS then
			return
		end
		elapsed = 0
		local ok, err = pcall(function()
			GateService.Step()
		end)
		if not ok then
			warn("[GateService] " .. tostring(err))
		end
	end)
end)

return GateService
