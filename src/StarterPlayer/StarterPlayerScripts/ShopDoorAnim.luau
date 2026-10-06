--!strict
-- ShopDoorAnim: moves the leaves of each shop's front door on this client.
-- The server owns the door: it sets DoorOpen on the shop model (and turns
-- the invisible blocker on and off). Here the leaves, which carry
-- ClosedCFrame and OpenCFrame relative to the shop's Counter, snap to the
-- state when the shop streams in and ease between the two when it changes
-- (ShopDoorLogic.StepAlpha). Looks only: nothing here can block anyone.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShopDoorLogic = require(ReplicatedStorage.Shared.ShopDoorLogic)

local ShopDoorAnim = {}

type Leaf = { part: BasePart, closed: CFrame, open: CFrame }

type Door = {
	model: Model,
	counter: BasePart,
	leaves: { Leaf },
	alpha: number, -- 0 shut .. 1 open
}

local doors: { [Model]: Door } = {}

local function collect(model: Model): Door?
	local counter = model:FindFirstChild("Counter")
	local node = model:FindFirstChild("ShopDoor")
	if counter == nil or not counter:IsA("BasePart") or node == nil then
		return nil
	end
	local leaves: { Leaf } = {}
	for _, part in ipairs(node:GetChildren()) do
		if part:IsA("BasePart") and part:GetAttribute("DoorLeaf") == true then
			local closed = part:GetAttribute("ClosedCFrame")
			local open = part:GetAttribute("OpenCFrame")
			if typeof(closed) == "CFrame" and typeof(open) == "CFrame" then
				table.insert(leaves, { part = part, closed = closed, open = open })
			end
		end
	end
	return { model = model, counter = counter, leaves = leaves, alpha = 1 }
end

local function target(model: Model): number
	return if model:GetAttribute("DoorOpen") == false then 0 else 1
end

local function pose(door: Door)
	local base = door.counter.CFrame
	local e = ShopDoorLogic.Ease(door.alpha)
	for _, leaf in ipairs(door.leaves) do
		leaf.part.CFrame = base * leaf.closed:Lerp(leaf.open, e)
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or doors[model] ~= nil then
		return
	end
	local door = collect(model)
	if door == nil then
		return
	end
	doors[model] = door
	door.alpha = target(model) -- snap to the state it streamed in with
	pose(door)
end

function ShopDoorAnim.Start()
	CollectionService:GetInstanceAddedSignal("ShopDoorModel"):Connect(track)
	for _, model in ipairs(CollectionService:GetTagged("ShopDoorModel")) do
		track(model)
	end
	CollectionService:GetInstanceRemovedSignal("ShopDoorModel"):Connect(function(model: Instance)
		if model:IsA("Model") then
			doors[model] = nil
		end
	end)
	RunService.Heartbeat:Connect(function(dt: number)
		for model, door in pairs(doors) do
			if not model:IsDescendantOf(workspace) then
				doors[model] = nil
				continue
			end
			local goal = target(model)
			if door.alpha ~= goal then
				door.alpha = ShopDoorLogic.StepAlpha(door.alpha, goal, dt)
				pose(door)
			end
		end
	end)
end

return ShopDoorAnim
