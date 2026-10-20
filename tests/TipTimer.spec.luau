--!nocheck
-- Timed tips: 3 s visible, a 0.4 s fade, 60 s before the same message returns.
return function(t)
	local TipTimer = t.shared("TipTimer")
	local fs = require("@lune/fs")

	t.test("the numbers", function()
		t.eq(TipTimer.VisibleSeconds, 3)
		t.eq(TipTimer.FadeSeconds, 0.4)
		t.eq(TipTimer.CooldownSeconds, 60)
	end)

	t.test("a thick-face tip fades after 3 s and is gone by 3.4 s", function()
		local s = TipTimer.New()
		local vis, a = TipTimer.Show(s, "thick", 10)
		t.ok(vis and a == 1, "shows at once")
		vis, a = TipTimer.Show(s, "thick", 12.9)
		t.ok(vis and a == 1, "full until 3 s")
		vis, a = TipTimer.Show(s, "thick", 13.2)
		t.ok(vis and a > 0 and a < 1, "fading")
		vis = TipTimer.Show(s, "thick", 13.4)
		t.ok(not vis, "gone")
		vis = TipTimer.Show(s, "thick", 69.9)
		t.ok(not vis, "not back before 60 s")
		vis = TipTimer.Show(s, "thick", 70.1)
		t.ok(vis, "back once 60 s have passed since it started")
	end)

	t.test("a message is allowed once per 60 s, each key on its own", function()
		local s = TipTimer.New()
		t.ok(TipTimer.Allow(s, "far", 0))
		t.ok(not TipTimer.Allow(s, "far", 59.9))
		t.ok(TipTimer.Allow(s, "tooHard", 1), "another key is separate")
		t.ok(TipTimer.Allow(s, "far", 60))
	end)

	t.test("ten swings on a thick tree: every tip is up at most 3.5 s and none repeats within 60 s", function()
		local s = TipTimer.New()
		local shownAt = { thick = {}, far = {}, tooHard = {}, none = {} }
		local visibleSince = nil
		local longest = 0
		local clock = 0
		local function tick()
			clock += 0.1
			local vis = TipTimer.Show(s, "thick", clock)
			if vis and not visibleSince then
				visibleSince = clock
				table.insert(shownAt.thick, clock)
			elseif not vis and visibleSince then
				longest = math.max(longest, clock - visibleSince)
				visibleSince = nil
			end
		end
		-- A swing every 0.6 s; the axe stays on the thick face and the
		-- pointing refresh ticks every 0.1 s. Every swing is refused.
		for swing = 1, 10 do
			while clock < swing * 0.6 do
				tick()
			end
			for _, key in ipairs({ "none", "far", "tooHard" }) do
				if TipTimer.Allow(s, key, clock) then
					table.insert(shownAt[key], clock)
				end
			end
		end
		-- Keep swinging for two more minutes.
		while clock < 130 do
			tick()
			for _, key in ipairs({ "none", "far", "tooHard" }) do
				if TipTimer.Allow(s, key, clock) then
					table.insert(shownAt[key], clock)
				end
			end
		end
		t.ok(longest <= 3.5, "a tip stayed up " .. tostring(longest) .. " s")
		t.eq(#shownAt.far, 3)
		for key, times in pairs(shownAt) do
			for i = 2, #times do
				t.ok(times[i] - times[i - 1] >= 60 - 1e-6, key .. " repeated inside 60 s")
			end
		end
		t.eq(#shownAt.thick, 3, "the thick tip: now, then once a minute")
	end)

	t.test("the controllers and HUD use it; the tooHard hint line stays", function()
		local dir = "src/StarterPlayer/StarterPlayerScripts/"
		local cut = fs.readFile(dir .. "CutController.luau")
		local chop = fs.readFile(dir .. "ChopController.luau")
		local hud = fs.readFile(dir .. "HUD.luau")
		for _, src in ipairs({ cut, chop }) do
			t.ok(not string.find(src, "HUD.Toast(", 1, true), "a warning still goes through plain HUD.Toast")
			t.ok(string.find(src, "HUD.TimedToast(", 1, true), "no timed toast")
		end
		t.ok(string.find(hud, "function HUD.TimedToast(", 1, true))
		t.ok(string.find(hud, "TipTimer.Show(", 1, true), "the thick hint is not timed")
		t.ok(string.find(hud, "tooHard = pointingHard", 1, true), "the tooHard hint line stays")
	end)
end
