--!nocheck
-- T421: the coverage list is exactly the 15 combos (3 trailers x the 5 towing trucks), each with all four trailer
-- meshes of its truck's variant and its truck's own meshes mapped to keys. The Scout ATV tows nothing.
return function(t)
	local Gate = t.shared("VehicleMeshGate")
	local ItemCatalog = t.shared("ItemCatalog")
	local VehicleModels = t.load("ReplicatedStorage/Shared/Art/VehicleModels")
	local VehicleMeshes = t.load("ReplicatedStorage/Shared/Art/VehicleMeshes")
	local TruckLayout = t.shared("TruckLayout")

	local keys = {}
	for _, key in ipairs(VehicleMeshes.MeshKeys()) do
		keys[key] = true
	end

	t.test("exactly 15 combos: 3 trailers x Rustbucket, Pickup, Flatbed, LoggingRig, TimberClassic", function()
		local combos = Gate.Combos()
		t.eq(#combos, 15)
		local seen = {}
		for _, c in ipairs(combos) do
			local name = c.truck .. "+" .. c.trailer
			t.eq(seen[name], nil, name .. " is listed twice")
			seen[name] = true
			t.ok(ItemCatalog.GetTruck(c.truck) ~= nil, c.truck)
			t.ok(ItemCatalog.GetTrailer(c.trailer) ~= nil, c.trailer)
		end
		t.eq(Gate.Tow, { "Rustbucket", "Pickup", "Flatbed", "LoggingRig", "TimberClassic" })
	end)

	t.test("each combo has all four trailer meshes of its variant, each a known key", function()
		for _, c in ipairs(Gate.Combos()) do
			t.eq(#c.trailerKeys, 4, c.truck .. "+" .. c.trailer)
			for i, part in ipairs({ "Body", "Bed", "Lights", "Hitch" }) do
				t.eq(c.trailerKeys[i], c.trailer .. "/" .. c.variant .. "/" .. part)
				t.ok(keys[c.trailerKeys[i]], c.trailerKeys[i] .. " is a key")
			end
			t.ok(
				VehicleModels.Trailer(c.trailer, c.variant) ~= nil,
				"a piece table for " .. c.trailer .. "/" .. c.variant
			)
		end
	end)

	t.test("its truck's meshes are mapped: the four trucks' six parts each, the Timber Classic's six", function()
		for _, c in ipairs(Gate.Combos()) do
			t.eq(#c.truckKeys, 6, c.truck)
			for _, key in ipairs(c.truckKeys) do
				t.ok(keys[key], key .. " is a key")
			end
		end
	end)

	t.test("the Timber Classic uses the Pickup's trailer variants; the others their own", function()
		for _, c in ipairs(Gate.Combos()) do
			t.eq(c.variant, if c.truck == "TimberClassic" then "Pickup" else c.truck)
		end
	end)

	t.test("the Scout ATV has no hitch and cannot take a trailer", function()
		local atv = ItemCatalog.GetTruck("ScoutATV")
		t.eq(VehicleModels.Truck("ScoutATV").Hitch, nil, "no hitch mesh (hitch = nil)")
		t.eq(atv.look.bedLength, 0)
		t.eq(atv.bedCapacity, 0)
		t.eq(Gate.VariantFor("ScoutATV"), nil)
		t.eq(TruckLayout.StyleOf(atv), "atv")
		for _, c in ipairs(Gate.Combos()) do
			t.ok(c.truck ~= "ScoutATV", "the Scout tows nothing")
		end
		for _, trailerId in ipairs(Gate.Trailers) do
			for _, variant in ipairs(Gate.Variants) do
				t.ok(keys[trailerId .. "/" .. variant .. "/Hitch"], "variants are for towing trucks only")
			end
			t.eq(keys[trailerId .. "/ScoutATV/Body"], nil, "no Scout variant")
		end
	end)
	t.test(
		"each truck's Wheel mesh is cloned onto every wheel centre, the Classic's four from TimberClassicData",
		function()
			local roblox = t.roblox
			local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
			local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
			local Data = t.shared("TimberClassicData")
			Gate.SetIds(Gate.FakeIds())
			MeshKit.Reset()
			MeshKit.Override = function(id, name, size)
				local part = roblox.Instance.new("MeshPart")
				part.Name = name
				part.Size = size
				part:SetAttribute("MeshId", tostring(id))
				return part
			end
			local ok, err = pcall(function()
				for _, def in ipairs(ItemCatalog.TruckList()) do
					local lay = TruckLayout.For(def)
					local model = TruckArt.Build(def, lay)
					t.eq(model:GetAttribute("VehicleMesh"), true, def.id .. " is meshed")
					local found = {}
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("MeshPart") and d.Name == "Wheel" and d:GetAttribute("Radius") ~= nil then
							table.insert(found, d)
						end
					end
					t.eq(#found, #lay.wheelZ * 2, def.id .. " has a Wheel mesh per wheel")
					local want = {}
					if def.id == "TimberClassic" then
						for _, c in ipairs(Data.WheelCentres) do
							table.insert(want, c)
						end
					else
						for _, z in ipairs(lay.wheelZ) do
							for _, side in ipairs({ -1, 1 }) do
								table.insert(want, roblox.Vector3.new(side * lay.wheelX, lay.wheelRadius, z))
							end
						end
					end
					for _, c in ipairs(want) do
						local hit
						for _, w in ipairs(found) do
							if (w.CFrame.Position - c).Magnitude < 0.02 then
								hit = w
							end
						end
						t.ok(hit ~= nil, def.id .. " has a wheel mesh at " .. tostring(c))
						-- the clone is that truck's own Wheel mesh: trucks/<Truck>/Wheel, or TimberClassic/Wheel
						local wheelKey = Gate.TruckKey(def.id, "Wheel")
						if Gate.IdOf(wheelKey) ~= nil then
							t.eq(
								hit:GetAttribute("MeshId"),
								Gate.IdOf(wheelKey),
								def.id .. " wheel mesh is " .. wheelKey
							)
						end
					end
				end
			end)
			MeshKit.Override = nil
			MeshKit.Reset()
			Gate.SetIds(nil)
			if not ok then
				error(err, 0)
			end
		end
	)
end
