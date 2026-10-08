--!nocheck
-- NatureArt: part counts, decoration flags, and the rain preview field.
return function(t)
	local NatureArt = t.load("ReplicatedStorage/Shared/Art/NatureArt")
	local Vector3 = t.roblox.Vector3
	local Color3 = t.roblox.Color3
	local Enum = t.roblox.Enum

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
		local NatureData = t.load("ReplicatedStorage/Shared/NatureData")
		t.eq(#NatureArt.RockShapes, 6, "six families")
		for _, shape in ipairs(NatureArt.RockShapes) do
			t.eq(NatureData.PartCost[shape], NatureArt.Parts[shape], shape .. " cost")
			for _, sizeName in ipairs(NatureArt.Sizes) do
				for _, look in ipairs(NatureArt.RockLooks) do
					local n = partsOf(NatureArt.Build(shape, 1, sizeName, look))
					t.eq(n, NatureArt.Parts[shape], shape .. " " .. sizeName .. " " .. look)
					t.ok(n >= 3 and n <= 8, shape .. " " .. sizeName)
				end
			end
		end
	end)

	local function worldBox(part)
		local hs = part.Size * 0.5
		local cf = part.CFrame
		local minX, minY, minZ = math.huge, math.huge, math.huge
		local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local w = cf:PointToWorldSpace(Vector3.new(hs.X * sx, hs.Y * sy, hs.Z * sz))
					minX = math.min(minX, w.X)
					minY = math.min(minY, w.Y)
					minZ = math.min(minZ, w.Z)
					maxX = math.max(maxX, w.X)
					maxY = math.max(maxY, w.Y)
					maxZ = math.max(maxZ, w.Z)
				end
			end
		end
		return minX, minY, minZ, maxX, maxY, maxZ
	end

	local function overlaps(a, b)
		local a0, a1, a2, a3, a4, a5 = worldBox(a)
		local b0, b1, b2, b3, b4, b5 = worldBox(b)
		return a0 <= b3 and a3 >= b0 and a1 <= b4 and a4 >= b1 and a2 <= b5 and a5 >= b2
	end

	local function blockParts(model)
		local list = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	t.test("no rock block is taller than 1.5 times its width", function()
		local function check(model, label)
			for _, p in ipairs(blockParts(model)) do
				local width = math.min(p.Size.X, p.Size.Z)
				t.ok(p.Size.Y <= width * 1.5 + 1e-4, label .. " " .. p.Name .. " " .. p.Size.Y .. " / " .. width)
			end
		end
		for _, shape in ipairs(NatureArt.RockShapes) do
			for _, sizeName in ipairs(NatureArt.Sizes) do
				check(NatureArt.Build(shape, 4, sizeName, "meadow"), shape .. " " .. sizeName)
				check(
					NatureArt.OreRock(shape, sizeName, Color3.fromRGB(40, 40, 40), Enum.Material.Slate, false),
					"ore " .. shape
				)
			end
		end
	end)

	t.test("every family tilts 8 to 20 degrees and sinks 20 to 30 percent", function()
		for seed = 1, 24 do
			local shape = NatureArt.RockShapes[(seed % #NatureArt.RockShapes) + 1]
			local model = NatureArt.Build(shape, seed, "mid", "snow")
			local tilt = model:GetAttribute("TiltDeg")
			local sink = model:GetAttribute("Sink")
			t.ok(tilt >= 8 and tilt <= 20, "tilt " .. tostring(tilt))
			t.ok(sink >= 0.2 - 1e-6 and sink <= 0.3 + 1e-6, "sink " .. tostring(sink))
			local core = model:FindFirstChild("Core")
			t.ok(core, shape .. " has a Core")
			local deg = math.deg(math.acos(math.clamp(core.CFrame.UpVector.Y, -1, 1)))
			t.ok(math.abs(deg - tilt) < 0.6, shape .. " leans " .. deg)
			local minY, maxY = math.huge, -math.huge
			for _, p in ipairs(blockParts(model)) do
				local _, y0, _, _, y1 = worldBox(p)
				minY = math.min(minY, y0)
				maxY = math.max(maxY, y1)
			end
			local buried = (0 - minY) / (maxY - minY)
			t.ok(buried >= 0.19 and buried <= 0.31, shape .. " buried " .. buried)
		end
	end)

	t.test("an ore rock is at most 8 parts, with flush vein wedges and a blank OreId", function()
		for _, shape in ipairs(NatureArt.RockShapes) do
			for _, sizeName in ipairs(NatureArt.Sizes) do
				for _, glow in ipairs({ false, true }) do
					local model =
						NatureArt.OreRock(shape, sizeName, Color3.fromRGB(180, 90, 40), Enum.Material.Metal, glow)
					local parts = blockParts(model)
					t.ok(#parts <= 8, shape .. " " .. sizeName .. " parts " .. #parts)
					t.eq(model:GetAttribute("OreId"), "", "OreId is blank for lane M")
					t.eq(model:HasTag("OreRockArt"), true, "OreRockArt tag")
					local veins, lights, neon = 0, 0, 0
					local body = {}
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") and d.Name == "Vein" then
							veins += 1
							t.eq(d.ClassName, "WedgePart", "a vein is a wedge")
							local thin = math.min(d.Size.X, d.Size.Y, d.Size.Z)
							local thick = math.max(d.Size.X, d.Size.Y, d.Size.Z)
							t.ok(thin <= thick * 0.45, "a vein is thin")
							if d.Material == Enum.Material.Neon then
								neon += 1
							end
						elseif d:IsA("BasePart") then
							table.insert(body, d)
							t.ok(d.Material ~= Enum.Material.Neon, "the host rock stays stone")
						elseif d:IsA("PointLight") then
							lights += 1
							t.eq(d.Shadows, false, "ore light casts no shadow")
						end
					end
					t.ok(veins == 2 or veins == 3, shape .. " veins " .. veins)
					for _, vein in ipairs(parts) do
						if vein.Name == "Vein" then
							local hit = false
							local _, _, _, _, veinTop = worldBox(vein)
							local rockTop = -math.huge
							for _, host in ipairs(body) do
								if overlaps(vein, host) then
									hit = true
								end
								local _, _, _, _, top = worldBox(host)
								rockTop = math.max(rockTop, top)
							end
							t.ok(hit, shape .. " vein sits in a face")
							t.ok(veinTop <= rockTop + 0.35, shape .. " vein is not stacked on top")
						end
					end
					if glow then
						t.eq(lights, 1, "glow adds one light")
						t.ok(neon >= 1, "glow veins are neon")
					else
						t.eq(lights, 0, "a dull ore has no light")
						t.eq(neon, 0, "a dull ore is not neon")
					end
				end
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
