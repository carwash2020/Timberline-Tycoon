--!nocheck
-- Lane F (job 10): building with the kit.
--   view 1  kit lineup: every kit piece, old and new (sandstone, copper)
--   view 2  a two-storey house from kit pieces only
--   view 3  snapping: a wall end joined (green ghost), a refused ghost (red)
--   view 4  close-up of the four V1 pieces (uploaded meshes)
-- The four V1 pieces draw their uploaded Body meshes (preview manifest);
-- the game keeps the part build until job 17 wires the meshes.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Instance = roblox.Instance
		local Kit = ctx.art("Kit")
		local PlotData = ctx.shared("PlotData")
		local BlueprintModels = ctx.shared("BlueprintModels")
		local root = Instance.new("Model")

		Kit.part(
			root,
			"Ground",
			V3.new(320, 1, 260),
			CF.new(0, -0.5, 0),
			C3.fromRGB(150, 172, 104),
			Enum.Material.Grass
		)

		-- Uploaded Body mesh per V1 piece: id, size, centre height above base.
		local MESH = {
			CopperTrim4 = { "87662133874242", V3.new(4.04, 0.73, 0.465), 0.365 },
			SandWall4 = { "120649476858651", V3.new(4.1, 6.637, 0.65), 3.3435 },
			SandFloor4 = { "81608834142851", V3.new(4.05, 0.32, 4.05), 0.14 },
			SandArch8 = { "140489088509915", V3.new(8.3, 7.675, 1.4), 3.8375 },
		}

		local function piece(id, x, z, rot, y, ghost)
			local cf = CF.new(x, y or 0, z) * CF.Angles(0, (rot or 0) * math.pi / 2, 0)
			local mesh = MESH[id]
			if mesh and not ghost then
				local m = Instance.new("Model")
				m.Name = id
				local part = Instance.new("MeshPart")
				part.Name = "Body"
				part.Size = mesh[2]
				part:SetAttribute("MeshId", mesh[1])
				part.CFrame = cf * CF.new(0, mesh[3], 0)
				part.Anchored = true
				part.Parent = m
				m.Parent = root
				return m
			end
			local model = BlueprintModels.Build(PlotData.Blueprint(id), ghost == true)
			model:PivotTo(cf)
			model.Parent = root
			return model
		end
		-- A placement ghost, drawn from the piece's boxes (the game's ghost is
		-- the part build tinted by a Highlight: green ok, red refused).
		local function ghost(id, x, z, rot, y, color)
			local bp = PlotData.Blueprint(id)
			local cf = CF.new(x, y or 0, z) * CF.Angles(0, (rot or 0) * math.pi / 2, 0)
			for i, box in ipairs(bp.boxes) do
				local part =
					Kit.part(root, "Ghost" .. i, box.size, cf * CF.new(box.offset), color, Enum.Material.SmoothPlastic)
				part.Transparency = 0.4
			end
		end

		-- View 1: the lineup, three rows along x around z = -70.
		local rows = {
			{ "Wall", "Wall4", "Wall12", "TallWall4", "TallWall8", "HalfWall8", "DoorWall8", "WindowWall8", "Fence" },
			{
				"Floor",
				"Floor4",
				"Foundation8",
				"Ramp8",
				"Stairs",
				"FlatRoof8",
				"SlopedRoof8",
				"RoofCorner",
				"RoofRidge8",
			},
			{
				"FenceGate4",
				"Post",
				"Beam8",
				"Railing8",
				"Door",
				"Window",
				"CopperTrim4",
				"SandWall4",
				"SandFloor4",
				"SandArch8",
			},
		}
		for r, list in ipairs(rows) do
			local x = -70
			for _, id in ipairs(list) do
				local bp = PlotData.Blueprint(id)
				local w = bp.footprint.X
				x += w / 2
				piece(id, x, -90 + r * 14, 0)
				x += w / 2 + 4
			end
		end

		-- View 2: a two-storey house, 16 x 16, at (0, 0, 60).
		local hx, hz = 0, 60
		for _, dx in ipairs({ -4, 4 }) do
			for _, dz in ipairs({ -4, 4 }) do
				piece("Foundation8", hx + dx, hz + dz, 0)
			end
		end
		-- Ground storey (base 2): tall walls, a door wall and window wall in front.
		piece("DoorWall8", hx - 4, hz + 8, 0, 2)
		piece("HalfWall8", hx - 4, hz + 8, 0, 8)
		piece("Beam8", hx - 4, hz + 8, 0, 11)
		piece("WindowWall8", hx + 4, hz + 8, 0, 2)
		piece("HalfWall8", hx + 4, hz + 8, 0, 8)
		piece("Beam8", hx + 4, hz + 8, 0, 11)
		for _, dx in ipairs({ -4, 4 }) do
			piece("TallWall8", hx + dx, hz - 8, 0, 2)
		end
		for _, sx in ipairs({ -8, 8 }) do
			for _, dz in ipairs({ -4, 4 }) do
				piece("TallWall8", hx + sx, hz + dz, 1, 2)
			end
		end
		-- Second floor on the tall wall tops (12), then the upper walls.
		for ix = -6, 6, 4 do
			for iz = -6, 6, 4 do
				piece("Floor4", hx + ix, hz + iz, 0, 12)
			end
		end
		for _, dx in ipairs({ -4, 4 }) do
			piece("WindowWall8", hx + dx, hz + 8, 0, 12.4)
			piece("Wall", hx + dx, hz - 8, 0, 12.4)
		end
		for _, sx in ipairs({ -8, 8 }) do
			for _, dz in ipairs({ -4, 4 }) do
				piece("Wall", hx + sx, hz + dz, 1, 12.4)
			end
		end
		-- Sloped roof, two rows each side, a ridge on top.
		local ry = 18.4
		for _, dx in ipairs({ -4, 4 }) do
			piece("SlopedRoof8", hx + dx, hz + 6, 2, ry)
			piece("SlopedRoof8", hx + dx, hz + 2, 2, ry + 3)
			piece("SlopedRoof8", hx + dx, hz - 6, 0, ry)
			piece("SlopedRoof8", hx + dx, hz - 2, 0, ry + 3)
			piece("RoofRidge8", hx + dx, hz, 0, ry + 3)
		end
		piece("Post", hx - 9, hz + 9, 0, 0)
		piece("Ramp8", hx - 4, hz + 13, 2, 0)

		-- View 3: snapping. Two walls placed; a green ghost joined to the
		-- end; a red ghost refused where it overlaps.
		local sx0, sz0 = 90, 0
		piece("Wall4", sx0, sz0, 0)
		piece("Wall4", sx0 + 2, sz0 + 2, 1)
		ghost("Wall4", sx0 - 4, sz0, 0, 0, C3.fromRGB(70, 200, 90)) -- end joined at x - 2
		ghost("Wall4", sx0 + 1, sz0 + 4, 0, 0, C3.fromRGB(220, 60, 50)) -- overlaps the turned wall
		piece("Foundation8", sx0 - 14, sz0, 0)
		ghost("Wall4", sx0 - 14, sz0 + 2, 0, 2, C3.fromRGB(70, 200, 90)) -- base on the foundation top

		-- View 4: the V1 pieces close up.
		piece("SandFloor4", -90, 0, 0)
		piece("SandFloor4", -86, 0, 0)
		piece("SandWall4", -90, -2, 0, 0.3)
		piece("SandArch8", -78, 2, 1, 0)
		piece("CopperTrim4", -90, -2, 0, 6.94)

		local function cam(cx, cy, cz, tx, ty, tz, label)
			return { pos = { cx, cy, cz }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 160,
			fov = 40,
			cameras = {
				cam(-18, 78, 2, -18, 0, -62, "kit lineup"),
				cam(34, 30, 100, 0, 9, 60, "two-storey house"),
				cam(84, 20, 26, 84, 2, 1, "snapping: green joined, red refused"),
				cam(-72, 16, 22, -84, 3, 0, "the V1 pieces"),
			},
		}
	end,
}
