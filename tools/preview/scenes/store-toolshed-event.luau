--!nocheck
-- The Tool Shed's event room, shown ACTIVE (ropes down, lamp on, banner up): the roped zone in the back east corner and
-- the banner at the aisle's west edge by the door. Views: 1 the zone from the aisle, 2 the zone from above,
-- 3 the banner from the door, 4 night, 5 the banner from inside. The other store scenes show it as the game does until
-- an event runs (rope up, banner hidden).
local Store = require("./_store")

return Store.scene({
	kind = "ToolShed",
	title = "TOOL SHED",
	accent = { 150, 62, 44 },
	keeper = "Tink",
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
			entrance = {
				pos = { 1, 10, 10.5 },
				target = { 12, 0.5, 18.5 },
				fov = 66,
				label = "event zone from the aisle",
			},
			tierStand = {
				pos = { 11.3, 24, 9 },
				target = { 11.3, 0, 17.5 },
				fov = 45,
				label = "event zone from above",
			},
			phone = { pos = { 0, 7, -23 }, target = { -3.25, 3.5, -18 }, fov = 60, label = "banner from the door" },
			night = { pos = { 1, 10, 10.5 }, target = { 12, 0.5, 18.5 }, fov = 66, label = "event zone at night" },
			extra = {
				{ pos = { 0.5, 7, -10 }, target = { -3.25, 4, -18 }, fov = 55, label = "banner from inside" },
			},
		}
	end,
})
