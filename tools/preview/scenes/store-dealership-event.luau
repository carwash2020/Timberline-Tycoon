--!nocheck
-- The Dealership's event room, shown ACTIVE (ropes down, lamp on, banner up): the roped zone against the lobby's
-- west wall and the banner in the front corner east of the door. Views: 1 the zone from the runner, 2 the zone from
-- the door, 3 the banner from the lobby, 4 night. The other Dealership scenes show the room as the game does
-- until an event runs (rope up, banner hidden).
local Dealer = require("./_dealership")

return Dealer.scene({
	active = true,
	cameras = function()
		return {
			entrance = { pos = { -57, 8, -8.5 }, target = { -73, 2, -8.5 }, fov = 62 },
			tierStand = { pos = { -66, 9, -26 }, target = { -73, 2, -9 }, fov = 62 },
			phone = { pos = { -64, 8, -10 }, target = { -58.4, 4.3, -27.2 }, fov = 60 },
			night = { pos = { -57, 8, -8.5 }, target = { -73, 2, -8.5 }, fov = 62 },
		}
	end,
})
