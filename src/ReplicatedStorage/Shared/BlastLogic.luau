--!strict
-- BlastLogic: the blasting charge on a cracked boulder. Pure. BlastService
-- does the spending, the fuse and the pieces. WORLD_DESIGN §11 and §15.
--
-- A charge costs GameConfig.DynamitePrice, paid at the boulder (there is no
-- carried item: ItemCatalog is gated). The fuse is FuseSec. The explosion
-- is looks only (BlastPressure 0, no joints broken). After
-- GameConfig.BoulderRespawnSec the boulder comes back, but only when its box
-- is empty of people and trucks; if it is not, the server waits RetrySec
-- and asks again.

local GameConfig = require(script.Parent.GameConfig)
local Util = require(script.Parent.Util)

local BlastLogic = {}

BlastLogic.FuseSec = 5
BlastLogic.RetrySec = 10
BlastLogic.PlaceRange = 16 -- studs from the boulder a charge can be set (the prompt reaches 10)
BlastLogic.PromptRange = 10
BlastLogic.BlastRadius = 14 -- the explosion's look
BlastLogic.BoxPad = 2 -- studs added around a boulder's box when checking it is clear

export type Point = { x: number, y: number, z: number }

function BlastLogic.Price(): number
	return GameConfig.DynamitePrice
end

-- True when `point` sits inside the box centred at `centre` with edge
-- lengths `size`, grown by BoxPad on every side.
function BlastLogic.Overlaps(centre: Point, size: Point, point: Point): boolean
	local pad = BlastLogic.BoxPad
	return math.abs(point.x - centre.x) <= size.x / 2 + pad
		and math.abs(point.y - centre.y) <= size.y / 2 + pad
		and math.abs(point.z - centre.z) <= size.z / 2 + pad
end

-- Whether any of `points` (a character's root, a truck's parts) is in the
-- box. The boulder only returns when this is false.
function BlastLogic.Blocked(centre: Point, size: Point, points: { Point }): boolean
	for _, point in ipairs(points) do
		if BlastLogic.Overlaps(centre, size, point) then
			return true
		end
	end
	return false
end

-- Seconds to wait before the next respawn attempt: the full respawn time
-- the first time (attempt 0), then RetrySec while the box stays blocked.
function BlastLogic.Delay(attempt: number): number
	if attempt <= 0 then
		return GameConfig.BoulderRespawnSec
	end
	return BlastLogic.RetrySec
end

-- Can a player at `distance` studs set a charge?
function BlastLogic.InRange(distance: number): boolean
	return distance <= BlastLogic.PlaceRange
end

function BlastLogic.ActionText(): string
	return string.format("Set a blasting charge (%s)", Util.formatCash(GameConfig.DynamitePrice))
end

function BlastLogic.ShortText(): string
	return string.format("A blasting charge costs %s.", Util.formatCash(GameConfig.DynamitePrice))
end

function BlastLogic.FuseText(): string
	return string.format("Fuse lit. Stand back: %d seconds.", BlastLogic.FuseSec)
end

function BlastLogic.BusyText(): string
	return "That boulder already has a charge."
end

return BlastLogic
