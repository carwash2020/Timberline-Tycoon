--!strict
-- LooseSave: what an unloaded base keeps of the loose things lying on its
-- plot (Connor's decision 9: unloading saves everything, loose wood
-- included). Pure rules; LooseService does the world work.
--
-- On UNLOAD BASE, and when a player leaves with their base on a pad, every
-- unheld log, plank, board, slab and ingot that is theirs (or nobody's) and
-- lies on their plot is written into `plot.loose`, relative to the pad's
-- pivot, and taken out of the world in the same step. Loading the base on any
-- pad puts each one back relative to that pad's pivot, once, and clears the
-- list. Someone else's wood is never touched.
--
-- plot.loose holds three kinds of record, all plain tables (ProfileSchema
-- keeps the list as it is):
--   wood   a LeftLoad piece (w, k, f, x, l, m, d, t, s sections) with
--          bed "Plot" and `at` = its root's place relative to the pad pivot
--   slab   { slab = true, at = {x, y, z, rx, ry, rz} }
--   ingot  { ingot = "Copper", at = {...} }
-- The list is capped (GameConfig.MaxLoosePieces pieces and MaxLooseSections
-- wood sections), so a full three-slot save stays under 1 MB (SaveSize.spec).
-- Over the cap the unload is refused with a count. Nothing is ever dropped.

local GameConfig = require(script.Parent.GameConfig)

local LooseSave = {}

LooseSave.Bed = "Plot"
LooseSave.MaxPieces = GameConfig.MaxLoosePieces
LooseSave.MaxSections = GameConfig.MaxSavedSections

export type Found = {
	pieces: number, -- everything that would be saved, one each
	sections: number, -- wood sections among them
	unsaveable: number, -- loose wood the save cannot hold (too many sections, unknown wood)
}

LooseSave.Texts = {
	over = "Your plot has %d loose things and a saved base holds %d. Pick up or sell %d first.",
	sections = "That much loose wood is too big to save with the base. Pick up or sell some first (%d pieces).",
	unsaveable = "%d loose piece%s can't be saved with the base. Pick %s up or sell %s first.",
} :: { [string]: string }

-- May the base come off the pad with this much loose on it? Returns true, or
-- false and the line to show. The numbers are what CollectCount found.
function LooseSave.Check(found: Found): (boolean, string?)
	if found.unsaveable > 0 then
		local n = found.unsaveable
		return false,
			string.format(
				LooseSave.Texts.unsaveable,
				n,
				if n == 1 then "" else "s",
				if n == 1 then "it" else "them",
				if n == 1 then "it" else "them"
			)
	end
	if found.pieces > LooseSave.MaxPieces then
		return false,
			string.format(LooseSave.Texts.over, found.pieces, LooseSave.MaxPieces, found.pieces - LooseSave.MaxPieces)
	end
	if found.sections > LooseSave.MaxSections then
		return false, string.format(LooseSave.Texts.sections, found.pieces)
	end
	return true, nil
end

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function numbers6(raw: unknown): { number }?
	if type(raw) ~= "table" then
		return nil
	end
	local list = raw :: { any }
	local out: { number } = {}
	for i = 1, 6 do
		local v = list[i]
		if not finite(v) then
			return nil
		end
		out[i] = v :: number
	end
	-- A plot is at most a few hundred studs across; anything wilder is junk.
	for i = 1, 3 do
		if math.abs(out[i]) > 400 then
			return nil
		end
	end
	for i = 4, 6 do
		if math.abs(out[i]) > 7 then
			return nil
		end
	end
	return out
end

local function round(n: number, step: number): number
	return math.floor(n / step + 0.5) * step
end

-- A place as 6 saved numbers: studs to 0.001, radians to 0.0001.
function LooseSave.EncodePlace(x: number, y: number, z: number, rx: number, ry: number, rz: number): { number }
	return { round(x, 0.001), round(y, 0.001), round(z, 0.001), round(rx, 0.0001), round(ry, 0.0001), round(rz, 0.0001) }
end

function LooseSave.SlabRecord(at: { number }): { [string]: any }
	return { slab = true, at = at }
end

function LooseSave.IngotRecord(ore: string, at: { number }): { [string]: any }
	return { ingot = ore, at = at }
end

export type Other = { kind: string, ore: string?, at: { number } }

-- A saved slab or ingot made safe, or nil for junk. `isOre` says whether an
-- ingot's ore id is real. Wood records are cleaned by LeftLoad, not here.
function LooseSave.CleanOther(raw: unknown, isOre: (string) -> boolean): Other?
	if type(raw) ~= "table" then
		return nil
	end
	local r = raw :: { [string]: any }
	local at = numbers6(r.at)
	if at == nil then
		return nil
	end
	if r.slab == true then
		return { kind = "slab", at = at }
	end
	if type(r.ingot) == "string" and isOre(r.ingot) then
		return { kind = "ingot", ore = r.ingot, at = at }
	end
	return nil
end

-- Is this saved record a wood piece (the LeftLoad shape)?
function LooseSave.IsWood(raw: unknown): boolean
	return type(raw) == "table"
		and (raw :: any).slab ~= true
		and (raw :: any).ingot == nil
		and type((raw :: any).w) == "string"
end

-- How many sections a saved wood record carries.
function LooseSave.SectionsOf(raw: unknown): number
	if type(raw) == "table" and type((raw :: any).s) == "table" then
		return #(raw :: any).s
	end
	return 0
end

-- Counts a saved list for the specs and for the restore's refusal message.
function LooseSave.Count(list: unknown): Found
	local found: Found = { pieces = 0, sections = 0, unsaveable = 0 }
	if type(list) ~= "table" then
		return found
	end
	for _, rec in ipairs(list :: { any }) do
		if type(rec) == "table" then
			found.pieces += 1
			found.sections += LooseSave.SectionsOf(rec)
		end
	end
	return found
end

-- What a load puts back and what it leaves in the list: the first MaxPieces
-- records go, any beyond stay saved (a hand-edited or older oversized list),
-- so nothing is ever lost, and the count says how many wait.
function LooseSave.Split(list: unknown): ({ any }, { any })
	local now: { any } = {}
	local later: { any } = {}
	if type(list) ~= "table" then
		return now, later
	end
	for _, rec in ipairs(list :: { any }) do
		if type(rec) == "table" then
			if #now < LooseSave.MaxPieces then
				table.insert(now, rec)
			else
				table.insert(later, rec)
			end
		end
	end
	return now, later
end

-- A line for the player after a load that brought things back.
function LooseSave.RestoredText(n: number, waiting: number): string
	if waiting > 0 then
		return string.format(
			"%d loose things are back on your plot. %d more are still saved; unload and load again after you clear some.",
			n,
			waiting
		)
	end
	return string.format("%d loose thing%s back on your plot.", n, if n == 1 then " is" else "s are")
end

return LooseSave
