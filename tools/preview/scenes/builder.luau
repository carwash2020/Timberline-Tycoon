--!nocheck
-- Builder tools, as parts: a wall stretched to 16, a fence tiled to 16,
-- a ghost that would be refused, and three copies waiting to place.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local PlotData = ctx.shared("PlotData")
		local Models = ctx.shared("BlueprintModels")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 80, nil, roblox.Vector3.new(0, -0.5, 8))

		local function put(id, x, z, rot, len, color, ghost)
			local piece = PlotData.Blueprint(id)
			local model = Models.Build(piece, ghost == true)
			model.Parent = root
			if len then
				Models.ApplySize(model, piece, len, nil, nil)
			end
			if ghost then
				Models.SetFaded(model, true)
			end
			if color then
				for _, child in ipairs(model:GetDescendants()) do
					if child:IsA("BasePart") and child.Name ~= "Root" then
						child.Color = roblox.Color3.fromRGB(color[1], color[2], color[3])
					end
				end
			end
			Models.Place(model, roblox.CFrame.identity, x, z, rot or 0, 0)
		end

		put("Wall", 0, 0, 0, 16, nil, true)
		put("Fence", 0, 6, 0, 16, nil, false)
		put("Wall", 0, -6, 0, nil, { 255, 80, 80 }, true)
		put("Wall", 24, 0, 0, nil, nil, true)
		put("Wall", 24, 8, 0, nil, nil, true)
		put("Wall", 24, 16, 0, nil, nil, true)

		return {
			root = root,
			cameras = {
				{ pos = { 8, 5, 14 }, target = { 0, 3, 0 }, label = "wall" },
				{ pos = { 8, 4, 16 }, target = { 0, 1.5, 6 }, label = "fence" },
				{ pos = { 6, 4, 4 }, target = { 0, 3, -6 }, label = "refused" },
				{ pos = { 32, 8, 20 }, target = { 24, 3, 8 }, label = "copies" },
			},
		}
	end,
}
