--!strict
-- ShopFacade: the street side of a shop and the little things that make it
-- read as a store someone works in: windows with frames, sills and flower
-- boxes, an awning or canopy over the door, a doormat, planters, a bench,
-- barrels and crates, a sandwich board with the hours, a chimney or roof
-- vent. Pure art code (Kit, Instance.new, datatypes); everything is built in
-- FINAL studs from the shop's origin (ground y = 0, the door on -Z), after the
-- shop is scaled, and is looks only (Kit.decor), except a bench, which is
-- left non-colliding too so nothing narrows the walk to the door.
--
-- Every piece stays at least DoorClear studs off the door's opening
-- (x -doorHalf to doorHalf) and out of the way of a 2-stud-wide walk from
-- the front edge to the door (the specs measure both).

local Kit = require(script.Parent.Kit)
local ShopHoursLogic = require(script.Parent.Parent.ShopHoursLogic)

local ShopFacade = {}

export type Spec = {
	kind: string,
	halfW: number, -- the front wall's half width (outside face)
	frontZ: number, -- z of the front wall's outside face (negative)
	doorCx: number, -- x of the door opening's middle (0 but at the Dealership)
	doorHalf: number, -- half the door opening's width
	doorTop: number, -- the door opening's top
	wallTop: number, -- the front wall's top edge
	roofTop: number, -- the roof's highest point over the front half
	groundY: number, -- the floor's top
	accent: Color3,
}

ShopFacade.DoorClear = 0.8

local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex

local TIMBER = hex("#5A3E26")
local PAPER = hex("#F4ECD8")
local TRIM = hex("#F2E7CF")
local IRON = hex("#3B3634")
local LEAF = hex("#4E7A3E")
local WOOD = hex("#8C6239")
local BRICK = hex("#8E4B3A")

local function decor(p: Part): Part
	Kit.decor(p, if math.max(p.Size.X, p.Size.Y, p.Size.Z) < 3 then false else nil)
	return p
end

local function box(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?): Part
	return decor(Kit.part(parent, name, size, cf, color, mat or MAT.Wood))
end

-- A window in the front wall: frame, sill, a pane of glass, one mullion each
-- way and, when `box`, a flower box under it. `cx` and `cy` are its middle.
local function window(parent: Instance, spec: Spec, cx: number, cy: number, w: number, h: number, flowers: boolean)
	local z = spec.frontZ - 0.12
	box(parent, "WindowFrame", V3(w + 0.8, 0.4, 0.4), CF(cx, cy + h / 2 + 0.2, z), TRIM)
	box(parent, "WindowFrame", V3(0.4, h, 0.4), CF(cx - w / 2 - 0.2, cy, z), TRIM)
	box(parent, "WindowFrame", V3(0.4, h, 0.4), CF(cx + w / 2 + 0.2, cy, z), TRIM)
	box(parent, "WindowSill", V3(w + 1.4, 0.35, 0.9), CF(cx, cy - h / 2 - 0.2, z - 0.25), TRIM)
	local pane = box(parent, "WindowGlass", V3(w, h, 0.12), CF(cx, cy, z + 0.12), hex("#BFD9E6"), MAT.Glass)
	pane.Transparency = 0.45
	pane.CastShadow = false
	box(parent, "WindowBar", V3(0.18, h, 0.2), CF(cx, cy, z), TRIM)
	box(parent, "WindowBar", V3(w, 0.18, 0.2), CF(cx, cy, z), TRIM)
	if flowers then
		box(parent, "FlowerBox", V3(w + 0.6, 0.8, 0.9), CF(cx, cy - h / 2 - 0.9, z - 0.5), WOOD)
		box(parent, "Flowers", V3(w + 0.2, 0.45, 0.7), CF(cx, cy - h / 2 - 0.35, z - 0.5), hex("#D9577B"), MAT.Grass)
	end
end

local function planter(parent: Instance, x: number, y: number, z: number)
	box(parent, "Planter", V3(2.2, 1.6, 2.2), CF(x, y + 0.8, z), WOOD)
	box(parent, "PlanterBand", V3(2.3, 0.25, 2.3), CF(x, y + 1.3, z), TIMBER)
	Kit.decor(Kit.ball(parent, "PlanterLeaves", 2.2, CF(x, y + 2.2, z), LEAF, MAT.Grass), false)
end

local function barrel(parent: Instance, x: number, y: number, z: number)
	Kit.decor(Kit.post(parent, "Barrel", V3(x, y, z), 2.6, 1.9, WOOD, MAT.Wood), false)
	for _, dy in ipairs({ 0.5, 2.1 }) do
		Kit.decor(Kit.post(parent, "BarrelHoop", V3(x, y + dy, z), 0.2, 1.98, IRON, MAT.Metal), false)
	end
end

local function crate(parent: Instance, x: number, y: number, z: number, s: number)
	box(parent, "Crate", V3(s, s, s), CF(x, y + s / 2, z), hex("#B08A55"))
	box(parent, "CrateBand", V3(s + 0.06, 0.2, s + 0.06), CF(x, y + s / 2, z), TIMBER)
end

local function bench(parent: Instance, x: number, y: number, z: number)
	box(parent, "BenchSeat", V3(4.4, 0.3, 1.4), CF(x, y + 1.5, z), WOOD)
	box(parent, "BenchBack", V3(4.4, 1.1, 0.25), CF(x, y + 2.3, z + 0.65), WOOD)
	for _, s in ipairs({ -1, 1 }) do
		box(parent, "BenchLeg", V3(0.3, 1.5, 1.2), CF(x + s * 1.9, y + 0.75, z), TIMBER)
	end
end

-- An A-frame sandwich board with the shop's hours on it.
local function sandwichBoard(parent: Instance, x: number, y: number, z: number, shopId: string)
	local span = ShopHoursLogic.Span(shopId)
	local text = "OPEN\nALL DAY"
	if span then
		local from = string.gsub(ShopHoursLogic.FormatHour(span.open), ":00", "")
		local to = string.gsub(ShopHoursLogic.FormatHour(span.close), ":00", "")
		text = string.format("OPEN\n%s -\n%s", from, to)
	end
	for _, s in ipairs({ -1, 1 }) do
		local b = box(
			parent,
			"SandwichBoard",
			V3(2.6, 3.4, 0.2),
			CF(x, y + 1.7, z + s * 0.5) * CFrame.Angles(-s * 0.18, 0, 0),
			hex("#2D3A33")
		)
		if s == -1 then
			Kit.signText(b, text, PAPER, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
		end
	end
end

local function doormat(parent: Instance, spec: Spec)
	box(
		parent,
		"Doormat",
		V3(spec.doorHalf * 1.4, 0.06, 2.2),
		CF(spec.doorCx, spec.groundY + 0.04, spec.frontZ - 1.6),
		hex("#6B5436"),
		MAT.Fabric
	)
end

local function chimney(parent: Instance, x: number, z: number, baseY: number, h: number)
	box(parent, "Chimney", V3(1.8, h, 1.8), CF(x, baseY + h / 2, z), BRICK, MAT.Brick)
	box(parent, "ChimneyCap", V3(2.4, 0.3, 2.4), CF(x, baseY + h + 0.15, z), hex("#5C5650"), MAT.Slate)
end

-- A striped awning on two posts over the door: `reach` studs out.
local function awning(parent: Instance, spec: Spec, y: number, reach: number, colorA: Color3, colorB: Color3)
	local w = spec.doorHalf * 2 + 4
	local c = spec.doorCx
	local n = 8
	local stripe = w / n
	local tilt = 0.32
	for i = 1, n do
		local x = c - w / 2 + stripe * (i - 0.5)
		box(
			parent,
			"AwningStripe",
			V3(stripe, 0.25, reach),
			CF(x, y, spec.frontZ - reach / 2 + 0.2) * CFrame.Angles(-tilt, 0, 0),
			if i % 2 == 0 then colorA else colorB,
			MAT.Fabric
		)
	end
	for _, s in ipairs({ -1, 1 }) do
		box(
			parent,
			"AwningPost",
			V3(0.3, y - spec.groundY - 0.4, 0.3),
			CF(c + s * (w / 2 - 0.2), spec.groundY + (y - spec.groundY - 0.4) / 2, spec.frontZ - reach + 0.4),
			TIMBER
		)
	end
end

local function shopSpecific(model: Model, spec: Spec)
	local gy = spec.groundY
	local hw = spec.halfW
	local fz = spec.frontZ
	local d = spec.doorHalf
	if spec.kind == "HearthAndHome" then
		for _, x in ipairs({ -20, -13.5, 13.5, 20 }) do
			window(model, spec, x, 6.8, 3.6, 4.4, true)
		end
		awning(model, spec, 11.9, 4.2, hex("#3E6A3A"), hex("#F2E7CF"))
		planter(model, -10.3, gy, fz - 1.8)
		planter(model, 10.3, gy, fz - 1.8)
		bench(model, -16.5, gy, fz - 1.4)
		sandwichBoard(model, 17.5, gy, fz - 2.4, "HearthAndHome")
		barrel(model, hw - 2.2, gy, fz - 1.6)
		crate(model, hw - 4.4, gy, fz - 1.4, 1.7)
		chimney(model, -16, 8, spec.roofTop - 0.2, 5)
	elseif spec.kind == "ToolShed" then
		for _, x in ipairs({ -11, 11 }) do
			window(model, spec, x, 6.2, 3.6, 3.6, false)
		end
		-- (The grindstone and the chopping block stand out front, and the door
		-- header carries the hours board, so the yard has no planters or sandwich
		-- board; the barrel and the crate stand by the west wall.)
		barrel(model, -hw - 1.6, gy, fz + 6)
		crate(model, -hw - 1.6, gy, fz + 8.6, 1.7)
		chimney(model, -6, 6, spec.roofTop - 2.4, 5)
	else
		-- The showroom: a canopy over the lobby door, planters, a bench and a
		-- sandwich board, a flag pole and roof units (its windows are the glass band).
		local c = spec.doorCx
		awning(model, spec, spec.doorTop + 0.7, 5, hex("#2F6DB5"), hex("#F2E7CF"))
		planter(model, c + d + 2.6, gy, fz - 1.8)
		planter(model, c - d - 2.6, gy, fz - 1.8)
		bench(model, c + d + 9, gy, fz - 1.4)
		sandwichBoard(model, c + d + 15, gy, fz - 2.4, "Dealership")
		box(model, "FlagPole", V3(0.25, 11, 0.25), CF(c + d + 21, gy + 5.5, fz - 1.4), IRON, MAT.Metal)
		box(model, "FlagCloth", V3(3.2, 2, 0.1), CF(c + d + 22.7, gy + 9.8, fz - 1.4), hex("#2F6DB5"), MAT.Fabric)
		for _, x in ipairs({ c + 40, c + 90 }) do
			box(
				model,
				"RoofUnit",
				V3(5, 2.2, 3.4),
				CF(x, spec.roofTop + 1.1, spec.frontZ + 10),
				hex("#A9B0B6"),
				MAT.Metal
			)
			box(model, "RoofUnitFan", V3(2.2, 0.2, 2.2), CF(x, spec.roofTop + 2.3, spec.frontZ + 10), IRON, MAT.Metal)
		end
	end
	doormat(model, spec)
end

-- Adds the facade to the shop's model. See Spec.
function ShopFacade.Add(model: Model, spec: Spec)
	shopSpecific(model, spec)
end

return ShopFacade
