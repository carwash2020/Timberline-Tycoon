--!nocheck
-- The Sparkworks interior. Views: 1 entrance
-- (from just inside the door), 2 tier stand, 3 phone (667x375, from the aisle
-- just inside the door), 4 night. See _store.luau.
local Store = require("./_store")

return Store.scene({
	kind = "Sparkworks",
	title = "SPARKWORKS",
	accent = { 46, 139, 139 },
	keeper = "Juno",
	walker = { 0, -6 },
	cameras = function()
		return {
			entrance = { pos = { 0, 7.4, -23.5 }, target = { 0, 7.6, 8 }, fov = 78 },
			tierStand = { pos = { 2, 8.5, -15 }, target = { 11, 5.5, -6 }, fov = 62 },
			phone = { pos = { 0, 8.5, -22 }, target = { 0, 7.4, 8 }, fov = 72 },
			night = { pos = { 0, 8.5, -22.5 }, target = { 0, 7.6, 8 }, fov = 76 },
			extra = {
				{ pos = { 0, 8, 2 }, target = { 0, 6, 20 }, fov = 75, label = "counter and back wall" },
				{ pos = { 25, 60, -30 }, target = { 0, 0, 0 }, fov = 55, label = "from above" },
				{ pos = { 4, 9, 8 }, target = { 13, 4.5, 14 }, fov = 62, label = "east corner and spools" },
				{ pos = { -2, 8, -14 }, target = { -12, 5, -2 }, fov = 62, label = "west unit close" },
				{ pos = { 2, 11, 0 }, target = { -17.5, 8.5, -8 }, fov = 62, label = "west wall wiring" },
				{ pos = { -2, 11, 0 }, target = { 17.5, 8.5, -8 }, fov = 62, label = "east wall wiring" },
				{ pos = { 0, 6.4, -17.5 }, target = { -9, 11, -8 }, fov = 70, label = "headers from the doorway" },
				{ pos = { 12, 9, 8 }, target = { 17, 3, 14 }, fov = 60, label = "wire spools" },
			},
		}
	end,
})
