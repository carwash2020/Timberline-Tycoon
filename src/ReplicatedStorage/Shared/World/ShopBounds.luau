--!strict
-- ShopBounds: the walk a shop offers, measured on the built model in the
-- door's own frame. A turned shop measures the same way. ShopFit stamps an
-- AisleClear on the booths; the town stores are measured from the door and
-- the counter alone.

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
ShopBounds.EndSlack = 0.1

local function findPart(model: Model, name: string): BasePart?
	local inst = model:FindFirstChild(name, true)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

local function doorOf(model: Model): BasePart?
	return findPart(model, "DoorBlock") or findPart(model, "DoorOpening")
end

local function counterOf(model: Model): BasePart?
	local counter = model:FindFirstChild("Counter")
	if counter and counter:IsA("BasePart") then
		return counter
	end
	return nil
end

-- How far `size` reaches along `axis` when the part's frame is `rel`.
local function halfAlong(rel: CFrame, size: Vector3, axis: Vector3): number
	local zHat = -rel.LookVector
	return math.abs(rel.RightVector:Dot(axis)) * size.X / 2
		+ math.abs(rel.UpVector:Dot(axis)) * size.Y / 2
		+ math.abs(zHat:Dot(axis)) * size.Z / 2
end

-- +1 when the counter is on the door's local +Z side (the usual inside).
local function insideSign(door: BasePart, counter: BasePart): number
	local z = door.CFrame:PointToObjectSpace(counter.CFrame.Position).Z
	return if z >= 0 then 1 else -1
end

-- The counter face that looks at the door, in the door's local Z.
local function counterNearZ(door: BasePart, counter: BasePart): number
	local rel = door.CFrame:ToObjectSpace(counter.CFrame)
	local sign = if rel.Position.Z >= 0 then 1 else -1
	local half = halfAlong(rel, counter.Size, Vector3.zAxis)
	return rel.Position.Z - sign * half
end

local function beside(door: BasePart, counter: BasePart): boolean
	local x = door.CFrame:PointToObjectSpace(counter.CFrame.Position).X
	return math.abs(x) > door.Size.X * 0.5
end

-- From just above the door's bottom (the opening's floor) to the top of the door.
local function vertical(door: BasePart): (number, number)
	local y0 = -door.Size.Y / 2 + 0.05
	local y1 = door.Size.Y / 2
	return (y0 + y1) / 2, y1 - y0
end

function ShopBounds.Door(model: Model): Box?
	local part = doorOf(model)
	if part == nil then
		return nil
	end
	return { name = part.Name, cf = part.CFrame, size = part.Size }
end

-- The booth's AisleClear, when its near end is on the door's inside face
-- and its far end is on the counter's near face. Nil otherwise.
function ShopBounds.Marked(model: Model): Box?
	local door = doorOf(model)
	local counter = counterOf(model)
	if door == nil or counter == nil then
		return nil
	end
	local sign = insideSign(door, counter)
	local inside = sign * (door.Size.Z / 2)
	local farTarget = counterNearZ(door, counter)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "AisleClear" and not d.CanCollide and d.Size.X >= ShopBounds.AisleMin then
			local rel = door.CFrame:ToObjectSpace(d.CFrame)
			local half = halfAlong(rel, d.Size, Vector3.zAxis)
			local near = if sign > 0 then rel.Position.Z - half else rel.Position.Z + half
			local far = if sign > 0 then rel.Position.Z + half else rel.Position.Z - half
			if math.abs(near - inside) <= ShopBounds.EndSlack and math.abs(far - farTarget) <= ShopBounds.EndSlack then
				return { name = "AisleClear", cf = d.CFrame, size = d.Size }
			end
		end
	end
	return nil
end

-- The customer walk, in the door's frame. It reaches the counter's near
-- face, or 8 studs past the inside face when the counter stands beside the
-- opening. It is never shortened to dodge a solid.
function ShopBounds.Walk(model: Model): Box?
	local door = doorOf(model)
	local counter = counterOf(model)
	if door == nil or counter == nil then
		return nil
	end
	local rel = door.CFrame:ToObjectSpace(counter.CFrame)
	local sign = if rel.Position.Z >= 0 then 1 else -1
	local inside = sign * (door.Size.Z / 2)
	local z0 = inside
	local z1 = if beside(door, counter) then inside + sign * 8 else counterNearZ(door, counter)
	local length = (z1 - z0) * sign
	if length < 1 then
		return nil
	end
	local yMid, height = vertical(door)
	return {
		name = "Walk",
		cf = door.CFrame * CFrame.new(0, yMid, (z0 + z1) / 2),
		size = Vector3.new(ShopBounds.AisleMin, height, length),
	}
end

-- Three studs beside an 8-wide opening, outside the shop, in the door's frame.
function ShopBounds.Shoulders(door: Box, inside: Vector3, studs: number): { Box }
	local localZ = door.cf:PointToObjectSpace(inside).Z
	local sign = if localZ >= 0 then 1 else -1
	local half = ShopBounds.DoorMinW / 2
	local z = -sign * (door.size.Z / 2 + studs / 2)
	local h = math.min(door.size.Y, 8)
	local boxes: { Box } = {}
	for _, side in ipairs({ -1, 1 }) do
		table.insert(boxes, {
			name = "Shoulder",
			cf = door.cf * CFrame.new(side * (half + studs / 2), 0, z),
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
