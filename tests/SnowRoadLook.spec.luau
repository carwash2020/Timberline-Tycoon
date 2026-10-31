--!nocheck
-- T416 item 6: the snow road is the town street: Asphalt, RoadGravel #A8A49C. Both the terrain under the
-- Snow Road and the solid Skyroot deck on its north end. Written first.
return function(t)
	local roblox = t.roblox
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local TownGround = t.load("ReplicatedStorage/Shared/World/TownGround")
	local TravelArt = t.load("ReplicatedStorage/Shared/Art/TravelArt")
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")

	t.test("the town street colour and material are the reference: Asphalt, #A8A49C", function()
		t.eq(WorldLayout.RoadMaterial, "Asphalt")
		t.eq(TownGround.RoadColor, Kit.hex("#A8A49C"))
		t.eq(Palette.RoadGravel, Kit.hex("#A8A49C"))
		t.eq(TerrainGen.MaterialColors.Asphalt, Kit.hex("#A8A49C"))
	end)

	t.test("every Skyroot deck part is the town street's material and colour", function()
		local model = TravelArt.SkyrootRoad()
		local decks = 0
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == "Deck" then
				decks += 1
				t.eq(d.Material.Name, WorldLayout.RoadMaterial, "deck material")
				t.eq(d.Color, TownGround.RoadColor, "deck colour")
			end
		end
		t.ok(decks > 5, "the climb has deck parts: " .. decks)
	end)

	t.test("the terrain under the Snow Road bed is Asphalt all the way up, snow region included", function()
		local road
		for _, r in ipairs(WorldLayout.Roads) do
			if r.name == "SnowRoad" then
				road = r
			end
		end
		local pts = road.points
		local inSnow, bad = 0, {}
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local len = (b - a).Magnitude
			local dir = (b - a).Unit
			for s = 0, len, 6 do
				local p = a + (b - a) * (s / len)
				for _, off in ipairs({ -12, -6, 0, 6, 12 }) do
					local x, z = p.X - dir.Y * off, p.Y + dir.X * off
					if z > 520 and z < 740 then
						inSnow += 1
						local h = TerrainGen.HeightAt(x, z)
						local m = TerrainGen.SurfaceMaterial(x, z, h, TerrainGen.SlopeAt(x, z))
						if m ~= WorldLayout.RoadMaterial then
							table.insert(bad, string.format("(%d,%d) %s", x, z, m))
						end
					end
				end
			end
		end
		t.ok(inSnow > 100, "samples in the snow region: " .. inSnow)
		t.eq(#bad, 0, table.concat(bad, "; "))
	end)
end
