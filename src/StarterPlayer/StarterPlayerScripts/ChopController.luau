--!strict
-- ChopController: chop with the equipped axe on any device.
-- A click, a tap on the screen and the gamepad trigger all fire the Tool's
-- Activated event, so there's no per-device input code. Hold to keep chopping.
--
-- Target: the tree (or crystal node, "Node" tag) under the pointer (mouse,
-- or the last tap), or, if there isn't one, the nearest within
-- AutoTargetRange (for gamepads and slightly-missed taps). Reach is
-- measured from the bark (GameConfig.ChopRange + the tree's TrunkRadius),
-- like the server. Nodes take any axe and go to MineNode instead of
-- ChopTree. The cooldown is mirrored here for responsiveness; the server
-- re-checks everything, so this isn't security.
--
-- While an axe is out, whatever you'd chop is outlined: cream when it's in
-- reach, amber when your axe is too weak for it. Out of reach, no outline.
--
-- Each swing first turns you to face its tree (FaceTarget: yaw only, and
-- only when it's more than 15 degrees off to the side), so the slash lands
-- on the trunk; holding to chop turns you again on every swing. Not while
-- you sit or climb.
--
-- The v1 loop only: under the v2 loop (Shared/CoreLoop) CutController
-- swings the axe (sections and crystal nodes) and this never swings or
-- outlines anything.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local FaceTarget = require(script.Parent.FaceTarget)
local HUD = require(script.Parent.HUD)

local ChopController = {}

local player = Players.LocalPlayer

local TARGET_TAGS = { "Tree", "Node" }
local AIM_INTERVAL = 0.1 -- seconds between outline updates
local RETRY_INTERVAL = 0.2 -- holding with nothing to chop: look again this often
local READY_COLOR = Color3.fromRGB(255, 244, 214)
local HARD_COLOR = Color3.fromRGB(255, 170, 70)

local holding = false
local cooldownUntil = 0 -- next swing allowed (mirrors the server)
local retryAt = 0 -- holding with nothing to chop: next look
local lastTap: Vector2? = nil -- screen position of the last touch on the 3D world
local lastHardToast = 0
local bound: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Every tree and node that has streamed in, kept up to date by tag signals
-- (so auto-targeting never builds a fresh list of the whole forest).
local targets: { [Model]: boolean } = {}

local highlight: Highlight? = nil

-- The axe definition behind a tool (axe tools carry an "AxeId" attribute).
local function axeOf(tool: Tool): ItemCatalog.AxeDef?
	local id = tool:GetAttribute("AxeId")
	return if type(id) == "string" then ItemCatalog.GetAxe(id) else nil
end

local function isNode(model: Model): boolean
	return CollectionService:HasTag(model, "Node")
end

-- Walk up from the hit part to the tagged tree or node model (or nil).
local function findTreeModel(inst: Instance): Model?
	local node: Instance? = inst
	while node and node ~= workspace do
		if node:IsA("Model") and targets[node] then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function isAlive(tree: Model): boolean
	local hp = tree:GetAttribute("HP")
	-- Dormant = hidden for now (the Gloam Hollow by day).
	return type(hp) == "number" and hp > 0 and tree:GetAttribute("Dormant") ~= true
end

-- Can this axe cut this tree at all? (Harder wood needs a stronger axe.)
local function canCut(axe: ItemCatalog.AxeDef, tree: Model): boolean
	if isNode(tree) then
		return true -- any axe mines crystals
	end
	local wood = WoodData.Get(tostring(tree:GetAttribute("WoodId")))
	return wood ~= nil and ItemCatalog.AxeDamage(axe, wood) > 0
end

-- Where a tree (or node) stands: its HomePivot when it has one, else its pivot.
local function baseOf(tree: Model): Vector3
	local home = tree:GetAttribute("HomePivot")
	return if typeof(home) == "CFrame" then home.Position else tree:GetPivot().Position
end

-- Horizontal distance from `from` to the tree's bark (to a node's centre).
local function reachTo(tree: Model, from: Vector3): number
	local pos = baseOf(tree)
	local radius = tree:GetAttribute("TrunkRadius")
	local flat = Vector3.new(pos.X - from.X, 0, pos.Z - from.Z).Magnitude
	return flat - (if type(radius) == "number" then radius else 0)
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

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- The tree under the pointer, if any, with what's in the way of chopping
-- it: nil (go ahead), "far" or "hard".
local function pointed(hrp: BasePart, axe: ItemCatalog.AxeDef): (Model?, string?)
	local camera = workspace.CurrentCamera
	local ray = if camera then pointerRay(camera) else nil
	if not ray then
		return nil, nil
	end
	rayParams.FilterDescendantsInstances = { player.Character :: Instance }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 250, rayParams)
	local tree = if hit then findTreeModel(hit.Instance) else nil
	if not tree or not isAlive(tree) then
		return nil, nil
	end
	if not canCut(axe, tree) then
		return tree, "hard"
	elseif reachTo(tree, hrp.Position) > GameConfig.ChopRange then
		return tree, "far"
	end
	return tree, nil
end

-- The nearest choppable tree within AutoTargetRange of the bark.
local function nearest(hrp: BasePart, axe: ItemCatalog.AxeDef): Model?
	local best: Model? = nil
	local bestDist = GameConfig.AutoTargetRange
	for model in pairs(targets) do
		if isAlive(model) then
			local d = reachTo(model, hrp.Position)
			if d <= bestDist and canCut(axe, model) then
				best, bestDist = model, d
			end
		end
	end
	return best
end

-- Returns (tree, problem): the tree to chop, or nil and why the pointed-at
-- tree can't be chopped ("far" / "hard").
local function pickTarget(hrp: BasePart, axe: ItemCatalog.AxeDef): (Model?, string?)
	local tree, problem = pointed(hrp, axe)
	if tree and problem == nil then
		return tree, nil
	end
	local best = nearest(hrp, axe)
	return best, if best == nil then problem else nil
end

-- Turns the character to face `tree` before a swing (see the header).
-- Skipped while sitting (the root part is welded to the seat, so turning
-- it would swing the truck), climbing, knocked over (PlatformStand) or
-- dead. The turn only has to hold for the slash: Humanoid.AutoRotate
-- leaves a character that stands still facing where it was put, and one
-- that's walking (or in shift lock / first person, which face the camera)
-- turns back on its own afterwards, so AutoRotate is left alone.
local function faceTree(hrp: BasePart, tree: Model)
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if
		not humanoid
		or humanoid.Sit
		or humanoid.SeatPart ~= nil
		or humanoid.PlatformStand
		or humanoid.Health <= 0
		or hrp.Anchored
		or humanoid:GetState() == Enum.HumanoidStateType.Climbing
	then
		return
	end
	local turned = FaceTarget.Turn(hrp.CFrame, baseOf(tree))
	if turned then
		hrp.CFrame = turned
	end
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

-- The equipped axe tool, its definition and the root part, or nils.
local function equipped(): (Tool?, ItemCatalog.AxeDef?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local axe = if tool then axeOf(tool) else nil
	if not tool or not axe or not hrp then
		return nil, nil, nil
	end
	return tool, axe, hrp
end

local function trySwing(fromClick: boolean)
	if CoreLoop.V2() then
		return -- CutController swings in the v2 loop
	end
	local now = os.clock()
	if now < cooldownUntil then
		return
	end
	local tool, axe, hrp = equipped()
	if not tool or not axe or not hrp then
		return
	end
	local tree, problem = pickTarget(hrp, axe)
	if not tree then
		if fromClick and problem == "far" then
			HUD.Toast("Too far away. Walk closer to chop.")
		elseif fromClick and problem == "hard" then
			SoundData.Play("ChopTooHard")
			if now - lastHardToast > 3 then
				lastHardToast = now
				HUD.Toast(string.format("This wood is too hard for your %s. You need a stronger axe.", axe.displayName))
			end
		end
		-- Holding with nothing to chop: don't search the forest every frame.
		retryAt = now + RETRY_INTERVAL
		return
	end
	cooldownUntil = now + GameConfig.SwingCooldown
	faceTree(hrp, tree)
	Net.Remote(if isNode(tree) then "MineNode" else "ChopTree"):FireServer(tree:GetAttribute("Uid"))
	playSlash(tool)
	SoundData.Play("Swing")
end

-- Outlines what you'd chop right now (see the header).
local function updateOutline()
	local hl = highlight
	if not hl then
		return
	end
	if CoreLoop.V2() then
		hl.Enabled = false
		return
	end
	local _tool, axe, hrp = equipped()
	local target: Model? = nil
	local color = READY_COLOR
	if axe and hrp then
		local tree, problem = pointed(hrp, axe)
		if tree and problem == nil then
			target = tree
		elseif tree and problem == "hard" and reachTo(tree, hrp.Position) <= GameConfig.ChopRange then
			target, color = tree, HARD_COLOR
		else
			target = nearest(hrp, axe)
		end
	end
	if target then
		hl.Adornee = target
		hl.OutlineColor = color
		hl.Enabled = true
	else
		hl.Enabled = false
		hl.Adornee = nil
	end
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

local function track(tag: string)
	local function add(inst: Instance)
		if inst:IsA("Model") then
			targets[inst] = true
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
		if inst:IsA("Model") then
			targets[inst] = nil
		end
	end)
end

function ChopController.Start()
	for _, tag in ipairs(TARGET_TAGS) do
		track(tag)
	end

	local hl = Instance.new("Highlight")
	hl.Name = "ChopTarget"
	hl.FillTransparency = 1
	hl.OutlineTransparency = 0.25
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Enabled = false
	hl.Parent = workspace.CurrentCamera
	highlight = hl
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hl.Parent = workspace.CurrentCamera
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.UserInputType == Enum.UserInputType.Touch then
			lastTap = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	local sinceAim = 0
	RunService.Heartbeat:Connect(function(dt: number)
		-- Hold-to-chop: keep swinging every cooldown while the button is down
		-- (each swing turns you to its tree again).
		local now = os.clock()
		if holding and now >= cooldownUntil and now >= retryAt then
			trySwing(false)
		end
		sinceAim += dt
		if sinceAim >= AIM_INTERVAL then
			sinceAim = 0
			updateOutline()
		end
	end)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

return ChopController
