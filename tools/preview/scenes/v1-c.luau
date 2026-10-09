--!nocheck
-- Lane C designs, one camera each. View order is the file names in
-- previews/v1-c/ (see the cameras' label fields).
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local PropArt = ctx.art("PropArt")
		local MachineArt = ctx.art("MachineArt")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 900, C3.fromRGB(100, 150, 70), V3.new(200, -0.5, 40))

		local cameras = {}
		local function place(model, x, z, cam, label, fov)
			Kit.placeAt(model, CF.new(x, 0, z))
			model.Parent = root
			table.insert(cameras, {
				pos = { x + cam[1], cam[2], z + cam[3] },
				target = { x + (cam[4] or 0), cam[5] or 4, z + (cam[6] or 0) },
				label = label,
				fov = fov,
			})
		end

		local tool = C3.fromRGB(58, 111, 216)
		local hearth = C3.fromRGB(47, 93, 58)
		local dealer = C3.fromRGB(217, 83, 79)

		place(BuildingArt.Sawmill(), 0, 0, { -28, 16, -36, 0, 8, 0 }, "sawmill-front")
		place(BuildingArt.Shop("ToolShed", "TOOL SHED", tool), 90, 0, { -8, 14, -48, 0, 6, 0 }, "toolshed-front")
		place(
			BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", hearth),
			180,
			0,
			{ -10, 14, -46, 0, 6, 0 },
			"hearth-front"
		)
		place(
			BuildingArt.Shop("Dealership", "DEALERSHIP", dealer),
			360,
			0,
			{ -40, 22, -70, 0, 8, 0 },
			"dealership-front"
		)

		-- Floor views: standing in the doorway, looking in (+Z).
		place(BuildingArt.Shop("ToolShed", "TOOL SHED", tool), 90, 140, { 0, 7, -28, 0, 4, 8 }, "floor-toolshed")
		place(
			BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", hearth),
			180,
			140,
			{ 0, 7, -28, 0, 4, 8 },
			"floor-hearth"
		)
		place(
			BuildingArt.Shop("Dealership", "DEALERSHIP", dealer),
			360,
			140,
			{ -50, 8, -40, -20, 4, 0 },
			"floor-dealership"
		)

		place(BuildingArt.SellStation(28, 32), 0, 280, { 8, 14, -28, 10, 4, 0 }, "weigh-house")
		place(BuildingArt.GateKiosk(C3.fromRGB(58, 111, 216)), 80, 280, { -6, 6, -10, 0, 3, 0 }, "gate-kiosk")
		place(BuildingArt.OddsAndEnds(), 120, 280, { -14, 10, -16, 0, 3, 0 }, "odds-and-ends")
		place(BuildingArt.Sparkworks(), 170, 280, { -16, 12, -18, 0, 4, 0 }, "sparkworks")
		place(BuildingArt.SkyMarket(), 220, 280, { -8, 7, -12, 0, 3, 0 }, "sky-market")
		place(BuildingArt.SkyTurnstile(), 250, 280, { -4, 4, -8, 0, 2, 0 }, "sky-turnstile")
		place(BuildingArt.PlotMapBoard(), 275, 280, { -6, 5, -10, 0, 4, 0 }, "plot-map")
		place(BuildingArt.ArrivalArch(), 310, 280, { -8, 8, -14, 0, 6, 0 }, "arrival-arch")
		place(BuildingArt.LandOffice(), 360, 280, { -14, 10, -18, 0, 4, 0 }, "land-office")
		place(BuildingArt.SkyForgeCourt(), 430, 280, { -20, 16, -28, 0, 4, 0 }, "sky-forge-court")
		place(BuildingArt.Campfire(), 500, 280, { -4, 4, -6, 0, 1, 0 }, "campfire")
		place(BuildingArt.Fence(18), 530, 280, { -4, 4, -12, 0, 2, 0 }, "fence")
		place(BuildingArt.LampPost(), 560, 280, { -5, 6, -8, 0, 6, 0 }, "lamp-post")
		-- About 25 studs out, three-quarter, tight enough that the prop is
		-- half the frame. The label stays in the corner, off the prop.
		place(PropArt.Scene("fishing"), 80, 360, { -15.9, 8.83, -21.7, 0, 1.1, -4 }, "scene-fishing", 29)
		place(PropArt.Scene("campfire"), 110, 360, { -15.9, 8.53, -17.7, 0, 0.8, 0 }, "scene-campfire", 15)
		-- Same 25-stud three-quarter. The aim is higher so the platform
		-- (about 9 studs up) stays in frame; the corner label still misses it.
		place(PropArt.Scene("lookout"), 140, 360, { -15.9, 13, -17.7, 0, 5.2, 0 }, "scene-lookout", 28)
		place(PropArt.Scene("bench"), 165, 360, { -15.5, 8.63, -17.6, 0.4, 0.9, 0.1 }, "scene-bench", 12)
		place(MachineArt.Build("SawmillRickety", false), 210, 360, { -8, 6, -12, 0, 2, 0 }, "machine-sawmill")
		-- The foreman stand and the widened DAILY JOBS board, from the road.
		place(BuildingArt.Sawmill(), 300, 400, { -38, 5.6, -33, -31, 3.8, -19.6 }, "mill-foreman")

		-- A street on the empty south lawn, fronts turned toward the camera,
		-- so one elevated three-quarter shows the town as a place. The
		-- display row above stays put for the per-building fronts.
		local yaw = CF.Angles(0, math.pi, 0)
		local function street(model, x, z)
			Kit.placeAt(model, CF.new(x, 0, z) * yaw)
			model.Parent = root
		end
		local road = Kit.part(
			root,
			"TownRoad",
			V3.new(430, 0.2, 24),
			CF.new(-16, 0.06, -256),
			C3.fromRGB(122, 108, 88),
			roblox.Enum.Material.Ground
		)
		road.CanCollide = false
		street(BuildingArt.Sawmill(), -167.5, -290.8)
		street(BuildingArt.Shop("ToolShed", "TOOL SHED", tool), -97.3, -297.8)
		street(BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", hearth), -31.9, -299.5)
		street(BuildingArt.Shop("Dealership", "DEALERSHIP", dealer), 100.8, -306.2)
		street(BuildingArt.ArrivalArch(), -184, -243)
		street(BuildingArt.LampPost(), -158, -243)
		street(BuildingArt.PlotMapBoard(), -140, -243.8)
		street(BuildingArt.GateKiosk(tool), -118, -241)
		street(BuildingArt.Campfire(), -96, -241.8)
		street(BuildingArt.Fence(16), -70, -243.7)
		street(BuildingArt.LandOffice(), -40, -236.5)
		street(BuildingArt.OddsAndEnds(), -8, -236)
		street(BuildingArt.Sparkworks(), 24, -236)
		street(BuildingArt.SkyMarket(), 48, -240)
		street(BuildingArt.SkyTurnstile(), 64, -243.5)
		street(BuildingArt.SkyForgeCourt(), 100, -232)
		street(BuildingArt.LampPost(), 150, -243.3)

		table.insert(cameras, 1, {
			pos = { 260, 42, -200 },
			target = { -30, 12, -285 },
			fov = 48,
			label = "town-overview",
		})

		return {
			root = root,
			shadowRadius = 520,
			cameras = cameras,
		}
	end,
}
