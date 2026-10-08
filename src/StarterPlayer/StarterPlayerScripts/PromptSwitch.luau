--!strict
-- PromptSwitch: the one place that flips ProximityPromptService.Enabled on
-- this client (rules in Shared/PromptGate). The dialogue box, a held piece,
-- the build placer and the wire tool each Hold under their own name and
-- Release it when they end; prompts are on whenever nobody holds them.
--
--   PromptSwitch.Hold("dialogue")     world prompts off
--   PromptSwitch.Release("dialogue")  that hold ends (prompts back if it was the last)
--
-- While anything is held a once-a-second watchdog runs. It puts the engine's
-- switch right if something else moved it, and warns (once per hold) about a
-- hold that has lasted over a minute, naming it: that is a stuck prompt
-- switch, and the line to look for in the output is "[PromptSwitch]".

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PromptGate = require(ReplicatedStorage.Shared.PromptGate)

local PromptSwitch = {}

local STALE_SECONDS = 60

local gate = PromptGate.New(function(enabled: boolean)
	ProximityPromptService.Enabled = enabled
end)
local watching = false
local warned: { [string]: boolean } = {}

local function watch()
	if watching then
		return
	end
	watching = true
	task.spawn(function()
		while not PromptGate.Open(gate) do
			task.wait(1)
			if PromptGate.Heal(gate, ProximityPromptService.Enabled) then
				warn("[PromptSwitch] something else switched world prompts; put right")
			end
			for _, line in ipairs(PromptGate.Stale(gate, os.clock(), STALE_SECONDS)) do
				if not warned[line] then
					warned[line] = true
					warn("[PromptSwitch] world prompts have been held off a long time: " .. line)
				end
			end
		end
		table.clear(warned)
		watching = false
	end)
end

function PromptSwitch.Hold(reason: string)
	PromptGate.Hold(gate, reason, os.clock())
	watch()
end

function PromptSwitch.Release(reason: string)
	PromptGate.Release(gate, reason)
end

-- Who holds prompts off now (for the specs and a log line).
function PromptSwitch.Reasons(): { string }
	return PromptGate.Reasons(gate)
end

return PromptSwitch
