--!strict
-- SwingPose: the two-handed chop, on every nearby character.
--
-- Motor6D.Transform does not replicate. The swinging client poses itself
-- from os.clock (BeginLocal) so the wind-up doesn't wait on a round trip.
-- The server stamps SwingAt (server time) and SwingLen (seconds, that
-- axe's cooldown) on the character, and every other client within
-- SwingLogic.SeeRange plays the same clip, the way CarryPose reads
-- CarriedLogs. An avatar on AnimationConstraints is posed through the
-- constraint's Transform, same as a Motor6D.
--
-- This writes on PreSimulation, after the Animator. It starts before
-- CarryPose, so a log grabbed mid-swing gets the carry pose as the last
-- word: while CarriedLogs > 0 this writes nothing. In first person the
-- pose is identity, so the axe doesn't sweep through the camera. No
-- camera shake, zoom, or field-of-view change lives here.
--
-- OnImpact hooks run on the impact frame, before that frame's pose, so
-- the bite or the glance is what you see when the chop is sent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarryLayout = require(ReplicatedStorage.Shared.CarryLayout)
local SwingLogic = require(ReplicatedStorage.Shared.SwingLogic)

local SwingPose = {}

local localPlayer = Players.LocalPlayer

type Held = { motor: Motor6D?, constraint: AnimationConstraint? }

type LocalSwing = {
	id: number,
	started: number,
	len: number,
	contact: SwingLogic.Contact?,
	cancelled: boolean,
	told: boolean,
}

local localSwing: LocalSwing? = nil
local heldByPlayer: { [Player]: { Held } } = {}
local impactHooks: { (number) -> () } = {}

function SwingPose.HookImpact(fn: (number) -> ())
	table.insert(impactHooks, fn)
end

function SwingPose.BeginLocal(id: number, len: number)
	localSwing = {
		id = id,
		started = os.clock(),
		len = len,
		contact = nil,
		cancelled = false,
		told = false,
	}
end

function SwingPose.SetContact(id: number, contact: SwingLogic.Contact)
	local swing = localSwing
	if swing and swing.id == id then
		swing.contact = contact
	end
end

function SwingPose.CancelLocal(id: number)
	local swing = localSwing
	if swing and swing.id == id then
		swing.cancelled = true
	end
end

local function write(held: Held, cf: CFrame)
	local motor, constraint = held.motor, held.constraint
	if motor then
		motor.Transform = cf
	elseif constraint then
		constraint.Transform = cf
	end
end

local function restore(player: Player)
	local list = heldByPlayer[player]
	if not list then
		return
	end
	for _, held in ipairs(list) do
		write(held, CFrame.identity)
	end
	heldByPlayer[player] = nil
end

local function serverNow(): number
	local clock = workspace.GetServerTimeNow
	if type(clock) == "function" then
		local ok, now = pcall(clock, workspace)
		if ok and type(now) == "number" then
			return now
		end
	end
	return os.clock()
end

local function viewerPosition(): Vector3?
	local char = localPlayer.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

local function carrying(player: Player): boolean
	local n = player:GetAttribute("CarriedLogs")
	return type(n) == "number" and n > 0
end

-- Clip position of `player`'s current swing, or nil when they aren't swinging.
function SwingPose.ClipOf(player: Player): number?
	if player == localPlayer then
		local swing = localSwing
		if not swing or swing.cancelled then
			return nil
		end
		local elapsed = os.clock() - swing.started
		if elapsed < 0 or elapsed >= swing.len then
			return nil
		end
		return SwingLogic.ClipAt(swing.len, elapsed)
	end
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local viewer = viewerPosition()
	local distance = if root and root:IsA("BasePart") and viewer then (root.Position - viewer).Magnitude else nil
	if not SwingLogic.InView(distance) then
		return nil
	end
	local len = character:GetAttribute("SwingLen")
	local at = character:GetAttribute("SwingAt")
	if type(len) ~= "number" or len <= 0 or type(at) ~= "number" then
		return nil
	end
	local elapsed = serverNow() - at
	if elapsed < 0 or elapsed >= len then
		return nil
	end
	return SwingLogic.ClipAt(len, elapsed)
end

local function handleLen(character: Model): number
	local tool = character:FindFirstChildOfClass("Tool")
	local handle = if tool then tool:FindFirstChild("Handle") else nil
	if handle and handle:IsA("BasePart") and handle.Size.Y > 1 then
		return handle.Size.Y
	end
	return 3.5
end

local function bind(character: Model, partName: string, jointName: string): Held?
	local names = { partName }
	if jointName == "Waist" then
		table.insert(names, "LowerTorso")
		table.insert(names, "UpperTorso")
	elseif jointName == "RootJoint" then
		table.insert(names, "LowerTorso")
	end
	for _, name in ipairs(names) do
		local part = character:FindFirstChild(name)
		if part then
			local joint = part:FindFirstChild(jointName)
			if not joint and jointName == "RootJoint" then
				joint = part:FindFirstChild("Root Hip")
			end
			if joint and joint:IsA("Motor6D") then
				return { motor = joint }
			elseif joint and joint:IsA("AnimationConstraint") then
				return { constraint = joint }
			end
		end
	end
	return nil
end

local function apply(held: Held, turn: CFrame)
	local c0: CFrame? = nil
	if held.motor then
		c0 = held.motor.C0
	elseif held.constraint and held.constraint.Attachment0 then
		c0 = held.constraint.Attachment0.CFrame
	end
	if c0 then
		write(held, CarryLayout.JointTransform(c0, turn))
	end
end

-- How far the blade tip is above terrain. Tools and Wood are not the ground.
local function groundGap(origin: Vector3, character: Model): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.CollisionGroup = "Leaves"
	local ignore: { Instance } = { character }
	params.FilterDescendantsInstances = ignore
	local from = origin + Vector3.new(0, 0.05, 0)
	local remain = 4
	for _ = 1, 4 do
		local hit = workspace:Raycast(from, Vector3.new(0, -remain, 0), params)
		if not hit then
			return nil
		end
		local inst = hit.Instance
		local group = if inst:IsA("BasePart") then inst.CollisionGroup else ""
		if inst:FindFirstAncestorOfClass("Tool") or group == "Wood" or inst:IsDescendantOf(character) then
			table.insert(ignore, inst)
			params.FilterDescendantsInstances = ignore
			remain -= hit.Distance + 0.05
			if remain <= 0 then
				return nil
			end
			from = hit.Position - Vector3.new(0, 0.02, 0)
		else
			return (origin - hit.Position).Y
		end
	end
	return nil
end

-- 1 is the full rip. Lower keeps the follow-through up off a slope.
local function pitchScale(
	root: BasePart,
	rig: SwingLogic.RigName,
	len: number,
	clip: number,
	contact: SwingLogic.Contact?,
	character: Model
): number
	if clip < SwingLogic.BiteEnd or clip >= SwingLogic.FollowEnd then
		return 1
	end
	local function clear(scale: number): boolean
		local low = root.CFrame * SwingLogic.BladeLow(rig, len, clip, contact, scale)
		local gap = groundGap(low, character)
		return gap == nil or gap >= SwingLogic.GroundStop
	end
	local ok, fits = pcall(clear, 1)
	if not ok or fits then
		return 1
	end
	local lo, hi = 0, 1
	for _ = 1, 5 do
		local mid = (lo + hi) / 2
		local fine, yes = pcall(clear, mid)
		if fine and yes then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

local function keyOf(held: Held): Instance?
	return held.motor or held.constraint
end

local function pose(player: Player, character: Model, humanoid: Humanoid, clip: number, contact: SwingLogic.Contact?)
	if player == localPlayer and SwingPose.ClipOf(player) ~= nil then
		local camera = workspace.CurrentCamera
		local head = character:FindFirstChild("Head")
		if
			camera
			and head
			and head:IsA("BasePart")
			and SwingLogic.InFirstPerson(camera.CFrame.Position, head.Position)
		then
			restore(player)
			return
		end
	end
	local rig: SwingLogic.RigName = if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
	local len = handleLen(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local scale = 1
	if root and root:IsA("BasePart") then
		scale = pitchScale(root, rig, len, clip, contact, character)
	end
	local specs = SwingLogic.Joints(rig, clip, contact, scale)
	local nextHeld: { Held } = {}
	local seen: { [Instance]: boolean } = {}
	for _, spec in ipairs(specs) do
		local held = bind(character, spec.part, spec.joint)
		local key = if held then keyOf(held) else nil
		if held and key and not seen[key] then
			seen[key] = true
			apply(held, spec.turn)
			table.insert(nextHeld, held)
		end
	end
	local previous = heldByPlayer[player]
	if previous then
		for _, old in ipairs(previous) do
			local key = keyOf(old)
			if key and not seen[key] then
				write(old, CFrame.identity)
			end
		end
	end
	heldByPlayer[player] = nextHeld
end

local function tellImpact(clip: number)
	local swing = localSwing
	if not swing or swing.told or swing.cancelled then
		return
	end
	if clip + 1e-4 < SwingLogic.Impact then
		return
	end
	swing.told = true
	local id = swing.id
	for _, fn in ipairs(impactHooks) do
		fn(id)
	end
end

local function step()
	local swing = localSwing
	if swing and (swing.cancelled or os.clock() - swing.started >= swing.len) then
		localSwing = nil
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		-- Dead, or a log in hand: hands back to the Animator (CarryPose
		-- writes next when they're carrying). The chopper cancels the hit.
		if not character or not humanoid or humanoid.Health <= 0 or carrying(player) then
			restore(player)
			continue
		end
		local clip: number? = nil
		local contact: SwingLogic.Contact? = nil
		if player == localPlayer then
			clip = SwingPose.ClipOf(player)
			if clip then
				tellImpact(clip)
				contact = if localSwing then localSwing.contact else nil
			end
		else
			clip = SwingPose.ClipOf(player)
		end
		if clip then
			pose(player, character, humanoid, clip, contact)
		else
			restore(player)
		end
	end
end

local function everyPhysicsStep(fn: () -> ())
	local ok, signal = pcall(function(): RBXScriptSignal
		return RunService.PreSimulation
	end)
	if ok and signal then
		signal:Connect(fn)
	else
		RunService.Stepped:Connect(function()
			fn()
		end)
	end
end

function SwingPose.Start()
	everyPhysicsStep(step)
end

return SwingPose
