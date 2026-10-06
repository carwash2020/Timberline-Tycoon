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
		-- The night WLD-06 settled on (HANDOFF 6b), lifted from brightness 0.6,
		-- ambient 26,28,46 and outdoor 55,65,105 so a trunk reads at 30 studs.
		local night = EnvironmentData.TimeOfDay(0)
		t.ok(math.abs(night.brightness - 0.8) < 1e-6, "night brightness")
		t.ok(colorDiff(night.ambient, Color3.fromRGB(34, 36, 58)) < 1e-6, "night ambient")
		t.ok(colorDiff(night.outdoorAmbient, Color3.fromRGB(72, 82, 125)) < 1e-6, "night outdoor ambient")
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
		-- 0.68 of noon's since WLD-06 lifted the night's fill (it was 0.55).
		t.ok(lum(night.outdoorAmbient) < lum(noon.outdoorAmbient) * 0.7)
		t.ok(night.exposure < 0)
		t.ok(EnvironmentData.Daylight(1) == 0 and EnvironmentData.Daylight(13) == 1)
		t.ok(EnvironmentData.Daylight(6) > 0 and EnvironmentData.Daylight(6) < 1)
		t.ok(EnvironmentData.Daylight(18.5) > 0 and EnvironmentData.Daylight(18.5) < 1)
	end)

	t.test("at night the Phantom Grove is the darkest place, but never black", function()
		local function lum(c)
			return (c.R + c.G + c.B) / 3
		end
		local grove = EnvironmentData.Blend(23, "grove", "Clear", 0)
		for _, biome in ipairs({ "", "starter", "hills", "snow", "volcano", "sky" }) do
			local other = EnvironmentData.Blend(23, biome, "Clear", 0)
			t.ok(grove.brightness < other.brightness, "darker than '" .. biome .. "'")
			t.ok(lum(grove.outdoorAmbient) < lum(other.outdoorAmbient), "dimmer fill than '" .. biome .. "'")
		end
		-- Never black: its fill (outdoor + ambient) and brightness stay above
		-- where they were before WLD-06 (0.38 and 0.36).
		t.ok(lum(grove.outdoorAmbient) + lum(grove.ambient) >= 0.4, "the grove's night fill")
		t.ok(grove.brightness >= 0.45, "the grove's night brightness")
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
		-- Phase 12 (ATMOS): its red fog (the decay was 180, 80, 60 and the air
		-- 230, 180, 155 before).
		t.ok(colorDiff(volcano.atmosphereDecay, Color3.fromRGB(201, 61, 33)) < 3 / 255, "volcano decay")
		t.ok(colorDiff(volcano.atmosphereColor, Color3.fromRGB(255, 140, 100)) < 3 / 255, "volcano air")
		local grove = EnvironmentData.Blend(13, "grove", "Clear", 0)
		t.ok(colorDiff(grove.tint, Color3.fromRGB(190, 180, 255)) < 2 / 255, "grove tint")
		t.ok(grove.brightness < base.brightness, "grove is darker")
		local sky = EnvironmentData.Blend(13, "sky", "Clear", 0)
		t.ok(math.abs(sky.atmosphereDensity - 0.2) < 1e-6)
		t.ok(math.abs(sky.atmosphereOffset - 0.4) < 1e-6)
		t.ok(math.abs(sky.saturation - (base.saturation + 0.2)) < 1e-6)
		t.ok(math.abs(sky.bloomIntensity - (base.bloomIntensity + 0.1)) < 1e-6, "isles bloom +0.1 (WLD-17)")
		t.ok(math.abs(sky.bloomIntensity - 0.7) < 1e-6)
		t.ok(math.abs(sky.brightness - (base.brightness + 0.3)) < 1e-6)
		local snow = EnvironmentData.Blend(13, "snow", "Clear", 0)
		t.ok(snow.brightness > base.brightness, "snow is bright")
		t.ok(snow.tint.B >= snow.tint.R, "snow is cool")
		-- A volcano night stays a night, just a redder one.
		local volcanoNight = EnvironmentData.Blend(1, "volcano", "Clear", 0)
		t.ok(volcanoNight.atmosphereDecay.R < 0.4)
	end)

	-- Phase 12 (ATMOS): each region's own air. (The preview can't draw
	-- Atmosphere, so these numbers are the whole check before Studio.)
	t.test("region air: the Volcano's red fog, the Snowfields' frost haze, Gloam Hollow's violet swamp mist", function()
		local function lum(c)
			return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
		end
		local country = EnvironmentData.Blend(13, "", "Clear", 0)
		-- The Volcano: its signature, a thick red fog at any hour. Thick, but
		-- a tree still shows 60-100 studs off (0.5-0.6, the Fog weather's
		-- 0.55 give or take), hazy, red-orange toward the sun and deep red
		-- away from it; never black (its light is the hour's).
		for _, h in ipairs({ 1, 4, 6, 9, 13, 17.5, 20, 23 }) do
			local v = EnvironmentData.Blend(h, "volcano", "Clear", 0)
			local here = string.format("the Volcano at %.1f", h)
			t.ok(v.atmosphereDensity >= 0.5 and v.atmosphereDensity <= 0.6, here .. ": " .. v.atmosphereDensity)
			t.ok(v.atmosphereHaze >= 2.5, here .. " is hazy")
			local c, d = v.atmosphereColor, v.atmosphereDecay
			t.ok(c.R > c.G * 1.5 and c.R > c.B * 1.8, here .. ": red-orange air")
			t.ok(d.R > d.G * 2.5 and d.R > d.B * 3, here .. ": a deep red decay")
			t.eq(v.brightness, EnvironmentData.Blend(h, "", "Clear", 0).brightness, here .. ": the hour's light")
		end
		t.ok(
			EnvironmentData.Blend(13, "volcano", "Clear", 0).atmosphereDensity > country.atmosphereDensity + 0.2,
			"the Volcano is much thicker than the country by day"
		)
		-- The Snowfields: a cold, frosty white-blue haze, a modest step up
		-- from the country's air, and never clearer than it at night.
		local snow = EnvironmentData.Blend(13, "snow", "Clear", 0)
		t.ok(
			snow.atmosphereDensity > country.atmosphereDensity + 0.05
				and snow.atmosphereDensity < country.atmosphereDensity + 0.15,
			"a modest frost haze: " .. snow.atmosphereDensity
		)
		t.ok(snow.atmosphereHaze > country.atmosphereHaze + 0.5, "hazier than the country")
		local air = snow.atmosphereColor
		t.ok(air.B >= air.G and air.G >= air.R and lum(air) > 0.8, "pale blue-white air")
		t.ok(snow.atmosphereDecay.B > snow.atmosphereDecay.R, "cold away from the sun")
		for _, h in ipairs({ 1, 6, 23 }) do
			local s = EnvironmentData.Blend(h, "snow", "Clear", 0)
			local open = EnvironmentData.Blend(h, "", "Clear", 0)
			t.ok(s.atmosphereDensity >= open.atmosphereDensity, string.format("the snow's air at %.1f", h))
			if h ~= 6 then -- (dawn is pink everywhere)
				t.ok(s.atmosphereColor.B > s.atmosphereColor.R, string.format("a cold night fog at %.1f", h))
			end
		end
		-- Gloam Hollow: a low violet swamp mist hanging in the hollow at any
		-- hour, mistier and hazier than the country (its light, the darkest
		-- at night and never black, is the test above).
		for _, h in ipairs({ 1, 13, 23 }) do
			local g = EnvironmentData.Blend(h, "grove", "Clear", 0)
			local open = EnvironmentData.Blend(h, "", "Clear", 0)
			local here = string.format("Gloam Hollow at %.1f", h)
			t.ok(g.atmosphereDensity >= open.atmosphereDensity, here .. " is mistier")
			t.ok(g.atmosphereHaze > open.atmosphereHaze + 0.5, here .. " is hazier")
			local c = g.atmosphereColor
			t.ok(c.B > c.R and c.R > c.G, here .. ": violet air")
		end
		t.ok(
			EnvironmentData.Blend(13, "grove", "Clear", 0).atmosphereDensity >= country.atmosphereDensity + 0.15,
			"a real mist by day"
		)
	end)

	-- STY-05: the night mist, LT2's way (phase 12 made it a real fog).
	t.test("night mist: thick from 23:00 to 06:30, lifting through the morning, gone by 09:30", function()
		local w = EnvironmentData.MistWeight
		for _, h in ipairs({ 23, 23.5, 0, 1, 3, 5, 6.4 }) do
			t.ok(math.abs(w(h) - 1) < 1e-9, string.format("full mist at %.1f", h))
		end
		for h = 9.5, 22, 0.25 do
			t.eq(w(h), 0, string.format("no mist at %.2f", h))
		end
		t.ok(w(8) > 0.1 and w(8) < 0.9, "lifting at 08:00")
		t.ok(w(22.5) > 0.1 and w(22.5) < 0.9, "thickening at 22:30")
		-- It only falls through the morning and only rises through the evening.
		for h = 6.5, 9.5, 0.05 do
			t.ok(w(h + 0.05) <= w(h) + 1e-12, "the morning mist only lifts")
		end
		for h = 22, 23, 0.05 do
			t.ok(w(h + 0.05) >= w(h) - 1e-12, "the evening mist only thickens")
		end
		t.ok(math.abs(w(23.9999) - w(0.0001)) < 1e-6, "continuous at midnight")
	end)

	t.test(
		"night fog: a real fog at night in the country, a cool grey-blue, the day untouched, never on the isles",
		function()
			local mist = EnvironmentData.Mist.override.add
			local night = EnvironmentData.Blend(1, "", "Clear", 0)
			local bare = EnvironmentData.TimeOfDay(1)
			t.ok(math.abs(night.atmosphereDensity - (bare.atmosphereDensity + mist.atmosphereDensity)) < 1e-9, "denser")
			t.ok(math.abs(night.atmosphereHaze - (bare.atmosphereHaze + mist.atmosphereHaze)) < 1e-9, "hazier")
			-- A real fog (phase 12, ATMOS; STY-05 added only 0.07 and 0.6, "a
			-- little"): about +0.16 density and +1.5 haze, so nights feel like
			-- nights.
			t.ok(mist.atmosphereDensity >= 0.14 and mist.atmosphereDensity <= 0.18, "a real fog, not a hint")
			t.ok(mist.atmosphereHaze >= 1.2 and mist.atmosphereHaze <= 1.8, "a hazy one")
			-- Still under the Fog weather's 0.55 on a clear night in every biome
			-- but one: the Volcano's red fog is its own, thick at any hour (but
			-- never so thick its trees vanish).
			for _, biome in ipairs({ "", "starter", "hills", "snow", "grove" }) do
				local s = EnvironmentData.Blend(1, biome, "Clear", 0)
				t.ok(s.atmosphereDensity < 0.55, string.format("%s's clear night is thinner than fog", biome))
			end
			local volcanoNight = EnvironmentData.Blend(1, "volcano", "Clear", 0)
			t.ok(volcanoNight.atmosphereDensity <= 0.65, "the Volcano's night stays findable")
			-- Only the air: the night's light is what it was (WLD-06).
			t.eq(night.brightness, bare.brightness)
			t.eq(night.exposure, bare.exposure)
			t.ok(colorDiff(night.outdoorAmbient, bare.outdoorAmbient) < 1e-9, "the night's fill")
			t.ok(colorDiff(night.ambient, bare.ambient) < 1e-9, "the night's ambient")
			-- Its colour: a cool grey-blue, greyer than the night's own blue and
			-- no brighter, so the dark stays dark.
			local function sat(c)
				local _, s = c:ToHSV()
				return s
			end
			local function lum(c)
				return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
			end
			local paint = EnvironmentData.Mist.colour.paint
			for _, k in ipairs({ "atmosphereColor", "atmosphereDecay" }) do
				local c, was = night[k], bare[k]
				t.ok(colorDiff(c, paint[k]) < 1e-9, k .. " is the fog's at 01:00")
				t.ok(c.B > c.G and c.G >= c.R, k .. " is a cool blue-grey")
				t.ok(sat(c) < sat(was), k .. " is greyer than the night's own")
				t.ok(lum(c) <= lum(was) * 1.1, k .. " is no brighter than the night's own")
			end
			-- The colour comes with the dark: full at night, gone by 07:00, when
			-- dawn's own colour lights the morning fog (still thick then).
			t.eq(EnvironmentData.MistColourWeight(1), 1)
			t.eq(EnvironmentData.MistColourWeight(7), 0)
			t.ok(EnvironmentData.MistWeight(7) > 0.9, "still foggy at 07:00")
			local morning = EnvironmentData.Blend(7, "", "Clear", 0)
			local dawn = EnvironmentData.TimeOfDay(7)
			t.ok(colorDiff(morning.atmosphereColor, dawn.atmosphereColor) < 1e-9, "the morning fog keeps dawn's colour")
			t.ok(morning.atmosphereDensity > dawn.atmosphereDensity + 0.1, "the morning fog is still thick")
			for h = 9.5, 22, 0.25 do
				t.eq(EnvironmentData.MistColourWeight(h), 0, string.format("no fog colour at %.2f", h))
			end
			-- The day is exactly as before: a phone's horizon stays as clear.
			for h = 9.5, 22, 0.5 do
				for _, biome in ipairs({ "", "starter", "snow", "volcano" }) do
					local d = maxDiff(
						EnvironmentData.Blend(h, biome, "Clear", 0),
						(function()
							local s = EnvironmentData.TimeOfDay(h)
							local o = EnvironmentData.BiomeOverrides[biome]
							if o then
								EnvironmentData.Apply(s, o, 1)
							end
							EnvironmentData.Clamp(s)
							return s
						end)()
					)
					t.ok(d < 1e-9, string.format("%s at %.1f changed", biome, h))
				end
			end
			-- The isles keep their own air (above the clouds), night or day.
			local isles = EnvironmentData.Blend(1, "sky", "Clear", 0)
			t.ok(math.abs(isles.atmosphereDensity - 0.2) < 1e-9, "the isles' density")
			local skyHaze = (EnvironmentData.BiomeOverrides.sky.add or {}).atmosphereHaze or 0
			t.ok(math.abs(isles.atmosphereHaze - (bare.atmosphereHaze + skyHaze)) < 1e-9, "no mist on the isles")
			-- Fog still sets its own (the mist goes under the weather).
			local fog = EnvironmentData.Blend(1, "", "Fog", 1)
			t.ok(math.abs(fog.atmosphereDensity - 0.55) < 1e-9, "fog's density")
		end
	)

	t.test("lamps still come on at dusk, before the grove wakes", function()
		local GameConfig = t.shared("GameConfig")
		local WorldTime = t.shared("WorldTime")
		-- 18:40 is 18.666...; the first lamp is 18.7 (18:42), then they stagger.
		t.ok(EnvironmentData.LampOnFrom >= 18 + 40 / 60, "not before 18:40")
		t.ok(EnvironmentData.LampOnFrom < GameConfig.NightStartsAt, "before the night")
		t.ok(not WorldTime.IsNight(EnvironmentData.LampOnFrom), "dusk, not night")
		t.ok(WorldTime.IsNight(GameConfig.NightStartsAt))
		t.eq(EnvironmentData.LampOnSpan, 0.7)
		t.eq(EnvironmentData.LampOffFrom, 5.4)
		t.eq(EnvironmentData.LampOffSpan, 0.6)
	end)

	t.test("FogZone: a cave is darker and thicker, a fog pocket only thickens, weight 0 changes nothing", function()
		t.eq(EnvironmentData.FogZoneTag, "FogZone")
		t.eq(EnvironmentData.FogPresetName(nil), "cave")
		t.eq(EnvironmentData.FogPresetName("cave"), "cave")
		t.eq(EnvironmentData.FogPresetName("fog"), "fog")
		t.eq(EnvironmentData.FogPresetName("nope"), "cave")

		local function lum(c)
			return (c.R + c.G + c.B) / 3
		end
		for _, hour in ipairs({ 1, 13, 22.5 }) do
			local open = EnvironmentData.Blend(hour, "", "Clear", 0)
			local none = EnvironmentData.Blend(hour, "", "Clear", 0, "cave", 0)
			t.ok(maxDiff(none, open) < 1e-9, "weight 0 at " .. hour)
			local cave = EnvironmentData.Blend(hour, "", "Clear", 0, "cave", 1)
			local half = EnvironmentData.Blend(hour, "", "Clear", 0, "cave", 0.5)
			inRange(cave, "cave at " .. hour)
			t.ok(cave.atmosphereDensity > open.atmosphereDensity + 0.1, "thicker at " .. hour)
			t.ok(cave.brightness < open.brightness, "darker at " .. hour)
			t.ok(cave.brightness >= 0.35, "not black at " .. hour)
			t.ok(half.brightness > cave.brightness and half.brightness < open.brightness, "half weight")
			local fog = EnvironmentData.Blend(hour, "", "Clear", 0, "fog", 1)
			inRange(fog, "fog pocket at " .. hour)
			t.ok(fog.atmosphereDensity > open.atmosphereDensity + 0.1, "fog pocket thickens")
			t.eq(fog.brightness, open.brightness, "a fog pocket keeps the hour's light")
			-- Unknown preset names are caves.
			local unknown = EnvironmentData.Blend(hour, "", "Clear", 0, "shaft", 1)
			t.ok(maxDiff(unknown, cave) < 1e-9, "unknown preset is a cave")
		end
		-- Inside a cave in the grove at night: darker than the grove, still not black.
		local grove = EnvironmentData.Blend(1, "grove", "Clear", 0)
		local groveCave = EnvironmentData.Blend(1, "grove", "Clear", 0, "cave", 1)
		inRange(groveCave, "grove cave")
		t.ok(groveCave.brightness < grove.brightness)
		t.ok(groveCave.brightness >= 0.45, "the grove's cave stays at the floor")
		t.ok(lum(groveCave.outdoorAmbient) > 0.05)
	end)

	t.test("a FogZone skips the weather and stays inside the density and brightness limits", function()
		local s = EnvironmentData.Blend(0, "grove", "storm", 1, "cave", 1)
		t.ok(s.atmosphereDensity <= 0.65, "density")
		t.ok(s.brightness >= 0.45, "brightness")
		t.ok(math.abs(s.atmosphereDensity - 0.65) < 1e-6, "the density cap is what holds")
		t.ok(math.abs(s.brightness - 0.45) < 1e-6, "the brightness floor is what holds")
		-- The storm would set cloud cover to 0.96. It is not applied in the zone.
		t.ok(s.cloudCover < 0.9, "weather is not stacked inside a FogZone")
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

	t.test("write throttle: 10 Hz with the frames' dt added up", function()
		t.eq(EnvironmentData.WriteEvery, 0.1)
		-- 60 fps: five frames wait, the sixth writes with all six frames' dt
		-- (exactly 100 writes in 10 s: 0.0999... counts).
		local pending, writes, eased = 0, 0, 0
		for _ = 1, 600 do
			local write, by, left = EnvironmentData.WriteTick(pending, 1 / 60)
			pending = left
			if write then
				writes += 1
				eased += by
				t.ok(by >= 0.1 - 1e-9 and by < 0.1 + 1 / 60, "eases by the accumulated dt")
				t.eq(left, 0)
			else
				t.eq(by, 0)
			end
		end
		t.eq(writes, 100)
		t.ok(math.abs(eased + pending - 10) < 1e-6, "no time lost: " .. (eased + pending))
		-- 5 fps: every frame writes, easing by its own (long) dt.
		local write, by = EnvironmentData.WriteTick(0, 0.2)
		t.ok(write and math.abs(by - 0.2) < 1e-9)
		-- A negative dt never runs the clock backwards.
		local w2, _, left2 = EnvironmentData.WriteTick(0.05, -1)
		t.ok(not w2 and left2 == 0.05)
	end)

	t.test("write throttle: a property is rewritten only when it moves past its epsilon", function()
		local moved = EnvironmentData.NumberMoved
		t.ok(moved(nil, 1), "never written: write")
		t.ok(not moved(1, 1), "unchanged: skip")
		t.ok(not moved(1, 1.0009), "under 1e-3: skip")
		t.ok(moved(1, 1.0011), "over 1e-3: write")
		t.ok(moved(1, 0.9989), "either way")
		t.ok(not moved(1, 1.04, 0.05) and moved(1, 1.06, 0.05), "an explicit epsilon")
		local color = EnvironmentData.ColorMoved
		local c = Color3.fromRGB(100, 120, 140)
		t.ok(color(nil, c), "never written: write")
		t.ok(not color(c, Color3.fromRGB(100, 120, 140)), "unchanged: skip")
		t.ok(not color(c, Color3.new(c.R + 0.5 / 255, c.G - 0.5 / 255, c.B)), "under one step: skip")
		t.ok(color(c, Color3.fromRGB(101, 120, 140)), "one step in red: write")
		t.ok(color(c, Color3.fromRGB(100, 120, 139)), "one step in blue: write")
		local clock = EnvironmentData.ClockMoved
		t.ok(clock(nil, 12), "never written: write")
		t.ok(not clock(12, 12.00005), "under the epsilon (a still clock): skip")
		t.ok(clock(12, 12 + 1 / 3000), "a small step of the clock: write")
		t.ok(not clock(23.99995, 0.00004), "across midnight it's 0.00009 h: skip")
		t.ok(clock(23.9999, 0.0002), "across midnight it's 0.0003 h: write")
		t.ok(clock(12, 23), "a ClockOverride jump: write")
		-- Easing toward a still target settles: after a while nothing moves
		-- past an epsilon, so idle frames write nothing.
		local current = EnvironmentData.Blend(13, "", "Clear", 0)
		local target = EnvironmentData.Blend(17.5, "volcano", "Storm", 1)
		local last = EnvironmentData.Lerp(current, current, 0)
		local quietWrites = 0
		for step = 1, 600 do -- 60 s of 10 Hz writes
			current = EnvironmentData.Lerp(current, target, 1 - math.exp(-0.1 / 1))
			for _, k in ipairs(EnvironmentData.NumberKeys) do
				if moved(last[k], current[k]) then
					last[k] = current[k]
					if step > 300 then
						quietWrites += 1
					end
				end
			end
			for _, k in ipairs(EnvironmentData.ColorKeys) do
				if color(last[k], current[k]) then
					last[k] = current[k]
					if step > 300 then
						quietWrites += 1
					end
				end
			end
		end
		t.eq(quietWrites, 0, "no writes once settled")
		local d = maxDiff(last, target)
		t.ok(d < 0.01, "what was written ends near the target: " .. d)
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

	t.test("no grass or flower decor on a homestead pad or its inside edge", function()
		local PlotData = t.shared("PlotData")
		local half = PlotData.Tiers[#PlotData.Tiers].size / 2
		for _, slot in ipairs(PlotData.Slots) do
			for dx = -half - 4, half + 4, 20 do
				for dz = -half - 4, half + 4, 20 do
					t.ok(EnvironmentData.DecorBlocked(slot.X + dx, slot.Y + dz), "decor is blocked on the pad")
				end
			end
		end
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

	t.test("ambient extras stay off on low", function()
		t.eq(EnvironmentData.LeafRate("low"), 0)
		t.eq(EnvironmentData.RiverMotes("low"), 0)
		t.eq(EnvironmentData.ChimneyRate("low"), 0)
		t.ok(EnvironmentData.LeafRate("high") > EnvironmentData.LeafRate("medium"))
		t.ok(EnvironmentData.RiverMotes("medium") > 0)
		t.ok(EnvironmentData.ChimneyRate("high") > 0)
	end)
end
