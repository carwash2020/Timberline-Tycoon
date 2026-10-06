--!strict
-- SwingLogic: the two-handed chop, as numbers (no instances).
--
-- Each swing lasts exactly that axe's cooldown, so the chop rate is the
-- rate the economy already uses. The motion is one clip (length 1) played
-- back at clipLength / cooldown. Phases, as fractions of that clip:
--   wind-up   0.00 .. 0.40   the axe comes back over the right shoulder
--   impact    0.40           the hit; never later than 0.26 s of real time
--   bite      0.40 .. 0.48   a real hit freezes in the bark; a miss glances
--   follow    0.48 .. 0.80   the heavy rip through
--   recover   0.80 .. 1.00   back to the shoulder rest, which is also the
--                            start, so a held chop chains straight on
--
-- The pose is joint turns in each rig's parent axes (the same convention
-- as CarryLayout). R15 folds at the elbow; R6's arm is one bone, so its
-- arc is a little shorter. The blade is the haft past the grip (AxeArt
-- holds 0.75 up a haft of about 3.2, and the longest is 3.5).

local SwingLogic = {}

SwingLogic.ClipLength = 1
SwingLogic.WindupEnd = 0.40
SwingLogic.Impact = 0.40
SwingLogic.BiteEnd = 0.48
SwingLogic.FollowEnd = 0.80
SwingLogic.RecoverEnd = 1
SwingLogic.Apex = 0.22 -- the top of the wind-up, inside the wind-up phase
SwingLogic.ImpactCap = 0.26 -- seconds; a slow axe still hits by here
SwingLogic.SeeRange = 100 -- studs; other clients beyond this don't pose it
SwingLogic.HeadClearance = 0.4
SwingLogic.GroundClearance = 0.3
SwingLogic.GroundStop = 0.3 -- a slope ray this close lifts the follow-through
SwingLogic.FirstPerson = 1 -- studs from the head: the camera is inside it
SwingLogic.HaftTiltMin = math.rad(25)
SwingLogic.TorsoTwist = math.rad(30)
SwingLogic.TorsoLean = math.rad(15)
SwingLogic.Arc = math.rad(150)
SwingLogic.FollowLimit = math.rad(40) -- no steeper than this below horizontal
SwingLogic.GripFromFoot = 0.75
SwingLogic.Lean = 0.15 -- AxeArt's forward lean in the hand

export type RigName = "R15" | "R6"
export type Contact = "bite" | "glance"
export type PhaseName = "windup" | "bite" | "follow" | "recover"

export type SwingState = {
	id: number,
	started: number,
	len: number,
	impactAt: number,
	fired: boolean,
	cancelled: boolean,
	contact: Contact?,
}

-- Playback speed of the unit clip so it finishes in `cooldown` seconds.
function SwingLogic.PlaybackScale(cooldown: number): number
	return SwingLogic.ClipLength / cooldown
end

-- Real seconds from the press to the impact. The 0.40 mark, but never
-- later than ImpactCap (a Steel axe's 0.40 * 0.73 would be 0.29 s).
function SwingLogic.ImpactTime(cooldown: number): number
	return math.min(SwingLogic.Impact * cooldown, SwingLogic.ImpactCap)
end

-- Clip position (0..1) at `elapsed` seconds into a swing of `cooldown`.
-- Wind-up is squeezed so the impact frame lands on ImpactTime; the rest
-- of the clip fills whatever cooldown remains. With no cap this is just
-- elapsed / cooldown.
function SwingLogic.ClipAt(cooldown: number, elapsed: number): number
	if cooldown <= 0 or elapsed >= cooldown then
		return 1
	end
	if elapsed <= 0 then
		return 0
	end
	local impactT = SwingLogic.ImpactTime(cooldown)
	if impactT <= 1e-6 then
		return 1
	end
	if elapsed <= impactT then
		return SwingLogic.Impact * (elapsed / impactT)
	end
	local span = cooldown - impactT
	if span <= 1e-6 then
		return 1
	end
	return SwingLogic.Impact + (1 - SwingLogic.Impact) * ((elapsed - impactT) / span)
end

-- The fallback swing, for a character whose arm joints can't be found (an
-- unusual avatar rig): the tool alone tips about its handle's X axis.
-- Radians, 0 at the start and the end of the clip; negative is back over
-- the shoulder, positive is down through the cut. No assets, no joints.
SwingLogic.GripBack = math.rad(70)
SwingLogic.GripThrough = math.rad(55)

function SwingLogic.GripAngle(clip: number): number
	local c = math.clamp(clip, 0, 1)
	local function ease(x: number): number
		local u = math.clamp(x, 0, 1)
		return u * u * (3 - 2 * u)
	end
	if c < SwingLogic.Apex then
		return -SwingLogic.GripBack * ease(c / SwingLogic.Apex)
	elseif c < SwingLogic.Impact then
		local u = ease((c - SwingLogic.Apex) / (SwingLogic.Impact - SwingLogic.Apex))
		return -SwingLogic.GripBack + (SwingLogic.GripBack + SwingLogic.GripThrough) * u
	elseif c < SwingLogic.FollowEnd then
		return SwingLogic.GripThrough
	end
	return SwingLogic.GripThrough * (1 - ease((c - SwingLogic.FollowEnd) / (1 - SwingLogic.FollowEnd)))
end

function SwingLogic.Phase(clip: number): PhaseName
	if clip < SwingLogic.Impact then
		return "windup"
	elseif clip < SwingLogic.BiteEnd then
		return "bite"
	elseif clip < SwingLogic.FollowEnd then
		return "follow"
	end
	return "recover"
end

-- The Lux trail is on from the impact through the end of the follow-through.
function SwingLogic.TrailOn(clip: number): boolean
	return clip >= SwingLogic.Impact - 1e-4 and clip < SwingLogic.FollowEnd
end

function SwingLogic.InView(distance: number?): boolean
	return distance ~= nil and distance <= SwingLogic.SeeRange
end

function SwingLogic.InFirstPerson(cameraPos: Vector3, headPos: Vector3): boolean
	return (cameraPos - headPos).Magnitude < SwingLogic.FirstPerson
end

-- Why a swing must not start, or must abort before the impact. Nil when
-- the body is free to chop. A missing health (no humanoid yet) does not
-- block: the server still refuses a dead character.
function SwingLogic.Blocked(health: number?, seated: boolean, carried: number): string?
	if health ~= nil and health <= 0 then
		return "dead"
	end
	if seated then
		return "sit"
	end
	if carried > 0 then
		return "carry"
	end
	return nil
end

function SwingLogic.Begin(id: number, now: number, cooldown: number): SwingState
	return {
		id = id,
		started = now,
		len = cooldown,
		impactAt = now + SwingLogic.ImpactTime(cooldown),
		fired = false,
		cancelled = false,
		contact = nil,
	}
end

function SwingLogic.Cancel(state: SwingState)
	state.cancelled = true
end

-- One decision at `now`. "wait" until the impact frame; then exactly one
-- of "chop" or "glance", and every later call is "wait" (no double hit).
-- "cancel" when the swing was aborted during the wind-up: no chop.
function SwingLogic.Resolve(state: SwingState, now: number, hasTarget: boolean): string
	if state.cancelled then
		return "cancel"
	end
	if state.fired or now < state.impactAt then
		return "wait"
	end
	state.fired = true
	if hasTarget then
		state.contact = "bite"
		return "chop"
	end
	state.contact = "glance"
	return "glance"
end

-- How many swings a hold of `seconds` starts. One at t = 0 and another
-- each cooldown, while the start is still inside the hold.
function SwingLogic.HoldChops(seconds: number, cooldown: number): number
	if cooldown <= 0 or seconds <= 0 then
		return 0
	end
	local count = 0
	local t = 0
	while t < seconds - 1e-9 do
		count += 1
		t += cooldown
	end
	return count
end

-- Presses at `times` (seconds). One accepted swing per cooldown; the rest
-- are ignored. Returns accepted, ignored.
function SwingLogic.SpamChops(times: { number }, cooldown: number): (number, number)
	local nextAt = -math.huge
	local accepted, ignored = 0, 0
	for _, t in ipairs(times) do
		if t >= nextAt - 1e-9 then
			accepted += 1
			nextAt = t + cooldown
		else
			ignored += 1
		end
	end
	return accepted, ignored
end

-- Impacts `cooldown` apart, each ImpactTime after its press, are all
-- taken by a server that arms the next swing when the chop arrives
-- (setSwingDue unchanged: due = max(now, due) + cooldown).
function SwingLogic.ServerTakes(impacts: { number }, cooldown: number, tolerance: number): boolean
	local due = 0
	for _, t in ipairs(impacts) do
		if t < due - tolerance then
			return false
		end
		due = math.max(t, due) + cooldown
	end
	return true
end

---------------------------------------------------------------------------
-- The pose
---------------------------------------------------------------------------

-- Channels: right arm, left arm, then waist twist (yaw) and lean (pitch).
type Channels = { number }

local function ch(p, y, r, e, lp, ly, lr, le, twist, lean): Channels
	return { p, y, r, e, lp, ly, lr, le, twist, lean }
end

local function rad(deg: number): number
	return math.rad(deg)
end

-- Shoulder rest, apex, impact, follow-through. Recover blends back to rest
-- and the next wind-up blends out of it, so a hold has no hitch.
local KEYS: { [RigName]: { Channels } } = {
	R15 = {
		ch(2.10, -0.40, 0.30, -0.50, 1.50, 0.45, -0.35, -0.35, rad(8), 0),
		ch(2.80, -0.60, 0.40, -0.80, 2.30, 0.70, -0.45, -0.50, rad(30), 0),
		ch(2.30, 1.20, -1.40, -1.20, 1.70, 0.50, -0.80, -0.70, rad(10), rad(6)),
		ch(0.50, 1.20, 0.60, -1.20, 0.90, 0.35, -0.55, -0.40, 0, rad(15)),
	},
	R6 = {
		ch(1.80, -0.50, -0.10, 0, 1.40, 0.40, 0, 0, rad(8), 0),
		ch(2.40, -0.80, -0.20, 0, 1.90, 0.60, 0.10, 0, rad(30), 0),
		ch(0.20, 0.80, 0.40, 0, 0.40, 0.30, -0.10, 0, rad(8), rad(4)),
		ch(0.20, 0.20, 0.40, 0, 0.30, 0.15, -0.10, 0, 0, rad(15)),
	},
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerpCh(a: Channels, b: Channels, t: number): Channels
	local out = table.create(#a, 0)
	local u = smooth(t)
	for i = 1, #a do
		out[i] = lerp(a[i], b[i], u)
	end
	return out
end

local function span(clip: number, a: number, b: number): number
	if b <= a then
		return 1
	end
	return math.clamp((clip - a) / (b - a), 0, 1)
end

-- `pitchScale` pulls the follow-through back toward the impact (1 is the
-- full rip, 0 stays at the impact). A slope ray uses it so the blade
-- doesn't dig in.
function SwingLogic.Channels(rig: RigName, clip: number, contact: Contact?, pitchScale: number?): Channels
	local keys = KEYS[rig]
	local rest, apex, impact, follow = keys[1], keys[2], keys[3], keys[4]
	local scale = if pitchScale == nil then 1 else math.clamp(pitchScale, 0, 1)
	local ripped = lerpCh(impact, follow, scale)
	local u = math.clamp(clip, 0, 1)
	local pose: Channels
	if u < SwingLogic.Apex then
		pose = lerpCh(rest, apex, span(u, 0, SwingLogic.Apex))
	elseif u < SwingLogic.Impact then
		pose = lerpCh(apex, impact, span(u, SwingLogic.Apex, SwingLogic.Impact))
	elseif u < SwingLogic.BiteEnd then
		-- A bite freezes in the bark. A glance bounces. No prediction (another
		-- player's swing) moves through, so a miss doesn't stick for them.
		if contact == "bite" then
			pose = impact
		elseif contact == "glance" then
			local bump = math.sin(span(u, SwingLogic.Impact, SwingLogic.BiteEnd) * math.pi)
			pose = lerpCh(impact, apex, 0.35 * bump)
		else
			pose = lerpCh(impact, ripped, span(u, SwingLogic.Impact, SwingLogic.BiteEnd) * 0.35)
		end
	elseif u < SwingLogic.FollowEnd then
		pose = lerpCh(impact, ripped, span(u, SwingLogic.BiteEnd, SwingLogic.FollowEnd))
	else
		pose = lerpCh(ripped, rest, span(u, SwingLogic.FollowEnd, 1))
	end
	return pose
end

export type JointTurn = { part: string, joint: string, turn: CFrame }

-- Turns in each joint's parent axes. R6 counters the root twist on the
-- hips so the legs stay planted while the torso winds up.
function SwingLogic.Joints(rig: RigName, clip: number, contact: Contact?, pitchScale: number?): { JointTurn }
	local c = SwingLogic.Channels(rig, clip, contact, pitchScale)
	local rArm = CFrame.Angles(c[1], c[2], c[3])
	local rElbow = CFrame.Angles(c[4], 0, 0)
	local lArm = CFrame.Angles(c[5], c[6], c[7])
	local lElbow = CFrame.Angles(c[8], 0, 0)
	local twist, lean = c[9], c[10]
	local waist = CFrame.Angles(-lean, -twist, 0)
	if rig == "R15" then
		return {
			{ part = "RightUpperArm", joint = "RightShoulder", turn = rArm },
			{ part = "RightUpperArm", joint = "RightElbow", turn = rElbow },
			{ part = "LeftUpperArm", joint = "LeftShoulder", turn = lArm },
			{ part = "LeftUpperArm", joint = "LeftElbow", turn = lElbow },
			{ part = "UpperTorso", joint = "Waist", turn = waist },
		}
	end
	local hips = CFrame.Angles(lean, twist, 0)
	return {
		{ part = "Torso", joint = "Right Shoulder", turn = rArm },
		{ part = "Torso", joint = "Left Shoulder", turn = lArm },
		{ part = "HumanoidRootPart", joint = "RootJoint", turn = waist },
		{ part = "Torso", joint = "Right Hip", turn = hips },
		{ part = "Torso", joint = "Left Hip", turn = hips },
	}
end

-- Default blocky rigs (the same joint frames CarryLayout's specs use) plus
-- where the torso sits on the root. HipHeight: R15's property is the leg
-- (2). R6's property is 0 and the legs hang another 2 below the root, so
-- both feet are 3 studs under the root centre (VehicleService's R6 height).
local R15_SHOULDER = {
	c0 = CFrame.new(1, 0.563, 0),
	c1 = CFrame.new(-0.5, 0.392, 0),
}
local R15_ELBOW = {
	c0 = CFrame.new(0, -0.334, 0),
	c1 = CFrame.new(0, 0.259, 0),
}
local R15_WRIST = {
	c0 = CFrame.new(0, -0.501, 0),
	c1 = CFrame.new(0, 0.125, 0),
}
local R15_LSHOULDER = {
	c0 = CFrame.new(-1, 0.563, 0),
	c1 = CFrame.new(0.5, 0.392, 0),
}
local R6_SHOULDER = {
	c0 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	c1 = CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
}
local R6_LSHOULDER = {
	c0 = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
	c1 = CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
}

local RIG = {
	R15 = {
		torsoY = 0.15,
		rootSizeY = 2,
		hipHeight = 2,
		gripDown = 0.15,
		headCentre = Vector3.new(0, 1.3, 0),
		headHalf = Vector3.new(0.6, 0.6, 0.6),
	},
	R6 = {
		torsoY = 0,
		rootSizeY = 2,
		hipHeight = 2,
		gripDown = 1,
		headCentre = Vector3.new(0, 1.5, 0),
		headHalf = Vector3.new(0.625, 0.625, 0.625),
	},
}

local function jointTransform(c0: CFrame, turn: CFrame): CFrame
	local r = c0.Rotation
	return r:Inverse() * turn.Rotation * r
end

local function limb(c0: CFrame, c1: CFrame, turn: CFrame): CFrame
	return c0 * jointTransform(c0, turn) * c1:Inverse()
end

type ArmFrames = {
	torso: CFrame,
	rightUpper: CFrame,
	rightLower: CFrame?,
	leftUpper: CFrame,
	leftLower: CFrame?,
	hand: CFrame,
}

-- Right-hand CFrame in root space, the elbow, the other elbow, and the
-- arm parts (their CFrames, the way a Motor6D would place them).
local function rightArm(rig: RigName, channels: Channels): (CFrame, Vector3, Vector3, ArmFrames)
	local torso = CFrame.new(0, RIG[rig].torsoY, 0) * CFrame.Angles(-channels[10], -channels[9], 0)
	local armTurn = CFrame.Angles(channels[1], channels[2], channels[3])
	local leftTurn = CFrame.Angles(channels[5], channels[6], channels[7])
	if rig == "R6" then
		local arm = limb(R6_SHOULDER.c0, R6_SHOULDER.c1, armTurn)
		local left = limb(R6_LSHOULDER.c0, R6_LSHOULDER.c1, leftTurn)
		local elbow = arm * Vector3.new(0, 0.4, 0)
		return torso * arm,
			torso * elbow,
			torso * R6_LSHOULDER.c0.Position,
			{
				torso = torso,
				rightUpper = torso * arm,
				rightLower = nil,
				leftUpper = torso * left,
				leftLower = nil,
				hand = torso * arm,
			}
	end
	local upper = limb(R15_SHOULDER.c0, R15_SHOULDER.c1, armTurn)
	local elbowAt = upper * R15_ELBOW.c0.Position
	local lower = upper * limb(R15_ELBOW.c0, R15_ELBOW.c1, CFrame.Angles(channels[4], 0, 0))
	local hand = lower * limb(R15_WRIST.c0, R15_WRIST.c1, CFrame.identity)
	local left = limb(R15_LSHOULDER.c0, R15_LSHOULDER.c1, leftTurn)
	local leftLower = left * limb(R15_ELBOW.c0, R15_ELBOW.c1, CFrame.Angles(channels[8], 0, 0))
	local leftElbow = left * R15_ELBOW.c0.Position
	return torso * hand,
		torso * elbowAt,
		torso * leftElbow,
		{
			torso = torso,
			rightUpper = torso * upper,
			rightLower = torso * lower,
			leftUpper = torso * left,
			leftLower = torso * leftLower,
			hand = torso * hand,
		}
end

-- Blade and poll samples in the axe's handle space (handle centre is the
-- origin, +Y toward the head, -Z the edge).
local function headLocals(len: number): { Vector3 }
	local y = len / 2
	return {
		Vector3.new(0, y, 0),
		Vector3.new(0, y, -1.05),
		Vector3.new(0, y - 0.5, -1.05),
		Vector3.new(0, y + 0.2, -0.3),
		Vector3.new(0.25, y, -0.4),
		Vector3.new(-0.25, y, -0.4),
		Vector3.new(0, y, 0.4),
	}
end

local function distToBox(point: Vector3, centre: Vector3, half: Vector3): number
	local d = point - centre
	local q = Vector3.new(math.abs(d.X) - half.X, math.abs(d.Y) - half.Y, math.abs(d.Z) - half.Z)
	local outside = Vector3.new(math.max(q.X, 0), math.max(q.Y, 0), math.max(q.Z, 0)).Magnitude
	local inside = math.max(q.X, math.max(q.Y, q.Z))
	if inside < 0 then
		return inside
	end
	return outside
end

export type Sample = {
	haft: Vector3, -- unit, hand toward the blade, root space
	hand: Vector3,
	elbow: Vector3,
	leftElbow: Vector3,
	headClear: number, -- studs outside the head box; negative is inside
	lowest: number, -- lowest blade sample, root space
	footPlane: number, -- the ground the clearance is measured from
	elevation: number, -- haft vs horizontal; negative is below
	fromVertical: number,
	twist: number,
	lean: number,
	handY: number,
	headTop: number,
}

function SwingLogic.FootPlane(rig: RigName): number
	local info = RIG[rig]
	return -info.rootSizeY / 2 - info.hipHeight
end

function SwingLogic.Sample(
	rig: RigName,
	handleLen: number,
	clip: number,
	contact: Contact?,
	pitchScale: number?
): Sample
	local channels = SwingLogic.Channels(rig, clip, contact, pitchScale)
	local info = RIG[rig]
	local handCF, elbow, leftElbow = rightArm(rig, channels)
	local grip = handCF * CFrame.new(0, -info.gripDown, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	local handleCF = grip
		* CFrame.Angles(-SwingLogic.Lean, 0, 0)
		* CFrame.new(0, handleLen / 2 - SwingLogic.GripFromFoot, 0)
	local torso = CFrame.new(0, info.torsoY, 0) * CFrame.Angles(-channels[10], -channels[9], 0)
	local headCentre = torso * info.headCentre
	local headTop = (torso * (info.headCentre + Vector3.new(0, info.headHalf.Y, 0))).Y
	local tip = handleCF * Vector3.new(0, handleLen / 2, 0)
	local haft = tip - grip.Position
	if haft.Magnitude > 1e-4 then
		haft = haft.Unit
	else
		haft = Vector3.yAxis
	end
	local clear = math.huge
	local lowest = math.huge
	for _, localPoint in ipairs(headLocals(handleLen)) do
		local world = handleCF * localPoint
		clear = math.min(clear, distToBox(world, headCentre, info.headHalf))
		lowest = math.min(lowest, world.Y)
	end
	return {
		haft = haft,
		hand = grip.Position,
		elbow = elbow,
		leftElbow = leftElbow,
		headClear = clear,
		lowest = lowest,
		footPlane = SwingLogic.FootPlane(rig),
		elevation = math.asin(math.clamp(haft.Y, -1, 1)),
		fromVertical = math.acos(math.clamp(haft.Y, -1, 1)),
		twist = channels[9],
		lean = channels[10],
		handY = grip.Position.Y,
		headTop = headTop,
	}
end

-- Lowest blade point in root space, for the slope ray.
function SwingLogic.BladeLow(
	rig: RigName,
	handleLen: number,
	clip: number,
	contact: Contact?,
	pitchScale: number?
): Vector3
	local channels = SwingLogic.Channels(rig, clip, contact, pitchScale)
	local info = RIG[rig]
	local handCF = rightArm(rig, channels)
	local grip = handCF * CFrame.new(0, -info.gripDown, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	local handleCF = grip
		* CFrame.Angles(-SwingLogic.Lean, 0, 0)
		* CFrame.new(0, handleLen / 2 - SwingLogic.GripFromFoot, 0)
	local lowest = handleCF * Vector3.new(0, handleLen / 2, 0)
	local lowY = lowest.Y
	for _, localPoint in ipairs(headLocals(handleLen)) do
		local world = handleCF * localPoint
		if world.Y < lowY then
			lowest = world
			lowY = world.Y
		end
	end
	return lowest
end

function SwingLogic.HaftAngle(a: Vector3, b: Vector3): number
	return math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
end

export type Block = { name: string, size: Vector3, cf: CFrame, color: Color3 }

local SKIN = Color3.fromRGB(232, 185, 148)
local SHIRT = Color3.fromRGB(184, 56, 46)
local PANTS = Color3.fromRGB(61, 90, 140)
local WOOD = Color3.fromRGB(168, 116, 68)
local STEEL = Color3.fromRGB(176, 184, 192)

local function block(list: { Block }, name: string, size: Vector3, cf: CFrame, color: Color3)
	table.insert(list, { name = name, size = size, cf = cf, color = color })
end

-- A blocky figure in root space (feet on FootPlane) holding the longest
-- kind of haft, so a preview can draw the same pose the clearance spec
-- measures. R15 bends at the elbow; R6's arm is one bone.
function SwingLogic.Figure(
	rig: RigName,
	handleLen: number,
	clip: number,
	contact: Contact?,
	pitchScale: number?
): { Block }
	local channels = SwingLogic.Channels(rig, clip, contact, pitchScale)
	local info = RIG[rig]
	local _hand, _elbow, _left, arms = rightArm(rig, channels)
	local grip = arms.hand * CFrame.new(0, -info.gripDown, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	local handleCF = grip
		* CFrame.Angles(-SwingLogic.Lean, 0, 0)
		* CFrame.new(0, handleLen / 2 - SwingLogic.GripFromFoot, 0)
	local out: { Block } = {}
	local torso = arms.torso
	block(out, "Torso", Vector3.new(2, 1.6, 1), torso * CFrame.new(0, 0.15, 0), SHIRT)
	block(out, "Head", info.headHalf * 2, torso * CFrame.new(info.headCentre), SKIN)
	if rig == "R15" then
		block(out, "RightUpperArm", Vector3.new(0.9, 1.2, 0.9), arms.rightUpper, SHIRT)
		block(out, "RightLowerArm", Vector3.new(0.85, 1.05, 0.85), arms.rightLower :: CFrame, SKIN)
		block(out, "LeftUpperArm", Vector3.new(0.9, 1.2, 0.9), arms.leftUpper, SHIRT)
		block(out, "LeftLowerArm", Vector3.new(0.85, 1.05, 0.85), arms.leftLower :: CFrame, SKIN)
		block(out, "RightLeg", Vector3.new(0.9, 1.9, 0.9), CFrame.new(0.5, -1.9, 0), PANTS)
		block(out, "LeftLeg", Vector3.new(0.9, 1.9, 0.9), CFrame.new(-0.5, -1.9, 0), PANTS)
	else
		block(out, "RightArm", Vector3.new(1, 2, 1), arms.rightUpper, SHIRT)
		block(out, "LeftArm", Vector3.new(1, 2, 1), arms.leftUpper, SHIRT)
		local hips = CFrame.Angles(channels[10], channels[9], 0)
		block(out, "RightLeg", Vector3.new(1, 2, 1), CFrame.new(0.5, -1, 0) * hips * CFrame.new(0, -1, 0), PANTS)
		block(out, "LeftLeg", Vector3.new(1, 2, 1), CFrame.new(-0.5, -1, 0) * hips * CFrame.new(0, -1, 0), PANTS)
	end
	block(out, "Haft", Vector3.new(0.26, handleLen, 0.32), handleCF, WOOD)
	local headY = handleLen / 2
	block(out, "Blade", Vector3.new(0.28, 1.15, 1.35), handleCF * CFrame.new(0, headY - 0.15, -0.55), STEEL)
	return out
end

return SwingLogic
