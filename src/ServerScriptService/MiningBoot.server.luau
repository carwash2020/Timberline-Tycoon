--!strict
-- MiningBoot: starts mining and crafting without editing GameServer.
-- A missing module is skipped.

local ServerScriptService = game:GetService("ServerScriptService")

local function boot(name: string)
	local mod = ServerScriptService:FindFirstChild(name)
	if mod == nil or not mod:IsA("ModuleScript") then
		return
	end
	local ok, result = pcall(require, mod)
	if not ok or type(result) ~= "table" or type(result.Init) ~= "function" then
		return
	end
	local ran, err = pcall(result.Init)
	if not ran then
		warn("[MiningBoot] " .. name .. " " .. tostring(err))
	end
end

boot("MiningService")
boot("CraftingService")
