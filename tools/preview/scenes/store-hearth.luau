--!nocheck
-- The General Store (Hearth & Home) interior in the new store look. Views: 1
-- entrance (from just inside the door), 2 table close-up (display tables with price cards), 3 phone (667x375,
-- from the aisle just inside the door), 4 night, 5 counter and CHECKOUT. See _store.luau.
local Store = require("./_store")

return Store.scene({
	kind = "HearthAndHome",
	title = "HEARTH & HOME",
	accent = { 47, 93, 58 },
	keeper = "Hazel",
	slotModels = true, -- PREVIEW_MESHES=tools/preview/store-items-meshes.json: the four slot models show
	walker = { 0, -6 },
	cameras = function()
		return {
			entrance = { pos = { 0, 8.5, -23 }, target = { 0, 7.6, 10 }, fov = 80 },
			tierStand = { pos = { -2.5, 7.2, -19.5 }, target = { -9.5, 3.6, -11 }, fov = 52 },
			phone = { pos = { 0, 7.8, -24.5 }, target = { 0, 7, 10 }, fov = 72 },
			night = { pos = { 0, 8.5, -23 }, target = { 0, 7.6, 10 }, fov = 80 },
			extra = {
				{ pos = { 0, 7.6, 3 }, target = { 0, 6.4, 21 }, fov = 62, label = "counter and CHECKOUT" },
				{ pos = { 25, 60, -30 }, target = { 0, 0, 0 }, fov = 55, label = "from above" },
				{ pos = { -15.6, 7, -19 }, target = { -15.6, 5.5, 10 }, fov = 60, label = "west side aisle" },
				{ pos = { 15.6, 7, -19 }, target = { 15.6, 5.5, 10 }, fov = 60, label = "east side aisle" },
				{ pos = { 4, 12, 4 }, target = { 20, 3, 18 }, fov = 55, label = "stock corner" },
			},
		}
	end,
})
