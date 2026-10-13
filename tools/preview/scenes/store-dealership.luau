--!nocheck
-- The Dealership showroom hall (store interior polish). The hall is at the
-- origin with its roof off, the real vehicles on their plinths (DealershipLot,
-- placed the way MapBuilder places them, each behind its packaged box), the
-- keeper at the counter and a person in the aisle (_dealership.luau). Views: 1 entrance (just
-- inside the door), 2 tier stand (a plinth's T-flag, mat and name sign from the
-- aisle), 3 phone (667x375, from the door), 4 night, then extras: 5 counter and CHECKOUT,
-- 6 the tables (reception and finance), 7 a plinth's name sign, 8 the hall from above, 9 down the
-- aisle, 10 the lot row (front row from the aisle), 11 the back row, 12 the lobby's west wall, 13 the lobby's back wall, 14 the front wall (racks and the event banner).
-- See _store.luau.
local Dealer = require("./_dealership")

return Dealer.scene({
	cameras = function()
		return {
			entrance = { pos = { -69, 9, -28.6 }, target = { -40, 8, 3 }, fov = 62 },
			tierStand = { pos = { -27, 5.2, 2.5 }, target = { -38, 3.8, -9 }, fov = 58 },
			phone = { pos = { -69, 9, -28.6 }, target = { -40, 8, 3 }, fov = 62 },
			night = { pos = { -69, 9, -28.6 }, target = { -40, 8, 3 }, fov = 62 },
			extra = {
				{ pos = { -64, 8, 2 }, target = { -64.2, 4.6, 26 }, fov = 58, label = "counter and CHECKOUT" },
				{ pos = { -64, 8, 2 }, target = { -60, 1.6, 12 }, fov = 62, label = "the tables" },
				{ pos = { -25, 4.5, 2 }, target = { -30, 1.6, -6.8 }, fov = 58, label = "a plinth's name sign" },
				{ pos = { 0, 150, -20 }, target = { 0, 0, 0 }, fov = 62, label = "the hall from above" },
				{ pos = { -58, 8, 6 }, target = { 30, 6, 0 }, fov = 70, label = "down the aisle" },
				{ pos = { 4, 8, 3 }, target = { 4, 4, -14 }, fov = 66, label = "the lot row, front" },
				{ pos = { 20, 9, -2 }, target = { 20, 6, 18 }, fov = 70, label = "back row from the aisle" },
				{ pos = { -56, 8, -4 }, target = { -77, 6, 8 }, fov = 78, label = "the lobby's west wall" },
				{ pos = { -58, 9, 6 }, target = { -50, 7, 30 }, fov = 66, label = "the lobby's back wall" },
				{
					pos = { -64, 8, -8 },
					target = { -55, 3.5, -29.5 },
					fov = 66,
					label = "the front wall: racks and the event banner",
				},
			},
		}
	end,
})
