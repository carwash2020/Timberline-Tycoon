--!strict
-- TerrainFit: where the engine really draws the ground we write (TER-01).
--
-- TerrainGen says how high the ground is and TerrainBuilder writes that as
-- voxel occupancies (TerrainGen.Voxel). How the engine meshes occupancies
-- into a surface is up to the engine, and on the live game the flat town
-- was drawn 2-3 studs above y = 0: the parking paint was buried, NPCs and
-- parked trucks stood waist-deep and players spawned inside the ground.
-- So TerrainBuilder measures it before writing the world: it writes small
-- flat test pads far below the map, one per written height across a voxel
-- (Residues), casts a ray onto each and hands the results to Fit. Written
-- then gives the height to write so the ground is drawn where TerrainGen
-- says. Missing or nonsensical measurements give the identity fit, so this
-- can only move the ground toward where it belongs.
--
-- Heights repeat every voxel (4 studs): writing h + 4 draws 4 studs higher
-- than writing h. So a fit is a curve over one voxel: for a written height
-- r studs above a voxel boundary, where (relative to that boundary) the
-- surface is drawn.

local TerrainFit = {}

local VOXEL = 4

-- Written heights (studs above a voxel boundary) the test pads use.
TerrainFit.Residues = { 0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5 }

-- Offsets under this are noise: the ground is already where it belongs.
TerrainFit.Tolerance = 0.15

-- The biggest believable offset (anything past it is a missed ray or a
-- broken pad, and the measurement is thrown away).
TerrainFit.MaxOffset = 6

export type Sample = { written: number, drawn: number }

export type Fit = {
	identity: boolean,
	offset: number, -- the mean drawn - written, for reports
	-- Inverse curve over one voxel, extended a voxel either way and sorted
	-- by `drawn`: the written residue that draws at each drawn residue.
	drawnKeys: { number },
	writtenKeys: { number },
	-- Forward curve, sorted by `written`.
	fwdWritten: { number },
	fwdDrawn: { number },
}

local IDENTITY: Fit = {
	identity = true,
	offset = 0,
	drawnKeys = {},
	writtenKeys = {},
	fwdWritten = {},
	fwdDrawn = {},
}
TerrainFit.Identity = IDENTITY

local function lerpAt(keys: { number }, values: { number }, x: number): number
	local n = #keys
	if x <= keys[1] then
		return values[1] + (x - keys[1])
	elseif x >= keys[n] then
		return values[n] + (x - keys[n])
	end
	for i = 2, n do
		local k1 = keys[i]
		if x <= k1 then
			local k0 = keys[i - 1]
			local span = k1 - k0
			if span <= 1e-9 then
				return values[i]
			end
			return values[i - 1] + (values[i] - values[i - 1]) * (x - k0) / span
		end
	end
	return values[n]
end

-- Builds a fit from measured samples (written height, drawn height; any
-- voxel). Returns the fit and a note on what was decided.
function TerrainFit.Fit(samples: { Sample }): (Fit, string)
	type Point = { r: number, d: number }
	local points: { Point } = {}
	local sum = 0
	for _, s in ipairs(samples) do
		local offset = s.drawn - s.written
		if offset ~= offset or math.abs(offset) > TerrainFit.MaxOffset then
			return IDENTITY, string.format("a pad read %.2f studs off; not trusted, left as written", offset)
		end
		local base = math.floor(s.written / VOXEL) * VOXEL
		table.insert(points, { r = s.written - base, d = s.drawn - base })
		sum += offset
	end
	if #points == 0 then
		return IDENTITY, "no pad was measured; left as written"
	end
	local mean = sum / #points
	local worst = 0
	for _, p in ipairs(points) do
		worst = math.max(worst, math.abs(p.d - p.r))
	end
	if worst < TerrainFit.Tolerance then
		return IDENTITY, string.format("drawn where written (within %.2f studs)", worst)
	end
	table.sort(points, function(a, b)
		return a.r < b.r
	end)
	-- Drawn must rise with written (one voxel on, it repeats 4 higher).
	for i = 2, #points do
		if points[i].d < points[i - 1].d - 0.05 then
			return IDENTITY, "the pads drew out of order; left as written"
		end
	end
	if points[1].d + VOXEL < points[#points].d - 0.05 then
		return IDENTITY, "the pads drew out of order across a voxel; left as written"
	end
	local fwdWritten, fwdDrawn = {}, {}
	for shift = -1, 1 do
		for _, p in ipairs(points) do
			table.insert(fwdWritten, p.r + shift * VOXEL)
			table.insert(fwdDrawn, p.d + shift * VOXEL)
		end
	end
	-- The inverse: the same points with the axes swapped (already in
	-- order, since drawn rises with written).
	local fit: Fit = {
		identity = false,
		offset = mean,
		drawnKeys = table.clone(fwdDrawn),
		writtenKeys = table.clone(fwdWritten),
		fwdWritten = fwdWritten,
		fwdDrawn = fwdDrawn,
	}
	return fit, string.format("drawn %.2f studs off where written; correcting", mean)
end

-- Where the engine draws ground written at `written` (per the fit).
function TerrainFit.Drawn(fit: Fit, written: number): number
	if fit.identity then
		return written
	end
	local base = math.floor(written / VOXEL) * VOXEL
	return base + lerpAt(fit.fwdWritten, fit.fwdDrawn, written - base)
end

-- The height to write so the ground is drawn at `target`.
function TerrainFit.Written(fit: Fit, target: number): number
	if fit.identity then
		return target
	end
	local base = math.floor(target / VOXEL) * VOXEL
	return base + lerpAt(fit.drawnKeys, fit.writtenKeys, target - base)
end

return TerrainFit
