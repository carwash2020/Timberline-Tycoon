--!nocheck
-- Cosmetic client loops follow QualityBudgets.CosmeticHz (every frame on
-- high, slower on medium, nearly off on low). Driving, chopping, carrying
-- and dragging do not: those change what the game does, not how it looks.
return function(t)
	local fs = require("@lune/fs")
	local SPS = "src/StarterPlayer/StarterPlayerScripts/"

	local function source(name: string): string
		return fs.readFile(SPS .. name .. ".luau")
	end

	local function usesBudget(name: string): boolean
		local code = source(name)
		return string.find(code, "CosmeticHz", 1, true) ~= nil or string.find(code, "CosmeticDue", 1, true) ~= nil
	end

	local COSMETIC = {
		"WindSway",
		"AmbientLife",
		"CanopyFade",
		"TownFX",
		"WeatherController",
		"LightingController",
		"ForestFiller",
		"VehicleFX",
		"AmbientSound",
		"CameraShake",
		"TreeFX",
		"WoodFX",
		"ForestUI",
		"NPCController",
		"TreeCosmetics",
		"LuxFX",
		"TownMarkers",
		"LifeFX",
	}

	-- These loops decide gameplay. Throttling them would change the outcome.
	local GAMEPLAY = {
		"VehicleController",
		"ChopController",
		"CarryController",
		"DragController",
		"CutController",
		"GondolaController",
	}

	t.test("each cosmetic loop reads the quality budget", function()
		for _, name in ipairs(COSMETIC) do
			t.ok(usesBudget(name), name .. " is quality-aware")
		end
	end)

	t.test("gameplay loops are not throttled by the cosmetic budget", function()
		for _, name in ipairs(GAMEPLAY) do
			t.eq(usesBudget(name), false, name)
		end
	end)
end
