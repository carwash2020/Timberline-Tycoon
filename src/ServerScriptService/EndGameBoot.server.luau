--!strict
-- EndGameBoot: starts Gus's Charter (SkyQuestService) and the Sky Forge's
-- end-game actions (AetherService.V1Init -> SkyForgeService) without editing GameServer or V1Boot,
-- like MiningBoot. GameServer makes the remotes; this waits for them and
-- for the town gondola station. A missing piece is skipped with a warning.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 60)
if remotesFolder == nil then
	warn("[EndGameBoot] no Remotes folder")
	return
end

local remotes: { [string]: Instance } = {}
for _, name in ipairs({ "SkyQuest", "ForgeAction", "ForgeOpen", "Notify" }) do
	local r = remotesFolder:WaitForChild(name, 30)
	if r then
		remotes[name] = r
	end
end

local function notify(player: Player, text: string)
	local r = remotes.Notify
	if r and r:IsA("RemoteEvent") then
		r:FireClient(player, text)
	end
end

local function service(name: string): any
	local mod = ServerScriptService:FindFirstChild(name)
	if mod == nil or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[EndGameBoot] " .. name .. " " .. tostring(result))
		return nil
	end
	return result
end

local function start(name: string, fn: () -> ())
	local ok, err = pcall(function(): any
		fn()
		return nil
	end)
	if not ok then
		warn("[EndGameBoot] " .. name .. " " .. tostring(err))
	end
end

-- AetherService.V1Init binds the Sky Forge (SkyForgeService).
local aether = service("AetherService")
if aether and type(aether.V1Init) == "function" then
	start("AetherService.V1Init", function()
		aether.V1Init({ remotes = remotes, notify = notify })
	end)
end

local quest = service("SkyQuestService")
if quest then
	local map = workspace:WaitForChild("TimberlineMap", 60)
	local town = if map then map:WaitForChild("GondolaTown", 60) else nil
	local platform = if town then town:WaitForChild("Platform", 30) else nil
	start("SkyQuestService", function()
		quest.V1Init({
			remotes = remotes,
			notify = notify,
			station = if platform and platform:IsA("BasePart") then platform else nil,
		})
	end)
end
