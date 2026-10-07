--!nocheck
-- The modern kit: the three sample builds (Shared/SampleBuilds) standing on
-- bare ground, as parts (the kit's meshes need Studio). A white and charcoal
-- two-storey house with picture windows, a balcony, inside stairs and a flat
-- overhanging roof; a boxy shop with a shop front, awning and sign post; a
-- wooden barn house. Cameras 1 to 4 are the house, 5 and 6 the shop, 7 the
-- barn, 8 all three, 9 the house's stairs and balcony close up.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local PlotData = ctx.shared("PlotData")
		local Models = ctx.shared("BlueprintModels")
		local Samples = ctx.shared("SampleBuilds")
		local Doors = ctx.load("ServerScriptService/PlotDoors")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 260, roblox.Color3.fromRGB(140, 120, 88), roblox.Vector3.new(0, -0.5, 0))

		local function stand(name, ox, oz, rot)
			local sample = Samples.Get(name)
			local items = Samples.Items(sample, rot, ox, oz, function(i)
				return name .. i
			end)
			for _, item in ipairs(items) do
				local bp = PlotData.Blueprint(item.blueprintId)
				local model = Models.Build(bp, false)
				model.Parent = root
				if bp.kit then
					Models.ApplySize(model, bp, item.len, item.lenX, item.lenZ)
				end
				Models.Place(model, roblox.CFrame.identity, item.x, item.z, item.rot, item.y or 0)
				if bp.kit then
					Models.ApplyWood(model, item.wood)
					Models.ApplyPaint(model, item.paint)
				end
				if bp.id == "Door" then
					Doors.Apply(model, bp.id, item.open == true)
				end
			end
		end

		stand("modern", 0, 0, 0)
		stand("shop", 44, 0, 0)
		stand("barn", -44, 0, 0)

		return {
			root = root,
			cameras = {
				{ pos = { -16, 9, -34 }, target = { 0, 6, -4 }, label = "house front" },
				{ pos = { 20, 10, 38 }, target = { 0, 6, 6 }, label = "house back" },
				{ pos = { -14, 34, -30 }, target = { 0, 4, 0 }, label = "house aerial" },
				{ pos = { 22, 8, -22 }, target = { 2, 6, -6 }, label = "house street" },
				{ pos = { 32, 6, -22 }, target = { 44, 4, -4 }, label = "shop front" },
				{ pos = { 60, 7, -16 }, target = { 44, 3, -2 }, label = "shop side" },
				{ pos = { -58, 7, -24 }, target = { -44, 4, 2 }, label = "barn" },
				{ pos = { 0, 38, -84 }, target = { 0, 2, -2 }, label = "all three" },
				{ pos = { -8, 12, -22 }, target = { -2, 8, -8 }, label = "balcony" },
			},
		}
	end,
}
