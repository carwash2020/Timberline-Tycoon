--!strict
-- FerryLogic: Cap'n Moss's ferry. Pure; FerryService is the only caller that
-- moves anything. WORLD_DESIGN §1, §11 and §15.
--
-- One boat, one clock (the server's). Every GameConfig.FerryIntervalSec
-- (360 s) it leaves the mainland dock for Ferry Island, and half a cycle
-- later it leaves the island for the mainland, so each dock sees a
-- departure every 6 minutes. A crossing takes TravelSec. The fare
-- (GameConfig.FerryFare) is charged per rider aboard at departure, never
-- before, so someone who steps off in time pays nothing.

local GameConfig = require(script.Parent.GameConfig)
local Util = require(script.Parent.Util)
local WorldLayout = require(script.Parent.World.WorldLayout)

local FerryLogic = {}

-- Dock is "main" or "island"; Leg is "main", "toIsland", "island" or "toMain".
export type Dock = string
export type Leg = string
export type State = {
	leg: Leg,
	alpha: number, -- 0 at the mainland dock, 1 at the island dock
	docked: Dock?, -- which dock the boat is tied up at, nil while sailing
}

FerryLogic.TravelSec = 40
-- Boarding shuts this many seconds before the boat leaves, so a rider is
-- never stepped on in the last second.
FerryLogic.BoardCloseSec = 3
-- Studs from a dock's deck a player may be and still board (the prompt
-- reaches PromptRange; the rest is slack for the server's view).
FerryLogic.PromptRange = 12
FerryLogic.BoardRange = 18
-- The boat's deck, studs (width across the boat, length along it), and the
-- water gap between a dock's deck centre and the boat's centre.
FerryLogic.DeckWidth = 14
FerryLogic.DeckLength = 22
FerryLogic.BerthGap = 20
-- The island berth sits this far past the island's edge, out in the water.
FerryLogic.IslandBerthOut = 16
-- The deck's centre sits this far above the sea surface.
FerryLogic.DeckRise = 0.5
-- A rider stands this far above the deck's top when placed.
FerryLogic.StandHeight = 4
-- How far past the deck's edge still counts as aboard (studs), and how
-- high above the deck.
FerryLogic.AboardPad = 1
FerryLogic.AboardHeight = 12

local function ease(a: number): number
	local x = math.clamp(a, 0, 1)
	return x * x * (3 - 2 * x)
end

-- The two berths (deck centres, world XZ): the mainland one a BerthGap off
-- the dock toward the island, the island one IslandBerthOut past the
-- island's shore on the mainland side.
function FerryLogic.Berths(): { main: { x: number, z: number }, island: { x: number, z: number } }
	local dock = WorldLayout.FerryDock
	local island = WorldLayout.Island
	local dx, dz = island.x - dock.x, island.z - dock.z
	local len = math.sqrt(dx * dx + dz * dz)
	local fx, fz = WorldLayout.FerryFacing()
	local reach = island.radius + FerryLogic.IslandBerthOut
	return {
		main = { x = dock.x + dx / len * FerryLogic.BerthGap, z = dock.z + dz / len * FerryLogic.BerthGap },
		island = { x = island.x + fx * reach, z = island.z + fz * reach },
	}
end

-- Where the boat sits for a state: world X, Z and yaw (radians, the bow, local
-- -Z, toward where it is going; it turns round while tied up at the island).
function FerryLogic.Pose(state: State): (number, number, number)
	local berths = FerryLogic.Berths()
	local a, b = berths.main, berths.island
	local x = a.x + (b.x - a.x) * state.alpha
	local z = a.z + (b.z - a.z) * state.alpha
	local outYaw = math.atan2(a.x - b.x, a.z - b.z)
	local heading = if state.leg == "main" or state.leg == "toIsland" then outYaw else outYaw + math.pi
	return x, z, heading
end

function FerryLogic.Cycle(): number
	return GameConfig.FerryIntervalSec
end

-- Where the boat is at server time `now`.
function FerryLogic.State(now: number): State
	local cycle = FerryLogic.Cycle()
	local half = cycle / 2
	local travel = FerryLogic.TravelSec
	local phase = now % cycle
	if phase < travel then
		return { leg = "toIsland", alpha = ease(phase / travel), docked = nil }
	elseif phase < half then
		return { leg = "island", alpha = 1, docked = "island" }
	elseif phase < half + travel then
		return { leg = "toMain", alpha = 1 - ease((phase - half) / travel), docked = nil }
	end
	return { leg = "main", alpha = 0, docked = "main" }
end

-- Seconds until the boat next leaves `dock`. 0 when it is leaving this
-- instant.
function FerryLogic.SecondsToDeparture(now: number, dock: Dock): number
	local cycle = FerryLogic.Cycle()
	local at = if dock == "main" then 0 else cycle / 2
	return (at - now) % cycle
end

-- Can someone board at `dock` right now? The boat has to be tied up there
-- and not about to go.
function FerryLogic.CanBoard(now: number, dock: Dock): boolean
	local state = FerryLogic.State(now)
	if state.docked ~= dock then
		return false
	end
	return FerryLogic.SecondsToDeparture(now, dock) > FerryLogic.BoardCloseSec
end

-- The dock a docked boat just left, when the leg we saw last tick was
-- docked and this tick's is sailing.
function FerryLogic.Departed(prev: Leg?, now: Leg): Dock?
	if prev == "main" and now == "toIsland" then
		return "main"
	elseif prev == "island" and now == "toMain" then
		return "island"
	end
	return nil
end

-- The dock a sailing boat just reached.
function FerryLogic.Arrived(prev: Leg?, now: Leg): Dock?
	if prev == "toIsland" and now == "island" then
		return "island"
	elseif prev == "toMain" and now == "main" then
		return "main"
	end
	return nil
end

-- "2:41", rounding up so the last second never reads 0:00 before it goes.
function FerryLogic.Clock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- Where on the deck rider number `i` (1-based) stands: a grid of 3 columns
-- 4 studs apart, filling the deck from the bow, wrapping if it fills. Local
-- X and Z from the deck's centre.
function FerryLogic.Slot(i: number): (number, number)
	local columns = 3
	local spacing = 4
	local index = (i - 1) % (columns * math.floor((FerryLogic.DeckLength - 4) / spacing))
	local col = index % columns
	local row = index // columns
	local x = (col - 1) * spacing
	local z = -FerryLogic.DeckLength / 2 + 3 + row * spacing
	return x, z
end

-- Is a point (given in the deck's local space, studs from its centre, y
-- above the deck's centre) aboard?
function FerryLogic.Aboard(localX: number, localY: number, localZ: number): boolean
	local pad = FerryLogic.AboardPad
	return math.abs(localX) <= FerryLogic.DeckWidth / 2 + pad
		and math.abs(localZ) <= FerryLogic.DeckLength / 2 + pad
		and localY >= -2
		and localY <= FerryLogic.AboardHeight
end

-- The texts.
function FerryLogic.ObjectText(now: number, dock: Dock): string
	local state = FerryLogic.State(now)
	if state.docked == dock then
		local secs = FerryLogic.SecondsToDeparture(now, dock)
		if secs <= FerryLogic.BoardCloseSec then
			return "Cap'n Moss's ferry (casting off)"
		end
		return "Cap'n Moss's ferry (leaves in " .. FerryLogic.Clock(secs) .. ")"
	end
	return "Cap'n Moss's ferry (back in " .. FerryLogic.Clock(FerryLogic.SecondsToDeparture(now, dock)) .. ")"
end

function FerryLogic.ActionText(): string
	return string.format("Board (%s)", Util.formatCash(GameConfig.FerryFare))
end

function FerryLogic.ShortText(): string
	return string.format("A ferry ride costs %s.", Util.formatCash(GameConfig.FerryFare))
end

function FerryLogic.TruckText(): string
	return "No trucks on the ferry. Hop out and board on foot."
end

function FerryLogic.AwayText(now: number, dock: Dock): string
	return "The ferry is out. It is back in " .. FerryLogic.Clock(FerryLogic.SecondsToDeparture(now, dock)) .. "."
end

function FerryLogic.AboardText(now: number, dock: Dock): string
	return string.format(
		"Stay on deck. The ferry leaves in %s (%s per rider).",
		FerryLogic.Clock(FerryLogic.SecondsToDeparture(now, dock)),
		Util.formatCash(GameConfig.FerryFare)
	)
end

function FerryLogic.PaidText(): string
	return string.format("%s paid. Hold on, the ferry is off.", Util.formatCash(GameConfig.FerryFare))
end

return FerryLogic
