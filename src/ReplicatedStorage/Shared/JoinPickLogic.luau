--!strict
-- JoinPickLogic: which join screens open, and in which order. Pure, so the
-- server (SaveSlotService, GameServer) and the client (SaveSlotUI,
-- PlotPickerUI) and the specs agree.
--
-- Saves are chosen by hand (Connor, 8 October 2026): a player is never put
-- into a save they did not pick. After the quality screen the save picker
-- lists the saves; the one last played is marked "Last played", not
-- "Playing". Only when the PICKED save has a plot does the plot picker open
-- (with its camera, map and pillar) so they choose a pad for that base. A
-- save with no plot just enters the world: the Land Office sells one. A
-- player already standing on a base this session (a swap from the SAVES
-- panel) is not asked again.

local JoinPickLogic = {}

export type State = {
	slotChosen: boolean, -- the player picked a save this visit (server memory only)
	onBase: boolean, -- they already stand on a pad this session
	needsQuality: boolean, -- the Lower / Higher screen is still owed
	pickedHasPlot: boolean, -- the chosen save owns a plot (profile.plot.claimed)
}

-- Does this player still owe a save pick? Not once they chose, and not when
-- they already stand on a base (a mid-session swap).
function JoinPickLogic.NeedsSlotPick(slotChosen: boolean, onBase: boolean): boolean
	return not slotChosen and not onBase
end

-- Does the chosen save lead to the plot picker?
function JoinPickLogic.NeedsPlotPick(slotChosen: boolean, onBase: boolean, pickedHasPlot: boolean): boolean
	return slotChosen and not onBase and pickedHasPlot
end

-- The screens this state still owes, in the order they open.
function JoinPickLogic.Screens(state: State): { string }
	local out: { string } = {}
	if state.needsQuality then
		table.insert(out, "quality")
	end
	if JoinPickLogic.NeedsSlotPick(state.slotChosen, state.onBase) then
		table.insert(out, "slot")
	end
	-- Until a save is picked nobody knows whether a plot picker is owed; once
	-- it is, only a save with a plot opens it.
	if JoinPickLogic.NeedsPlotPick(state.slotChosen, state.onBase, state.pickedHasPlot) then
		table.insert(out, "plot")
	end
	return out
end

-- The labels of the save picker. Before a pick the active save is where the
-- save last left off, not a game you are in. There is no wipe button on the
-- list any more: Restart save lives in Settings (SettingsLogic.RestartRow).
function JoinPickLogic.ActiveBadge(picking: boolean): string
	return if picking then "Last played" else "Playing"
end

-- The button on a save row: PLAY (the join pick), START (a never-played
-- save), LOAD (a swap from the SAVES panel). The playing save has none.
function JoinPickLogic.PlayLabel(picking: boolean, fresh: boolean, active: boolean): string?
	if picking then
		return if fresh then "START" else "PLAY"
	end
	if active then
		return nil
	end
	return if fresh then "START" else "LOAD"
end

-- One line on a save row: whether it owns a plot, and how much is on it.
function JoinPickLogic.PlotText(hasPlot: boolean, pieces: number, packed: number): string
	if not hasPlot then
		return "No plot yet"
	end
	local text = if pieces == 1 then "Plot, 1 piece" else string.format("Plot, %d pieces", pieces)
	if packed > 0 then
		text ..= string.format(", %d packed", packed)
	end
	return text
end

return JoinPickLogic
