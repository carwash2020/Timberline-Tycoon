--!strict
-- MaterialSetup (T397): makes the ground show real textures. A MaterialVariant
-- in MaterialService does nothing until a base material is pointed at it, and
-- nothing ever did, so the synced TimberGrass, TimberGround and TimberLeafy
-- never reached the screen and the ground drew as flat colour. Apply() sets
-- the four base-material overrides (Grass, Ground, LeafyGrass, Asphalt) and
-- the terrain's palette colours, once, at server start (MapBuilder).
--
-- Overrides replicate: the client needs nothing. Terrain Decoration stays off
-- (default.project.json). If a variant is missing the override is skipped and
-- the base material keeps its plain look.

local Palette = require(game:GetService("ReplicatedStorage").Shared.Art.Palette)

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

-- Terrain colours: the style guide's palette names (Shared/Art/Palette).
-- TerrainGen.MaterialColors holds the same values for the preview tool; a
-- spec keeps the two equal. Materials with no palette name (Limestone,
-- Sandstone) keep TerrainBuilder's colour.
MaterialSetup.Colors = {
	Grass = "MeadowGrass",
	LeafyGrass = "DeepMeadow",
	Ground = "TrailDirt",
	Mud = "WetMud",
	Sand = "ShoreSand",
	Rock = "CliffRock",
	Snow = "FreshSnow",
	Glacier = "BlueIce",
	Basalt = "AshBasalt",
	Slate = "QuarrySlate",
	CrackedLava = "LavaGlow",
	Cobblestone = "TownCobble",
	Asphalt = "RoadGravel",
} :: { [string]: string }

-- Returns how many overrides were set.
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
		for material, name in pairs(MaterialSetup.Colors) do
			terrain:SetMaterialColor((Enum.Material :: any)[material], Palette.Get(name))
		end
	end
	print(string.format("[MaterialSetup] %d of %d ground texture overrides set", set, #MaterialSetup.Overrides))
	return set
end

return MaterialSetup
