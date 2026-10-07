--!nocheck
-- A homestead's raised dark grey build platform (Shared/PlotPlatform), on
-- the real terrain of Birch Side (0, -350): the 110 tier plus four bought
-- squares, grass all round, a hut, a fence and a Logging Rig on the
-- platform, a Pickup on the grass nose to the south ramp. 1 from above, 2
-- close from the south, 3 at the south ramp's foot at eye height, 4 along
-- the south edge at ground level to show the 1-stud step, 5 at night.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF = roblox.Vector3, roblox.CFrame
		local Kit = ctx.art("Kit")
		local TruckArt = ctx.art("TruckArt")
		local PlotData = ctx.shared("PlotData")
		local PlotPlatform = ctx.shared("PlotPlatform")
		local Models = ctx.shared("BlueprintModels")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local TruckLayout = ctx.shared("TruckLayout")
		local root = roblox.Instance.new("Model")

		local index = 1
		local home = PlotData.Homes[index]
		local origin = PlotPlatform.Origin(index)
		local top = origin.Position.Y
		local layout = PlotPlatform.Layout(110, { "1,0", "1,1", "1,-1", "0,1" })
		PlotPlatform.Build(root, layout, origin, PlotData.Look(index))

		local function put(id, x, z, rot, y, wood)
			local model = Models.Build(PlotData.Blueprint(id), false)
			model.Parent = root
			Models.Place(model, origin, x, z, rot or 0, y or 0)
			if wood then
				Models.ApplyWood(model, wood)
			end
		end
		-- A hut with a door, a flat roof and a fence, standing on the top (y = 0).
		put("Floor", -20, 12, 0, 0, "birch")
		put("Wall", -20, 8, 0, 0.4, "birch")
		put("Wall", -24, 12, 1, 0.4, "birch")
		put("WindowWall8", -16, 12, 1, 0.4, "oak")
		put("DoorWall8", -20, 16, 0, 0.4, "oak")
		put("FlatRoof8", -20, 12, 0, 6.4, "oak")
		put("Floor", 30, -20, 0, 0, "oak")
		put("Stairs", 30, -10, 0, 0, "birch")

		-- A Logging Rig on the platform (its wheels on y = 0 plot-local), and a
		-- Pickup on the grass south of it, nose to the ramp.
		local function truck(id, cf)
			local def = ItemCatalog.GetTruck(id)
			local model = TruckArt.Build(def, TruckLayout.For(def))
			Kit.placeAt(model, cf)
			model.Parent = root
		end
		truck("LoggingRig", origin * CF.new(8, 0, -24) * CF.Angles(0, math.pi, 0))
		truck("Pickup", CF.new(home.x - 14, top - PlotData.PlatformHeight, home.z - 80) * CF.Angles(0, 0, 0))

		local function eye(dx, dy, dz)
			return { home.x + dx, top + dy, home.z + dz }
		end
		return {
			root = root,
			terrain = Common.terrain(ctx, home.x - 170, home.z - 170, home.x + 170, home.z + 170, 2),
			shadowRadius = 260,
			lighting = { fogNear = 900, fogFar = 3000 },
			fov = 60,
			cameras = {
				{ pos = eye(60, 230, -190), target = eye(0, 0, 0), label = "the platform from above" },
				{ pos = eye(-70, 40, -120), target = eye(0, 0, -10), label = "from the south, close", fov = 55 },
				{ pos = eye(-34, 4.5, -85), target = eye(-20, 0, -40), label = "eye: the south ramp's foot", fov = 70 },
				{
					pos = eye(-90, 1.5, -57),
					target = eye(0, 0, -57),
					label = "along the south edge, ground level",
					fov = 55,
				},
				{
					pos = eye(60, 230, -190),
					target = eye(0, 0, 0),
					label = "the platform from above, night",
					night = true,
				},
			},
		}
	end,
}
