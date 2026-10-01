--!nocheck
-- TreeArt (Shared/Art): where the HP bar floats. TreeService stores
-- BarHeight as the BarOffset attribute and TreeUI adds it to the Trunk
-- part's centre, so for every wood, in every size class and as an Elder,
-- the bar must land BarAboveGround (7) studs over the ground the tree
-- stands on: just over a player's head, on screen while they chop.
-- And the fall dust's colour (TreeFX): one per home biome, white on the
-- snow, ash grey on the volcano.
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
end
