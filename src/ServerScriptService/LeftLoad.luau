--!strict
-- LeftLoad: what a rejoin puts back, and how much of it.
--
-- The v1 loop (PLAY-14): saved left-behind logs (profile.leftLoad) come
-- back when their owner rejoins. Every one is its own log model with its
-- own prompt, so the count is capped at GameConfig.MaxLeftLogs (72: the
-- biggest load there is, a Logging Rig's 48 plus a Heavy Hauler's 24, so
-- nobody loses a full truck). New saves already stop there (GameServer's
-- save on leave); saves made under the old cap of 150 can hold more, so
-- the restore is capped too. It keeps the first MaxLeftLogs entries as
-- saved; the rest go when the save's list is cleared. GameServer passes
-- the result to VehicleService.RestoreLeftLoad.
--
-- The v2 loop (V2_PLAN.md §4d, M1.6): the loose wood on your truck's beds
-- is saved in profile.truckLoad (TruckLoad, on leaving and as it rides)
-- and rebuilt on the bed when you rejoin. Each piece is a compact record
-- (ProfileSchema.TruckPiece): its wood, kind, figure, boost, the bed it
-- rode, where it lay on that bed, and its sections' sizes and places. The
-- list is capped both ways, on saving and on restoring: at most
-- GameConfig.MaxSavedPieces pieces and GameConfig.MaxSavedSections
-- sections in all. Clean checks a saved record before anything is built
-- from it. Pure (CFrames are datatypes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local LeftLoad = {}

-- The saved entries to put back: the first MaxLeftLogs, in saved order
-- (a new list; `saved` isn't changed).
function LeftLoad.ToRestore(saved: { any }): { any }
	local n = math.min(#saved, GameConfig.MaxLeftLogs)
	local out: { any } = table.create(n)
	for i = 1, n do
		out[i] = saved[i]
	end
	return out
end

---------------------------------------------------------------------------
-- v2: loose pieces on the bed (profile.truckLoad)
---------------------------------------------------------------------------

-- One saved piece (ProfileSchema.TruckPiece has the same shape):
--   w    wood id                  k   "log" | "plank"
--   f    figure id, if figured    x   boost (2 = cut under 2x Wood), if any
--   bed  the bed it rode: "BedFloor" (the truck's) or "TrailerBed"
--   at   its root section's CFrame relative to that bed part: { x, y, z,
--        rx, ry, rz } (studs; radians, CFrame.fromEulerAnglesXYZ)
--   s    its sections, the root first: { sx, sy, sz, x, y, z, rx, ry, rz,
--        faces } each, size and place relative to the root; faces: 1 = a
--        cut face on its +Y end, 2 = on its -Y end, 3 = both
export type Piece = {
	w: string,
	k: string,
	f: string?,
	x: number?,
	bed: string,
	at: { number },
	s: { { number } },
}

LeftLoad.Beds = { BedFloor = true, TrailerBed = true } :: { [string]: boolean }
LeftLoad.MaxOffset = 80 -- studs: a saved place further than this from its bed (or root) is junk
LeftLoad.MaxSize = 80 -- studs: a section bigger than this is junk
LeftLoad.MinSize = 0.05
LeftLoad.MaxBoost = 4

local function round(n: number, step: number): number
	return math.floor(n / step + 0.5) * step
end

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- `cf` as 6 numbers: position (to 0.001 studs) and XYZ Euler angles (to
-- 0.0001 radians).
function LeftLoad.EncodeCFrame(cf: CFrame): { number }
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	local p = cf.Position
	return {
		round(p.X, 0.001),
		round(p.Y, 0.001),
		round(p.Z, 0.001),
		round(rx, 0.0001),
		round(ry, 0.0001),
		round(rz, 0.0001),
	}
end

-- The CFrame 6 saved numbers (from `first`, default 1) stand for, or nil
-- when they aren't sane (missing, not finite, or further than MaxOffset).
function LeftLoad.DecodeCFrame(list: unknown, first: number?): CFrame?
	if type(list) ~= "table" then
		return nil
	end
	local raw = list :: { any }
	local i = first or 1
	local n: { number } = {}
	for k = 0, 5 do
		local v = raw[i + k]
		if not finite(v) then
			return nil
		end
		n[k + 1] = v :: number
	end
	if
		math.abs(n[1]) > LeftLoad.MaxOffset
		or math.abs(n[2]) > LeftLoad.MaxOffset
		or math.abs(n[3]) > LeftLoad.MaxOffset
	then
		return nil
	end
	for k = 4, 6 do
		if math.abs(n[k]) > 7 then
			return nil -- angles are within a turn or so
		end
	end
	return CFrame.new(n[1], n[2], n[3]) * CFrame.fromEulerAnglesXYZ(n[4], n[5], n[6])
end

-- One saved section, encoded: its size, its place relative to the root,
-- and which ends show a cut face.
function LeftLoad.EncodeSection(size: Vector3, rel: CFrame, faces: number): { number }
	local c = LeftLoad.EncodeCFrame(rel)
	return {
		round(size.X, 0.001),
		round(size.Y, 0.001),
		round(size.Z, 0.001),
		c[1],
		c[2],
		c[3],
		c[4],
		c[5],
		c[6],
		faces,
	}
end

-- A saved section's size, place relative to the root and cut faces, or
-- nil for junk.
function LeftLoad.DecodeSection(raw: unknown): (Vector3?, CFrame?, number)
	if type(raw) ~= "table" then
		return nil, nil, 0
	end
	local list = raw :: { any }
	local sx, sy, sz = list[1], list[2], list[3]
	for _, v in ipairs({ sx, sy, sz }) do
		if not finite(v) or v < LeftLoad.MinSize or v > LeftLoad.MaxSize then
			return nil, nil, 0
		end
	end
	local rel = LeftLoad.DecodeCFrame(list, 4)
	if not rel then
		return nil, nil, 0
	end
	local faces = list[10]
	local f = if finite(faces) then math.clamp(math.floor(faces :: number), 0, 3) else 0
	return Vector3.new(sx, sy, sz), rel, f
end

-- A saved piece made safe to rebuild: a known wood (`isWood`), a kind, a
-- bed, a sane place and at least one sane section; figure and boost kept
-- when they make sense. Nil for junk. A new table (nothing shared).
function LeftLoad.CleanPiece(raw: unknown, isWood: (string) -> boolean): Piece?
	if type(raw) ~= "table" then
		return nil
	end
	local r = raw :: { [string]: any }
	if type(r.w) ~= "string" or not isWood(r.w) then
		return nil
	end
	if type(r.bed) ~= "string" or not LeftLoad.Beds[r.bed] then
		return nil
	end
	if not LeftLoad.DecodeCFrame(r.at) or type(r.s) ~= "table" then
		return nil
	end
	local sections: { { number } } = {}
	for _, s in ipairs(r.s :: { any }) do
		local size, rel, faces = LeftLoad.DecodeSection(s)
		if not size or not rel then
			return nil -- a piece missing a section isn't that piece any more
		end
		table.insert(sections, LeftLoad.EncodeSection(size, rel, faces))
	end
	if #sections == 0 or #sections > GameConfig.MaxSavedSections then
		return nil
	end
	local at = r.at :: { number }
	local boost = r.x
	return {
		w = r.w,
		k = if r.k == "plank" then "plank" else "log",
		f = if type(r.f) == "string" and r.f ~= "" then r.f else nil,
		x = if finite(boost) and (boost :: number) > 1 then math.min(boost :: number, LeftLoad.MaxBoost) else nil,
		bed = r.bed,
		at = { at[1], at[2], at[3], at[4], at[5], at[6] },
		s = sections,
	}
end

-- The pieces that fit the save, in the order given (TruckLoad puts the
-- most valuable first): at most MaxSavedPieces, and a piece whose
-- sections would take the total over MaxSavedSections is skipped (a
-- smaller one after it may still fit). Returns them and how many didn't.
function LeftLoad.Fit(pieces: { Piece }): ({ Piece }, number)
	local out: { Piece } = {}
	local sections, dropped = 0, 0
	for _, p in ipairs(pieces) do
		local n = #p.s
		if #out >= GameConfig.MaxSavedPieces or sections + n > GameConfig.MaxSavedSections then
			dropped += 1
		else
			table.insert(out, p)
			sections += n
		end
	end
	return out, dropped
end

-- A saved truckLoad made safe to rebuild: each piece cleaned (junk
-- dropped), then capped (Fit). Returns the pieces and how many didn't
-- come back.
function LeftLoad.PiecesToRestore(saved: unknown, isWood: (string) -> boolean): ({ Piece }, number)
	if type(saved) ~= "table" then
		return {}, 0
	end
	local clean: { Piece } = {}
	local junk = 0
	for _, raw in ipairs(saved :: { any }) do
		local p = LeftLoad.CleanPiece(raw, isWood)
		if p then
			table.insert(clean, p)
		else
			junk += 1
		end
	end
	local kept, over = LeftLoad.Fit(clean)
	return kept, junk + over
end

return LeftLoad
