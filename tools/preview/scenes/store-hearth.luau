--!nocheck
-- The General Store (Hearth & Home) interior in the new store look. Views: 1
-- entrance (from just inside the door), 2 tier stand, 3 phone (667x375, from
-- the aisle just inside the door), 4 night. See _store.luau.
local Store = require("./_store")

return Store.scene({
	kind = "HearthAndHome",
	title = "HEARTH & HOME",
	accent = { 47, 93, 58 },
	keeper = "Hazel",
	walker = { 0, -6 },
	cameras = function()
		return {
			entrance = { pos = { 0, 8.5, -23 }, target = { 0, 7.6, 10 }, fov = 80 },
			tierStand = { pos = { -1, 7.5, -17 }, target = { -12, 5.5, -10 }, fov = 62 },
			phone = { pos = { 0, 8.5, -23 }, target = { 0, 7.4, 10 }, fov = 72 },
			night = { pos = { 0, 8.5, -23 }, target = { 0, 7.6, 10 }, fov = 80 },
			extra = {
				{ pos = { 0, 8, 2 }, target = { 0, 6, 21 }, fov = 75, label = "counter and back wall" },
				{ pos = { 25, 60, -30 }, target = { 0, 0, 0 }, fov = 55, label = "from above" },
				{ pos = { -15.6, 7, -19 }, target = { -15.6, 5.5, 10 }, fov = 60, label = "west side aisle" },
				{ pos = { 15.6, 7, -19 }, target = { 15.6, 5.5, 10 }, fov = 60, label = "east side aisle" },
				{ pos = { 4, 12, 4 }, target = { 20, 3, 18 }, fov = 55, label = "stock corner" },
			},
		}
	end,
})
