--!nocheck
-- The first look of a new world (phase-2/fix-world-first-look): the TO THE
-- WOODS sign as WorldPlan builds it (its lines come from
-- WorldPlan.WoodsSignLines), alone on grass in daylight, front and back and
-- close. Same part-built board and text as the town scene.
--   1 front   2 front, close   3 back   4 side   5 from the spawn walk
-- Studio keeps each uploaded Signpost piece where it sits in its model
-- (MeshKit: pivot "authored"); Lune has no pivots, so this scene puts each
-- piece at its GLB place from preview/a2-centres.json (see
-- tools/preview/v1_a2_meshes.py, town_centres()).
local fs = require("@lune/fs")
local serde = require("@lune/serde")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local root = roblox.Instance.new("Model")
		assert(fs.isFile("preview/a2-centres.json"), "write preview/a2-centres.json first (no stand-ins)")
		local centres = serde.decode("json", fs.readFile("preview/a2-centres.json"))
		Kit.part(root, "Ground", V3.new(60, 1, 60), CF.new(0, -0.5, 0), C3.fromRGB(116, 164, 78), Enum.Material.Grass)
		for _, sign in ipairs(WorldPlan.Town().signs) do
			if string.find(sign.text, "TO THE WOODS", 1, true) then
				-- Facing -Z at the origin (the sign's own front).
				local model = BuildingArt.Signpost(sign.text, sign.lit)
				Kit.placeAt(model, CF.new(0, 0, 0))
				for _, d in ipairs(model:GetDescendants()) do
					local at = d:IsA("MeshPart") and centres[tostring(d:GetAttribute("MeshId"))]
					if at then
						d.CFrame = CF.new(at[1], at[2], at[3]) * d.CFrame.Rotation
					end
				end
				model.Parent = root
			end
		end
		return {
			root = root,
			shadowRadius = 40,
			fov = 45,
			lighting = {
				sunDir = { -0.72, 0.5, -0.5 },
				sunColor = "#ffe2b0",
				sunIntensity = 2.5,
				skyTop = "#7fa6d6",
				skyBottom = "#f6cf98",
				ground = "#7a6a4c",
				hemiIntensity = 1.25,
				ambient = 0.45,
				bloom = 0.3,
			},
			cameras = {
				{ pos = { 0, 6.5, -22 }, target = { 0, 6.5, 0 }, fov = 40, label = "front" },
				{ pos = { 0, 7, -11 }, target = { 0, 7, 0 }, fov = 40, label = "front, close" },
				{ pos = { 0, 6.5, 22 }, target = { 0, 6.5, 0 }, fov = 40, label = "back" },
				{ pos = { 20, 6.5, -4 }, target = { 0, 6.5, 0 }, fov = 40, label = "side" },
				{ pos = { 8, 6.5, -16 }, target = { 0, 6.5, 0 }, fov = 60, label = "from the walk" },
			},
		}
	end,
}
