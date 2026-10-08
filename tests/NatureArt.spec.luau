--!nocheck
-- NatureArt: part counts, decoration flags, and the rain preview field.
return function(t)
	local NatureArt = t.load("ReplicatedStorage/Shared/Art/NatureArt")

	local function partsOf(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
				t.eq(d.Anchored, true, d.Name .. " anchored")
				t.eq(d.CanCollide, false, d.Name .. " no collide")
				t.eq(d.CanQuery, false, d.Name .. " no query")
				t.eq(d.CanTouch, false, d.Name .. " no touch")
				t.eq(d.CastShadow, false, d.Name .. " no shadow")
			end
			if d:IsA("PointLight") then
				t.eq(d.Shadows, false, "a nature light casts no shadow")
			end
		end
		return n
	end

	t.test("each built piece matches its part budget", function()
		local total, kinds = 0, 0
		for kind, want in pairs(NatureArt.Parts) do
			local model = NatureArt.Build(kind, 3, "mid")
			local n = partsOf(model)
			t.eq(n, want, kind .. " parts")
			t.ok(n >= 2 and n <= 8, kind .. " is 2 to 8 parts")
			total += n
			kinds += 1
		end
		t.ok(total / kinds <= 8, "average piece is 8 parts or fewer")
	end)

	t.test("rocks stay in the rock budget at every size", function()
		for _, shape in ipairs(NatureArt.RockShapes) do
			for _, sizeName in ipairs(NatureArt.Sizes) do
				local n = partsOf(NatureArt.Build(shape, 1, sizeName))
				t.ok(n >= 3 and n <= 8, shape .. " " .. sizeName)
			end
		end
	end)

	t.test("rain streaks are thin parts and a shelter skips the middle", function()
		local blobs = NatureArt.RainField("blobs", "high", false)
		local streaks = NatureArt.RainField("streaks", "high", false)
		local low = NatureArt.RainField("streaks", "low", false)
		local shop = NatureArt.RainField("streaks", "high", true)
		local function named(model, name)
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d.Name == name then
					n += 1
				end
			end
			return n
		end
		t.ok(named(blobs, "Blob") > named(streaks, "Blob"), "blobs are the old puff")
		t.eq(named(streaks, "Blob"), 0, "streaks are not blobs")
		t.ok(named(streaks, "Streak") > named(low, "Streak"), "low uses fewer streaks")
		t.ok(named(streaks, "Splash") > 0, "open ground has splashes")
		t.eq(named(shop, "Splash"), 0, "a shelter has no splashes")
		t.ok(named(shop, "Streak") < named(streaks, "Streak"), "a roof cuts the streaks under it")
	end)
end
