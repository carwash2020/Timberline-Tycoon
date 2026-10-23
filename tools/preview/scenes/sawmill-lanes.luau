-- The Sawmill's part build on its own, with the T409 lane boxes drawn over it (tools/blender/lanes.json,
-- Shared/Lint/LaneData: slip, carriage, outfeed in blue, the office door in green) so a top-down shot shows
-- at a glance that nothing solid stands in them. Flat-colour preview, not Studio.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local LaneData = ctx.load("ReplicatedStorage/Shared/Lint/LaneData")
		local root = roblox.Instance.new("Model")

		Common.ground(ctx, root, 140, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 0))
		BuildingArt.Sawmill().Parent = root

		for _, lane in ipairs(LaneData.Boxes.Sawmill) do
			local size = lane.max - lane.min
			local box = Kit.part(
				root,
				"Lane_" .. lane.name,
				size,
				CF.new((lane.min + lane.max) / 2),
				if lane.kind == "door" then C3.fromRGB(60, 200, 90) else C3.fromRGB(70, 140, 255),
				Enum.Material.Neon
			)
			box.Transparency = 0.7
			box.CanCollide = false
		end

		return {
			root = root,
			shadowRadius = 100,
			cameras = {
				{
					pos = { 0, 110, 0.01 },
					target = { 0, 0, 0 },
					label = "top-down, lanes in blue, door in green",
					fov = 60,
				},
				{
					pos = { 28, 26, -30 },
					target = { 6, 3, -2 },
					label = "the slip and the carriage from the south-east",
				},
				{ pos = { -23, 7, -34 }, target = { -21, 5, -11 }, label = "the office door", fov = 70 },
				{ pos = { 0, 14, -34 }, target = { 0, 6, 0 }, label = "front, player eye" },
			},
		}
	end,
}
