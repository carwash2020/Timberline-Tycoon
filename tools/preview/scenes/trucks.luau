--!nocheck
-- Every truck in a row, each towing a trailer (the Scout ATV can't tow),
-- beds partly loaded (one Burl log in the Pickup's bed, banded the way
-- VehicleService bands a figured log), plus a lone Rustbucket up front for
-- close-ups.
-- A driver sits in every truck: a CharacterArt figure seated the way
-- Roblox seats an R15 (hips on the seat's top, at its middle), its legs
-- straight out in front (R6's worst case) and a 0.6-stud hat on, to check
-- heads and hats clear the roofs and legs stay inside the hoods.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local TruckArt = ctx.art("TruckArt")
		local CharacterArt = ctx.art("CharacterArt")
		local ForestArt = ctx.art("ForestArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local TruckLayout = ctx.shared("TruckLayout")
		local WoodData = ctx.shared("WoodData")
		local root = roblox.Instance.new("Model")

		Common.ground(ctx, root, 300, C3.fromRGB(116, 164, 84), V3.new(20, -0.5, 10))
		-- A packed-dirt lot under the trucks (they grew in M1.5: the longest
		-- rig is 57.9 studs).
		Kit.part(
			root,
			"Lot",
			V3.new(110, 0.1, 100),
			CF.new(24, 0.02, 4),
			C3.fromRGB(176, 146, 104),
			Enum.Material.Ground
		)

		local woods = { "oak", "birch", "pine", "maple", "oak", "pine", "birch", "emberwood", "oak", "maple" }
		-- `figures`: { [slot] = figure id } for figured logs.
		local function load(model, layout, floorName, slots, count, offset, figures)
			local floor = model:FindFirstChild(floorName)
			if not floor then
				return
			end
			for i = 1, math.min(count, #slots) do
				local wood = WoodData.Get(woods[(i + offset) % #woods + 1])
				local log = TruckArt.BedLog(floor, slots[i], wood, layout.logLength, i)
				local figure = figures and figures[i]
				if figure then
					log:SetAttribute("Figure", figure)
					ForestArt.FigureBand(log.PrimaryPart, figure)
				end
				log.Parent = root
			end
		end

		-- The driver: Motor6D Transforms applied the way Roblox does (Part1 =
		-- Part0 * C0 * Transform * C1:Inverse(), then the welded details
		-- follow), hips turned a quarter so the legs point forward.
		local HAT = 0.6
		local function seatDriver(truck, shirt)
			local seat = truck:FindFirstChild("DriverSeat")
			if not seat then
				return
			end
			local fig = CharacterArt.Build({
				name = "Driver",
				skin = C3.fromHex("#E8B994"),
				shirt = shirt,
				pants = C3.fromHex("#3D4F6E"),
				hairStyle = "bald",
				hat = "none",
				tag = false,
			})
			local hip = fig.Torso:FindFirstChild("LeftHip")
			local hipY = (hip.Part0.CFrame * hip.C0).Y
			for _, name in ipairs({ "LeftHip", "RightHip" }) do
				local motor = fig.Torso:FindFirstChild(name)
				motor.Part1.CFrame = motor.Part0.CFrame * motor.C0 * CF.Angles(math.pi / 2, 0, 0) * motor.C1:Inverse()
			end
			for _, d in ipairs(fig:GetDescendants()) do
				local w = d:IsA("BasePart") and d:FindFirstChild("Weld")
				if w then
					d.CFrame = w.Part0.CFrame * w.C0
				end
			end
			local head = fig.Head
			Kit.part(
				fig,
				"Hat",
				V3.new(1.44, HAT, 1.3),
				head.CFrame * CF.new(0, head.Size.Y / 2 + HAT / 2, 0),
				C3.fromHex("#7A3FA0"),
				Enum.Material.Fabric
			)
			-- The hip joints on the seat's top, over its middle.
			local rootY = fig:GetPivot().Y
			fig:PivotTo(seat.CFrame * CF.new(0, seat.Size.Y / 2 + rootY - hipY, 0))
			fig.Parent = root
		end
		local shirts = { "#C8553D", "#E9C46A", "#2A9D8F", "#F4F1DE", "#264653" }

		local rigs = {
			{ "Rustbucket", "PonyTrailer", 5, 4 },
			{ "Pickup", "RanchTrailer", 9, 7, { [8] = "burl" } }, -- the Burl on top, by the cab
			{ "ScoutATV", nil, 0, 0 },
			{ "Flatbed", "RanchTrailer", 16, 0 },
			{ "LoggingRig", "HeavyHauler", 40, 20 },
		}
		local spacing = 11 -- as far apart as the parking slots
		for i, entry in ipairs(rigs) do
			local def = ItemCatalog.GetTruck(entry[1])
			local layout = TruckLayout.For(def)
			local trailer = if entry[2] then ItemCatalog.GetTrailer(entry[2]) else nil
			local tl = if trailer then TruckLayout.ForTrailer(trailer, layout) else nil
			local model = TruckArt.Build(def, layout, trailer, tl)
			Kit.placeAt(model, CF.new((i - 1) * spacing, 0, 0))
			model.Parent = root
			seatDriver(model, C3.fromHex(shirts[i]))
			load(model, layout, "BedFloor", layout.logSlots, entry[3], i, entry[5])
			if tl then
				load(model, layout, "TrailerBed", tl.logSlots, entry[4], i + 3)
			end
		end

		-- A lone Rustbucket out front, turned toward the camera.
		local rust = ItemCatalog.GetTruck("Rustbucket")
		local rustLayout = TruckLayout.For(rust)
		local lone = TruckArt.Build(rust, rustLayout)
		Kit.placeAt(lone, CF.new(-24, 0, -32) * CF.Angles(0, math.rad(35), 0))
		lone.Parent = root
		seatDriver(lone, C3.fromHex("#4C7A3E"))
		load(lone, rustLayout, "BedFloor", rustLayout.logSlots, 6, 2)

		local function at(i)
			return (i - 1) * spacing
		end
		-- Where the Pickup's driver's head is (for the seated-driver view).
		local pickupSeat = TruckLayout.For(ItemCatalog.GetTruck("Pickup")).front + 6.1
		return {
			root = root,
			shadowRadius = 110,
			cameras = {
				{ pos = { -40, 34, -70 }, target = { 28, 3, 8 }, label = "line-up" },
				{ pos = { 28, 12, -62 }, target = { 28, 4, 2 }, label = "line-up, front" },
				{ pos = { -22, 8, -50 }, target = { -24.5, 3.2, -32 }, label = "Rustbucket" },
				{ pos = { -41, 7, -19 }, target = { -24, 3.2, -32 }, label = "Rustbucket, side" },
				{ pos = { -11, 11, 40 }, target = { at(1), 3, 16 }, label = "Rustbucket + Pony, rear" },
				{ pos = { at(2) - 12, 9, -24 }, target = { at(2), 4, -6 }, label = "Pickup" },
				{ pos = { at(3) - 8, 6.5, -12 }, target = { at(3), 3, 0 }, label = "Scout ATV" },
				{ pos = { at(4) - 14, 12, -30 }, target = { at(4), 4, -6 }, label = "Flatbed" },
				{ pos = { at(5) - 16, 12, -38 }, target = { at(5), 4.5, -10 }, label = "Logging Rig" },
				{ pos = { at(5) + 26, 14, 36 }, target = { at(5), 4, 20 }, label = "Logging Rig + Heavy Hauler" },
				-- From the Pickup's passenger side: the seated driver's head and hat
				-- under the roof, the Burl on the load behind the cab.
				{
					pos = { at(2) + 9, 6.8, pickupSeat - 1.5 },
					target = { at(2), 5.6, pickupSeat },
					label = "Pickup, seated driver",
				},
				-- Every cab from the front at hat height (M1.5): each driver (an
				-- avatar-sized figure, a 0.6 hat on) sits with room to spare under
				-- the roofs, the bigger the truck the more.
				{ pos = { 21, 6.4, -46 }, target = { 21, 6.0, -10 }, label = "hats under the roofs, front" },
			},
		}
	end,
}
