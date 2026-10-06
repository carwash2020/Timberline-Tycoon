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
	return {
		id = machine.id,
		displayName = machine.displayName,
		category = "Machine",
		priceCash = machine.priceCash,
		tier = 1,
		footprint = Vector2.new(def.width, def.depth),
		boxes = {
			{
				size = Vector3.new(def.width, 1.2, def.depth),
				offset = Vector3.new(0, 0.6, 0),
				color = machine.color,
				material = "Wood",
			},
		},
		note = AutomationLogic.Note(def.shape),
	}
end

function AutomationLogic.Note(shape: string): string
	if shape == "turn" then
		return "Carries wood round a corner. Wood moves at the belt's speed."
	elseif shape == "funnel" then
		return "A wide mouth that narrows to a belt. Feed a mill from it."
	end
	return "Carries logs and planks along. Line it up with a mill's mouth."
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
