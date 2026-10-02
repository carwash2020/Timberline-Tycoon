--!nocheck
-- The townsfolk (Shared/NPCData + Art/CharacterArt): everyone in a row with
-- their name tags, then the town with each NPC where NPCService puts them
-- (keepers behind their counters, Millie by the sell pad, Gus by the
-- gondola, Murph at his camp) and the walkers' loops drawn on the ground.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local CharacterArt = ctx.art("CharacterArt")
		local BuildingArt = ctx.art("BuildingArt")
		local NPCData = ctx.shared("NPCData")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local root = roblox.Instance.new("Model")

		-- 1. The line-up, away from the town.
		local npcs = NPCData.All()
		local LX, LZ, GAP = 260, -60, 5
		local width = (#npcs - 1) * GAP
		Kit.part(
			root,
			"Ground",
			V3.new(width + 30, 1, 30),
			CF.new(LX + width / 2, -0.5, LZ),
			C3.fromRGB(112, 162, 82),
			Enum.Material.Grass
		)
		local murph
		for i, npc in ipairs(npcs) do
			local m = CharacterArt.Build(npc.look)
			Kit.placeAt(m, CF.new(LX + (i - 1) * GAP, 0, LZ))
			m.Parent = root
			if npc.id == "Murph" then
				murph = m
			end
		end

		-- 1b. Poses: the Motor6D Transforms NPCController uses, applied the way
		-- Roblox does (Part1 = Part0 * C0 * Transform * C1:Inverse(), then the
		-- welded details follow), to check the joints and the signs.
		local A = CF.Angles
		local function pose(m, transforms)
			for _, name in ipairs(CharacterArt.Joints) do
				local motor = m:FindFirstChild(name, true)
				local tr = transforms[name]
				if motor and tr then
					motor.Part1.CFrame = motor.Part0.CFrame * motor.C0 * tr * motor.C1:Inverse()
				end
			end
			for _, d in ipairs(m:GetDescendants()) do
				local w = d:IsA("BasePart") and d:FindFirstChild("Weld")
				if w then
					d.CFrame = w.Part0.CFrame * w.C0
				end
			end
		end
		local poses = {
			{ "Murph", "waving", { RightShoulder = A(0.15, 0, 3.0), Neck = A(0, 0.3, 0) * A(0.1, 0, 0.08) } },
			{ "Murph", "sipping", { LeftShoulder = A(0, -0.55, 0) * A(1.85, 0, 0), Neck = A(0.22, 0, 0) } },
			{
				"Rosa",
				"walking",
				{
					RootJoint = CF.new(0, 0.12, 0) * A(0.04, 0, 0),
					LeftHip = A(0.6, 0, 0),
					RightHip = A(-0.6, 0, 0),
					LeftShoulder = A(-0.22, 0, 0),
					RightShoulder = A(0.45, 0, 0),
				},
			},
			{ "Tink", "glasses", { RightShoulder = A(0, 0.62, 0) * A(2.35, 0, 0) } },
			{ "Dale", "wiping his brow", { RightShoulder = A(0, 0.75, 0) * A(2.45, 0, 0), Neck = A(-0.12, 0, 0) } },
			{
				"Millie",
				"checking her clipboard",
				{ LeftShoulder = A(0, -0.3, 0) * A(0.55, 0, 0), Neck = A(0, 0.25, 0) * A(-0.4, 0, 0) },
			},
			{ "Bram", "looking to his left", { Neck = A(0, 0.9, 0) * A(0.2, 0, 0) } },
		}
		local PZ = LZ + 40
		Kit.part(
			root,
			"PoseGround",
			V3.new(#poses * GAP + 20, 1, 24),
			CF.new(LX + (#poses - 1) * GAP / 2, -0.5, PZ),
			C3.fromRGB(112, 162, 82),
			Enum.Material.Grass
		)
		for i, p in ipairs(poses) do
			local look = table.clone(NPCData.Get(p[1]).look)
			look.role = p[2]
			local m = CharacterArt.Build(look)
			pose(m, p[3])
			Kit.placeAt(m, CF.new(LX + (i - 1) * GAP, 0, PZ))
			m.Parent = root
		end

		-- 2. The town, as MapBuilder lays it out.
		local town = WorldPlan.Town()
		Kit.part(
			root,
			"TownGround",
			V3.new(300, 1, 260),
			CF.new(0, -0.5, 80),
			C3.fromRGB(196, 184, 150),
			Enum.Material.Ground
		)
		local built = {}
		local function place(model, cf, name)
			Kit.placeAt(model, cf)
			model.Parent = root
			if name then
				model.Name = name
				built[name] = model
			end
			return model
		end
		place(BuildingArt.Sawmill(), town.sawmill)
		place(BuildingArt.SellPad(24, 18), town.sellPad)
		local sellArea = roblox.Instance.new("Model")
		sellArea.Name = "SellArea"
		local zone = Kit.part(sellArea, "SellZone", WorldPlan.SellZoneSize, town.sellZone, C3.new(1, 1, 1))
		zone.Transparency = 1
		sellArea.Parent = root
		built.SellArea = sellArea
		Kit.part(sellArea, "SkyBin", V3.new(4, 4, 4), town.skyBin, C3.fromRGB(130, 96, 60), Enum.Material.WoodPlanks)
		for _, spot in ipairs(town.shops) do
			place(BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe, spot.kind)
		end
		place(BuildingArt.GondolaStation(), town.gondola, "GondolaTown")
		place(BuildingArt.Campsite(), town.campsite)
		for _, cf in ipairs(town.lamps) do
			place(BuildingArt.LampPost(), cf)
		end
		for _, prop in ipairs(town.props) do
			place(BuildingArt.Prop(prop.name, prop.seed), prop.cframe)
		end
		for _, sign in ipairs(town.signs) do
			place(BuildingArt.Signpost(sign.text), sign.cframe)
		end
		for _, cf in ipairs(town.parkingSlots) do
			Kit.part(root, "Slot", WorldPlan.ParkingSlotSize, cf, C3.fromRGB(186, 168, 140), Enum.Material.Slate)
		end
		Kit.part(
			root,
			"Spawn",
			V3.new(6, 1, 6),
			CF.new(town.spawn),
			C3.fromRGB(168, 152, 128),
			Enum.Material.Cobblestone
		)

		local function find(modelName, partName)
			local model = built[modelName]
			local part = model and model:FindFirstChild(partName)
			if part then
				return part.CFrame, part.Size
			end
			return nil, nil
		end
		local ROUTE_COLORS = { C3.fromRGB(230, 90, 70), C3.fromRGB(70, 140, 230), C3.fromRGB(240, 200, 60) }
		local walkers = 0
		for _, npc in ipairs(npcs) do
			local m = CharacterArt.Build(npc.look)
			Kit.placeAt(m, NPCData.SpotFor(npc, find))
			m.Parent = root
			if npc.route then
				walkers += 1
				local color = ROUTE_COLORS[(walkers - 1) % #ROUTE_COLORS + 1]
				local n = #npc.route
				for i, w in ipairs(npc.route) do
					local nxt = npc.route[i % n + 1]
					-- (Not Kit.beam: it uses CFrame.lookAt, which Lune gets wrong.)
					local dx, dz = nxt.x - w.x, nxt.z - w.z
					Kit.part(
						root,
						"Route",
						V3.new(0.4, 0.12, math.sqrt(dx * dx + dz * dz)),
						CF.new((w.x + nxt.x) / 2, 0.08, (w.z + nxt.z) / 2) * CF.Angles(0, NPCData.YawOf(dx, dz), 0),
						color
					)
					Kit.part(root, "Waypoint", V3.new(1, 0.2, 1), CF.new(w.x, 0.1, w.z), color)
				end
			end
		end

		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		local mid = LX + width / 2
		local head = murph:FindFirstChild("Head")
		local eye = (head.CFrame * CF.new(0, 0.35, -5.2)).Position
		local look = head.CFrame.Position + V3.new(0, 0.05, 0)
		local portrait = cam(eye.X, eye.Y, eye.Z, look.X, look.Y, look.Z, "QuestUI's portrait framing (centre square)")
		portrait.fov = 30
		local function at(i)
			return LX + (i - 1) * GAP
		end
		return {
			root = root,
			shadowRadius = 160,
			fov = 40,
			cameras = {
				cam(mid, 4.5, LZ - 34, mid, 3, LZ, "the line-up"),
				cam(at(2), 4.2, LZ - 13, at(2), 3.4, LZ, "Murph, Millie, Tink"),
				cam(at(5), 4.2, LZ - 13, at(5), 3.4, LZ, "Dale, Hazel, Gus"),
				cam(at(8), 4.2, LZ - 13, at(8), 3.2, LZ, "Rosa, Pip, Old Bram"),
				cam(at(1) - 2.5, 5.4, LZ - 5.5, at(1), 4.5, LZ, "Murph up close"),
				cam(mid + 8, 7, LZ + 24, mid, 3, LZ, "from behind"),
				cam(at(1) - 9, 5, LZ - 7, at(3), 3, LZ, "three-quarter"),
				cam(-8, 150, 40, -8, 0, 74, "the town from above, walkers' loops"),
				-- West to Murph by his campfire, from 12 studs south of the spawn
				-- pad: from the pad itself, (-2, 6, 40), the TO THE WOODS sign at
				-- (-16, 44) hides his head and chest.
				cam(-4, 6, 28, -25, 3.5, 41.8, "Murph at his camp, from by the spawn"),
				cam(-45, 7, 84, -45, 3.5, 102, "Tink behind the Tool Shed counter"),
				cam(4, 9, 66, 12, 3, 90, "Millie by the sell pad"),
				cam(-24, 9, 128, -36, 3, 148, "Gus by the gondola"),
				cam(LX + 7.5, 4.5, LZ + 40 - 16, LX + 7.5, 3.6, LZ + 40, "poses: wave, sip, stride, glasses"),
				cam(LX + 22.5, 4.5, LZ + 40 - 16, LX + 22.5, 3.6, LZ + 40, "poses: wipe, clipboard, look"),
				cam(LX + 18, 5, LZ + 40 - 3, LX + 10, 3.4, LZ + 40, "poses from the side"),
				cam(at(3) + 4, 5, LZ - 6, at(3), 3.4, LZ, "Tink, three-quarter (apron, glasses)"),
				cam(at(6) - 4, 5, LZ - 6, at(6), 3.6, LZ, "Gus, three-quarter (vest, scarf)"),
				cam(at(5) + 4, 5, LZ - 6, at(5), 3.6, LZ, "Hazel, three-quarter (scarf, lantern)"),
				cam(at(8) - 3, 3.5, LZ - 5, at(8), 2.6, LZ, "Pip up close"),
				-- QuestUI's portrait, exactly: a FOV 30 camera at Murph's head *
				-- (0, 0.35, -5.2), looking at the head's centre + 0.05 up (its
				-- viewport is square, so read the centre square).
				portrait,
			},
		}
	end,
}
