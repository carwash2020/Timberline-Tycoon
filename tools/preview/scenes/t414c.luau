--!nocheck
-- T414c: the Land Office and Sparkworks art builders, front 3/4, door level,
-- inside, from above, the door clearance overlay and a silhouette against the
-- sky. Run before and after the change on the same cameras. Preview only.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 400, C3.fromRGB(116, 164, 84), V3.new(20, -0.5, 0))

		local function place(model, x)
			Kit.placeAt(model, CF.new(x, 0, 0))
			model.Parent = root
		end
		place(BuildingArt.LandOffice(), 0)
		place(BuildingArt.Sparkworks(), 40)
		-- The door clearance overlay: the 8 wide x 10 tall opening and a 6 deep apron.
		local function overlay(x, frontZ, floorY)
			local box = Kit.part(
				root,
				"DoorOverlay",
				V3.new(8, 10, 6),
				CF.new(x, floorY + 5, frontZ - 3),
				C3.fromRGB(60, 200, 90),
				roblox.Enum.Material.SmoothPlastic
			)
			box.Transparency = 0.55
			Kit.decor(box, false)
		end
		overlay(0, -7, 0.4)
		overlay(40, -6, 0.5)

		return {
			root = root,
			shadowRadius = 90,
			fov = 50,
			cameras = {
				{ pos = { -20, 11, -26 }, target = { 0, 5.5, 0 }, label = "Land Office front 3/4" },
				{ pos = { 0, 4, 3 }, target = { 0, 4.5, 14 }, fov = 70, label = "Land Office inside" },
				{ pos = { 0, 70, 1 }, target = { 0, 0, 0 }, fov = 40, label = "Land Office top down" },
				{ pos = { 0, 5.5, -30 }, target = { 0, 5, 0 }, fov = 45, label = "Land Office eye level" },
				{ pos = { 20, 10, -22 }, target = { 40, 5, 0 }, label = "Sparkworks front 3/4" },
				{ pos = { 40, 4, 2 }, target = { 40, 4.5, 14 }, fov = 70, label = "Sparkworks inside" },
				{ pos = { 40, 70, 1 }, target = { 40, 0, 0 }, fov = 40, label = "Sparkworks top down" },
				{ pos = { 40, 5.5, -28 }, target = { 40, 5, 0 }, fov = 45, label = "Sparkworks eye level" },
				{ pos = { 20, 16, -34 }, target = { 20, 4, 0 }, fov = 55, label = "door clearance overlay, both" },
				{ pos = { 20, 1.5, -46 }, target = { 20, 16, 0 }, fov = 60, label = "silhouette against sky" },
			},
		}
	end,
}
