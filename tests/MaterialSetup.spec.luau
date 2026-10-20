--!nocheck
-- MaterialSetup (T397): Grass, Ground, LeafyGrass and Asphalt are pointed at
-- their MaterialVariants (nothing did before, so the ground drew flat), the
-- variants carry the settled tiling, and the terrain colours are the palette's.
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local MaterialSetup = t.server("MaterialSetup")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")

	local function fakeService(variants)
		local svc = { overrides = {} }
		function svc:FindFirstChild(name)
			return if variants[name] then variants[name] else nil
		end
		function svc:SetBaseMaterialOverride(material, name)
			self.overrides[material.Name] = name
		end
		return svc
	end
	local function fakeTerrain()
		local terrain = { colors = {} }
		function terrain:SetMaterialColor(material, color)
			self.colors[material.Name] = color
		end
		return terrain
	end
	local ALL = { TimberGrass = true, TimberGround = true, TimberLeafy = true, TimberAsphalt = true }

	t.test("Apply sets all four base-material overrides", function()
		local svc, terrain = fakeService(ALL), fakeTerrain()
		t.eq(MaterialSetup.Apply(svc, terrain), 4)
		t.eq(svc.overrides.Grass, "TimberGrass")
		t.eq(svc.overrides.Ground, "TimberGround")
		t.eq(svc.overrides.LeafyGrass, "TimberLeafy")
		t.eq(svc.overrides.Asphalt, "TimberAsphalt")
	end)

	t.test("a missing variant is skipped, not an error, and the rest still apply", function()
		local svc = fakeService({ TimberGrass = true })
		t.eq(MaterialSetup.Apply(svc, fakeTerrain()), 1)
		t.eq(svc.overrides.Grass, "TimberGrass")
		t.eq(svc.overrides.Asphalt, nil)
	end)

	t.test("every override names a variant file with that base material and the settled StudsPerTile", function()
		local settled = { Grass = 10, Ground = 12, LeafyGrass = 8, Asphalt = 8 }
		t.eq(#MaterialSetup.Overrides, 4)
		for _, o in ipairs(MaterialSetup.Overrides) do
			local def = serde.decode("json", fs.readFile("src/MaterialService/" .. o.variant .. ".model.json"))
			t.eq(def.className, "MaterialVariant", o.variant)
			t.eq(def.properties.BaseMaterial, o.material, o.variant .. "'s base material")
			t.eq(def.properties.StudsPerTile, settled[o.material], o.variant .. "'s tiling (json)")
			t.eq(o.studsPerTile, settled[o.material], o.variant .. "'s tiling (setup)")
			-- No flat SmoothPlastic ground: a ground variant is organic or a plain tile.
			t.ok(def.properties.MaterialPattern == "Organic", o.variant .. " tiles organically")
		end
	end)

	t.test("terrain colours are the palette's, and match TerrainGen.MaterialColors", function()
		local terrain = fakeTerrain()
		MaterialSetup.Apply(fakeService(ALL), terrain)
		for material, name in pairs(MaterialSetup.Colors) do
			local got = terrain.colors[material]
			t.ok(got ~= nil, material .. " colour set")
			t.eq(got:ToHex(), Palette.Get(name):ToHex(), material)
			t.eq(TerrainGen.MaterialColors[material]:ToHex(), got:ToHex(), material .. " equals TerrainGen's")
		end
	end)

	t.test("grass, asphalt and dirt each resolve to a named MaterialVariant; no flat plastic ground", function()
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local Enum = t.roblox.Enum
		local overridden = {}
		for _, o in ipairs(MaterialSetup.Overrides) do
			overridden[o.material] = o.variant
		end
		-- The roads, the town's paths and the lot's slab are Asphalt; the meadow is Grass,
		-- the forest floor LeafyGrass, bare earth Ground.
		t.eq(TerrainGen.GravelMaterial, "Asphalt")
		t.eq(WorldLayout.RoadMaterial, "Asphalt")
		for _, material in ipairs({ "Asphalt", "Grass", "LeafyGrass", "Ground" }) do
			t.ok(overridden[material], material .. " has a MaterialVariant")
		end
		-- Every terrain surface the map paints on open ground resolves to one of them.
		local seen = {}
		for x = -900, 900, 60 do
			for z = -900, 900, 60 do
				local _, surface = TerrainGen.Sample(x, z)
				seen[surface] = true
			end
		end
		for _, name in ipairs({ "Grass", "LeafyGrass", "Ground", "Asphalt" }) do
			t.ok(overridden[name], name .. " is overridden")
		end
		t.ok(seen.Grass or seen.LeafyGrass, "the map has grass")
		-- The lot's ground parts: Asphalt and Ground, never SmoothPlastic.
		for _, p in ipairs(BuildingArt.ParkingLot(WorldLayout.ParkingLot):GetChildren()) do
			t.ok(
				p.Material == Enum.Material.Asphalt or p.Material == Enum.Material.Ground,
				p.Name .. " is a textured ground material"
			)
		end
	end)

	t.test("T397 adds at most 200 parts: the lot's ground and one curb a stall", function()
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local lotParts = #BuildingArt.ParkingLot(WorldLayout.ParkingLot):GetChildren()
		local curbs = #WorldPlan.Town().parkingSlots
		t.eq(lotParts, 5)
		t.eq(curbs, 13)
		t.ok(lotParts + curbs <= 200, "parts added: " .. (lotParts + curbs))
	end)

	t.test("MapBuilder runs MaterialSetup before the terrain is written", function()
		local src = fs.readFile("src/ServerScriptService/MapBuilder.server.luau")
		local at = string.find(src, "MaterialSetup.Apply", 1, true)
		local terrain = string.find(src, 'step("3. Terrain"', 1, true)
		t.ok(at and terrain and at < terrain, "applied before step 3")
	end)
end
