--!strict
-- ChopFeelLogic: the numbers behind how a chop feels (CHOP-T325). Pure, so
-- the specs pin them and WoodFX / CutController only wire them up.
--   * Prediction: the swinger's chips and thunk play on the impact frame; the
--     server's own "Cut" within PredictWindow consumes that prediction (no
--     double effect), and one that never arrives (or a "Clink") cancels it.
--     Nothing predicted carries cash, a number or progress.
--   * ThunkPitch rises about 20 percent from first to last hit.
--   * The creak and canopy sway latch once per section per cut at CreakAt.
--   * Landing shake caps per device; haptic strengths; the aim cone.
--   * Cut-line labels: what each side of a felled log is about worth.

local SectionLogic = require(script.Parent.SectionLogic)

local ChopFeelLogic = {}

ChopFeelLogic.PredictWindow = 0.75 -- seconds a predicted swing waits for the server's "Cut"
ChopFeelLogic.MatchRadius = 8 -- studs between a predicted impact and the server's cut point
ChopFeelLogic.PitchRise = 0.2 -- thunk speed gain across a whole cut
ChopFeelLogic.CreakAt = 0.8 -- progress at which the creak and sway fire
ChopFeelLogic.SwaySeconds = 0.6
ChopFeelLogic.SwayAngle = 0.05 -- radians of extra canopy rock at the peak of the nudge
ChopFeelLogic.SwayHz = 14 -- how fast it rocks

ChopFeelLogic.ShakeCap = { phone = 0.6, console = 0.9, desktop = 0.9 } :: { [string]: number }
ChopFeelLogic.FinishNudge = 0.25 -- the swinger's own finishing cut, before the cap

ChopFeelLogic.HapticBite = 0.3 -- Small motor on the predicted impact
ChopFeelLogic.HapticFinal = 0.6 -- and on the final hit
ChopFeelLogic.HapticSeconds = 0.1

ChopFeelLogic.AimConeDegrees = 25 -- touch and gamepad: nearest trunk inside this cone

-- Thunk speed multiplier for a cut `progress` (0..1) of the way through.
function ChopFeelLogic.ThunkPitch(progress: number): number
	return 1 + ChopFeelLogic.PitchRise * math.clamp(progress, 0, 1)
end

-- Whether progress has reached the creak, and `latched` says it has not
-- fired yet for this cut. Returns whether to fire now and the new latch.
function ChopFeelLogic.CreakStep(progress: number, latched: boolean): (boolean, boolean)
	if latched then
		return false, true
	end
	if progress >= ChopFeelLogic.CreakAt then
		return true, true
	end
	return false, false
end

-- The nudge's strength `t` seconds in: 0 before, a half sine up and down
-- over SwaySeconds, 0 after.
function ChopFeelLogic.SwayEnvelope(t: number): number
	if t <= 0 or t >= ChopFeelLogic.SwaySeconds then
		return 0
	end
	return math.sin(math.pi * t / ChopFeelLogic.SwaySeconds)
end

-- A cut that restarts (progress back under the creak mark) re-arms the latch.
function ChopFeelLogic.Rearm(progress: number): boolean
	return progress < ChopFeelLogic.CreakAt
end

-- The camera-shake cap for a device ("phone", "console" or "desktop").
function ChopFeelLogic.ShakeLimit(device: string): number
	return ChopFeelLogic.ShakeCap[device] or ChopFeelLogic.ShakeCap.desktop
end

-- A landing's shake strength: heavier lands harder, capped per device.
function ChopFeelLogic.ShakeStrength(mass: number, device: string): number
	return math.min(math.clamp(0.25 + mass / 80, 0.25, 0.9), ChopFeelLogic.ShakeLimit(device))
end

-- The small nudge on the swinger's own finishing cut.
function ChopFeelLogic.FinishShake(device: string): number
	return math.min(ChopFeelLogic.FinishNudge, ChopFeelLogic.ShakeLimit(device))
end

-- Whether `offset` (from the player to a trunk) is inside the aim cone around
-- `look`. A zero look (no camera) accepts anything.
function ChopFeelLogic.InCone(offset: Vector3, look: Vector3?, degrees: number?): boolean
	if look == nil or look.Magnitude < 1e-3 or offset.Magnitude < 1e-3 then
		return true
	end
	local limit = math.cos(math.rad(degrees or ChopFeelLogic.AimConeDegrees))
	return offset.Unit:Dot(look.Unit) >= limit - 1e-9
end

---------------------------------------------------------------------------
-- The prediction ledger
---------------------------------------------------------------------------

export type Prediction = { at: number, pos: Vector3, token: any }
export type Ledger = { list: { Prediction } }

function ChopFeelLogic.NewLedger(): Ledger
	return { list = {} }
end

function ChopFeelLogic.Add(ledger: Ledger, pos: Vector3, token: any, now: number)
	table.insert(ledger.list, { at = now, pos = pos, token = token })
end

local function near(a: Vector3, b: Vector3): boolean
	return (a - b).Magnitude <= ChopFeelLogic.MatchRadius
end

-- The server's own "Cut" at `pos`: takes the oldest live prediction near it
-- (and returns it), or nil when there is none (play the effect as usual).
function ChopFeelLogic.Consume(ledger: Ledger, pos: Vector3, now: number): Prediction?
	for i, p in ipairs(ledger.list) do
		if now - p.at <= ChopFeelLogic.PredictWindow and near(p.pos, pos) then
			table.remove(ledger.list, i)
			return p
		end
	end
	return nil
end

-- Predictions older than the window: removed and returned (their chips go
-- back to the pool).
function ChopFeelLogic.Sweep(ledger: Ledger, now: number): { Prediction }
	local gone: { Prediction } = {}
	local keep: { Prediction } = {}
	for _, p in ipairs(ledger.list) do
		if now - p.at > ChopFeelLogic.PredictWindow then
			table.insert(gone, p)
		else
			table.insert(keep, p)
		end
	end
	ledger.list = keep
	return gone
end

-- A "Clink" at `pos`: removes and returns every prediction near it.
function ChopFeelLogic.Cancel(ledger: Ledger, pos: Vector3): { Prediction }
	local gone: { Prediction } = {}
	local keep: { Prediction } = {}
	for _, p in ipairs(ledger.list) do
		if near(p.pos, pos) then
			table.insert(gone, p)
		else
			table.insert(keep, p)
		end
	end
	ledger.list = keep
	return gone
end

---------------------------------------------------------------------------
-- Reject telemetry (log only: no kick, no remote, no event, no save)
---------------------------------------------------------------------------

ChopFeelLogic.RejectEvery = 25 -- one printed line per this many tracked rejects
ChopFeelLogic.TrackedRejects = { "cooldown", "far", "noLOS", "rate" } :: { string }

local TRACKED: { [string]: boolean } = {}
for _, reason in ipairs(ChopFeelLogic.TrackedRejects) do
	TRACKED[reason] = true
end

export type RejectCounts = { cooldown: number, far: number, noLOS: number, rate: number }

function ChopFeelLogic.NewRejects(): RejectCounts
	return { cooldown = 0, far = 0, noLOS = 0, rate = 0 }
end

-- Counts `reason` (ignored unless tracked). Returns whether this one is a
-- tracked reject that should print a line (every RejectEvery-th in total).
function ChopFeelLogic.CountReject(counts: RejectCounts, reason: string?): boolean
	if reason == nil or not TRACKED[reason] then
		return false
	end
	local c = counts :: any
	c[reason] += 1
	return ChopFeelLogic.RejectTotal(counts) % ChopFeelLogic.RejectEvery == 0
end

function ChopFeelLogic.RejectTotal(counts: RejectCounts): number
	return counts.cooldown + counts.far + counts.noLOS + counts.rate
end

function ChopFeelLogic.RejectLine(userId: number, counts: RejectCounts): string
	return string.format(
		"[Chop] user %d rejects: cooldown %d, far %d, noLOS %d, rate %d",
		userId,
		counts.cooldown,
		counts.far,
		counts.noLOS,
		counts.rate
	)
end

---------------------------------------------------------------------------
-- Cut-line label
---------------------------------------------------------------------------

-- The volume (u³) of each side of a section sx by sy by sz studs cut `h`
-- studs up from its bottom: (low, high). Together they are the whole.
function ChopFeelLogic.SplitVolumes(sx: number, sy: number, sz: number, h: number): (number, number)
	local cut = math.clamp(h, 0, sy)
	return SectionLogic.Volume(sx, cut, sz), SectionLogic.Volume(sx, sy - cut, sz)
end

-- "about 1.2 u3 · $8" for the label; value is the whole piece's `Value`
-- attribute scaled by this side's share. Ignores a Lux swing's bonus.
function ChopFeelLogic.SideText(volume: number, totalVolume: number, totalValue: number): string
	local share = if totalVolume > 1e-9 then math.clamp(volume / totalVolume, 0, 1) else 0
	return string.format("about %.1f u3, $%d", volume, math.floor(totalValue * share + 0.5))
end

return ChopFeelLogic
