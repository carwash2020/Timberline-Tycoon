--!strict
-- V1Boot: services the v1 lanes add. GameServer calls Start once the core
-- is up. A name with no ModuleScript yet is skipped, so a lane can land
-- its service after this list. SecretService belongs to the map remake.

local V1Boot = {}

V1Boot.Services = { "SecretService" }

function V1Boot.Start(safely: (string, (...any) -> ...any) -> ())
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
end

return V1Boot
