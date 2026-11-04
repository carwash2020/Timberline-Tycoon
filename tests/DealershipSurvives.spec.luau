--!nocheck
-- T417: one vehicle that cannot be built never aborts the Dealership lot (Studio: "4. The
-- dealership lot failed" took the whole showroom down on a CollisionFidelity write).
return function(t)
	t.support("VehicleStock")(function(path)
		return t.load(path)
	end, t.roblox)
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local ItemCatalog = t.shared("ItemCatalog")

	local function plinths(lot)
		local n = 0
		for _, d in ipairs(lot:GetDescendants()) do
			if d.Name == "Plinth" or d.Name == "PlinthTop" then
				n += 1
			end
		end
		return n
	end

	t.test("a truck that errors in its build leaves the lot standing and is named", function()
		local good = DealershipLot.Build()
		t.eq(
			#DealershipLot.Failures,
			0,
			"a normal build has no failures: " .. table.concat(DealershipLot.Failures, "; ")
		)
		local goodPlinths = plinths(good)
		local goodParts = #good:GetDescendants()

		local victim = ItemCatalog.TruckList()[1]
		local original = TruckArt.Build
		TruckArt.Build = function(def, ...)
			if def.id == victim.id then
				error("The current thread cannot write 'CollisionFidelity' (lacking capability PluginOrOpenCloud)")
			end
			return original(def, ...)
		end
		local ok, lot = pcall(DealershipLot.Build)
		TruckArt.Build = original
		t.ok(ok, "the lot builds: " .. tostring(lot))
		t.ok(#DealershipLot.Failures >= 1, "the failure is kept")
		t.ok(
			string.find(DealershipLot.Failures[1], victim.id, 1, true),
			"it names the vehicle: " .. DealershipLot.Failures[1]
		)
		t.ok(string.find(DealershipLot.Failures[1], "CollisionFidelity", 1, true), "and the real error")
		t.eq(plinths(lot), goodPlinths, "every plinth is still there")
		t.ok(#lot:GetDescendants() > goodParts * 0.7, "the other vehicles are still stocked")
	end)
end
