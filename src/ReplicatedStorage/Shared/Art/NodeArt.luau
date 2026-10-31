--!strict
-- NodeArt: the look of a mineable node (NodeService): a rock outcrop with ore
-- veins, instead of the old crystal cluster. Pure parts (Instance.new and
-- datatypes only), so the game and the previews build the same node.
--
-- The model stands on the ground at the origin and is looks only: the hit box
-- NodeService makes (the part you aim at and bump into) is the collision, so
-- every part here is decor. The body is CliffRock and QuarrySlate faceted wedge
-- clusters (T416: no ellipsoid, no cube anywhere), and the veins are thin ore
-- ribbons laid on the boulders' skin in Amber or Garnet, half sunk so they
-- read as ore running through the stone. No Neon, no light.
--
-- Footprint: inside NodeArt.Footprint (the hit box's width and depth), at most
-- NodeArt.Height tall, so the hit box wraps the whole look.

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local NodeArt = {}

NodeArt.Footprint = Vector3.new(4.4, 0, 3.8) -- x and z of the hit box; y is NodeArt.Height
NodeArt.Height = 4.5
NodeArt.Veins = { "Amber", "Garnet" }
NodeArt.VeinHex = { Amber = "#D98A1E", Garnet = "#7A2038" } -- ore hex (style guide 15)

-- A vein on the ellipsoid (centre `c`, radii `r`): a chain of four short ore bars laid up the skin
-- from yaw `theta` and elevation `phi`, wandering a little, half sunk, so it reads as a seam of ore
-- running through the stone and not as one stuck-on disc.
local function skinPoint(c: Vector3, r: Vector3, theta: number, phi: number, lift: number): Vector3
	local dir = Vector3.new(math.cos(phi) * math.cos(theta), math.sin(phi), math.cos(phi) * math.sin(theta))
	local normal = Vector3.new(dir.X / r.X, dir.Y / r.Y, dir.Z / r.Z).Unit
	return c + Vector3.new(dir.X * r.X, dir.Y * r.Y, dir.Z * r.Z) + normal * lift
end

local function vein(parent: Instance, c: Vector3, r: Vector3, theta: number, phi: number, length: number, color: Color3)
	local wander = { 0, 0.14, -0.08, 0.12 }
	local rise = length / 3 / math.max(r.Y, 0.5)
	local last = skinPoint(c, r, theta, phi, 0.05)
	for k = 1, 4 do
		local here = skinPoint(c, r, theta + wander[k], phi + k * rise, 0.05)
		if (here - last).Magnitude > 0.05 then
			local bar = Kit.beam(parent, "Vein", last, here, 0.3 - k * 0.04, 0.2, color, Enum.Material.Metal)
			Kit.decor(bar, false)
		end
		last = here
	end
end

-- seed picks the turn and which ore; `ore` forces "Amber" or "Garnet".
function NodeArt.Build(seed: number, ore: string?): Model
	local model = Kit.model("Look")
	local rng = Kit.rng(seed)
	local oreName = ore or (if seed % 3 == 0 then "Garnet" else "Amber")
	local veinColor = Kit.hex(NodeArt.VeinHex[oreName] or NodeArt.VeinHex.Amber)
	local cliff, slate = Palette.CliffRock, Palette.QuarrySlate

	-- The stone: a cluster of faceted wedges, every one turned off the axes (yaw, pitch and roll all
	-- different) so no two faces line up and nothing is a cube or a ball. Each sinks into the ground a
	-- little and the facets overlap into one outcrop. `c` is the centre, `size` the wedge's box, `a` the
	-- yaw, pitch and roll; `r` is the radii of the ellipsoid the ore bars are laid on (a hair inside the
	-- facets, so the ore shows through them).
	local bodies = {
		{
			c = Vector3.new(0, 0.95, 0),
			size = Vector3.new(2.6, 1.9, 2.0),
			a = { 0.45, 0.14, 0.1 },
			color = cliff,
			r = Vector3.new(1.15, 0.85, 0.95),
		},
		{
			c = Vector3.new(-0.45, 1.9, 0.15),
			size = Vector3.new(1.5, 2.4, 1.3),
			a = { 2.0, -0.15, 0.12 },
			color = slate,
			r = Vector3.new(0.6, 1.1, 0.55),
		},
		{
			c = Vector3.new(0.95, 0.55, -0.65),
			size = Vector3.new(1.3, 1.1, 1.2),
			a = { 3.5, 0.2, -0.15 },
			color = cliff,
			r = Vector3.new(0.5, 0.45, 0.5),
		},
		{
			c = Vector3.new(-1.0, 0.4, -0.7),
			size = Vector3.new(1.2, 0.9, 1.1),
			a = { 5.0, -0.2, 0.1 },
			color = slate,
			r = Vector3.new(0.45, 0.35, 0.45),
		},
		{
			c = Vector3.new(0.55, 0.4, 0.95),
			size = Vector3.new(1.3, 0.9, 1.0),
			a = { 0.8, 0.15, 0.2 },
			color = slate,
			r = Vector3.new(0.5, 0.35, 0.4),
		},
		{
			c = Vector3.new(-1.2, 0.5, 0.7),
			size = Vector3.new(1.1, 1.0, 1.0),
			a = { 2.4, 0.18, -0.12 },
			color = cliff,
			r = Vector3.new(0.4, 0.4, 0.4),
		},
		{
			c = Vector3.new(0.1, 2.4, -0.1),
			size = Vector3.new(0.9, 1.4, 0.8),
			a = { 4.0, 0.2, 0.15 },
			color = cliff,
			r = Vector3.new(0.3, 0.55, 0.3),
		},
	}
	for _, b in ipairs(bodies) do
		local turn = CFrame.Angles(b.a[2], b.a[1] + rng:range(-0.08, 0.08), b.a[3])
		local p = Kit.wedge(model, "Rock", b.size, CFrame.new(b.c) * turn, b.color, Enum.Material.Slate)
		Kit.decor(p)
	end
	-- One angular ledge low on the front, so the outline is broken at the foot as well.
	local ledge = Kit.wedge(
		model,
		"RockFace",
		Vector3.new(1.5, 0.8, 1.0),
		CFrame.new(0.2, 0.3, 1.0) * CFrame.Angles(0.12, math.pi + 0.5 + rng:range(-0.2, 0.2), -0.1),
		slate,
		Enum.Material.Slate
	)
	Kit.decor(ledge)
	local yaw = -math.pi / 2 + rng:range(-0.5, 0.5) -- the first seam faces -Z, the way a node is most often met
	local main, tall = bodies[1], bodies[2]
	vein(model, main.c, main.r, yaw, 0.35, 1.7, veinColor)
	vein(model, main.c, main.r, yaw + 0.5, 0.15, 1.2, veinColor)
	vein(model, tall.c, tall.r, yaw + 2.2, 0.25, 1.5, veinColor)
	vein(model, tall.c, tall.r, yaw + 3.4, 0.55, 1.0, veinColor)
	vein(model, bodies[3].c, bodies[3].r, yaw + 4.4, 0.4, 0.8, veinColor)
	vein(model, main.c, main.r, yaw + math.pi, 0.3, 1.5, veinColor) -- and one round the back
	return model
end

return NodeArt
