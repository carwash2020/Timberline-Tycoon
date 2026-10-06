--!strict
-- ShopInterior: what goes inside a shop once BuildingArt has built and
-- scaled it: the tables and shelf units the boxes stand on, the aisle
-- signs, the ceiling beams, the lamps, a wood floor and an aisle runner.
-- Pure art code (Kit, Instance.new, datatypes). Everything is in FINAL
-- studs from the shop's origin (ground y = 0, the door on -Z), so a table
-- is exactly as big as StoreStock's lane for it and a box on it never
-- overhangs; nothing here is scaled again.
--
-- Only tables, shelf units and the counter collide (a player walks between
-- them); signs, beams, lamps and floor trim are looks only (Kit.decor).

local Kit = require(script.Parent.Kit)
local RobuxShelf = require(script.Parent.Parent.RobuxShelf)
local ShelfLayout = require(script.Parent.Parent.ShelfLayout)
local StoreStock = require(script.Parent.Parent.StoreStock)

local ShopInterior = {}

export type Frame = {
	floorTop: number, -- y of the floor surface
	halfW: number, -- inner half width (x)
	halfD: number, -- inner half depth (z)
	ceilY: number, -- y of the underside of the ceiling beams' level
}

local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex

local TABLE = hex("#8C6239")
local TABLE_TOP = hex("#C69C6D")
local TIMBER = hex("#5A3E26")
local IRON = hex("#3B3634")
local PAPER = hex("#F4ECD8")
local GOLD = hex("#E3B73C")
local GOLD_INK = hex("#6B4A12")
local RUNNER = hex("#9A3D2E")
local RUNNER_EDGE = hex("#E3C98A")

local function decor(p: Part): Part
	Kit.decor(p, if math.max(p.Size.X, p.Size.Y, p.Size.Z) < 3 then false else nil)
	return p
end

local function dBox(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	return decor(Kit.part(parent, name, size, cf, color, mat or MAT.Wood))
end

-- The floor rectangle a lane's boxes actually cover, grown a little.
function ShopInterior.LaneRect(lane: ShelfLayout.Lane, spots: { ShelfLayout.Spot }): (number?, number?)
	local lo, hi = math.huge, -math.huge
	for _, spot in ipairs(spots) do
		if spot.lane == lane.name then
			lo = math.min(lo, spot.z - spot.d / 2)
			hi = math.max(hi, spot.z + spot.d / 2)
		end
	end
	if lo > hi then
		return nil
	end
	return math.max(lane.z0, lo - 0.8), math.min(lane.z1, hi + 0.8)
end

-- The spots of a shop as ShelfLayout.Spot (for the table extents).
local function spotsOf(kind: string): { ShelfLayout.Spot }
	local out: { ShelfLayout.Spot } = {}
	local lanes = StoreStock.Lanes(kind)
	for _, place in ipairs(StoreStock.Placements(kind)) do
		local laneName = ""
		for _, lane in ipairs(lanes) do
			if place.x >= lane.x0 and place.x <= lane.x1 and place.z >= lane.z0 and place.z <= lane.z1 then
				laneName = lane.name
				break
			end
		end
		local depth = place.count * place.size.Z + (place.count - 1) * (place.pitch - place.size.Z)
		table.insert(out, {
			id = place.slotId,
			lane = laneName,
			x = place.x,
			y = place.y,
			z = place.z,
			w = place.size.X,
			h = place.size.Y,
			d = depth,
		})
	end
	return out
end

-- A table: legs and apron (a body, solid), a top board that overhangs a
-- little, and a trim along its front edge. `topY` is the surface.
local function furniture(
	parent: Instance,
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	floorTop: number,
	topY: number,
	body: Color3,
	top: Color3
)
	local w, d = x1 - x0, z1 - z0
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local bodyH = topY - floorTop - 0.3
	Kit.part(parent, name, V3(w - 0.4, bodyH, d - 0.4), CF(cx, floorTop + bodyH / 2, cz), body, MAT.WoodPlanks)
	local board = Kit.part(parent, name .. "Top", V3(w, 0.3, d), CF(cx, topY - 0.15, cz), top, MAT.Wood)
	board.CanQuery = false
	dBox(parent, name .. "Trim", V3(w + 0.1, 0.5, 0.18), CF(cx, topY - 0.5, z0 - 0.04), TIMBER)
end

-- A board hung on two chains from the ceiling, facing -Z, with `text` on
-- both faces so it reads walking in and walking out.
local function hangSign(
	parent: Instance,
	cx: number,
	cy: number,
	z: number,
	w: number,
	h: number,
	ceilY: number,
	text: string,
	board: Color3,
	ink: Color3
)
	local b = dBox(parent, "AisleSign", V3(w, h, 0.3), CF(cx, cy, z), board)
	Kit.signText(b, text, ink)
	dBox(parent, "AisleSignFrame", V3(w + 0.4, 0.22, 0.42), CF(cx, cy + h / 2 + 0.1, z), TIMBER)
	dBox(parent, "AisleSignFrame", V3(w + 0.4, 0.22, 0.42), CF(cx, cy - h / 2 - 0.1, z), TIMBER)
	for _, s in ipairs({ -1, 1 }) do
		local top = cy + h / 2 + 0.2
		dBox(
			parent,
			"AisleSignChain",
			V3(0.1, ceilY - top, 0.1),
			CF(cx + s * (w / 2 - 0.4), (ceilY + top) / 2, z),
			IRON,
			MAT.Metal
		)
	end
end

local function beam(parent: Instance, y: number, z: number, width: number)
	dBox(parent, "CeilingBeam", V3(width, 0.9, 0.9), CF(0, y, z), TIMBER)
end

local function lamp(parent: Instance, x: number, y: number, z: number, ceilY: number)
	local len = ceilY - y - 0.6
	dBox(parent, "LampChain", V3(0.1, len, 0.1), CF(x, ceilY - len / 2, z), IRON, MAT.Metal)
	Kit.lantern(parent, CF(x, y, z), 1.1)
end

local function floorBoards(parent: Instance, frame: Frame)
	local w, d = 2 * frame.halfW - 0.4, 2 * frame.halfD - 0.4
	dBox(parent, "FloorBoards", V3(w, 0.06, d), CF(0, frame.floorTop + 0.03, 0), hex("#B58B5A"), MAT.WoodPlanks)
end

-- A runner down the middle aisle, with an edge stripe each side.
local function runner(parent: Instance, frame: Frame, halfWidth: number, z0: number, z1: number)
	local len = z1 - z0
	local cz = (z0 + z1) / 2
	local y = frame.floorTop + 0.09
	dBox(parent, "AisleRunner", V3(2 * halfWidth, 0.06, len), CF(0, y, cz), RUNNER, MAT.Fabric)
	for _, s in ipairs({ -1, 1 }) do
		dBox(
			parent,
			"AisleRunnerEdge",
			V3(0.35, 0.07, len),
			CF(s * (halfWidth - 0.3), y + 0.005, cz),
			RUNNER_EDGE,
			MAT.Fabric
		)
	end
end

local function laneFurniture(parent: Instance, kind: string, frame: Frame, name: string, body: Color3, top: Color3)
	local spots = spotsOf(kind)
	for _, lane in ipairs(StoreStock.Lanes(kind)) do
		local lo, hi = ShopInterior.LaneRect(lane, spots)
		if lo and hi then
			furniture(parent, name, lane.x0, lane.x1, lo, hi, frame.floorTop, lane.y, body, top)
		end
	end
end

---------------------------------------------------------------------------
-- The Tool Shed
---------------------------------------------------------------------------

local function toolShed(model: Model, frame: Frame)
	laneFurniture(model, "ToolShed", frame, "DisplayTable", TABLE, TABLE_TOP)
	-- The Robux table: the same table as the cash shelves with a gold top, and
	-- a gold sign hung over it (no plinth in front). Its boxes are the gold
	-- boxes, one name label and one price tag each.
	local entries = RobuxShelf.List()
	if #entries > 0 then
		local width = RobuxShelf.RowWidth()
		local cz = RobuxShelf.TableZ
		local depth = RobuxShelf.TableDepth
		furniture(
			model,
			"GoldTable",
			-width / 2,
			width / 2,
			cz - depth / 2,
			cz + depth / 2,
			frame.floorTop,
			RobuxShelf.TableTop,
			TIMBER,
			GOLD
		)
		hangSign(
			model,
			0,
			frame.ceilY - 3.7,
			cz - depth / 2 - 0.2,
			8.4,
			1.6,
			frame.ceilY - 0.9,
			"ROBUX SHELF",
			GOLD,
			GOLD_INK
		)
	end

	floorBoards(model, frame)
	runner(model, frame, 2.6, -frame.halfD + 1.4, 12)
	local y = frame.ceilY
	for _, z in ipairs({ -13, -1, 11, 17.5 }) do
		beam(model, y - 0.45, z, 2 * frame.halfW - 0.6)
	end
	for _, z in ipairs({ -13, -1, 11 }) do
		for _, x in ipairs({ -9.6, 9.6 }) do
			lamp(model, x, y - 3.1, z, y - 0.9)
		end
	end
	lamp(model, 0, y - 3.1, 17.5, y - 0.9)
	hangSign(model, -9.6, y - 3.7, -16.4, 7.8, 1.6, y - 0.9, "AXES", hex("#8E3B2B"), PAPER)
	hangSign(model, 9.6, y - 3.7, -16.4, 7.8, 1.6, y - 0.9, "SAWMILLS & MACHINES", hex("#3E4A62"), PAPER)
end

---------------------------------------------------------------------------
-- Hearth & Home
---------------------------------------------------------------------------

local function hearth(model: Model, frame: Frame)
	local spots = spotsOf("HearthAndHome")
	for _, lane in ipairs(StoreStock.Lanes("HearthAndHome")) do
		local lo, hi = ShopInterior.LaneRect(lane, spots)
		if lo and hi then
			furniture(model, "Shelf", lane.x0, lane.x1, lo, hi, frame.floorTop, lane.y, TABLE, TABLE_TOP)
			if lane.name == "GearShelf" or lane.name == "LampShelf" then
				-- Tall back shelving on the wall behind the unit: an upright
				-- panel and two boards, looks only.
				local wallX = if lane.x0 < 0 then -frame.halfW + 0.3 else frame.halfW - 0.3
				local cz = (lo + hi) / 2
				dBox(model, "ShelfBack", V3(0.3, 9.5, hi - lo), CF(wallX, frame.floorTop + 4.75 + 0.3, cz), TABLE)
				for _, y in ipairs({ 6.6, 9.6 }) do
					dBox(
						model,
						"WallShelf",
						V3(1.6, 0.25, hi - lo),
						CF(wallX + (if lane.x0 < 0 then 0.8 else -0.8), y, cz),
						TABLE_TOP
					)
				end
			end
		end
	end
	floorBoards(model, frame)
	runner(model, frame, 3.6, -frame.halfD + 1.6, frame.halfD - 3.5)
	local y = frame.ceilY
	for _, z in ipairs({ -12, -3, 6, 14 }) do
		beam(model, y - 0.45, z, 2 * frame.halfW - 0.6)
	end
	for _, z in ipairs({ -12, 6 }) do
		for _, x in ipairs({ -19, -10, 10, 19 }) do
			lamp(model, x, y - 3.4, z, y - 0.9)
		end
	end
	lamp(model, 0, y - 3.4, 14, y - 0.9)
	hangSign(model, -20.6, y - 3.4, -16.8, 6.4, 1.5, y - 0.9, "GEAR", hex("#2E8B7A"), PAPER)
	hangSign(model, -10.2, y - 3.4, -16.8, 6.4, 1.5, y - 0.9, "PLANS", hex("#3B6FB6"), PAPER)
	hangSign(model, 10.2, y - 3.4, -16.8, 6.4, 1.5, y - 0.9, "PLANS", hex("#3B6FB6"), PAPER)
	hangSign(model, 20.6, y - 3.4, -16.8, 6.4, 1.5, y - 0.9, "LIMITED", hex("#8E5BB5"), PAPER)
end

---------------------------------------------------------------------------
-- The Dealership showroom
---------------------------------------------------------------------------

local function dealership(model: Model, frame: Frame, west: number, east: number, zf: number, zb: number)
	local width = east - west
	local cx = (east + west) / 2
	dBox(
		model,
		"FloorBoards",
		V3(width - 0.4, 0.06, zb - zf - 0.4),
		CF(cx, frame.floorTop + 0.03, (zf + zb) / 2),
		hex("#CFC7BA"),
		MAT.Concrete
	)
	-- A runner from the door to the counter.
	local lobbyCx = west + 7.75
	local y = frame.floorTop + 0.09
	dBox(model, "AisleRunner", V3(5, 0.06, 20), CF(lobbyCx, y, zf + 11), RUNNER, MAT.Fabric)
	local ceil = frame.ceilY
	-- Beams across the hall with strip lights along them.
	for _, z in ipairs({ zf + 9, zf + 25, zf + 41 }) do
		dBox(model, "CeilingBeam", V3(width - 0.6, 0.9, 0.9), CF(cx, ceil - 0.45, z), TIMBER)
		local x = west + 12
		while x < east - 6 do
			local strip = dBox(model, "StripLight", V3(9, 0.2, 0.5), CF(x, ceil - 1.1, z), hex("#FFF1D6"), MAT.Neon)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 236, 205)
			light.Range = 26
			light.Brightness = 1
			light.Shadows = false
			light.Parent = strip
			x += 24
		end
	end
	hangSign(model, lobbyCx, ceil - 3.6, zf + 5, 9, 1.7, ceil - 0.9, "SHOWROOM", hex("#2F6DB5"), PAPER)
end

-- Adds the interior. `frame` is the shop's final-stud frame (see Frame);
-- for the Dealership `extra` is the showroom's inner west x, east x, front
-- z and back z.
function ShopInterior.Add(model: Model, kind: string, frame: Frame, extra: { number }?)
	if kind == "ToolShed" then
		toolShed(model, frame)
	elseif kind == "HearthAndHome" then
		hearth(model, frame)
	elseif kind == "Dealership" then
		local span = extra or { -frame.halfW, frame.halfW, -frame.halfD, frame.halfD }
		dealership(model, frame, span[1], span[2], span[3], span[4])
	end
end

return ShopInterior
