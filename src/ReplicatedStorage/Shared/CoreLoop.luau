--!strict
-- CoreLoop: which core loop runs (V2_PLAN.md §0). 1 = the v1 loop (whole
-- trees with HP, two logs carried, bed slots, press Sell): live until the
-- flip. 2 = v2 (section trees cut anywhere, wood dragged and carried loose
-- on beds, sold by volume). GameConfig.CoreLoop is the setting; in Studio
-- the workspace attribute "CoreLoop" overrides it, so Connor can try v2
-- without a publish:
--     workspace:SetAttribute("CoreLoop", 2)   -- in edit mode, then Play
-- A live server ignores the attribute (PlaceCheck warns if one was saved
-- into the place). MapBuilder resolves it once at boot and publishes the
-- answer as the workspace attribute "CoreLoopActive", which every server
-- module and client reads through CoreLoop.Active(). Pure but for Active.

local CoreLoop = {}

CoreLoop.Attribute = "CoreLoop"
CoreLoop.ActiveAttribute = "CoreLoopActive"
CoreLoop.Loops = { 1, 2 }

local function valid(n: unknown): boolean
	return n == 1 or n == 2
end

-- The loop to run: `configured` (GameConfig.CoreLoop), or `override` when
-- in Studio and it is 1 or 2. Anything else keeps the configured loop; a
-- broken configured value falls back to 1.
function CoreLoop.Resolve(configured: unknown, override: unknown, isStudio: boolean): number
	if isStudio and valid(override) then
		return override :: number
	end
	if valid(configured) then
		return configured :: number
	end
	return 1
end

-- The loop this server runs, as MapBuilder published it (1 until then).
function CoreLoop.Active(): number
	local n = workspace:GetAttribute(CoreLoop.ActiveAttribute)
	return if valid(n) then n :: number else 1
end

-- Runs `callback` once the server has published the loop (MapBuilder sets
-- CoreLoopActive before it builds, but after its requires, so a client can
-- get here first; if the server's world code fails to load it is never set).
-- Never yields: a controller's Start used to poll for this with task.wait for
-- up to 8 to 120 s (Connor's Studio log: "ChopSawController Start took
-- 8.03s"), held the client's ready handshake, and then, once the wait ran
-- out, decided for the v1 loop for good. Now Start returns at once and the
-- callback runs when the attribute lands, however late; if it is already
-- there, the callback runs right now. `root` is for specs (default workspace).
function CoreLoop.WhenKnown(callback: () -> (), root: Instance?)
	local source: Instance = root or workspace
	if source:GetAttribute(CoreLoop.ActiveAttribute) ~= nil then
		callback()
		return
	end
	local connection: RBXScriptConnection? = nil
	local done = false
	connection = source:GetAttributeChangedSignal(CoreLoop.ActiveAttribute):Connect(function()
		if done or source:GetAttribute(CoreLoop.ActiveAttribute) == nil then
			return
		end
		done = true
		if connection then
			connection:Disconnect()
		end
		callback()
	end)
end

-- True when the v2 loop is running.
function CoreLoop.V2(): boolean
	return CoreLoop.Active() == 2
end

return CoreLoop
