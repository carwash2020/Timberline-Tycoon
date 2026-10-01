--!nocheck
-- The world's light, decoration and wildlife rules (Shared/EnvironmentData).
return function(t)
	local EnvironmentData = t.shared("EnvironmentData")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local Color3 = t.roblox.Color3

	local function colorDiff(a, b)
		return math.max(math.abs(a.R - b.R), math.abs(a.G - b.G), math.abs(a.B - b.B))
	end

	local function maxDiff(a, b)
		local worst, which = 0, ""
		for _, k in ipairs(EnvironmentData.NumberKeys) do
			local r = EnvironmentData.Ranges[k]
			local d = math.abs(a[k] - b[k]) / (r[2] - r[1])
			if d > worst then
				worst, which = d, k
			end
		end
		for _, k in ipairs(EnvironmentData.ColorKeys) do
			local d = colorDiff(a[k], b[k])
			if d > worst then
				worst, which = d, k
			end
		end
		return worst, which
	end

	local function inRange(s, label)
		for _, k in ipairs(EnvironmentData.NumberKeys) do
			local r = EnvironmentData.Ranges[k]
			t.ok(type(s[k]) == "number", label .. ": " .. k .. " is a number")
			t.ok(s[k] >= r[1] and s[k] <= r[2], string.format("%s: %s = %s out of range", label, k, tostring(s[k])))
		end
		for _, k in ipairs(EnvironmentData.ColorKeys) do
			local c = s[k]
			t.ok(typeof(c) == "Color3", label .. ": " .. k .. " is a Color3")
			t.ok(c.R >= 0 and c.R <= 1 and c.G >= 0 and c.G <= 1 and c.B >= 0 and c.B <= 1, label .. ": " .. k)
		end
	end

	local BIOMES = { "", "starter", "hills", "snow", "volcano", "grove", "sky", "nowhere" }
	local WEATHERS = { "Clear", "Cloudy", "Rain", "Storm", "Fog", "Snow", "Blizzard", "Ashfall", "Wind" }

	t.test("keyframes are in order and the day matches them at their hours", function()
		local prev = -1
		for _, f in ipairs(EnvironmentData.Keyframes) do
			t.ok(f.hour > prev, "keyframes sorted")
			prev = f.hour
			local s = EnvironmentData.TimeOfDay(f.hour)
			local d, k = maxDiff(s, f.state)
			t.ok(d < 1e-6, string.format("%s at %.2f differs in %s", f.name, f.hour, k))
		end
		-- The brief's starting values.
		t.ok(math.abs(EnvironmentData.TimeOfDay(13).brightness - 2.6) < 1e-6)
		t.ok(math.abs(EnvironmentData.TimeOfDay(6).brightness - 1.8) < 1e-6)
		t.ok(math.abs(EnvironmentData.TimeOfDay(17.5).brightness - 2.2) < 1e-6)
		t.ok(math.abs(EnvironmentData.TimeOfDay(0).brightness - 0.6) < 1e-6)
	end)

	t.test("continuous through the whole day, midnight included", function()
		local step = 0.01
		local prev = EnvironmentData.Blend(23.9, "", "Clear", 0)
		local h = 23.9 + step
		while h < 48 do
			local s = EnvironmentData.Blend(h % 24, "", "Clear", 0)
			local d, k = maxDiff(prev, s)
			t.ok(d < 0.03, string.format("jump of %.3f in %s at %.2f", d, k, h % 24))
			prev = s
			h += step
		end
		local justBefore = EnvironmentData.Blend(23.9999, "starter", "Rain", 0.5)
		local justAfter = EnvironmentData.Blend(0.0001, "starter", "Rain", 0.5)
		t.ok(maxDiff(justBefore, justAfter) < 1e-3)
	end)

	t.test("every hour, biome and weather stays inside the legal ranges", function()
		for _, biome in ipairs(BIOMES) do
			for _, weather in ipairs(WEATHERS) do
				for hour = 0, 24, 0.75 do
					for _, intensity in ipairs({ 0, 0.5, 1 }) do
						inRange(
							EnvironmentData.Blend(hour, biome, weather, intensity),
							string.format("%s/%s/%.2f", biome, weather, hour)
						)
					end
				end
			end
		end
		inRange(EnvironmentData.Blend(12, nil, nil, nil), "nil inputs")
		inRange(EnvironmentData.Blend(12, "sky", "Storm", 7), "intensity clamps")
	end)

	t.test("nights are dark; days are bright", function()
		local night = EnvironmentData.Blend(1, "", "Clear", 0)
		local noon = EnvironmentData.Blend(13, "", "Clear", 0)
		t.ok(night.brightness < noon.brightness * 0.4)
		local function lum(c)
			return (c.R + c.G + c.B) / 3
		end
		t.ok(lum(night.outdoorAmbient) < lum(noon.outdoorAmbient) * 0.6)
		t.ok(night.exposure < 0)
		t.ok(EnvironmentData.Daylight(1) == 0 and EnvironmentData.Daylight(13) == 1)
		t.ok(EnvironmentData.Daylight(6) > 0 and EnvironmentData.Daylight(6) < 1)
		t.ok(EnvironmentData.Daylight(18.5) > 0 and EnvironmentData.Daylight(18.5) < 1)
	end)

	t.test("weather overrides apply with their intensity", function()
		local clear = EnvironmentData.Blend(13, "", "Clear", 1)
		local rain = EnvironmentData.Blend(13, "", "Rain", 1)
		local halfRain = EnvironmentData.Blend(13, "", "Rain", 0.5)
		local noRain = EnvironmentData.Blend(13, "", "Rain", 0)
		t.ok(math.abs(rain.brightness - clear.brightness * 0.7) < 1e-6, "rain x0.7")
		t.ok(math.abs(rain.atmosphereDensity - (clear.atmosphereDensity + 0.1)) < 1e-6, "rain +0.1 density")
		t.ok(math.abs(rain.saturation - (clear.saturation - 0.1)) < 1e-6, "rain -0.1 saturation")
		t.ok(math.abs(halfRain.brightness - clear.brightness * 0.85) < 1e-6, "half the effect at 0.5")
		t.ok(maxDiff(noRain, clear) < 1e-9, "no effect at 0")
		local storm = EnvironmentData.Blend(13, "", "Storm", 1)
		t.ok(math.abs(storm.brightness - clear.brightness * 0.5) < 1e-6, "storm x0.5")
		t.ok(math.abs(storm.atmosphereDensity - (clear.atmosphereDensity + 0.15)) < 1e-6, "storm +0.15")
		t.ok(storm.cloudCover > 0.9)
		local fog = EnvironmentData.Blend(2, "", "Fog", 1)
		t.ok(math.abs(fog.atmosphereDensity - 0.55) < 1e-6)
		t.ok(math.abs(fog.atmosphereOffset - 0.05) < 1e-6)
		t.ok(math.abs(fog.atmosphereHaze - 3) < 1e-6)
	end)

	t.test("biome overrides: volcano, grove, isles, snow", function()
		local base = EnvironmentData.Blend(13, "", "Clear", 0)
		local volcano = EnvironmentData.Blend(13, "volcano", "Clear", 0)
		t.ok(colorDiff(volcano.tint, Color3.fromRGB(255, 215, 190)) < 2 / 255, "volcano tint")
		t.ok(colorDiff(volcano.atmosphereDecay, Color3.fromRGB(180, 80, 60)) < 3 / 255, "volcano decay")
		local grove = EnvironmentData.Blend(13, "grove", "Clear", 0)
		t.ok(colorDiff(grove.tint, Color3.fromRGB(190, 180, 255)) < 2 / 255, "grove tint")
		t.ok(grove.brightness < base.brightness, "grove is darker")
		local sky = EnvironmentData.Blend(13, "sky", "Clear", 0)
		t.ok(math.abs(sky.atmosphereDensity - 0.2) < 1e-6)
		t.ok(math.abs(sky.atmosphereOffset - 0.4) < 1e-6)
		t.ok(math.abs(sky.saturation - (base.saturation + 0.2)) < 1e-6)
		t.ok(math.abs(sky.bloomIntensity - 0.9) < 1e-6)
		t.ok(math.abs(sky.brightness - (base.brightness + 0.3)) < 1e-6)
		local snow = EnvironmentData.Blend(13, "snow", "Clear", 0)
		t.ok(snow.brightness > base.brightness, "snow is bright")
		t.ok(snow.tint.B >= snow.tint.R, "snow is cool")
		-- A volcano night stays a night, just a redder one.
		local volcanoNight = EnvironmentData.Blend(1, "volcano", "Clear", 0)
		t.ok(volcanoNight.atmosphereDecay.R < 0.4)
	end)

	t.test("Lerp and Apply leave their inputs alone", function()
		local a = EnvironmentData.TimeOfDay(6)
		local b = EnvironmentData.TimeOfDay(13)
		local before = a.brightness
		local mid = EnvironmentData.Lerp(a, b, 0.5)
		t.eq(a.brightness, before)
		t.ok(math.abs(mid.brightness - (a.brightness + b.brightness) / 2) < 1e-9)
		local s = EnvironmentData.TimeOfDay(13)
		local copy = EnvironmentData.Lerp(s, s, 0)
		EnvironmentData.Apply(copy, { mul = { brightness = 0.5 } }, 1)
		t.ok(math.abs(copy.brightness - s.brightness * 0.5) < 1e-9)
		t.ok(EnvironmentData.TimeOfDay(13).brightness == s.brightness, "keyframes untouched")
	end)

	t.test("vitality tiers", function()
		t.eq(EnvironmentData.VitalityTier(10), "Thinning")
		t.eq(EnvironmentData.VitalityTier(60), "Healthy")
		t.eq(EnvironmentData.VitalityTier(80), "Thriving")
		t.eq(EnvironmentData.VitalityTier(95), "OldGrowth")
		t.ok(EnvironmentData.LifeFactor(95) > EnvironmentData.LifeFactor(80))
		t.ok(EnvironmentData.LifeFactor(80) > EnvironmentData.LifeFactor(60))
		t.ok(EnvironmentData.LifeFactor(60) > EnvironmentData.LifeFactor(10))
	end)

	local function vitality(v)
		return function()
			return v
		end
	end

	-- Cells around the Starter Forest, the Hills edge and the countryside.
	local CELLS = {}
	for cx = -4, 3 do
		for cz = -5, 1 do
			table.insert(CELLS, { cx, cz })
		end
	end
	for cx = -9, -5 do
		for cz = -1, 3 do
			table.insert(CELLS, { cx, cz })
		end
	end

	t.test("decoration is deterministic and never on roads, water or building zones", function()
		local total = 0
		for _, c in ipairs(CELLS) do
			local a = EnvironmentData.DecorSpots(c[1], c[2], vitality(60))
			local b = EnvironmentData.DecorSpots(c[1], c[2], vitality(60))
			t.eq(#a, #b)
			for i, s in ipairs(a) do
				t.eq(s.x, b[i].x)
				t.eq(s.kind, b[i].kind)
				t.eq(s.variant, b[i].variant)
				t.ok(s.x >= c[1] * 64 and s.x < (c[1] + 1) * 64, "inside its cell")
				t.ok(TerrainGen.RoadClearance(s.x, s.z) >= 2.5, "off the road")
				if s.kind == "LilyPad" then
					t.eq(s.y, TerrainGen.WaterLevelAt(s.x, s.z), "lily pads float on the water")
				else
					t.ok(TerrainGen.WaterLevelAt(s.x, s.z) == nil, "on dry land")
					t.ok(math.abs(s.y - TerrainGen.HeightAt(s.x, s.z)) < 1, "on the ground")
				end
				t.ok(WorldLayout.FlatWeight(s.x, s.z) <= 0, "not in town or the plots")
				local row = EnvironmentData.Decor[s.biome][s.index]
				t.eq(row.kind, s.kind)
				t.ok(row.enabled ~= false, "only kinds that can be built")
				t.ok(s.variant >= 1 and s.variant <= row.variants)
				total += 1
			end
		end
		t.ok(total > 60, "the meadows aren't empty: " .. total)
	end)

	t.test("the water's edge: reeds on the bank, lily pads on still water, nothing on the river", function()
		local kinds = {}
		local function scan(cx0, cx1, cz0, cz1)
			for cx = cx0, cx1 do
				for cz = cz0, cz1 do
					for _, s in ipairs(EnvironmentData.DecorSpots(cx, cz, vitality(60))) do
						kinds[s.kind] = (kinds[s.kind] or 0) + 1
						local water = TerrainGen.WaterLevelAt(s.x, s.z)
						local _, distance, kind = EnvironmentData.NearestWater(s.x, s.z)
						if s.kind == "LilyPad" then
							t.ok(water ~= nil and kind ~= "river", "lily pads only on the lake and the pond")
						elseif s.kind == "Reeds" or s.kind == "Cattails" then
							t.ok(water == nil and distance < 6, "reeds and cattails on the bank")
						else
							t.ok(water == nil, s.kind .. " stays out of the water")
						end
					end
				end
			end
		end
		-- The lake (centre (-830, -190), radius 135) and the pond (78, -182).
		scan(-16, -10, -6, 0)
		scan(0, 2, -4, -2)
		t.ok((kinds.LilyPad or 0) > 0, "some lily pads")
		t.ok((kinds.Reeds or 0) + (kinds.Cattails or 0) > 0, "some reeds")
	end)

	t.test("thriving groves grow more flowers; rocks don't care", function()
		local function count(v, kind)
			local n = 0
			for _, c in ipairs(CELLS) do
				for _, s in ipairs(EnvironmentData.DecorSpots(c[1], c[2], vitality(v))) do
					if s.kind == kind then
						n += 1
					end
				end
			end
			return n
		end
		local thin, healthy, thriving = count(20, "Flowers"), count(60, "Flowers"), count(85, "Flowers")
		t.ok(thriving > healthy and healthy > thin, string.format("flowers %d / %d / %d", thin, healthy, thriving))
		t.eq(count(20, "Rock"), count(85, "Rock"))
	end)

	t.test("critters: butterflies by day, fireflies by night, wisps only in the grove", function()
		local function plan(over)
			local ctx = {
				biomeId = "starter",
				daylight = 1,
				weather = "Clear",
				intensity = 1,
				vitality = 60,
				nearPond = false,
				nearWater = false,
			}
			for k, v in pairs(over or {}) do
				ctx[k] = v
			end
			local out = {}
			for _, w in ipairs(EnvironmentData.CritterPlan(ctx)) do
				out[w.kind] = w.count
			end
			return out
		end
		local day = plan()
		t.ok(day.Butterfly and day.Butterfly > 0)
		t.ok(day.Fireflies == nil)
		t.ok(day.Flock == 1)
		local night = plan({ daylight = 0 })
		t.ok(night.Fireflies and night.Fireflies > 0)
		t.ok(night.Butterfly == nil)
		t.ok(plan({ weather = "Rain" }).Butterfly == nil, "rain sends butterflies home")
		t.ok((plan({ vitality = 85 }).Butterfly or 0) > day.Butterfly, "thriving groves have more")
		t.ok((plan({ vitality = 85 }).Deer or 0) > (day.Deer or 0), "and more deer")
		t.ok(plan({ biomeId = "grove", daylight = 0 }).Wisp ~= nil)
		t.ok(plan({ biomeId = "grove", daylight = 1 }).Wisp == nil)
		t.ok(plan({ biomeId = "starter", daylight = 0 }).Wisp == nil)
		t.ok(plan({ biomeId = "volcano" }).EmberSprite ~= nil)
		t.ok(plan({ nearPond = true }).Duck ~= nil)
		t.ok(plan({ nearWater = true }).Fish ~= nil)
		t.ok(plan({ biomeId = "sky" }).Flock == nil)
		-- Every plan's first kinds fit in the budget.
		for _, over in ipairs({ {}, { vitality = 95, nearPond = true, nearWater = true }, { daylight = 0 } }) do
			local ctx = plan(over)
			local cost = 0
			for kind, n in pairs(ctx) do
				t.ok(EnvironmentData.CritterCost[kind], "a cost for " .. kind)
				cost += EnvironmentData.CritterCost[kind] * n
			end
			t.ok(cost > 0)
		end
	end)

	t.test("nearest water finds the pond, the lake and the river", function()
		local pond = WorldLayout.Pond
		local p, d, kind = EnvironmentData.NearestWater(pond.x + pond.radius + 10, pond.z)
		t.eq(kind, "pond")
		t.ok(math.abs(d - 10) < 1e-6)
		t.ok(TerrainGen.WaterLevelAt(p.X, p.Z) ~= nil, "the point is on the water")
		local lake = WorldLayout.Lake
		local _, _, lakeKind = EnvironmentData.NearestWater(lake.x, lake.z - lake.radius - 20)
		t.eq(lakeKind, "lake")
		local r = WorldLayout.River.points[3]
		local rp, rd, riverKind = EnvironmentData.NearestWater(r.X + 40, r.Y)
		t.eq(riverKind, "river")
		t.ok(rd < 40)
		t.eq(rp.Y, WorldLayout.LakeLevel)
	end)
end
