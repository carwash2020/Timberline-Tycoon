--!strict
-- V1Boot: services the v1 lanes add. GameServer calls Start once the core
-- is up, and passes the remote table. A name with no ModuleScript yet is
-- skipped, so a lane can land its service after this list. SecretService
-- belongs to the map remake.
-- LogicService is called by name: V1Init gets the LogicSet remote so the
-- settings panel is bound. GameServer still calls Init with the Wire remote.

local V1Boot = {}

V1Boot.Services = { "SecretService" }

local function isModule(child: any): boolean
	if type(child) == "table" and (child :: any).__module ~= nil then
		return true
	end
	local ok, yes = pcall(function()
		return (child :: any):IsA("ModuleScript")
	end)
	return ok and yes == true
end

function V1Boot.Start(safely: (string, (...any) -> ...any) -> (), remotes: { [string]: any }?)
	local parent = script.Parent
	for _, name in ipairs(V1Boot.Services) do
		local child = parent:FindFirstChild(name)
		if isModule(child) then
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
