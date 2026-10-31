--!nocheck
-- The live terrain fill paints the town even when this spec did not load
-- TownGround first. The check is the voxels TerrainBuilder writes, not a
-- scan of the source and not TerrainGen.Sample on a module that was
-- already warm.

return function(t)
	t.test("a fresh TerrainBuilder writes Cobblestone at the street and Ground on the spawn walk", function()
		local writes = {}
		local terrain = {
			GetAttribute = function()
				return nil
			end,
			Clear = function() end,
			SetMaterialColor = function() end,
			FillBlock = function() end,
			WriteVoxels = function(_, region, _, mats, occs)
				table.insert(writes, { region = region, mats = mats, occs = occs })
			end,
		}
		local ws = { Terrain = terrain }
		function ws:SetAttribute() end
		function ws:GetAttribute()
			return nil
		end
		function ws:Raycast()
			return nil
		end
		local loader = t.loader({
			isolated = true,
			globals = {
				workspace = ws,
				RaycastParams = {
					new = function()
						return {}
					end,
				},
				task = {
					wait = function() end,
				},
			},
		})
		-- Drop anything this loader already holds, then prove TownGround is absent.
		loader.cache = {}
		local function townLoaded(): boolean
			for key in pairs(loader.cache) do
				if string.find(key, "TownGround.luau", 1, true) then
					return true
				end
			end
			return false
		end
		t.eq(townLoaded(), false, "TownGround is not loaded yet")
		local TerrainBuilder = loader:server("TerrainBuilder")
		t.eq(townLoaded(), true, "requiring TerrainBuilder loads TownGround")
		-- nearRadius 0 still settles the town chunks. That is the live write.
		TerrainBuilder.Build(nil, {
			nearRadius = 0,
			wait = function() end,
		})
		local function written(x: number, z: number): string?
			for _, w in ipairs(writes) do
				local pos, size = w.region.CFrame.Position, w.region.Size
				local x0, z0 = pos.X - size.X / 2, pos.Z - size.Z / 2
				local x1, z1 = pos.X + size.X / 2, pos.Z + size.Z / 2
				if x >= x0 and x < x1 and z >= z0 and z < z1 then
					local i = math.floor((x - x0) / 4) + 1
					local k = math.floor((z - z0) / 4) + 1
					local column, occ = w.mats[i], w.occs[i]
					if column then
						for j = #column, 1, -1 do
							local occCell = occ[j][k]
							local mat = column[j][k]
							if occCell and occCell > 0 and mat and mat.Name ~= "Water" and mat.Name ~= "Air" then
								return mat.Name
							end
						end
					end
				end
			end
			return nil
		end
		t.eq(written(-60, 73), "Cobblestone", "written street voxel")
		t.eq(written(0, 50), "Ground", "written spawn-walk voxel")
	end)
end
