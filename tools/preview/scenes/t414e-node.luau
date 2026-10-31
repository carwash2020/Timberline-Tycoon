--!nocheck
-- T414e: a mining node on the ground. Before T414e it is PropArt's crystal cluster (what NodeService
-- placed); after it, NodeArt's rock with ore veins. 1 close three-quarter, 2 top-down, 3 two nodes
-- side by side (Amber and Garnet) at eye level.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 120, C3.fromRGB(110, 160, 80))
		local okNode, NodeArt = pcall(ctx.art, "NodeArt")
		local function node(x, seed, ore)
			local look
			if okNode then
				look = NodeArt.Build(seed, ore)
			else
				look = ctx.art("PropArt").Crystal(seed, C3.fromHex("#9FD4FF"), 4)
			end
			Kit.placeAt(look, CF.new(x, 0, 0))
			look.Parent = root
		end
		node(-4, 3, "Amber")
		node(4, 4, "Garnet")
		return {
			root = root,
			fov = 45,
			cameras = {
				{ pos = { -4 - 6, 3.2, -8 }, target = { -4, 1.6, 0 }, label = "a node, three-quarter" },
				{ pos = { 0, 22, -1 }, target = { 0, 0, 0 }, label = "top-down" },
				{ pos = { 0, 2.4, -16 }, target = { 0, 1.8, 0 }, label = "two nodes, eye level" },
			},
		}
	end,
}
