--!strict
-- MaterialSetup (T397): makes the ground show real textures. A MaterialVariant
-- in MaterialService does nothing until a base material is pointed at it, and
-- nothing ever did, so the synced TimberGrass, TimberGround and TimberLeafy
-- never reached the screen and the ground drew as flat colour. Apply() sets
-- the four base-material overrides (Grass, Ground, LeafyGrass, Asphalt) and
-- the terrain's palette colours, once, at server start (MapBuilder).
--
-- T402: this is also the only writer of the terrain's material colours.
--
-- Overrides replicate: the client needs nothing. Terrain Decoration stays off
-- (default.project.json). If a variant is missing the override is skipped and
-- the base material keeps its plain look.

local MaterialSetup = {}

export type Override = { material: string, variant: string, studsPerTile: number }

-- StudsPerTile is also in each variant's model.json (src/MaterialService): a
-- spec keeps the two equal. Grass 10, Ground 12, LeafyGrass 8 as settled;
-- Asphalt 8 is this build's choice (the Art Director's value was not given),
-- one number to change.
MaterialSetup.Overrides = {
	{ material = "Grass", variant = "TimberGrass", studsPerTile = 10 },
	{ material = "Ground", variant = "TimberGround", studsPerTile = 12 },
	{ material = "LeafyGrass", variant = "TimberLeafy", studsPerTile = 8 },
	{ material = "Asphalt", variant = "TimberAsphalt", studsPerTile = 8 },
} :: { Override }

-- Terrain colours (T402): the one place the terrain's palette is written.
-- TerrainBuilder no longer touches them (it used to set a second palette
-- right after this one, so the two fought and the later one won).
-- TerrainGen.MaterialColors holds the same values for the preview tool and
-- WorldPlan; a spec keeps the two equal. Every material TerrainGen writes
-- has a row, so none is left at the engine's stock colour. Pavement is
-- absent on purpose: nothing writes it (the town's roads are parts now).
-- Mud and Rock keep the colours they had; the grey that bled onto the grass
-- is fixed by what lies under the grass (TerrainGen.SubMaterial), not here.
MaterialSetup.Colors = {
	Grass = Color3.fromRGB(110, 159, 69), -- #6E9F45
	LeafyGrass = Color3.fromRGB(90, 138, 60), -- #5A8A3C
	Ground = Color3.fromRGB(142, 108, 74), -- #8E6C4A
	Mud = Color3.fromRGB(90, 74, 62), -- #5A4A3E
	Rock = Color3.fromRGB(126, 118, 108), -- #7E766C
	Slate = Color3.fromRGB(124, 122, 106), -- #7C7A6A
	Asphalt = Color3.fromRGB(85, 88, 90), -- #55585A
	-- Connor's values (21 October 2026) for every other material the terrain writes.
	Sand = Color3.fromRGB(216, 198, 154), -- #D8C69A
	Snow = Color3.fromRGB(238, 243, 247), -- #EEF3F7
	Glacier = Color3.fromRGB(169, 211, 230), -- #A9D3E6
	Basalt = Color3.fromRGB(58, 52, 51), -- #3A3433
	CrackedLava = Color3.fromRGB(255, 106, 30), -- #FF6A1E
	Cobblestone = Color3.fromRGB(156, 149, 138), -- #9C958A
	Limestone = Color3.fromRGB(78, 74, 54), -- #4E4A36
	Sandstone = Color3.fromRGB(200, 105, 62), -- #C8693E
} :: { [string]: Color3 }

-- Returns how many overrides were set. (Shared/ColorMapGuard then checks the
-- variants' ColorMaps on a thread of its own.)
function MaterialSetup.Apply(materialService: any, terrain: any): number
	local set = 0
	for _, o in ipairs(MaterialSetup.Overrides) do
		local ok, err = pcall(function()
			if materialService:FindFirstChild(o.variant) == nil then
				error("no MaterialVariant named " .. o.variant)
			end
			materialService:SetBaseMaterialOverride((Enum.Material :: any)[o.material], o.variant)
		end)
		if ok then
			set += 1
		else
			warn(string.format("[MaterialSetup] %s override skipped: %s", o.material, tostring(err)))
		end
	end
	if terrain then
		for material, color in pairs(MaterialSetup.Colors) do
			terrain:SetMaterialColor((Enum.Material :: any)[material], color)
		end
	end
	print(string.format("[MaterialSetup] %d of %d ground texture overrides set", set, #MaterialSetup.Overrides))
	return set
end

return MaterialSetup
