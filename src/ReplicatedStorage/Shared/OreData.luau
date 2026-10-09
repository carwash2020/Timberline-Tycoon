--!strict
-- OreData: how an ore vein looks. No prices and no recipes. Lane M owns
-- mining. NatureArt tints vein meshes from here, and the part-built
-- fallback uses the same row when the caller passes an ore id.
-- Heartstone is the only ore with a glow mesh. Opal only gets a dim light.

local OreData = {}

export type Ore = {
	id: string,
	name: string,
	color: Color3,
	material: Enum.Material,
	glow: boolean,
}

local ores: { [string]: Ore } = {
	coal = {
		id = "coal",
		name = "Coal",
		color = Color3.fromRGB(12, 12, 14),
		material = Enum.Material.Slate,
		glow = false,
	},
	copper = {
		id = "copper",
		name = "Copper",
		color = Color3.fromRGB(232, 120, 36),
		material = Enum.Material.Metal,
		glow = false,
	},
	iron = {
		id = "iron",
		name = "Iron",
		color = Color3.fromRGB(176, 64, 42),
		material = Enum.Material.CorrodedMetal,
		glow = false,
	},
	silver = {
		id = "silver",
		name = "Silver",
		color = Color3.fromRGB(232, 236, 242),
		material = Enum.Material.Foil,
		glow = false,
	},
	gold = {
		id = "gold",
		name = "Gold",
		color = Color3.fromRGB(250, 198, 28),
		material = Enum.Material.Metal,
		glow = false,
	},
	opal = {
		id = "opal",
		name = "Opal",
		color = Color3.fromRGB(214, 206, 230),
		material = Enum.Material.SmoothPlastic,
		glow = true,
	},
	heartstone = {
		id = "heartstone",
		name = "Heartstone",
		color = Color3.fromRGB(255, 70, 118),
		material = Enum.Material.Neon,
		glow = true,
	},
}

function OreData.Get(oreId: string): Ore?
	return ores[oreId]
end

function OreData.Ids(): { string }
	local ids: { string } = {}
	for id in pairs(ores) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return OreData
