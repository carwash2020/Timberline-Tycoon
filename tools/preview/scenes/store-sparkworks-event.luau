--!nocheck
-- The Sparkworks' event room, shown ACTIVE (ropes down, lamp on, banner up): the roped zone in the back west corner
-- and the banner by the counter. Views: 1 the zone from the aisle, 2 the zone from the counter side, 3 the banner
-- from the door. The other store scenes show it as the game does until an event runs (rope up, banner hidden).
local Store = require("./_store")

return Store.scene({
	kind = "Sparkworks",
	title = "SPARKWORKS",
	accent = { 46, 139, 139 },
	keeper = "Juno",
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
			entrance = { pos = { -4, 8.5, 3 }, target = { -13, 2.5, 13 }, fov = 62 },
			tierStand = { pos = { -4, 9, 16 }, target = { -14, 2.5, 11.5 }, fov = 62 },
			phone = { pos = { 2, 7.5, 4.5 }, target = { 8.2, 4.2, 11.6 }, fov = 60 },
			night = { pos = { -4, 8.5, 3 }, target = { -13, 2.5, 13 }, fov = 62 },
		}
	end,
})
