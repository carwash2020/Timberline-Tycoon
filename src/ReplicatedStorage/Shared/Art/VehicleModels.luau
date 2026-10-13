--!strict
-- Vehicle meshes. Each role uses the individual piece meshId
-- (not the Assembly Model's mesh) at the Assembly or ByTruck size.
-- ScoutATV has no bed and no hitch. Trailer hitch width follows the tow truck.
-- Triangle budget for a truck plus its trailer: 12,000 (not measured here).

local VehicleModels = {}

-- Piece fields:
--   meshId, size  the uploaded mesh and the size it is shown at. `size` is the piece's own bounds in
--                 its GLB (assets/meshes/vehicles), so nothing is resized (a wheel keeps the mesh's
--                 own radius and width). tests/VehicleWheelClearance.spec pins every one to the GLB.
--   at            where the middle of the piece's bounds sits in the vehicle's own frame, from the
--                 GLB's assembly (the GLB is authored on the ground with the truck's wheels at
--                 TruckLayout's wheel centres: x 0 is the middle, -Z the front, y 0 the ground). A
--                 trailer's `at` is relative to its bed's middle (VehicleMeshes adds the bed's z).
--                 A piece with no `at` is placed from the hull instead (VehicleMeshes.Place). A
--                 wheel has none: it goes where the part-built wheel was, one mesh copied per axle.
--   mirrorLeft    (a Wheel only) the half turn for a mesh whose rim shows on +X only. Every wheel has it
--                 on: the wheel meshes live in Roblox are still the one-sided uploads (rim, lugs and
--                 cap on +X, a flat black tyre back on -X; the repo's GLBs are dished on both faces
--                 but need the re-upload in ASSETS.md), and a half turn of a two-sided wheel looks
--                 the same, so the flag is safe before and after the re-upload. Look only: the
--                 axle, spin and steering are unchanged (TruckArt.Rig).
export type Piece = { meshId: number, size: Vector3, at: Vector3?, mirrorLeft: boolean? }

local trucks: { [string]: { [string]: Piece } } = {
	Rustbucket = {
		Body = {
			meshId = 135063576797220,
			size = Vector3.new(10.69, 8.8, 23.409),
			at = Vector3.new(-0.015, 5.3, 0.161),
		},
		Glass = {
			meshId = 135044303797643,
			size = Vector3.new(9.863, 3.186, 3.698),
			at = Vector3.new(0.096, 7.401, -4.321),
		},
		Lights = {
			meshId = 100118337585227,
			size = Vector3.new(8.437, 0.802, 20.568),
			at = Vector3.new(0.01, 4.517, 0.741),
		},
		Bed = { meshId = 138924268082867, size = Vector3.new(8.68, 3.2, 14.057), at = Vector3.new(0, 4.425, 4.754) },
		Wheel = { meshId = 96000510170326, size = Vector3.new(1.307, 3.39, 3.38), mirrorLeft = true },
		Hitch = { meshId = 103950687746451, size = Vector3.new(0.7, 1.06, 1.68), at = Vector3.new(0, 2.005, 11.315) },
	},
	Pickup = {
		Body = {
			meshId = 132220778486341,
			size = Vector3.new(11.11, 9.145, 26.136),
			at = Vector3.new(0, 5.273, -0.077),
		},
		Glass = { meshId = 76718452145232, size = Vector3.new(10.098, 3.391, 3.395), at = Vector3.new(0, 7.471, -5.24) },
		Lights = { meshId = 137894921214259, size = Vector3.new(8.54, 2.95, 25.03), at = Vector3.new(0, 4.225, -0.16) },
		Bed = { meshId = 73313476424595, size = Vector3.new(9, 4.05, 15.815), at = Vector3.new(0, 4.375, 4.562) },
		Wheel = { meshId = 100358820661876, size = Vector3.new(1.377, 3.52, 3.51), mirrorLeft = true },
		Hitch = { meshId = 130679096877652, size = Vector3.new(0.7, 1.06, 1.68), at = Vector3.new(0, 2.005, 12.875) },
	},
	ScoutATV = {
		Body = { meshId = 135899530798267, size = Vector3.new(9.3, 9.36, 12.891), at = Vector3.new(0, 5.98, 0.73) },
		Glass = { meshId = 93031171745389, size = Vector3.new(1.4, 0.867, 0.308), at = Vector3.new(0, 6.185, -2.31) },
		Lights = {
			meshId = 102368590223260,
			size = Vector3.new(9.4, 2.648, 10.999),
			at = Vector3.new(0, 4.389, -0.014),
		},
		Wheel = { meshId = 108444483567193, size = Vector3.new(1.822, 3.26, 3.25), mirrorLeft = true },
	},
	Flatbed = {
		Body = {
			meshId = 137271532937493,
			size = Vector3.new(12.18, 10.918, 34.425),
			at = Vector3.new(0, 6.259, -0.118),
		},
		Glass = { meshId = 98760659539151, size = Vector3.new(11.2, 3.947, 3.852), at = Vector3.new(0, 7.747, -9.073) },
		Lights = { meshId = 75034398950940, size = Vector3.new(7.96, 8.76, 33.76), at = Vector3.new(0, 6.83, 0.275) },
		Bed = { meshId = 77252595923073, size = Vector3.new(9.76, 7.475, 23.4), at = Vector3.new(0, 7.223, 4.745) },
		Wheel = { meshId = 94524411538210, size = Vector3.new(1.447, 3.65, 3.64), mirrorLeft = true },
		Hitch = { meshId = 112169540184474, size = Vector3.new(0.7, 1.06, 1.68), at = Vector3.new(0, 2.005, 17.035) },
	},
	LoggingRig = {
		Body = { meshId = 84804800200555, size = Vector3.new(12.99, 14.281, 46.67), at = Vector3.new(0, 7.84, 0) },
		Glass = { meshId = 110663013657387, size = Vector3.new(12.194, 4.44, 3.925), at = Vector3.new(0, 8.83, -13.27) },
		Lights = { meshId = 140436189658598, size = Vector3.new(11.865, 9.605, 45.8), at = Vector3.new(0, 7.303, 0.495) },
		Bed = { meshId = 94574370000217, size = Vector3.new(10.67, 7.325, 33.8), at = Vector3.new(0, 8.112, 5.785) },
		Wheel = { meshId = 88377082453341, size = Vector3.new(1.546, 4.56, 4.55), mirrorLeft = true },
		Hitch = { meshId = 79514319620242, size = Vector3.new(0.7, 1.06, 1.68), at = Vector3.new(0, 2.005, 23.275) },
	},
}

local trailers: { [string]: { [string]: { [string]: Piece } } } = {
	PonyTrailer = {
		Default = {
			Body = {
				meshId = 123304918392077,
				size = Vector3.new(9.79, 2.035, 13.045),
				at = Vector3.new(0, 2.352, 0.023),
			},
			Lights = {
				meshId = 133463511111788,
				size = Vector3.new(8.2, 0.38, 12.83),
				at = Vector3.new(0, 2.925, 0.205),
			},
			Bed = { meshId = 80093608141805, size = Vector3.new(8.34, 2.14, 13), at = Vector3.new(0, 3.745, 0) },
			Wheel = { meshId = 137072790984838, size = Vector3.new(1.105, 3, 2.99), mirrorLeft = true },
			Hitch = {
				meshId = 116050139782151,
				size = Vector3.new(6.466, 3.51, 3.063),
				at = Vector3.new(0, 1.755, -7.492),
			},
		},
		Flatbed = {
			Body = {
				meshId = 123304918392077,
				size = Vector3.new(11.09, 2.035, 13.045),
				at = Vector3.new(0, 2.352, 0.023),
			},
			Lights = {
				meshId = 133463511111788,
				size = Vector3.new(9.5, 0.38, 12.83),
				at = Vector3.new(0, 2.925, 0.205),
			},
			Bed = { meshId = 80093608141805, size = Vector3.new(9.64, 2.14, 13), at = Vector3.new(0, 3.745, 0) },
			Wheel = { meshId = 137072790984838, size = Vector3.new(1.105, 3, 2.99), mirrorLeft = true },
			Hitch = {
				meshId = 116050139782151,
				size = Vector3.new(7.739, 3.51, 3.072),
				at = Vector3.new(0, 1.755, -7.488),
			},
		},
		LoggingRig = {
			Body = {
				meshId = 123304918392077,
				size = Vector3.new(11.87, 2.035, 13.045),
				at = Vector3.new(0, 2.352, 0.023),
			},
			Lights = {
				meshId = 133463511111788,
				size = Vector3.new(10.28, 0.38, 12.83),
				at = Vector3.new(0, 2.925, 0.205),
			},
			Bed = { meshId = 80093608141805, size = Vector3.new(10.42, 2.14, 13), at = Vector3.new(0, 3.745, 0) },
			Wheel = { meshId = 137072790984838, size = Vector3.new(1.105, 3, 2.99), mirrorLeft = true },
			Hitch = {
				meshId = 116050139782151,
				size = Vector3.new(8.505, 3.51, 3.076),
				at = Vector3.new(0, 1.755, -7.486),
			},
		},
		Pickup = {
			Body = {
				meshId = 123304918392077,
				size = Vector3.new(10.31, 2.035, 13.045),
				at = Vector3.new(0, 2.352, 0.023),
			},
			Lights = {
				meshId = 133463511111788,
				size = Vector3.new(8.72, 0.38, 12.83),
				at = Vector3.new(0, 2.925, 0.205),
			},
			Bed = { meshId = 80093608141805, size = Vector3.new(8.86, 2.14, 13), at = Vector3.new(0, 3.745, 0) },
			Wheel = { meshId = 137072790984838, size = Vector3.new(1.105, 3, 2.99), mirrorLeft = true },
			Hitch = {
				meshId = 116050139782151,
				size = Vector3.new(6.974, 3.51, 3.067),
				at = Vector3.new(0, 1.755, -7.49),
			},
		},
		Rustbucket = {
			Body = {
				meshId = 123304918392077,
				size = Vector3.new(9.79, 2.035, 13.045),
				at = Vector3.new(0, 2.352, 0.023),
			},
			Lights = {
				meshId = 133463511111788,
				size = Vector3.new(8.2, 0.38, 12.83),
				at = Vector3.new(0, 2.925, 0.205),
			},
			Bed = { meshId = 80093608141805, size = Vector3.new(8.34, 2.14, 13), at = Vector3.new(0, 3.745, 0) },
			Wheel = { meshId = 137072790984838, size = Vector3.new(1.105, 3, 2.99), mirrorLeft = true },
			Hitch = {
				meshId = 116050139782151,
				size = Vector3.new(6.466, 3.51, 3.063),
				at = Vector3.new(0, 1.755, -7.492),
			},
		},
	},
	RanchTrailer = {
		Default = {
			Body = {
				meshId = 71494115864794,
				size = Vector3.new(10.31, 2.1, 18.245),
				at = Vector3.new(0, 2.45, 0.023),
			},
			Lights = {
				meshId = 84284546831741,
				size = Vector3.new(8.72, 4.22, 18.295),
				at = Vector3.new(0, 4.845, 0.072),
			},
			Bed = { meshId = 90363231220918, size = Vector3.new(9.16, 4.13, 18.27), at = Vector3.new(0, 4.74, -0.035) },
			Wheel = { meshId = 75586028370689, size = Vector3.new(1.105, 3.13, 3.12), mirrorLeft = true },
			Hitch = {
				meshId = 72831025595179,
				size = Vector3.new(6.974, 3.51, 3.067),
				at = Vector3.new(0, 1.755, -10.09),
			},
		},
		Flatbed = {
			Body = {
				meshId = 71494115864794,
				size = Vector3.new(11.09, 2.1, 18.245),
				at = Vector3.new(0, 2.45, 0.023),
			},
			Lights = {
				meshId = 84284546831741,
				size = Vector3.new(9.5, 4.22, 18.295),
				at = Vector3.new(0, 4.845, 0.073),
			},
			Bed = { meshId = 90363231220918, size = Vector3.new(9.94, 4.13, 18.27), at = Vector3.new(0, 4.74, -0.035) },
			Wheel = { meshId = 75586028370689, size = Vector3.new(1.105, 3.13, 3.12), mirrorLeft = true },
			Hitch = {
				meshId = 72831025595179,
				size = Vector3.new(7.739, 3.51, 3.072),
				at = Vector3.new(0, 1.755, -10.088),
			},
		},
		LoggingRig = {
			Body = {
				meshId = 71494115864794,
				size = Vector3.new(11.87, 2.1, 18.245),
				at = Vector3.new(0, 2.45, 0.023),
			},
			Lights = {
				meshId = 84284546831741,
				size = Vector3.new(10.28, 4.22, 18.295),
				at = Vector3.new(0, 4.845, 0.073),
			},
			Bed = {
				meshId = 90363231220918,
				size = Vector3.new(10.72, 4.13, 18.27),
				at = Vector3.new(0, 4.74, -0.035),
			},
			Wheel = { meshId = 75586028370689, size = Vector3.new(1.105, 3.13, 3.12), mirrorLeft = true },
			Hitch = {
				meshId = 72831025595179,
				size = Vector3.new(8.505, 3.51, 3.076),
				at = Vector3.new(0, 1.755, -10.086),
			},
		},
		Pickup = {
			Body = {
				meshId = 71494115864794,
				size = Vector3.new(10.31, 2.1, 18.245),
				at = Vector3.new(0, 2.45, 0.023),
			},
			Lights = {
				meshId = 84284546831741,
				size = Vector3.new(8.72, 4.22, 18.295),
				at = Vector3.new(0, 4.845, 0.072),
			},
			Bed = { meshId = 90363231220918, size = Vector3.new(9.16, 4.13, 18.27), at = Vector3.new(0, 4.74, -0.035) },
			Wheel = { meshId = 75586028370689, size = Vector3.new(1.105, 3.13, 3.12), mirrorLeft = true },
			Hitch = {
				meshId = 72831025595179,
				size = Vector3.new(6.974, 3.51, 3.067),
				at = Vector3.new(0, 1.755, -10.09),
			},
		},
		Rustbucket = {
			Body = { meshId = 71494115864794, size = Vector3.new(9.79, 2.1, 18.245), at = Vector3.new(0, 2.45, 0.023) },
			Lights = {
				meshId = 84284546831741,
				size = Vector3.new(8.2, 4.22, 18.295),
				at = Vector3.new(0, 4.845, 0.073),
			},
			Bed = { meshId = 90363231220918, size = Vector3.new(8.64, 4.13, 18.27), at = Vector3.new(0, 4.74, -0.035) },
			Wheel = { meshId = 75586028370689, size = Vector3.new(1.105, 3.13, 3.12), mirrorLeft = true },
			Hitch = {
				meshId = 72831025595179,
				size = Vector3.new(6.466, 3.51, 3.063),
				at = Vector3.new(0, 1.755, -10.092),
			},
		},
	},
	HeavyHauler = {
		Default = {
			Body = { meshId = 84731895539673, size = Vector3.new(12, 2.085, 26.045), at = Vector3.new(0, 2.507, 0.023) },
			Lights = {
				meshId = 126727044946144,
				size = Vector3.new(10.28, 4.22, 26.075),
				at = Vector3.new(0, 4.845, 0.082),
			},
			Bed = { meshId = 111192039401543, size = Vector3.new(10.74, 4.15, 26.08), at = Vector3.new(0, 4.75, -0.04) },
			Wheel = { meshId = 76485456462102, size = Vector3.new(1.172, 3.26, 3.25), mirrorLeft = true },
			Hitch = {
				meshId = 76951151154210,
				size = Vector3.new(8.505, 3.51, 3.076),
				at = Vector3.new(0, 1.755, -13.986),
			},
		},
		Flatbed = {
			Body = {
				meshId = 84731895539673,
				size = Vector3.new(11.22, 2.085, 26.045),
				at = Vector3.new(0, 2.507, 0.023),
			},
			Lights = {
				meshId = 126727044946144,
				size = Vector3.new(9.5, 4.22, 26.075),
				at = Vector3.new(0, 4.845, 0.083),
			},
			Bed = { meshId = 111192039401543, size = Vector3.new(9.96, 4.15, 26.08), at = Vector3.new(0, 4.75, -0.04) },
			Wheel = { meshId = 76485456462102, size = Vector3.new(1.172, 3.26, 3.25), mirrorLeft = true },
			Hitch = {
				meshId = 76951151154210,
				size = Vector3.new(7.739, 3.51, 3.072),
				at = Vector3.new(0, 1.755, -13.988),
			},
		},
		LoggingRig = {
			Body = { meshId = 84731895539673, size = Vector3.new(12, 2.085, 26.045), at = Vector3.new(0, 2.507, 0.023) },
			Lights = {
				meshId = 126727044946144,
				size = Vector3.new(10.28, 4.22, 26.075),
				at = Vector3.new(0, 4.845, 0.082),
			},
			Bed = { meshId = 111192039401543, size = Vector3.new(10.74, 4.15, 26.08), at = Vector3.new(0, 4.75, -0.04) },
			Wheel = { meshId = 76485456462102, size = Vector3.new(1.172, 3.26, 3.25), mirrorLeft = true },
			Hitch = {
				meshId = 76951151154210,
				size = Vector3.new(8.505, 3.51, 3.076),
				at = Vector3.new(0, 1.755, -13.986),
			},
		},
		Pickup = {
			Body = {
				meshId = 84731895539673,
				size = Vector3.new(10.44, 2.085, 26.045),
				at = Vector3.new(0, 2.507, 0.023),
			},
			Lights = {
				meshId = 126727044946144,
				size = Vector3.new(8.72, 4.22, 26.075),
				at = Vector3.new(0, 4.845, 0.083),
			},
			Bed = { meshId = 111192039401543, size = Vector3.new(9.18, 4.15, 26.08), at = Vector3.new(0, 4.75, -0.04) },
			Wheel = { meshId = 76485456462102, size = Vector3.new(1.172, 3.26, 3.25), mirrorLeft = true },
			Hitch = {
				meshId = 76951151154210,
				size = Vector3.new(6.974, 3.51, 3.067),
				at = Vector3.new(0, 1.755, -13.99),
			},
		},
		Rustbucket = {
			Body = {
				meshId = 84731895539673,
				size = Vector3.new(9.92, 2.085, 26.045),
				at = Vector3.new(0, 2.507, 0.023),
			},
			Lights = {
				meshId = 126727044946144,
				size = Vector3.new(8.2, 4.22, 26.075),
				at = Vector3.new(0, 4.845, 0.083),
			},
			Bed = { meshId = 111192039401543, size = Vector3.new(8.66, 4.15, 26.08), at = Vector3.new(0, 4.75, -0.04) },
			Wheel = { meshId = 76485456462102, size = Vector3.new(1.172, 3.26, 3.25), mirrorLeft = true },
			Hitch = {
				meshId = 76951151154210,
				size = Vector3.new(6.466, 3.51, 3.063),
				at = Vector3.new(0, 1.755, -13.992),
			},
		},
	},
}

-- Every truck and trailer piece as { meshId, wheel } (a wheel loads with
-- Hull collision, the rest with Box), for MeshManifest's preload. Each
-- (id, wheel) pair once, in a fixed order.
function VehicleModels.AllPieces(): { { meshId: number, wheel: boolean } }
	local out: { { meshId: number, wheel: boolean } } = {}
	local seen: { [string]: boolean } = {}
	local function sortedKeys(map: { [string]: any }): { string }
		local keys: { string } = {}
		for key in pairs(map) do
			table.insert(keys, key)
		end
		table.sort(keys)
		return keys
	end
	local function add(spec: { [string]: Piece })
		for _, role in ipairs(sortedKeys(spec)) do
			local piece = spec[role]
			local wheel = role == "Wheel"
			local key = tostring(piece.meshId) .. (if wheel then "w" else "")
			if piece.meshId ~= 0 and not seen[key] then
				seen[key] = true
				table.insert(out, { meshId = piece.meshId, wheel = wheel })
			end
		end
	end
	for _, id in ipairs(sortedKeys(trucks)) do
		add(trucks[id])
	end
	for _, id in ipairs(sortedKeys(trailers)) do
		for _, truckId in ipairs(sortedKeys(trailers[id])) do
			add(trailers[id][truckId])
		end
	end
	return out
end

function VehicleModels.Truck(id: string): { [string]: Piece }?
	return trucks[id]
end

function VehicleModels.Trailer(id: string, truckId: string?): { [string]: Piece }?
	local entry = trailers[id]
	if not entry then
		return nil
	end
	if truckId and entry[truckId] then
		return entry[truckId]
	end
	return entry.Default
end

return VehicleModels
