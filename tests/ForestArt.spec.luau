--!nocheck
-- ForestArt (Shared/Art): the Heartseed sprout (NAT-04). On a stump it's
-- sized to the cut, so its mound of soil, its glowing halo and the seed
-- never hang in mid-air past the stump's edge, for every wood's stump at
-- every size (even an Elder's); without a diameter it keeps the old
-- fixed-size look. And it grows from a seedling to full size, never past
-- it (SproutScale, which ForestUI scales the sprout by).
return function(t)
	local ForestArt = t.load("ReplicatedStorage/Shared/Art/ForestArt")
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local WoodData = t.shared("WoodData")
	local TreeLogic = t.shared("TreeLogic")
	local ForestLogic = t.shared("ForestLogic")

	local MARGIN = 0.05 -- studs past the stump's edge that still read as on it

	local function scales(def)
		local out = {}
		for _, size in ipairs(TreeLogic.Sizes) do
			table.insert(out, { name = size.name, scale = size.scale })
		end
		table.insert(out, { name = "elder", scale = ForestLogic.ElderSize(def).scale })
		return out
	end

	-- How far a round part reaches from the sprout's axis (x = z = 0),
	-- sideways: its centre's distance out plus its radius across. The
	-- Mound is an upright ellipsoid (Size.X and Size.Z across), the Halo a
	-- cylinder turned upright (Size.Y and Size.Z across), the Heartseed a ball.
	local function reach(part)
		local p = part.CFrame.Position
		local across = if part.Name == "Halo"
			then math.max(part.Size.Y, part.Size.Z)
			else math.max(part.Size.X, part.Size.Z)
		return math.sqrt(p.X * p.X + p.Z * p.Z) + across / 2
	end

	local function near(a, b)
		return math.abs(a - b) < 1e-4
	end

	t.test("on a stump, the mound and halo stay on the cut, for every wood at every size", function()
		local smallest = math.huge
		for _, def in ipairs(WoodData.All()) do
			for _, size in ipairs(scales(def)) do
				local stump = TreeArt.Stump(def, 7, size.scale)
				local d = stump.PrimaryPart.Size.Y
				smallest = math.min(smallest, d)
				for _, seed in ipairs({ 1, 99 }) do
					local sprout = ForestArt.Sprout(def, seed, d)
					local label = string.format("%s %s (cut %.2f)", def.id, size.name, d)
					t.eq(sprout.PrimaryPart and sprout.PrimaryPart.Name, "Mound")
					local mound, halo = sprout:FindFirstChild("Mound"), sprout:FindFirstChild("Halo")
					t.ok(near(mound.Size.X, d * 0.8) and near(mound.Size.Z, d * 0.8), label .. ": mound 0.8 D across")
					t.ok(near(mound.Size.Y, 0.35), label .. ": mound 0.35 tall")
					t.ok(near(halo.Size.Y, d * 0.95), label .. ": halo 0.95 D across")
					for _, name in ipairs({ "Mound", "Halo", "Heartseed" }) do
						local part = sprout:FindFirstChild(name)
						t.ok(
							reach(part) <= d / 2 + MARGIN,
							string.format("%s: the %s reaches %.2f past a %.2f radius", label, name, reach(part), d / 2)
						)
					end
					-- Nothing of it sinks under the stump's cut (ground at y = 0)
					-- by more than the mound's own seat in it.
					t.ok(mound.CFrame.Position.Y - mound.Size.Y / 2 > -0.1, label .. ": the mound sits on the cut")
					t.ok(
						halo.CFrame.Position.Y - halo.Size.X / 2 >= 0.07,
						label .. ": the halo is over the cut's rings"
					)
				end
			end
		end
		t.ok(smallest < 1.2, "a small birch's cut is covered (" .. smallest .. ")")
	end)

	t.test("without a stump's diameter (or a bad one) a sprout keeps the old look", function()
		local oak = WoodData.Get("oak")
		local NONE = {} -- (ipairs stops at a nil, so nil goes in as this)
		local tried = 0
		for _, given in ipairs({ NONE, 0, -1, 0 / 0, math.huge }) do
			tried += 1
			local d = if given == NONE then nil else given
			local sprout = ForestArt.Sprout(oak, 5, d)
			local mound = sprout:FindFirstChild("Mound")
			local halo = sprout:FindFirstChild("Halo")
			local heart = sprout:FindFirstChild("Heartseed")
			t.eq(sprout.PrimaryPart, mound)
			t.ok(near(mound.Size.X, 2.6) and near(mound.Size.Y, 0.7), "the old 2.6 mound for " .. tostring(d))
			t.ok(near(halo.Size.Y, 3.6) and near(halo.Size.X, 0.05), "the old 3.6 halo for " .. tostring(d))
			t.ok(near(heart.Size.X, 0.55), "the old seed")
			local at = heart.CFrame.Position
			t.ok(near(at.X, 0.5) and near(at.Y, 0.42) and near(at.Z, -0.3), "where it was")
		end
		t.eq(tried, 5)
	end)

	t.test("it grows from a seedling (0.25) to full size (1) and never past it", function()
		t.eq(ForestArt.SproutScale(0), 0.25)
		t.eq(ForestArt.SproutScale(1), 1)
		local prev = -1
		for i = -10, 30 do
			local u = i / 20 -- -0.5 to 1.5: a late frame overshoots the end
			local scale = ForestArt.SproutScale(u)
			t.ok(scale >= 0.25 and scale <= 1, "u " .. u .. ": " .. scale)
			t.ok(scale >= prev, "it only grows")
			prev = scale
		end
		t.ok(ForestArt.SproutScale(0.5) > 0.7, "eases out: most of the growth comes early")
	end)
end
