--!nocheck
-- TreeArt (Shared/Art): where the HP bar floats. TreeService stores
-- BarHeight as the BarOffset attribute and TreeUI adds it to the Trunk
-- part's centre, so for every wood, in every size class and as an Elder,
-- the bar must land BarAboveGround (7) studs over the ground the tree
-- stands on: just over a player's head, on screen while they chop.
-- And the fall dust's colour (TreeFX): one per home biome, white on the
-- snow, ash grey on the volcano.
-- And stumps (NAT-03): no root flare sticks up past the cut, for every
-- wood at every size and as an Elder; a stump's flares are shorter
-- (0.35-0.5 diameters) and a standing tree's are as they were.
-- And part budgets (NAT-17): trees are most of the world's parts, so a
-- pine stays at or under 44 and a frostwood at or under 60, in every size
-- class and for any seed, with their tiers and snow caps still there.
return function(t)
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local WoodData = t.shared("WoodData")
	local TreeLogic = t.shared("TreeLogic")
	local ForestLogic = t.shared("ForestLogic")

	local function scales(def)
		local out = {}
		for _, size in ipairs(TreeLogic.Sizes) do
			table.insert(out, { name = size.name, scale = size.scale })
		end
		table.insert(out, { name = "elder", scale = ForestLogic.ElderSize(def).scale })
		return out
	end

	t.test("the bar sits 7 studs above the ground", function()
		t.eq(TreeArt.BarAboveGround, 7)
	end)

	t.test("every size class is covered, with the Elder bigger than large", function()
		local names = {}
		for _, size in ipairs(TreeLogic.Sizes) do
			table.insert(names, size.scale)
		end
		t.eq(names, { 0.82, 1, 1.22 })
		local oak = WoodData.Get("oak")
		t.ok(ForestLogic.ElderSize(oak).scale > 1.22, "an Elder is bigger than a large tree")
	end)

	t.test("every wood's bar lands 7 studs over the ground, in every size", function()
		for _, def in ipairs(WoodData.All()) do
			for _, size in ipairs(scales(def)) do
				for _, seed in ipairs({ 1, 777 }) do
					local model = TreeArt.Build(def, seed, size.scale)
					local trunk = model.PrimaryPart
					t.ok(trunk and trunk.Name == "Trunk", def.id .. ": the PrimaryPart is the Trunk")
					-- Built with the ground at y = 0; TreeUI adds BarOffset to the
					-- trunk part's centre (StudsOffsetWorldSpace). CFrames are
					-- 32-bit floats, hence the tolerance.
					local barY = trunk.CFrame.Position.Y + TreeArt.BarHeight(def, size.scale)
					t.ok(
						math.abs(barY - 7) < 1e-3,
						string.format("%s %s: the bar is %.2f studs up, not 7", def.id, size.name, barY)
					)
					-- The trunk stands on the ground, so its centre is half its length up.
					t.ok(
						math.abs(trunk.CFrame.Position.Y - trunk.Size.X / 2) < 1e-3,
						def.id .. ": the trunk starts at the ground"
					)
				end
			end
		end
	end)

	t.test("every wood's fall dust has its biome's colour", function()
		local earth = TreeArt.DustColor(WoodData.Get("oak"))
		local seen = {}
		for _, def in ipairs(WoodData.All()) do
			local c = TreeArt.DustColor(def)
			t.ok(typeof(c) == "Color3", def.id .. " has a dust colour")
			if def.biome ~= "starter" then
				t.ok(c ~= earth, def.id .. " (" .. def.biome .. ") has its own dust, not the forest's")
			end
			seen[def.biome] = c
		end
		local snow = seen.snow
		t.ok(snow and snow.R > 0.9 and snow.G > 0.9 and snow.B > 0.9, "snow dust is white")
		local ash = seen.volcano
		t.ok(ash, "the volcano has a wood")
		local hi, lo = math.max(ash.R, ash.G, ash.B), math.min(ash.R, ash.G, ash.B)
		t.ok(hi - lo < 0.06 and hi < 0.6, "volcano dust is ash grey")
		-- An unknown biome falls back to the forest's earth.
		t.eq(TreeArt.DustColor({ id = "x", biome = "nowhere" }), earth)
	end)

	-- The highest and lowest world Y of a part's box (in Lune, read
	-- part.CFrame, never part.Position).
	local function topOf(part)
		local cf, size = part.CFrame, part.Size
		local half = (
			math.abs(cf.XVector.Y) * size.X
			+ math.abs(cf.YVector.Y) * size.Y
			+ math.abs(cf.ZVector.Y) * size.Z
		) / 2
		return cf.Position.Y + half, cf.Position.Y - half
	end

	local function named(model, name)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == name then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("no stump's root flare sticks up past its cut, at any size", function()
		for _, def in ipairs(WoodData.All()) do
			for _, scale in ipairs({ 0.82, 1, 1.22, ForestLogic.ElderSize(def).scale }) do
				for _, seed in ipairs({ 1, 2, 3, 42, 777, 9001 }) do
					local stump = TreeArt.Stump(def, seed, scale)
					local body = named(stump, "Stump")[1]
					t.ok(body and stump.PrimaryPart == body, def.id .. ": the stump's PrimaryPart is Stump")
					local cut = topOf(body)
					local roots = named(stump, "Root")
					t.eq(#roots, 3, def.id .. ": three root flares")
					for _, root in ipairs(roots) do
						local top = topOf(root)
						t.ok(
							top < cut,
							string.format(
								"%s x%.2f seed %d: a root flare tops out at %.2f, over the cut at %.2f",
								def.id,
								scale,
								seed,
								top,
								cut
							)
						)
					end
				end
			end
		end
	end)

	t.test("the scales checked are the size classes and the Elder", function()
		t.eq(ForestLogic.ElderSize(WoodData.Get("oak")).scale, 1.7)
	end)

	t.test("a stump's flares reach 0.35-0.5 diameters out and still show", function()
		for _, def in ipairs(WoodData.All()) do
			for _, scale in ipairs({ 0.82, 1, 1.7 }) do
				for _, seed in ipairs({ 1, 5, 42, 777 }) do
					local stump = TreeArt.Stump(def, seed, scale)
					local body = named(stump, "Stump")[1]
					local D = body.Size.Y -- the cylinder's axis is its X
					local _, ground = topOf(body)
					for _, root in ipairs(named(stump, "Root")) do
						-- 0.77 x a standing tree's 0.45-0.65: 0.35-0.50 to two places.
						local out = root.Size.Z / D
						t.ok(
							out >= 0.3465 - 1e-4 and out <= 0.5005 + 1e-4,
							def.id .. ": a flare " .. out .. " diameters long"
						)
						local top, bottom = topOf(root)
						t.ok(top > ground + 0.1, def.id .. ": a flare shows above the ground")
						t.ok(math.abs(bottom - (ground - 0.05)) < 1e-3, def.id .. ": a flare sits on the ground")
					end
				end
			end
		end
	end)

	t.test("a standing tree's root flares are as they were", function()
		for _, def in ipairs(WoodData.All()) do
			for _, seed in ipairs({ 1, 777 }) do
				local tree = TreeArt.Build(def, seed, 1)
				local roots = named(tree, "Root")
				if def.id ~= "palmwood" then -- a palm has none
					t.ok(#roots >= 3, def.id .. " has root flares")
				end
				local D = tree.PrimaryPart.Size.Y
				for _, root in ipairs(roots) do
					local tall, out = root.Size.Y / D, root.Size.Z / D
					t.ok(
						tall >= 0.55 - 1e-3 and tall <= 0.8 + 1e-3,
						def.id .. ": a flare " .. tall .. " diameters tall"
					)
					t.ok(out >= 0.45 - 1e-3 and out <= 0.65 + 1e-3, def.id .. ": a flare " .. out .. " diameters long")
				end
			end
		end
	end)

	t.test("the bar is no longer up in the canopy", function()
		-- The old bar floated 18-34 studs up, off screen while chopping.
		for _, def in ipairs(WoodData.All()) do
			for _, size in ipairs(scales(def)) do
				local model = TreeArt.Build(def, 1, size.scale)
				local barY = model.PrimaryPart.CFrame.Position.Y + TreeArt.BarHeight(def, size.scale)
				t.ok(barY < 8, def.id .. " " .. size.name .. ": the bar is too high")
			end
		end
	end)

	local function partCount(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		return n
	end

	local BUDGET = { pine = 44, frostwood = 60 }
	local SEEDS = { 1, 2, 3, 11, 42, 777, 9001 }

	t.test("pines and frostwoods stay inside their part budgets", function()
		local line = {}
		for _, def in ipairs(WoodData.All()) do
			local most = 0
			for _, size in ipairs(scales(def)) do
				for _, seed in ipairs(SEEDS) do
					local n = partCount(TreeArt.Build(def, seed, size.scale))
					most = math.max(most, n)
					local cap = BUDGET[def.id]
					if cap then
						t.ok(
							n <= cap,
							string.format(
								"%s %s seed %d: %d parts, over its budget of %d",
								def.id,
								size.name,
								seed,
								n,
								cap
							)
						)
					end
				end
			end
			table.insert(line, def.id .. " " .. most)
		end
		print("    tree parts (most per wood): " .. table.concat(line, ", "))
	end)

	t.test("a conifer keeps four five-sided tiers, and a frostwood's caps top only the upper two", function()
		for _, id in ipairs({ "pine", "frostwood" }) do
			local def = WoodData.Get(id)
			for _, scale in ipairs({ 0.82, 1, 1.22 }) do
				for _, seed in ipairs({ 1, 42, 777 }) do
					local tree = TreeArt.Build(def, seed, scale)
					local tiers = {}
					local caps = {}
					for _, child in ipairs(tree:GetChildren()) do
						if child:IsA("Model") and child.Name == "Tier" then
							table.insert(tiers, child)
						elseif child:IsA("BasePart") and child.Name == "Facet" then
							table.insert(caps, child)
						end
					end
					t.eq(#tiers, TreeArt.ConiferTiers, id .. ": four Tier models")
					for _, tier in ipairs(tiers) do
						-- Two wedges a face (Kit.triangle), every one a clickable Facet.
						t.eq(partCount(tier), TreeArt.ConiferSides * 2, id .. ": a five-sided tier")
						for _, p in ipairs(tier:GetChildren()) do
							t.ok(p.Name == "Facet" and p.CanQuery, id .. ": tier parts are clickable Facets")
						end
					end
					if id == "frostwood" then
						t.eq(#caps, TreeArt.SnowCappedTiers * TreeArt.SnowCapSides * 2, "two four-sided caps")
						-- The third tier from the bottom starts 0.92 trunk heights up.
						local thirdTier = 0.92 * def.trunkHeight * scale
						for _, cap in ipairs(caps) do
							t.ok(cap.Material == t.roblox.Enum.Material.Snow, "a cap is snow")
							t.ok(cap.CFrame.Position.Y > thirdTier, "a snow cap sits on one of the top two tiers")
						end
					else
						t.eq(#caps, 0, "a pine has no snow")
					end
				end
			end
		end
	end)
end
