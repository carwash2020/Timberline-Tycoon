--!nocheck
-- The landmarks' builders on a showcase lot (Shared/Art/LandmarkArt,
-- phase 10, STY-03 and STY-04): a brown boulder cluster, the timber
-- footbridge over a channel, a plank dock with its rowboat, and the
-- lighthouse. world-landmarks.luau shows them where MapBuilder puts them.
-- 1 the lot, 2 the footbridge, 3 on its deck, 4 the dock and rowboat,
-- 5 the lighthouse, 6 its lamp room, 7 the dock at night, 8 the lighthouse
-- at night.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local LandmarkArt = ctx.art("LandmarkArt")
		local BuildingArt = ctx.art("BuildingArt")
		local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
		local root = roblox.Instance.new("Model")
		local grass = TerrainGen.MaterialColors.Grass
		local bed = TerrainGen.MaterialColors.Mud
		local water = C3.fromRGB(62, 140, 150)

		local function place(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
			return model
		end
		local function slab(name, x0, x1, z0, z1, top, color, material)
			local p = Kit.part(
				root,
				name,
				V3.new(x1 - x0, 2, z1 - z0),
				CF.new((x0 + x1) / 2, top - 1, (z0 + z1) / 2),
				color,
				material or Enum.Material.Grass
			)
			return p
		end
		local function waterPlate(x0, x1, z0, z1, top)
			local p = slab("Water", x0, x1, z0, z1, top, water, Enum.Material.Glass)
			p.Transparency = 0.35
		end

		-- A boulder cluster (as WorldPlan lays one out: a big rock, smaller ones leaning on it).
		slab("Ground", -70, -20, -30, 20, 0, grass)
		for i, r in ipairs({ { 0, 0, 8 }, { 6.5, 3, 4 }, { -5, 4.5, 3.2 }, { 1.5, -6, 4.6 }, { -6, -4, 2.6 } }) do
			local size = r[3]
			place(
				LandmarkArt.BrownRock(size, 100 + i * 7, 1 + i % 2, i == 1),
				CF.new(-45 + r[1], -(0.5 + 0.1 * size), -5 + r[2]) * CF.Angles(0, i * 1.7, 0)
			)
		end

		-- The footbridge over a channel: banks at 0, the water at -2, its bed at -9.
		local span = 36
		slab("Bank", -15, 15, 0, 20, 0, grass)
		slab("Bank", -15, 15, -span - 20, -span, 0, grass)
		slab("RiverBed", -15, 15, -span, 0, -9, bed, Enum.Material.Mud)
		waterPlate(-15, 15, -span + 5, -5, -2)
		slab("Bank", -15, 15, -5, 0, -1, grass)
		slab("Bank", -15, 15, -span, -span + 5, -1, grass)
		place(LandmarkArt.Footbridge(span, 0, 7, 1.6, { 0, -7, -9, -7, 0 }), CF.new(0, 0, 0))
		place(BuildingArt.Signpost("TIMBER BRIDGE"), CF.new(-11.3, 0, 4) * CF.Angles(0, math.pi, 0))

		-- A dock out over the water, its rowboat alongside.
		slab("Shore", 30, 60, 0, 20, 0, grass)
		slab("Sea bed", 30, 60, -40, 0, -8, TerrainGen.MaterialColors.Sand, Enum.Material.Sand)
		waterPlate(30, 60, -40, 0, -1)
		local dock = place(LandmarkArt.Dock(26, 5, 0.3, -1, { -0.3, -2.7, -5, -7.4 }), CF.new(45, 0, 2))
		place(LandmarkArt.Rowboat(17), CF.new(45 - 4.5, -1, 2 - 20) * CF.Angles(0, math.pi + 0.12, 0))
		local _ = dock

		-- The lighthouse on the sand.
		slab("Sand", 75, 125, -30, 20, 0, TerrainGen.MaterialColors.Sand, Enum.Material.Sand)
		place(LandmarkArt.Lighthouse(), CF.new(100, 0, -5))

		return {
			root = root,
			lighting = { fogNear = 400, fogFar = 1400 },
			shadowRadius = 120,
			fov = 50,
			cameras = {
				{ pos = { 30, 70, 95 }, target = { 30, 10, -15 }, label = "the lot" },
				{ pos = { 26, 9, -8 }, target = { 0, 1, -18 }, label = "the footbridge" },
				{ pos = { 0, 6.5, 2 }, target = { 0, 6, -36 }, label = "on the footbridge" },
				{ pos = { 62, 8, 12 }, target = { 44, 0, -14 }, label = "the dock and its rowboat" },
				{ pos = { 140, 22, 45 }, target = { 100, 26, -5 }, label = "the lighthouse" },
				{ pos = { 110, 50, 6 }, target = { 100, 48, -5 }, label = "its lamp room" },
				{ pos = { 62, 8, 12 }, target = { 44, 0, -14 }, label = "the dock at night", night = true },
				{ pos = { 140, 22, 45 }, target = { 100, 30, -5 }, label = "the lighthouse at night", night = true },
			},
		}
	end,
}
