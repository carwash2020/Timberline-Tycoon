--!nocheck
-- The Sparkworks interior in the new store look. Views: 1 entrance (from just inside the door), 2 table close-up
-- (display tables with price cards), 3 phone (667x375, from the aisle just inside the door), 4 night, 5 counter and
-- CHECKOUT, 6 from above, 7 west unit close, 8 east corner (banner, rug, spools), 9 west wall (event room, shelves).
-- See _store.luau.
local Store = require("./_store")

return Store.scene({
	kind = "Sparkworks",
	title = "SPARKWORKS",
	accent = { 46, 139, 139 },
	keeper = "Juno",
	walker = { 0, -6 },
	cameras = function()
		return {
			entrance = { pos = { 0, 8.5, -22.5 }, target = { 0, 7.6, 8 }, fov = 78 },
			tierStand = { pos = { 2, 8.2, -14 }, target = { 10, 4.2, -9 }, fov = 52 },
			phone = { pos = { 0, 8.5, -22 }, target = { 0, 7.4, 8 }, fov = 72 },
			night = { pos = { 0, 8.5, -22.5 }, target = { 0, 7.6, 8 }, fov = 78 },
			extra = {
				{ pos = { 0, 8, 2 }, target = { 0, 6, 20 }, fov = 70, label = "counter and CHECKOUT" },
				{ pos = { 25, 60, -30 }, target = { 0, 0, 0 }, fov = 55, label = "from above" },
				{ pos = { -2, 8, -14 }, target = { -12, 5, -2 }, fov = 62, label = "west unit close" },
				{ pos = { 2, 9, 3 }, target = { 12, 3.5, 15 }, fov = 62, label = "east corner, banner and spools" },
				{ pos = { -3, 9, 5 }, target = { -15, 5, 13 }, fov = 62, label = "west wall and event room" },
			},
		}
	end,
})
