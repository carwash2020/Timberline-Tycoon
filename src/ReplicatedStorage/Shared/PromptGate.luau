--!strict
-- PromptGate: who is holding the world's ProximityPrompts off. Pure, so the
-- client (StarterPlayerScripts/PromptSwitch) and the specs agree.
--
-- ProximityPromptService.Enabled is one switch on one client, and four
-- things used to flip it by saving "what it was" and putting that back: the
-- dialogue box (DialogueUI), a held piece (DragController), the build
-- placer (BlueprintPlacer) and the wire tool (WireTool). Two of them
-- overlapping left the switch OFF for good: the second one to start saved
-- the first one's "off" as the value to restore, the first one then ended
-- and switched prompts on, and when the second ended it put "off" back.
-- Nothing was left to turn them on again, so every Talk, Buy, Open and Pick
-- up prompt in the world was dead until the next box opened and closed.
--
-- Here nobody saves anything. Each holder has a name (a reason); prompts are
-- on exactly when nobody holds them off, and a holder that ends (or ends
-- twice, or never began) can only remove its own name.

local PromptGate = {}

export type Gate = {
	reasons: { [string]: number }, -- reason -> os.clock when it began holding
	apply: (enabled: boolean) -> (),
	applied: boolean?, -- the last value sent to `apply`
}

-- A gate that sends every change of state to `apply`. It starts with prompts
-- on and sends nothing until a reason arrives.
function PromptGate.New(apply: (enabled: boolean) -> ()): Gate
	return { reasons = {}, apply = apply, applied = true }
end

-- Whether prompts should be on right now: nobody holds them off.
function PromptGate.Open(gate: Gate): boolean
	return next(gate.reasons) == nil
end

local function push(gate: Gate)
	local want = PromptGate.Open(gate)
	if gate.applied ~= want then
		gate.applied = want
		gate.apply(want)
	end
end

-- `reason` holds prompts off (from `now`). Holding twice is the same hold.
function PromptGate.Hold(gate: Gate, reason: string, now: number?)
	if gate.reasons[reason] == nil then
		gate.reasons[reason] = now or 0
	end
	push(gate)
end

-- `reason` lets go. Prompts come back when it was the last. Releasing a
-- reason that is not held does nothing.
function PromptGate.Release(gate: Gate, reason: string)
	gate.reasons[reason] = nil
	push(gate)
end

-- The reasons now holding prompts off, sorted (for a log line).
function PromptGate.Reasons(gate: Gate): { string }
	local out: { string } = {}
	for reason in pairs(gate.reasons) do
		table.insert(out, reason)
	end
	table.sort(out)
	return out
end

-- Holds that have lasted longer than `seconds` at `now`, as "reason (12s)".
-- The server-side of a stuck switch is a hold nobody released: this is what
-- the client warns about.
function PromptGate.Stale(gate: Gate, now: number, seconds: number): { string }
	local out: { string } = {}
	for _, reason in ipairs(PromptGate.Reasons(gate)) do
		local since = gate.reasons[reason] :: number
		if now - since > seconds then
			table.insert(out, string.format("%s (%ds)", reason, math.floor(now - since)))
		end
	end
	return out
end

-- Puts the switch right when something else moved it: `actual` is what the
-- engine says now. Returns true when it had to be corrected.
function PromptGate.Heal(gate: Gate, actual: boolean): boolean
	local want = PromptGate.Open(gate)
	if actual == want then
		return false
	end
	gate.applied = want
	gate.apply(want)
	return true
end

return PromptGate
