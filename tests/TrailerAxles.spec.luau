--!nocheck
-- T421: a trailer's axles come only from the data (TrailerAxleData: the approved meshes' stats.json axles), one wheel
-- pair per axle. The values below are the brief's, trailer-local: the bed's middle is Z 0, the hitch is toward -Z.
return function(t)
	local fs = require("@lune/fs")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local TruckLayout = t.shared("TruckLayout")
	local TrailerAxleData = t.shared("TrailerAxleData")
	local ItemCatalog = t.shared("ItemCatalog")

	local WANT = {
		PonyTrailer = { 1.30 },
		RanchTrailer = { 0.26, 3.38 },
		HeavyHauler = { 0.91, 4.29 },
	}
	local WHEELS = { PonyTrailer = 2, RanchTrailer = 4, HeavyHauler = 4 }

	t.test("the data holds Pony {1.30}, Ranch {0.26, 3.38}, HeavyHauler {0.91, 4.29}", function()
		for id, axles in pairs(WANT) do
			t.eq(TrailerAxleData.For(id), axles, id)
		end
	end)

	t.test("TruckLayout.ForTrailer puts each axle at the bed's middle plus the data, for every tow truck", function()
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			if truck.look.bedLength <= 0 then
				continue
			end
			local lay = TruckLayout.For(truck)
			for id, axles in pairs(WANT) do
				local tl = TruckLayout.ForTrailer(ItemCatalog.GetTrailer(id), lay)
				t.eq(#tl.axleZ, #axles, truck.id .. " + " .. id .. " axle count")
				for i, a in ipairs(axles) do
					t.ok(math.abs(tl.axleZ[i] - tl.bedCenterZ - a) < 1e-9, truck.id .. " + " .. id .. " axle " .. i)
				end
			end
		end
	end)

	t.test("Trailer() builds exactly one wheel pair per axle: Pony 2 wheels, Ranch 4, HeavyHauler 4", function()
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			if truck.look.bedLength <= 0 then
				continue
			end
			local lay = TruckLayout.For(truck)
			for id, count in pairs(WHEELS) do
				local def = ItemCatalog.GetTrailer(id)
				local tl = TruckLayout.ForTrailer(def, lay)
				local model = TruckArt.Build(truck, lay, def, tl)
				local n = 0
				local zs = {}
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "Wheel" and d:GetAttribute("TrailerBody") == true then
						n += 1
						zs[string.format("%.3f", d.CFrame.Z)] = true
					end
				end
				t.eq(n, count, truck.id .. " + " .. id .. " trailer wheels")
				local axleCount = 0
				for _ in pairs(zs) do
					axleCount += 1
				end
				t.eq(axleCount, count // 2, truck.id .. " + " .. id .. " distinct axles")
			end
		end
		local alone = TruckArt.BuildTrailer(ItemCatalog.GetTrailer("RanchTrailer"), ItemCatalog.GetTruck("Pickup"))
		local n = 0
		for _, d in ipairs(alone:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Wheel" then
				n += 1
			end
		end
		t.eq(n, 4, "a Ranch trailer shown alone")
	end)

	t.test("no axle value is typed outside the data: TruckLayout has no tandem gap and no 0.6 of the bed", function()
		local source = fs.readFile("src/ReplicatedStorage/Shared/TruckLayout.luau")
		-- (the trucks' own STYLES keep their tandemGap: this is about trailers)
		local trailerPart = string.sub(source, string.find(source, "local TRAILERS", 1, true))
		t.ok(not string.find(trailerPart, "tandemGap", 1, true), "no trailer tandemGap")
		t.ok(not string.find(trailerPart, "bedLength * 0.6", 1, true), "no 0.6 of the bed")
	end)

	t.expectedFail(
		"wheel X per truck variant matches bbox_check.md within 0.01",
		function()
			local file = "assets/vehicles/t421/bbox_check.md"
			t.ok(fs.isFile(file), file .. " is in the repo")
		end,
		"assets/vehicles/t421/bbox_check.md was not attached to the branch; its per-variant wheel X cannot be compared"
	)
end
