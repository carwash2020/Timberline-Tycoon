--!nocheck
-- Hearth & Home's event room, shown ACTIVE (ropes down, lamp on, banner up): the roped zone in the back west corner
-- and the banner in the front west corner. Views: 1 the zone from the aisle, 2 the zone from the counter side, 3 the
-- banner from the door. The other store scenes show it as the game does until an event runs (rope up, banner hidden).
local Store = require("./_store")

return Store.scene({
	kind = "HearthAndHome",
	title = "HEARTH & HOME",
	accent = { 47, 93, 58 },
	keeper = "Hazel",
	slotModels = true,
	populate = function(ctx, _root, shop)
		local Kit = ctx.art("ShopEventKit")
		for _, d in ipairs(shop:GetDescendants()) do
			if d.Name == "EventExpansion" then
				Kit.SetZoneActive(d, true)
			elseif d.Name == "EventBanner" and d:IsA("BasePart") then
				Kit.SetBannerActive(d, true, "TEST DAY")
			end
		end
	end,
	cameras = function()
		return {
			entrance = { pos = { -14.6, 8.5, 1 }, target = { -14.6, 2.5, 17 }, fov = 62 },
			tierStand = { pos = { 2, 9, 9 }, target = { -14.6, 2, 17 }, fov = 62 },
			phone = { pos = { -14.5, 8.5, -14.2 }, target = { -15.6, 4.2, -19.6 }, fov = 60 },
			night = { pos = { -14.6, 8.5, 1 }, target = { -14.6, 2.5, 17 }, fov = 62 },
		}
	end,
})
