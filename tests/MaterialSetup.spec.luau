--!nocheck
-- MaterialSetup (T397, T402): Grass, Ground, LeafyGrass and Asphalt are pointed
-- at their MaterialVariants (nothing did before, so the ground drew flat), the
-- variants carry the settled tiling, and the terrain's colours are written here
-- and nowhere else (every material TerrainGen writes has a row).
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local MaterialSetup = t.server("MaterialSetup")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")

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

	-- Every row of the ticket's table (T402), by hex.
	local WANT = {
		Grass = "6E9F45",
		LeafyGrass = "5A8A3C",
		Ground = "8E6C4A",
		Mud = "5A4A3E", -- unchanged: the colour it had
		Rock = "7E766C", -- unchanged: the colour it had
		Slate = "5B5650",
		Asphalt = "A8A49C",
		Sand = "D8C69A",
		Snow = "EEF3F7",
		Glacier = "A9D3E6",
		Basalt = "3A3433",
		CrackedLava = "FF6A1E",
		Cobblestone = "9C958A",
		Limestone = "4E4A36",
		Sandstone = "C8693E",
	}

	t.test("the terrain palette: every row, written by Apply, equal to TerrainGen.MaterialColors", function()
		local terrain = fakeTerrain()
		MaterialSetup.Apply(fakeService(ALL), terrain)
		for material, hex in pairs(WANT) do
			local got = terrain.colors[material]
			t.ok(got ~= nil, material .. " colour set")
			t.eq(got:ToHex(), hex, material)
			t.eq(TerrainGen.MaterialColors[material]:ToHex(), got:ToHex(), material .. " equals TerrainGen's")
		end
		for material in pairs(terrain.colors) do
			t.ok(WANT[material], material .. " is a row of the table")
		end
		t.eq(MaterialSetup.Colors.Pavement, nil, "the Pavement row is gone (nothing writes it)")
		t.eq(TerrainGen.MaterialColors.Pavement, nil)
	end)

	-- Walks src/ and returns every .luau file's path.
	local function luauFiles(dir, out)
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				luauFiles(path, out)
			elseif string.sub(name, -5) == ".luau" then
				table.insert(out, path)
			end
		end
		return out
	end
	local function code(path)
		-- The file without its comments (a `--` to the end of the line).
		local lines = {}
		for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
			table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
		end
		return table.concat(lines, "\n")
	end

	t.test("MaterialSetup is the only module that calls SetMaterialColor", function()
		local callers = {}
		for _, path in ipairs(luauFiles("src", {})) do
			if string.find(code(path), "SetMaterialColor", 1, true) then
				table.insert(callers, path)
			end
		end
		t.eq(callers, { "src/ServerScriptService/MaterialSetup.luau" })
	end)

	t.test("every material the terrain is written with has a colour row", function()
		local skip = { Water = true, Air = true } -- water has its own colour (TerrainBuilder.setLook), air none
		local names = {}
		for _, item in ipairs(t.roblox.Enum.Material:GetEnumItems()) do
			names[item.Name] = true
		end
		local written = {}
		local function scan(path, onlyTerrainLines)
			local src = code(path)
			if onlyTerrainLines then
				for line in string.gmatch(src, "[^\n]+") do
					if string.find(line, "Terrain", 1, true) or string.find(line, "terrain", 1, true) then
						for name in string.gmatch(line, "Enum%.Material%.(%w+)") do
							written[name] = path
						end
					end
				end
			else
				for literal in string.gmatch(src, '"(%w+)"') do
					if names[literal] then
						written[literal] = path
					end
				end
			end
		end
		-- Every string TerrainGen could answer with that is a material's name (and the two writers' own).
		scan("src/ReplicatedStorage/Shared/World/TerrainGen.luau", false)
		scan("src/ServerScriptService/TerrainBuilder.luau", true)
		scan("src/ServerScriptService/MapBuilder.server.luau", true)
		local count = 0
		for name, path in pairs(written) do
			if not skip[name] then
				count += 1
				t.ok(
					MaterialSetup.Colors[name] ~= nil,
					name .. " (written in " .. path .. ") has a SetMaterialColor row"
				)
			end
		end
		t.ok(count >= 12, "the scan found the terrain's materials: " .. count)
		-- And what the sampler actually answers over the map.
		for x = -1000, 1000, 50 do
			for z = -1000, 1000, 50 do
				local _, surface = TerrainGen.Sample(x, z)
				t.ok(MaterialSetup.Colors[surface] ~= nil, surface .. " has a row")
			end
		end
	end)

	t.test("each ground variant exists, is applied, and GetBaseMaterialOverride returns it", function()
		local svc = fakeService(ALL)
		function svc:GetBaseMaterialOverride(material)
			return self.overrides[material.Name]
		end
		MaterialSetup.Apply(svc, fakeTerrain())
		for _, o in ipairs(MaterialSetup.Overrides) do
			t.ok(fs.isFile("src/MaterialService/" .. o.variant .. ".model.json"), o.variant .. " is in the project")
			t.eq(svc:GetBaseMaterialOverride(t.roblox.Enum.Material[o.material]), o.variant, o.material)
		end
		t.eq(#MaterialSetup.Overrides, 4)
	end)

	-- The ColorMap assets the ground variants may use (ASSETS.md lists them as textures). A new one is a
	-- decision: add it here on purpose.
	local COLORMAP_ALLOWLIST = {
		["rbxassetid://9920551868"] = true, -- TimberGrass
		["rbxassetid://9920554482"] = true, -- TimberGround
		["rbxassetid://9920557906"] = true, -- TimberLeafy
	}

	t.test("the variants tile organically; each ColorMap is an allowlisted asset", function()
		for _, o in ipairs(MaterialSetup.Overrides) do
			local def = serde.decode("json", fs.readFile("src/MaterialService/" .. o.variant .. ".model.json"))
			t.eq(def.properties.MaterialPattern, "Organic", o.variant)
			local map = def.properties.ColorMap
			if map ~= nil then
				t.ok(COLORMAP_ALLOWLIST[map], o.variant .. "'s ColorMap " .. tostring(map) .. " is not allowlisted")
			end
		end
		for id in pairs(COLORMAP_ALLOWLIST) do
			t.ok(string.match(id, "^rbxassetid://%d+$"), id .. " is an asset id")
		end
		t.eq(MaterialSetup.ColorMapAllowlist, nil, "no asset ids duplicated in the module")
	end)

	t.test("a ColorMap that fails to load is cleared, so the flat colour stays", function()
		local ColorMapGuard = t.shared("ColorMapGuard")
		local Instance = t.roblox.Instance
		local function variant(name, map)
			local v = Instance.new("MaterialVariant")
			v.Name = name
			v.ColorMap = map
			return v
		end
		local grass, ground =
			variant("TimberGrass", "rbxassetid://9920551868"), variant("TimberGround", "rbxassetid://9920554482")
		local bare = variant("TimberAsphalt", "")
		local svc = Instance.new("Folder")
		for _, v in ipairs({ grass, ground, bare }) do
			v.Parent = svc
		end
		local Status = t.roblox.Enum.AssetFetchStatus
		local provider = {
			PreloadAsync = function(_, list, callback)
				callback("x", if list[1] == grass then Status.Failure else Status.Success)
			end,
		}
		t.eq(ColorMapGuard.Run(svc, provider), 1)
		t.eq(grass.ColorMap, "", "the failed map is cleared")
		t.eq(ground.ColorMap, "rbxassetid://9920554482", "a map that loaded stays")
		t.eq(bare.ColorMap, "", "a variant with no map is left alone")
		-- A provider that throws counts as a failure; a time-out too.
		local timedOut = variant("TimberLeafy", "rbxassetid://9920557906")
		timedOut.Parent = svc
		local slow = {
			PreloadAsync = function(_, list, callback)
				callback("x", Status.TimedOut)
			end,
		}
		t.eq(ColorMapGuard.Run(svc, slow), 2, "the two that still had a map")
		-- No MaterialService to read: a warning, not an error.
		t.eq(ColorMapGuard.Run(nil, provider), 0)
	end)

	t.test("grass, asphalt and dirt each resolve to a named MaterialVariant", function()
		local overridden = {}
		for _, o in ipairs(MaterialSetup.Overrides) do
			overridden[o.material] = o.variant
		end
		-- The country roads are Asphalt terrain; the meadow is Grass, the forest floor LeafyGrass, bare earth Ground.
		t.eq(TerrainGen.GravelMaterial, "Asphalt")
		for _, material in ipairs({ "Asphalt", "Grass", "LeafyGrass", "Ground" }) do
			t.ok(overridden[material], material .. " has a MaterialVariant")
		end
		local seen = {}
		for x = -900, 900, 60 do
			for z = -900, 900, 60 do
				local _, surface = TerrainGen.Sample(x, z)
				seen[surface] = true
			end
		end
		t.ok(seen.Grass or seen.LeafyGrass, "the map has grass")
	end)

	t.test("the lot has no dirt shoulder and no road voxels: its pavement is TownGround's part", function()
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local lot = WorldLayout.ParkingLot
		local spots =
			{ { lot.x0 + 5, lot.z0 + 5 }, { lot.x1 - 5, lot.z1 - 5 }, { lot.x0 - 1, lot.z0 + 40 }, { lot.x1 + 1, 20 } }
		for _, p in ipairs(spots) do
			local _, surface = TerrainGen.Sample(p[1], p[2])
			t.ok(surface ~= "Asphalt", "the lot's terrain is not painted Asphalt: " .. surface)
		end
	end)

	t.test("MapBuilder runs MaterialSetup before the terrain is written", function()
		local src = fs.readFile("src/ServerScriptService/MapBuilder.server.luau")
		local at = string.find(src, "MaterialSetup.Apply", 1, true)
		local terrain = string.find(src, 'step("3. Terrain"', 1, true)
		t.ok(at and terrain and at < terrain, "applied before step 3")
	end)
end
