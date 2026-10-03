--!strict
-- ItemMeshData: uploaded Blender meshes for the plot pieces that already
-- have one (the 18 PlotData blueprints, plus the plot sign, corner post
-- and border rail PlotService builds). Collision meshes are not listed:
-- the gameplay part stays the collider. Colours are vertex colours, so a
-- mesh is left white unless a caller tints it. At most 4 visible meshes.

export type MeshRole = "Wood" | "Glass" | "Glow" | "Sign" | "Flag" | "Door"

export type MeshDef = {
	name: string,
	meshId: string,
	size: Vector3,
	role: MeshRole,
}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function mesh(name: string, id: string, size: Vector3, role: MeshRole): MeshDef
	return { name = name, meshId = id, size = size, role = role }
end

local ItemMeshData = {}

ItemMeshData.MaxMeshes = 4

-- Visible meshes only. Stairs is included: its collider is the wedge in
-- PlotData, and this mesh is the flight that wedge walks.
ItemMeshData.Items = {
	Wall = { mesh("Body", "rbxassetid://85233243499195", v(8, 6, 0.6), "Wood") },
	Floor = { mesh("Body", "rbxassetid://134684216163207", v(7.95, 0.4, 7.98), "Wood") },
	Door = {
		mesh("Body", "rbxassetid://121239833575865", v(3.8, 6.3, 0.6), "Wood"),
		mesh("Door", "rbxassetid://71619965421917", v(3.16, 5.95, 0.48), "Door"),
	},
	Window = {
		mesh("Body", "rbxassetid://73677583211835", v(3.8, 2.88, 0.65), "Wood"),
		mesh("Glass", "rbxassetid://132351348411495", v(3.2, 2.4, 0.08), "Glass"),
	},
	Stairs = { mesh("Body", "rbxassetid://81005251088688", v(3.6, 4, 8.05), "Wood") },
	Shed = {
		mesh("Body", "rbxassetid://136215992489717", v(10.1, 6.6, 8.1), "Wood"),
		mesh("Roof", "rbxassetid://130355041655175", v(10.574, 2.471, 8.3), "Wood"),
	},
	WoodSign = {
		mesh("Body", "rbxassetid://75201943310825", v(3.2, 3.9, 0.735), "Wood"),
		mesh("Sign", "rbxassetid://82248576176144", v(3, 1.2, 0.15), "Sign"),
	},
	PaintCan = { mesh("Body", "rbxassetid://96159005518459", v(1.26, 1.565, 1.224), "Wood") },
	Mailbox = { mesh("Body", "rbxassetid://113682027937082", v(0.88, 3.875, 1.45), "Wood") },
	Fence = { mesh("Body", "rbxassetid://97743434575899", v(8.1, 3.16, 0.6), "Wood") },
	FlowerBed = { mesh("Body", "rbxassetid://71406221435175", v(4, 1.295, 4), "Wood") },
	Bench = { mesh("Body", "rbxassetid://125026873129323", v(4, 2.617, 1.543), "Wood") },
	LampPost = {
		mesh("Body", "rbxassetid://122727224889509", v(1.25, 8.425, 1.25), "Wood"),
		mesh("Glow", "rbxassetid://72172329191191", v(0.85, 1, 0.85), "Glow"),
	},
	LogPile = { mesh("Body", "rbxassetid://90576413321443", v(5.974, 2.185, 3.8), "Wood") },
	Flag = {
		mesh("Body", "rbxassetid://102728327572502", v(1, 12.4, 1), "Wood"),
		mesh("Flag", "rbxassetid://118621040752731", v(0.336, 2.4, 3.4), "Flag"),
	},
	Cabin = {
		mesh("Body", "rbxassetid://85865214195600", v(12.94, 12.21, 10.795), "Wood"),
		mesh("Roof", "rbxassetid://93554668994248", v(12.7, 3.65, 11.529), "Wood"),
		mesh("Glow", "rbxassetid://89489461690884", v(11.8, 1.8, 6.15), "Glow"),
	},
	Warehouse = {
		mesh("Body", "rbxassetid://124832442437427", v(16.1, 11.2, 12.575), "Wood"),
		mesh("Roof", "rbxassetid://88260552161622", v(16.98, 1.612, 13.171), "Wood"),
		mesh("Glow", "rbxassetid://139264614078279", v(0.33, 0.42, 0.33), "Glow"),
	},
	AxeRack = { mesh("Body", "rbxassetid://120770468233431", v(6.1, 4.7, 1.75), "Wood") },
	PlotSign = {
		mesh("Body", "rbxassetid://91854520961950", v(8.8, 8.725, 1.2), "Wood"),
		mesh("Sign", "rbxassetid://113789372437689", v(8, 3.5, 0.4), "Sign"),
	},
	PlotCorner = { mesh("Body", "rbxassetid://140687924961400", v(0.95, 3.4, 0.95), "Wood") },
	PlotRail = { mesh("Body", "rbxassetid://97750771801717", v(10, 0.37, 0.42), "Wood") },
} :: { [string]: { MeshDef } }

function ItemMeshData.List(id: string): { MeshDef }
	return ItemMeshData.Items[id] or {}
end

function ItemMeshData.Count(id: string): number
	return #ItemMeshData.List(id)
end

return ItemMeshData
