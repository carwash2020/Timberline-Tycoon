--!strict
-- AutomationLogic: conveyors and the rules for machines fed by them
-- (GAME_DESIGN §9, V2_PLAN.md §10). Pure, so the server (BeltService,
-- SawmillService, PlanerService), the shop, the placer and the specs agree.
--
-- What is built here (and what is not): belts that carry loose logs and
-- planks into a sawmill or a planer, and the machines' outfeeds landing on a
-- belt. Not built: the logic network (levers, sensors, sorting, wires).
--
--   * The kit: Straight Belt, Turn Belt and Funnel Belt (ItemCatalog.Machines,
--     belt = ...). Each is a boxed one-time-use item like the sawmills and
--     planers: bought at the Tool Shed, opened into a placement ghost on your
--     plot, the box is spent when it is placed.
--   * The plot holds at most GameConfig.MaxConveyorsPerPlot belt pieces.
--   * A belt runs only while its owner is online (GAME_DESIGN §9), and stops
--     while the owner has MaxLooseOutputs or more planks and boards lying
--     around (the Warehouse is not built yet, so this is its capacity: clear
--     the floor and the line starts again).
--   * A machine takes a piece off a belt only when it is the owner's own
--     wood, ordinary wood (no rare or figured wood, no Elder: those stay
--     hand work), and the machine's throughput bucket has room. Throughput
--     is the tier's autoRate in u³ a minute (ItemCatalog / planer tables);
--     hand-fed pieces are not capped, so hand work stays the faster way to
--     a given piece and a higher tier is what makes a belt worth building.

local GameConfig = require(script.Parent.GameConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)
local PlanerLogic = require(script.Parent.PlanerLogic)
local PlotData = require(script.Parent.PlotData)
local WoodData = require(script.Parent.WoodData)

local AutomationLogic = {}

export type Def = ItemCatalog.BeltDef

AutomationLogic.Tag = "Belt"

-- Loose planks and boards one owner may have lying about before belts stop.
AutomationLogic.MaxLooseOutputs = 60

-- A piece untouched by any player for this long arrived by belt (or was
-- left there): the throughput cap applies. A piece a hand put in a moment
-- ago is hand work and is never capped.
AutomationLogic.HandWindow = 4

-- The bucket holds this many seconds of the machine's rate.
AutomationLogic.BucketSeconds = 10

-- Woods that only hand work may use (GAME_DESIGN §9 "the best things stay
-- hands-on"): Lumenwood and Phantomwood. Figured wood, Elder trees and
-- anything with a Lux tag are manual too (see Refusal).
AutomationLogic.ManualWoods = {
	phantomwood = true,
	lumenwood = true,
} :: { [string]: boolean }

function AutomationLogic.IsBelt(id: unknown): boolean
	if type(id) ~= "string" then
		return false
	end
	local machine = ItemCatalog.GetMachine(id)
	return machine ~= nil and machine.belt ~= nil
end

function AutomationLogic.Get(id: unknown): (ItemCatalog.MachineDef?, Def?)
	if type(id) ~= "string" then
		return nil, nil
	end
	local machine = ItemCatalog.GetMachine(id)
	if machine and machine.belt then
		return machine, machine.belt
	end
	return nil, nil
end

-- Whether opening this item's box starts a one-time placement ghost (the
-- sawmills, the planers and the belts) instead of going to the hammer's stock.
function AutomationLogic.PlacedFromBox(id: unknown): boolean
	if type(id) ~= "string" then
		return false
	end
	if ItemCatalog.GetSawmill(id) then
		return true
	end
	local machine = ItemCatalog.GetMachine(id)
	return machine ~= nil and machine.placeFromBox == true
end

function AutomationLogic.CountBelts(placed: { any }?): number
	local n = 0
	if type(placed) == "table" then
		for _, item in ipairs(placed) do
			if type(item) == "table" and AutomationLogic.IsBelt(item.blueprintId) then
				n += 1
			end
		end
	end
	return n
end

AutomationLogic.OnlyOwnerLine = "Only the plot's owner can put a belt down."

function AutomationLogic.CapLine(): string
	return string.format("A plot has room for %d belt pieces.", GameConfig.MaxConveyorsPerPlot)
end

-- Whether a placing is refused: planers and belts are the owner's, and
-- belts stop at the plot's cap. Anything else is not this module's call.
function AutomationLogic.PlaceRefusal(blueprintId: string, isOwner: boolean, placed: { any }?): string?
	local planer = PlanerLogic.PlaceRefusal(blueprintId, isOwner, placed)
	if planer then
		return planer
	end
	if not AutomationLogic.IsBelt(blueprintId) then
		return nil
	end
	if not isOwner then
		return AutomationLogic.OnlyOwnerLine
	end
	if AutomationLogic.CountBelts(placed) >= GameConfig.MaxConveyorsPerPlot then
		return AutomationLogic.CapLine()
	end
	return nil
end

-- A PlotLogic blueprint for a belt piece. One block over the footprint, low,
-- so a log can ride over it and a player walks across (the belt group does
-- not collide with players).
function AutomationLogic.Blueprint(id: string): PlotData.Blueprint?
	local machine, def = AutomationLogic.Get(id)
	if not machine or not def then
		return nil
	end
	local height = AutomationLogic.BoxHeight(def)
	return {
		id = machine.id,
		displayName = machine.displayName,
		category = "Machine",
		priceCash = machine.priceCash,
		tier = 1,
		footprint = Vector2.new(def.width, def.depth),
		boxes = {
			{
				size = Vector3.new(def.width, height, def.depth),
				offset = Vector3.new(0, height / 2, 0),
				color = machine.color,
				material = "Wood",
			},
		},
		note = AutomationLogic.Note(def.shape),
	}
end

function AutomationLogic.Note(shape: string): string
	if shape == "switch" then
		return "Sends wood out the left or the right. A wire picks the side."
	elseif shape == "tilted" then
		return "Carries wood up one step. Set the next belt on a Belt Support."
	elseif shape == "support" then
		return "Holds a belt one step up, level with a Tilted Belt's top."
	elseif shape == "detector" then
		return "A short belt that sends a signal when wood passes. Pick a wood to watch."
	end
	if shape == "turn" then
		return "Carries wood round a corner. Wood moves at the belt's speed."
	elseif shape == "funnel" then
		return "A wide mouth that narrows to a belt. Feed a mill from it."
	end
	return "Carries logs and planks along. Line it up with a mill's mouth."
end

-- The placement box height. A Belt Support is exactly one LIFT (2.0) tall,
-- so a belt set on it (y = 2.0) sits flush with a Tilted Belt's top end.
function AutomationLogic.BoxHeight(def: Def): number
	if def.shape == "support" then
		return AutomationLogic.Lift
	elseif def.shape == "tilted" then
		return 1.2 + (def.rise or AutomationLogic.Lift)
	end
	return 1.2
end

---------------------------------------------------------------------------
-- Lane W: belts and machines on wires (practical automation)
--
-- Ports (WireLogic reads these):
--   * every belt with a deck: 1 power, 2 reverse.
--   * Switch Belt: 1 side, 2 power, 3 reverse (a wire on 1 sends wood the
--     other way; the side is what a wire is for on this piece).
--   * sawmills and planers: 1 power.
--   * an unwired port runs as before: powered, forward, the default side.
-- The saved switches on the piece itself (item.reversed, item.flip) are
-- the owner's Reverse and Flip prompts. A wire on the reverse port flips
-- whatever the saved direction is.
---------------------------------------------------------------------------

AutomationLogic.Lift = 2.0 -- TLD-1 LIFT: Tilted Belt rise and Belt Support saddle
AutomationLogic.DeckTop = 0.72 -- TLD-1 deck top
AutomationLogic.PlateWidth = 6.0 -- TLD-1 base plate
AutomationLogic.Channel = 5.0 -- TLD-1 clear channel between the rails
AutomationLogic.RollerPitch = 1.0 -- TLD-1 roller pitch

export type Ports = { power: number?, reverse: number?, side: number? }

local NO_PORTS: Ports = {}
local BELT_PORTS: Ports = { power = 1, reverse = 2 }
local SWITCH_PORTS: Ports = { side = 1, power = 2, reverse = 3 }
local MACHINE_PORTS: Ports = { power = 1 }

-- Which input port does what on this piece. Empty for anything else.
function AutomationLogic.Ports(id: unknown): Ports
	if type(id) ~= "string" then
		return NO_PORTS
	end
	local _, def = AutomationLogic.Get(id)
	if def then
		if def.shape == "support" then
			return NO_PORTS
		elseif def.shape == "switch" then
			return SWITCH_PORTS
		end
		return BELT_PORTS
	end
	if ItemCatalog.GetSawmill(id) or PlanerLogic.IsPlaner(id) then
		return MACHINE_PORTS
	end
	return NO_PORTS
end

-- The input port numbers this piece has, low to high.
function AutomationLogic.InPorts(id: unknown): { number }
	local ports = AutomationLogic.Ports(id)
	local out: { number } = {}
	for _, port in ipairs({ ports.power, ports.reverse, ports.side }) do
		if port then
			table.insert(out, port)
		end
	end
	table.sort(out)
	return out
end

-- A wire target: belts with a deck, sawmills and planers.
function AutomationLogic.IsWireTarget(id: unknown): boolean
	return #AutomationLogic.InPorts(id) > 0
end

-- The owner's Reverse prompt is on every belt with a deck.
function AutomationLogic.CanReverse(id: unknown): boolean
	return AutomationLogic.Ports(id).reverse ~= nil
end

-- Flip mirrors the Switch Belt's diverter (GAD: no second texture). A turn
-- belt needs no flip: turned a quarter and reversed, it is the left turn.
function AutomationLogic.CanFlip(id: unknown): boolean
	local _, def = AutomationLogic.Get(id)
	return def ~= nil and def.shape == "switch"
end

-- Power: an unwired power port runs as it always did.
function AutomationLogic.Powered(wired: boolean, level: boolean): boolean
	return not wired or level
end

-- Direction: the owner's saved Reverse, flipped again while a wired
-- reverse input is on.
function AutomationLogic.Reversed(saved: boolean, wired: boolean, level: boolean): boolean
	local wireOn = wired and level
	return saved ~= wireOn
end

-- Switch Belt side: +1 sends wood to +X (the diverter as built), -1 to -X.
-- Flip mirrors the default; a wired side input that is on sends it the
-- other way.
function AutomationLogic.SwitchSide(flip: boolean, wired: boolean, level: boolean): number
	local side = if flip then -1 else 1
	if wired and level then
		side = -side
	end
	return side
end

-- The signed belt speed: 0 when off, negative when reversed.
function AutomationLogic.SignedSpeed(base: number, powered: boolean, reversed: boolean): number
	if not powered or base <= 0 then
		return 0
	end
	return if reversed then -base else base
end

-- A sawmill or planer runs unless a wire has turned its power off
-- (PowerIn is false only then; a machine nobody wired never has it).
function AutomationLogic.MachinePowered(powerIn: unknown): boolean
	return powerIn ~= false
end

-- Seconds a paused job's clock moves on when power returns.
function AutomationLogic.PauseShift(pausedAt: number, now: number): number
	if pausedAt ~= pausedAt or now ~= now then
		return 0
	end
	return math.max(0, now - pausedAt)
end

AutomationLogic.ReverseLine = "Belt reversed."
AutomationLogic.ForwardLine = "Belt runs forward."
AutomationLogic.FlipLine = "Switch flipped."
AutomationLogic.OwnerOnlyLine = "Only the plot's owner can change that belt."

---------------------------------------------------------------------------
-- Wood Detector filter. The index is a place in WoodData.All(), which is
-- append-only (a spec pins today's list), so a saved filter never shifts
-- to another wood. 0 watches every wood.
---------------------------------------------------------------------------

function AutomationLogic.FilterWoods(): { string }
	local out: { string } = {}
	for _, def in ipairs(WoodData.All()) do
		table.insert(out, def.id)
	end
	return out
end

function AutomationLogic.CleanFilter(value: unknown): number
	if type(value) ~= "number" or value ~= value or value ~= math.floor(value) then
		return 0
	end
	if value < 0 or value > #WoodData.All() then
		return 0
	end
	return value
end

function AutomationLogic.NextFilter(value: unknown): number
	local current = AutomationLogic.CleanFilter(value)
	local nextValue = current + 1
	if nextValue > #WoodData.All() then
		return 0
	end
	return nextValue
end

function AutomationLogic.FilterMatches(filter: unknown, woodId: unknown): boolean
	local index = AutomationLogic.CleanFilter(filter)
	if index == 0 then
		return true
	end
	local def = WoodData.All()[index]
	return def ~= nil and def.id == woodId
end

function AutomationLogic.FilterName(filter: unknown): string
	local index = AutomationLogic.CleanFilter(filter)
	if index == 0 then
		return "Any wood"
	end
	local def = WoodData.All()[index]
	return if def then def.displayName else "Any wood"
end

---------------------------------------------------------------------------
-- Wood Sweeper: a wire pulse pushes wood off the belt beside it.
---------------------------------------------------------------------------

AutomationLogic.SweepMax = 10 -- pieces one pulse may push (QA W5)
AutomationLogic.SweepSpeed = 14 -- studs/s, sideways
AutomationLogic.SweepLand = 5 -- studs: where a pushed piece is checked to land
AutomationLogic.SweepCooldown = 0.5 -- seconds between pulses that push

export type SweepCandidate = {
	key: any,
	held: boolean, -- HeldBy someone (QA W5: never moved)
	wood: boolean, -- a Wood piece (players and vehicles are never candidates)
	ownerId: number,
	landsOnPlot: boolean, -- would still be on its owner's plot after the push
}

-- Which pieces one pulse pushes: loose wood of the plot owner (or nobody's),
-- not held, that lands on the plot. At most SweepMax, in the order given.
function AutomationLogic.SweepPick(candidates: { SweepCandidate }, plotOwnerId: number): { any }
	local out: { any } = {}
	for _, c in ipairs(candidates) do
		if #out >= AutomationLogic.SweepMax then
			break
		end
		local ownerOk = c.ownerId == plotOwnerId or c.ownerId == 0
		if c.wood and not c.held and ownerOk and c.landsOnPlot then
			table.insert(out, c.key)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Laser pair: an emitter finds the receiver facing it on its own axis.
---------------------------------------------------------------------------

AutomationLogic.LaserRange = 40 -- studs, emitter port to receiver port
AutomationLogic.LaserAxisSlack = 1.0 -- studs off the emitter's axis
AutomationLogic.MaxLaserPairs = 8 -- emitters that run per plot (PROPOSAL; QA W10)
AutomationLogic.LaserHz = 5 -- server raycasts a second per emitter
AutomationLogic.BeamPortY = 1.92 -- TLD-1 BeamPort height
AutomationLogic.BeamPortZ = 0.72 -- emitter lens, local +Z
AutomationLogic.ReceiverPortZ = -0.64 -- receiver dish, local -Z

-- Distance along the emitter's beam to the receiver's port, or nil when the
-- receiver is not on the axis, faces the wrong way, or is out of range.
-- Directions are unit vectors in world space; ports are world positions.
function AutomationLogic.LaserReach(
	emitterPort: Vector3,
	emitterDir: Vector3,
	receiverPort: Vector3,
	receiverDir: Vector3
): number?
	local delta = receiverPort - emitterPort
	local along = delta:Dot(emitterDir)
	if along <= 0.05 or along > AutomationLogic.LaserRange then
		return nil
	end
	local off = (delta - emitterDir * along).Magnitude
	if off > AutomationLogic.LaserAxisSlack then
		return nil
	end
	-- The receiver's dish faces back along the beam.
	if receiverDir:Dot(emitterDir) > -0.7 then
		return nil
	end
	return along
end

---------------------------------------------------------------------------
-- When a belt runs
---------------------------------------------------------------------------

-- The speed a belt part should have (studs/s along its direction).
function AutomationLogic.BeltSpeed(ownerOnline: boolean, looseOutputs: number): number
	if not ownerOnline or looseOutputs >= AutomationLogic.MaxLooseOutputs then
		return 0
	end
	return GameConfig.ConveyorSpeed
end

---------------------------------------------------------------------------
-- What a machine takes off a belt
---------------------------------------------------------------------------

export type Facts = {
	automated: boolean, -- see IsAutomated
	woodId: string,
	figure: string?,
	elder: boolean?,
	lux: boolean?,
	pieceOwnerId: number,
	machineOwnerId: number,
	ownerOnline: boolean,
	looseOutputs: number,
}

export type Refusal = "offline" | "full" | "rare" | "notYours"

-- A piece untouched for HandWindow seconds is automated.
function AutomationLogic.IsAutomated(secondsSinceTouched: number): boolean
	return secondsSinceTouched == secondsSinceTouched and secondsSinceTouched >= AutomationLogic.HandWindow
end

-- Why automation won't take this piece, or nil. A hand-fed piece is never
-- refused here: these rules are for belts.
function AutomationLogic.Refusal(f: Facts): Refusal?
	if not f.automated then
		return nil
	end
	if not f.ownerOnline then
		return "offline"
	end
	if f.looseOutputs >= AutomationLogic.MaxLooseOutputs then
		return "full"
	end
	if AutomationLogic.ManualWoods[f.woodId] == true or f.figure ~= nil or f.elder == true or f.lux == true then
		return "rare"
	end
	if f.pieceOwnerId ~= f.machineOwnerId then
		return "notYours"
	end
	return nil
end

function AutomationLogic.RefusalLine(reason: string): string
	if reason == "rare" then
		return "Rare and figured wood only goes through by hand."
	elseif reason == "full" then
		return "Your plot is full of planks. Sell or load some and the line starts again."
	elseif reason == "notYours" then
		return "A belt only feeds its owner's own wood."
	end
	return "The line is off while its owner is away."
end

---------------------------------------------------------------------------
-- Throughput: a bucket per machine
---------------------------------------------------------------------------

-- A bucket refills at `rate` u³ a minute up to BucketSeconds of it, and a
-- piece may enter while it holds anything above 0; its volume is taken in
-- full, which can leave the bucket in debt. Long run: `rate`, however big the
-- pieces, and a piece bigger than the bucket is never starved out.
export type Bucket = { tokens: number, at: number, rate: number }

function AutomationLogic.Capacity(rate: number): number
	return math.max(0, rate) / 60 * AutomationLogic.BucketSeconds
end

function AutomationLogic.NewBucket(rate: number, now: number): Bucket
	return { tokens = AutomationLogic.Capacity(rate), at = now, rate = math.max(0, rate) }
end

function AutomationLogic.Refill(b: Bucket, now: number)
	local dt = now - b.at
	if dt > 0 then
		b.tokens = math.min(AutomationLogic.Capacity(b.rate), b.tokens + b.rate / 60 * dt)
		b.at = now
	end
end

function AutomationLogic.Ready(b: Bucket, now: number): boolean
	AutomationLogic.Refill(b, now)
	return b.tokens > 1e-9
end

function AutomationLogic.Take(b: Bucket, volumeU3: number, now: number)
	AutomationLogic.Refill(b, now)
	b.tokens -= math.max(0, volumeU3)
end

-- Seconds until a bucket is ready again (0 when it already is).
function AutomationLogic.WaitSeconds(b: Bucket, now: number): number
	AutomationLogic.Refill(b, now)
	if b.tokens > 1e-9 or b.rate <= 0 then
		return if b.rate <= 0 then math.huge else 0
	end
	return (1e-9 - b.tokens) / (b.rate / 60)
end

return AutomationLogic
