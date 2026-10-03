--!strict
-- SawmillController: the X/Y buttons on a placed mill's panel (v2).
-- The server owns the cut. A press only sends SawmillSet.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local Net = require(ReplicatedStorage.Shared.Net)

local SawmillController = {}

local BOOT_WAIT = 8 -- seconds to hear which loop runs (MapBuilder publishes it)
local hooked: { [Instance]: boolean } = {}

local function hookButton(mill: Model, button: TextButton)
	button.Activated:Connect(function()
		local uid = mill:GetAttribute("Uid")
		local axis = button:GetAttribute("Axis")
		local dir = button:GetAttribute("Dir")
		if type(uid) == "string" and (axis == "x" or axis == "y") and (dir == 1 or dir == -1) then
			Net.Remote("SawmillSet"):FireServer(uid, axis, dir)
		end
	end)
end

local function hook(inst: Instance)
	if hooked[inst] or not inst:IsA("Model") then
		return
	end
	hooked[inst] = true
	local mill = inst :: Model
	local function watch(d: Instance)
		if d:IsA("TextButton") then
			hookButton(mill, d)
		end
	end
	for _, d in ipairs(mill:GetDescendants()) do
		watch(d)
	end
	mill.DescendantAdded:Connect(watch)
end

function SawmillController.Start()
	local waited = 0
	while workspace:GetAttribute(CoreLoop.ActiveAttribute) == nil and waited < BOOT_WAIT do
		waited += task.wait(0.25)
	end
	if not CoreLoop.V2() then
		return
	end
	for _, inst in ipairs(CollectionService:GetTagged("Sawmill")) do
		hook(inst)
	end
	CollectionService:GetInstanceAddedSignal("Sawmill"):Connect(hook)
end

return SawmillController
