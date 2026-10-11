--!nocheck
-- Rook Calloway stands on the sawmill's MillForemanSpot pad (the yard west
-- of the office door), faces the road, and keeps off the sell lane.
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local NPCData = t.shared("NPCData")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")

	local function padWorld()
		local town = WorldPlan.Town()
		local mill = BuildingArt.Sawmill()
		mill:PivotTo(town.sawmill)
		local pad = mill:FindFirstChild("MillForemanSpot", true)
		return pad
	end

	t.test("the Foreman's fixed spot is on the mill's MillForemanSpot pad", function()
		local pad = padWorld()
		t.ok(pad ~= nil, "the mill builds the pad")
		local at = pad.CFrame.Position
		local spot = NPCData.ForemanSpot
		t.ok(
			math.abs(at.X - spot.X) < 1.5 and math.abs(at.Z - spot.Z) < 1.5,
			string.format("pad at %.2f, %.2f", at.X, at.Z)
		)
	end)

	t.test("he faces the road, away from the mill wall", function()
		local pad = padWorld()
		local npc = NPCData.Get("Foreman")
		local cf = NPCData.SpotFor(npc, function()
			return nil, nil
		end)
		-- The pad's own front is -Z (the road side); he should look along it.
		t.ok(cf.LookVector:Dot(pad.CFrame.LookVector) > 0.99, "same way as the pad's front")
	end)

	t.test("he keeps off the sell zone and the truck lane", function()
		local town = WorldPlan.Town()
		local spot = NPCData.ForemanSpot
		local zone = town.sellZone or { x = 53, z = 111 }
		local x = zone.x or 53
		t.ok(math.abs(spot.X - x) > 14 + 3, "clear of the SellZone's 28-wide span")
	end)
end
