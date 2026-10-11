--!strict
-- PlotFill: turn a loose plank into units on a kit blueprint. The plank is
-- destroyed before the units are counted. Two touches in one step, or two
-- blueprints grabbing one plank, count once. Leftover volume is spawned
-- back as a plank before the original is destroyed, so a failed spawn
-- leaves the plank where it was.

local BuildCost = require(game:GetService("ReplicatedStorage").Shared.BuildCost)
local FillLogic = require(game:GetService("ReplicatedStorage").Shared.FillLogic)
local PlotData = require(game:GetService("ReplicatedStorage").Shared.PlotData)
local PlotLogic = require(game:GetService("ReplicatedStorage").Shared.PlotLogic)

local PlotFill = {}

export type Piece = FillLogic.Offer & {
	cf: CFrame,
	figure: string?,
	boost: number?,
	lux: boolean?,
	mill: number?,
	board: number?,
	temper: number?,
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
	local need = BuildCost.Need(bp, item).units
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
			mill = piece.mill,
			board = piece.board,
			temper = piece.temper,
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
	if BuildCost.IsComplete(bp, item) then
		item.fill = nil
	end
	busyWood[piece.uid] = nil
	busyItem[item.uid] = nil
	return true, nil
end

export type MaterialApi = {
	-- Destroys the slab or ingot. False when it was already gone (another
	-- fill took it first). Must not yield.
	Take: (uid: string) -> boolean,
}

-- Applies one slab or ingot to `item`. The part is destroyed first, with no
-- yield between the check and the take, and only then counted: two touches
-- in one step, or two ghosts grabbing one part, count once (QA BL2). A
-- refusal takes nothing. Returns whether the piece changed.
function PlotFill.ApplyMaterial(
	item: PlotLogic.Placed,
	offer: FillLogic.Material,
	ownerId: number,
	api: MaterialApi
): (boolean, string?)
	local bp = PlotLogic.Blueprint(item.blueprintId)
	if not bp or bp.kit ~= true or not item.fill then
		return false, "built"
	end
	if busyWood[offer.uid] or busyItem[item.uid] then
		return false, "busy"
	end
	local need = BuildCost.Need(bp, item)
	local missing = BuildCost.Missing(bp, item)
	local ok, why = FillLogic.AcceptMaterial(need, missing, offer, ownerId)
	if not ok then
		return false, why
	end
	busyWood[offer.uid] = true
	busyItem[item.uid] = true
	local taken = api.Take(offer.uid)
	if taken ~= true then
		busyWood[offer.uid] = nil
		busyItem[item.uid] = nil
		return false, "gone"
	end
	local fill = item.fill :: BuildCost.Fill
	if offer.kind == "slab" then
		fill.slabs = (fill.slabs or 0) + 1
	else
		local ore = offer.ore :: string
		local ingots = fill.ingots or {}
		ingots[ore] = (ingots[ore] or 0) + 1
		fill.ingots = ingots
	end
	if BuildCost.IsComplete(bp, item) then
		item.fill = nil
	end
	busyWood[offer.uid] = nil
	busyItem[item.uid] = nil
	return true, nil
end

-- The fee written onto a new kit piece. Exposed so a test can match it.
function PlotFill.Fee(bp: PlotData.Blueprint): number
	return PlotData.Price(bp)
end

return PlotFill
