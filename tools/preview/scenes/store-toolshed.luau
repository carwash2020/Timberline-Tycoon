--!nocheck
-- The Tool Shed interior (the pilot of the new store look). Views: 1 entrance
-- (from just inside the door), 2 tier stand, 3 phone (667x375, from the aisle
-- just inside the door), 4 night. See _store.luau.
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
			tierStand = { pos = { 2, 7.5, -16 }, target = { -11, 5.5, -10 }, fov = 62 },
			phone = { pos = { 0, 8.5, -22 }, target = { 0, 7.4, 8 }, fov = 72 },
			night = { pos = { 0, 8.5, -22.5 }, target = { 0, 7.6, 8 }, fov = 76 },
			extra = {
				{ pos = { 0, 8, 2 }, target = { 0, 6, 20 }, fov = 75, label = "counter and axe wall" },
				{ pos = { 25, 60, -30 }, target = { 0, 0, 0 }, fov = 55, label = "from above" },
				{ pos = { -4, 14, 6 }, target = { -14, 1, 19.5 }, fov = 55, label = "stock corner" },
				{ pos = { -3, 7, 4 }, target = { 11, 5, 4 }, fov = 62, label = "machine table close" },
			},
		}
	end,
})
