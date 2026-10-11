--!strict
-- RegionBoot: starts the Bayou and Red Mesa (Lane R) without editing
-- GameServer or V1Boot, like MiningBoot. A missing module is skipped.

local ServerScriptService = game:GetService("ServerScriptService")

local mod = ServerScriptService:FindFirstChild("RegionService")
if mod ~= nil and mod:IsA("ModuleScript") then
	local ok, result = pcall(require, mod)
	if ok and type(result) == "table" and type((result :: any).Init) == "function" then
		local ran, err = pcall((result :: any).Init)
		if not ran then
			warn("[RegionBoot] " .. tostring(err))
		end
	else
		warn("[RegionBoot] RegionService did not load: " .. tostring(result))
	end
end
