--!strict
-- ItemBox: the box for an item, from the item. Measures the model the box
-- will show (Art/ItemModel.Extent) and applies BoxSize's rule: the item's
-- bounding box plus a margin, never below the minimum, never above the
-- shelf (or vehicle) maximum. Cached per item.
--
-- SCALE GROUPS. A thing too big for its box is shown smaller, and every
-- member of a family is shown at the SAME scale, so a bigger sawmill (or
-- planer, or truck) is a bigger box than the one below it: the Rickety Mill's
-- box is smaller than the Industrial's, the Scout ATV's is smaller than the
-- Logging Rig's. Axes, plans, gear and the one-off machines (chop saw, Sky
-- Bin) are each fitted on their own: they would be unreadable at a family's
-- scale. A group's scale is the smallest scale its members need (the biggest
-- member just fits its maximum).
--
-- ItemModel is required when first asked: it builds the real art, which
-- (through BuildingArt) needs StoreStock, which needs this module.

local BoxSize = require(script.Parent.BoxSize)
local ItemCatalog = require(script.Parent.ItemCatalog)

local ItemBox = {}

export type Result = {
	size: Vector3, -- the box
	scale: number, -- the item's scale in the window
	inner: Vector3, -- the item as shown (extent * scale)
	extent: Vector3, -- the item's real bounding box
	parts: number, -- parts in the window (the display copy)
	vehicle: boolean,
	group: string, -- the scale group
}

-- The vehicles the showroom sells, in no order (DealershipLot sorts them by
-- price). The one list: the showroom builds its bays from it, and these are
-- the members of the "Vehicle" scale group.
ItemBox.Showroom = {
	{ kind = "Truck", id = "Rustbucket" },
	{ kind = "Truck", id = "Pickup" },
	{ kind = "Truck", id = "ScoutATV" },
	{ kind = "Truck", id = "Flatbed" },
	{ kind = "Truck", id = "LoggingRig" },
	{ kind = "Trailer", id = "PonyTrailer" },
	{ kind = "Trailer", id = "RanchTrailer" },
	{ kind = "Trailer", id = "HeavyHauler" },
} :: { { kind: string, id: string } }

local cache: { [string]: Result } = {}
local groupScale: { [string]: number } = {}

-- Found by name at run time, not by a static path: the type checker (rightly)
-- sees a static require here as a cycle through BuildingArt.
local function itemModel(): any
	local art = script.Parent:FindFirstChild("Art")
	local module = if art then art:FindFirstChild("ItemModel") else nil
	local load = require :: any
	return load(module)
end

-- The scale group an item belongs to.
function ItemBox.GroupOf(kind: string, itemId: string): string
	if BoxSize.IsVehicleKind(kind) then
		return "Vehicle"
	elseif kind == "Sawmill" then
		return "Sawmill"
	elseif kind == "Machine" then
		local machine = ItemCatalog.GetMachine(itemId)
		if machine and machine.planer ~= nil then
			return "Planer"
		elseif machine and machine.belt ~= nil then
			return "Belt"
		end
	end
	return kind .. ":" .. itemId
end

-- The members of a family group: { kind, id } pairs. nil for a lone item.
local function members(group: string): { { kind: string, id: string } }?
	local out: { { kind: string, id: string } } = {}
	if group == "Vehicle" then
		return ItemBox.Showroom
	elseif group == "Sawmill" then
		for _, mill in ipairs(ItemCatalog.SawmillList()) do
			table.insert(out, { kind = "Sawmill", id = mill.id })
		end
		return out
	elseif group == "Planer" or group == "Belt" then
		for _, machine in ipairs(ItemCatalog.MachineList()) do
			if (group == "Planer" and machine.planer ~= nil) or (group == "Belt" and machine.belt ~= nil) then
				table.insert(out, { kind = "Machine", id = machine.id })
			end
		end
		return out
	end
	return nil
end

-- The scale a group shows its items at: the smallest any member needs.
local function scaleOf(group: string, kind: string, extent: Vector3): number
	local known = groupScale[group]
	if known then
		return known
	end
	local scale = BoxSize.Fit(extent, kind).scale
	local list = members(group)
	if list then
		local model = itemModel()
		for _, member in ipairs(list) do
			local e = model.Get(member.kind, member.id).extent
			scale = math.min(scale, BoxSize.Fit(e, member.kind).scale)
		end
	end
	groupScale[group] = scale
	return scale
end

function ItemBox.For(kind: string, itemId: string): Result
	local key = kind .. ":" .. itemId
	local hit = cache[key]
	if hit then
		return hit
	end
	local display = itemModel().Get(kind, itemId)
	local group = ItemBox.GroupOf(kind, itemId)
	local scale = scaleOf(group, kind, display.extent)
	local fit = BoxSize.Fit(display.extent, kind, scale)
	local result: Result = {
		size = fit.size,
		scale = fit.scale,
		inner = fit.inner,
		extent = display.extent,
		parts = #display.parts,
		vehicle = BoxSize.IsVehicleKind(kind),
		group = group,
	}
	cache[key] = result
	return result
end

function ItemBox.Size(kind: string, itemId: string): Vector3
	return ItemBox.For(kind, itemId).size
end

return ItemBox
