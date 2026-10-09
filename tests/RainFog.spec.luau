--!nocheck
-- Steady rain must thicken the fog once, not every frame. LightingController
-- writes Atmosphere from RainFog.Target; WeatherController only sets wetness.
return function(t)
	local fs = require("@lune/fs")
	local RainFog = t.load("ReplicatedStorage/Shared/RainFog")
	local EnvironmentData = t.load("ReplicatedStorage/Shared/EnvironmentData")
	local Color3 = t.roblox.Color3

	local function commit(baseDensity, baseHaze, baseShift, last)
		local target = RainFog.Target(baseDensity, baseHaze, baseShift)
		if last == nil then
			return target
		end
		return {
			density = if EnvironmentData.NumberMoved(last.density, target.density)
				then target.density
				else last.density,
			haze = if EnvironmentData.NumberMoved(last.haze, target.haze) then target.haze else last.haze,
			shift = if EnvironmentData.ColorMoved(last.shift, target.shift) then target.shift else last.shift,
		}
	end

	t.test("600 frames of steady rain add at most 0.08 density, and clear weather returns to the base", function()
		local baseDensity = 0.32
		local baseHaze = 1.4
		local baseShift = Color3.fromRGB(210, 186, 150)
		RainFog.SetWet(1)
		local live = nil
		for _ = 1, 600 do
			live = commit(baseDensity, baseHaze, baseShift, live)
		end
		t.ok(live.density <= baseDensity + 0.08 + 1e-6, "density " .. live.density)
		t.ok(math.abs(live.density - (baseDensity + 0.08)) < 1e-4, "full wetness is exactly +0.08")
		t.ok(live.haze <= baseHaze + 1.1 + 1e-6, "haze " .. live.haze)
		RainFog.SetWet(0)
		live = commit(baseDensity, baseHaze, baseShift, live)
		t.ok(math.abs(live.density - baseDensity) < 1e-4, "rain off restores density")
		t.ok(math.abs(live.haze - baseHaze) < 1e-4, "rain off restores haze")
		t.ok(math.abs(live.shift.R - baseShift.R) < 1e-4, "rain off restores the colour shift")
	end)

	t.test("WeatherController does not write the sky, and LightingController uses the shared target", function()
		local weather = fs.readFile("src/StarterPlayer/StarterPlayerScripts/WeatherController.luau")
		local lighting = fs.readFile("src/StarterPlayer/StarterPlayerScripts/LightingController.luau")
		t.eq(string.find(weather, "ColorShift_Top", 1, true), nil)
		t.eq(string.find(weather, ".Density", 1, true), nil)
		t.eq(string.find(weather, ".Haze", 1, true), nil)
		t.ok(string.find(weather, "RainFog.SetWet", 1, true))
		t.ok(string.find(lighting, "RainFog.Target", 1, true))
	end)
end
