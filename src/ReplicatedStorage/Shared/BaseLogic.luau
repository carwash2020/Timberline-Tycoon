--!strict
-- BaseLogic: unloading your base and loading it back (LT2 style). The base
-- is the plot record in `profile.plot` (tier, bought squares, placed pieces,
-- wires, switches and `pads`, the vehicle pads). UNLOAD BASE saves the active
-- save, takes the base off the pad (its models come down, visitors are set
-- down outside, the pad is free for others) and leaves you in the world with
-- no pad. The record never moves and is never copied or edited: it stays in
-- `profile.plot` of that save, so every piece, pad and uid exists exactly once
-- and no cash changes hands. LOAD BASE opens the free plot picker and builds
-- the same record on the pad you choose. Switching to ANOTHER base is
-- switching saves (SaveSlotLogic); this module only decides when an unload is
-- allowed. Positions are plot-local (y = 0 is the platform's top), so a base
-- loads the same on any pad. Pure: PlotService does the work.
--
-- `baseCooldownUntil` is account-wide (SaveSlotLogic.ACCOUNT), so a rejoin
-- or a save swap does not skip it. Loading a base back is never cooled.

local GameConfig = require(script.Parent.GameConfig)

local BaseLogic = {}

BaseLogic.Cooldown = GameConfig.BaseCooldownSec

export type Context = {
	now: number,
	hasPad: boolean, -- they stand on a pad this session
	busy: boolean, -- a claim, expand or earlier unload is in flight
	looseWood: number, -- their logs and planks lying on the plot, not held, not loaded
}

-- The refusal texts, shown as a toast. "bad" is silent.
BaseLogic.Reasons = {
	busy = "Hold on, one thing at a time.",
	noPlot = "You have no plot to unload.",
	nopad = "Your base is not on a pad right now.",
	cooldown = "Give it %d more seconds before unloading again.",
	wood = "Pick up or sell the loose logs and planks on your plot first. Nothing gets lost, but loose wood can't be saved with the base.",
	bad = "bad",
}

BaseLogic.UnloadConfirm =
	"Unload your base? It is saved with this save, taken off your pad and your pad is freed for others. Nothing is lost or sold. Press LOAD BASE any time to put it on a pad."
BaseLogic.UnloadedToast = "Base unloaded and saved. Your pad is free. Use LOAD BASE in the SAVES panel to put it back."
BaseLogic.LoadedToast = "Pick a pad for your base."

-- Can the base come off the pad right now? Returns ok, or false and the reason.
function BaseLogic.CheckUnload(profile: any, ctx: Context): (boolean, string?)
	if type(profile) ~= "table" or type(profile.plot) ~= "table" then
		return false, BaseLogic.Reasons.bad
	end
	if ctx.busy then
		return false, BaseLogic.Reasons.busy
	end
	if profile.plot.claimed ~= true then
		return false, BaseLogic.Reasons.noPlot
	end
	if not ctx.hasPad then
		return false, BaseLogic.Reasons.nopad
	end
	local untilAt = profile.baseCooldownUntil
	if type(untilAt) == "number" and ctx.now < untilAt then
		return false, string.format(BaseLogic.Reasons.cooldown, math.max(1, math.ceil(untilAt - ctx.now)))
	end
	-- Wood that stays behind is the one thing an unload could strand: refuse.
	if ctx.looseWood > 0 then
		return false, BaseLogic.Reasons.wood
	end
	return true, nil
end

-- Can the base be loaded onto a pad? It owns a plot and has none now.
function BaseLogic.CanLoad(profile: any, hasPad: boolean): (boolean, string?)
	if type(profile) ~= "table" or type(profile.plot) ~= "table" or profile.plot.claimed ~= true then
		return false, BaseLogic.Reasons.noPlot
	end
	if hasPad then
		return false, BaseLogic.Reasons.bad
	end
	return true, nil
end

-- After an unload that took effect.
function BaseLogic.Stamp(profile: any, now: number)
	profile.baseCooldownUntil = now + BaseLogic.Cooldown
end

-- What the SAVES panel's base button should be: "unload" while the base is
-- on a pad, "load" while the save has a base waiting for one, nil otherwise
-- (no plot, or the save picker is still up).
function BaseLogic.ButtonFor(hasPad: boolean, saveHasPlot: boolean, picking: boolean): string?
	if picking then
		return nil
	end
	if hasPad then
		return "unload"
	end
	if saveHasPlot then
		return "load"
	end
	return nil
end

function BaseLogic.ButtonText(kind: string): string
	return if kind == "unload" then "UNLOAD BASE" else "LOAD BASE"
end

-- Every uid the base holds (placed pieces and pads), sorted. An unload must
-- leave this list exactly as it was.
function BaseLogic.Uids(profile: any): { string }
	local out: { string } = {}
	local plot = profile.plot
	if type(plot) == "table" then
		for _, list in ipairs({ plot.placed, plot.pads }) do
			if type(list) == "table" then
				for _, item in ipairs(list) do
					if type(item) == "table" and type(item.uid) == "string" then
						table.insert(out, item.uid)
					end
				end
			end
		end
	end
	table.sort(out)
	return out
end

return BaseLogic
