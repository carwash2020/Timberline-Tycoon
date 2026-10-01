--!strict
-- CarryController: the client half of loading and selling.
-- Log pickup is a server-side ProximityPrompt on each log. Loading and
-- selling use prompts this script creates locally, so each player only sees
-- the prompts that apply to them:
--   * "Load logs" on YOUR truck's tailgate, while you're carrying logs.
--   * "Sell logs" at the sawmill, while you stand on the sell pad with logs.
-- Prompts work with keyboard (E), touch (tap) and gamepad out of the box,
-- and Roblox only shows the nearest prompt per button, so Pick up / Load /
-- Drive / Sell never fight over the same key. The server re-validates
-- range, capacity and the sell zone on every request.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util)

local CarryController = {}

local player = Players.LocalPlayer

local myTruck: Model? = nil
local loadPrompt: ProximityPrompt? = nil
local truckConn: RBXScriptConnection? = nil

local function carried(): number
	return (player:GetAttribute("CarriedLogs") :: number?) or 0
end

local function bedCount(): number
	local truck = myTruck
	return if truck then (truck:GetAttribute("BedCount") :: number?) or 0 else 0
end

local function bedCapacity(): number
	local truck = myTruck
	return if truck then (truck:GetAttribute("BedCapacity") :: number?) or 0 else 0
end

local function newPrompt(parent: Instance, maxDistance: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.MaxActivationDistance = maxDistance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = parent
	return prompt
end

local function refreshLoadPrompt()
	local prompt = loadPrompt
	if not prompt then
		return
	end
	local n = carried()
	prompt.Enabled = n > 0 and bedCount() < bedCapacity()
	prompt.ActionText = if n == 1 then "Load 1 log" else string.format("Load %d logs", n)
	prompt.ObjectText = string.format("Truck bed %d/%d", bedCount(), bedCapacity())
end

local function bindTruck(truck: Model)
	if truck:GetAttribute("OwnerId") ~= player.UserId then
		return
	end
	if ((truck:GetAttribute("BedCapacity") :: number?) or 0) <= 0 then
		-- No bed (the Scout ATV): nothing to load.
		if loadPrompt then
			loadPrompt:Destroy()
			loadPrompt = nil
		end
		myTruck = truck
		return
	end
	task.spawn(function()
		-- The LoadPoint sits behind the last bed: the truck's, or the
		-- trailer's when one is hitched. Wait a moment for it to stream in.
		local point: Instance? = nil
		for _ = 1, 20 do
			point = truck:FindFirstChild("LoadPoint", true)
			if point then
				break
			end
			task.wait(0.5)
		end
		if not point or not point:IsA("Attachment") then
			return
		end
		if loadPrompt then
			loadPrompt:Destroy()
		end
		if truckConn then
			truckConn:Disconnect()
		end
		myTruck = truck
		local prompt = newPrompt(point, GameConfig.LoadPromptRange)
		prompt.Triggered:Connect(function()
			Net.Remote("LoadToTruck"):FireServer()
		end)
		loadPrompt = prompt
		truckConn = truck:GetAttributeChangedSignal("BedCount"):Connect(refreshLoadPrompt)
		refreshLoadPrompt()
	end)
end

local function setupSellPrompt()
	local map = workspace:WaitForChild("TimberlineMap")
	local area = map:WaitForChild("SellArea") -- a Persistent model: always streamed in
	local zone = area:WaitForChild("SellZone") :: BasePart
	local point = zone:WaitForChild("SellPoint")

	local prompt = newPrompt(point, 40) -- the zone check below is what gates it
	prompt.ObjectText = "Timberline Sawmill"
	prompt.Triggered:Connect(function()
		Net.Remote("SellLogs"):FireServer()
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 0.2 then
			return
		end
		elapsed = 0
		local char = player.Character
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
		local inZone = hrp ~= nil and Util.pointInPart(zone, hrp.Position)
		-- Mirrors the server: the bed only counts if the truck is at the mill.
		local truckPart = if myTruck then myTruck.PrimaryPart else nil
		local truckHere = false
		if truckPart then
			local d = truckPart.Position - zone.Position
			truckHere = Vector3.new(d.X, 0, d.Z).Magnitude <= GameConfig.SellTruckRange
		end
		-- Logs waiting in the Sky Bin (sent down the Cloud Chute) sell here too.
		local skyBin = (player:GetAttribute("SkyBin") :: number?) or 0
		local n = carried() + (if truckHere then bedCount() else 0) + skyBin
		prompt.Enabled = inZone and n > 0
		prompt.ActionText = if n == 1 then "Sell 1 log" else string.format("Sell %d logs", n)
	end)
end

function CarryController.Start()
	player:GetAttributeChangedSignal("CarriedLogs"):Connect(refreshLoadPrompt)
	for _, inst in ipairs(CollectionService:GetTagged("Truck")) do
		if inst:IsA("Model") then
			bindTruck(inst)
		end
	end
	-- Also fires when your truck streams back into range.
	CollectionService:GetInstanceAddedSignal("Truck"):Connect(function(inst)
		if inst:IsA("Model") then
			bindTruck(inst)
		end
	end)
	task.spawn(setupSellPrompt)
end

return CarryController
