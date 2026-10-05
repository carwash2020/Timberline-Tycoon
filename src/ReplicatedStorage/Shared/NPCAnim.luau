--!strict
-- NPCAnim: poses for the blocky townsfolk (CharacterArt's Motor6D rig).
-- These figures are not R15, so the default avatar animation pack has
-- nothing to bind to. A pose is a few joint angles the client writes into
-- Motor6D.Transform once per frame, and only for NPCs near the camera.
-- Nothing here runs on the server, and there is no Humanoid or
-- AnimationController to pay for.
--
-- Angle convention (CharacterArt):
--   pitch > 0  a limb swings forward; the head tips back (looks up)
--   yaw > 0    the head turns to its left
--   roll > 0   raises the RIGHT arm out sideways (negative raises the left)

local NPCAnim = {}

export type Work = "chop" | "saw" | "sweep" | "carry"

NPCAnim.ChopLength = 1.35 -- one wind-up, strike, and recover
NPCAnim.SawLength = 2.4 -- a few strokes
NPCAnim.SweepLength = 2.6 -- one sweep across and back

-- Asleep, the limbs stay tucked. The lie itself is the root CFrame
-- (NPCData.SleepCFrame), not a big root pitch.
NPCAnim.SleepArmPitch = 0.15
NPCAnim.SleepArmRoll = 0.35
NPCAnim.SleepNeckPitch = 0.25
NPCAnim.SleepHip = 0.1

function NPCAnim.Length(work: string): number
	if work == "chop" then
		return NPCAnim.ChopLength
	elseif work == "saw" then
		return NPCAnim.SawLength
	elseif work == "sweep" then
		return NPCAnim.SweepLength
	end
	return 0
end

-- Props the walk holds in the left hand (a mug or clipboard has its own
-- idle flourish instead).
function NPCAnim.Holds(carry: string?): boolean
	return carry == "basket" or carry == "sapling" or carry == "cane"
end

export type Pose = {
	bob: number,
	rootPitch: number,
	rootYaw: number,
	neckPitch: number,
	neckYaw: number,
	neckRoll: number,
	leftPitch: number,
	leftYaw: number,
	leftRoll: number,
	rightPitch: number,
	rightYaw: number,
	rightRoll: number,
	leftHip: number,
	rightHip: number,
}

local function bare(): Pose
	return {
		bob = 0,
		rootPitch = 0,
		rootYaw = 0,
		neckPitch = 0,
		neckYaw = 0,
		neckRoll = 0,
		leftPitch = 0,
		leftYaw = 0,
		leftRoll = 0,
		rightPitch = 0,
		rightYaw = 0,
		rightRoll = 0,
		leftHip = 0,
		rightHip = 0,
	}
end

function NPCAnim.Mix(a: number, b: number, w: number): number
	return a + (b - a) * math.clamp(w, 0, 1)
end

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- One chop. `u` is 0..1 through the clip. Returns the right arm's pitch
-- and roll, and how far the torso leans.
function NPCAnim.Chop(u: number): (number, number, number)
	u = math.clamp(u, 0, 1)
	if u < 0.4 then
		local k = smooth(u / 0.4)
		return -1.7 * k, 1.05 * k, -0.12 * k
	elseif u < 0.58 then
		local k = smooth((u - 0.4) / 0.18)
		return -1.7 + 3.15 * k, 1.05 * (1 - k), -0.12 + 0.28 * k
	end
	local k = smooth((u - 0.58) / 0.42)
	return 1.45 * (1 - k), 0, 0.16 * (1 - k)
end

-- Both arms on a saw, sliding opposite each other. Returns left pitch,
-- right pitch, left yaw, right yaw, and a small torso lean.
function NPCAnim.Saw(t: number): (number, number, number, number, number)
	local slide = math.sin(t * 8.5)
	return 1.05 + slide * 0.32, 1.05 - slide * 0.32, -0.5, 0.42, 0.08
end

-- A broom stroke. Returns right-arm pitch, right-arm yaw, and torso yaw.
function NPCAnim.Sweep(t: number): (number, number, number)
	local arc = math.sin(t * 3.6)
	return 0.72, arc * 1.05, arc * 0.22
end

-- How the left arm holds a prop. Pitch, yaw, roll.
function NPCAnim.Carry(kind: string): (number, number, number)
	if kind == "cane" then
		return 0.28, -0.12, -0.25
	elseif kind == "sapling" then
		return 0.85, -0.4, -0.2
	end
	return 1.2, -0.62, -0.08 -- basket, cradled
end

-- A stride. Left leg and right arm swing together. Returns left hip,
-- right hip, left arm pitch, right arm pitch, and a bob.
function NPCAnim.Walk(phase: number, weight: number): (number, number, number, number, number)
	local swing = math.sin(phase) * math.clamp(weight, 0, 1)
	local bob = math.abs(math.sin(phase)) * 0.12 * math.clamp(weight, 0, 1)
	return 0.62 * swing, -0.62 * swing, -0.48 * swing, 0.48 * swing, bob
end

-- A talking hand and a nod. Weight 0 is still. Returns right-arm pitch
-- and neck pitch.
function NPCAnim.Talk(t: number, weight: number): (number, number)
	local w = math.clamp(weight, 0, 1)
	if w <= 0 then
		return 0, 0
	end
	return w * (0.5 + 0.3 * math.sin(t * 8)), w * 0.07 * math.sin(t * 11)
end

export type SampleInput = {
	phase: number,
	walk: number,
	carry: string?,
	work: string?,
	workU: number,
	workTime: number,
	workWeight: number,
	talkTime: number,
	talkWeight: number,
	breath: number,
	asleep: boolean?,
}

-- Tucked limbs for a keeper who is already lying down.
function NPCAnim.Sleep(): Pose
	local p = bare()
	p.leftPitch = NPCAnim.SleepArmPitch
	p.rightPitch = NPCAnim.SleepArmPitch
	p.leftRoll = -NPCAnim.SleepArmRoll
	p.rightRoll = NPCAnim.SleepArmRoll
	p.neckPitch = NPCAnim.SleepNeckPitch
	p.leftHip = NPCAnim.SleepHip
	p.rightHip = NPCAnim.SleepHip
	return p
end

-- The pose for this frame: a walk, a held prop, one work clip, and a
-- talk gesture blended on top. Work wins the arms over talk.
function NPCAnim.Sample(input: SampleInput): Pose
	if input.asleep == true then
		return NPCAnim.Sleep()
	end
	local p = bare()
	local walk = math.clamp(input.walk, 0, 1)
	local leftHip, rightHip, leftArm, rightArm, bob = NPCAnim.Walk(input.phase, walk)
	p.leftHip = leftHip
	p.rightHip = rightHip
	p.leftPitch = leftArm
	p.rightPitch = rightArm
	p.bob = bob
	p.rootPitch = 0.04 * walk
	local idle = 1 - walk
	p.leftRoll = -0.03 * input.breath * idle
	p.rightRoll = 0.03 * input.breath * idle

	local carry = input.carry
	if carry and NPCAnim.Holds(carry) then
		local cp, cy, cr = NPCAnim.Carry(carry)
		p.leftPitch = NPCAnim.Mix(p.leftPitch, cp, 0.85)
		p.leftYaw = cy
		p.leftRoll = NPCAnim.Mix(p.leftRoll, cr, 0.85)
	end

	local ww = math.clamp(input.workWeight, 0, 1)
	local work = input.work
	if work == "chop" and ww > 0 then
		local rp, rr, lean = NPCAnim.Chop(input.workU)
		p.rightPitch = NPCAnim.Mix(p.rightPitch, rp, ww)
		p.rightRoll = NPCAnim.Mix(p.rightRoll, rr, ww)
		p.rootPitch = NPCAnim.Mix(p.rootPitch, lean, ww)
	elseif work == "saw" and ww > 0 then
		local lp, rp, ly, ry, lean = NPCAnim.Saw(input.workTime)
		p.leftPitch = NPCAnim.Mix(p.leftPitch, lp, ww)
		p.rightPitch = NPCAnim.Mix(p.rightPitch, rp, ww)
		p.leftYaw = NPCAnim.Mix(p.leftYaw, ly, ww)
		p.rightYaw = NPCAnim.Mix(p.rightYaw, ry, ww)
		p.rootPitch = NPCAnim.Mix(p.rootPitch, lean, ww)
	elseif work == "sweep" and ww > 0 then
		local rp, ry, rootYaw = NPCAnim.Sweep(input.workTime)
		p.rightPitch = NPCAnim.Mix(p.rightPitch, rp, ww)
		p.rightYaw = NPCAnim.Mix(p.rightYaw, ry, ww)
		p.rootYaw = rootYaw * ww
	end

	local tw = math.clamp(input.talkWeight, 0, 1)
	if tw > 0 and ww < 0.35 then
		local arm, nod = NPCAnim.Talk(input.talkTime, tw * (1 - ww / 0.35))
		p.rightPitch = NPCAnim.Mix(p.rightPitch, arm, tw)
		p.neckPitch += nod
	elseif tw > 0 then
		local _, nod = NPCAnim.Talk(input.talkTime, tw)
		p.neckPitch += nod
	end
	return p
end

return NPCAnim
