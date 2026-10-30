--!nocheck
-- The live terrain fill has to paint the town even when the test did not
-- require TownGround first. A source-order check is not this.

return function(t)
	t.test("TerrainBuilder.Build paints the street and the spawn walk without a preloaded TownGround", function()
		local terrain = {
			GetAttribute = function()
				return nil
			end,
			Clear = function() end,
			SetMaterialColor = function() end,
			FillBlock = function() end,
			WriteVoxels = function() end,
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
		-- The entry point. TownGround is not loaded before this.
		local TerrainBuilder = loader:server("TerrainBuilder")
		-- nearRadius 0 still settles the town (that is the live entry). The
		-- returned finisher is the rest of the map; this spec does not run it.
		TerrainBuilder.Build(nil, {
			nearRadius = 0,
			wait = function() end,
		})
		local TerrainGen = loader:load("ReplicatedStorage/Shared/World/TerrainGen")
		local function surface(x, z)
			local _, m = TerrainGen.Sample(x, z)
			return m
		end
		t.eq(surface(-60, 73), "Cobblestone", "main street")
		t.eq(surface(0, 50), "Ground", "spawn walk")
	end)
end
