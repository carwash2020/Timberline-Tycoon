--!nocheck
-- Every store model slot (Shared/StoreModelSlots) standing on a plain floor at its
-- fitted size, inside a marker of the slot's `fit` box (the item's part-built
-- size), so scale, yaw and pivot can be judged. Views: 1 all, then a front, a
-- three-quarter and a side per slot.
--   bash tools/preview/shoot.sh store-models-raw
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local Slots = ctx.shared("StoreModelSlots")
		local StoreModelArt = ctx.art("StoreModelArt")
		local root = roblox.Instance.new("Model")
		local Common = require("./_common")
		Common.ground(ctx, root, 200, C3.fromRGB(120, 150, 110))

		local cameras = {}
		local total = 0
		for _, slot in ipairs(Slots.All) do
			total += math.max(slot.fit.X, 2.5) + 1.5
		end
		local x = -total / 2
		for _, slot in ipairs(Slots.All) do
			local w = math.max(slot.fit.X, 2.5)
			local cx = x + w / 2
			x += w + 1.5
			local fit = slot.fit
			Kit.part(
				root,
				"Floor_" .. slot.id,
				V3.new(w + 0.4, 0.2, math.max(fit.Z, 2) + 0.4),
				CF.new(cx, 0.1, 0),
				C3.fromRGB(70, 60, 50),
				Enum.Material.Wood
			)
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					Kit.part(
						root,
						"Fit_" .. slot.id,
						V3.new(0.06, fit.Y, 0.06),
						CF.new(cx + sx * fit.X / 2, 0.2 + fit.Y / 2, sz * fit.Z / 2),
						C3.fromRGB(255, 80, 80),
						Enum.Material.Neon
					)
				end
			end
			local made = StoreModelArt.Build(slot, CF.new(cx, 0.2, 0), { parent = root })
			if not made then
				print("  no mesh for " .. slot.id)
			end
			local h = math.max(fit.Y, 2)
			table.insert(cameras, {
				pos = { cx, 0.2 + h * 0.6, -(w * 2.2 + 3) },
				target = { cx, 0.2 + h / 2, 0 },
				fov = 40,
				label = slot.id .. " front",
			})
			table.insert(cameras, {
				pos = { cx + w * 1.6 + 2, 0.2 + h * 0.9, -(w * 1.6 + 2) },
				target = { cx, 0.2 + h / 2, 0 },
				fov = 40,
				label = slot.id .. " three-quarter",
			})
			table.insert(cameras, {
				pos = { cx + (w * 2.4 + 3), 0.2 + h * 0.5, 0 },
				target = { cx, 0.2 + h / 2, 0 },
				fov = 40,
				label = slot.id .. " side",
			})
		end
		table.insert(cameras, 1, { pos = { 0, 14, -34 }, target = { 0, 2, 0 }, fov = 55, label = "all slots" })
		return { root = root, cameras = cameras }
	end,
}
