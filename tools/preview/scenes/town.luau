--!nocheck
-- The town exactly as MapBuilder builds it (section 4), from
-- WorldPlan.Town(): the sawmill at (0, 110) with the sell station (pad, Weigh
-- House, log rack) beside it to the east, the Tool Shed, the Dealership and Hearth & Home along the street,
-- the gondola station behind them, Murph's camp by the spawn, the spawn pad,
-- the parking lot's slots, lamps, fences, props, signs and the town's
-- greenery (its ornamental trees, bushes, flower beds and rocks), on the
-- real terrain (TerrainGen paints the cobbled plaza, the street and the
-- paths), at golden hour. Nothing here that MapBuilder doesn't build: no
-- people or trucks (NPCService and VehicleService add those at runtime).
-- world.luau builds the same town the same way.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local DealershipLot = ctx.art("DealershipLot")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local root = roblox.Instance.new("Model")

		local function place(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
			return model
		end

		local town = WorldPlan.Town()

		-- The lamps first: on a day camera the viewer draws only the first
		-- 24 point lights in export order, so these always light.
		for _, cf in ipairs(town.lamps) do
			place(BuildingArt.LampPost(), cf)
		end

		-- Then section 4 in MapBuilder's order. The spawn pad (a
		-- SpawnLocation in game).
		Kit.part(
			root,
			"SpawnLocation",
			V3.new(6, 1, 6),
			town.spawnFacing,
			C3.fromRGB(168, 152, 128),
			Enum.Material.Cobblestone
		)
		place(BuildingArt.Sawmill(), town.sawmill)
		place(BuildingArt.SellStation(WorldPlan.SellPadWidth, WorldPlan.SellPadDepth), town.sellPad) -- the SellZone over it is invisible
		for _, spot in ipairs(town.shops) do
			place(BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe)
		end
		place(DealershipLot.Build(), town.displayLot)
		place(BuildingArt.GondolaStation(), town.gondola)
		place(BuildingArt.Campsite(), town.campsite)
		for index, cf in ipairs(town.parkingSlots) do
			local slot = Kit.part(
				root,
				"ParkingSlot_" .. index,
				town.parkingSizes[index] or WorldPlan.ParkingSlotSize,
				cf,
				C3.fromRGB(186, 168, 140),
				Enum.Material.Slate
			)
			slot.CanCollide = false
			slot.CastShadow = false
			BuildingArt.ParkingBay(slot, index)
		end
		for _, fence in ipairs(town.fences) do
			place(BuildingArt.Fence(fence.length), fence.cframe)
		end
		for _, prop in ipairs(town.props) do
			place(BuildingArt.Prop(prop.name, prop.seed), prop.cframe)
		end
		for _, sign in ipairs(town.signs) do
			place(BuildingArt.Signpost(sign.text, sign.lit), sign.cframe)
		end
		for _, g in ipairs(town.greenery) do
			place(BuildingArt.Greenery(g.kind, g.size, g.seed, g.woodId), g.cframe)
		end
		for _, cf in ipairs(town.pathRounds) do
			place(BuildingArt.PathRound(), cf)
		end
		-- The Robux store board and its arch (MapBuilder step 4).
		place(ctx.shared("StoreBoard").Build(), ctx.shared("StoreBoard").CFrame)

		return {
			root = root,
			-- East edge covers the display lot (x about 188 to 294).
			terrain = Common.terrain(ctx, -190, -70, 360, 260, 4),
			shadowRadius = 200,
			fov = 50,
			lighting = {
				sunDir = { -0.72, 0.34, -0.5 },
				sunColor = "#ffc887",
				sunIntensity = 2.5,
				skyTop = "#7fa6d6",
				skyBottom = "#f6cf98",
				ground = "#7a6a4c",
				hemiIntensity = 1.25,
				ambient = 0.45,
				fog = "#efd2a8",
				fogNear = 220,
				fogFar = 900,
				-- world.luau's bloom (it keeps the viewer's default, 0.3 since
				-- ACT-15), so Neon and the lamps glow the same in both scenes.
				bloom = 0.3,
			},
			cameras = {
				{ pos = { 2, 6.5, 32 }, target = { 0, 9, 110 }, label = "from the spawn" },
				{ pos = { -95, 105, -20 }, target = { -10, 0, 100 }, label = "aerial" },
				{ pos = { -84, 7, 56 }, target = { -84, 8, 104 }, label = "Tool Shed, up its path" },
				{ pos = { 190, 9, 62 }, target = { 205, 8, 104 }, label = "Dealership" },
				{ pos = { -118, 8.5, 140 }, target = { -102, 8, 172 }, label = "Hearth & Home" },
				{ pos = { -36, 12, 116 }, target = { -40, 6, 150 }, label = "gondola station" },
				{ pos = { -10, 6, 30 }, target = { -28, 2, 42 }, label = "Murph's camp" },
				{ pos = { 36, 6, 70 }, target = { 53, 3, 111 }, label = "sell station + mill" },
				{ pos = { 80, 14, 24 }, target = { 0, 9, 100 }, label = "from the lot" },
				{ pos = { 0, 260, 90 }, target = { 0, 0, 91 }, label = "top down" },
				{ pos = { 2, 6.5, 32 }, target = { 0, 9, 110 }, label = "the spawn walk at night", night = true },
				{ pos = { 80, 14, 24 }, target = { 40, 0, 30 }, label = "the lot at night", night = true },
				{
					pos = { 52, 7, 66 },
					target = { 60, 5, 100 },
					label = "the sell sign and station at night",
					night = true,
				},
				{ pos = { -6, 5.5, -12 }, target = { -22, 4.2, -16 }, label = "south exit, grove gate" },
				-- Standing in the General Store's doorway, looking in at the counter.
				{
					pos = { -100, 6.2, 163 },
					target = { -100, 4.5, 195 },
					fov = 62,
					label = "store interior from the door",
				},
				-- The open display lot, trucks facing the plot road.
				{ pos = { 235, 62, 40 }, target = { 262, 0, 125 }, fov = 55, label = "dealership display lot" },
				-- The Robux store board: from the spawn, and close.
				{ pos = { 2, 6.5, 32 }, target = { -20.5, 7, 58.3 }, fov = 60, label = "store board from the spawn" },
				{ pos = { -8, 5, 58.3 }, target = { -20.5, 5, 58.3 }, fov = 60, label = "store board close" },
			},
		}
	end,
}
