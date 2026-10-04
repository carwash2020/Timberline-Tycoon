--!nocheck
-- The building kit as parts (meshes need Studio). A starter hut, a
-- two-storey frame in birch and oak, the door swung open, and 400 pieces.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local PlotData = ctx.shared("PlotData")
		local Models = ctx.shared("BlueprintModels")
		local Doors = ctx.load("ServerScriptService/PlotDoors")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 240, nil, roblox.Vector3.new(20, -0.5, 30))

		local function put(id, x, z, rot, y, wood, open)
			local model = Models.Build(PlotData.Blueprint(id), false)
			model.Parent = root
			Models.Place(model, roblox.CFrame.identity, x, z, rot or 0, y or 0)
			if wood then
				Models.ApplyWood(model, wood)
			end
			if open then
				Doors.Apply(model, id, true)
			end
		end

		-- Starter hut. Walls sit on the floor (y = 0.4). The door is open.
		put("Floor", 0, 0, 0, 0, "birch")
		put("Wall", 0, -4, 0, 0.4, "birch")
		put("Wall", -4, 0, 1, 0.4, "birch")
		put("WindowWall8", 4, 0, 1, 0.4, "oak")
		put("DoorWall8", 0, 4, 0, 0.4, "oak")
		put("Door", 0, 4, 0, 0.4, "oak", true)
		put("FlatRoof8", 0, 0, 0, 6.4, "oak")

		-- Two storeys: birch beside oak, stairs, railings, slopes and a ridge.
		local x = 28
		put("Floor", x, 0, 0, 0, "birch")
		put("Floor", x, 0, 0, 6, "oak")
		put("Stairs", x, 8, 0, 0, "birch")
		put("Railing8", x, 12, 0, 4, "birch")
		put("Wall", x - 4, 0, 1, 6.4, "birch")
		put("Wall", x + 4, 0, 1, 6.4, "oak")
		put("Railing8", x, -4, 0, 6.4, "birch")
		put("Railing8", x, 4, 0, 6.4, "oak")
		put("SlopedRoof8", x, 0, 0, 12.4, "birch")
		put("SlopedRoof8", x, 4, 2, 12.4, "oak")
		put("RoofRidge8", x, 2, 0, 12.4, "oak")
		put("FenceGate4", x, -10, 0, 0, "birch", true)

		-- 400 short walls, alternating birch and oak.
		for i = 0, 19 do
			for j = 0, 19 do
				put("Wall4", -40 + i * 4, 48 + j * 2, 0, 0, if (i + j) % 2 == 0 then "birch" else "oak")
			end
		end

		return {
			root = root,
			cameras = {
				{ pos = { 0, 7, 20 }, target = { 0, 3, 0 }, label = "hut" },
				{ pos = { 10, 16, 24 }, target = { 28, 7, 2 }, label = "frame" },
				{ pos = { 3, 3, 12 }, target = { 0, 3, 4 }, label = "door" },
				{ pos = { -8, 36, 78 }, target = { -2, 2, 66 }, label = "four hundred" },
			},
		}
	end,
}
