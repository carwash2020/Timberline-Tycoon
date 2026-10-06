--!nocheck
-- The parking lot and the sell pad in use (phase 12): the town exactly as
-- town.luau builds it, with the trucks VehicleService adds at runtime.
-- Eleven players join in turn, each rig parked in the bay
-- VehicleLogic.BayChoices gives it (the smallest free bay it fits, else the
-- longest it may overhang), where VehicleService puts it (the rig centred
-- on its bay, facing the way the bay faces; tail-aligned when it overhangs
-- one): the Rustbucket + Pony (38.7 long) takes the Flatbed's other bay.
-- Bays 7 and 8 stay free, to see the paint. A loaded Logging Rig backed
-- onto the sell pad, its tail a stud short of the mill's ramp, and the
-- SellZone (invisible in game) drawn translucent, to check the bed lands
-- in it and the rig clears the post and the lamps. A 5-stud figure
-- between the Rustbucket and the Pickup in bays 5 and 6, for scale.
-- Views: 1 the lot from above; 2 from the spawn; 3 the small bays;
-- 4 the Flatbed's, the longest and the long bays; 5 the sell pad; 6 top down.
local Town = require("./town")

return {
	build = function(ctx)
		local built = Town.build(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local TruckArt = ctx.art("TruckArt")
		local CharacterArt = ctx.art("CharacterArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local TruckLayout = ctx.shared("TruckLayout")
		local VehicleLogic = ctx.shared("VehicleLogic")
		local WoodData = ctx.shared("WoodData")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local root = built.root
		local town = WorldPlan.Town()

		local function rig(truckId, trailerId)
			local def = ItemCatalog.GetTruck(truckId)
			local layout = TruckLayout.For(def)
			local trailer = if trailerId then ItemCatalog.GetTrailer(trailerId) else nil
			local tl = if trailer then TruckLayout.ForTrailer(trailer, layout) else nil
			return TruckArt.Build(def, layout, trailer, tl), layout, tl
		end

		-- The players' rigs, in the order they join.
		local joins = {
			{ "Rustbucket" },
			{ "Pickup" },
			{ "LoggingRig", "HeavyHauler" },
			{ "Flatbed" },
			{ "ScoutATV" },
			{ "Pickup", "RanchTrailer" },
			{ "LoggingRig" },
			{ "Rustbucket", "PonyTrailer" },
			{ "Pickup" },
			{ "Rustbucket" },
			{ "Pickup" },
		}
		local taken = {}
		for _, entry in ipairs(joins) do
			local model, layout, tl = rig(entry[1], entry[2])
			local length, width = TruckLayout.RigSize(layout, tl)
			local free = {}
			for index, size in ipairs(town.parkingSizes) do
				if not taken[index] then
					table.insert(free, { index = index, length = size.Z, width = size.X })
				end
			end
			local index = VehicleLogic.BayChoices(free, length, width)[1]
			if index then
				taken[index] = true
				local slot, size = town.parkingSlots[index], town.parkingSizes[index]
				local ground = slot.Position - V3.new(0, size.Y / 2, 0)
				local shift = (if tl then tl.length / 2 else 0) + VehicleLogic.OverhangShift(size.Z, length)
				Kit.placeAt(model, CF.new(ground) * slot.Rotation * CF.new(0, 0, -shift))
				model.Parent = root
			end
		end

		-- The Logging Rig on the sell station's lane: backed in from the street
		-- (its nose to the street, -Z), its tail two studs short of the log
		-- rack's front stakes (z 122.4); 46.7 long, its nose reaches z 73.
		local logRig, logLayout = rig("LoggingRig")
		local tailZ = 120 -- the Rig is built around its middle, its tail length / 2 back
		Kit.placeAt(logRig, CF.new(town.sellPad.Position.X, 0, tailZ - logLayout.length / 2))
		logRig.Parent = root
		local floor = logRig:FindFirstChild("BedFloor")
		local woods = { "oak", "pine", "birch", "maple", "pine", "oak" }
		for i = 1, math.min(24, #logLayout.logSlots) do
			local log = TruckArt.BedLog(
				floor,
				logLayout.logSlots[i],
				WoodData.Get(woods[i % #woods + 1]),
				logLayout.logLength,
				i
			)
			log.Parent = root
		end
		local zone = Kit.part(
			root,
			"ShownSellZone",
			WorldPlan.SellZoneSize,
			town.sellZone,
			C3.fromRGB(80, 200, 255),
			Enum.Material.SmoothPlastic
		)
		zone.Transparency = 0.75
		zone.CanCollide = false

		-- A 5-stud figure in the gap between bays 5 and 6.
		local fig = CharacterArt.Build({
			name = "Driver",
			skin = C3.fromHex("#E8B994"),
			shirt = C3.fromHex("#C8553D"),
			pants = C3.fromHex("#3D4F6E"),
			hairStyle = "bald",
			hat = "none",
			tag = false,
		})
		Kit.placeAt(fig, CF.new(24.75, 0, 38) * CF.Angles(0, math.pi, 0))
		fig.Parent = root

		built.cameras = {
			{ pos = { 20, 70, 115 }, target = { 75, 0, 20 }, label = "1 the lot from above" },
			{
				pos = { -4, 15, 36 },
				target = { 56, 1, 12 },
				label = "2 the lot from the spawn, at chase-camera height",
			},
			{ pos = { 40, 10, 68 }, target = { 40, 3, 25 }, label = "3 the small bays" },
			{
				pos = { 125, 18, 78 },
				target = { 100, 3, 20 },
				label = "4 the Flatbed's, the longest and the long bays",
			},
			{ pos = { 36, 24, 42 }, target = { 0, 4, 74 }, label = "5 the sell pad" },
			{ pos = { 75, 190, 30 }, target = { 75, 0, 31 }, label = "6 top down" },
		}
		return built
	end,
}
