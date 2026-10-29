--!nocheck
-- T413 travel greyboxes: the free town bridge, the paid lift, the car ferry
-- and its docks, the Skyroot hairpin, and one junction sign.
-- Views 1, 5, 6, 7 and 8 are the five shots under preview/t413/.
-- View 9 is the EastLink shoulder (preview/t413/eastlink-shoulder.png).
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local TravelArt = ctx.art("TravelArt")
		local TravelPlan = ctx.shared("TravelPlan")
		local LandmarkArt = ctx.art("LandmarkArt")
		local FerryLogic = ctx.shared("FerryLogic")
		local ShopPins = ctx.load("ReplicatedStorage/Shared/World/ShopPins")
		local root = roblox.Instance.new("Model")
		local function pad(x, z, w)
			local p = roblox.Instance.new("Part")
			p.Name = "Pad"
			p.Anchored = true
			p.Size = V3.new(w, 1, w)
			p.CFrame = CF.new(x, -1, z)
			p.Color = C3.fromRGB(110, 122, 96)
			p.Parent = root
		end
		pad(113, 80, 220)
		pad(-36, 40, 120)
		pad(1000, -670, 420)
		pad(-150, 640, 280)
		local travel = TravelArt.Build(root)
		travel.Parent = root
		local boat = LandmarkArt.FerryBoat()
		local berth = FerryLogic.Berths().main
		Kit.placeAt(boat, CF.new(berth.x, FerryLogic.DeckY(), berth.z))
		boat.Parent = root

		-- Studio set, west of the map, so a world sign cannot sit in the shot.
		local studio = -2400
		pad(studio, 0, 160)
		local lift = TravelArt.LiftBridge()
		Kit.placeAt(lift, CF.new(studio, 0, 0))
		lift.Parent = root

		pad(studio, 180, 90)
		local free = TravelArt.FreeBridge()
		Kit.placeAt(free, CF.new(studio, 0, 180))
		free.Parent = root

		pad(studio, 360, 140)
		local ferry = LandmarkArt.FerryBoat()
		Kit.placeAt(ferry, CF.new(studio, 4, 360))
		ferry.Parent = root

		pad(studio, 540, 90)
		local stone = TravelArt.StoneBridge()
		Kit.placeAt(stone, CF.new(studio - 20, 0, 540))
		stone.Parent = root
		local foot = TravelArt.FootBridge()
		Kit.placeAt(foot, CF.new(studio + 18, 0, 540))
		foot.Parent = root

		-- Travel pins and the T411/T412 shops. No gondola marker.
		local map = Kit.model("TravelPins")
		map.Parent = root
		local SCALE = 0.05
		-- Travel labels sit at least 6 map-studs clear of each other and of
		-- the shop labels. Nudge is in that same map space (screen studs).
		local function pinAt(name, x, z, color, wide, nudge)
			local px, pz = x * SCALE + 2000, z * SCALE + 1100
			if nudge then
				px += nudge[1]
				pz += nudge[2]
			end
			local marker = Kit.part(
				map,
				name,
				V3.new(if wide then 14 else 8, 0.4, 4),
				CF.new(px, 0.4, pz),
				color,
				roblox.Enum.Material.SmoothPlastic
			)
			Kit.signText(
				marker,
				name,
				C3.fromRGB(42, 36, 32),
				{ roblox.Enum.NormalId.Top },
				roblox.Enum.Font.GothamBold
			)
		end
		local travelColor = C3.fromRGB(201, 162, 74)
		local shopColor = C3.fromRGB(196, 122, 74)
		pinAt("TOWN", TravelPlan.FreeBridge.x, TravelPlan.FreeBridge.z, travelColor, false, { 0, -16 })
		pinAt("LIFT $100", TravelPlan.LiftX, TravelPlan.LiftZ, travelColor, true, { 20.35, -18 })
		pinAt("DOCK", TravelPlan.Mainland.x, TravelPlan.Mainland.z, travelColor, false, { -10, 0 })
		pinAt("ISLE", TravelPlan.IslandDock.x, TravelPlan.IslandDock.z, travelColor, false, { 0, 17 })
		local sky = TravelPlan.SkyrootPoints()
		for i = 1, #sky - 1 do
			local a, b = sky[i], sky[i + 1]
			local mx, mz = (a.x + b.x) / 2 * SCALE + 2000, (a.z + b.z) / 2 * SCALE + 1100
			local dx, dz = (b.x - a.x) * SCALE, (b.z - a.z) * SCALE
			local len = math.sqrt(dx * dx + dz * dz)
			Kit.part(
				map,
				"SkyLeg",
				V3.new(1.2, 0.2, len),
				CF.new(mx, 0.15, mz) * roblox.CFrame.Angles(0, math.atan2(dx, dz), 0),
				travelColor,
				roblox.Enum.Material.SmoothPlastic
			)
		end
		local lodge = sky[#sky]
		pinAt("SKYROOT", lodge.x, lodge.z, travelColor, true, { 0, -16 })
		for _, row in ipairs(ShopPins.All()) do
			pinAt(row.id, row.x, row.z, shopColor, false)
		end

		local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
		local shoulderY = TerrainGen.HeightAt(420, 80)
		return {
			root = root,
			terrain = Common.terrain(ctx, 340, 40, 520, 130, 2),
			shadowRadius = 40,
			fov = 40,
			lighting = {
				sunDir = { -0.35, 0.55, -0.45 },
				sunColor = "#ffd2a0",
				sunIntensity = 2.2,
				skyTop = "#8eb4d8",
				skyBottom = "#f3d7b0",
				ground = "#6e7a68",
				hemiIntensity = 1.1,
				ambient = 0.55,
				fog = "#d5e2ea",
				fogNear = 80,
				fogFar = 520,
				bloom = 0.2,
			},
			cameras = {
				-- Booth face toward -Z. Camera sits south of the sign.
				{ pos = { -2490, 36, -70 }, target = { -2408, 10, 12 }, label = "lift top", fov = 34 },
				{ pos = { 860, 36, -590 }, target = { 960, 4, -650 }, label = "ferry docks" },
				{ pos = { -90, 70, 620 }, target = { -178, 2, 691 }, label = "skyroot hairpin" },
				{ pos = { -48, 7, 28 }, target = { -60, 5, 40 }, label = "junction sign" },
				{ pos = { -2348, 22, 132 }, target = { -2400, 2, 164 }, label = "free town bridge", fov = 38 },
				{ pos = { -2364, 70, 280 }, target = { -2400, 3, 360 }, label = "ferry truck", fov = 42 },
				{ pos = { -2400, 48, 470 }, target = { -2402, 1, 540 }, label = "bridges contrast", fov = 42 },
				{ pos = { 2012, 95, 1100 }, target = { 2012, 0, 1100 }, label = "travel pins", fov = 48 },
				-- Eye level on the south edge of EastLink, looking along the flat shoulder.
				{
					pos = { 390, shoulderY + 6, 104 },
					target = { 460, shoulderY + 1, 84 },
					label = "eastlink shoulder",
					fov = 42,
				},
				-- Three-quarter from the stern: cabin, lamp, and the ghost truck
				-- on the 18×84 deck. The studio boat sits at (-2400, 4, 360).
				{
					pos = { -2332, 34, 458 },
					target = { -2400, 6, 365 },
					label = "ferry cabin",
					fov = 32,
				},
			},
		}
	end,
}
