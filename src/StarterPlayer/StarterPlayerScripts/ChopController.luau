-- ChopController: click (or click-hold) on a tree to chop it.
-- Raycasts from the camera through the mouse to find a "Tree"-tagged model,
-- then fires ChopTree to the server. Cooldown is mirrored client-side for
-- responsiveness; the server re-checks it, so this is not security.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ChopController = {}

local player = Players.LocalPlayer

local SWING_COOLDOWN = 0.8
local MOUSE = Enum.UserInputType.MouseButton1

local remotes: Folder? = nil
local chopping = false
local currentTreeUid: string? = nil
local cooldownUntil = 0

local function getRemotes(): Folder
	if not remotes then
		remotes = ReplicatedStorage:WaitForChild("Remotes")
	end
	return remotes :: Folder
end

-- Walk up from the hit part to the tagged tree model (or nil).
local function findTreeModel(inst: Instance): Model?
	local node: Instance? = inst
	while node and node ~= workspace do
		if node:IsA("Model") and CollectionService:HasTag(node, "Tree") then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function sendSwing()
	local char = player.Character
	if not char then
		return
	end
	if not char:FindFirstChildOfClass("Tool") then
		return
	end
	if not currentTreeUid then
		return
	end
	if os.clock() < cooldownUntil then
		return
	end
	cooldownUntil = os.clock() + SWING_COOLDOWN
	getRemotes().ChopTree:FireServer(currentTreeUid)
	local tool = char:FindFirstChildOfClass("Tool")
	if tool then
		tool:Activate() -- plays the swing animation, if any
	end
end

-- Hold-to-chop loop: re-swing every cooldown while the button is held.
local function setupHoldLoop()
	local nextSwingAt = 0
	RunService.RenderStepped:Connect(function()
		if chopping and os.clock() >= nextSwingAt then
			nextSwingAt = os.clock() + SWING_COOLDOWN
			sendSwing()
		end
	end)
end

local function pickTreeUnderMouse(): string?
	local char = player.Character
	if not char then
		return nil
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mouse = player:GetMouse()
	local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 100, params)
	if not result or not result.Instance then
		return nil
	end
	local treeModel = findTreeModel(result.Instance)
	if not treeModel then
		return nil
	end
	return treeModel:GetAttribute("Uid") :: string?
end

function ChopController.Start()
	setupHoldLoop()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or input.UserInputType ~= MOUSE then
			return
		end
		local uid = pickTreeUnderMouse()
		if uid == nil then
			return
		end
		currentTreeUid = uid
		chopping = true
		sendSwing()
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == MOUSE then
			chopping = false
			currentTreeUid = nil
		end
	end)
end

return ChopController
