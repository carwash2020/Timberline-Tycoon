--!strict
-- Rock meshes. meshId is the MeshPart under ReplicatedStorage.MeshTemplates,
-- the same slot pattern as AxeModels. 0 means that piece is not uploaded:
-- NatureArt keeps the part build and logs it once.
-- Numbers come from each Blender rock's stats.json (uploaded 2026-10-08).
-- Every kind has an A and a B variant. `hostCentre` is the MeshHost bounding
-- box centre above the rock's ground pivot. A piece's `offset` is the
-- distance from the MeshHost centre to that piece's centre, unrotated, in
-- studs. NatureArt places MeshHost at pivot * CFrame.new(hostCentre * scale)
-- and every other piece at MeshHost.CFrame * CFrame.new(offset * scale).
-- Glow is the heartstone emissive piece only. Moss and Snow are the caps.

local RockModels = {}

export type Piece = { meshId: number, size: Vector3, offset: Vector3 }

export type RockMesh = {
	hostCentre: Vector3,
	Host: Piece,
	Moss: Piece,
	Snow: Piece,
	Vein1: Piece,
	Vein2: Piece,
	Glow: Piece,
}

export type Variant = "A" | "B"

RockModels.Shapes = { "Boulder", "CrackedBoulder", "Spire", "Slab", "PebbleCluster", "Outcrop" }
RockModels.Variants = { "A", "B" }
RockModels.PieceKeys = { "Host", "Vein1", "Vein2", "Moss", "Snow", "Glow" }

local rocks: { [string]: { [string]: RockMesh } } = {
	Boulder = {
		A = {
			hostCentre = Vector3.new(0, 1.01, 0),
			Host = { meshId = 80686921861072, size = Vector3.new(3.422, 2.02, 2.394), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 135285101472759,
				size = Vector3.new(1.688, 1.532, 2.144),
				offset = Vector3.new(-0.521, -0.1, 0.066),
			},
			Vein2 = {
				meshId = 102587715074861,
				size = Vector3.new(1.62, 1.878, 2.082),
				offset = Vector3.new(0.153, 0.073, -0.026),
			},
			Moss = {
				meshId = 108571714472065,
				size = Vector3.new(3.23, 1.616, 2.323),
				offset = Vector3.new(-0.047, 0.278, 0.002),
			},
			Snow = {
				meshId = 78056572803123,
				size = Vector3.new(3.532, 1.981, 2.646),
				offset = Vector3.new(-0.082, 0.237, -0.022),
			},
			Glow = {
				meshId = 104109068749289,
				size = Vector3.new(3.107, 2.634, 2.279),
				offset = Vector3.new(-0.665, 0.42, 0.041),
			},
		},
		B = {
			hostCentre = Vector3.new(0, 0.865, 0),
			Host = { meshId = 135954677451616, size = Vector3.new(3.808, 1.73, 2.814), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 81217018152748,
				size = Vector3.new(1.733, 1.381, 2.311),
				offset = Vector3.new(-0.007, -0.057, 0.177),
			},
			Vein2 = {
				meshId = 130743362864832,
				size = Vector3.new(1.569, 1.622, 2.22),
				offset = Vector3.new(0.752, 0.063, 0.116),
			},
			Moss = {
				meshId = 118121899916712,
				size = Vector3.new(3.614, 1.349, 2.273),
				offset = Vector3.new(0.017, 0.264, 0.204),
			},
			Snow = {
				meshId = 117316128539352,
				size = Vector3.new(3.984, 1.892, 3.042),
				offset = Vector3.new(0.015, 0.145, -0.016),
			},
			Glow = {
				meshId = 120441451290084,
				size = Vector3.new(3.106, 2.754, 2.397),
				offset = Vector3.new(-0.043, 0.603, 0.174),
			},
		},
	},
	CrackedBoulder = {
		A = {
			hostCentre = Vector3.new(0, 0.988, 0),
			Host = { meshId = 123515393937777, size = Vector3.new(3.006, 1.975, 2.354), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 134764809615746,
				size = Vector3.new(1.608, 1.372, 1.983),
				offset = Vector3.new(-0.641, -0.135, 0.083),
			},
			Vein2 = {
				meshId = 132475579395371,
				size = Vector3.new(1.369, 1.25, 1.819),
				offset = Vector3.new(0.761, -0.169, 0.073),
			},
			Moss = {
				meshId = 82487395045845,
				size = Vector3.new(2.843, 1.348, 1.9),
				offset = Vector3.new(-0.042, 0.388, 0.161),
			},
			Snow = {
				meshId = 122975660028978,
				size = Vector3.new(3.17, 2.077, 2.615),
				offset = Vector3.new(0.031, 0.17, -0.019),
			},
			Glow = {
				meshId = 101286265773616,
				size = Vector3.new(3.606, 2.211, 2.042),
				offset = Vector3.new(-0.412, 0.277, 0.079),
			},
		},
		B = {
			hostCentre = Vector3.new(0, 0.955, 0),
			Host = { meshId = 100630014533328, size = Vector3.new(2.92, 1.909, 2.392), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 93012071548500,
				size = Vector3.new(1.958, 1.203, 2.052),
				offset = Vector3.new(-0.485, -0.059, 0.084),
			},
			Vein2 = {
				meshId = 131449379256182,
				size = Vector3.new(1.749, 1.369, 1.981),
				offset = Vector3.new(0.574, -0.099, -0.145),
			},
			Moss = {
				meshId = 95470563986109,
				size = Vector3.new(2.913, 1.496, 1.946),
				offset = Vector3.new(-0.017, 0.263, 0.135),
			},
			Snow = {
				meshId = 85402746195194,
				size = Vector3.new(3.15, 1.948, 2.587),
				offset = Vector3.new(-0.028, 0.166, -0.049),
			},
			Glow = {
				meshId = 102541556185071,
				size = Vector3.new(3.631, 2.21, 2.268),
				offset = Vector3.new(-0.39, 0.316, -0.002),
			},
		},
	},
	Outcrop = {
		A = {
			hostCentre = Vector3.new(0, 0.57, 0),
			Host = { meshId = 76321144260453, size = Vector3.new(2.916, 1.14, 1.914), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 73167730011310,
				size = Vector3.new(0.833, 0.377, 1.304),
				offset = Vector3.new(-0.201, 0.048, 0.192),
			},
			Vein2 = {
				meshId = 81898150064862,
				size = Vector3.new(1.193, 0.417, 1.805),
				offset = Vector3.new(0.448, -0.351, -0.007),
			},
			Moss = {
				meshId = 117901466468019,
				size = Vector3.new(2.806, 1.178, 1.868),
				offset = Vector3.new(-0.02, 0.057, 0.006),
			},
			Snow = {
				meshId = 92851382181470,
				size = Vector3.new(3.231, 1.326, 2.198),
				offset = Vector3.new(0.011, 0.131, 0.002),
			},
			Glow = {
				meshId = 92695059497176,
				size = Vector3.new(1.783, 1.808, 1.839),
				offset = Vector3.new(0.141, 0.337, -0.023),
			},
		},
		B = {
			hostCentre = Vector3.new(0, 0.667, 0),
			Host = { meshId = 130142943401116, size = Vector3.new(3.238, 1.334, 1.798), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 79400154649592,
				size = Vector3.new(1.504, 0.986, 1.52),
				offset = Vector3.new(-0.53, -0.152, -0.025),
			},
			Vein2 = {
				meshId = 96322577929774,
				size = Vector3.new(0.637, 0.44, 1.153),
				offset = Vector3.new(0.51, 0.271, -0.115),
			},
			Moss = {
				meshId = 129244625350818,
				size = Vector3.new(3.091, 1.037, 1.667),
				offset = Vector3.new(-0.017, 0.212, -0.022),
			},
			Snow = {
				meshId = 94839303985408,
				size = Vector3.new(3.376, 1.533, 1.991),
				offset = Vector3.new(-0.037, 0.117, -0.037),
			},
			Glow = {
				meshId = 134147863493545,
				size = Vector3.new(2.379, 1.535, 1.975),
				offset = Vector3.new(-0.407, 0.107, -0.25),
			},
		},
	},
	PebbleCluster = {
		A = {
			hostCentre = Vector3.new(0, 0.343, 0),
			Host = { meshId = 116131616381659, size = Vector3.new(2.062, 0.685, 1.776), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 127956204159935,
				size = Vector3.new(0.979, 0.604, 0.994),
				offset = Vector3.new(-0.127, 0.013, -0.059),
			},
			Vein2 = {
				meshId = 140288429621552,
				size = Vector3.new(0.755, 0.485, 0.797),
				offset = Vector3.new(0.643, -0.064, -0.307),
			},
			Moss = {
				meshId = 93389463678447,
				size = Vector3.new(1.806, 0.516, 1.257),
				offset = Vector3.new(0.127, 0.151, -0.087),
			},
			Snow = {
				meshId = 72316176267224,
				size = Vector3.new(2.331, 0.864, 2.025),
				offset = Vector3.new(0.004, 0.138, 0.004),
			},
			Glow = {
				meshId = 72506631534828,
				size = Vector3.new(1.971, 0.999, 1.401),
				offset = Vector3.new(0.007, 0.185, -0.294),
			},
		},
		B = {
			hostCentre = Vector3.new(0, 0.274, 0),
			Host = { meshId = 140068358947807, size = Vector3.new(2.362, 0.548, 1.642), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 118195742752744,
				size = Vector3.new(0.868, 0.493, 0.88),
				offset = Vector3.new(-0.275, 0.023, 0.148),
			},
			Vein2 = {
				meshId = 107968526158919,
				size = Vector3.new(0.78, 0.42, 0.757),
				offset = Vector3.new(0.527, -0.029, 0.358),
			},
			Moss = {
				meshId = 130260208165473,
				size = Vector3.new(1.746, 0.478, 1.128),
				offset = Vector3.new(0.111, 0.111, 0.183),
			},
			Snow = {
				meshId = 126355289210718,
				size = Vector3.new(2.614, 0.745, 1.871),
				offset = Vector3.new(-0.015, 0.117, -0.011),
			},
			Glow = {
				meshId = 129233942409876,
				size = Vector3.new(1.99, 0.919, 1.341),
				offset = Vector3.new(-0.109, 0.214, 0.054),
			},
		},
	},
	Slab = {
		A = {
			hostCentre = Vector3.new(0, 0.41, 0),
			Host = { meshId = 89071774904778, size = Vector3.new(3.164, 0.82, 2.16), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 76053001678761,
				size = Vector3.new(1.274, 0.554, 1.884),
				offset = Vector3.new(-0.469, -0.119, 0.153),
			},
			Vein2 = {
				meshId = 74075404917586,
				size = Vector3.new(0.858, 0.554, 1.84),
				offset = Vector3.new(0.627, -0.119, -0.039),
			},
			Moss = {
				meshId = 120054350575997,
				size = Vector3.new(3.126, 0.746, 2.052),
				offset = Vector3.new(0.015, 0.113, 0.024),
			},
			Snow = {
				meshId = 84286722746349,
				size = Vector3.new(3.415, 0.88, 2.442),
				offset = Vector3.new(-0.02, 0.18, -0.011),
			},
			Glow = {
				meshId = 127108880483384,
				size = Vector3.new(2.641, 1.02, 2.765),
				offset = Vector3.new(-0.314, 0.104, -0.318),
			},
		},
		B = {
			hostCentre = Vector3.new(0, 0.586, 0),
			Host = { meshId = 83797901809117, size = Vector3.new(4.074, 1.172, 1.986), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 140599043656529,
				size = Vector3.new(1.232, 0.495, 1.747),
				offset = Vector3.new(-1.283, -0.325, 0.135),
			},
			Vein2 = {
				meshId = 102972490912638,
				size = Vector3.new(0.884, 0.496, 1.671),
				offset = Vector3.new(-0.15, -0.325, -0.045),
			},
			Moss = {
				meshId = 107045585185064,
				size = Vector3.new(4.07, 1.082, 1.893),
				offset = Vector3.new(-0.009, 0.099, 0.016),
			},
			Snow = {
				meshId = 112030824525124,
				size = Vector3.new(4.317, 1.233, 2.21),
				offset = Vector3.new(-0.004, 0.174, 0.042),
			},
			Glow = {
				meshId = 140345419460828,
				size = Vector3.new(2.519, 0.885, 2.748),
				offset = Vector3.new(-1.031, -0.139, -0.396),
			},
		},
	},
	Spire = {
		A = {
			hostCentre = Vector3.new(0, 1.317, 0),
			Host = { meshId = 116736395836828, size = Vector3.new(2.12, 2.635, 1.446), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 78415289115581,
				size = Vector3.new(1.405, 0.942, 1.208),
				offset = Vector3.new(-0.101, -0.392, 0.106),
			},
			Vein2 = {
				meshId = 124596463310175,
				size = Vector3.new(1.135, 0.965, 1.025),
				offset = Vector3.new(-0.005, 0.406, 0.093),
			},
			Moss = {
				meshId = 89464630244395,
				size = Vector3.new(1.247, 2.25, 1.207),
				offset = Vector3.new(-0.131, 0.256, 0.099),
			},
			Snow = {
				meshId = 129384016726186,
				size = Vector3.new(2.424, 2.708, 1.678),
				offset = Vector3.new(-0.002, 0.128, -0.004),
			},
			Glow = {
				meshId = 133514845456052,
				size = Vector3.new(2.093, 1.68, 1.802),
				offset = Vector3.new(-0.419, 0.012, -0.203),
			},
		},
		B = {
			hostCentre = Vector3.new(0, 1.31, 0),
			Host = { meshId = 98952222683990, size = Vector3.new(1.844, 2.62, 1.524), offset = Vector3.new(0, 0, 0) },
			Vein1 = {
				meshId = 111560392695120,
				size = Vector3.new(0.958, 0.826, 1.194),
				offset = Vector3.new(0.103, 0.003, 0.063),
			},
			Vein2 = {
				meshId = 97286944998962,
				size = Vector3.new(1.203, 0.829, 1.5),
				offset = Vector3.new(-0.068, -0.874, 0.016),
			},
			Moss = {
				meshId = 140021699860349,
				size = Vector3.new(1.699, 2.24, 1.452),
				offset = Vector3.new(-0.037, 0.262, 0.021),
			},
			Snow = {
				meshId = 103763403133102,
				size = Vector3.new(2.059, 2.622, 1.749),
				offset = Vector3.new(-0.019, 0.224, 0.007),
			},
			Glow = {
				meshId = 139498143650556,
				size = Vector3.new(1.163, 2.844, 1.436),
				offset = Vector3.new(-0.028, 0.118, 0.005),
			},
		},
	},
}

-- Lane M's ore shapes (OreData, lowercase) to a rock kind and variant.
RockModels.OreShapes = {
	boulder = { kind = "Boulder", variant = "A" },
	split = { kind = "CrackedBoulder", variant = "A" },
	standing = { kind = "Spire", variant = "A" },
	slab = { kind = "Slab", variant = "A" },
	mossy = { kind = "Boulder", variant = "B", moss = true },
	pebbles = { kind = "PebbleCluster", variant = "A" },
} :: { [string]: { kind: string, variant: Variant, moss: boolean? } }

local told: { [string]: boolean } = {}

-- (kind, variant, moss). Accepts the six OreData shapes and the capitalised
-- kind names (variant A, no moss). Anything else is Boulder A, told once.
function RockModels.KindFor(shape: string): (string, Variant, boolean)
	local row = RockModels.OreShapes[shape]
	if row then
		return row.kind, row.variant, row.moss == true
	end
	if rocks[shape] then
		return shape, "A", false
	end
	if not told[shape] then
		told[shape] = true
		warn(string.format("[RockModels] unknown rock shape %q; using Boulder A.", tostring(shape)))
	end
	return "Boulder", "A", false
end

function RockModels.Get(kind: string, variant: Variant?): RockMesh?
	local pair = rocks[kind]
	if not pair then
		return nil
	end
	return pair[variant or "A"]
end

-- 0 keeps the part-built rock. A shipped id is not 0.
function RockModels.UsesMesh(meshId: number): boolean
	return type(meshId) == "number" and meshId == meshId and meshId ~= 0
end

-- Scenery models that are not scatter rocks: the mine mouth and the two bomb
-- rubble piles. Each piece's offset is from the Body centre; `hostCentre` is
-- the Body centre above the pivot. meshId 0 keeps the part build.
export type SceneryPiece = { meshId: number, size: Vector3, offset: Vector3 }
export type Scenery = { hostCentre: Vector3, pieces: { [string]: SceneryPiece } }

local function sp(meshId: number, size: Vector3, offset: Vector3): SceneryPiece
	return { meshId = meshId, size = size, offset = offset }
end

local scenery: { [string]: Scenery } = {
	CaveMouth = {
		hostCentre = Vector3.new(0, 10.117, 0),
		pieces = {
			Body = sp(101341694885371, Vector3.new(39.42, 20.233, 15.26), Vector3.new(0, 0, 0)),
			Frame = sp(99645603164777, Vector3.new(18.8, 15.5, 7.175), Vector3.new(-0.052, -1.873, -2.958)),
			Glow = sp(95595144644129, Vector3.new(17.62, 1.05, 0.52), Vector3.new(-0.052, -1.873, -6.17)),
			Collision = sp(105311834374970, Vector3.new(32, 20, 15), Vector3.new(-0.052, 0.376, 0.13)),
		},
	},
	RubbleBoulders = {
		hostCentre = Vector3.new(0, 6.388, 0),
		pieces = {
			Body = sp(92619823907586, Vector3.new(17.082, 12.776, 9.68), Vector3.new(0, 0, 0)),
			Moss = sp(126856307775172, Vector3.new(15.558, 9.705, 6.794), Vector3.new(0.135, 1.646, 0.249)),
			Marks = sp(113108254107488, Vector3.new(2.306, 2.288, 0.3), Vector3.new(0.574, -3.244, -3.463)),
			Collision = sp(122883454923856, Vector3.new(16, 12, 6), Vector3.new(-0.026, 0.156, 1.136)),
		},
	},
	RubbleTunnel = {
		hostCentre = Vector3.new(0, 6.3, 0),
		pieces = {
			Body = sp(125645204407135, Vector3.new(18.136, 12.599, 9.758), Vector3.new(0, 0, 0)),
			Timber = sp(130502799772380, Vector3.new(14.9, 11.188, 6.955), Vector3.new(0.237, -0.405, -0.571)),
			Marks = sp(123210761799280, Vector3.new(2.306, 2.288, 0.3), Vector3.new(0.534, -3.901, -3.304)),
			Collision = sp(121885047697204, Vector3.new(16, 12, 6), Vector3.new(-0.066, -0.001, 1.896)),
		},
	},
}

RockModels.SceneryKinds = { "CaveMouth", "RubbleBoulders", "RubbleTunnel" }

function RockModels.Scenery(name: string): Scenery?
	return scenery[name]
end

-- Every id a rock or scenery piece spawns, once each, for MeshManifest.
-- Zeros are skipped. Walks both variants.
function RockModels.MeshIds(): { number }
	local seen: { [number]: boolean } = {}
	local ids: { number } = {}
	local function take(meshId: number)
		if meshId ~= 0 and not seen[meshId] then
			seen[meshId] = true
			table.insert(ids, meshId)
		end
	end
	for _, pair in pairs(rocks) do
		for _, spec in pairs(pair) do
			for _, key in ipairs(RockModels.PieceKeys) do
				take((spec :: any)[key].meshId)
			end
		end
	end
	for _, item in pairs(scenery) do
		for _, p in pairs(item.pieces) do
			take(p.meshId)
		end
	end
	table.sort(ids)
	return ids
end

return RockModels
