--!strict
-- GrabLogic: the rules behind grabbing and dragging loose wood in the v2
-- core loop (V2_PLAN.md §4a), pure so they're tested
-- (tests/GrabLogic.spec.luau). GrabService (server) and DragController
-- (client) both use it.
--   * CanGrab(facts): who may take hold of (or cut) a piece. Dead,
--     selling or held by someone else: no. A shop's display item: yes. On
--     someone else's truck bed: no; on your own: yes, whoever's it is (so
--     nobody can dump wood on your bed). Unowned, your own, or an Elder's
--     piece: yes. Someone else's piece while they're in the server: no
--     (wood is its owner's; WoodService drops the owner of wood left
--     untouched for WoodUnownedAfterSec). An owner who has left: their
--     piece is free once GameConfig.PickupGraceSec has passed since it was
--     cut free. Moving someone's wood never changes who is paid for it
--     (NewOwner), but unowned wood becomes the grabber's. `plotAllows` is
--     the hook plot permissions use later (M3): false refuses.
--   * Force/Torque/CanLift: the drag's pull, mass x DragForcePerMass
--     capped at DragForceCap, so light wood flies and heavy wood drags
--     along the ground (about 20 mass is the most that lifts).
--   * ClampHold/StartHold/StepHold: the hold distance, HoldMin to HoldMax
--     studs from the character.
--   * ClampToBox: where on a piece the grab lands (the server's check of a
--     client's hit point).
--   * ReleaseReason/TooFar: when a hold ends (too far away, dead, seated,
--     an axe taken out).
--   * Target, Turn, KeyAction, PadAction, TouchHold, ConfirmSec, AxeHint:
--     DragController's input maths: where the held point is pulled to,
--     rotation steps, which key does what, tap-and-hold on a touch screen.

local BoxLogic = require(script.Parent.BoxLogic)
local GameConfig = require(script.Parent.GameConfig)

local GrabLogic = {}

---------------------------------------------------------------------------
-- Who may grab what
---------------------------------------------------------------------------

export type Reason = "dead" | "selling" | "held" | "bed" | "plot" | "owned" | "grace" | "far" | "claim" | "cap"

-- What the server knows about one grab request.
export type Facts = {
	userId: number, -- who wants to grab it
	ownerId: number, -- the piece's owner, 0 = nobody
	createdAt: number, -- when it was cut free (the server's os.clock)
	now: number, -- the same clock
	heldBy: number, -- who holds it now, 0 = nobody
	dead: boolean?, -- a dead tree's wood: can't be grabbed, cut or sold
	selling: boolean?, -- being sold right now
	elder: boolean?, -- an Elder's wood: anyone may grab it at once
	shopItem: boolean?, -- a shop's display item (M2)
	shopBox: boolean?, -- a boxed store item (shelf box)
	claimUserId: number?, -- who claimed an unpaid shop box, 0 = nobody
	claimUntil: number?, -- server clock: the claim lasts until this
	paid: boolean?, -- a shop box someone has paid for
	buyerId: number?, -- who paid, when paid
	unpaidByPlayer: number?, -- unpaid boxes this player already has off the shelf
	unpaidOnServer: number?, -- unpaid boxes off the shelf, whole server
	taking: boolean?, -- this grab would lift a shop box off its shelf
	bedOwnerId: number?, -- resting on this player's truck bed (M1.6), nil = not on a bed
	ownerHere: boolean?, -- whether the owner is in the server (nil: count them as here)
	plotAllows: boolean?, -- plot permissions (M3): false = the plot's owner says no
}

-- Whether the piece is someone else's (not unowned, not theirs, not an
-- Elder's, which are everyone's).
function GrabLogic.OwnedByOther(facts: Facts): boolean
	return facts.ownerId ~= 0 and facts.ownerId ~= facts.userId and not facts.elder
end

-- Seconds `facts.userId` still has to wait before grabbing someone else's
-- fresh piece (0: no wait).
function GrabLogic.GraceLeft(facts: Facts): number
	if facts.ownerId == 0 or facts.ownerId == facts.userId or facts.elder then
		return 0
	end
	local left = facts.createdAt + GameConfig.PickupGraceSec - facts.now
	return if left > 0 then left else 0
end

-- Whether the grab may go ahead, and why not.
function GrabLogic.CanGrab(facts: Facts): (boolean, Reason?)
	if facts.dead then
		return false, "dead"
	elseif facts.selling then
		return false, "selling"
	elseif facts.heldBy ~= 0 and facts.heldBy ~= facts.userId then
		return false, "held"
	elseif facts.shopBox then
		local ok, why = BoxLogic.CanGrab({
			userId = facts.userId,
			now = facts.now,
			heldBy = facts.heldBy,
			paid = facts.paid,
			buyerId = facts.buyerId,
			claimUserId = facts.claimUserId,
			claimUntil = facts.claimUntil,
			unpaidByPlayer = facts.unpaidByPlayer,
			unpaidOnServer = facts.unpaidOnServer,
			taking = facts.taking,
		})
		return ok, why :: Reason?
	elseif facts.shopItem then
		return true, nil
	elseif facts.bedOwnerId ~= nil and facts.bedOwnerId ~= facts.userId then
		return false, "bed"
	elseif facts.plotAllows == false then
		return false, "plot"
	elseif facts.bedOwnerId == facts.userId then
		return true, nil -- your own truck bed: you may move anything on it
	elseif GrabLogic.OwnedByOther(facts) and facts.ownerHere ~= false then
		return false, "owned"
	elseif GrabLogic.GraceLeft(facts) > 0 then
		return false, "grace"
	end
	return true, nil
end

export type PadFacts = {
	userId: number,
	ownerId: number,
	plotAllows: boolean?, -- B04: true when the plot owner has allowed this player
}

-- The pad's owner may always press. Anyone else needs the plot permission
-- hook (plotAllows == true). A missing or false hook refuses.
function GrabLogic.CanPressPad(facts: PadFacts): boolean
	if facts.userId ~= 0 and facts.userId == facts.ownerId then
		return true
	end
	return facts.plotAllows == true
end

-- Who owns the piece once `facts.userId` has grabbed it: unowned wood
-- becomes theirs; anyone else's stays theirs (moving wood never changes
-- who is paid for it).
function GrabLogic.NewOwner(facts: Facts): number
	if facts.shopBox then
		return facts.ownerId
	end
	if facts.ownerId == 0 and not facts.shopItem then
		return facts.userId
	end
	return facts.ownerId
end

-- The toast for a refused grab, or nil for none (a dead or selling piece
-- is about to vanish). `name` names whose truck it's on ("bed") or whose
-- wood it is ("owned").
function GrabLogic.Message(reason: string?, facts: Facts?, name: string?): string?
	if reason == "held" then
		return "Someone else is holding that."
	elseif reason == "bed" then
		return string.format("That's on %s's truck.", name or "someone")
	elseif reason == "owned" then
		return string.format("That's %s's wood.", name or "someone else")
	elseif reason == "plot" then
		return "That's on someone's land. Ask them to let you."
	elseif reason == "claim" then
		return "Someone else just picked that up."
	elseif reason == "cap" then
		return BoxLogic.CapMessage(
			if facts then facts.unpaidByPlayer or 0 else 0,
			if facts then facts.unpaidOnServer or 0 else 0
		)
	elseif reason == "far" then
		return "Too far away. Walk closer to grab it."
	elseif reason == "grace" and facts then
		local n = math.max(1, math.ceil(GrabLogic.GraceLeft(facts)))
		return string.format(
			"Someone else just cut that. It's free to take in %d second%s.",
			n,
			if n == 1 then "" else "s"
		)
	end
	return nil
end

---------------------------------------------------------------------------
-- The pull
---------------------------------------------------------------------------

GrabLogic.Gravity = 196.2 -- studs/s², Roblox's default
GrabLogic.TorqueArm = 2 -- studs: the turn's torque is the pull times this
GrabLogic.MaxSpin = 6 -- rad/s: a held piece never spins faster (no log helicopters)

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- The pull on a piece of `mass`: mass x perMass, at most cap (0 for
-- nonsense). Defaults are GameConfig's (the client passes Tune's).
function GrabLogic.Force(mass: number, perMass: number?, cap: number?): number
	local per = perMass or GameConfig.DragForcePerMass
	local most = cap or GameConfig.DragForceCap
	if not finite(mass) or mass <= 0 or not finite(per) or not finite(most) then
		return 0
	end
	return math.clamp(mass * per, 0, math.max(0, most))
end

-- The most torque the hold turns a piece with, from its pull.
function GrabLogic.Torque(force: number): number
	if not finite(force) or force <= 0 then
		return 0
	end
	return force * GrabLogic.TorqueArm
end

-- Whether the pull can lift a piece of `mass` off the ground (or only
-- drag it along).
function GrabLogic.CanLift(mass: number, perMass: number?, cap: number?): boolean
	return GrabLogic.Force(mass, perMass, cap) > mass * GrabLogic.Gravity
end

---------------------------------------------------------------------------
-- How far away it's held
---------------------------------------------------------------------------

-- `d` kept to HoldMin..HoldMax studs (defaults from GameConfig).
function GrabLogic.ClampHold(d: number, min: number?, max: number?): number
	local lo = min or GameConfig.HoldMin
	local hi = math.max(lo, max or GameConfig.HoldMax)
	if not finite(d) then
		return lo
	end
	return math.clamp(d, lo, hi)
end

-- The hold distance a grab starts at: where it was grabbed, from `anchor`
-- (the character's head), clamped.
function GrabLogic.StartHold(grip: Vector3, anchor: Vector3, min: number?, max: number?): number
	return GrabLogic.ClampHold((grip - anchor).Magnitude, min, max)
end

-- The hold distance moved by `delta` studs, clamped.
function GrabLogic.StepHold(d: number, delta: number, min: number?, max: number?): number
	return GrabLogic.ClampHold(d + delta, min, max)
end

-- `point` on the box `cf`/`size` (the closest point on or in it), or nil
-- when it's more than `margin` studs off it. The server's check of where
-- a client says it grabbed a piece (which may have moved a little since).
function GrabLogic.ClampToBox(cf: CFrame, size: Vector3, point: Vector3, margin: number): Vector3?
	local p = cf:PointToObjectSpace(point)
	if not (finite(p.X) and finite(p.Y) and finite(p.Z)) then
		return nil
	end
	local h = size / 2
	local clamped = Vector3.new(math.clamp(p.X, -h.X, h.X), math.clamp(p.Y, -h.Y, h.Y), math.clamp(p.Z, -h.Z, h.Z))
	if (p - clamped).Magnitude > margin then
		return nil
	end
	return cf:PointToWorldSpace(clamped)
end

---------------------------------------------------------------------------
-- When a hold ends
---------------------------------------------------------------------------

export type HoldState = {
	distance: number, -- studs from the character to the held point
	alive: boolean,
	seated: boolean,
	toolOut: boolean, -- an axe (any tool) in hand: dragging needs empty hands
}

-- Why the hold should end now, or nil to keep holding.
function GrabLogic.ReleaseReason(state: HoldState, releaseDistance: number?): string?
	if not state.alive then
		return "died"
	elseif state.seated then
		return "seated"
	elseif state.toolOut then
		return "tool"
	elseif not finite(state.distance) or state.distance > (releaseDistance or GameConfig.ReleaseDistance) then
		return "far"
	end
	return nil
end

-- The server's version of "too far": with its tolerance for lag.
function GrabLogic.TooFar(distance: number, releaseDistance: number?, tolerance: number?): boolean
	local limit = (releaseDistance or GameConfig.ReleaseDistance) + (tolerance or GameConfig.RangeTolerance)
	return not finite(distance) or distance > limit
end

---------------------------------------------------------------------------
-- DragController's input maths
---------------------------------------------------------------------------

GrabLogic.RotateStep = math.rad(15) -- one rotate press
GrabLogic.TouchTurnSteps = 3 -- a touch screen's Turn and Tip buttons turn 45 degrees a press
GrabLogic.WheelStep = 1 -- studs per scroll-wheel notch
GrabLogic.DistanceSpeed = 14 -- studs/s while the D-pad, a bumper or a +/- button is held
GrabLogic.TouchHoldSec = 0.25 -- a touch screen grabs after a finger rests this long on a piece
GrabLogic.TouchSlop = 12 -- pixels: a finger that moves further first is swiping, not grabbing
GrabLogic.ConfirmBase = 0.5 -- seconds the client waits for the server to say the piece is held
GrabLogic.ConfirmMax = 2

-- Where the held point is pulled to: along the camera ray (`origin`,
-- unit `dir`), at `hold` studs from `anchor` (the character's head), in
-- front. When the ray never comes that close (the camera looking far
-- away), the point `hold` studs from the anchor nearest the ray.
function GrabLogic.Target(origin: Vector3, dir: Vector3, anchor: Vector3, hold: number): Vector3
	local unit = if dir.Magnitude > 1e-6 then dir.Unit else Vector3.new(0, 0, -1)
	local m = origin - anchor
	local b = m:Dot(unit)
	local c = m:Dot(m) - hold * hold
	local disc = b * b - c
	if disc >= 0 then
		local t = -b + math.sqrt(disc)
		if t >= 0 then
			return origin + unit * t
		end
	end
	local nearest = origin + unit * math.max(0, -b)
	local away = nearest - anchor
	if away.Magnitude < 1e-6 then
		return anchor + unit * hold
	end
	return anchor + away.Unit * hold
end

export type Turn = { kind: "yaw" | "pitch", steps: number }

-- `rot` (a rotation) turned by `turn`: yaw about the world's up, pitch
-- about the camera's flat right (from its `look`), so "tip away" always
-- tips away from you.
function GrabLogic.Turn(rot: CFrame, turn: Turn, look: Vector3): CFrame
	local angle = turn.steps * GrabLogic.RotateStep
	if turn.kind == "yaw" then
		return GrabLogic.Rotate(rot, angle, 0, look)
	end
	return GrabLogic.Rotate(rot, 0, angle, look)
end

-- `rot` turned by `yaw` radians about the world's up and `pitch` radians
-- about the camera's flat right. The same turns as above, in any amount.
function GrabLogic.Rotate(rot: CFrame, yaw: number, pitch: number, look: Vector3): CFrame
	local right = Vector3.new(-look.Z, 0, look.X) -- look x up, flattened
	local axis = if right.Magnitude > 1e-6 then right.Unit else Vector3.new(1, 0, 0)
	return CFrame.fromAxisAngle(axis, pitch) * CFrame.fromAxisAngle(Vector3.new(0, 1, 0), yaw) * rot.Rotation
end

-- The right stick while the left trigger holds a carried piece in the air
-- (the gamepad's way to turn it): `x`/`y` are the stick (-1..1), `dt` the
-- frame. Returns (yaw, pitch) in radians for this frame. Stick right turns
-- it clockwise seen from above, stick up tips its far end up. Inside the
-- dead zone nothing moves, and the rest of the throw is rescaled from 0 so
-- it starts gently.
GrabLogic.StickDeadZone = 0.2
GrabLogic.StickTurnSpeed = math.rad(150) -- per second at full throw
function GrabLogic.StickTurn(x: number, y: number, dt: number): (number, number)
	local function axis(v: number): number
		if v ~= v or v == math.huge or v == -math.huge then
			return 0
		end
		local m = math.min(math.abs(v), 1)
		if m <= GrabLogic.StickDeadZone then
			return 0
		end
		local scaled = (m - GrabLogic.StickDeadZone) / (1 - GrabLogic.StickDeadZone)
		return (if v < 0 then -1 else 1) * scaled
	end
	local step = GrabLogic.StickTurnSpeed * math.clamp(dt, 0, 0.1)
	return -axis(x) * step, -axis(y) * step
end

-- The rotation a key press asks for while holding, or nil (that key does
-- something else: plain WASD walks). Q/E and Shift+A/D turn; Shift+W/S tip.
function GrabLogic.KeyAction(keyName: string, shift: boolean): Turn?
	if keyName == "Q" then
		return { kind = "yaw", steps = 1 }
	elseif keyName == "E" then
		return { kind = "yaw", steps = -1 }
	elseif not shift then
		return nil
	elseif keyName == "A" then
		return { kind = "yaw", steps = 1 }
	elseif keyName == "D" then
		return { kind = "yaw", steps = -1 }
	elseif keyName == "W" then
		return { kind = "pitch", steps = -1 }
	elseif keyName == "S" then
		return { kind = "pitch", steps = 1 }
	end
	return nil
end

-- The right stick as a flick, for the build placer (LT held): a push past
-- StickFlickAt from a stick that was back inside StickResetAt gives -1 (left or
-- down) or +1 (right or up) once; holding it over does nothing more.
-- `was` is the last value this axis reported, `now` this one. Returns
-- (flick, armed): the flick (0 if none) and whether the next one may fire.
GrabLogic.StickFlickAt = 0.65
GrabLogic.StickResetAt = 0.3
function GrabLogic.StickFlick(was: number, now: number, armed: boolean): (number, boolean)
	if now ~= now then
		return 0, armed
	end
	local m = math.abs(now)
	if m < GrabLogic.StickResetAt then
		return 0, true
	end
	if armed and m >= GrabLogic.StickFlickAt and math.abs(was) < GrabLogic.StickFlickAt then
		return (if now < 0 then -1 else 1), false
	end
	return 0, armed
end

-- A gamepad button while holding: a turn, or a hold-distance direction
-- (+1 further while held, -1 nearer). D-pad left/right turn, D-pad up/down
-- and RB/LB push and pull. (Tipping is the right stick, with LT held.)
function GrabLogic.PadAction(keyName: string): (Turn?, number?)
	if keyName == "DPadLeft" then
		return { kind = "yaw", steps = 1 }, nil
	elseif keyName == "DPadRight" then
		return { kind = "yaw", steps = -1 }, nil
	elseif keyName == "DPadUp" or keyName == "ButtonR1" then
		return nil, 1
	elseif keyName == "DPadDown" or keyName == "ButtonL1" then
		return nil, -1
	end
	return nil, nil
end

-- Whether the drag hold takes an InputBegan press. A bound action marks
-- R2 handled even when it passes it on, and a trigger is no button's
-- click, so a handled trigger still counts unless a menu holds the pad
-- selection. While the placer is up R2 is its Place bind: no grab.
function GrabLogic.PadPressAccepted(processed: boolean, trigger: boolean, selecting: boolean, placing: boolean): boolean
	if trigger and placing then
		return false
	end
	return not processed or (trigger and not selecting)
end

-- A finger resting on a piece since `startAt` at `startPos` (screen
-- pixels), now at `pos`: "grab" once it has rested TouchHoldSec without
-- moving more than TouchSlop, "cancel" once it moves further (a swipe:
-- the camera's), else "wait".
function GrabLogic.TouchHold(startAt: number, startPos: Vector2, now: number, pos: Vector2): "grab" | "cancel" | "wait"
	if (pos - startPos).Magnitude > GrabLogic.TouchSlop then
		return "cancel"
	elseif now - startAt >= GrabLogic.TouchHoldSec then
		return "grab"
	end
	return "wait"
end

-- Whether a touch at `pos` is in the bottom-left corner a touch screen's
-- thumbstick takes (the left 40%, under the top third), which a grab
-- must never steal from.
function GrabLogic.InThumbstickZone(pos: Vector2, screen: Vector2): boolean
	return pos.X < screen.X * 0.4 and pos.Y > screen.Y / 3
end

-- How long the client waits for the server to confirm a grab (HeldBy),
-- given its network ping in seconds: half a second, plus the round trip.
function GrabLogic.ConfirmSec(ping: number?): number
	local p = if ping and finite(ping) and ping > 0 then ping else 0
	return math.min(GrabLogic.ConfirmMax, GrabLogic.ConfirmBase + 2 * p)
end

-- The hint for clicking a piece with an axe out (UITheme.Device names).
function GrabLogic.AxeHint(device: string): string
	if device == "phone" then
		return "Put your axe away (tap it) to drag"
	elseif device == "console" then
		return "Put your axe away to drag"
	end
	return "Put your axe away (press 1) to drag"
end

return GrabLogic
