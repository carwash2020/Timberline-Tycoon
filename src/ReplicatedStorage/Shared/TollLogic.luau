--!strict
-- TollLogic: the north-strip line check. Pure. GateService keeps the last
-- sample per character and per vehicle and asks Crossed before it moves
-- anyone. Payment is GateService's (cash through EconomyService); this
-- file holds the pure rules around it: whether a tap is a fresh payment,
-- how close to the booth counts, and the texts. WORLD_DESIGN §1 and §15.

local GameConfig = require(script.Parent.GameConfig)
local TerrainGen = require(script.Parent.World.TerrainGen)
local Util = require(script.Parent.Util)
local WorldLayout = require(script.Parent.World.WorldLayout)

local TollLogic = {}

-- Studs from the booth's counter a payment still counts (the prompt reaches
-- 12; the rest is the slack a walking player needs between the tap and the
-- server seeing it).
TollLogic.PayRange = 16
TollLogic.PromptRange = 12

-- The south-bank landing. Y is the ground there plus clearance, so a
-- pushed truck or a body pulled out of the gorge is not left inside it.
function TollLogic.Landing(): Vector3
	local y = TerrainGen.HeightAt(WorldLayout.TollPushX, WorldLayout.TollPushZ) + WorldLayout.TollClearance
	return Vector3.new(WorldLayout.TollPushX, y, WorldLayout.TollPushZ)
end

-- True only when a move goes from south of the line to on or past it,
-- inside the strip's x range. Southbound (newZ < prevZ) is always free.
-- One sample per tick, so a 40-stud jump still counts.
function TollLogic.Crossed(prevZ: number, newZ: number, x: number): boolean
	if newZ < prevZ then
		return false
	end
	if prevZ >= WorldLayout.TollLineZ or newZ < WorldLayout.TollLineZ then
		return false
	end
	return x >= WorldLayout.TollLineX0 and x <= WorldLayout.TollLineX1
end

-- One translation: the lead point lands on the push-back, and every other
-- point keeps its offset. Y is the ground at that spot plus clearance,
-- not the height they fell from. A seated player moves the whole assembly.
function TollLogic.MoveAssembly(points: { Vector3 }): { Vector3 }
	local out: { Vector3 } = {}
	local lead = points[1]
	if not lead then
		return out
	end
	local land = TollLogic.Landing()
	local dx = land.X - lead.X
	local dy = land.Y - lead.Y
	local dz = land.Z - lead.Z
	for _, point in ipairs(points) do
		table.insert(out, Vector3.new(point.X + dx, point.Y + dy, point.Z + dz))
	end
	return out
end

-- A driver in a seat takes the vehicle with them. On foot, only that player.
function TollLogic.MovesWholeAssembly(seated: boolean): boolean
	return seated
end

-- Is a tap a fresh payment? "already" while the window the player paid for
-- is still live (a second tap never charges, and never stretches it).
function TollLogic.Quote(now: number, paidUntil: number?): "ok" | "already"
	if paidUntil ~= nil and paidUntil > now then
		return "already"
	end
	return "ok"
end

-- When a payment made at `now` runs out.
function TollLogic.WindowEnd(now: number): number
	return now + GameConfig.TollSeconds
end

-- Whether a player at (x, z) is near enough the booth to pay.
function TollLogic.InPayRange(x: number, z: number, boothX: number?, boothZ: number?): boolean
	local dx = x - (boothX or WorldLayout.BoothX)
	local dz = z - (boothZ or WorldLayout.BoothZ)
	return dx * dx + dz * dz <= TollLogic.PayRange * TollLogic.PayRange
end

local function clock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end
TollLogic.Clock = clock

-- The toasts. The push-back names Old Tolly and the fee; the short-cash
-- one is the price alone (they are different toasts, WORLD_DESIGN §15).
function TollLogic.PushText(): string
	return string.format(
		"Old Tolly: the bridge toll is %s for %d minutes. Pay at his booth first.",
		Util.formatCash(GameConfig.TollFee),
		GameConfig.TollSeconds // 60
	)
end

function TollLogic.ShortText(): string
	return string.format("The toll costs %s.", Util.formatCash(GameConfig.TollFee))
end

function TollLogic.PaidText(): string
	return string.format(
		"Old Tolly: %s paid. Cross within %d minutes.",
		Util.formatCash(GameConfig.TollFee),
		GameConfig.TollSeconds // 60
	)
end

function TollLogic.AlreadyText(left: number): string
	return string.format("You're paid up for another %s. Cross away.", clock(left))
end

function TollLogic.ActionText(): string
	return string.format("Pay toll (%s)", Util.formatCash(GameConfig.TollFee))
end

-- What Old Tolly says about the price, for his Talk bubbles (NPCData). Every
-- number comes from GameConfig, so a change there changes his talk.
function TollLogic.TalkLines(): { string }
	local fee = Util.formatCash(GameConfig.TollFee)
	local minutes = GameConfig.TollSeconds // 60
	return {
		string.format("The toll's %s. That buys you %d minutes to cross.", fee, minutes),
		string.format("Pay at my booth first, friend. %s, then %d minutes to get over.", fee, minutes),
		string.format("Heading north? %s. Heading home south is always free.", fee),
	}
end

return TollLogic
