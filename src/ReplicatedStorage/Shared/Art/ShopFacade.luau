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

export type FrameOpts = {
	postW: number?, -- the posts' width (default 0.9)
	proud: number?, -- how far the posts stand out from the wall (default 0.55)
	postTop: number?, -- the posts' top (default just under the awning)
	trim: Color3?, -- the posts' colour (default the cream trim)
	base: Color3?, -- the footing blocks' colour (default the stone grey)
}

ShopFacade.FrameGap = 0.75 -- the frame's posts start this far outside the opening, past the door leaves' swing (a leaf is 0.4 thick on the opening's edge)

-- A real DOOR FRAME round the opening, in final studs: two cream posts (pilasters) standing proud of the wall just
-- outside the opening, each on a stone footing block, and a flush stone THRESHOLD across the doorway (a looks-only
-- slab 0.12 thick, so there is no step to trip on: nothing collides). The wall's own jambs and header (the leaf the
-- shop hours recolour) are the inner frame; these are its outer trim. Nothing stands in the opening or in the
-- 2-stud walk to it. Reusable by any store: ShopFacade.DoorFrame(model, spec) with the same Spec as Add.
-- Parts: DoorPost x2, DoorPostBase x2, DoorThreshold.
function ShopFacade.DoorFrame(parent: Instance, spec: Spec, opts: FrameOpts?)
	local o: FrameOpts = opts or {}
	local postW = o.postW or 0.9
	local proud = o.proud or 0.55
	local gy = spec.groundY
	local top = o.postTop or (spec.doorTop + 0.65)
	local inner = spec.doorHalf + ShopFacade.FrameGap
	local trim = o.trim or TRIM
	local stone = o.base or hex("#8C867C")
	for _, s in ipairs({ -1, 1 }) do
		local x = spec.doorCx + s * (inner + postW / 2)
		-- (the post starts inside its footing and the footing sinks 0.05 into the wall: no two faces share a plane)
		box(
			parent,
			"DoorPost",
			V3(postW, top - gy - 0.35, proud),
			CF(x, (top + gy + 0.35) / 2, spec.frontZ - proud / 2 - 0.03),
			trim
		)
		box(
			parent,
			"DoorPostBase",
			V3(postW + 0.3, 0.6, proud + 0.3),
			CF(x, gy + 0.32, spec.frontZ - (proud + 0.3) / 2),
			stone,
			MAT.Slate
		)
	end
	-- the threshold: a flush stone slab across the doorway, beside the doormat (which starts 0.5 outside it)
	box(
		parent,
		"DoorThreshold",
		V3(2 * spec.doorHalf, 0.12, 0.4),
		CF(spec.doorCx, gy + 0.06, spec.frontZ + 0.7),
		stone,
		MAT.Slate
	)
end

export type AwningOpts = {
	backY: number, -- the canopy's top at the wall
	reach: number, -- how far it reaches out from the wall
	colorA: Color3,
	colorB: Color3,
	stripes: number?, -- stripes across (default 6)
	width: number?, -- default the door + 4
	tilt: number?, -- radians the front drops below the back (default 0.13)
	valance: number?, -- the front valance's height (default 0.7; every other piece is a third shorter: a stepped edge)
}

-- A STRIPED AWNING over the door, built of parts (no uploaded texture): `stripes` fabric slabs 0.18 thick in two
-- colours side by side, sloping out and down from the wall; a front VALANCE of the same stripes hanging from the front
-- edge, every other piece a third shorter so the edge steps like a scallop; two posts
-- to the ground and two brackets back to the wall. Everything stays clear of the door leaves when they swing out
-- (their tops are lower than the valance's bottom) and of the opening. Looks only. Reusable by any store.
-- Parts: AwningStripe x n, AwningValance x n, AwningPost x2, AwningBracket x2.
function ShopFacade.StripedAwning(parent: Instance, spec: Spec, o: AwningOpts)
	local n = o.stripes or 6
	local w = o.width or (spec.doorHalf * 2 + 4)
	local c = spec.doorCx
	local stripe = w / n
	local tilt = o.tilt or 0.13
	local thick = 0.18
	local reach = o.reach
	local z0 = spec.frontZ -- the wall's outside face
	local val = o.valance or 0.7
	-- the slab's middle: its back edge top is at backY on the wall, the front end drops by reach * sin(tilt)
	local midY = o.backY - (reach / 2) * math.sin(tilt) - (thick / 2) * math.cos(tilt)
	local midZ = z0 - (reach / 2) * math.cos(tilt)
	local frontTop = o.backY - reach * math.sin(tilt)
	local frontZ = z0 - reach * math.cos(tilt)
	for i = 1, n do
		local x = c - w / 2 + stripe * (i - 0.5)
		local color = if i % 2 == 0 then o.colorA else o.colorB
		box(
			parent,
			"AwningStripe",
			V3(stripe, thick, reach),
			CF(x, midY, midZ) * CFrame.Angles(-tilt, 0, 0),
			color,
			MAT.Fabric
		)
		-- the valance piece under the front edge (stepped: odd pieces hang shorter)
		local h = if i % 2 == 0 then val else val * 0.62
		box(
			parent,
			"AwningValance",
			V3(stripe, h, 0.12),
			CF(x, frontTop - thick - h / 2 + 0.02, frontZ + 0.04),
			color,
			MAT.Fabric
		)
	end
	local railY = frontTop - thick - 0.12
	for _, s in ipairs({ -1, 1 }) do
		local x = c + s * (w / 2 - 0.2)
		local postTop = railY + 0.05
		box(
			parent,
			"AwningPost",
			V3(0.3, postTop - spec.groundY, 0.3),
			CF(x, spec.groundY + (postTop - spec.groundY) / 2, frontZ + 0.2),
			TIMBER
		)
		-- a bracket from the post's head back to the wall under the slab
		local from = Vector3.new(x, railY - 0.15, frontZ + 0.2)
		local to = Vector3.new(x, railY - 0.15 - (reach - 0.3) * 0.18, z0 - 0.1)
		local len = (to - from).Magnitude
		box(parent, "AwningBracket", V3(0.2, 0.2, len), CFrame.lookAt((from + to) / 2, to), TIMBER)
	end
end

-- A warm wall lantern on a short iron arm, at the shop's front wall (x, y are
-- its middle). Modest light: never a white-out (ShopKit's caps: 1 / 22).
local function wallLamp(parent: Instance, spec: Spec, x: number, y: number)
	box(parent, "LampArm", V3(0.2, 0.2, 0.9), CF(x, y + 0.8, spec.frontZ - 0.45), IRON, MAT.Metal)
	local glow = Kit.lantern(parent, CF(x, y, spec.frontZ - 0.95), 0.9)
	for _, d in ipairs(glow:GetChildren()) do
		if d:IsA("PointLight") then
			d.Brightness = 0.9
			d.Range = 14
			d.Color = Color3.fromRGB(255, 206, 150)
		end
	end
end

-- The General Store's dressing beyond the shared kit: a stone plinth and timber
-- corner posts so the walls stand on something, a cornice under the roof, shutters
-- and flower boxes on the windows, lanterns either side of the door, shingle
-- strips on the roof, and a flagstone path from the street to the door with a
-- lamp post each side. All looks only; the doorway (x within doorHalf, below the
-- lintel) stays empty.
local function hearthDressing(model: Model, spec: Spec)
	local gy, hw, fz, d = spec.groundY, spec.halfW, spec.frontZ, spec.doorHalf
	local stone = hex("#8C867C")
	local green = hex("#3E6A3A")
	-- plinth in two pieces, leaving the doorway open
	local sideW = hw - d - 0.8
	for _, s in ipairs({ -1, 1 }) do
		box(
			model,
			"FoundationStone",
			V3(sideW, 1.0, 0.5),
			CF(s * (d + 0.8 + sideW / 2), gy + 0.5, fz - 0.2),
			stone,
			MAT.Slate
		)
		box(
			model,
			"CornerPost",
			V3(0.9, spec.wallTop - gy, 0.7),
			CF(s * (hw - 0.45), (spec.wallTop + gy) / 2, fz - 0.1),
			TIMBER
		)
	end
	-- (the cornice stops short of the hours board over the door: 3 studs each side of the middle)
	local corniceW = hw - 3
	for _, s in ipairs({ -1, 1 }) do
		box(
			model,
			"Cornice",
			V3(corniceW, 0.7, 0.7),
			CF(s * (3 + corniceW / 2), spec.wallTop - 0.35, fz - 0.15),
			TIMBER
		)
	end
	-- shutters beside each window
	for _, x in ipairs({ -16, 16 }) do
		for _, s in ipairs({ -1, 1 }) do
			box(model, "Shutter", V3(1.3, 4.4, 0.2), CF(x + s * 3.0, 7.3, fz - 0.15), green)
		end
	end
	-- two windows in each side wall, so the sides are not blank
	for _, s in ipairs({ -1, 1 }) do
		for _, zc in ipairs({ -8, 9 }) do
			local x = s * (hw + 0.4)
			box(model, "WindowFrame", V3(0.2, 5.4, 5.0), CF(x, 7.8, zc), TRIM)
			local pane =
				box(model, "WindowGlass", V3(0.2, 4.4, 3.6), CF(x + s * 0.2, 7.8, zc), hex("#BFD9E6"), MAT.Glass)
			pane.Transparency = 0.45
			pane.CastShadow = false
			box(model, "WindowSill", V3(0.9, 0.35, 5.6), CF(x + s * 0.2, 4.95, zc), TRIM)
		end
	end
	-- lanterns either side of the door, clear of the leaves
	for _, s in ipairs({ -1, 1 }) do
		wallLamp(model, spec, s * (d + 3.6), 8.2)
	end
	-- shingle strips along the roof (alternating tones)
	local roofW = 2 * hw - 1
	local n = 8
	for i = 1, n do
		box(
			model,
			"RoofShingle",
			V3(roofW / n - 0.1, 0.1, 40),
			CF(-roofW / 2 + roofW / n * (i - 0.5), spec.roofTop + 0.03, 0),
			if i % 2 == 0 then hex("#3A5E34") else hex("#2F4D2B"),
			MAT.WoodPlanks
		)
	end
	-- flagstone path from the street to the door, with a lamp post each side
	for i = 1, 3 do
		local off = if i % 2 == 0 then 0.5 else -0.5
		box(
			model,
			"PathStone",
			V3(4.6, 0.1, 1.6),
			CF(spec.doorCx + off, gy + 0.05, fz - 3.7 - (i - 1) * 2.0),
			if i % 2 == 0 then hex("#A29A8C") else hex("#938B7E"),
			MAT.Slate
		)
	end
	for _, s in ipairs({ -1, 1 }) do
		local x, z = spec.doorCx + s * (d + 2.2), fz - 7
		Kit.decor(Kit.post(model, "PathLampPost", V3(x, gy, z), 5.2, 0.35, IRON, MAT.Metal), false)
		local glow = Kit.lantern(model, CF(x, gy + 5.8, z), 0.9)
		for _, l in ipairs(glow:GetChildren()) do
			if l:IsA("PointLight") then
				l.Brightness = 0.9
				l.Range = 14
				l.Color = Color3.fromRGB(255, 206, 150)
			end
		end
	end
end

-- The Tool Shed's street side in the Hearth & Home restyle: the door frame (cream posts on stone footings, the shell's
-- own header above, a stone threshold) with a lantern on each post, a barn-red and cream striped awning over the door
-- (its back at 12.4: over the door track and under the hours board, which stands on the wall above it), two lit windows
-- in each long wall, and a flagstone path from the doormat to the street. The sliding barn-door leaves stand clear of
-- the posts when open (ShopDoor `openShift`). All looks only; the doorway and the 2-stud walk to it stay empty.
local function toolShedDressing(model: Model, spec: Spec)
	local hw, fz = spec.halfW, spec.frontZ
	local postX = spec.doorHalf + ShopFacade.FrameGap + 0.45
	-- The barn's floor is 0.75 above the lawn (a ramp climbs to the door), and everything out front stands on the LAWN:
	-- the door posts and the awning posts go down to y 0, not to the floor's level where they would hover.
	local lawn = table.clone(spec)
	lawn.groundY = 0
	ShopFacade.DoorFrame(model, lawn, { postTop = spec.doorTop + 0.75 })
	local threshold = model:FindFirstChild("DoorThreshold")
	if threshold and threshold:IsA("BasePart") then
		threshold.CFrame = threshold.CFrame + V3(0, spec.groundY, 0) -- (the threshold is in the doorway, at the floor's level)
	end
	ShopFacade.StripedAwning(model, lawn, {
		backY = 12.4,
		reach = 4.2,
		colorA = hex("#963E2C"),
		colorB = hex("#F2E7CF"),
		stripes = 6,
		tilt = 0.13,
		valance = 0.7,
	})
	-- a lantern on each door post: an iron arm out from the post's face and the lantern at its end
	for _, s in ipairs({ -1, 1 }) do
		local x = spec.doorCx + s * postX
		local faceZ = fz - 0.55 - 0.03
		box(model, "LampArm", V3(0.2, 0.2, 0.8), CF(x, 8.6, faceZ - 0.4), IRON, MAT.Metal)
		local glow = Kit.lantern(model, CF(x, 7.8, faceZ - 0.8), 0.8)
		for _, d in ipairs(glow:GetChildren()) do
			if d:IsA("PointLight") then
				d.Brightness = 0.9
				d.Range = 14
				d.Color = Color3.fromRGB(255, 206, 150)
				d.Shadows = false
			end
		end
	end
	-- two lit windows in each long wall (the sides were bare boards): a cream frame on the wall's outside face, the
	-- glass in front of it (it glows at night like every window), a sill under it
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -9, 9 }) do
			local x = side * (hw + 0.45)
			box(model, "SideWindowFrame", V3(0.3, 4.4, 4.4), CF(x + side * 0.15, 7.6, z), TRIM)
			local pane =
				box(model, "WindowGlass", V3(0.12, 3.6, 3.6), CF(x + side * 0.36, 7.6, z), hex("#BFD9E6"), MAT.Glass)
			pane.Transparency = 0.45
			pane.CastShadow = false
		end
	end
	-- a flagstone path from the doormat out to the lane (two stones, the doormat is 2.2 deep)
	local matEnd = fz - 2.65
	for i, depth in ipairs({ 2.0, 2.0 }) do
		box(
			model,
			"PathStone",
			V3(if i == 1 then 6 else 5.2, 0.15, depth),
			CF(spec.doorCx, 0.075, matEnd - depth * (i - 0.5)),
			if i == 1 then hex("#A39A86") else hex("#948B78"),
			MAT.Slate
		)
	end
	-- (the grindstone and the chopping block stand out front, so the yard has no planters or sandwich board)
	barrel(model, -hw + 0.9, 0, fz - 2.4)
	crate(model, hw - 2.6, 0, fz - 2.6, 1.7)
	chimney(model, -6, 6, spec.roofTop - 2.4, 5)
end

local function shopSpecific(model: Model, spec: Spec)
	local gy = spec.groundY
	local hw = spec.halfW
	local fz = spec.frontZ
	local d = spec.doorHalf
	if spec.kind == "HearthAndHome" then
		for _, x in ipairs({ -16, 16 }) do
			window(model, spec, x, 7.3, 3.6, 4.4, true)
		end
		hearthDressing(model, spec)
		ShopFacade.DoorFrame(model, spec)
		-- (the canopy is high and shallow so the door leaves swing out under its valance, and its top stays under
		-- the hours board over the door)
		ShopFacade.StripedAwning(model, spec, {
			backY = 12.6,
			reach = 4.0,
			colorA = hex("#3E6A3A"),
			colorB = hex("#F2E7CF"),
			stripes = 6,
			tilt = 0.12,
			valance = 0.7,
		})
		planter(model, -10.3, gy, fz - 1.8)
		planter(model, 10.3, gy, fz - 1.8)
		bench(model, -20.5, gy, fz - 1.4)
		sandwichBoard(model, 17.5, gy, fz - 2.4, "HearthAndHome")
		barrel(model, hw - 2.2, gy, fz - 1.6)
		crate(model, hw - 4.4, gy, fz - 1.4, 1.7)
		chimney(model, -16, 8, spec.roofTop - 0.2, 5)
	elseif spec.kind == "Sparkworks" then
		-- Two teal-framed windows, a teal and cream awning over the door, a
		-- planter each side, a barrel and a crate by the east wall and the
		-- sandwich board ("OPEN ALL DAY": Sparkworks has no hours).
		for _, x in ipairs({ -16, 16 }) do
			window(model, spec, x, 6.8, 3.6, 4.4, false)
		end
		awning(model, spec, 11.9, 4.2, spec.accent, hex("#F2E7CF"))
		planter(model, -10.3, gy, fz - 1.8)
		planter(model, 10.3, gy, fz - 1.8)
		sandwichBoard(model, 17.5, gy, fz - 2.4, "Sparkworks")
		barrel(model, hw - 2.2, gy, fz - 1.6)
		crate(model, hw - 4.4, gy, fz - 1.4, 1.7)
	elseif spec.kind == "ToolShed" then
		toolShedDressing(model, spec)
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
	doormat(model, spec)
end

-- Adds the facade to the shop's model. See Spec.
function ShopFacade.Add(model: Model, spec: Spec)
	shopSpecific(model, spec)
end

return ShopFacade
