--!nocheck
-- T420: a saved base across a plot's entrance. Three floors stand on the south
-- entrance (plot-local z -18); the red pad is where the spawn used to go
-- (under them), the green pad is where PlotLogic.SpawnSpot puts it now. Real
-- ground and the viewer's sun and shadows (three.js), not Studio lighting.
--   1 from the south, above   2 eye level at the new spawn pad

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local PlotData = ctx.shared("PlotData")
		local PlotPlatform = ctx.shared("PlotPlatform")
		local PlotLogic = ctx.shared("PlotLogic")
		local Models = ctx.shared("BlueprintModels")
		local root = roblox.Instance.new("Model")

		local index = 1
		local home = PlotData.Homes[index]
		local origin = PlotPlatform.Origin(index)
		local top = origin.Position.Y
		local size = PlotData.Tiers[1].size
		PlotPlatform.Build(root, PlotPlatform.Layout(size, {}), origin, PlotData.Look(index))

		local rects = {}
		for _, x in ipairs({ -8, 0, 8 }) do
			local bp = PlotData.Blueprint("Floor")
			local model = Models.Build(bp, false)
			model.Parent = root
			Models.Place(model, origin, x, -18, 0, 0)
			Models.ApplyWood(model, "oak")
			table.insert(rects, PlotLogic.RectOf(PlotLogic.Blueprint("Floor"), x, -18, 0))
		end
		local nx, nz = PlotLogic.SpawnSpot(size, rects)
		local function pad(name, x, z, color)
			local p = Kit.part(
				root,
				name,
				V3.new(PlotLogic.SpawnSize, 0.3, PlotLogic.SpawnSize),
				origin * CF.new(x, 0.45, z),
				color,
				Enum.Material.SmoothPlastic
			)
			p.CanCollide = false
		end
		pad("OldSpawn", PlotLogic.VisitPad[1], PlotLogic.VisitPad[2], C3.fromRGB(205, 60, 50))
		pad("NewSpawn", nx, nz, C3.fromRGB(70, 200, 90))

		local function eye(dx, dy, dz)
			return { home.x + dx, top + dy, home.z + dz }
		end
		return {
			root = root,
			terrain = Common.terrain(ctx, home.x - 120, home.z - 120, home.x + 120, home.z + 120, 2),
			shadowRadius = 200,
			lighting = { fogNear = 900, fogFar = 3000 },
			fov = 60,
			cameras = {
				{
					pos = eye(0, 38, -78),
					target = eye(0, 0, -14),
					label = "red: old spawn under the floors, green: where it goes now",
					fov = 60,
				},
				{
					pos = eye(nx + 14, 4.5, nz - 20),
					target = eye(nx, 2, nz + 4),
					label = "eye level, from the entrance side",
					fov = 65,
				},
			},
		}
	end,
}
