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

-- One faceted rock: a ridge, two wedges set back to back so their tall edges meet along the crest (a
-- pitched roof of stone). `cf` is the ridge's frame (its crest runs along local Z), `w` the width across
-- the foot, `h` the crest height over the foot and `len` the length. Both wedges are Slate and both are
-- looks only. Returns the frame, for the ore seams.
type Ridge = { cf: CFrame, w: number, h: number, len: number }

local function ridge(parent: Instance, cf: CFrame, w: number, h: number, len: number, color: Color3): Ridge
	-- A wedge's tall (back) face is its local +Z. The first wedge stands on the near half with its tall
	-- face on the middle line; the second is turned half a circle and stands on the far half.
	local front = Kit.wedge(
		parent,
		"Rock",
		Vector3.new(w, h, len / 2),
		cf * CFrame.new(0, 0, -len / 4),
		color,
		Enum.Material.Slate
	)
	local back = Kit.wedge(
		parent,
		"Rock",
		Vector3.new(w, h, len / 2),
		cf * CFrame.new(0, 0, len / 4) * CFrame.Angles(0, math.pi, 0),
		color,
		Enum.Material.Slate
	)
	Kit.decor(front)
	Kit.decor(back)
	return { cf = cf, w = w, h = h, len = len }
end

-- An ore seam laid on a ridge's skin: four short bars from (x, z) `from` to `to` in the ridge's frame, the
-- height read off the pitched roof (crest on the middle line z = 0, falling to the foot at both ends),
-- wandering a little, standing a hair proud so the ore reads as running through the stone.
local function seam(parent: Instance, r: Ridge, fromX: number, fromZ: number, toX: number, toZ: number, color: Color3)
	local wander = { 0, 0.1, -0.07, 0.08 }
	local function skin(x: number, z: number): Vector3
		local y = r.h / 2 - r.h * math.abs(z) / (r.len / 2) + 0.07
		return r.cf:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local last = skin(fromX, fromZ)
	for k = 1, 4 do
		local f = k / 4
		local here = skin(fromX + (toX - fromX) * f + wander[k], fromZ + (toZ - fromZ) * f)
		local bar = Kit.beam(parent, "Vein", last, here, 0.34 - k * 0.04, 0.22, color, Enum.Material.Metal)
		Kit.decor(bar, false)
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

	-- The stone: ridges (pairs of wedges, no cube and no ball), each turned a different way and tilted
	-- on all three axes, so no two faces line up. They sink into the ground a little and overlap into
	-- one faceted outcrop. a = yaw, pitch, roll.
	local function frame(x: number, y: number, z: number, yaw: number, pitch: number, roll: number): CFrame
		return CFrame.new(x, y, z) * CFrame.Angles(pitch, yaw + rng:range(-0.06, 0.06), roll)
	end
	local main = ridge(model, frame(0, 0.7, 0, 0.45, 0.06, 0.05), 2.4, 1.5, 2.6, cliff)
	local cross = ridge(model, frame(-0.1, 0.95, 0.05, 2.0, -0.05, 0.07), 2.0, 1.9, 2.0, slate)
	local spire = ridge(model, frame(-0.35, 1.75, 0.1, 0.9, 0.05, -0.06), 1.1, 1.7, 1.2, cliff)
	local lowA = ridge(model, frame(0.95, 0.35, -0.65, 3.6, 0.1, -0.08), 1.1, 0.9, 1.3, cliff)
	ridge(model, frame(-1.0, 0.3, -0.7, 5.0, -0.09, 0.07), 1.0, 0.8, 1.2, slate)
	ridge(model, frame(0.55, 0.3, 0.95, 0.8, 0.08, 0.1), 1.1, 0.8, 1.1, slate)
	ridge(model, frame(-1.2, 0.35, 0.7, 2.4, 0.09, -0.07), 1.0, 0.9, 1.1, cliff)
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
	-- Ore seams: along each big crest, and down the slope facing -Z (the way a node is most often met).
	seam(model, main, -0.8, 0, 0.8, 0, veinColor)
	seam(model, main, 0.4, -0.15, -0.2, -0.95, veinColor)
	seam(model, cross, -0.6, 0, 0.6, 0, veinColor)
	seam(model, cross, 0.3, -0.1, -0.1, -0.7, veinColor)
	seam(model, spire, -0.3, 0, 0.3, 0, veinColor)
	seam(model, lowA, -0.3, 0.05, 0.3, 0.05, veinColor)
	return model
end

return NodeArt
