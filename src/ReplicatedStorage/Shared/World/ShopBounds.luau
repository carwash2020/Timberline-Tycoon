--!strict
-- ShopBounds: the walk a shop offers, measured on the built model.
-- The door, the aisle from that door, and the shoulders beside it.
-- ShopFit stamps an AisleClear when the shell has no computed walk long
-- enough; the big stores already have the gap, so this only measures them.

local Clearance = require(script.Parent.Clearance)

local ShopBounds = {}

export type Box = {
	name: string,
	cf: CFrame,
	size: Vector3,
}

ShopBounds.AisleMin = 8
ShopBounds.DoorMinW = 8
ShopBounds.DoorMinH = 10
ShopBounds.Shoulder = 3
ShopBounds.WalkMin = 6

local function findPart(model: Model, name: string): BasePart?
	local inst = model:FindFirstChild(name, true)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

function ShopBounds.Door(model: Model): Box?
	local part = findPart(model, "DoorBlock") or findPart(model, "DoorOpening")
	if part == nil then
		return nil
	end
	return { name = part.Name, cf = part.CFrame, size = part.Size }
end

-- An aisle part, if the shell placed one that is already wide and long.
function ShopBounds.Marked(model: Model): Box?
	for _, d in ipairs(model:GetDescendants()) do
		if
			d:IsA("BasePart")
			and d.Name == "AisleClear"
			and d.Size.X >= ShopBounds.AisleMin
			and d.Size.Z >= ShopBounds.WalkMin
		then
			return { name = "AisleClear", cf = d.CFrame, size = d.Size }
		end
	end
	return nil
end

-- The customer walk: the marked aisle, or an 8-wide box from the door's
-- inside face to the counter (or 8 studs past the door when the counter
-- stands to one side). Width is X, length is Z. Nil when the shop has
-- neither a door nor a counter.
function ShopBounds.Walk(model: Model): Box?
	local marked = ShopBounds.Marked(model)
	if marked then
		return marked
	end
	local door = findPart(model, "DoorBlock") or findPart(model, "DoorOpening")
	local counter = model:FindFirstChild("Counter")
	if door == nil or counter == nil or not counter:IsA("BasePart") then
		return nil
	end
	local doorAt, counterAt = door.CFrame.Position, counter.CFrame.Position
	local dir = if counterAt.Z >= doorAt.Z then 1 else -1
	local z0 = doorAt.Z + dir * (door.Size.Z / 2 + 0.02)
	local beside = math.abs(counterAt.X - doorAt.X) > door.Size.X * 0.5
	local z1 = if beside then z0 + dir * 8 else counterAt.Z - dir * (counter.Size.Z / 2 + 0.02)
	local length = (z1 - z0) * dir
	if length < 1 then
		return nil
	end
	-- Shorten from the far end until the box is free of solids, staying at
	-- least WalkMin long. A reception desk or an event post ends the walk;
	-- it does not erase the clear run from the door.
	local zFar = z1
	local guard = 0
	while guard < 80 do
		local span = (zFar - z0) * dir
		if span < ShopBounds.WalkMin - 1e-3 then
			break
		end
		local box: Box = {
			name = "Walk",
			cf = CFrame.new(doorAt.X, 3.6, (z0 + zFar) / 2),
			size = Vector3.new(ShopBounds.AisleMin, 3.2, span),
		}
		if #ShopBounds.Hits(model, box, nil) == 0 then
			return box
		end
		zFar -= dir * 1.5
		guard += 1
	end
	return {
		name = "Walk",
		cf = CFrame.new(doorAt.X, 3.6, (z0 + z1) / 2),
		size = Vector3.new(ShopBounds.AisleMin, 3.2, length),
	}
end

-- Three studs beside an 8-wide opening (the door box), outside the shop
-- (away from `inside`). A wider door already contains that margin.
function ShopBounds.Shoulders(door: Box, insideZ: number, studs: number): { Box }
	local dir = if insideZ >= door.cf.Position.Z then -1 else 1
	local y = door.cf.Position.Y
	local h = math.min(door.size.Y, 8)
	local half = ShopBounds.DoorMinW / 2
	local boxes: { Box } = {}
	for _, side in ipairs({ -1, 1 }) do
		table.insert(boxes, {
			name = "Shoulder",
			cf = CFrame.new(
				door.cf.Position.X + side * (half + studs / 2),
				y,
				door.cf.Position.Z + dir * (door.size.Z / 2 + studs / 2)
			),
			size = Vector3.new(studs, h, studs),
		})
	end
	return boxes
end

function ShopBounds.Hits(model: Model, box: Box, skip: { [string]: boolean }?): { BasePart }
	local shape = Clearance.Box(box.cf, box.size)
	local out: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide and not (skip and skip[d.Name]) then
			if Clearance.BoxDepth(shape, Clearance.Box(d.CFrame, d.Size)) > 0.05 then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- How far `item`'s bottom sits above `support`'s top. Negative sinks in.
function ShopBounds.RestGap(item: BasePart, support: BasePart): number
	local bottom = item.CFrame.Position.Y - item.Size.Y / 2
	local top = support.CFrame.Position.Y + support.Size.Y / 2
	return bottom - top
end

-- The smallest axis overlap. 0 when the parts only touch or miss.
function ShopBounds.Penetration(a: BasePart, b: BasePart): number
	local ap, bp = a.CFrame.Position, b.CFrame.Position
	local ox = (a.Size.X + b.Size.X) / 2 - math.abs(ap.X - bp.X)
	local oy = (a.Size.Y + b.Size.Y) / 2 - math.abs(ap.Y - bp.Y)
	local oz = (a.Size.Z + b.Size.Z) / 2 - math.abs(ap.Z - bp.Z)
	if ox <= 0 or oy <= 0 or oz <= 0 then
		return 0
	end
	return math.min(ox, oy, oz)
end

return ShopBounds
