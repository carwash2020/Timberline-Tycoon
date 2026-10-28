--!nocheck
-- T413 travel greyboxes: the free town bridge, the paid lift, the car ferry
-- and its docks, the Skyroot hairpin, and one junction sign.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local TravelArt = ctx.art("TravelArt")
		local LandmarkArt = ctx.art("LandmarkArt")
		local FerryLogic = ctx.shared("FerryLogic")
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
		-- A LoggingRig plus trailer ghost, 75 studs, on the deck.
		local ghost = roblox.Instance.new("Part")
		ghost.Name = "RigGhost"
		ghost.Anchored = true
		ghost.CanCollide = false
		ghost.Transparency = 0.45
		ghost.Size = V3.new(10, 4, 75)
		ghost.Color = C3.fromRGB(196, 154, 99)
		ghost.CFrame = boat:GetPivot() * CF.new(0, 3, 0)
		ghost.Parent = boat
		return {
			root = root,
			shadowRadius = 40,
			fov = 40,
			lighting = {
				sunDir = { -0.45, 0.72, -0.4 },
				sunColor = "#ffd2a0",
				sunIntensity = 2.1,
				skyTop = "#8eb4d8",
				skyBottom = "#f3d7b0",
				ground = "#6e7a68",
				hemiIntensity = 1.05,
				ambient = 0.45,
				fog = "#d5e2ea",
				fogNear = 80,
				fogFar = 420,
				bloom = 0.25,
			},
			cameras = {
				{ pos = { 113, 160, 80 }, target = { 113, 4, 80 }, label = "lift top" },
				{ pos = { 860, 36, -590 }, target = { 960, 4, -650 }, label = "ferry docks" },
				{ pos = { -90, 70, 620 }, target = { -178, 2, 691 }, label = "skyroot hairpin" },
				{ pos = { -48, 7, 28 }, target = { -60, 5, 40 }, label = "junction sign" },
			},
		}
	end,
}
