--!nocheck
-- The Tool Shed interior in the Hearth & Home restyle (wood display tables, price cards, spots, headers, wall dressing).
-- Views: 1 entrance (from just inside the door), 2 table close-up, 3 phone (667x375, from the aisle just inside the
-- door), 4 night, 5 counter and CHECKOUT, 6 from above, 7 stock corner, 8 the machine table close, 9 the door from
-- inside (pegboards, plant). See _store.luau. The event room is shown active by store-toolshed-event.
local Store = require("./_store")

return Store.scene({
	kind = "ToolShed",
	title = "TOOL SHED",
	accent = { 150, 62, 44 },
	keeper = "Tink",
	walker = { 0, -6 },
	cameras = function()
		return {
			entrance = { pos = { 0, 8.5, -22.5 }, target = { 0, 7.6, 8 }, fov = 76 },
			tierStand = { pos = { 1.5, 8.2, -14 }, target = { -11, 4.6, -12 }, fov = 62, label = "table close-up" },
			phone = { pos = { 0, 8.5, -22 }, target = { 0, 7.4, 8 }, fov = 72 },
			night = { pos = { 0, 8.5, -22.5 }, target = { 0, 7.6, 8 }, fov = 76 },
			extra = {
				{ pos = { 0, 8, 2 }, target = { 0, 6, 20 }, fov = 75, label = "counter and CHECKOUT" },
				{ pos = { 25, 60, -30 }, target = { 0, 0, 0 }, fov = 55, label = "from above" },
				{ pos = { -4, 14, 6 }, target = { -14, 1, 19.5 }, fov = 55, label = "stock corner" },
				{ pos = { -3, 8, 2 }, target = { 11, 4.6, 0 }, fov = 62, label = "machine table close" },
				{ pos = { 0, 8.5, 9 }, target = { 0, 6.5, -22 }, fov = 76, label = "the door from inside" },
				{ pos = { 0, 9, -12 }, target = { 12.4, 9.2, -22 }, fov = 62, label = "pegboard by the door" },
				{ pos = { 4, 8.5, -2 }, target = { -17, 10, -6 }, fov = 62, label = "west wall shelves and pictures" },
			},
		}
	end,
})
