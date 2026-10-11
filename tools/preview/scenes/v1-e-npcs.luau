--!nocheck
-- Lane E layout check: Rook Calloway on the sawmill's MillForemanSpot pad,
-- and the five NPCs that now have Blender meshes (Hermit, Old Tolly,
-- Cap'n Moss, Old Hank, the Foreman) as their PART-BUILT fallback.
-- The Blender GLBs for these five are not in the pack (only stats.json), so
-- these renders are layout and facing checks only, NOT mesh renders.
--   1 Rook at the mill, three-quarter   2 close, front   3 from behind
--   4 from the side   5 the yard from the road   6 line-up of the five
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local CharacterArt = ctx.art("CharacterArt")
		local BuildingArt = ctx.art("BuildingArt")
		local NPCData = ctx.shared("NPCData")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 700, C3.fromRGB(112, 162, 82), V3.new(0, -0.5, 100))

		local town = WorldPlan.Town()
		local mill = BuildingArt.Sawmill()
		mill:PivotTo(town.sawmill)
		mill.Parent = root

		local function stand(id)
			local npc = NPCData.Get(id)
			local m = CharacterArt.Build(npc.look)
			Kit.placeAt(
				m,
				NPCData.SpotFor(npc, function()
					return nil, nil
				end)
			)
			m.Parent = root
			return m
		end
		local rook = stand("Foreman")
		local spot = NPCData.ForemanSpot

		-- The five, in a row off to the east.
		local LX, LZ = 300, 100
		for i, id in ipairs({ "Hermit", "OldTolly", "CapnMoss", "OldHank", "Foreman" }) do
			local npc = NPCData.Get(id)
			local m = CharacterArt.Build(npc.look)
			Kit.placeAt(m, CF.new(LX + (i - 1) * 5, 0, LZ))
			m.Parent = root
		end

		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 160,
			fov = 40,
			cameras = {
				cam(spot.X + 6, 4.5, spot.Z - 7, spot.X, 3.4, spot.Z, "Rook at the mill, three-quarter (part-built)"),
				cam(spot.X, 4, spot.Z - 8, spot.X, 3.4, spot.Z, "Rook up close, front (he faces the road, -Z)"),
				cam(spot.X, 4.5, spot.Z + 8, spot.X, 3.4, spot.Z, "Rook from behind (the mill wall behind him)"),
				cam(spot.X + 9, 4, spot.Z, spot.X, 3.4, spot.Z, "Rook from the side, feet on the pad"),
				cam(-8, 14, 40, spot.X + 6, 4, spot.Z, "the yard from the road, with the jobs board"),
				cam(LX + 10, 5, LZ - 24, LX + 10, 3.4, LZ, "the five NPCs, part-built fallbacks (layout only)"),
			},
		}
	end,
}
