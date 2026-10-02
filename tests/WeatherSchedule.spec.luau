--!nocheck
-- The weather comes from the clock: every server agrees, the mix is right,
-- fog only lies at night, and nothing ever jumps.
return function(t)
	local WeatherSchedule = t.shared("WeatherSchedule")
	local WorldTime = t.shared("WorldTime")
	local GameConfig = t.shared("GameConfig")

	local SLOT = WeatherSchedule.SlotSeconds
	local BASE = 1790000000 -- an ordinary unix time (2026)

	t.test("deterministic: the same time gives the same weather", function()
		for i = 0, 200 do
			local now = BASE + i * 37.3
			local a, b = WeatherSchedule.At(now), WeatherSchedule.At(now)
			t.eq(a.kind, b.kind)
			t.eq(a.intensity, b.intensity)
		end
		-- A fresh copy of the module (another server) agrees too.
		local other = t.loader():shared("WeatherSchedule")
		for i = 0, 50 do
			local now = BASE + i * 911
			t.eq(other.At(now).kind, WeatherSchedule.At(now).kind)
		end
	end)

	t.test("slots are 10 minutes and the state names its slot", function()
		t.eq(SLOT, 600)
		local s = WeatherSchedule.At(BASE + 125)
		t.ok(s.slotStart <= BASE + 125 and BASE + 125 < s.slotEnd)
		t.eq(s.slotEnd - s.slotStart, SLOT)
		t.eq(s.slotStart % SLOT, 0)
	end)

	t.test("weights are roughly 50/20/15/7/8 over 10,000 slots", function()
		local counts = {}
		local n = 10000
		local first = math.floor(BASE / SLOT)
		for i = 0, n - 1 do
			local kind = WeatherSchedule.SlotKind(first + i)
			counts[kind] = (counts[kind] or 0) + 1
		end
		for _, w in ipairs(WeatherSchedule.Weights) do
			local share = (counts[w.kind] or 0) / n * 100
			t.ok(
				math.abs(share - w.weight) < 2.5,
				string.format("%s: %.1f%% (want about %d%%)", w.kind, share, w.weight)
			)
		end
	end)

	t.test("no fog at midday; fog only between dusk and the morning", function()
		local cycle = GameConfig.DayCycleMinutes * 60
		local fogSeen = 0
		for i = 0, 20000 do
			local now = BASE + i * 17
			local s = WeatherSchedule.At(now)
			if s.kind == "Fog" then
				local clock = WorldTime.ClockTime(now)
				t.ok(WeatherSchedule.FogWindow(clock) > 0, "fog at " .. WorldTime.Format(clock))
				t.ok(clock >= WeatherSchedule.FogFrom or clock <= WeatherSchedule.FogTo, "fog at " .. clock)
				if s.intensity > 0.5 then
					fogSeen += 1
				end
			end
		end
		t.ok(fogSeen > 0, "some fog over ~4 days")
		t.eq(WeatherSchedule.FogWindow(12), 0)
		t.eq(WeatherSchedule.FogWindow(13), 0)
		t.eq(WeatherSchedule.FogWindow(2), 1)
		-- Midday on a fog slot reads as clear.
		local first = math.floor(BASE / SLOT)
		for i = 0, 400 do
			local index = first + i
			if WeatherSchedule.SlotKind(index) == "Fog" then
				for k = 0, 600, 5 do
					local now = index * SLOT + k
					local clock = WorldTime.ClockTime(now)
					if clock > 10 and clock < 19 then
						t.ok(WeatherSchedule.At(now).kind ~= "Fog", "fog at " .. clock)
					end
				end
			end
		end
		t.ok(cycle > 0)
	end)

	t.test("intensity is continuous: no jumps within a weather, ~0 when the weather changes", function()
		local prev = WeatherSchedule.At(BASE)
		local step = 1
		for i = 1, 6 * 3600 do
			local now = BASE + i * step
			local s = WeatherSchedule.At(now)
			t.ok(s.intensity >= 0 and s.intensity <= 1, "intensity in 0..1")
			if s.kind == prev.kind then
				t.ok(
					math.abs(s.intensity - prev.intensity) < 0.06,
					string.format("%s jumped %.3f -> %.3f at %d", s.kind, prev.intensity, s.intensity, now)
				)
			elseif s.kind ~= "Clear" or prev.kind ~= "Clear" then
				-- Changing weather: whatever was showing has faded out, and
				-- the new one starts from nothing.
				local outgoing = if prev.kind == "Clear" then 0 else prev.intensity
				local incoming = if s.kind == "Clear" then 0 else s.intensity
				t.ok(outgoing < 0.06, string.format("%s ended at %.3f", prev.kind, prev.intensity))
				t.ok(incoming < 0.06, string.format("%s started at %.3f", s.kind, s.intensity))
			end
			prev = s
		end
	end)

	t.test("eases in and out over 40 s, but two slots of the same weather join up", function()
		local first = math.floor(BASE / SLOT)
		local checkedEase, checkedJoin = false, false
		for i = 1, 600 do
			local index = first + i
			local kind = WeatherSchedule.SlotKind(index)
			if kind ~= "Fog" and kind ~= "Clear" then
				local start = index * SLOT
				local mid = WeatherSchedule.At(start + SLOT / 2)
				t.eq(mid.intensity, 1)
				if WeatherSchedule.SlotKind(index - 1) ~= kind then
					t.eq(WeatherSchedule.At(start).intensity, 0)
					t.ok(WeatherSchedule.At(start + 20).intensity > 0.3)
					t.eq(WeatherSchedule.At(start + 40).intensity, 1)
					checkedEase = true
				else
					t.eq(WeatherSchedule.At(start).intensity, 1)
					checkedJoin = true
				end
			end
		end
		t.ok(checkedEase and checkedJoin)
	end)

	t.test("each biome reads the weather its own way", function()
		local function s(kind)
			return { kind = kind, intensity = 0.7, slotStart = 0, slotEnd = 600 }
		end
		t.eq(WeatherSchedule.ForBiome(s("Rain"), "snow").kind, "Snow")
		t.eq(WeatherSchedule.ForBiome(s("Storm"), "snow").kind, "Blizzard")
		t.eq(WeatherSchedule.ForBiome(s("Storm"), "volcano").kind, "Ashfall")
		t.eq(WeatherSchedule.ForBiome(s("Rain"), "volcano").kind, "Rain")
		t.eq(WeatherSchedule.ForBiome(s("Rain"), "sky").kind, "Wind")
		t.eq(WeatherSchedule.ForBiome(s("Fog"), "sky").kind, "Clear")
		t.eq(WeatherSchedule.ForBiome(s("Storm"), "starter").kind, "Storm")
		t.eq(WeatherSchedule.ForBiome(s("Rain"), "").kind, "Rain")
		t.eq(WeatherSchedule.ForBiome(s("Rain"), nil).kind, "Rain")
		t.eq(WeatherSchedule.ForBiome(s("Rain"), "snow").intensity, 0.7)
	end)

	t.test("wind: calm when clear, a gale in a storm, smooth in between", function()
		t.eq(WeatherSchedule.Wind("Storm", 0), WeatherSchedule.Wind("Clear", 1))
		t.ok(WeatherSchedule.Wind("Storm", 1) > WeatherSchedule.Wind("Rain", 1))
		t.ok(WeatherSchedule.Wind("Fog", 1) < WeatherSchedule.Wind("Clear", 1))
		t.ok(WeatherSchedule.Wind("Nonsense", 1) == WeatherSchedule.Wind("Clear", 1))
		t.ok(WeatherSchedule.IsWet("Rain") and WeatherSchedule.IsWet("Ashfall"))
		t.ok(not WeatherSchedule.IsWet("Fog") and not WeatherSchedule.IsWet("Wind"))
	end)

	t.test("the forecast lists the next slots", function()
		local f = WeatherSchedule.Forecast(BASE, 3)
		t.eq(#f, 3)
		local index = math.floor(BASE / SLOT)
		t.eq(f[1].slotStart, (index + 1) * SLOT)
		t.eq(f[1].kind, WeatherSchedule.SlotKind(index + 1))
	end)

	t.test("map emitters (the waterfall) run at their BaseRate, half on low quality", function()
		local rate = WeatherSchedule.MapEmitterRate
		t.eq(rate(60, 1), 60, "high: the full rate")
		t.eq(rate(60, 0.5), 30, "low: half")
		t.eq(rate(8, 0.5), 4)
		t.eq(rate(60, 2), 60, "never above the base")
		t.eq(rate(nil, 1), nil, "no attribute: leave the emitter alone")
		t.eq(rate("60", 1), nil)
		t.eq(rate(-5, 1), nil)
		t.eq(rate(0 / 0, 1), nil)
		t.eq(rate(math.huge, 1), nil)
	end)
end
