--!nocheck
-- Furniture and wired pieces as parts (DecorData, LogicItems): a cabin
-- corner with a table, chairs, a shelf and a rug, a yard with a fire pit,
-- barrels and crates, and a switch beside a lit lamp and an unlit one.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local PlotData = ctx.shared("PlotData")
		local Models = ctx.shared("BlueprintModels")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 120, nil, roblox.Vector3.new(0, -0.5, 0))

		local function put(id, x, z, rot, y)
			local model = Models.Build(PlotData.Blueprint(id), false)
			model.Parent = root
			Models.Place(model, roblox.CFrame.identity, x, z, rot or 0, y or 0)
			return model
		end

		-- A room: floor, back wall, table with four chairs, shelf, rug.
		put("Floor", 0, 0, 0, 0)
		put("Floor", 8, 0, 0, 0)
		put("Wall", 0, -4, 0, 0.4)
		put("Wall", 8, -4, 0, 0.4)
		put("Rug", 2, 0, 0, 0.4)
		put("Table", 2, 0, 0, 0.4)
		put("Chair", -1, 0, 3, 0.4)
		put("Chair", 5, 0, 1, 0.4)
		put("Chair", 2, 3, 2, 0.4)
		put("Bookshelf", 10, -3, 0, 0.4)

		-- The yard.
		put("FirePit", -14, 6, 0)
		put("Barrel", -18, -2, 0)
		put("Crate", -16, -2, 0)
		put("Crate", -16, -2, 0, 1.8)
		put("Bench", -14, 12, 2)

		-- Wiring: a switch, a lit lamp (not wired yet) and a dark one.
		put("SparkSwitch", 18, 8, 0)
		put("SparkLamp", 24, 6, 0)
		local dark = put("SparkLamp", 24, 12, 0)
		for _, d in ipairs(dark:GetDescendants()) do
			if d:IsA("PointLight") then
				d.Enabled = false
			elseif d:IsA("BasePart") and d.Material == roblox.Enum.Material.Neon then
				d.Material = roblox.Enum.Material.SmoothPlastic
				d.Color = roblox.Color3.fromRGB(88, 84, 76)
			end
		end

		return {
			root = root,
			cameras = {
				{ pos = { 4, 9, 18 }, target = { 4, 1.5, 0 }, label = "room" },
				{ pos = { -8, 8, 18 }, target = { -15, 1, 2 }, label = "yard" },
				{ pos = { 20, 7, 20 }, target = { 22, 3, 8 }, label = "wiring" },
			},
		}
	end,
}
