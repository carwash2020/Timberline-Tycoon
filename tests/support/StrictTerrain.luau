--!nocheck
-- StrictTerrain (T417): the two rules of Terrain:WriteVoxels that the Lune fakes
-- never checked, so a terrain with no ground passed every spec (#270 moved the
-- chunk origin off the 4-stud voxel grid and Studio drew nothing):
--   1. the Region3's min and max are multiples of the resolution
--      ("Region has to be aligned to the grid");
--   2. the materials and occupancy arrays are nx by ny by nz, the region's voxel
--      counts ("Bad argument materials to 'WriteVoxels' (NxNyxNz array expected)").
-- Use:  local Strict = t.support("StrictTerrain")
--       WriteVoxels = function(_, region, res, mats, occs) Strict.check(region, res, mats, occs) ... end
-- Mimics those two documented rules only; it cannot say the engine is satisfied.
return function()
	local Strict = {}

	local function isMultiple(v: number, res: number): boolean
		return math.abs(v / res - math.floor(v / res + 0.5)) < 1e-9
	end

	-- Region bounds as numbers: minX, minY, minZ, maxX, maxY, maxZ.
	function Strict.bounds(region: any): { number }
		local p, s = region.CFrame.Position, region.Size
		return { p.X - s.X / 2, p.Y - s.Y / 2, p.Z - s.Z / 2, p.X + s.X / 2, p.Y + s.Y / 2, p.Z + s.Z / 2 }
	end

	-- True when Region3:ExpandToGrid(res) would return the same region.
	function Strict.aligned(region: any, res: number): boolean
		for _, v in ipairs(Strict.bounds(region)) do
			if not isMultiple(v, res) then
				return false
			end
		end
		return true
	end

	-- Errors like the engine does.
	function Strict.check(region: any, res: number, mats: any, occs: any)
		if not Strict.aligned(region, res) then
			error("Region has to be aligned to the grid (use Region3:ExpandToGrid with authoring resolution)", 2)
		end
		local b = Strict.bounds(region)
		local nx = math.floor((b[4] - b[1]) / res + 0.5)
		local ny = math.floor((b[5] - b[2]) / res + 0.5)
		local nz = math.floor((b[6] - b[3]) / res + 0.5)
		local want = string.format("%dx%dx%d array expected", nx, ny, nz)
		for _, pair in ipairs({ { "materials", mats }, { "occupancy", occs } }) do
			local name, arr = pair[1], pair[2]
			local bad = type(arr) ~= "table" or #arr ~= nx
			if not bad then
				for i = 1, nx do
					local plane = arr[i]
					if type(plane) ~= "table" or #plane ~= ny then
						bad = true
						break
					end
					for j = 1, ny do
						local row = plane[j]
						if type(row) ~= "table" or #row ~= nz then
							bad = true
							break
						end
					end
					if bad then
						break
					end
				end
			end
			if bad then
				error(string.format("Bad argument %s to 'WriteVoxels' (%s)", name, want), 2)
			end
		end
	end

	return Strict
end
