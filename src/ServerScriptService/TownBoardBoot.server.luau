--!strict
-- TownBoardBoot: starts the town leaderboard board without editing
-- GameServer or V1Boot. A missing module is skipped.

local ServerScriptService = game:GetService("ServerScriptService")

local mod = ServerScriptService:FindFirstChild("TownBoardService")
if mod ~= nil and mod:IsA("ModuleScript") then
	local ok, result = pcall(require, mod)
	if ok and type(result) == "table" and type((result :: any).Init) == "function" then
		local ran, err = pcall((result :: any).Init)
		if not ran then
			warn("[TownBoardBoot] TownBoardService " .. tostring(err))
		end
	end
end
