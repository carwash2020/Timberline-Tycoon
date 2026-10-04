--!nocheck
-- Murph's cart: one small tutorial sale, and a spot that stays off the
-- roads, the street, the spawn walk and the townsfolk.
return function(t)
	local TutorialGrove = t.shared("TutorialGrove")
	local WorldLayout = t.shared("World/WorldLayout")
	local NPCData = t.shared("NPCData")
	local TreeGen = t.shared("TreeGen")
	local SectionLogic = t.shared("SectionLogic")

	local function offer(extra)
		local base = {
			done = false,
			stepId = "sell",
			pieces = 1,
			volume = 10,
			logs = 1,
			cartVolume = 0,
			cash = 20,
			ownsTruck = false,
			truckPrice = 75,
		}
		for k, v in pairs(extra or {}) do
			base[k] = v
		end
		return base
	end

	t.test("the cart buys small loads during sell, plot and truck", function()
		local ok, why = TutorialGrove.Accept(offer())
		t.eq(ok, true)
		t.eq(why, nil)
		t.eq(select(1, TutorialGrove.Accept(offer({ pieces = 0 }))), false)
		t.eq(select(1, TutorialGrove.Accept(offer({ stepId = "plot" }))), true, "a sale during the plot step")
		t.eq(select(1, TutorialGrove.Accept(offer({ stepId = "truck" }))), true)
		t.eq(select(2, TutorialGrove.Accept(offer({ done = true }))), TutorialGrove.RefuseClosed)
		t.eq(select(2, TutorialGrove.Accept(offer({ stepId = "load" }))), TutorialGrove.RefuseClosed)
		t.eq(select(2, TutorialGrove.Accept(offer({ stepId = "fell" }))), TutorialGrove.RefuseClosed)
		local over = offer()
		over.stepId = nil -- a finished tutorial has no step
		t.eq(select(2, TutorialGrove.Accept(over)), TutorialGrove.RefuseClosed)
		t.eq(select(2, TutorialGrove.Accept(offer({ pieces = TutorialGrove.MaxPieces + 1 }))), TutorialGrove.RefuseBig)
		t.eq(select(2, TutorialGrove.Accept(offer({ volume = TutorialGrove.MaxVolume + 1 }))), TutorialGrove.RefuseBig)
		t.eq(select(2, TutorialGrove.Accept(offer({ logs = TutorialGrove.MaxLogs + 1 }))), TutorialGrove.RefuseBig)
		t.eq(select(1, TutorialGrove.Accept(offer({ volume = nil, logs = nil, pieces = 2 }))), true)
	end)

	t.test("three single-piece sales in a row pass, and a sale past 80 is refused", function()
		local slot = { cartVolume = 0 }
		for n = 1, 3 do
			local ok, why = TutorialGrove.Accept(offer({
				volume = 10,
				cartVolume = TutorialGrove.SavedVolume(slot),
			}))
			t.eq(ok, true, why)
			TutorialGrove.Remember(slot, 10)
			t.eq(slot.cartVolume, n * 10)
		end
		t.eq(select(1, TutorialGrove.Accept(offer({ volume = 10, cartVolume = 70 }))), true, "80 exactly still fits")
		t.eq(
			select(2, TutorialGrove.Accept(offer({ volume = 10, cartVolume = 75 }))),
			TutorialGrove.RefuseBig,
			"75 + 10 passes 80"
		)
	end)

	t.test("a second v1 cart sale during the truck step is refused", function()
		local slot = { cartUsed = false }
		local first = {
			done = false,
			stepId = "sell",
			used = slot.cartUsed,
			pieces = 1,
			logs = 2,
		}
		t.eq(select(1, TutorialGrove.AcceptV1(first)), true)
		slot.cartUsed = true -- GameServer sets this on the slot after the sale
		t.eq(
			select(
				2,
				TutorialGrove.AcceptV1({
					done = false,
					stepId = "truck",
					used = slot.cartUsed,
					pieces = 1,
					logs = 2,
				})
			),
			TutorialGrove.RefuseUsed
		)
		-- Another slot has not used its cart, so its first sale still stands.
		t.eq(
			select(
				1,
				TutorialGrove.AcceptV1({
					done = false,
					stepId = "sell",
					used = false,
					pieces = 1,
					logs = 2,
				})
			),
			true
		)
	end)

	t.test("starting cash, Murph's bonus and a full cart of oak or birch cover the Rustbucket", function()
		local GameConfig = t.shared("GameConfig")
		local SellLogic = t.shared("SellLogic")
		local TutorialData = t.shared("TutorialData")
		local function bonusOf(steps)
			local bonus = 0
			for _, step in ipairs(steps) do
				if step.id == "sell" then
					bonus = step.rewardCash or 0
				end
			end
			return bonus
		end
		-- The same pricing SellService uses (SellLogic.PieceValue, then Payout).
		local function cartPay(woodId: string): number
			local gross = SellLogic.PieceValue(woodId, "log", TutorialGrove.MaxVolume, nil, 1, false)
			return SellLogic.Payout(gross, 1)
		end
		local function covers(loop: number, steps, label: string)
			local price = TutorialGrove.TruckPrice(loop)
			local purse = GameConfig.StartingCash + bonusOf(steps)
			t.ok(purse + cartPay("oak") >= price, label .. " oak")
			t.ok(purse + cartPay("birch") >= price, label .. " birch")
		end
		covers(2, TutorialData.StepsV2, "v2")
		-- v1 uses TutorialData.Steps' sell reward, not the v2 step's.
		covers(1, TutorialData.Steps, "v1")
	end)

	t.test("the cart refuses at $75 or with a truck owned", function()
		t.eq(select(1, TutorialGrove.Accept(offer({ cash = 74 }))), true)
		t.eq(select(2, TutorialGrove.Accept(offer({ cash = 75 }))), TutorialGrove.RefuseUsed)
		t.eq(select(2, TutorialGrove.Accept(offer({ cash = 200 }))), TutorialGrove.RefuseUsed)
		t.eq(select(2, TutorialGrove.Accept(offer({ ownsTruck = true, cash = 0 }))), TutorialGrove.RefuseUsed)
		t.eq(TutorialGrove.TruckPrice(2), 75)
	end)

	local function spots()
		local out = {}
		for _, tree in ipairs(TutorialGrove.Trees) do
			table.insert(out, tree)
		end
		local c = TutorialGrove.Cart
		local half = TutorialGrove.ZoneSize / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				table.insert(out, { x = c.x + sx * half.X, z = c.z + sz * half.Z })
			end
		end
		table.insert(out, c)
		return out
	end

	local function segDist(px, pz, ax, az, bx, bz)
		local dx, dz = bx - ax, bz - az
		local len2 = dx * dx + dz * dz
		local t = if len2 <= 0 then 0 else math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1)
		local qx, qz = ax + dx * t, az + dz * t
		return math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2)
	end

	t.test("the grove and the cart stay off the roads, the town paint and the walkers", function()
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

	t.test("one small oak fits on the cart", function()
		local scale = TreeGen.ScaleFor("small")
		for seed = 4100, 4106 do
			local skel = TreeGen.Skeleton("oak", seed, scale)
			local volume = 0
			for _, section in ipairs(skel.sections) do
				volume += SectionLogic.Volume(section.thickness, section.length, section.thickness)
			end
			t.ok(volume > 5, "a real tree")
			t.ok(volume <= TutorialGrove.MaxVolume, string.format("seed %d is %0.1f u³", seed, volume))
		end
	end)
end
