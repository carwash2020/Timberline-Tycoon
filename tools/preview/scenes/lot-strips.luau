--!nocheck
-- The dealership lot's plinths and their tier strips (green, purple, blue,
-- orange ... one tier colour per plinth, matching its T-flag), on flat grass:
-- the real lot as MapBuilder builds it, real vehicle meshes, no hall. The
-- strips must read as paint on the slab top: flush, inside the slab's edges,
-- no gap, no overhang. Views: 1 the whole lot from above; 2 the front row
-- from a low angle along the aisle; 3 the back row; 4 a corner of the first
-- plinth at ground level; 5 the seam between two plinths; 6 the last
-- plinth's end; 7 the aisle edge of a plinth, very low and close; 8 the lot
-- from the west, low.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local DealershipLot = ctx.art("DealershipLot")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 600, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 0))
		-- A hall-floor slab under the lot, as in the game (the lot stands on the floor).
		local layout = DealershipLot.Layout()
		local lot = DealershipLot.Build()
		Kit.placeAt(lot, CF.new(0, 0, 0))
		lot.Parent = root
		for _, d in ipairs(lot:GetDescendants()) do
			if d.Name == "BoxSpot" then
				d:Destroy()
			end
		end
		local oz = -layout.depth / 2
		local top = DealershipLot.PlinthHeight
		local front, back = {}, {}
		for _, bay in ipairs(layout.bays) do
			table.insert(if bay.row == 1 then front else back, bay)
		end
		local f1, fN, b1 = front[1], front[#front], back[1]
		local function at(bay, dx, dz)
			return { bay.x + dx, top, oz + bay.z + dz }
		end
		local aisleF = f1.depth / 2 -- the front row's aisle is at +Z
		local cameras = {
			{ pos = { 0, 190, -10 }, target = { 0, 0, 0 }, fov = 55, label = "1 the whole lot from above" },
			{
				pos = { f1.x - f1.width / 2 - 14, 3.2, oz + f1.z + aisleF + 7 },
				target = { f1.x + 40, top, oz + f1.z + aisleF },
				fov = 70,
				label = "2 the front row from a low angle along the aisle",
			},
			{
				pos = { b1.x - b1.width / 2 - 14, 3.2, oz + b1.z - b1.depth / 2 - 7 },
				target = { b1.x + 40, top, oz + b1.z - b1.depth / 2 },
				fov = 70,
				label = "3 the back row from a low angle along the aisle",
			},
			{
				pos = { f1.x - f1.width / 2 - 3, top + 1.4, oz + f1.z + aisleF + 3 },
				target = { f1.x - f1.width / 2 + 0.5, top, oz + f1.z + aisleF - 0.5 },
				fov = 50,
				label = "4 a corner of the first plinth, low",
			},
			{
				pos = {
					(front[1].x + front[1].width / 2 + front[2].x - front[2].width / 2) / 2,
					top + 1.2,
					oz + f1.z + aisleF + 4,
				},
				target = {
					(front[1].x + front[1].width / 2 + front[2].x - front[2].width / 2) / 2,
					top,
					oz + f1.z + aisleF - 0.4,
				},
				fov = 50,
				label = "5 the seam between two plinths, low",
			},
			{
				pos = { fN.x - fN.width / 2 - 3, top + 1.4, oz + fN.z + aisleF + 3 },
				target = { fN.x - fN.width / 2 + 0.5, top, oz + fN.z + aisleF - 0.5 },
				fov = 50,
				label = "6 the last front plinth west corner, low",
			},
			{
				pos = { f1.x, top + 0.5, oz + f1.z + aisleF + 5 },
				target = { f1.x, top, oz + f1.z + aisleF - 0.3 },
				fov = 45,
				label = "7 the aisle edge of a plinth, very low",
			},
			{
				pos = { -layout.width / 2 - 40, 4, oz + f1.z },
				target = { -layout.width / 2 + 20, top, 0 },
				fov = 70,
				label = "8 the lot from the west, low",
			},
		}
		return { root = root, shadowRadius = 260, cameras = cameras }
	end,
}
