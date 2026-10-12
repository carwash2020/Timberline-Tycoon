--!nocheck
-- The Dealership hall from outside (store polish): the building as MapBuilder stands it,
-- roof on, the door shut, on a flat lawn. Views: 1 front, 2 three-quarter from the door end,
-- 3 night, 4 the forecourt and the door close up, 5 the door end's wall, 6 the door from
-- the street (shoot it at 667x375 for the phone size), 7 the forecourt lamps, 8 the east end.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local DealershipLot = ctx.art("DealershipLot")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 700, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 0))
		ctx.art("TownMeshes").Enabled = false

		local hall = DealershipLot.Hall()
		local shop = BuildingArt.Shop("Dealership", "DEALERSHIP", C3.fromRGB(47, 109, 181))
		Kit.placeAt(shop, CF.new(0, 0, 0))
		shop.Parent = root

		local hx, hz = hall.innerW / 2, hall.innerD / 2
		local doorX = -hx + 8
		local cameras = {
			{ pos = { -45, 11, -88 }, target = { -45, 8, -31 }, label = "1 front", fov = 72 },
			{ pos = { -125, 15, -70 }, target = { -50, 7, -8 }, label = "2 three-quarter from the door end", fov = 60 },
			{
				pos = { -125, 15, -70 },
				target = { -50, 7, -8 },
				label = "3 night",
				fov = 60,
				night = true,
			},
			{ pos = { doorX + 16, 5, -54 }, target = { doorX, 6, -hz }, label = "4 forecourt and door", fov = 70 },
			{ pos = { -150, 10, 8 }, target = { -77, 8, 0 }, label = "5 the door end's wall", fov = 62 },
			{ pos = { doorX, 5, -48 }, target = { doorX, 6, -hz }, label = "6 the door from the street", fov = 62 },
			{ pos = { 10, 5, -54 }, target = { 28, 5, -34 }, label = "7 forecourt lamps and piers", fov = 70 },
			{ pos = { 135, 22, 75 }, target = { 20, 6, 0 }, label = "8 east end and back", fov = 62 },
		}
		return { root = root, shadowRadius = 260, cameras = cameras }
	end,
}
