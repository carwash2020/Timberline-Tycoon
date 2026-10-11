--!nocheck
-- Lane E: Rook Calloway on the sawmill's MillForemanSpot pad, and Hermit, Old
-- Tolly, Cap'n Moss and Old Hank on their stand spots. Run with
--   PREVIEW_MESHES=<json> bash tools/preview/shoot.sh v1-e-npcs
-- (a preview-only manifest pointing at assets/glb/backlog/npcs/*) for the REAL
-- Blender meshes; without it they are the part-built fallbacks.
--   1 Rook at the mill, three-quarter   2 close, front   3 from behind
--   4 from the side   5 the yard from the road   6 line-up of the five
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
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

		-- The five on their real stand spots (NPCData.SpotFor; fixed spots stand on
		-- the terrain plus the booth floor or dock deck). The landmarks around
		-- them (booth, dock, cave, Land Office) are not built here: each gets a
		-- 24-stud grass patch at its own height.
		local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
		local placed = {}
		-- Calibration: Murph (his meshes are in assets/meshes) on the same patch rules,
		-- 40 studs east of Rook, facing -Z like every NPC.
		do
			local m = CharacterArt.Build(NPCData.Get("Murph").look)
			Kit.part(
				root,
				"PatchMurph",
				V3.new(24, 1, 24),
				CF.new(60, -0.5, 100),
				C3.fromRGB(112, 162, 82),
				Enum.Material.Grass
			)
			Kit.placeAt(m, CF.new(60, 0, 100))
			m.Parent = root
			placed.Murph = CF.new(60, 0, 100)
		end
		for _, id in ipairs({ "Hermit", "OldTolly", "CapnMoss", "OldHank" }) do
			local npc = NPCData.Get(id)
			local feet = NPCData.SpotFor(npc, function()
				return nil, nil
			end)
			local at = feet.Position
			local rise = npc.spot.ground
			local y = at.Y
			if rise then
				y = TerrainGen.HeightAt(at.X, at.Z) + rise
			end
			feet = CF.new(at.X, y, at.Z) * feet.Rotation
			Kit.part(
				root,
				"Patch" .. id,
				V3.new(24, 1, 24),
				CF.new(at.X, y - 0.5, at.Z),
				C3.fromRGB(112, 162, 82),
				Enum.Material.Grass
			)
			local m = CharacterArt.Build(npc.look)
			Kit.placeAt(m, feet)
			m.Parent = root
			placed[id] = feet
		end

		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		local result = {
			root = root,
			shadowRadius = 160,
			fov = 40,
			cameras = {
				cam(spot.X + 6, 4.5, spot.Z - 7, spot.X, 3.4, spot.Z, "Rook at the mill, three-quarter"),
				cam(spot.X, 4, spot.Z - 8, spot.X, 3.4, spot.Z, "Rook front (facing the road, the dialogue pose)"),
				cam(spot.X, 4.5, spot.Z + 8, spot.X, 3.4, spot.Z, "Rook from behind"),
				cam(spot.X + 9, 4, spot.Z, spot.X, 3.4, spot.Z, "Rook from the side"),
				cam(-8, 14, 40, spot.X + 6, 4, spot.Z, "the yard from the road"),
			},
		}
		-- Front (facing the player, the dialogue pose), side and back of each of the other four.
		for _, id in ipairs({ "Murph", "Hermit", "OldTolly", "CapnMoss", "OldHank" }) do
			local cf = placed[id]
			local p = cf.Position
			local fwd = cf.LookVector
			local right = cf.RightVector
			local c = V3.new(p.X, p.Y + 3.2, p.Z)
			local function at(v, label)
				table.insert(result.cameras, cam(c.X + v.X, c.Y + 0.8 + v.Y, c.Z + v.Z, c.X, c.Y, c.Z, label))
			end
			at(fwd * 13, id .. " front (facing the player)")
			at(right * 13, id .. " side")
			at(fwd * -13, id .. " back")
		end
		return result
	end,
}
