--!strict
-- CarryLayout: how a player holds the logs they carry (ACT-01). Pure maths
-- on datatypes (no services), so the Lune tests check it.
--
-- The logs: GameServer welds each carried log to the torso (UpperTorso on
-- R15, Torso on R6) at LogOffset(slot), its length across the chest. Slot
-- 0, the first log, sits at chest height with its ends in the hands. Slot
-- 1 tucks in under it, not on top: an avatar's head sits right above its
-- shoulders, so a log stacked on the first would hide the face. Either way
-- the top of the logs stays below the mouth and clear of the head on both
-- default rigs. CarryService restacks after a take, so one log in hand is
-- always slot 0.
--
-- The arms: on R15 the upper arms swing forward ShoulderRaise and the
-- elbows bend so the forearms cross the stack where the two logs meet:
-- the first log rests on them (its lower part in the hands) and the
-- second hangs from them (its upper part in the hands). R6's arms have no
-- elbow and can't reach that low in front of the chest, so they rise
-- R6ShoulderRaise to hold the first log end to end; the second tucks in
-- just under them. tests/CarryLayout.spec works all of this out against
-- the default rigs.
--
-- The joints: CarryPose (client) sets each arm joint's Motor6D.Transform to
-- JointTransform(joint.C0, turn). A Motor6D puts Part1 at
--   Part0.CFrame * C0 * Transform * C1:Inverse()
-- so Transform turns Part1 about the joint in the joint's own axes (C0's).
-- R15's arm joints line up with the body (C0 has no rotation), but R6's
-- shoulders are C0 = Angles(0, +-90deg, 0), so the same swing forward is
-- about X on R15 and about the joint's Z on R6 (+Z on the right arm, -Z
-- on the left). JointTransform takes the turn in Part0's axes (the
-- torso's for a shoulder, the upper arm's for an elbow) and works out the
-- joint's version from C0, so one table serves every rig:
--   Angles(a, 0, 0), a > 0   swings the limb forward (-Z) about Part0's X.

local CarryLayout = {}

CarryLayout.ShoulderRaise = math.rad(52) -- R15 upper arms forward, below level
CarryLayout.ElbowBend = math.rad(18) -- R15 forearms tip up past them, to run between the logs
CarryLayout.R6ShoulderRaise = math.rad(80) -- R6 straight arms forward, just under level
CarryLayout.Range = 150 -- studs from you: players further off aren't posed

-- The carried log weld, relative to the torso. GameServer's pickup writes
-- these numbers into its weld line; tests/CarryLayout.spec checks they
-- match.
CarryLayout.LogBaseY = 0.35 -- slot 0's centre, above the torso's centre
CarryLayout.LogStep = 1.25 -- each further slot this much lower (logs are 1.2 across)
CarryLayout.LogForward = 1.35 -- in front of the torso's centre

function CarryLayout.LogOffset(slot: number): CFrame
	return CFrame.new(0, CarryLayout.LogBaseY - slot * CarryLayout.LogStep, -CarryLayout.LogForward)
end

-- The Motor6D.Transform that turns a joint's Part1 by `turn` (a rotation in
-- Part0's axes) about the joint's pivot, for a joint whose C0 is `c0`.
function CarryLayout.JointTransform(c0: CFrame, turn: CFrame): CFrame
	local r = c0.Rotation
	return r:Inverse() * turn.Rotation * r
end

-- Where a joint puts Part1, relative to Part0, holding `transform`.
function CarryLayout.Limb(c0: CFrame, c1: CFrame, transform: CFrame): CFrame
	return c0 * transform * c1:Inverse()
end

export type ArmJoint = {
	part: string, -- the joint's parent: its Part1 (R15) or the Torso (R6)
	joint: string, -- the Motor6D's name
	turn: CFrame, -- in Part0's axes
}

local raise = CFrame.Angles(CarryLayout.ShoulderRaise, 0, 0)
local bend = CFrame.Angles(CarryLayout.ElbowBend, 0, 0)
local raiseR6 = CFrame.Angles(CarryLayout.R6ShoulderRaise, 0, 0)

CarryLayout.R15 = {
	{ part = "RightUpperArm", joint = "RightShoulder", turn = raise },
	{ part = "LeftUpperArm", joint = "LeftShoulder", turn = raise },
	{ part = "RightLowerArm", joint = "RightElbow", turn = bend },
	{ part = "LeftLowerArm", joint = "LeftElbow", turn = bend },
} :: { ArmJoint }

CarryLayout.R6 = {
	{ part = "Torso", joint = "Right Shoulder", turn = raiseR6 },
	{ part = "Torso", joint = "Left Shoulder", turn = raiseR6 },
} :: { ArmJoint }

-- Whether a player's arms hold the carry pose: logs in hand (`carried` is
-- the CarriedLogs attribute, which may be missing), alive, not sitting
-- (driving), and `distance` (nil: not known) within Range of you.
function CarryLayout.ShouldPose(carried: unknown, alive: boolean, seated: boolean, distance: number?): boolean
	return type(carried) == "number"
		and carried > 0
		and alive
		and not seated
		and distance ~= nil
		and distance <= CarryLayout.Range
end

return CarryLayout
