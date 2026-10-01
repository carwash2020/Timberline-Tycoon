--!nocheck
-- Every truck in a row, each towing a trailer (the Scout ATV can't tow),
-- beds partly loaded, plus a lone Rustbucket up front for close-ups.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local TruckArt = ctx.art("TruckArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local TruckLayout = ctx.shared("TruckLayout")
		local WoodData = ctx.shared("WoodData")
		local root = roblox.Instance.new("Model")

		Common.ground(ctx, root, 260, C3.fromRGB(116, 164, 84), V3.new(20, -0.5, 10))
		-- A packed-dirt lot under the trucks.
		Kit.part(
			root,
			"Lot",
			V3.new(78, 0.1, 64),
			CF.new(20, 0.02, 12),
			C3.fromRGB(176, 146, 104),
			Enum.Material.Ground
		)

		local woods = { "oak", "birch", "pine", "maple", "oak", "pine", "birch", "emberwood", "oak", "maple" }
		local function load(model, layout, floorName, slots, count, offset)
			local floor = model:FindFirstChild(floorName)
			if not floor then
				return
			end
			for i = 1, math.min(count, #slots) do
				local wood = WoodData.Get(woods[(i + offset) % #woods + 1])
				local log = TruckArt.BedLog(floor, slots[i], wood, layout.logLength, i)
				log.Parent = root
			end
		end

		local rigs = {
			{ "Rustbucket", "PonyTrailer", 5, 4 },
			{ "Pickup", "RanchTrailer", 9, 7 },
			{ "ScoutATV", nil, 0, 0 },
			{ "Flatbed", "RanchTrailer", 16, 0 },
			{ "LoggingRig", "HeavyHauler", 40, 20 },
		}
		local spacing = 11
		for i, entry in ipairs(rigs) do
			local def = ItemCatalog.GetTruck(entry[1])
			local layout = TruckLayout.For(def)
			local trailer = if entry[2] then ItemCatalog.GetTrailer(entry[2]) else nil
			local tl = if trailer then TruckLayout.ForTrailer(trailer, layout) else nil
			local model = TruckArt.Build(def, layout, trailer, tl)
			Kit.placeAt(model, CF.new((i - 1) * spacing, 0, 0))
			model.Parent = root
			load(model, layout, "BedFloor", layout.logSlots, entry[3], i)
			if tl then
				load(model, layout, "TrailerBed", tl.logSlots, entry[4], i + 3)
			end
		end

		-- A lone Rustbucket out front, turned toward the camera.
		local rust = ItemCatalog.GetTruck("Rustbucket")
		local rustLayout = TruckLayout.For(rust)
		local lone = TruckArt.Build(rust, rustLayout)
		Kit.placeAt(lone, CF.new(-16, 0, -22) * CF.Angles(0, math.rad(35), 0))
		lone.Parent = root
		load(lone, rustLayout, "BedFloor", rustLayout.logSlots, 6, 2)

		local function at(i)
			return (i - 1) * spacing
		end
		return {
			root = root,
			shadowRadius = 90,
			cameras = {
				{ pos = { -30, 26, -52 }, target = { 22, 2, 6 }, label = "line-up" },
				{ pos = { 21, 9, -46 }, target = { 22, 3, 2 }, label = "line-up, front" },
				{ pos = { -15, 6, -35 }, target = { -16.5, 2.4, -22 }, label = "Rustbucket" },
				{ pos = { -27, 5, -14 }, target = { -16, 2.4, -22 }, label = "Rustbucket, side" },
				{ pos = { -8, 8, 17 }, target = { at(1), 2.5, 9 }, label = "Rustbucket + Pony, rear" },
				{ pos = { at(2) - 9, 7, -16 }, target = { at(2), 3, -4 }, label = "Pickup" },
				{ pos = { at(3) - 6, 5, -9 }, target = { at(3), 2.2, 0 }, label = "Scout ATV" },
				{ pos = { at(4) - 10, 9, -20 }, target = { at(4), 3, -4 }, label = "Flatbed" },
				{ pos = { at(5) - 12, 9, -24 }, target = { at(5), 3.5, -8 }, label = "Logging Rig" },
				{ pos = { at(5) + 18, 10, 18 }, target = { at(5), 3, 10 }, label = "Logging Rig + Heavy Hauler" },
			},
		}
	end,
}
