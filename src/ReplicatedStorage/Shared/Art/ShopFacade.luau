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
	matY: number?, -- where the doormat lies, when that is not the floor's top (the Dealership's walk is at street level)
	accent: Color3,
	yardY: number?, -- where the yard's props stand (the real ground) when the floor is a step up from it; default groundY
}

ShopFacade.DoorClear = 0.8
ShopFacade.AwningGap = 0.7 -- the Dealership canopy's near end stands this far off the wall, clear of the hours board on it
ShopFacade.AwningReach = 5 -- how far the Dealership's canopy reaches out from the front wall

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
local COPPER = hex("#B87333")
local STONE = hex("#9C958A")
local SPARK = hex("#3FC9C0")

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
		CF(spec.doorCx, (spec.matY or spec.groundY) + 0.04, spec.frontZ - 1.6),
		hex("#6B5436"),
		MAT.Fabric
	)
end

local function chimney(parent: Instance, x: number, z: number, baseY: number, h: number)
	box(parent, "Chimney", V3(1.8, h, 1.8), CF(x, baseY + h / 2, z), BRICK, MAT.Brick)
	box(parent, "ChimneyCap", V3(2.4, 0.3, 2.4), CF(x, baseY + h + 0.15, z), hex("#5C5650"), MAT.Slate)
end

-- A striped awning on two posts over the door: `reach` studs out.
local function awning(
	parent: Instance,
	spec: Spec,
	y: number,
	reach: number,
	colorA: Color3,
	colorB: Color3,
	gap: number?
)
	local off = gap or 0 -- how far the canopy's near end stands off the wall
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
			CF(x, y, spec.frontZ - off - reach / 2 + 0.2) * CFrame.Angles(-tilt, 0, 0),
			if i % 2 == 0 then colorA else colorB,
			MAT.Fabric
		)
	end
	for _, s in ipairs({ -1, 1 }) do
		box(
			parent,
			"AwningPost",
			V3(0.3, y - spec.groundY - 0.4, 0.3),
			CF(c + s * (w / 2 - 0.2), spec.groundY + (y - spec.groundY - 0.4) / 2, spec.frontZ - off - reach + 0.4),
			TIMBER
		)
	end
end

-- The Sparkworks' street side: it stands on a stone plinth, a doorstep leads to the door,
-- away from it with a lamp post each side, the front and the side walls carry a copper conduit with spark lamps,
-- the corners are teal pilasters, the roof edge a teal fascia and the roof two lightning rods. The yard's props
-- (windows, planters, barrel, crate, board, awning) stand on the real ground (spec.yardY).
local function sparkworksFront(model: Model, spec: Spec)
	local fz, hw = spec.frontZ, spec.halfW + 0.45 -- the walls' outside faces
	local gy = spec.yardY or spec.groundY
	local floorY = spec.groundY
	local d = spec.doorHalf
	local yard = table.clone(spec)
	yard.groundY = gy

	-- Plinth: the wall's foot sticks out past the floor slab, so a stone strip runs under it
	-- (front in two pieces round the doorstep, the sides and the back), top level with the floor.
	-- These and the doorstep are walked on, so they collide.
	local ring = hw + 0.55
	local frontLen = ring - d
	for _, s in ipairs({ -1, 1 }) do
		Kit.part(
			model,
			"Foundation",
			V3(frontLen, floorY, 1.0),
			CF(s * (d + frontLen / 2), floorY / 2, fz - 0.05),
			STONE,
			MAT.Cobblestone
		)
		Kit.part(
			model,
			"Foundation",
			V3(1.0, floorY, 2 * ring - 1.9),
			CF(s * (hw + 0.05), floorY / 2, 0),
			STONE,
			MAT.Cobblestone
		)
	end
	Kit.part(model, "Foundation", V3(2 * ring, floorY, 1.0), CF(0, floorY / 2, -fz + 0.05), STONE, MAT.Cobblestone)
	-- The doorstep: level with the floor, under the doormat.
	Kit.part(model, "Doorstep", V3(2 * d, floorY, 1.9), CF(spec.doorCx, floorY / 2, fz - 0.5), STONE, MAT.Cobblestone)
	-- (the doormat, 1.5 deep, lies on it: the generic one is 2.2 deep and would hang over the step)
	box(model, "Doormat", V3(d * 1.4, 0.06, 1.5), CF(spec.doorCx, floorY + 0.04, fz - 0.5), hex("#6B5436"), MAT.Fabric)

	-- Yard: two windows, the awning, a planter each side, the board, a barrel and a crate.
	for _, x in ipairs({ -16, 16 }) do
		window(model, spec, x, 6.8, 3.6, 4.4, false)
	end
	awning(model, yard, 11.9, 4.2, spec.accent, hex("#F2E7CF"))
	planter(model, -10.3, gy, fz - 1.8)
	planter(model, 10.3, gy, fz - 1.8)
	sandwichBoard(model, -15.5, gy, fz - 2.4, "Sparkworks") -- (west, clear of the barrel and crate)
	barrel(model, spec.halfW - 2.2, gy, fz - 1.6)
	crate(model, spec.halfW - 4.4, gy, fz - 1.4, 1.7)

	-- A window in each side wall, over the counter's end of the shop (the shelf units' wall
	-- panels stop short of it).
	for _, s in ipairs({ -1, 1 }) do
		local x, cz, cy, w, h = s * (hw + 0.12), 12, 6.8, 3.6, 4.4
		box(model, "WindowFrame", V3(0.4, 0.4, w + 0.8), CF(x, cy + h / 2 + 0.2, cz), TRIM)
		for _, e in ipairs({ -1, 1 }) do
			box(model, "WindowFrame", V3(0.4, h, 0.4), CF(x, cy, cz + e * (w / 2 + 0.2)), TRIM)
		end
		box(model, "WindowSill", V3(0.9, 0.35, w + 1.4), CF(x + s * 0.25, cy - h / 2 - 0.2, cz), TRIM)
		local pane = box(model, "WindowGlass", V3(0.12, h, w), CF(s * hw, cy, cz), hex("#BFD9E6"), MAT.Glass)
		pane.Transparency = 0.45
		pane.CastShadow = false
		box(model, "WindowBar", V3(0.2, h, 0.18), CF(x, cy, cz), TRIM)
		box(model, "WindowBar", V3(0.2, 0.18, w), CF(x, cy, cz), TRIM)
	end

	-- Teal pilasters at the front corners and a teal skirting along the walls.
	local wallH = spec.wallTop - floorY
	for _, s in ipairs({ -1, 1 }) do
		box(model, "Pilaster", V3(1.0, wallH, 1.0), CF(s * (hw + 0.05), floorY + wallH / 2, fz - 0.05), spec.accent)
		box(model, "WallBand", V3(0.3, 1.2, 2 * hw - 1.0), CF(s * (hw + 0.15), floorY + 0.6, 0), spec.accent)
		local runLen = hw - d - 1.4
		box(
			model,
			"WallBand",
			V3(runLen, 1.2, 0.3),
			CF(s * (d + 0.9 + runLen / 2), floorY + 0.6, fz - 0.15),
			spec.accent
		)
	end

	-- Roof edge: a teal fascia on the front and the two sides.
	local roofH = spec.roofTop - spec.wallTop
	local roofHalf = hw + 1.05
	box(model, "Fascia", V3(2 * roofHalf, roofH, 0.3), CF(0, spec.wallTop + roofH / 2, -roofHalf - 0.15), spec.accent)
	for _, s in ipairs({ -1, 1 }) do
		box(
			model,
			"Fascia",
			V3(0.3, roofH, 2 * roofHalf),
			CF(s * (roofHalf + 0.15), spec.wallTop + roofH / 2, 0),
			spec.accent
		)
	end

	-- Wiring: a copper conduit along the front and both sides, spark lamps under it, a drop each side
	-- of the awning to a wall lantern, and a fuse box on each side wall.
	local runY = 13.2
	box(model, "Conduit", V3(2 * hw - 2.0, 0.4, 0.4), CF(0, runY, fz - 0.2), COPPER, MAT.Metal)
	for _, x in ipairs({ -16, -12.4, 12.4, 16 }) do
		local bulb = box(model, "SparkBulb", V3(0.9, 0.9, 0.5), CF(x, runY - 0.65, fz - 0.25), SPARK, MAT.Neon)
		bulb.CastShadow = false
	end
	for _, s in ipairs({ -1, 1 }) do
		local lx = s * (d + 2.7)
		box(model, "ConduitDrop", V3(0.35, runY - 9.0, 0.35), CF(lx, (runY + 9.0) / 2, fz - 0.2), COPPER, MAT.Metal)
		box(model, "LanternArm", V3(0.3, 0.25, 1.1), CF(lx, 8.9, fz - 0.55), IRON, MAT.Metal)
		local glow = Kit.lantern(model, CF(lx, 8.12, fz - 1.0), 0.9)
		for _, c in ipairs(glow:GetChildren()) do
			if c:IsA("PointLight") then
				c.Brightness = 0.9
				c.Range = 14
			end
		end
		box(model, "Conduit", V3(0.4, 0.4, 2 * hw - 2.0), CF(s * (hw + 0.2), runY, 0), COPPER, MAT.Metal)
		for _, z in ipairs({ -10, 0, 10 }) do
			local bulb = box(model, "SparkBulb", V3(0.5, 0.9, 0.9), CF(s * (hw + 0.2), runY - 0.65, z), SPARK, MAT.Neon)
			bulb.CastShadow = false
		end
		box(
			model,
			"ConduitDrop",
			V3(0.35, runY - 8.8, 0.35),
			CF(s * (hw + 0.175), (runY + 8.8) / 2, -6),
			COPPER,
			MAT.Metal
		)
		box(model, "FuseBox", V3(0.6, 1.6, 1.2), CF(s * (hw + 0.3), 8.0, -6), hex("#3A332D"), MAT.Metal)
	end

	-- Roof: a lightning rod each side, a spark ball on top.
	for _, s in ipairs({ -1, 1 }) do
		local x = s * (hw - 1.4)
		box(model, "RodBase", V3(1.6, 0.9, 1.6), CF(x, spec.roofTop + 0.45, -4), STONE, MAT.Slate)
		box(model, "SparkRod", V3(0.2, 5, 0.2), CF(x, spec.roofTop + 0.9 + 2.5, -4), IRON, MAT.Metal)
		local ball = Kit.ball(model, "SparkBall", 0.9, CF(x, spec.roofTop + 0.9 + 5 + 0.35, -4), SPARK, MAT.Neon)
		Kit.decor(ball, false)
	end

	-- Out front: a lamp post each side of the path (the road paint in WorldLayout, 12 wide, runs to the doorstep).
	for _, s in ipairs({ -1, 1 }) do
		local x, pz = s * 9.4, fz - 8
		box(model, "LampPostBase", V3(1.0, 0.5, 1.0), CF(x, 0.25, pz), STONE, MAT.Cobblestone)
		box(model, "LampPost", V3(0.35, 5.0, 0.35), CF(x, 3.0, pz), IRON, MAT.Metal)
		local glow = Kit.lantern(model, CF(x, 5.5 + 0.77, pz), 1.1)
		for _, c in ipairs(glow:GetChildren()) do
			if c:IsA("PointLight") then
				c.Brightness = 0.9
				c.Range = 16
			end
		end
	end
end

local function shopSpecific(model: Model, spec: Spec)
	local gy = spec.groundY
	local hw = spec.halfW
	local fz = spec.frontZ
	local d = spec.doorHalf
	if spec.kind == "HearthAndHome" then
		for _, x in ipairs({ -16, 16 }) do
			window(model, spec, x, 6.8, 3.6, 4.4, false)
		end
		awning(model, spec, 11.9, 4.2, hex("#3E6A3A"), hex("#F2E7CF"))
		planter(model, -10.3, gy, fz - 1.8)
		planter(model, 10.3, gy, fz - 1.8)
		bench(model, -16.5, gy, fz - 1.4)
		sandwichBoard(model, 17.5, gy, fz - 2.4, "HearthAndHome")
		barrel(model, hw - 2.2, gy, fz - 1.6)
		crate(model, hw - 4.4, gy, fz - 1.4, 1.7)
		chimney(model, -16, 8, spec.roofTop - 0.2, 5)
	elseif spec.kind == "Sparkworks" then
		sparkworksFront(model, spec)
	elseif spec.kind == "ToolShed" then
		-- (The grindstone and the chopping block stand out front, and the door
		-- header carries the hours board, so the yard has no planters or sandwich
		-- board; the barrel and the crate stand by the west wall.)
		barrel(model, -hw + 4.2, gy, fz - 2.4)
		crate(model, hw - 4.2, gy, fz - 2.6, 1.7)
		chimney(model, -6, 6, spec.roofTop - 2.4, 5)
	else
		-- The showroom: a canopy over the lobby door, planters, a bench and a
		-- sandwich board, a flag pole and roof units (its windows are the glass band).
		local c = spec.doorCx
		awning(
			model,
			spec,
			spec.doorTop + 0.7,
			ShopFacade.AwningReach - ShopFacade.AwningGap,
			hex("#2F6DB5"),
			hex("#F2E7CF"),
			ShopFacade.AwningGap
		)
		planter(model, c + d + 2.6, gy, fz - 1.8)
		planter(model, c - d - 2.6, gy, fz - 1.8)
		bench(model, c + d + 9, gy, fz - 1.4)
		box(model, "FlagPole", V3(0.25, 11, 0.25), CF(c + d + 21, gy + 5.5, fz - 1.4), IRON, MAT.Metal)
		box(model, "FlagCloth", V3(3.2, 2, 0.1), CF(c + d + 22.7, gy + 9.8, fz - 1.4), spec.accent, MAT.Fabric)
		box(model, "FlagLine", V3(6, 0.08, 0.08), CF(c + d + 24, gy + 10.6, fz - 1.4), IRON, MAT.Metal)
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
	if spec.kind ~= "Sparkworks" then
		doormat(model, spec)
	end
end

-- Adds the facade to the shop's model. See Spec.
function ShopFacade.Add(model: Model, spec: Spec)
	shopSpecific(model, spec)
end

return ShopFacade
