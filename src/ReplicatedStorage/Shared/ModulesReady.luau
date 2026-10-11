--!strict
-- ModulesReady: PlayerScripts' modules are copied in one by one, so a
-- script that runs early and requires a sibling (which requires its own
-- siblings) can hit one that has not arrived yet, and the errored module is
-- then cached as failed for everyone who requires it. Client.client waits
-- for every module in the folder, then sets this attribute on the folder;
-- the other .client scripts call Wait before their first require.
local ModulesReady = {}

ModulesReady.Attribute = "ModulesReady"
ModulesReady.DefaultWait = 35 -- seconds; Client's own wait is 30

-- True once the folder says its modules are all in. Waits up to `seconds`
-- and returns false on timeout, so a script can warn and go on.
function ModulesReady.Wait(folder: Instance, seconds: number?): boolean
	if folder:GetAttribute(ModulesReady.Attribute) == true then
		return true
	end
	local thread = coroutine.running()
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		task.spawn(thread)
	end
	local connection = folder:GetAttributeChangedSignal(ModulesReady.Attribute):Connect(function()
		if folder:GetAttribute(ModulesReady.Attribute) == true then
			finish()
		end
	end)
	local timer = task.delay(seconds or ModulesReady.DefaultWait, finish)
	-- It may have been set between the first check and the connection.
	if folder:GetAttribute(ModulesReady.Attribute) == true then
		finished = true
	else
		coroutine.yield()
	end
	connection:Disconnect()
	pcall(task.cancel, timer)
	return folder:GetAttribute(ModulesReady.Attribute) == true
end

-- Called by Client once every module is in the folder (or the wait ran out).
function ModulesReady.Mark(folder: Instance)
	folder:SetAttribute(ModulesReady.Attribute, true)
end

return ModulesReady
