--!strict
-- BaseLogic: packing a base away and bringing one back (Land Office, Old
-- Hank). A BASE is a plot record: `profile.plot` (tier, bought squares,
-- placed pieces, wires and switches, and `pads`, the vehicle pads). The one
-- on your pad is `profile.plot`; the ones packed away sit in
-- `profile.bases` (the shelf), each the very same record. A pack or a
-- bring-out MOVES a record between the two, it never copies one, so every
-- piece, pad and box uid exists exactly once at every moment: nothing is
-- lost and nothing is duplicated, and no cash changes hands. The shelf
-- belongs to the save slot (SaveSlotLogic copies it with the slot); the
-- cooldown (`baseCooldownUntil`) is account-wide.
--
-- Positions are plot-local (y = 0 is the platform's top), so a base loads
-- the same on any pad. Pure: PlotService decides when, this decides what.

local GameConfig = require(script.Parent.GameConfig)

local BaseLogic = {}

BaseLogic.Cap = GameConfig.BaseShelfCap
BaseLogic.Cooldown = GameConfig.BaseCooldownSec

export type Plot = { [string]: any }

function BaseLogic.FreshPlot(): Plot
	return { claimed = true, tier = 1, placed = {}, squares = {}, wires = {}, switches = {} }
end

local function count(list: any): number
	return if type(list) == "table" then #list else 0
end

function BaseLogic.Pieces(plot: any): number
	if type(plot) ~= "table" then
		return 0
	end
	return count(plot.placed) + count(plot.pads)
end

-- Nothing here is worth keeping: no pieces, no pads, no bought squares, and
-- still the first tier (a bought tier is money, so it is never "empty").
function BaseLogic.IsEmpty(plot: any): boolean
	if type(plot) ~= "table" then
		return true
	end
	local tier = plot.tier
	return BaseLogic.Pieces(plot) == 0 and count(plot.squares) == 0 and (tier == nil or tier == 1)
end

function BaseLogic.Shelf(profile: any): { Plot }
	if type(profile.bases) ~= "table" then
		profile.bases = {}
	end
	return profile.bases
end

-- "Base 1", the smallest number no shelved base uses.
function BaseLogic.NextName(shelf: { Plot }): string
	local used: { [string]: boolean } = {}
	for _, base in ipairs(shelf) do
		if type(base) == "table" and type(base.name) == "string" then
			used[base.name] = true
		end
	end
	local n = 1
	while used["Base " .. n] do
		n += 1
	end
	return "Base " .. n
end

export type Context = {
	now: number,
	hasPad: boolean, -- they stand on a pad this session
	nearOffice: boolean, -- at Old Hank's counter
	busy: boolean, -- a claim, expand or earlier switch is in flight
	looseWood: number, -- their logs and planks lying on the plot, not held, not loaded
}

-- The refusal texts, said by Old Hank or as a toast.
BaseLogic.Reasons = {
	busy = "Hold on, one thing at a time.",
	office = "Come up to Old Hank's counter at the Land Office for that.",
	noPlot = "You need a plot before you can pack a base.",
	cooldown = "Give it %d more seconds before changing bases.",
	wood = "Pick up or sell the loose logs and planks on your plot first. Nothing gets lost, but loose wood can't be crated.",
	nopad = "Pick a pad for your base first.",
	empty = "There is nothing on this base to pack up.",
	full = "The shelf is full. Bring one back out first.",
	gone = "That base isn't on the shelf any more.",
	bad = "bad",
}

-- Can this change happen right now? action: "pack" (crate the base and give
-- up the pad), "new" (crate it and start an empty base on the same pad),
-- "bring" (swap the base on your pad, or on no pad yet, for shelf entry
-- `index`). Returns ok, or false and the reason text ("bad" is silent).
function BaseLogic.Check(profile: any, action: string, index: unknown, ctx: Context): (boolean, string?)
	if action ~= "pack" and action ~= "new" and action ~= "bring" then
		return false, BaseLogic.Reasons.bad
	end
	if type(profile) ~= "table" or type(profile.plot) ~= "table" then
		return false, BaseLogic.Reasons.bad
	end
	if ctx.busy then
		return false, BaseLogic.Reasons.busy
	end
	if not ctx.nearOffice then
		return false, BaseLogic.Reasons.office
	end
	if profile.plot.claimed ~= true then
		return false, BaseLogic.Reasons.noPlot
	end
	local untilAt = profile.baseCooldownUntil
	if type(untilAt) == "number" and ctx.now < untilAt then
		return false, string.format(BaseLogic.Reasons.cooldown, math.max(1, math.ceil(untilAt - ctx.now)))
	end
	local shelf = BaseLogic.Shelf(profile)
	if action == "bring" then
		if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index == math.huge then
			return false, BaseLogic.Reasons.bad
		end
		if type(shelf[index]) ~= "table" then
			return false, BaseLogic.Reasons.gone
		end
	else
		if action == "pack" and not ctx.hasPad then
			return false, BaseLogic.Reasons.nopad
		end
		if BaseLogic.IsEmpty(profile.plot) then
			return false, BaseLogic.Reasons.empty
		end
		if #shelf >= BaseLogic.Cap then
			return false, BaseLogic.Reasons.full
		end
	end
	-- Wood that stays behind is the one thing a switch could strand: refuse.
	if ctx.hasPad and ctx.looseWood > 0 then
		return false, BaseLogic.Reasons.wood
	end
	return true, nil
end

local function stamp(plot: Plot, shelf: { Plot }, now: number, guid: () -> string)
	if type(plot.id) ~= "string" or plot.id == "" then
		plot.id = guid()
	end
	if type(plot.name) ~= "string" or plot.name == "" then
		plot.name = BaseLogic.NextName(shelf)
	end
	plot.savedAt = now
end

-- Moves records; checks nothing (Check first). Returns the record now on the
-- pad.
function BaseLogic.Swap(profile: any, action: string, index: number?, now: number, guid: () -> string): Plot
	local shelf = BaseLogic.Shelf(profile)
	local live: Plot = profile.plot
	if action == "bring" and index ~= nil then
		local target = shelf[index]
		if BaseLogic.IsEmpty(live) then
			table.remove(shelf, index) -- an empty base is not worth a shelf slot
		else
			stamp(live, shelf, now, guid)
			shelf[index] = live
		end
		target.claimed = true
		profile.plot = target
		return target
	end
	stamp(live, shelf, now, guid)
	table.insert(shelf, live)
	local fresh = BaseLogic.FreshPlot()
	profile.plot = fresh
	return fresh
end

-- After a change that took effect.
function BaseLogic.Stamp(profile: any, now: number)
	profile.baseCooldownUntil = now + BaseLogic.Cooldown
end

export type Snapshot = { plot: Plot, shelf: { Plot }, cooldown: number }

-- References only: Swap moves records and never edits what is inside them,
-- so putting the references back undoes it exactly (a rebuild that failed).
function BaseLogic.Snapshot(profile: any): Snapshot
	local shelf: { Plot } = table.clone(BaseLogic.Shelf(profile))
	return { plot = profile.plot, shelf = shelf, cooldown = tonumber(profile.baseCooldownUntil) or 0 }
end

function BaseLogic.Restore(profile: any, snap: Snapshot)
	local shelf = BaseLogic.Shelf(profile)
	table.clear(shelf)
	for i, base in ipairs(snap.shelf) do
		shelf[i] = base
	end
	profile.plot = snap.plot
	profile.baseCooldownUntil = snap.cooldown
end

-- Every uid the bases hold (placed pieces and pads), live and shelved, in
-- sorted order. A switch must leave this list exactly as it was.
function BaseLogic.Uids(profile: any): { string }
	local out: { string } = {}
	local function take(plot: any)
		if type(plot) ~= "table" then
			return
		end
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
	take(profile.plot)
	for _, base in ipairs(BaseLogic.Shelf(profile)) do
		take(base)
	end
	table.sort(out)
	return out
end

-- The confirm card's words for each change (the Bases panel asks before it
-- sends, and the server checks again).
function BaseLogic.ConfirmText(action: string, name: string, hasPad: boolean): string
	if action == "pack" then
		return "Crate up this base? Everything on it goes in the crate and you give up your pad. Nothing is lost: bring it back out on any open pad."
	elseif action == "new" then
		return "Crate this base and start a fresh empty one on this pad? Your old base waits safely in its crate."
	end
	if hasPad then
		return string.format(
			"Swap your base for %s? Yours goes in a crate, nothing lost, and %s is built on this pad.",
			name,
			name
		)
	end
	return string.format("Bring out %s? You pick a pad for it next.", name)
end

export type Row = { index: number, name: string, tier: number, pieces: number, savedAt: number }

-- The shelf as the panel shows it.
function BaseLogic.Summary(profile: any): { Row }
	local rows: { Row } = {}
	for i, base in ipairs(BaseLogic.Shelf(profile)) do
		table.insert(rows, {
			index = i,
			name = if type(base.name) == "string" and base.name ~= "" then base.name else "Base " .. i,
			tier = if type(base.tier) == "number" then base.tier else 1,
			pieces = BaseLogic.Pieces(base),
			savedAt = if type(base.savedAt) == "number" then base.savedAt else 0,
		})
	end
	return rows
end

return BaseLogic
