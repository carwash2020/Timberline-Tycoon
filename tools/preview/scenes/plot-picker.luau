--!nocheck
-- The plot picker's camera shot on a grown plot (T420). One 200-stud plot
-- (the top tier) on Birch Side's real terrain, a hut on it. 1 is the old
-- shot (the base 80-pad framing: PlotPickerMap.Shot with no size), 2 is the
-- new one (Shot(plot, 200): same side, further back, so the whole plot is
-- in frame). A flat-colour preview, not Studio: the picker's glide, fade and
-- UI are not drawn here.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local CF = roblox.CFrame
		local PlotData = ctx.shared("PlotData")
		local PlotPlatform = ctx.shared("PlotPlatform")
		local PlotPickerMap = ctx.shared("PlotPickerMap")
		local Models = ctx.shared("BlueprintModels")
		local root = roblox.Instance.new("Model")

		local index = 1
		local home = PlotData.Homes[index]
		local origin = PlotPlatform.Origin(index)
		local top = origin.Position.Y
		local size = 200
		PlotPlatform.Build(root, PlotPlatform.Layout(size, {}), origin, PlotData.Look(index))
		local function put(id, x, z, rot, y, wood)
			local model = Models.Build(PlotData.Blueprint(id), false)
			model.Parent = root
			Models.Place(model, origin, x, z, rot or 0, y or 0)
			if wood then
				Models.ApplyWood(model, wood)
			end
		end
		put("Floor", -60, 50, 0, 0, "birch")
		put("Wall", -60, 46, 0, 0.4, "birch")
		put("DoorWall8", -60, 54, 0, 0.4, "oak")
		put("Floor", 70, -60, 0, 0, "oak")

		local spot = { x = home.x, y = top, z = home.z }
		local function view(shot, label)
			return {
				pos = { shot.fromX, shot.fromY, shot.fromZ },
				target = { shot.atX, shot.atY, shot.atZ },
				label = label,
				fov = 70,
			}
		end
		return {
			root = root,
			terrain = Common.terrain(ctx, home.x - 330, home.z - 330, home.x + 330, home.z + 330, 4),
			shadowRadius = 400,
			lighting = { fogNear = 1500, fogFar = 4000 },
			fov = 70,
			cameras = {
				view(PlotPickerMap.Shot(spot), "old shot: base framing on a 200 plot"),
				view(PlotPickerMap.Shot(spot, size), "new shot: framing scaled to the plot"),
			},
		}
	end,
}
