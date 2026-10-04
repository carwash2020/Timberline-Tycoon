--!strict
-- GateService: the toll line. One connection on TollPay (payment is a later
-- batch; this handler only budgets the call). About twice a second the
-- server samples each character and each vehicle. An unpaid move from
-- south of the line to on or past it, anywhere in x -400..400, is pushed
-- back to the south bank. A seated player takes the whole assembly.
-- Already-north players are not moved when a window expires: the sample
-- updates even when the toll is paid, and only an unpaid crossing pushes.
--
-- tollPaidUntil is not a save field. It lives on the server, keyed by
-- UserId, and is cleared when that player leaves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local RateLimiter = require(script.Parent.RateLimiter)
local TollLogic = require(ReplicatedStorage.Shared.TollLogic)

local GateService = {}

local tollPaidUntil: { [number]: number } = {}
GateService.TollPaidUntil = tollPaidUntil

-- Last sample. Characters by UserId, vehicles by the model.
local charSample: { [number]: Vector3 } = {}
local vehicleSample: { [Model]: Vector3 } = {}

local bound = false

local CHECK_SECONDS = 0.5 -- TBD (Builder) about 2 Hz

local function toast(player: Player, message: string)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local notify = if folder then folder:FindFirstChild("Notify") else nil
	if notify and notify:IsA("RemoteEvent") then
		notify:FireClient(player, message)
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

local function shiftModel(model: Model, dx: number, dz: number)
	local ok, pivot = pcall(function()
		return model:GetPivot()
	end)
	if ok and typeof(pivot) == "CFrame" then
		model:PivotTo(pivot + Vector3.new(dx, 0, dz))
	end
end

-- One pass. `now` is injectable so a spec can freeze the clock.
function GateService.Step(now: number?)
	local clock = now or os.clock()
	local Players = game:GetService("Players")
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
		if not (root and root:IsA("BasePart") and humanoid) then
			continue
		end
		local seat = humanoid.SeatPart
		if seat and seat:IsA("BasePart") and TollLogic.MovesWholeAssembly(true) then
			local vehicle = seat:FindFirstAncestorOfClass("Model")
			if vehicle then
				local pos = vehicle:GetPivot().Position
				local prev = vehicleSample[vehicle]
				vehicleSample[vehicle] = pos
				if prev and TollLogic.Crossed(prev.Z, pos.Z, pos.X) and not driverPaid(vehicle, clock) then
					local moved = TollLogic.MoveAssembly({ pos })
					local lead = moved[1]
					shiftModel(vehicle, lead.X - pos.X, lead.Z - pos.Z)
					vehicleSample[vehicle] = lead
					toast(player, string.format("Old Tolly charges $%d to cross.", GameConfig.TollFee))
				end
			end
		else
			local pos = root.Position
			local prev = charSample[player.UserId]
			charSample[player.UserId] = pos
			if prev and TollLogic.Crossed(prev.Z, pos.Z, pos.X) and not paid(player.UserId, clock) then
				local moved = TollLogic.MoveAssembly({ pos })
				local lead = moved[1]
				root.CFrame = root.CFrame + Vector3.new(lead.X - pos.X, 0, lead.Z - pos.Z)
				charSample[player.UserId] = lead
				toast(player, string.format("Old Tolly charges $%d to cross.", GameConfig.TollFee))
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
