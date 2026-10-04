--!nocheck
-- ForestArt (Shared/Art): the sprout (NAT-04). On a stump it's
-- sized to the cut, so its mound of soil, its glowing halo and the seed
-- never hang in mid-air past the stump's edge, for every wood's stump at
-- every size (even an Elder's); without a diameter it keeps the old
-- fixed-size look. And it grows from a seedling to full size, never past
-- it (SproutScale, which ForestUI scales the sprout by).
-- And the seed orb (NAT-12): 0.9 across, a lime-gold trail fading to
-- nothing (two Attachments, 0.35 s), a burst-only sparkle emitter with a
-- soft texture, a quick pop as it lands, and a pooled orb's trail wiped
-- before it flies again, so it never streaks across the map.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame

	-- @lune/roblox has no Trail:Clear; this one notes what the orb was
	-- like when its trail was wiped.
	local clears = {}
	roblox.implementMethod("Trail", "Clear", function(trail)
		local orb = trail.Parent
		table.insert(clears, {
			trail = trail,
			enabled = trail.Enabled,
			at = if orb then orb.CFrame.Position else nil,
		})
	end)

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
	-- cylinder turned upright (Size.Y and Size.Z across), the seed a ball.
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
					for _, name in ipairs({ "Mound", "Halo", "SeedGem" }) do
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
			local heart = sprout:FindFirstChild("SeedGem")
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

	local function near3(a, b)
		return (a - b).Magnitude < 1e-4
	end

	t.test("the seed orb: 0.9 across, a light, a trail and a sparkle emitter, all looks", function()
		local orb = ForestArt.SeedOrb()
		t.eq(orb.Name, "SeedOrbPart")
		t.ok(near3(orb.Size, Vector3.new(0.9, 0.9, 0.9)), "0.9, up from 0.7")
		t.eq(orb.Shape, roblox.Enum.PartType.Ball)
		t.eq(orb.Material, roblox.Enum.Material.Neon)
		t.eq(orb.Color, ForestArt.FreshLime)
		t.eq({ orb.Anchored, orb.CanCollide, orb.CanQuery, orb.CanTouch }, { true, false, false, false })
		t.ok(orb:FindFirstChildOfClass("PointLight") ~= nil, "it glows")
		local trail = orb:FindFirstChild("SeedTrail")
		t.ok(trail and trail:IsA("Trail"), "a Trail")
		local a0, a1 = trail.Attachment0, trail.Attachment1
		t.ok(a0 and a1 and a0 ~= a1, "between two Attachments")
		t.ok(a0:IsA("Attachment") and a0.Parent == orb and a1.Parent == orb, "both on the orb")
		t.ok(near3(a0.CFrame.Position - a1.CFrame.Position, Vector3.new(0, 0.6, 0)), "a ribbon 0.6 wide")
		t.ok(math.abs(trail.Lifetime - 0.35) < 1e-4, "0.35 s long")
		local color = trail.Color.Keypoints
		t.eq(color[1].Value, ForestArt.FreshLime)
		t.eq(color[#color].Value, ForestArt.FreshLime)
		local fade = trail.Transparency.Keypoints
		t.ok(fade[1].Value < 0.5, "bright at the orb")
		t.eq(fade[#fade].Value, 1, "fading to nothing")
		t.eq(trail.LightEmission, 1)
		t.eq(trail.FaceCamera, true)
		t.eq(trail.Enabled, false, "off until it flies (LaunchSeedOrb)")
		local sparkle = orb:FindFirstChild("SeedSparkle")
		t.ok(sparkle and sparkle:IsA("ParticleEmitter"), "a sparkle emitter")
		t.eq(sparkle.Rate, 0, "bursts only")
		t.eq(ForestArt.SeedSparkles, 12)
		t.eq(sparkle.Texture, ForestArt.SeedSparkleTexture)
		t.ok(
			sparkle.Texture ~= "" and sparkle.Texture ~= "rbxasset://textures/particles/sparkles_main.dds",
			"a soft texture, not the default star"
		)
		t.eq(sparkle.LightEmission, 1)
	end)

	t.test("a pooled orb flies again with its trail wiped first, never across the map", function()
		local orb = ForestArt.SeedOrb()
		-- Its last flight ended far away, mid-pop, its trail still on.
		ForestArt.LaunchSeedOrb(orb, CFrame.new(500, 20, -300))
		orb.Size = Vector3.new(1.6, 1.6, 1.6)
		orb.Transparency = 0.7
		local trail = orb:FindFirstChild("SeedTrail")
		t.eq(trail.Enabled, true, "on in flight")
		-- Back to the pool.
		table.clear(clears)
		ForestArt.RestSeedOrb(orb)
		t.eq(trail.Enabled, false, "off in the pool")
		t.eq(#clears, 1, "and wiped")
		t.ok(near3(orb.Size, Vector3.new(0.9, 0.9, 0.9)) and orb.Transparency == 0, "back to how it was made")
		-- It flies again from somewhere else.
		table.clear(clears)
		trail.Enabled = true -- (even if something left it on)
		ForestArt.LaunchSeedOrb(orb, CFrame.new(10, 3, 12))
		t.eq(#clears, 1, "the old trail is wiped")
		t.eq(clears[1].enabled, false, "with the trail off while it moved")
		t.ok(near3(clears[1].at, Vector3.new(10, 3, 12)), "once it's at its new start")
		t.eq(trail.Enabled, true, "then on again, from there")
		t.ok(near3(orb.CFrame.Position, Vector3.new(10, 3, 12)))
		t.ok(near3(orb.Size, Vector3.new(0.9, 0.9, 0.9)) and orb.Transparency == 0, "full size and solid")
	end)

	t.test("as it lands it pops: a quick swell, fading out", function()
		local s0, f0 = ForestArt.SeedOrbPop(0)
		t.eq({ s0, f0 }, { 1, 0 }, "it starts as it flew")
		local s1, f1 = ForestArt.SeedOrbPop(1)
		t.ok(s1 > 1.5, "swells: " .. s1)
		t.eq(f1, 1, "and is gone")
		local _, fLate = ForestArt.SeedOrbPop(1.4)
		t.eq(fLate, 1, "a late frame stays gone")
		local prevS, prevF = 0, -1
		for i = 0, 20 do
			local s, f = ForestArt.SeedOrbPop(i / 20)
			t.ok(s >= prevS and f >= prevF, "only swells and fades")
			prevS, prevF = s, f
		end
		t.ok(ForestArt.SeedPopSeconds > 0 and ForestArt.SeedPopSeconds <= 0.25, "quick")
	end)
end
