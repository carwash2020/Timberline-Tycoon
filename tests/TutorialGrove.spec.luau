--!nocheck
-- The tutorial grove: spots that stay off the roads, the street, the spawn
-- walk and the townsfolk, and a first sale at the sawmill that can fund the
-- plot and the Rustbucket (Murph's buy cart is gone).
return function(t)
	local TutorialGrove = t.shared("TutorialGrove")
	local WorldLayout = t.shared("World/WorldLayout")
	local NPCData = t.shared("NPCData")
	local TreeGen = t.shared("TreeGen")
	local SectionLogic = t.shared("SectionLogic")

	local function spots()
		return TutorialGrove.Trees
	end

	local function segDist(px, pz, ax, az, bx, bz)
		local dx, dz = bx - ax, bz - az
		local len2 = dx * dx + dz * dz
		local t = if len2 <= 0 then 0 else math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1)
		local qx, qz = ax + dx * t, az + dz * t
		return math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2)
	end

	t.test("the grove stays off the roads, the town paint and the walkers", function()
		for _, spot in ipairs(spots()) do
			t.ok(
				math.sqrt(spot.x ^ 2 + (spot.z - 40) ^ 2) < 35,
				string.format("near the spawn: %g, %g", spot.x, spot.z)
			)
			for _, road in ipairs(WorldLayout.Roads) do
				local points = road.points
				for i = 1, #points - 1 do
					local a, b = points[i], points[i + 1]
					local d = segDist(spot.x, spot.z, a.X, a.Y, b.X, b.Y)
					t.ok(
						d > road.width / 2 + 2,
						string.format("%s is %0.1f from (%g, %g)", road.name, d, spot.x, spot.z)
					)
				end
			end
			for _, paint in ipairs(WorldLayout.TownPaint) do
				local inside = spot.x >= paint.x0 - 2
					and spot.x <= paint.x1 + 2
					and spot.z >= paint.z0 - 2
					and spot.z <= paint.z1 + 2
				t.ok(not inside, string.format("%s covers (%g, %g)", paint.name, spot.x, spot.z))
			end
			local lot = WorldLayout.ParkingLot
			local inLot = spot.x >= lot.x0 - 2
				and spot.x <= lot.x1 + 2
				and spot.z >= lot.z0 - 2
				and spot.z <= lot.z1 + 2
			t.ok(not inLot, "the lot")
			t.ok(math.sqrt((spot.x + 28) ^ 2 + (spot.z - 45) ^ 2) > 6, "Murph's camp")
		end
		for _, npc in ipairs(NPCData.List) do
			local route = npc.route
			if route then
				for i, w in ipairs(route) do
					for _, spot in ipairs(spots()) do
						local d = math.sqrt((spot.x - w.x) ^ 2 + (spot.z - w.z) ^ 2)
						t.ok(d > 4, string.format("%s mark (%g, %g) is %0.1f from the grove", npc.id, w.x, w.z, d))
						local nxt = route[i % #route + 1]
						local along = segDist(spot.x, spot.z, w.x, w.z, nxt.x, nxt.z)
						t.ok(along > 4, string.format("%s's walk passes %0.1f from the grove", npc.id, along))
					end
				end
			end
		end
	end)

	t.test(
		"no soft-lock: a few small oaks sold at the sawmill buy the plot, and the plot's payback the truck",
		function()
			local GameConfig = t.shared("GameConfig")
			local SellLogic = t.shared("SellLogic")
			local ItemCatalog = t.shared("ItemCatalog")
			local ShopLogic = t.shared("ShopLogic")
			local TutorialData = t.shared("TutorialData")
			local byId = {}
			for _, step in ipairs(TutorialData.StepsV2) do
				byId[step.id] = step
			end
			local truck = ShopLogic.Price(ItemCatalog.GetTruck("Rustbucket"), 2)
			-- The sawmill pays by volume with no cap and no minimum (the cart's
			-- 80 u3 cap is gone), so a player is never refused: the worst case is
			-- the smallest tutorial oak, sold again and again.
			local least = math.huge
			for seed = 4100, 4106 do
				local skel = TreeGen.Skeleton("oak", seed, TreeGen.ScaleFor("small"))
				local volume = 0
				for _, section in ipairs(skel.sections) do
					volume += SectionLogic.Volume(section.thickness, section.length, section.thickness)
				end
				t.ok(volume > 5, "a real tree")
				least = math.min(least, SellLogic.Payout(SellLogic.PieceValue("oak", "log", volume, nil, 1, false), 1))
			end
			t.ok(least > 0, "an oak always pays something")
			local before = GameConfig.StartingCash + byId.sell.rewardCash
			local oaks = math.ceil((GameConfig.PlotPrice - before) / least)
			t.ok(oaks <= 8, string.format("%d small oaks ($%0.1f each) to afford the plot", oaks, least))
			-- Bought, the plot pays Murph's share back: the box is within reach.
			local after = before + oaks * least - GameConfig.PlotPrice + byId.plot.rewardCash
			t.ok(after + 8 * least >= truck, "the Rustbucket box follows from the plot's payback and a few more oaks")
			t.eq(byId.plot.cashPrice, GameConfig.PlotPrice)
		end
	)
end
