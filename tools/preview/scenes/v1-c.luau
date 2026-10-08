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
		local function place(model, x, z, cam, label)
			Kit.placeAt(model, CF.new(x, 0, z))
			model.Parent = root
			table.insert(cameras, {
				pos = { x + cam[1], cam[2], z + cam[3] },
				target = { x + (cam[4] or 0), cam[5] or 4, z + (cam[6] or 0) },
				label = label,
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
		place(PropArt.Scene("fishing"), 80, 360, { -6, 5, -8, 0, 1, -4 }, "scene-fishing")
		place(PropArt.Scene("campfire"), 110, 360, { -5, 4, -6, 0, 1, 0 }, "scene-campfire")
		place(PropArt.Scene("lookout"), 140, 360, { -6, 5, -8, 0, 1, 0 }, "scene-lookout")
		place(PropArt.Scene("bench"), 165, 360, { -5, 4, -7, 0, 1, 0 }, "scene-bench")
		place(MachineArt.Build("SawmillRickety", false), 210, 360, { -8, 6, -12, 0, 2, 0 }, "machine-sawmill")

		table.insert(cameras, 1, {
			pos = { 220, 90, -80 },
			target = { 220, 0, 140 },
			label = "town-overview",
		})

		return {
			root = root,
			shadowRadius = 280,
			cameras = cameras,
		}
	end,
}
