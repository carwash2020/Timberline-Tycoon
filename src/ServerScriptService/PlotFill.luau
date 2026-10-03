--!strict
-- PlotFill: turn a loose plank into units on a kit blueprint. The plank is
-- destroyed before the units are counted. Two touches in one step, or two
-- blueprints grabbing one plank, count once. Leftover volume is spawned
-- back as a plank before the original is destroyed, so a failed spawn
-- leaves the plank where it was.

local FillLogic = require(game:GetService("ReplicatedStorage").Shared.FillLogic)
local PlotData = require(game:GetService("ReplicatedStorage").Shared.PlotData)
local PlotLogic = require(game:GetService("ReplicatedStorage").Shared.PlotLogic)

local PlotFill = {}

export type Piece = FillLogic.Offer & {
	cf: CFrame,
	figure: string?,
	boost: number?,
	lux: boolean?,
}

export type Api = {
	Get: (uid: string) -> any,
	Remove: (piece: any, reason: string) -> (),
	SpawnPlank: (info: any) -> any,
}

local busyWood: { [string]: boolean } = {}
local busyItem: { [string]: boolean } = {}

function PlotFill.Reset()
	table.clear(busyWood)
	table.clear(busyItem)
end

-- Applies `piece` to `item`. Returns whether the blueprint changed.
function PlotFill.Apply(item: PlotLogic.Placed, piece: Piece, ownerId: number, api: Api): (boolean, string?)
	local bp = PlotLogic.Blueprint(item.blueprintId)
	if not bp or bp.kit ~= true or not item.fill then
		return false, "built"
	end
	if busyWood[piece.uid] or busyItem[item.uid] then
		return false, "busy"
	end
	if api.Get(piece.uid) == nil then
		return false, "gone"
	end
	local need = bp.woodUnits or 0
	local ok, why = FillLogic.Accept(item.wood, item.fill.units, need, piece, ownerId)
	if not ok then
		return false, why
	end
	local take, left = FillLogic.Take(item.fill.units, need, piece.volume)
	if take <= 0 then
		return false, "empty"
	end
	busyWood[piece.uid] = true
	busyItem[item.uid] = true
	local spawned: any = nil
	if left > 1e-4 then
		spawned = api.SpawnPlank({
			woodId = piece.woodId,
			size = FillLogic.LeftoverSize(piece.size, left, piece.volume),
			cf = piece.cf,
			ownerId = piece.ownerId,
			figure = piece.figure,
			boost = piece.boost,
			lux = piece.lux,
		})
		if spawned == nil then
			busyWood[piece.uid] = nil
			busyItem[item.uid] = nil
			return false, "excess"
		end
	end
	api.Remove(piece, "blueprint")
	if api.Get(piece.uid) ~= nil then
		if spawned and spawned.uid then
			local back = api.Get(spawned.uid)
			if back then
				api.Remove(back, "blueprint")
			end
		end
		busyWood[piece.uid] = nil
		busyItem[item.uid] = nil
		return false, "remove"
	end
	if item.wood == nil then
		item.wood = piece.woodId
	end
	item.fill.units += take
	if item.fill.units >= need then
		item.fill = nil
	end
	busyWood[piece.uid] = nil
	busyItem[item.uid] = nil
	return true, nil
end

-- The fee written onto a new kit piece. Exposed so a test can match it.
function PlotFill.Fee(bp: PlotData.Blueprint): number
	return PlotData.Price(bp)
end

return PlotFill
