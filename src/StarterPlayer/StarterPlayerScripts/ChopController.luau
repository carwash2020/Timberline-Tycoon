--!strict
-- ChopController: chop with the equipped axe on any device.
-- A click, a tap on the screen and the gamepad trigger all fire the Tool's
-- Activated event, so there's no per-device input code. Hold to keep chopping.
--
-- Target: the tree under the pointer (mouse, or the last tap), or, if
-- there isn't a choppable one, the nearest tree within AutoTargetRange (for
-- gamepads and slightly-missed taps). The cooldown is mirrored here for
-- responsiveness; the server re-checks everything, so this isn't security.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local HUD = require(script.Parent.HUD)

local ChopController = {}

local player = Players.LocalPlayer

local holding = false
local cooldownUntil = 0
local lastTap: Vector2? = nil -- screen position of the last touch on the 3D world
local bound: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- The axe definition behind a tool (axe tools carry an "AxeId" attribute).
local function axeOf(tool: Tool): ItemCatalog.AxeDef?
	local id = tool:GetAttribute("AxeId")
	return if type(id) == "string" then ItemCatalog.GetAxe(id) else nil
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

local function isAlive(tree: Model): boolean
	local hp = tree:GetAttribute("HP")
	return type(hp) == "number" and hp > 0
end

-- Can this axe cut this tree at all? (Harder wood needs a stronger axe.)
local function canCut(axe: ItemCatalog.AxeDef, tree: Model): boolean
	local wood = WoodData.Get(tostring(tree:GetAttribute("WoodId")))
	return wood ~= nil and ItemCatalog.AxeDamage(axe, wood) > 0
end

local function flatDistance(tree: Model, from: Vector3): number
	local home = tree:GetAttribute("HomePivot")
	local pos = if typeof(home) == "CFrame" then home.Position else tree:GetPivot().Position
	return Vector3.new(pos.X - from.X, 0, pos.Z - from.Z).Magnitude
end

-- Ray from wherever the player is pointing, or nil for gamepads.
local function pointerRay(camera: Camera): Ray?
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		local tap = lastTap
		return if tap then camera:ScreenPointToRay(tap.X, tap.Y) else nil
	elseif string.sub(last.Name, 1, 7) == "Gamepad" then
		return nil
	end
	local m = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(m.X, m.Y)
end

-- Returns (tree, problem) where problem explains a miss: "far" if the
-- pointer is on a tree out of reach, "hard" if it's on one this axe can't cut.
local function pickTarget(hrp: BasePart, axe: ItemCatalog.AxeDef): (Model?, string?)
	local problem: string? = nil
	local camera = workspace.CurrentCamera
	local ray = if camera then pointerRay(camera) else nil
	if ray then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Instance }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 250, params)
		local tree = if hit then findTreeModel(hit.Instance) else nil
		if tree and isAlive(tree) then
			if not canCut(axe, tree) then
				problem = "hard"
			elseif flatDistance(tree, hrp.Position) <= GameConfig.ChopRange then
				return tree, nil
			else
				problem = "far"
			end
		end
	end
	-- Nothing choppable under the pointer: take the nearest tree within reach.
	local best: Model? = nil
	local bestDist = GameConfig.AutoTargetRange
	for _, inst in ipairs(CollectionService:GetTagged("Tree")) do
		if inst:IsA("Model") and isAlive(inst) and canCut(axe, inst) then
			local d = flatDistance(inst, hrp.Position)
			if d <= bestDist then
				best, bestDist = inst, d
			end
		end
	end
	return best, if best == nil then problem else nil
end

-- The default character Animate script plays its built-in tool-slash
-- animation when a StringValue "toolanim" = "Slash" appears in the tool.
local function playSlash(tool: Tool)
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	Debris:AddItem(anim, 1)
end

local function trySwing(fromClick: boolean)
	local now = os.clock()
	if now < cooldownUntil then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	local tool = char:FindFirstChildOfClass("Tool")
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local axe = if tool then axeOf(tool) else nil
	if not tool or not hrp or not axe then
		return
	end
	local tree, problem = pickTarget(hrp, axe)
	if not tree then
		if fromClick and problem == "far" then
			HUD.Toast("Too far away. Walk closer to chop.")
		elseif fromClick and problem == "hard" then
			HUD.Toast(string.format("This wood is too hard for your %s. You need a stronger axe.", axe.displayName))
		end
		return
	end
	cooldownUntil = now + GameConfig.SwingCooldown
	Net.Remote("ChopTree"):FireServer(tree:GetAttribute("Uid"))
	playSlash(tool)
end

local function bindTool(tool: Tool)
	if bound[tool] or not axeOf(tool) then
		return
	end
	bound[tool] = true
	tool.Activated:Connect(function()
		holding = true
		-- Defer one step so a tap's InputBegan (which records where it
		-- landed) has run before we aim.
		task.defer(trySwing, true)
	end)
	tool.Deactivated:Connect(function()
		holding = false
	end)
	tool.Unequipped:Connect(function()
		holding = false
	end)
end

local function watchCharacter(char: Model)
	holding = false
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then
			bindTool(child)
		end
	end
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			bindTool(child)
		end
	end)
end

function ChopController.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.UserInputType == Enum.UserInputType.Touch then
			lastTap = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	-- Hold-to-chop: keep swinging every cooldown while the button is down.
	RunService.Heartbeat:Connect(function()
		if holding and os.clock() >= cooldownUntil then
			trySwing(false)
		end
	end)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

return ChopController
