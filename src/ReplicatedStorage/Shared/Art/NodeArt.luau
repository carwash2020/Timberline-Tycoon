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

-- A vein ribbon on the ellipsoid (centre `c`, radii `r`) at yaw `theta` and
-- elevation `phi`: its middle `sink` studs inside the skin.
local function vein(
	parent: Instance,
	c: Vector3,
	r: Vector3,
	theta: number,
	phi: number,
	length: number,
	color: Color3
): Part
	local dir = Vector3.new(math.cos(phi) * math.cos(theta), math.sin(phi), math.cos(phi) * math.sin(theta))
	local skin = c + Vector3.new(dir.X * r.X, dir.Y * r.Y, dir.Z * r.Z)
	-- The outward normal of an ellipsoid at that point.
	local normal = Vector3.new(dir.X / r.X, dir.Y / r.Y, dir.Z / r.Z).Unit
	local p = Kit.ellipsoid(
		parent,
		"Vein",
		Vector3.new(0.34, length, 0.22),
		orient(skin - normal * 0.06, normal),
		color,
		Enum.Material.Metal
	)
	return Kit.decor(p, false)
end

-- seed picks the turn and which ore; `ore` forces "Amber" or "Garnet".
function NodeArt.Build(seed: number, ore: string?): Model
	local model = Kit.model("Look")
	local rng = Kit.rng(seed)
	local oreName = ore or (if seed % 3 == 0 then "Garnet" else "Amber")
	local veinColor = Kit.hex(NodeArt.VeinHex[oreName] or NodeArt.VeinHex.Amber)
	local cliff, slate = Palette.CliffRock, Palette.QuarrySlate

	-- The boulders: centre, radii (full size = 2r), colour. Each sinks 0.15 into the ground.
	local bodies = {
		{ c = Vector3.new(0, 1.15, 0), r = Vector3.new(1.75, 1.3, 1.5), color = cliff },
		{ c = Vector3.new(-0.55, 1.95, 0.25), r = Vector3.new(1.05, 1.5, 0.95), color = slate },
		{ c = Vector3.new(1.0, 0.7, -0.7), r = Vector3.new(0.8, 0.85, 0.75), color = cliff },
	}
	for i, b in ipairs(bodies) do
		local turn = CFrame.Angles(0, rng:range(0, math.pi), 0)
		local p = Kit.ellipsoid(model, "Rock", b.r * 2, CFrame.new(b.c) * turn, b.color, Enum.Material.Slate)
		Kit.decor(p)
		if i == 1 then
			-- an angular shoulder, so the outline is not all round
			local w = Kit.wedge(
				model,
				"RockFace",
				Vector3.new(1.5, 1.1, 1.3),
				CFrame.new(0.15, 0.65, 0.95) * CFrame.Angles(0, math.pi + rng:range(-0.4, 0.4), 0),
				slate,
				Enum.Material.Slate
			)
			Kit.decor(w)
		end
	end
	local yaw = rng:range(0, math.pi * 2)
	local main, tall = bodies[1], bodies[2]
	vein(model, main.c, main.r, yaw, 0.35, 1.7, veinColor)
	vein(model, main.c, main.r, yaw + 0.5, 0.15, 1.2, veinColor)
	vein(model, tall.c, tall.r, yaw + 2.2, 0.25, 1.5, veinColor)
	vein(model, tall.c, tall.r, yaw + 3.4, 0.55, 1.0, veinColor)
	vein(model, bodies[3].c, bodies[3].r, yaw + 4.4, 0.4, 0.8, veinColor)
	return model
end

return NodeArt
