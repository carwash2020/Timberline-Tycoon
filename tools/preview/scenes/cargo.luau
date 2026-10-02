--!nocheck
-- The v2 loop's loads (V2_PLAN.md §4b, M1.6): bucked v2 logs lying loose
-- on every truck's and trailer's bed, the way TruckLoad carries them.
-- Each log is a real section piece (TreeGen's trunk thickness for its
-- wood, TreeArt.FromSkeleton, a TreeArt.CutFace at each end), cut to fit
-- its bed, side by side along it, a second layer on the bigger beds, each
-- nudged a little as dragged wood lies. Front row: the loaded rigs. Back
-- row: the same rigs empty, their BedZones (invisible in the game) drawn
-- as translucent boxes, to check each covers its bed.
-- Views: 1 the line-up; 2 Rustbucket + Pony; 3 Pickup + Ranch;
-- 4 Flatbed + Ranch; 5 Logging Rig + Heavy Hauler; 6 the BedZones.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local TruckArt = ctx.art("TruckArt")
		local TreeArt = ctx.art("TreeArt")
		local CharacterArt = ctx.art("CharacterArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local TruckLayout = ctx.shared("TruckLayout")
		local TreeGen = ctx.shared("TreeGen")
		local WoodData = ctx.shared("WoodData")
		local root = roblox.Instance.new("Model")

		Common.ground(ctx, root, 400, C3.fromRGB(116, 164, 84), V3.new(20, -0.5, 40))
		Kit.part(
			root,
			"Lot",
			V3.new(70, 0.1, 150),
			CF.new(16, 0.02, 40),
			C3.fromRGB(176, 146, 104),
			Enum.Material.Ground
		)

		-- A wood's trunk thickness at the base, from a real skeleton.
		local thickness = {}
		local function trunk(woodId)
			if not thickness[woodId] then
				thickness[woodId] = TreeGen.Skeleton(woodId, 2, 1).sections[1].thickness
			end
			return thickness[woodId]
		end

		-- One bucked log: a one-section piece of `woodId`, `length` long.
		local function log(woodId, length)
			local def = WoodData.Get(woodId)
			local t = trunk(woodId)
			local fake = {
				woodId = woodId,
				seed = 1,
				scale = 1,
				stage = 1,
				elder = false,
				trunkSegments = 1,
				maxDepth = 0,
				height = t,
				width = t,
				stretch = 1,
				sections = {
					{
						id = 1,
						children = {},
						depth = 0,
						cf = CF.identity,
						length = length,
						thickness = t,
						dress = {},
					},
				},
			}
			local model = TreeArt.FromSkeleton(def, fake)
			TreeArt.CutFace(def, model.PrimaryPart, true)
			TreeArt.CutFace(def, model.PrimaryPart, false)
			return model, t
		end

		-- Fills `bedName` on `truck` with `woodId` logs cut to fit, side by
		-- side along the bed, `layers` deep (the top layer one log fewer,
		-- nested between the logs below).
		local function load(truck, bedName, woodId, layers, seed)
			local bed = truck:FindFirstChild(bedName)
			local zone = bed and bed:FindFirstChild("BedZone")
			if not zone then
				return
			end
			local rng = Kit.rng(seed)
			local inside, along = zone.Size.X, zone.Size.Z
			local t = trunk(woodId)
			local floorTop = bed.Size.Y / 2
			local length = along - 0.6
			for layer = 0, layers - 1 do
				local across = math.max(1, math.floor((inside - 0.2) / (t + 0.08))) - layer
				for n = 1, across do
					local piece = log(woodId, length * rng:range(0.86, 0.97))
					local span = across * (t + 0.08)
					local x = -span / 2 + (n - 0.5) * (t + 0.08)
					local y = floorTop + t / 2 + layer * t * 0.86
					local z = rng:range(-0.3, 0.3)
					local len = piece.PrimaryPart.Size.Y
					local cf = bed.CFrame
						* CF.new(x, y, z)
						* CF.Angles(0, rng:range(-0.04, 0.04), rng:range(-0.05, 0.05))
						* CF.new(0, 0, -len / 2)
						* CF.Angles(math.pi / 2, 0, 0)
					Kit.placeAt(piece, cf)
					piece.Parent = root
				end
			end
		end

		local rigs = {
			{ "Rustbucket", "PonyTrailer", "oak", "birch", 1 },
			{ "Pickup", "RanchTrailer", "birch", "maple", 1 },
			{ "Flatbed", "RanchTrailer", "pine", "oak", 2 },
			{ "LoggingRig", "HeavyHauler", "pine", "frostwood", 2 },
		}
		local spacing = 11
		local function rig(entry, i, z)
			local def = ItemCatalog.GetTruck(entry[1])
			local layout = TruckLayout.For(def)
			local trailer = ItemCatalog.GetTrailer(entry[2])
			local tl = TruckLayout.ForTrailer(trailer, layout)
			local model = TruckArt.Build(def, layout, trailer, tl)
			Kit.placeAt(model, CF.new((i - 1) * spacing, 0, z))
			model.Parent = root
			return model
		end
		for i, entry in ipairs(rigs) do
			local model = rig(entry, i, 0)
			load(model, "BedFloor", entry[3], entry[5], i * 7)
			load(model, "TrailerBed", entry[4], entry[5], i * 7 + 3)
		end
		-- The back row: empty, BedZones drawn.
		local ZONES = 80
		for i, entry in ipairs(rigs) do
			local model = rig(entry, i, ZONES)
			for _, z in ipairs(TruckArt.BedZones(model)) do
				local shown = Kit.part(
					root,
					"ShownBedZone",
					z.zone.Size,
					z.zone.CFrame,
					C3.fromRGB(80, 200, 255),
					Enum.Material.SmoothPlastic
				)
				shown.Transparency = 0.55
			end
		end
		local fig = CharacterArt.Build({
			name = "Dummy",
			skin = C3.fromHex("#E8B994"),
			shirt = C3.fromHex("#B8382E"),
			pants = C3.fromHex("#3D5A8C"),
			hairStyle = "bald",
			hat = "none",
			tag = false,
		})
		Kit.placeAt(fig, CF.new(-7, 0, 6))
		fig.Parent = root

		local function at(i)
			return (i - 1) * spacing
		end
		return {
			root = root,
			shadowRadius = 110,
			cameras = {
				{ pos = { -34, 30, 52 }, target = { 18, 3, 14 }, label = "1 loaded line-up" },
				{ pos = { at(1) - 13, 12, 26 }, target = { at(1), 3, 10 }, label = "2 Rustbucket + Pony" },
				{ pos = { at(2) - 13, 13, 30 }, target = { at(2), 3, 12 }, label = "3 Pickup + Ranch" },
				{ pos = { at(3) - 15, 15, 36 }, target = { at(3), 3.5, 14 }, label = "4 Flatbed + Ranch" },
				{ pos = { at(4) + 18, 17, 44 }, target = { at(4), 4, 16 }, label = "5 Logging Rig + Heavy Hauler" },
				{ pos = { -30, 34, ZONES + 50 }, target = { 18, 3, ZONES + 12 }, label = "6 BedZones" },
			},
		}
	end,
}
