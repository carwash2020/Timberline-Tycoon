--!strict
-- CarryPose: anyone carrying logs holds them up on their forearms (ACT-01).
-- For every player with CarriedLogs > 0 within CarryLayout.Range of you
-- (you included), this sets their arm joints' Motor6D.Transform to the
-- carry pose every frame: both arms raised forward, R15 elbows bent a
-- little. Shared/CarryLayout has the maths (R15 and R6 joints turn about
-- different axes) and where the server welds the logs.
--
-- Why PreSimulation: each frame runs PreAnimation, then the Animator steps
-- (writing every animated joint's Transform), then PreSimulation, then the
-- physics step, which places the parts from their joints. A Transform set
-- on PreSimulation is the last word for that frame; one set on
-- PreAnimation, PreRender or Heartbeat is overwritten by the Animator
-- before it's used. So the write happens again every frame, and stops
-- (the joints back to identity, the Animator's again) as soon as a player
-- isn't carrying, is sitting (driving), dies, or is out of range.
--
-- Transform doesn't replicate, so every client poses everyone it can see
-- itself, from the CarriedLogs attribute the server publishes. Characters
-- stream in and out, so their joints are looked up again every REFRESH
-- seconds, and a missing arm is simply not posed. An avatar with
-- AnimationConstraints in place of Motor6Ds (Roblox's avatar joint
-- upgrade) has a constraint found under the joint's name posed the same
-- way, through its Transform (relative to its Attachment0, as C0 is);
-- anything else is left alone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarryLayout = require(ReplicatedStorage.Shared.CarryLayout)

local CarryPose = {}

local REFRESH = 0.25 -- seconds between re-checks of who to pose and their joints

-- One arm joint and the Transform it holds: a Motor6D, or an
-- AnimationConstraint on an upgraded avatar.
type Posed = { motor: Motor6D?, constraint: AnimationConstraint?, transform: CFrame }

type Record = {
	conns: { RBXScriptConnection },
	posed: { Posed }, -- written every frame; empty while not posing
	humanoid: Humanoid?,
}

local records: { [Player]: Record } = {}
local localPlayer = Players.LocalPlayer

local function write(p: Posed, cf: CFrame)
	local motor, constraint = p.motor, p.constraint
	if motor then
		motor.Transform = cf
	elseif constraint then
		constraint.Transform = cf
	end
end

local function sameJoint(a: Posed, b: Posed): boolean
	return a.motor == b.motor and a.constraint == b.constraint
end

-- Hands the arms back to the Animator.
local function restore(rec: Record)
	for _, p in ipairs(rec.posed) do
		write(p, CFrame.identity)
	end
	table.clear(rec.posed)
	rec.humanoid = nil
end

-- The arm joints of `character` that are there right now, each with the
-- Transform that holds it in the carry pose.
local function armJoints(character: Model, humanoid: Humanoid): { Posed }
	local out: { Posed } = {}
	local joints = if humanoid.RigType == Enum.HumanoidRigType.R15 then CarryLayout.R15 else CarryLayout.R6
	for _, spec in ipairs(joints) do
		local part = character:FindFirstChild(spec.part)
		local joint = if part then part:FindFirstChild(spec.joint) else nil
		if joint and joint:IsA("Motor6D") then
			table.insert(out, { motor = joint, transform = CarryLayout.JointTransform(joint.C0, spec.turn) })
		elseif joint and joint:IsA("AnimationConstraint") then
			local a0 = joint.Attachment0
			if a0 then
				table.insert(out, { constraint = joint, transform = CarryLayout.JointTransform(a0.CFrame, spec.turn) })
			end
		end
	end
	return out
end

-- Where "in range" is measured from: your character, else the camera.
local function viewerPosition(): Vector3?
	local char = localPlayer.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

-- Starts, keeps or stops posing `player`.
local function evaluate(player: Player, rec: Record, viewer: Vector3?)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local distance = if root and root:IsA("BasePart") and viewer then (root.Position - viewer).Magnitude else nil
	if
		not character
		or not humanoid
		or not CarryLayout.ShouldPose(
			player:GetAttribute("CarriedLogs"),
			humanoid.Health > 0,
			humanoid.Sit or humanoid.SeatPart ~= nil,
			distance
		)
	then
		restore(rec)
		return
	end
	local joints = armJoints(character, humanoid)
	-- A joint that's gone (streamed out, or the rig rebuilt) goes back first.
	for _, old in ipairs(rec.posed) do
		local kept = false
		for _, new in ipairs(joints) do
			if sameJoint(old, new) then
				kept = true
				break
			end
		end
		if not kept then
			write(old, CFrame.identity)
		end
	end
	rec.posed = joints
	rec.humanoid = humanoid
end

local elapsed = REFRESH -- the first frame checks everyone

local function step(dt: number)
	elapsed += dt
	if elapsed >= REFRESH then
		elapsed = 0
		local viewer = viewerPosition()
		for player, rec in pairs(records) do
			evaluate(player, rec, viewer)
		end
	end
	for _, rec in pairs(records) do
		if #rec.posed == 0 then
			continue
		end
		-- Sitting down or dying between checks lets go at once.
		local humanoid = rec.humanoid
		if not humanoid or humanoid.Sit or humanoid.SeatPart ~= nil or humanoid.Health <= 0 then
			restore(rec)
			continue
		end
		for _, p in ipairs(rec.posed) do
			write(p, p.transform)
		end
	end
end

local function track(player: Player)
	if records[player] then
		return
	end
	local rec: Record = { conns = {}, posed = {}, humanoid = nil }
	records[player] = rec
	-- Loading, selling or dropping lowers the arms on the spot.
	table.insert(
		rec.conns,
		player:GetAttributeChangedSignal("CarriedLogs"):Connect(function()
			evaluate(player, rec, viewerPosition())
		end)
	)
	table.insert(
		rec.conns,
		player.CharacterRemoving:Connect(function()
			restore(rec)
		end)
	)
end

local function untrack(player: Player)
	local rec = records[player]
	if not rec then
		return
	end
	records[player] = nil
	for _, conn in ipairs(rec.conns) do
		conn:Disconnect()
	end
	table.clear(rec.conns)
	restore(rec)
end

-- PreSimulation where the engine has it, else Stepped (the same moment:
-- after the Animator, before the joints are solved).
local function everyPhysicsStep(fn: (number) -> ())
	local ok, signal = pcall(function(): RBXScriptSignal<number>
		return RunService.PreSimulation
	end)
	if ok and signal then
		signal:Connect(fn)
	else
		RunService.Stepped:Connect(function(_time: number, dt: number)
			fn(dt)
		end)
	end
end

function CarryPose.Start()
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	for _, player in ipairs(Players:GetPlayers()) do
		track(player)
	end
	everyPhysicsStep(step)
end

return CarryPose
