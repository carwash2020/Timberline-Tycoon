--!strict
-- StockIds: ids that wait in a player's stock (profile.sawmillStock) beside
-- the boxed sawmills and machines, and are spent when placed (free). Lane F.
--
--   furniture  the crafted pieces PlotService.GrantPiece hands out
--   logic      the Sparkworks pieces the counter sells (SparkworksStock): a
--              purchase puts one in stock, the same flow as a boxed machine
--
-- Pure and dependency-free so SawmillLogic (the client's stock decode),
-- BlueprintBook (what may be placed) and PlotService all agree. A spec keeps
-- the logic list equal to SparkworksStock's.

local FurnitureData = require(script.Parent.FurnitureData)

local StockIds = {}

StockIds.Logic = {
	"Button",
	"Lever",
	"PressurePlate",
	"SparkSwitch",
	"GateAnd",
	"GateOr",
	"GateXor",
	"GateNot",
	"Delay",
	"Sustain",
	"Clock",
	"SparkLamp",
	"GlowWire",
	"Hatch",
	"WoodSweeper",
	"LaserEmitter",
	"LaserReceiver",
} :: { string }

local LOGIC: { [string]: boolean } = {}
for _, id in ipairs(StockIds.Logic) do
	LOGIC[id] = true
end

function StockIds.IsLogic(id: unknown): boolean
	return type(id) == "string" and LOGIC[id] == true
end

function StockIds.IsFurniture(id: unknown): boolean
	return FurnitureData.IsGranted(id)
end

-- Any id that may sit in the stock list as a crafted or Sparkworks piece.
function StockIds.Has(id: unknown): boolean
	return StockIds.IsLogic(id) or FurnitureData.IsGranted(id)
end

return StockIds
