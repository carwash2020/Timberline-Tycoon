--!strict
-- V1Boot: services the v1 lanes add. GameServer calls Start once the core
-- is up, and passes the remote table. A name with no ModuleScript yet is
-- skipped, so a lane can land its service after this list. SecretService
-- belongs to the map remake.
-- The end game starts here too (it was EndGameBoot): AetherService.V1Init
-- binds the Sky Forge (SkyForgeService) and SkyQuestService.V1Init starts
-- Gus's Charter once the town gondola station is built.
-- LogicService is called by name: V1Init gets the LogicSet remote so the
-- settings panel is bound. GameServer still calls Init with the Wire remote.

local V1Boot = {}

V1Boot.Services = { "SecretService" }

-- The specs swap these: how a task is spawned, and how the town gondola
-- station's platform is found (nil when the map has none).
V1Boot.Spawn = nil :: ((() -> ()) -> ())?
V1Boot.WaitStation = nil :: (() -> BasePart?)?

local function waitTownStation(): BasePart?
	local map = workspace:WaitForChild("TimberlineMap", 60)
	local town = if map then map:WaitForChild("GondolaTown", 60) else nil
	local platform = if town then town:WaitForChild("Platform", 30) else nil
	return if platform and platform:IsA("BasePart") then platform else nil
end

local function isModule(child: any): boolean
	if type(child) == "table" and (child :: any).__module ~= nil then
		return true
	end
	local ok, yes = pcall(function()
		return (child :: any):IsA("ModuleScript")
	end)
	return ok and yes == true
end

-- The Sky Forge's end-game actions and Gus's Charter. A remote that is not
-- in the table is skipped, as a missing service is.
function V1Boot.StartEndGame(parent: any, safely: (string, (...any) -> ...any) -> (), remotes: { [string]: any }?)
	if
		type(remotes) ~= "table"
		or (remotes.SkyQuest == nil and remotes.ForgeAction == nil and remotes.ForgeOpen == nil)
	then
		return
	end
	local notifyRemote = remotes.Notify
	local function notify(player: Player, text: string)
		if notifyRemote ~= nil then
			notifyRemote:FireClient(player, text)
		end
	end
	local aether = parent:FindFirstChild("AetherService")
	if isModule(aether) then
		safely("AetherService.V1Init", function()
			local mod = require(aether :: any) :: any
			if type(mod.V1Init) == "function" then
				mod.V1Init({ remotes = remotes, notify = notify })
			end
		end)
	end
	local quest = parent:FindFirstChild("SkyQuestService")
	if isModule(quest) then
		local function go()
			safely("SkyQuestService", function()
				local mod = require(quest :: any) :: any
				if type(mod.V1Init) == "function" then
					local station = if V1Boot.WaitStation then V1Boot.WaitStation() else waitTownStation()
					mod.V1Init({ remotes = remotes, notify = notify, station = station })
				end
			end)
		end
		-- The station is built by MapBuilder, which may still be running.
		if V1Boot.Spawn then
			V1Boot.Spawn(go)
		else
			task.spawn(go)
		end
	end
end

function V1Boot.Start(safely: (string, (...any) -> ...any) -> (), remotes: { [string]: any }?)
	local parent = script.Parent
	for _, name in ipairs(V1Boot.Services) do
		local child = parent:FindFirstChild(name)
		if child ~= nil and child:IsA("ModuleScript") then
			safely(name, function()
				local mod = require(child) :: any
				if type(mod.Init) == "function" then
					mod.Init()
				elseif type(mod.Start) == "function" then
					mod.Start()
				end
			end)
		end
	end
	V1Boot.StartEndGame(parent, safely, remotes)
	local logic = parent:FindFirstChild("LogicService")
	if isModule(logic) then
		safely("LogicService", function()
			local mod = require(logic :: any) :: any
			if type(mod.V1Init) == "function" then
				local logicSet = if type(remotes) == "table" then remotes.LogicSet else nil
				mod.V1Init({ remotes = { LogicSet = logicSet } })
			end
		end)
	end
end

return V1Boot
