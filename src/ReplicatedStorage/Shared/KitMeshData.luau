--!strict
-- KitMeshData: uploaded meshes for the building kit. One row per piece.
-- CollisionFidelity is chosen here and passed into MeshKit at creation;
-- it cannot be changed on the MeshPart afterwards.
-- A Col mesh is an invisible collider. Wood, Trim and Glass are visual
-- except RoofCorner's Wood (Hull, it has no Col) and the door and gate
-- leaves (Box). DoorWall8 has no Col: the jambs are parts.

local V3 = Vector3.new

export type Fidelity = "Box" | "Hull"
export type Role = "Wood" | "Trim" | "Glass" | "Door" | "Col"

export type Mesh = {
	name: string,
	meshId: number,
	size: Vector3,
	role: Role,
	fidelity: Fidelity,
	collide: boolean, -- this mesh is a collider
	offset: Vector3, -- pivot, in the piece's ground space
	swing: boolean?, -- the client tweens this one
}

local KitMeshData = {}

local function box(id: number, size: Vector3, offset: Vector3): Mesh
	return {
		name = "Col",
		meshId = id,
		size = size,
		role = "Col",
		fidelity = "Box",
		collide = true,
		offset = offset,
	}
end

local function hull(id: number, size: Vector3, offset: Vector3): Mesh
	local mesh = box(id, size, offset)
	mesh.fidelity = "Hull"
	return mesh
end

local function wood(id: number, size: Vector3, offset: Vector3?): Mesh
	return {
		name = "Wood",
		meshId = id,
		size = size,
		role = "Wood",
		fidelity = "Box",
		collide = false,
		offset = offset or Vector3.zero,
	}
end

-- id, tris (for the PR table), cap, meshes
KitMeshData.Pieces = {
	Wall4 = {
		tris = 120,
		cap = 250,
		meshes = { wood(109029592716076, V3(4, 6, 1)), box(128457368602839, V3(4, 6, 1), V3(0, 3, 0)) },
	},
	Wall = {
		tris = 120,
		cap = 250,
		meshes = { wood(99465405713921, V3(8, 6, 1)), box(126041521825452, V3(8, 6, 1), V3(0, 3, 0)) },
	},
	Wall12 = {
		tris = 132,
		cap = 250,
		meshes = { wood(120660751744175, V3(12, 6, 1)), box(78552137472446, V3(12, 6, 1), V3(0, 3, 0)) },
	},
	TallWall4 = {
		tris = 168,
		cap = 250,
		meshes = { wood(140520576025638, V3(4, 10, 1)), box(106581335446864, V3(4, 10, 1), V3(0, 5, 0)) },
	},
	TallWall8 = {
		tris = 168,
		cap = 250,
		meshes = { wood(99726500181036, V3(8, 10, 1)), box(116870188640151, V3(8, 10, 1), V3(0, 5, 0)) },
	},
	HalfWall8 = {
		tris = 96,
		cap = 250,
		meshes = { wood(108948940119854, V3(8, 3, 1)), box(115724309287354, V3(8, 3, 1), V3(0, 1.5, 0)) },
	},
	DoorWall8 = {
		tris = 216,
		cap = 250,
		meshes = { wood(84108857863628, V3(8, 6, 1)) },
	},
	WindowWall8 = {
		tris = 240,
		cap = 250,
		meshes = { wood(81216731170475, V3(8, 6, 1)), box(126041521825452, V3(8, 6, 1), V3(0, 3, 0)) },
	},
	Door = {
		tris = 120,
		cap = 500,
		meshes = {
			wood(92614532031627, V3(4, 6, 1)),
			{
				name = "Door",
				meshId = 85140047871902,
				size = V3(3.2, 6, 0.4),
				role = "Door" :: Role,
				fidelity = "Box" :: Fidelity,
				collide = true,
				offset = V3(0, 3, 0),
				swing = true,
			},
		},
	},
	Window = {
		tris = 108,
		cap = 500,
		meshes = {
			wood(111557478178184, V3(4, 3, 1), V3(0, 3.5, 0)),
			{
				name = "Glass",
				meshId = 74892568048481,
				size = V3(3.2, 2.4, 0.08),
				role = "Glass" :: Role,
				fidelity = "Box" :: Fidelity,
				collide = false,
				offset = V3(0, 3.5, 0),
			},
			box(133911836509151, V3(4, 3, 0.3), V3(0, 3.5, 0)),
		},
	},
	Floor4 = {
		tris = 84,
		cap = 250,
		meshes = { wood(104952124701042, V3(4, 0.4, 4)), box(84015618100992, V3(4, 0.4, 4), V3(0, 0.2, 0)) },
	},
	Floor = {
		tris = 144,
		cap = 250,
		meshes = { wood(111559217063343, V3(8, 0.4, 8)), box(140616724444561, V3(8, 0.4, 8), V3(0, 0.2, 0)) },
	},
	Foundation8 = {
		tris = 216,
		cap = 250,
		meshes = {
			wood(138592277198174, V3(8, 2, 8)),
			{
				name = "Trim",
				meshId = 132080866023484,
				size = V3(8, 2, 8),
				role = "Trim" :: Role,
				fidelity = "Box" :: Fidelity,
				collide = false,
				offset = Vector3.zero,
			},
			box(115113425380693, V3(8, 2, 8), V3(0, 1, 0)),
		},
	},
	Stairs = {
		tris = 280,
		cap = 500,
		meshes = { wood(135152345128364, V3(4, 4, 8)), hull(121441762172695, V3(4, 4, 8), V3(0, 2, 0)) },
	},
	Ramp8 = {
		tris = 40,
		cap = 500,
		meshes = { wood(79595962219470, V3(4, 2, 8)), hull(87909791831811, V3(4, 2, 8), V3(0, 1, 0)) },
	},
	FlatRoof8 = {
		tris = 156,
		cap = 500,
		meshes = { wood(139892769635979, V3(9, 0.4, 9)), box(140616724444561, V3(8, 0.4, 8), V3(0, 0.2, 0)) },
	},
	SlopedRoof8 = {
		tris = 192,
		cap = 500,
		meshes = { wood(98186309048933, V3(9, 3, 5)), hull(108430978098778, V3(8, 3, 4), V3(0, 1.5, 0)) },
	},
	RoofRidge8 = {
		tris = 68,
		cap = 500,
		meshes = {
			wood(72598895169696, V3(9, 0.8, 2), V3(0, 2.475, 0)),
			box(133341052456224, V3(8, 0.8, 1), V3(0, 2.875, 0)),
		},
	},
	RoofCorner = {
		tris = 98,
		cap = 500,
		meshes = {
			{
				name = "Wood",
				meshId = 134460693041565,
				size = V3(4, 3, 4),
				role = "Wood" :: Role,
				fidelity = "Hull" :: Fidelity,
				collide = true,
				offset = V3(0, 1.5, 0),
			},
		},
	},
	Fence = {
		tris = 224,
		cap = 250,
		meshes = { wood(112203689695205, V3(8, 3, 1)), box(115724309287354, V3(8, 3, 1), V3(0, 1.5, 0)) },
	},
	FenceGate4 = {
		tris = 160,
		cap = 500,
		meshes = {
			wood(102029522927110, V3(4, 3, 1)),
			{
				name = "Door",
				meshId = 138609336116860,
				size = V3(3.2, 3, 0.4),
				role = "Door" :: Role,
				fidelity = "Box" :: Fidelity,
				collide = true,
				offset = V3(0, 1.5, 0),
				swing = true,
			},
		},
	},
	Post = {
		tris = 80,
		cap = 250,
		meshes = { wood(82575072978283, V3(1, 6, 1)), box(99945088655922, V3(1, 6, 1), V3(0, 3, 0)) },
	},
	Beam8 = {
		tris = 98,
		cap = 250,
		meshes = { wood(95905082010293, V3(8, 1, 1)), box(103427372287639, V3(8, 1, 1), V3(0, 0.5, 0)) },
	},
	Railing8 = {
		tris = 228,
		cap = 250,
		meshes = { wood(136485582140109, V3(8, 3, 1)), box(115724309287354, V3(8, 3, 1), V3(0, 1.5, 0)) },
	},
} :: {
	[string]: {
		tris: number,
		cap: number,
		meshes: { Mesh },
	},
}

function KitMeshData.Get(id: string)
	return KitMeshData.Pieces[id]
end

return KitMeshData
