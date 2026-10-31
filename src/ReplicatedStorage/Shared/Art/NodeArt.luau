--!strict
-- NodeArt: the look of a mineable node (NodeService): a rock outcrop with ore
-- veins, instead of the old crystal cluster. Pure parts (Instance.new and
-- datatypes only), so the game and the previews build the same node.
--
-- The model stands on the ground at the origin and is looks only: the hit box
-- NodeService makes (the part you aim at and bump into) is the collision, so
-- every part here is decor. The body is CliffRock and QuarrySlate boulders
-- (ellipsoids and a wedge: no cube anywhere), and the veins are thin ore
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

local function orient(at: Vector3, normal: Vector3): CFrame
	-- A part whose Y runs along the surface and up the boulder, X across it.
	local up = if math.abs(normal.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local side = up:Cross(normal).Unit
	local along = normal:Cross(side).Unit
	return CFrame.fromMatrix(at, side, along, normal)
end

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
	local last = skinPoint(c, r, theta, phi, 0)
	for k = 1, 4 do
		local here = skinPoint(c, r, theta + wander[k], phi + k * rise, 0)
		if (here - last).Magnitude > 0.05 then
			local bar = Kit.beam(parent, "Vein", last, here, 0.2 - k * 0.025, 0.12, color, Enum.Material.Metal)
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

	-- The boulders: centre, radii (full size = 2r), colour, turn and a tilt, so no two sit alike. Each
	-- sinks into the ground a little; the parts overlap into one outcrop.
	local bodies = {
		{ c = Vector3.new(0, 1.05, 0), r = Vector3.new(1.65, 1.15, 1.4), color = cliff, tilt = 0.08 },
		{ c = Vector3.new(-0.5, 1.85, 0.2), r = Vector3.new(0.95, 1.35, 0.85), color = slate, tilt = -0.18 },
		{ c = Vector3.new(0.95, 0.6, -0.65), r = Vector3.new(0.75, 0.7, 0.7), color = cliff, tilt = 0.25 },
		{ c = Vector3.new(-1.0, 0.45, -0.7), r = Vector3.new(0.65, 0.55, 0.6), color = slate, tilt = -0.3 },
		{ c = Vector3.new(0.5, 0.4, 1.1), r = Vector3.new(0.7, 0.5, 0.55), color = slate, tilt = 0.2 },
	}
	for _, b in ipairs(bodies) do
		local turn = CFrame.Angles(b.tilt, rng:range(0, math.pi), b.tilt * 0.6)
		local p = Kit.ellipsoid(model, "Rock", b.r * 2, CFrame.new(b.c) * turn, b.color, Enum.Material.Slate)
		Kit.decor(p)
	end
	-- One angular ledge, so the outline is not all round.
	local ledge = Kit.wedge(
		model,
		"RockFace",
		Vector3.new(1.6, 0.9, 1.1),
		CFrame.new(0.2, 0.3, 1.0) * CFrame.Angles(0, math.pi + rng:range(-0.4, 0.4), 0),
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
