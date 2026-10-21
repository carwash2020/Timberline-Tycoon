--!strict
-- ColorMapGuard (T402): a MaterialVariant whose ColorMap fails to load would
-- draw the engine's blurry stock texture. This preloads each variant's
-- ColorMap (it yields: MapBuilder runs it on a thread of its own, nothing
-- waits on it) and clears one that failed or timed out, so the terrain keeps
-- its flat colour (MaterialSetup's table). Lives in Shared so the server's
-- build path itself never names the content service (BuildBudget.spec).

local ColorMapGuard = {}

-- Returns how many ColorMaps it cleared.
function ColorMapGuard.Run(materialService: any, provider: any?): number
	local cleared = 0
	local ok, err = pcall(function()
		local service = provider or game:GetService("ContentProvider")
		local fetch = (Enum :: any).AssetFetchStatus
		for _, variant in ipairs(materialService:GetChildren()) do
			if variant:IsA("MaterialVariant") and variant.ColorMap ~= "" then
				local bad = false
				local loaded, why = pcall(function()
					service:PreloadAsync({ variant }, function(_: string, status: any)
						if status == fetch.Failure or status == fetch.TimedOut then
							bad = true
						end
					end)
				end)
				if bad or not loaded then
					variant.ColorMap = ""
					cleared += 1
					warn(
						string.format(
							"[ColorMapGuard] %s's ColorMap did not load (%s): its flat colour stays",
							variant.Name,
							if loaded then "asset failed" else tostring(why)
						)
					)
				end
			end
		end
	end)
	if not ok then
		warn("[ColorMapGuard] could not check the ground's ColorMaps: " .. tostring(err))
	end
	return cleared
end

return ColorMapGuard
