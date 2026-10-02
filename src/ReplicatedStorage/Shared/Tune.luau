--!strict
-- Tune: feel-tuning without code edits (V2_PLAN.md §0). Tune.Get(key) is
-- GameConfig[key], unless running in Studio with a numeric workspace
-- attribute "Tune_<key>", e.g. in the command bar during Play:
--     workspace:SetAttribute("Tune_DragResponsiveness", 45)
-- so drag force, bed friction and cut numbers can be tried live. A live
-- server ignores the attributes (PlaceCheck warns about saved ones).

local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.GameConfig)

local Tune = {}

Tune.Prefix = "Tune_"

-- The value for `key`: `configured`, or `override` in Studio when both
-- are numbers (a finite override). Pure.
function Tune.Resolve(configured: unknown, override: unknown, isStudio: boolean): unknown
	if isStudio and type(override) == "number" and type(configured) == "number" then
		if override == override and override ~= math.huge and override ~= -math.huge then
			return override
		end
	end
	return configured
end

function Tune.Get(key: string): any
	local configured = (GameConfig :: any)[key]
	local override = workspace:GetAttribute(Tune.Prefix .. key)
	return Tune.Resolve(configured, override, RunService:IsStudio())
end

return Tune
