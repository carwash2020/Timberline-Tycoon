--!strict
-- DragController: grab and drag loose wood in the v2 core loop (V2_PLAN.md
-- §4a), on every device. Under the v1 loop it does nothing at all: Start
-- returns before it binds or builds anything.
--
-- Grabbing needs empty hands: with an axe out a click swings it, and
-- clicking a piece says "Put your axe away" (GrabLogic.AxeHint) instead.
--   * Mouse: hold the left button on a piece (anything tagged Wood) within
--     GrabRange; let go to drop it. The scroll wheel pushes it away or
--     pulls it in; Q/E or Shift+A/D turn it, Shift+W/S tip it, 15 degrees a
--     press (GrabLogic.KeyAction). Shift and WASD-with-Shift are ours while
--     holding (no walking, no shift lock), plain WASD still walks.
--   * Touch: rest a finger on a piece for GrabLogic.TouchHoldSec without
--     moving it; that finger is taken from the camera (a
--     ContextActionService action under the thumbstick's, and never in the
--     thumbstick's corner). Move it to drag; lift it to drop. While holding,
--     a row of buttons (- + Turn Tip) works with another finger.
--   * Gamepad: hold R2 to grab what the centre dot points at; let go to
--     drop. While holding: RB/LB (or D-pad up/down) push and pull, D-pad
--     left/right turn, and hold L2 to hang the piece in the air and turn it
--     with the LEFT (movement) stick (left/right spins it, up/down tips it)
--     without letting go of R2; the right stick keeps the camera. While L2
--     is down the left stick does not walk you (it is sunk, and the
--     humanoid is held still), and the lock lets go the instant L2 is up,
--     the piece is dropped, a menu opens or the window loses focus
--     (GrabLogic.LockStays). These are bound over HUD's D-pad shortcuts
--     only while holding.
-- On a grab the client fires Grab(part, hitPos) and at once adds, on that
-- part, an Attachment at the hit point, an AlignPosition pulling it
-- (force GrabLogic.Force(mass), Responsiveness DragResponsiveness,
-- MaxVelocity DragMaxSpeed, not at the centre of mass, so a piece swings
-- from your grip) and an AlignOrientation holding the grab-time
-- orientation turned by your presses. They act once the server hands this
-- device the piece's physics. If HeldBy isn't you within
-- GrabLogic.ConfirmSec (the server said no, with a toast), or it stops
-- being you (the server let go), the hold ends.
--
-- Each frame while holding (BindToRenderStep, after the camera): the
-- target is the pointer's camera ray at the hold distance (HoldMin to
-- HoldMax from your head, GrabLogic.Target), pulled back in front of
-- anything solid between your head and it (the one raycast a frame). It
-- lets go past ReleaseDistance, on death, sitting or taking out a tool
-- (GrabLogic.ReleaseReason), and tells the server (Release).
--
-- Everyone's grip shows as a small blue Neon ball: yours where you hold
-- it, others' from the HeldBy and GrabPoint attributes. World prompts are
-- off while you hold something (E turns it).

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BedGhost = require(ReplicatedStorage.Shared.BedGhost)
local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GrabLogic = require(ReplicatedStorage.Shared.GrabLogic)
local Net = require(ReplicatedStorage.Shared.Net)
local Tune = require(ReplicatedStorage.Shared.Tune)
local BlueprintPlacer = require(script.Parent.BlueprintPlacer)
local HUD = require(script.Parent.HUD)
local UITheme = require(script.Parent.UITheme)

local DragController = {}

local player = Players.LocalPlayer

local WOOD_TAG = "Wood"
local SHOP_TAG = "ShopBox"
local BALL_COLOR = Color3.fromRGB(70, 160, 255)
local BALL_SIZE = 0.45
local RENDER_STEP = "DragControllerHold"
local HOLD_PRIORITY = Enum.ContextActionPriority.High.Value + 1 -- over HUD's D-pad shortcuts
local TOUCH_PRIORITY = Enum.ContextActionPriority.Low.Value -- under the touch thumbstick's own action
local HINT_EVERY = 6 -- seconds between "put your axe away" hints
local POLL = 0.2 -- seconds between the reticle's checks
local HEAL_AFTER = 1 -- a piece the server still says we hold, after we let go: tell it again
local BOOT_WAIT = 120 -- seconds to wait for the server to say which loop runs
local BUTTON_SIZE = Vector2.new(60, UITheme.Size.Tap)

type Device = "mouse" | "touch" | "pad"

type Hold = {
	model: Model,
	part: BasePart,
	grip: Attachment,
	pull: AlignPosition,
	turn: AlignOrientation,
	rot: CFrame, -- the orientation it's held at
	distance: number, -- from your head, studs
	device: Device,
	touch: InputObject?, -- the finger holding it
	confirmed: boolean, -- the server said it's ours (HeldBy)
	box: boolean, -- a shop box: held at its centre of mass, upright, with a torque sized to it
	radius: number, -- studs, centre to far corner of the whole piece
	mass: number, -- what the pull is sized by (GrabLogic.PullMass); re-read when the piece's assembly changes
	assemblyMass: number, -- part.AssemblyMass when the pull was last sized
	conn: RBXScriptConnection?, -- HeldBy changes
}

type Pending = { input: InputObject, at: number, pos: Vector2 }

local hold: Hold? = nil
local pending: Pending? = nil -- a finger resting on a piece, not yet holding it
local distanceAxis = 0 -- +1 pushing out, -1 pulling in (D-pad, bumpers, the +/- buttons)
local locked = false -- the gamepad's left trigger is down: the piece hangs where it is and the left stick turns it
local lockPad: Enum.UserInputType? = nil -- the gamepad whose trigger started the lock
local focusConn: RBXScriptConnection? = nil -- the window losing focus lets go of the lock
local stick = Vector2.zero -- the left stick, read while locked
local tookKey: { [Enum.KeyCode]: boolean } = {} -- key presses whose Begin we used
local lastHint = -math.huge
local promptsWere: boolean? = nil -- ProximityPromptService.Enabled before the hold
local balls: { [Model]: BasePart } = {}
local watched: { [Model]: RBXScriptConnection } = {}
local ballFolder: Folder? = nil
local buttonRow: Frame? = nil
local reticle: Frame? = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true -- leaves and decor never catch the ray

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function tune(key: string): number
	return Tune.Get(key) :: number
end

-- Your character, root part and humanoid while alive, else nils.
local function character(): (Model?, BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hrp:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return char, hrp :: BasePart, humanoid
end

-- Where holding is measured from: your head.
local function anchorOf(char: Model, hrp: BasePart): Vector3
	local head = char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return hrp.Position + Vector3.new(0, 1.5, 0)
end

local function toolOut(char: Model): boolean
	return char:FindFirstChildOfClass("Tool") ~= nil
end

-- The loose piece (a Model tagged Wood) `inst` is part of.
local function pieceOf(inst: Instance): Model?
	local node: Instance? = inst
	for _ = 1, 5 do
		if node == nil or node == workspace then
			return nil
		end
		if
			node:IsA("Model") and (CollectionService:HasTag(node, WOOD_TAG) or CollectionService:HasTag(node, SHOP_TAG))
		then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Every character but yours is skipped by the hold's ray too (held wood
-- passes through players).
local function characters(): { Instance }
	local list: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

-- The ray the device points along: the mouse, the finger, or the screen's
-- centre on a gamepad.
local function rayFor(device: Device, touch: InputObject?): Ray?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	if device == "touch" then
		if not touch then
			return nil
		end
		return camera:ScreenPointToRay(touch.Position.X, touch.Position.Y)
	elseif device == "pad" then
		local size = camera.ViewportSize
		return camera:ViewportPointToRay(size.X / 2, size.Y / 2)
	end
	local m = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(m.X, m.Y)
end

-- What `ray` points at: a piece (or nil), and when it's within GrabRange,
-- the part and the point hit.
local function pick(ray: Ray, char: Model, hrp: BasePart): (Model?, BasePart?, Vector3?)
	rayParams.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(ray.Origin, ray.Direction.Unit * 250, rayParams)
	if not hit or not hit.Instance:IsA("BasePart") then
		return nil, nil, nil
	end
	local model = pieceOf(hit.Instance)
	if not model then
		return nil, nil, nil
	end
	if (hit.Position - hrp.Position).Magnitude > tune("GrabRange") then
		return model, nil, nil
	end
	return model, hit.Instance :: BasePart, hit.Position
end

local function hint()
	local now = os.clock()
	if now - lastHint < HINT_EVERY then
		return
	end
	lastHint = now
	-- Once per session: the hint line at the bottom says it again.
	HUD.Toast(GrabLogic.AxeHint(UITheme.Device()), nil, { key = "axeHint", once = true })
end

---------------------------------------------------------------------------
-- Balls: everyone's grip
---------------------------------------------------------------------------

local function newBall(): BasePart
	local ball = Instance.new("Part")
	ball.Name = "GrabBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(BALL_SIZE, BALL_SIZE, BALL_SIZE)
	ball.Material = Enum.Material.Neon
	ball.Color = BALL_COLOR
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Parent = ballFolder
	return ball
end

-- Shows or hides `model`'s ball: while anyone holds it, or you're
-- grabbing it (before the server has said so).
local function refreshBall(model: Model)
	local heldBy = model:GetAttribute("HeldBy")
	local mine = hold ~= nil and hold.model == model
	local held = mine or (type(heldBy) == "number" and heldBy ~= 0)
	local ball = balls[model]
	if held and not ball then
		balls[model] = newBall()
	elseif not held and ball then
		ball:Destroy()
		balls[model] = nil
	end
	-- The server still says it's ours after we let go (a Release lost
	-- to the rate limit): say so again, once it has had time to hear.
	if heldBy == player.UserId and not mine then
		task.delay(HEAL_AFTER, function()
			local h = hold
			local root = model.PrimaryPart
			if
				model.Parent
				and root
				and model:GetAttribute("HeldBy") == player.UserId
				and not (h and h.model == model)
			then
				Net.Remote("Release"):FireServer(root)
			end
		end)
	end
end

local function placeBalls()
	for model, ball in pairs(balls) do
		local h = hold
		local at: Vector3? = nil
		if h and h.model == model then
			at = h.grip.WorldPosition
		else
			local point = model:GetAttribute("GrabPoint")
			local root = model.PrimaryPart
			if typeof(point) == "Vector3" and root then
				at = root.CFrame:PointToWorldSpace(point)
			end
		end
		ball.Transparency = if at then 0 else 1
		if at then
			ball.CFrame = CFrame.new(at)
		end
	end
end

local function watchPiece(inst: Instance)
	if not inst:IsA("Model") or watched[inst] then
		return
	end
	local model = inst :: Model
	watched[model] = model:GetAttributeChangedSignal("HeldBy"):Connect(function()
		refreshBall(model)
	end)
	refreshBall(model)
end

local function unwatchPiece(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local model = inst :: Model
	local conn = watched[model]
	if conn then
		conn:Disconnect()
		watched[model] = nil
	end
	local ball = balls[model]
	if ball then
		ball:Destroy()
		balls[model] = nil
	end
end

---------------------------------------------------------------------------
-- Touch buttons and the gamepad's dot
---------------------------------------------------------------------------

local function showButtons(show: boolean)
	local row = buttonRow
	if row then
		local on = show and not HUD.BuildOpen()
		if on then
			-- Above the hint line, wherever Roblox's hotbar is now.
			row.Position = UDim2.new(0.5, 0, 1, -(UITheme.Bottom() + 38))
		end
		row.Visible = on
	end
end

-- PlotUI: while build mode is open the drag row stays hidden.
function DragController.SetBuildMode(on: boolean)
	if on then
		local row = buttonRow
		if row then
			row.Visible = false
		end
		return
	end
	local h = hold
	if h and h.device == "touch" then
		showButtons(true)
	end
end

local function hidePrompts(hide: boolean)
	if hide then
		if promptsWere == nil then
			promptsWere = ProximityPromptService.Enabled
		end
		ProximityPromptService.Enabled = false
	elseif promptsWere ~= nil then
		ProximityPromptService.Enabled = promptsWere
		promptsWere = nil
	end
end

local function turnBy(turn: GrabLogic.Turn)
	local h = hold
	local camera = workspace.CurrentCamera
	if h and camera then
		h.rot = GrabLogic.Turn(h.rot, turn, camera.CFrame.LookVector)
	end
end

local function nudge(delta: number)
	local h = hold
	if h then
		h.distance = GrabLogic.StepHold(h.distance, delta, tune("HoldMin"), tune("HoldMax"))
	end
end

local function buildButtons()
	local gui = UITheme.Screen("DragControls", UITheme.Layers.Drag)
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -(UITheme.Bottom() + 38))
	row.Size = UDim2.new()
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.BackgroundTransparency = 1
	row.Visible = false
	UITheme.list(row, 8, true)
	row.Parent = gui
	local function pressed(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
	end
	-- - and +: held, they keep pulling or pushing (a tap moves half a stud).
	for i, dir in ipairs({ -1, 1 }) do
		local b = UITheme.Button({
			text = if dir < 0 then "−" else "+",
			size = BUTTON_SIZE,
			style = "bark",
			font = UITheme.Fonts.Heading,
			textSize = 24,
			name = if dir < 0 then "Nearer" else "Further",
		})
		b.root.LayoutOrder = i
		b.face.InputBegan:Connect(function(input: InputObject)
			if pressed(input) then
				distanceAxis = dir
				nudge(dir * 0.5)
			end
		end)
		b.face.InputEnded:Connect(function(input: InputObject)
			if pressed(input) and distanceAxis == dir then
				distanceAxis = 0
			end
		end)
		b.root.Parent = row
	end
	for i, kind in ipairs({ "yaw", "pitch" }) do
		local b = UITheme.Button({
			text = if kind == "yaw" then "Turn" else "Tip",
			size = BUTTON_SIZE,
			style = "bark",
			textSize = UITheme.Size.TextButton,
			name = if kind == "yaw" then "Turn" else "Tip",
		})
		b.root.LayoutOrder = 2 + i
		b.face.Activated:Connect(function()
			turnBy({ kind = kind :: any, steps = GrabLogic.TouchTurnSteps })
		end)
		b.root.Parent = row
	end
	gui.Parent = UITheme.PlayerGui()
	buttonRow = row
end

local function buildReticle()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DragReticle"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- the true centre, where the gamepad's ray goes
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 0
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(8, 8)
	dot.BackgroundColor3 = UITheme.Colors.Cream
	dot.Visible = false
	UITheme.corner(dot, 4)
	UITheme.stroke(dot, UITheme.Colors.Ink, 1.5)
	dot.Parent = gui
	gui.Parent = UITheme.PlayerGui()
	reticle = dot
end

-- The dot shows on a gamepad when your hands are free to grab.
local function refreshReticle()
	local dot = reticle
	if not dot then
		return
	end
	local char, _hrp, humanoid = character()
	dot.Visible = UITheme.Device() == "console"
		and char ~= nil
		and humanoid ~= nil
		and humanoid.SeatPart == nil
		and not toolOut(char)
end

---------------------------------------------------------------------------
-- Holding
---------------------------------------------------------------------------

local onKey: (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
local onWheel: (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
local onPad: (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
local onLock: (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
local onStick: (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
local step: (number) -> ()

local function bindHold()
	ContextActionService:BindActionAtPriority(
		"DragKeys",
		onKey,
		false,
		HOLD_PRIORITY,
		Enum.KeyCode.Q,
		Enum.KeyCode.E,
		Enum.KeyCode.W,
		Enum.KeyCode.A,
		Enum.KeyCode.S,
		Enum.KeyCode.D,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.RightShift
	)
	ContextActionService:BindActionAtPriority("DragWheel", onWheel, false, HOLD_PRIORITY, Enum.UserInputType.MouseWheel)
	ContextActionService:BindActionAtPriority(
		"DragPad",
		onPad,
		false,
		HOLD_PRIORITY,
		Enum.KeyCode.DPadUp,
		Enum.KeyCode.DPadDown,
		Enum.KeyCode.DPadLeft,
		Enum.KeyCode.DPadRight,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1
	)
	-- LT hangs the piece in the air; the LEFT stick then turns it and no
	-- longer walks you (sunk while locked), and the right stick stays the
	-- camera's. Not locked, the left stick passes on and walks as always.
	ContextActionService:BindActionAtPriority("DragLock", onLock, false, HOLD_PRIORITY, Enum.KeyCode.ButtonL2)
	ContextActionService:BindActionAtPriority("DragStick", onStick, false, HOLD_PRIORITY, Enum.KeyCode.Thumbstick1)
	RunService:BindToRenderStep(RENDER_STEP, Enum.RenderPriority.Camera.Value + 1, step)
	-- A window that loses focus never reports the trigger going up.
	if focusConn == nil then
		focusConn = UserInputService.WindowFocusReleased:Connect(function()
			locked = false
			lockPad = nil
			stick = Vector2.zero
		end)
	end
end

local function unbindHold()
	ContextActionService:UnbindAction("DragKeys")
	ContextActionService:UnbindAction("DragWheel")
	ContextActionService:UnbindAction("DragPad")
	ContextActionService:UnbindAction("DragLock")
	ContextActionService:UnbindAction("DragStick")
	RunService:UnbindFromRenderStep(RENDER_STEP)
	table.clear(tookKey)
	locked = false
	lockPad = nil
	stick = Vector2.zero
	local conn = focusConn
	if conn then
		conn:Disconnect()
		focusConn = nil
	end
end

-- Ends the hold: the constraints go, and (`tell`) the server hears.
---------------------------------------------------------------------------
-- Truck beds while you hold a piece
---------------------------------------------------------------------------

-- The sides of nearby truck beds, as they were (collision, local see-through),
-- put back when you let go. Your client only: the held piece is yours to
-- simulate, so it passes through the sides here and nowhere else.
local ghosted: { [BasePart]: boolean } = {}

local function ghostBeds(on: boolean)
	if not on then
		for part, wasCollide in pairs(ghosted) do
			if part.Parent then
				part.CanCollide = wasCollide
				part.LocalTransparencyModifier = 0
			end
		end
		table.clear(ghosted)
		return
	end
	local _char, hrp = character()
	if not hrp then
		return
	end
	for _, truck in ipairs(CollectionService:GetTagged("Truck")) do
		local root = if truck:IsA("Model") then truck.PrimaryPart else nil
		if root and BedGhost.Near((root.Position - hrp.Position).Magnitude) then
			for _, d in ipairs(truck:GetDescendants()) do
				if d:IsA("BasePart") and BedGhost.IsSide(d.Name) and ghosted[d] == nil then
					ghosted[d] = d.CanCollide
					d.CanCollide = false
					d.LocalTransparencyModifier = BedGhost.Transparency
				end
			end
		end
	end
end

local function drop(tell: boolean)
	local h = hold
	if not h then
		return
	end
	hold = nil
	distanceAxis = 0
	ghostBeds(false)
	unbindHold()
	showButtons(false)
	hidePrompts(false)
	if h.conn then
		h.conn:Disconnect()
	end
	h.pull:Destroy()
	h.turn:Destroy()
	h.grip:Destroy()
	if tell then
		Net.Remote("Release"):FireServer(h.part)
	end
	refreshBall(h.model)
end

-- What the pull is sized by: the larger of the assembly's mass and the sum of
-- the piece's parts (an anchored shelf box reports an assembly mass of 0).
local function massOf(model: Model, part: BasePart): number
	local masses: { number } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(masses, d:GetMass())
		end
	end
	return GrabLogic.PullMass(part.AssemblyMass, masses)
end

-- Sizes the pull and the turn to `h.mass`.
local function sizePull(h: Hold)
	local force = GrabLogic.HoldForce(h.mass, h.box, tune("DragForcePerMass"), tune("DragForceCap"))
	h.pull.MaxForce = force
	h.turn.MaxTorque = GrabLogic.HoldTorque(force, h.box, h.radius)
end

-- Starts holding what `device` points at (see the header).
local function grab(device: Device, touch: InputObject?)
	if hold then
		return
	end
	local char, hrp, humanoid = character()
	if not char or not hrp or not humanoid or humanoid.SeatPart ~= nil then
		return
	end
	local ray = rayFor(device, touch)
	if not ray then
		return
	end
	local model, part, at = pick(ray, char, hrp)
	if not model then
		return
	end
	if toolOut(char) then
		hint() -- the press swings the axe
		return
	end
	if not part or not at then
		HUD.Toast(GrabLogic.Message("far") :: string)
		return
	end
	local heldBy = model:GetAttribute("HeldBy")
	if type(heldBy) == "number" and heldBy ~= 0 and heldBy ~= player.UserId then
		HUD.Toast(GrabLogic.Message("held") :: string)
		return
	end
	local mass = massOf(model, part)
	local isBox = CollectionService:HasTag(model, SHOP_TAG)
	local radius = model:GetExtentsSize().Magnitude / 2
	local force = GrabLogic.HoldForce(mass, isBox, tune("DragForcePerMass"), tune("DragForceCap"))
	-- A box is held upright at the yaw it stands at (see GrabLogic.HoldForce).
	local startRot = if isBox then GrabLogic.Upright(part.CFrame) else part.CFrame.Rotation
	local grip = Instance.new("Attachment")
	grip.Name = "DragGrip"
	grip.CFrame = CFrame.new(part.CFrame:PointToObjectSpace(at))
	grip.Parent = part
	local pull = Instance.new("AlignPosition")
	pull.Name = "DragPull"
	pull.Mode = Enum.PositionAlignmentMode.OneAttachment
	pull.Attachment0 = grip
	pull.ApplyAtCenterOfMass = GrabLogic.PullsAtCentre(isBox) -- wood swings from your grip; a box hangs from its centre
	pull.RigidityEnabled = false
	pull.MaxForce = force
	pull.MaxVelocity = tune("DragMaxSpeed")
	pull.Responsiveness = tune("DragResponsiveness")
	pull.Position = at
	pull.Parent = part
	local turn = Instance.new("AlignOrientation")
	turn.Name = "DragTurn"
	turn.Mode = Enum.OrientationAlignmentMode.OneAttachment
	turn.Attachment0 = grip
	turn.RigidityEnabled = false
	turn.MaxTorque = GrabLogic.HoldTorque(force, isBox, radius)
	turn.MaxAngularVelocity = GrabLogic.MaxSpin
	turn.Responsiveness = tune("DragResponsiveness")
	turn.CFrame = startRot
	turn.Parent = part
	local h: Hold = {
		model = model,
		part = part,
		grip = grip,
		pull = pull,
		turn = turn,
		rot = startRot,
		box = isBox,
		radius = radius,
		distance = GrabLogic.StartHold(at, anchorOf(char, hrp), tune("HoldMin"), tune("HoldMax")),
		device = device,
		touch = touch,
		confirmed = false,
		mass = mass,
		assemblyMass = part.AssemblyMass,
		conn = nil,
	}
	hold = h
	distanceAxis = 0
	HUD.NoteGrab()
	ghostBeds(true)
	Net.Remote("Grab"):FireServer(part, at)
	h.conn = model:GetAttributeChangedSignal("HeldBy"):Connect(function()
		if hold ~= h then
			return
		end
		if model:GetAttribute("HeldBy") == player.UserId then
			h.confirmed = true
			if h.box then
				-- Whatever spin the shelf release left on it is damped at once.
				pcall(function()
					h.part.AssemblyAngularVelocity = Vector3.zero
				end)
			end
		elseif h.confirmed then
			drop(false) -- the server let go (sold, cut, too far, put back)
		end
	end)
	bindHold()
	showButtons(device == "touch")
	hidePrompts(true)
	refreshBall(model)
	task.delay(GrabLogic.ConfirmSec(player:GetNetworkPing()), function()
		if hold == h and not h.confirmed then
			if model:GetAttribute("HeldBy") == player.UserId then
				h.confirmed = true
			else
				drop(false) -- refused: the server's toast says why
			end
		end
	end)
end

step = function(dt: number)
	local h = hold
	if not h then
		return
	end
	local char, hrp, humanoid = character()
	if not char or not hrp or not humanoid or not h.model.Parent or not h.part:IsDescendantOf(h.model) then
		drop(true)
		return
	end
	if distanceAxis ~= 0 then
		nudge(distanceAxis * GrabLogic.DistanceSpeed * dt)
	end
	-- The server freeing a shelf box (it was anchored) changes its assembly:
	-- size the pull again, so the first grab moves it.
	local assembly = h.part.AssemblyMass
	if assembly ~= h.assemblyMass then
		h.assemblyMass = assembly
		h.mass = massOf(h.model, h.part)
		sizePull(h)
	end
	if locked then
		-- The lock lets go the moment its reasons are gone: LT up (polled, in
		-- case the release was never reported), a menu open, typing.
		local pad = lockPad
		local stays = GrabLogic.LockStays({
			holding = true,
			triggerDown = pad ~= nil and UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.ButtonL2),
			alive = humanoid.Health > 0,
			seated = humanoid.SeatPart ~= nil,
			toolOut = toolOut(char),
			panelOpen = GuiService.SelectedObject ~= nil,
			typing = UserInputService:GetFocusedTextBox() ~= nil,
			focused = nil,
		})
		if not stays then
			locked = false
			lockPad = nil
			stick = Vector2.zero
		end
	end
	if locked then
		-- Hanging in the air: the target stays where it was, the left stick
		-- turns it. It does not also walk you: Thumbstick1 is sunk, and the
		-- humanoid is held still here, after the controls' own Move.
		if not GrabLogic.StickWalks(locked) then
			humanoid:Move(Vector3.zero, false)
		end
		local camera = workspace.CurrentCamera
		if camera then
			local yaw, pitch = GrabLogic.StickTurn(stick.X, stick.Y, dt)
			if yaw ~= 0 or pitch ~= 0 then
				h.rot = GrabLogic.Rotate(h.rot, yaw, pitch, camera.CFrame.LookVector)
			end
		end
	end
	local ray = if locked then nil else rayFor(h.device, h.touch)
	if ray then
		local anchor = anchorOf(char, hrp)
		local target = GrabLogic.Target(ray.Origin, ray.Direction, anchor, h.distance)
		-- Never pulled into the ground or through a wall: in front of
		-- whatever is between your head and the target.
		local ignore = characters()
		table.insert(ignore, h.model)
		rayParams.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(anchor, target - anchor, rayParams)
		if hit then
			target = hit.Position + hit.Normal * 0.5
		end
		h.pull.Position = target
	end
	h.turn.CFrame = h.rot
	local reason = GrabLogic.ReleaseReason({
		distance = (h.grip.WorldPosition - hrp.Position).Magnitude,
		alive = true,
		seated = humanoid.SeatPart ~= nil,
		toolOut = toolOut(char),
	}, tune("ReleaseDistance"))
	if reason then
		drop(true)
	end
end

onKey = function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	local key = input.KeyCode
	if state == Enum.UserInputState.Begin then
		if not hold or UserInputService:GetFocusedTextBox() ~= nil then
			return Enum.ContextActionResult.Pass
		end
		if key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.RightShift then
			tookKey[key] = true -- the rotate modifier now, not shift lock
			return Enum.ContextActionResult.Sink
		end
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		local turn = GrabLogic.KeyAction(key.Name, shift)
		if turn then
			tookKey[key] = true
			turnBy(turn)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end
	if tookKey[key] then
		if state ~= Enum.UserInputState.Change then
			tookKey[key] = nil
		end
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

onWheel = function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if not hold then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Change and input.Position.Z ~= 0 then
		nudge(if input.Position.Z > 0 then GrabLogic.WheelStep else -GrabLogic.WheelStep)
	end
	return Enum.ContextActionResult.Sink -- the camera doesn't zoom while you hold something
end

onPad = function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if not hold then
		return Enum.ContextActionResult.Pass
	end
	local turn, axis = GrabLogic.PadAction(input.KeyCode.Name)
	if state == Enum.UserInputState.Begin then
		if turn then
			turnBy(turn)
		elseif axis then
			distanceAxis = axis
		end
	elseif state ~= Enum.UserInputState.Change and axis and distanceAxis == axis then
		distanceAxis = 0
	end
	return Enum.ContextActionResult.Sink
end

onLock = function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if not hold then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		locked = true
		lockPad = input.UserInputType
	elseif state ~= Enum.UserInputState.Change then
		locked = false -- LT up (or cancelled): the left stick walks again at once
		lockPad = nil
		stick = Vector2.zero
	end
	return Enum.ContextActionResult.Sink
end

onStick = function(_name: string, _state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if not hold or GrabLogic.StickWalks(locked) then
		return Enum.ContextActionResult.Pass -- not locked: it walks you, as always
	end
	stick = Vector2.new(input.Position.X, input.Position.Y)
	return Enum.ContextActionResult.Sink -- locked: it turns the piece and walks nobody
end

-- Touch: a finger that starts on a piece is ours (sunk), so the camera
-- never turns with it; anything else passes on to the camera.
local function onTouch(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		local camera = workspace.CurrentCamera
		if hold or pending or not camera then
			return Enum.ContextActionResult.Pass
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if GrabLogic.InThumbstickZone(pos, camera.ViewportSize) then
			return Enum.ContextActionResult.Pass
		end
		local char, hrp, humanoid = character()
		if not char or not hrp or not humanoid or humanoid.SeatPart ~= nil then
			return Enum.ContextActionResult.Pass
		end
		local model, part = pick(camera:ScreenPointToRay(pos.X, pos.Y), char, hrp)
		if not model then
			return Enum.ContextActionResult.Pass
		end
		if toolOut(char) then
			hint() -- the tap swings the axe
			return Enum.ContextActionResult.Pass
		end
		if not part then
			return Enum.ContextActionResult.Pass -- too far: the camera may have it
		end
		pending = { input = input, at = os.clock(), pos = pos }
		return Enum.ContextActionResult.Sink
	end
	local p = pending
	if p and p.input == input then
		if state ~= Enum.UserInputState.Change then
			pending = nil -- lifted before it grabbed: a tap
		end
		return Enum.ContextActionResult.Sink
	end
	local h = hold
	if h and h.touch == input then
		if state ~= Enum.UserInputState.Change then
			drop(true)
		end
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

-- A resting finger grabs once it has rested long enough (GrabLogic.TouchHold).
local function checkPending()
	local p = pending
	if not p then
		return
	end
	local pos = Vector2.new(p.input.Position.X, p.input.Position.Y)
	local verdict = GrabLogic.TouchHold(p.at, p.pos, os.clock(), pos)
	if verdict == "grab" then
		pending = nil
		grab("touch", p.input)
	elseif verdict == "cancel" then
		pending = nil
	end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

function DragController.Start()
	-- MapBuilder says which loop runs before it builds anything.
	local waited = 0
	while workspace:GetAttribute(CoreLoop.ActiveAttribute) == nil and waited < BOOT_WAIT do
		waited += task.wait(0.25)
	end
	if not CoreLoop.V2() then
		return -- the v1 loop: nothing here runs
	end

	local folder = Instance.new("Folder")
	folder.Name = "GrabBalls"
	folder.Parent = workspace
	ballFolder = folder
	buildButtons()
	buildReticle()

	local function watchTag(tag: string)
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			watchPiece(inst)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(watchPiece)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(unwatchPiece)
	end
	watchTag(WOOD_TAG)
	watchTag(SHOP_TAG)

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		-- RT is no button's click: a bound action (the builder's select) marks
		-- it handled even when it passes it on. Only a menu with the pad
		-- selection keeps it.
		local trigger = input.KeyCode == Enum.KeyCode.ButtonR2
		if
			not GrabLogic.PadPressAccepted(
				processed,
				trigger,
				GuiService.SelectedObject ~= nil,
				BlueprintPlacer.Active()
			)
		then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			grab("mouse", nil)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			grab("pad", nil)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local h = hold
		if not h then
			return
		end
		if
			(input.UserInputType == Enum.UserInputType.MouseButton1 and h.device == "mouse")
			or (input.KeyCode == Enum.KeyCode.ButtonR2 and h.device == "pad")
		then
			drop(true)
		end
	end)
	ContextActionService:BindActionAtPriority("DragTouch", onTouch, false, TOUCH_PRIORITY, Enum.UserInputType.Touch)

	player.CharacterAdded:Connect(function()
		drop(false)
		pending = nil
	end)

	RunService.RenderStepped:Connect(placeBalls)
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		checkPending()
		since += dt
		if since >= POLL then
			since = 0
			refreshReticle()
		end
	end)
end

return DragController
