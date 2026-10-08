--!nocheck
-- Lane D: the hover price colours. Gold when you can pay, red when you cannot.
-- Closed, owned and out of stock stay plain.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF = roblox.Vector3, roblox.CFrame
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local HoverTag = ctx.shared("HoverTag")
		local root = roblox.Instance.new("Model")
		local cards = {
			{ "Can pay", HoverTag.CoinGold },
			{ "Too much", HoverTag.StopRed },
			{ "Closed", Kit.hex("#F4EBD0") },
		}
		for i, card in ipairs(cards) do
			local x = (i - 2) * 4.2
			local board =
				Kit.part(root, "Card", V3.new(3.4, 1.6, 0.12), CF.new(x, 1.4, 0), card[2], Enum.Material.SmoothPlastic)
			Kit.signText(board, card[1], Kit.hex("#2A2420"), { Enum.NormalId.Front })
		end
		Kit.part(root, "Ground", V3.new(18, 1, 8), CF.new(0, -0.5, 0), Kit.hex("#C49A63"), Enum.Material.WoodPlanks)
		return {
			root = root,
			shadowRadius = 16,
			fov = 32,
			cameras = {
				{
					pos = { 0, 1.6, -8 },
					target = { 0, 1.4, 0 },
					label = "hover price colours",
				},
			},
		}
	end,
}
