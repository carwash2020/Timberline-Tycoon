--!strict
-- Kit: the building blocks every code-built model uses (GAME_DESIGN §13,
-- "cozy low-poly"). Pure: only Instance.new and datatypes, no services, so
-- the same code builds the game's models in Roblox and the previews in
-- tools/preview (Lune). Rules for art code:
--   * Place parts with .CFrame, never .Position (the preview reads CFrame).
--   * Everything is Anchored. Decoration doesn't collide, can't be clicked
--     or touched (Kit.decor); only what players stand on or bump into
--     collides.
--   * Determinism: variation comes from Kit.rng(seed), never math.random,
--     so a tree looks the same on every server and in the preview.

local Kit = {}

---------------------------------------------------------------------------
-- Random numbers you can reproduce
---------------------------------------------------------------------------

export type Rng = {
	next: (self: Rng) -> number, -- [0, 1)
	range: (self: Rng, lo: number, hi: number) -> number,
	int: (self: Rng, lo: number, hi: number) -> number,
	pick: <T>(self: Rng, list: { T }) -> T,
	sign: (self: Rng) -> number,
	state: number,
}

local RngMethods = {}
RngMethods.__index = RngMethods

function RngMethods.next(self: Rng): number
	-- xorshift32 on a 32-bit state; plenty for scattering leaves.
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x / 4294967296
end

function RngMethods.range(self: Rng, lo: number, hi: number): number
	return lo + (hi - lo) * self:next()
end

function RngMethods.int(self: Rng, lo: number, hi: number): number
	return math.min(hi, lo + math.floor((hi - lo + 1) * self:next()))
end

function RngMethods.pick<T>(self: Rng, list: { T }): T
	return list[self:int(1, #list)]
end

function RngMethods.sign(self: Rng): number
	return if self:next() < 0.5 then -1 else 1
end

-- A seeded generator. Any number works as a seed; 0 is nudged.
function Kit.rng(seed: number): Rng
	local s = math.floor(math.abs(seed) * 2654435761) % 4294967296
	if s == 0 then
		s = 0x9E3779B9
	end
	local r = setmetatable({ state = s }, RngMethods) :: any
	for _ = 1, 4 do
		r:next() -- warm up: nearby seeds drift apart
	end
	return r :: Rng
end

-- A stable seed from a position (so a tree planted in the same spot always
-- looks the same).
function Kit.seedAt(x: number, z: number): number
	return math.floor(x * 73.13 + z * 19.71) % 100000 + 1
end

---------------------------------------------------------------------------
-- Colour helpers
---------------------------------------------------------------------------

function Kit.hex(h: string): Color3
	return Color3.fromHex(h)
end

-- Lighter (amount > 0) or darker (amount < 0), keeping the hue.
function Kit.shade(c: Color3, amount: number): Color3
	if amount >= 0 then
		return c:Lerp(Color3.new(1, 1, 1), amount)
	end
	return c:Lerp(Color3.new(0, 0, 0), -amount)
end

-- A small random nudge in brightness and hue, for hand-painted variety.
function Kit.vary(c: Color3, rng: Rng, amount: number): Color3
	local h, s, v = c:ToHSV()
	h = (h + rng:range(-amount, amount) * 0.08) % 1
	s = math.clamp(s + rng:range(-amount, amount) * 0.3, 0, 1)
	v = math.clamp(v + rng:range(-amount, amount), 0, 1)
	return Color3.fromHSV(h, s, v)
end

---------------------------------------------------------------------------
-- Parts
---------------------------------------------------------------------------

local function setup(p: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?)
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

-- A block. Collides by default; call Kit.decor on looks-only parts.
function Kit.part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	setup(p, name, size, cf, color, material)
	p.Parent = parent
	return p
end

-- A wedge: full bottom and back (+Z) faces, the slope running from the top
-- of the back edge down to the bottom of the front (-Z) edge.
function Kit.wedge(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): WedgePart
	local p = Instance.new("WedgePart")
	setup(p, name, size, cf, color, material)
	p.Parent = parent
	return p
end

-- A cylinder `length` long along the CFrame's X axis.
function Kit.cylinder(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	setup(p, name, Vector3.new(length, diameter, diameter), cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	p.Parent = parent
	return p
end

-- An upright cylinder standing on `base` (a point), `height` tall.
function Kit.post(
	parent: Instance,
	name: string,
	base: Vector3,
	height: number,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	return Kit.cylinder(
		parent,
		name,
		height,
		diameter,
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material
	)
end

function Kit.ball(
	parent: Instance,
	name: string,
	diameter: number,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	setup(p, name, Vector3.new(diameter, diameter, diameter), cf, color, material)
	p.Shape = Enum.PartType.Ball
	p.Parent = parent
	return p
end

-- An ellipsoid (a block with a sphere mesh): `size` is its full extent.
function Kit.ellipsoid(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	setup(p, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	p.Parent = parent
	return p
end

-- A box from a to b (`width` x `height` cross-section), e.g. a plank or rail.
function Kit.beam(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	height: number,
	color: Color3,
	material: Enum.Material?
): Part
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local up = if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	return Kit.part(parent, name, Vector3.new(width, height, length), CFrame.lookAt(mid, b, up), color, material)
end

-- A cylinder from a to b, e.g. a branch, a rope, a pipe.
function Kit.rod(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	material: Enum.Material?
): Part
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	local up = if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
	-- lookAt points -Z at b; the cylinder runs along X, so turn it a quarter.
	return Kit.cylinder(
		parent,
		name,
		length,
		diameter,
		CFrame.lookAt(mid, b, up) * CFrame.Angles(0, math.pi / 2, 0),
		color,
		material
	)
end

-- Looks only: no collisions, no clicks or touches, and (for small parts)
-- no shadow. Returns the part for chaining.
function Kit.decor<T>(p: T & BasePart, castShadow: boolean?): T
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if castShadow == false then
		p.CastShadow = false
	end
	return p
end

-- Every BasePart under `root` becomes decoration (see Kit.decor), except
-- parts named in `keep`.
function Kit.decorAll(root: Instance, keep: { [string]: boolean }?)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and not (keep and keep[d.Name]) then
			Kit.decor(d)
		end
	end
end

---------------------------------------------------------------------------
-- Low-poly surfaces
---------------------------------------------------------------------------

-- A flat triangle a-b-c from two wedges (the classic Roblox trick). The
-- wedges are `thickness` thick, sitting on the side away from `inside`
-- when given (so a closed shape's outer faces are exactly the triangles).
-- Returns how many parts it made (0-2).
function Kit.triangle(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	color: Color3,
	material: Enum.Material?,
	thickness: number?,
	inside: Vector3?
): number
	local t = thickness or 0.1
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- Make bc the longest edge, a the apex across from it.
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-6 then
		return 0 -- degenerate
	end
	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local shift = Vector3.zero
	if inside then
		local center = (a + b + c) / 3
		local outward = if (center - inside):Dot(right) >= 0 then right else -right
		shift = -outward * (t / 2)
	end
	local made = 0
	local d1 = math.abs(ab:Dot(back))
	if d1 > 1e-3 and height > 1e-3 then
		local w1 = Kit.wedge(
			parent,
			"Facet",
			Vector3.new(t, height, d1),
			CFrame.fromMatrix((a + b) / 2 + shift, right, up, back),
			color,
			material
		)
		Kit.decor(w1)
		made += 1
	end
	local d2 = math.abs(ac:Dot(back))
	if d2 > 1e-3 and height > 1e-3 then
		local w2 = Kit.wedge(
			parent,
			"Facet",
			Vector3.new(t, height, d2),
			CFrame.fromMatrix((a + c) / 2 + shift, -right, up, -back),
			color,
			material
		)
		Kit.decor(w2)
		made += 1
	end
	return made
end

-- A cone of `sides` faceted triangles: base circle (radius) at `base`,
-- apex `height` above it. `twist` turns the facets; colours come from
-- colorFor(i) so faces can be shaded by hand. Open at the bottom.
function Kit.cone(
	parent: Instance,
	base: CFrame,
	radius: number,
	height: number,
	sides: number,
	colorFor: (number) -> Color3,
	material: Enum.Material?,
	thickness: number?,
	jitter: ((number) -> number)?
): number
	local apex = (base * CFrame.new(0, height, 0)).Position
	local ring: { Vector3 } = {}
	for i = 1, sides do
		local ang = (i - 1) / sides * math.pi * 2
		local r = radius * (if jitter then jitter(i) else 1)
		table.insert(ring, (base * CFrame.new(math.cos(ang) * r, 0, math.sin(ang) * r)).Position)
	end
	local inside = (base * CFrame.new(0, height * 0.3, 0)).Position
	local made = 0
	for i = 1, sides do
		local a, b = ring[i], ring[i % sides + 1]
		made += Kit.triangle(parent, a, b, apex, colorFor(i), material, thickness, inside)
	end
	return made
end

-- A cluster of tilted cubes: the cheap faceted "blob" low-poly canopies
-- and bushes are made of. `size` is the cluster's overall extent; returns
-- the parts so callers can recolour or tag them.
function Kit.blob(
	parent: Instance,
	name: string,
	center: CFrame,
	size: Vector3,
	count: number,
	rng: Rng,
	colors: { Color3 },
	material: Enum.Material?
): { Part }
	local out: { Part } = {}
	for i = 1, count do
		-- One big core cube, then smaller ones pushed out toward the
		-- surface of an ellipsoid, so the silhouette reads round.
		local s = if i == 1 then 0.66 else rng:range(0.36, 0.52)
		local offset = Vector3.zero
		if i > 1 then
			local theta = rng:range(0, math.pi * 2)
			local y = rng:range(-0.55, 0.85)
			local r = math.sqrt(1 - y * y)
			local reach = rng:range(0.22, 0.34)
			offset = Vector3.new(
				math.cos(theta) * r * reach * size.X,
				y * reach * size.Y,
				math.sin(theta) * r * reach * size.Z
			)
		end
		local cube = Vector3.new(size.X * s, size.Y * s, size.Z * s)
		local tilt = if i % 2 == 0
			then CFrame.Angles(math.rad(35.26), math.rad(45), 0) -- a corner pointing up: rounder
			else CFrame.Angles(rng:range(-0.5, 0.5), 0, rng:range(-0.5, 0.5))
		local cf = center * CFrame.new(offset) * CFrame.Angles(0, rng:range(0, math.pi * 2), 0) * tilt
		local color = Kit.vary(colors[(i - 1) % #colors + 1], rng, 0.05)
		local p = Kit.part(parent, name, cube, cf, color, material or Enum.Material.SmoothPlastic)
		Kit.decor(p)
		table.insert(out, p)
	end
	return out
end

-- A pitched roof: two wedges meeting at a ridge along the CFrame's X axis.
-- `cf` is the centre of the roof's base (the top of the walls); `width`
-- runs along the ridge, `depth` across it (eaves to eaves), `height` is
-- eaves to ridge.
function Kit.gableRoof(
	parent: Instance,
	name: string,
	cf: CFrame,
	width: number,
	depth: number,
	height: number,
	color: Color3,
	material: Enum.Material?
): { WedgePart }
	local half = depth / 2
	local w1 = Kit.wedge(
		parent,
		name,
		Vector3.new(width, height, half),
		cf * CFrame.new(0, height / 2, half / 2) * CFrame.Angles(0, math.pi, 0),
		color,
		material
	)
	local w2 = Kit.wedge(
		parent,
		name,
		Vector3.new(width, height, half),
		cf * CFrame.new(0, height / 2, -half / 2),
		color,
		material
	)
	return { w1, w2 }
end

-- Shingles: rows of thin, slightly staggered boards laid down a roof slope,
-- from the ridge (`ridge`, a point) out to the eave along `down` (a unit
-- vector down the slope) for `slopeLength`, `width` wide along `along`.
function Kit.shingles(
	parent: Instance,
	ridge: Vector3,
	down: Vector3,
	along: Vector3,
	slopeLength: number,
	width: number,
	rows: number,
	rng: Rng,
	colors: { Color3 },
	material: Enum.Material?
)
	local normal = along:Cross(down).Unit
	if normal.Y < 0 then
		normal = -normal
	end
	local rowLen = slopeLength / rows
	for r = 1, rows do
		local dist = (r - 0.5) * rowLen
		local center = ridge + down * dist + normal * 0.12
		local boards = math.max(2, math.floor(width / 2.2))
		local bw = width / boards
		local stagger = if r % 2 == 0 then bw / 2 else 0
		for i = 0, boards - 1 do
			local offset = -width / 2 + bw / 2 + i * bw + stagger
			if offset - bw / 2 < width / 2 - 0.05 then
				local w = math.min(bw, width / 2 - (offset - bw / 2))
				local pos = center + along * (offset - (bw - w) / 2)
				local cf = CFrame.fromMatrix(pos, along, normal, -down)
					* CFrame.Angles(math.rad(rng:range(-3, 3)) - 0.08, 0, 0)
				Kit.decor(
					Kit.part(
						parent,
						"Shingle",
						Vector3.new(w - 0.08, 0.18, rowLen * 1.15),
						cf,
						Kit.vary(rng:pick(colors), rng, 0.04),
						material or Enum.Material.WoodPlanks
					),
					false
				)
			end
		end
	end
end

-- A wall of horizontal planks: `cf` is the wall's centre, facing -Z (its
-- front). Each board gets a slightly different tone, like painted wood.
function Kit.plankWall(
	parent: Instance,
	name: string,
	cf: CFrame,
	width: number,
	height: number,
	thickness: number,
	boards: number,
	rng: Rng,
	colors: { Color3 },
	material: Enum.Material?
): { Part }
	local out: { Part } = {}
	local bh = height / boards
	for i = 1, boards do
		local y = -height / 2 + bh * (i - 0.5)
		local p = Kit.part(
			parent,
			name,
			Vector3.new(width, bh * 0.94, thickness + (if i % 2 == 0 then 0.06 else 0)),
			cf * CFrame.new(0, y, if i % 2 == 0 then -0.03 else 0),
			Kit.vary(rng:pick(colors), rng, 0.03),
			material or Enum.Material.WoodPlanks
		)
		table.insert(out, p)
	end
	return out
end

-- A low wall of rough stones (foundations, fire pits, wells): `cf` is the
-- centre of the course's base, running along X for `length`.
function Kit.stoneCourse(
	parent: Instance,
	cf: CFrame,
	length: number,
	height: number,
	depth: number,
	rng: Rng,
	colors: { Color3 }
)
	local x = -length / 2
	while x < length / 2 - 0.2 do
		local w = math.min(rng:range(1.1, 2.0), length / 2 - x)
		local h = height * rng:range(0.85, 1.05)
		local stone = Kit.part(
			parent,
			"Stone",
			Vector3.new(w - 0.08, h, depth * rng:range(0.9, 1.05)),
			cf * CFrame.new(x + w / 2, h / 2, 0) * CFrame.Angles(0, 0, math.rad(rng:range(-4, 4))),
			Kit.vary(rng:pick(colors), rng, 0.06),
			Enum.Material.Slate
		)
		Kit.decor(stone, false)
		x += w
	end
end

-- A faceted rock: a few tilted, overlapping blocks.
function Kit.rock(parent: Instance, cf: CFrame, size: number, rng: Rng, colors: { Color3 }): { Part }
	local parts = Kit.blob(
		parent,
		"Rock",
		cf * CFrame.new(0, size * 0.18, 0),
		Vector3.new(size * 1.2, size * 0.7, size),
		3,
		rng,
		colors,
		Enum.Material.Slate
	)
	return parts
end

-- A window: a frame, glass that glows warm at night (Neon when `lit`), and
-- a cross bar. `cf` is the window's centre on the wall face, facing -Z.
function Kit.window(parent: Instance, cf: CFrame, w: number, h: number, frame: Color3, lit: boolean)
	local glass = Kit.part(
		parent,
		"WindowGlass",
		Vector3.new(w, h, 0.2),
		cf,
		if lit then Color3.fromRGB(255, 196, 110) else Color3.fromRGB(150, 190, 210),
		if lit then Enum.Material.Neon else Enum.Material.Glass
	)
	Kit.decor(glass, false)
	local function bar(size: Vector3, offset: Vector3)
		Kit.decor(Kit.part(parent, "WindowFrame", size, cf * CFrame.new(offset), frame, Enum.Material.Wood), false)
	end
	bar(Vector3.new(w + 0.5, 0.25, 0.35), Vector3.new(0, h / 2 + 0.1, -0.05))
	bar(Vector3.new(w + 0.6, 0.3, 0.5), Vector3.new(0, -h / 2 - 0.1, -0.12)) -- sill
	bar(Vector3.new(0.25, h, 0.35), Vector3.new(w / 2 + 0.1, 0, -0.05))
	bar(Vector3.new(0.25, h, 0.35), Vector3.new(-w / 2 - 0.1, 0, -0.05))
	bar(Vector3.new(0.12, h, 0.3), Vector3.new(0, 0, -0.06))
	bar(Vector3.new(w, 0.12, 0.3), Vector3.new(0, 0, -0.06))
	return glass
end

-- A warm hanging lantern with a light; returns the glowing part.
function Kit.lantern(parent: Instance, cf: CFrame, scale: number?): Part
	local s = scale or 1
	local iron = Color3.fromRGB(45, 40, 38)
	Kit.decor(
		Kit.part(
			parent,
			"LanternCap",
			Vector3.new(0.9, 0.25, 0.9) * s,
			cf * CFrame.new(0, 0.7 * s, 0),
			iron,
			Enum.Material.Metal
		),
		false
	)
	Kit.decor(
		Kit.part(
			parent,
			"LanternBase",
			Vector3.new(0.8, 0.2, 0.8) * s,
			cf * CFrame.new(0, -0.6 * s, 0),
			iron,
			Enum.Material.Metal
		),
		false
	)
	local glow = Kit.part(
		parent,
		"LanternGlow",
		Vector3.new(0.6, 1.0, 0.6) * s,
		cf,
		Color3.fromRGB(255, 200, 110),
		Enum.Material.Neon
	)
	Kit.decor(glow, false)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 120)
	light.Range = 14 * s
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = glow
	return glow
end

-- Text on one or both faces of a board (signs), laid out at 40 pixels a
-- stud so the canvas takes the face's shape (a new SurfaceGui's default
-- fixed 800 x 600 canvas would stretch the text to fit). Returns the labels.
function Kit.signText(
	part: BasePart,
	text: string,
	color: Color3,
	faces: { Enum.NormalId }?,
	font: Enum.Font?
): { TextLabel }
	local out: { TextLabel } = {}
	for _, face in ipairs(faces or { Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0.6
		sg.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = font or Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextWrapped = true
		label.TextColor3 = color
		label.Text = text
		label.Parent = sg
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.06, 0)
		pad.PaddingRight = UDim.new(0.06, 0)
		pad.PaddingTop = UDim.new(0.08, 0)
		pad.PaddingBottom = UDim.new(0.08, 0)
		pad.Parent = label
		table.insert(out, label)
	end
	return out
end

-- Moves a model that was just built around the origin so its origin lands
-- on `cf` (e.g. a ground point). Its pivot keeps its own offset and turn
-- (a tree's pivot is its rotated trunk cylinder), so only use this right
-- after building, while the model still sits at the origin.
function Kit.placeAt(model: Model, cf: CFrame)
	model:PivotTo(cf * model:GetPivot())
end

-- A new Model with a name, parented (or not yet, if parent is nil).
function Kit.model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	if parent then
		m.Parent = parent
	end
	return m
end

return Kit
