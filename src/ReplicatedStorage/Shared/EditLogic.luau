--!strict
-- EditLogic: rotate, move, resize, copy, delete, and undo for a kit ghost.
-- Pure. The server applies the cash delta and rebuilds models.
-- Wood locks a piece against edits. A copy is still allowed: it starts
-- empty and pays its own fee. Resizing changes only the fee difference.
-- woodUnits is never saved; it is worked out from the size.

local PieceSize = require(script.Parent.PieceSize)
local PlotData = require(script.Parent.PlotData)
local PlotLogic = require(script.Parent.PlotLogic)

local EditLogic = {}

EditLogic.UndoLimit = 10
EditLogic.MaxGroup = 20
EditLogic.GhostTransparency = 0.45

EditLogic.Reasons = {
	"owner",
	"missing",
	"filled",
	"rot",
	"grid",
	"len",
	"fixed",
	"overlap",
	"bounds",
	"cap",
	"cash",
	"group",
	"gone",
	"empty",
	"rate",
}

EditLogic.CanResize = PieceSize.CanResize
EditLogic.Tiled = PieceSize.Tiled
EditLogic.Tiles = PieceSize.Tiles
EditLogic.CleanLen = PieceSize.CleanLen
EditLogic.Units = PieceSize.Units
EditLogic.Fee = PieceSize.Fee
EditLogic.Shape = PieceSize.Shape
EditLogic.Step = PieceSize.Step

function EditLogic.Message(reason: string?): string?
	if reason == "owner" then
		return "That piece isn't on your plot."
	elseif reason == "missing" then
		return "That piece isn't there."
	elseif reason == "filled" then
		return "This piece already has wood in it."
	elseif reason == "rot" then
		return "Turn it by a quarter turn."
	elseif reason == "grid" then
		return "That spot isn't on the grid."
	elseif reason == "len" then
		return "That length isn't on the 2-stud grid."
	elseif reason == "fixed" then
		return "That piece doesn't resize."
	elseif reason == "overlap" then
		return "Something's in the way."
	elseif reason == "bounds" then
		return "That's outside your plot."
	elseif reason == "cap" then
		return string.format("Your plot holds %d kit pieces at most.", PlotData.MaxKit)
	elseif reason == "cash" then
		return "You don't have enough for that."
	elseif reason == "group" then
		return string.format("You can copy %d pieces at a time.", EditLogic.MaxGroup)
	elseif reason == "gone" then
		return "That edit can't be undone."
	elseif reason == "empty" then
		return "Nothing to undo."
	elseif reason == "rate" then
		return "Slow down a little."
	end
	return nil
end

export type Item = PlotLogic.Placed

export type World = {
	cash: number,
	tier: number,
	ownerId: number,
	playerId: number,
	placed: { Item },
	undo: { Entry },
	squares: { string }?, -- bought land squares (profile.plot.squares): they count as the plot
}

export type Entry = {
	kind: string,
	uid: string,
	before: Item?,
	cash: number,
	spawned: { Item }?,
}

function EditLogic.Locked(item: Item): boolean
	if item.wood ~= nil then
		return true
	end
	local fill = item.fill
	if fill == nil then
		return true
	end
	return fill.units ~= 0
end

function EditLogic.Readout(bp: PlotData.Blueprint, item: Item): string
	local units = EditLogic.Units(bp, item)
	local fee = units * PlotData.KitCashPerUnit
	local lenX, lenZ = PieceSize.Lengths(bp, item)
	if PieceSize.Floor(bp.id) then
		return string.format("%s %d×%d studs, $%d", bp.displayName, lenX, lenZ, fee)
	end
	return string.format("%s %d studs, $%d", bp.displayName, lenX, fee)
end

function EditLogic.GroupReadout(count: number, fee: number): string
	return string.format("%d of %d selected, $%d", count, EditLogic.MaxGroup, fee)
end

local function find(placed: { Item }, uid: string): (Item?, number)
	for i, item in ipairs(placed) do
		if item.uid == uid then
			return item, i
		end
	end
	return nil, 0
end

function EditLogic.Snapshot(item: Item): Item
	return {
		uid = item.uid,
		blueprintId = item.blueprintId,
		x = item.x,
		z = item.z,
		rot = item.rot,
		y = item.y,
		wood = item.wood,
		paint = item.paint,
		fill = if item.fill then { units = item.fill.units } else nil,
		paid = item.paid,
		len = item.len,
		lenX = item.lenX,
		lenZ = item.lenZ,
		data = item.data,
	}
end

local function remember(world: World, entry: Entry)
	table.insert(world.undo, entry)
	while #world.undo > EditLogic.UndoLimit do
		table.remove(world.undo, 1)
	end
end

local function onGrid(value: number): boolean
	return math.abs(value - PlotLogic.Snap(value)) < 1e-3
end

local function refuseCheck(ok: boolean, why: string?): (boolean, string?)
	if ok then
		return true, nil
	end
	if why == "Outside your plot" then
		return false, "bounds"
	end
	if why == "bad" then
		return false, "grid"
	end
	if type(why) == "string" and string.find(why, "kit pieces", 1, true) then
		return false, "cap"
	end
	return false, "overlap"
end

local function placeCheck(
	bp: PlotData.Blueprint,
	item: Item,
	tier: number,
	placed: { Item },
	ignore: string?,
	squares: { string }?
): (boolean, string?)
	local shaped = EditLogic.Shape(bp, item)
	local ok, why = PlotLogic.Check(shaped, item.x, item.z, item.rot, tier, placed, ignore, item.y or 0, squares)
	return refuseCheck(ok, why)
end

local function owned(world: World, uid: string): (Item?, string?)
	if world.playerId ~= world.ownerId then
		return nil, "owner"
	end
	local item = find(world.placed, uid)
	if not item then
		return nil, "missing"
	end
	return item, nil
end

local function applyCash(world: World, delta: number): (boolean, string?)
	if delta < 0 and world.cash + delta < -1e-6 then
		return false, "cash"
	end
	world.cash += delta
	return true, nil
end

function EditLogic.Run(world: World, request: { [string]: any }, newUid: () -> string): (boolean, string?)
	local op = request.op
	if op == "undo" then
		return EditLogic.Undo(world)
	end
	local uid = request.uid
	if op == "copy" then
		return EditLogic.Copy(world, request, newUid)
	end
	if type(uid) ~= "string" then
		return false, "missing"
	end
	local item, why = owned(world, uid)
	if not item then
		return false, why
	end
	if EditLogic.Locked(item) then
		return false, "filled"
	end
	local bp = PlotLogic.Blueprint(item.blueprintId)
	if not bp or bp.kit ~= true then
		return false, "fixed"
	end
	if op == "rotate" then
		local rot = request.rot
		if type(rot) ~= "number" or rot ~= math.floor(rot) or rot < 0 or rot > 3 then
			return false, "rot"
		end
		local nextItem = EditLogic.Snapshot(item)
		nextItem.rot = rot
		local ok, code = placeCheck(bp, nextItem, world.tier, world.placed, item.uid, world.squares)
		if not ok then
			return false, code
		end
		local before = EditLogic.Snapshot(item)
		item.rot = rot
		remember(world, { kind = "rotate", uid = item.uid, before = before, cash = 0 })
		return true, nil
	elseif op == "move" then
		local x, z = request.x, request.z
		if type(x) ~= "number" or type(z) ~= "number" or not onGrid(x) or not onGrid(z) then
			return false, "grid"
		end
		local y = if type(request.y) == "number" then request.y else (item.y or 0)
		if not PlotLogic.HeightOk(y) then
			return false, "grid"
		end
		local rot = if type(request.rot) == "number" then request.rot else item.rot
		if rot ~= math.floor(rot) or rot < 0 or rot > 3 then
			return false, "rot"
		end
		local nextItem = EditLogic.Snapshot(item)
		nextItem.x, nextItem.z, nextItem.rot = x, z, rot
		nextItem.y = if y ~= 0 then y else nil
		local ok, code = placeCheck(bp, nextItem, world.tier, world.placed, item.uid, world.squares)
		if not ok then
			return false, code
		end
		local before = EditLogic.Snapshot(item)
		item.x, item.z, item.rot = x, z, rot
		item.y = if y ~= 0 then y else nil
		remember(world, { kind = "move", uid = item.uid, before = before, cash = 0 })
		return true, nil
	elseif op == "resize" then
		if not EditLogic.CanResize(bp.id) then
			return false, "fixed"
		end
		local nextItem = EditLogic.Snapshot(item)
		if PieceSize.Floor(bp.id) then
			local lenX = request.lenX
			local lenZ = request.lenZ
			if type(lenX) ~= "number" or type(lenZ) ~= "number" then
				return false, "len"
			end
			if not PieceSize.LengthOk(bp.footprint.X, lenX) or not PieceSize.LengthOk(bp.footprint.Y, lenZ) then
				return false, "len"
			end
			nextItem.lenX = if math.abs(lenX - bp.footprint.X) < 1e-3 then nil else lenX
			nextItem.lenZ = if math.abs(lenZ - bp.footprint.Y) < 1e-3 then nil else lenZ
		else
			local len = request.len
			if type(len) ~= "number" or not PieceSize.LengthOk(bp.footprint.X, len) then
				return false, "len"
			end
			nextItem.len = if math.abs(len - bp.footprint.X) < 1e-3 then nil else len
		end
		local oldFee = if type(item.paid) == "number" then item.paid else EditLogic.Fee(bp, item)
		local newFee = EditLogic.Fee(bp, nextItem)
		local delta = oldFee - newFee
		if delta < 0 and world.cash + delta < -1e-6 then
			return false, "cash"
		end
		local ok, code = placeCheck(bp, nextItem, world.tier, world.placed, item.uid, world.squares)
		if not ok then
			return false, code
		end
		local paidOk = applyCash(world, delta)
		if not paidOk then
			return false, "cash"
		end
		local before = EditLogic.Snapshot(item)
		item.len, item.lenX, item.lenZ = nextItem.len, nextItem.lenX, nextItem.lenZ
		item.paid = newFee
		remember(world, { kind = "resize", uid = item.uid, before = before, cash = delta })
		return true, nil
	elseif op == "delete" then
		local _, index = find(world.placed, item.uid)
		local refund = if type(item.paid) == "number" then item.paid else EditLogic.Fee(bp, item)
		local before = EditLogic.Snapshot(item)
		table.remove(world.placed, index)
		applyCash(world, refund)
		remember(world, { kind = "delete", uid = item.uid, before = before, cash = refund })
		return true, nil
	end
	return false, "missing"
end

function EditLogic.Copy(world: World, request: { [string]: any }, newUid: () -> string): (boolean, string?)
	if world.playerId ~= world.ownerId then
		return false, "owner"
	end
	local uids = request.uids
	if type(uids) ~= "table" or #uids < 1 then
		return false, "missing"
	end
	if #uids > EditLogic.MaxGroup then
		return false, "group"
	end
	local dx, dz = request.dx, request.dz
	if type(dx) ~= "number" or type(dz) ~= "number" or not onGrid(dx) or not onGrid(dz) then
		return false, "grid"
	end
	local working = table.clone(world.placed)
	local spawned: { Item } = {}
	local total = 0
	for _, uid in ipairs(uids) do
		if type(uid) ~= "string" then
			return false, "missing"
		end
		local src = find(world.placed, uid)
		if not src then
			return false, "missing"
		end
		-- Filled pieces can be copied. The lock blocks editing the source.
		local bp = PlotLogic.Blueprint(src.blueprintId)
		if not bp or bp.kit ~= true then
			return false, "fixed"
		end
		local copy = EditLogic.Snapshot(src)
		copy.uid = newUid()
		copy.x += dx
		copy.z += dz
		copy.wood = nil
		copy.fill = { units = 0 }
		copy.data = nil
		local fee = EditLogic.Fee(bp, copy)
		copy.paid = fee
		total += fee
		local ok, code = placeCheck(bp, copy, world.tier, working, nil, world.squares)
		if not ok then
			return false, code
		end
		table.insert(working, copy)
		table.insert(spawned, copy)
	end
	if world.cash < total then
		return false, "cash"
	end
	local first = spawned[1]
	if not first then
		return false, "missing"
	end
	world.placed = working
	applyCash(world, -total)
	remember(world, {
		kind = "copy",
		uid = first.uid,
		cash = -total,
		spawned = spawned,
	})
	return true, nil
end

function EditLogic.Undo(world: World): (boolean, string?)
	if world.playerId ~= world.ownerId then
		return false, "owner"
	end
	local entry = world.undo[#world.undo]
	if not entry then
		return false, "empty"
	end
	table.remove(world.undo)
	if entry.kind == "copy" then
		local spawned = entry.spawned or {}
		for _, made in ipairs(spawned) do
			local live = find(world.placed, made.uid)
			if not live or EditLogic.Locked(live) then
				return false, "gone"
			end
		end
		for _, made in ipairs(spawned) do
			local _, index = find(world.placed, made.uid)
			if index > 0 then
				table.remove(world.placed, index)
			end
		end
		applyCash(world, -entry.cash)
		return true, nil
	end
	local before = entry.before
	if not before then
		return false, "gone"
	end
	if entry.kind == "delete" then
		local bp = PlotLogic.Blueprint(before.blueprintId)
		if not bp then
			return false, "gone"
		end
		local ok, code = placeCheck(bp, before, world.tier, world.placed, nil, world.squares)
		if not ok then
			table.insert(world.undo, entry)
			return false, code
		end
		if world.cash + -entry.cash < -1e-6 then
			table.insert(world.undo, entry)
			return false, "cash"
		end
		table.insert(world.placed, EditLogic.Snapshot(before))
		applyCash(world, -entry.cash)
		return true, nil
	end
	local live, index = find(world.placed, entry.uid)
	if not live or EditLogic.Locked(live) then
		return false, "gone"
	end
	local bp = PlotLogic.Blueprint(before.blueprintId)
	if not bp then
		return false, "gone"
	end
	local ok, code = placeCheck(bp, before, world.tier, world.placed, live.uid, world.squares)
	if not ok then
		table.insert(world.undo, entry)
		return false, code
	end
	if world.cash + -entry.cash < -1e-6 then
		table.insert(world.undo, entry)
		return false, "cash"
	end
	world.placed[index] = EditLogic.Snapshot(before)
	applyCash(world, -entry.cash)
	return true, nil
end

return EditLogic
