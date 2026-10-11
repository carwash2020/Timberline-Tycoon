--!nocheck
-- Lane F (job 10): a furnished room, drawn the way the game draws it.
--   view 1  the room from the doorway: kit floor and walls (their real meshes),
--           furniture (part-built: the furniture meshes are job 17's), the two
--           crafted pieces, a sandstone wall with a copper trim
--   view 2  close-up: Copper Lamp Post, lit, with the Gold-banded Chest
--   view 3  close-up: the table, chairs, rug and shelf
--   view 4  the sandstone wall, arch and copper trim from the side
-- Kit pieces go through BlueprintModels.Build (KitMeshes.Dress puts their
-- meshes on); the four sandstone and copper pieces use their uploaded Body
-- meshes (the preview manifest), like v1-f-building.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Instance = roblox.Instance
		local PlotData = ctx.shared("PlotData")
		local Models = ctx.shared("BlueprintModels")
		local root = Instance.new("Model")
		Common.ground(ctx, root, 120, nil, V3.new(0, -0.5, 0))

		local MESH = {
			CopperTrim4 = { "87662133874242", V3.new(4.04, 0.73, 0.465), 0.365 },
			SandWall4 = { "120649476858651", V3.new(4.1, 6.637, 0.65), 3.3435 },
			SandFloor4 = { "81608834142851", V3.new(4.05, 0.32, 4.05), 0.14 },
			SandArch8 = { "140489088509915", V3.new(8.3, 7.675, 1.4), 3.8375 },
		}

		local function put(id, x, z, rot, y)
			local cf = CF.new(x, y or 0, z) * CF.Angles(0, (rot or 0) * math.pi / 2, 0)
			local mesh = MESH[id]
			if mesh then
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
			local model = Models.Build(PlotData.Blueprint(id), false)
			model.Parent = root
			Models.Place(model, CF.identity, x, z, rot or 0, y or 0)
			return model
		end

		-- The room: a foundation 16 x 16 (four Foundation8), walls round three
		-- sides, a door and a window in the front, a Floor on top of it.
		local fy = 2 -- Foundation8 top
		for _, dx in ipairs({ -4, 4 }) do
			for _, dz in ipairs({ -4, 4 }) do
				put("Foundation8", dx, dz, 0)
			end
		end
		for ix = -6, 6, 4 do
			for iz = -6, 6, 4 do
				put("Floor4", ix, iz, 0, fy)
			end
		end
		local wy = fy + 0.4
		put("DoorWall8", -4, 8, 0, wy)
		put("WindowWall8", 4, 8, 0, wy)
		for _, dx in ipairs({ -4, 4 }) do
			put("TallWall8", dx, -8, 0, wy)
		end
		-- The west wall is left out so the camera can see in (a cutaway).
		-- The east side is sandstone: three walls and an arch to the yard, with a
		-- copper trim along the top of the first.
		put("SandWall4", 8, -6, 1, wy)
		put("SandArch8", 8, 0, 1, wy)
		put("SandWall4", 8, 6, 1, wy)
		put("CopperTrim4", 8, -6, 1, wy + 6.6)

		-- Furniture on the floor top (2.4): grid positions, quarter turns.
		local ty = wy
		put("Rug", -2, 0, 0, ty)
		put("Table", -2, 0, 0, ty)
		put("Chair", -5, 0, 3, ty)
		put("Chair", 1, 0, 1, ty)
		put("Chair", -2, 3, 2, ty)
		put("Chair", -2, -3, 0, ty)
		put("Bookshelf", -4, -7, 0, ty)
		put("FirePit", 4, -5, 0, ty)
		-- The crafted pieces: a copper lamp post by the arch, a chest beside it.
		put("CopperLampPost", 6, 4, 0, ty)
		put("GoldChest", 5, 0, 1, ty)
		-- The yard past the arch.
		put("Bench", 14, 0, 1, 0)
		put("Barrel", 13, -6, 0, 0)
		put("Crate", 13, 6, 0, 0)

		local function cam(cx, cy, cz, tx, ty2, tz, label)
			return { pos = { cx, cy, cz }, target = { tx, ty2, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 90,
			fov = 45,
			cameras = {
				cam(-24, 15, 20, 1, 3, 0, "the room, west wall cut away"),
				cam(-6, 8, 13, 6, 3, 1, "the lamp post and the chest"),
				cam(-17, 8, 9, -3, 3, 0, "table, chairs, rug, shelf"),
				cam(26, 9, 14, 8, 3, 0, "sandstone wall, arch and copper trim"),
			},
		}
	end,
}
