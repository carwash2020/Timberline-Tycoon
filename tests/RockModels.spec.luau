--!nocheck
-- RockModels: the uploaded numbers, the A/B variants, the ore shape map and
-- the scenery pieces (mine mouth, bomb rubble).
return function(t)
	local RockModels = t.load("ReplicatedStorage/Shared/Art/RockModels")
	local Vector3 = t.roblox.Vector3

	-- Copied from each rock's stats.json (job pack, 2026-10-08):
	-- { meshId, size, offset } per slot.
	local EXPECTED = {
		{
			kind = "Boulder",
			variant = "A",
			centre = { 0, 1.01, 0 },
			pieces = {
				Host = { 80686921861072, { 3.422, 2.02, 2.394 }, { 0, 0, 0 } },
				Vein1 = { 135285101472759, { 1.688, 1.532, 2.144 }, { -0.521, -0.1, 0.066 } },
				Vein2 = { 102587715074861, { 1.62, 1.878, 2.082 }, { 0.153, 0.073, -0.026 } },
				Moss = { 108571714472065, { 3.23, 1.616, 2.323 }, { -0.047, 0.278, 0.002 } },
				Snow = { 78056572803123, { 3.532, 1.981, 2.646 }, { -0.082, 0.237, -0.022 } },
				Glow = { 104109068749289, { 3.107, 2.634, 2.279 }, { -0.665, 0.42, 0.041 } },
			},
		},
		{
			kind = "Boulder",
			variant = "B",
			centre = { 0, 0.865, 0 },
			pieces = {
				Host = { 135954677451616, { 3.808, 1.73, 2.814 }, { 0, 0, 0 } },
				Vein1 = { 81217018152748, { 1.733, 1.381, 2.311 }, { -0.007, -0.057, 0.177 } },
				Vein2 = { 130743362864832, { 1.569, 1.622, 2.22 }, { 0.752, 0.063, 0.116 } },
				Moss = { 118121899916712, { 3.614, 1.349, 2.273 }, { 0.017, 0.264, 0.204 } },
				Snow = { 117316128539352, { 3.984, 1.892, 3.042 }, { 0.015, 0.145, -0.016 } },
				Glow = { 120441451290084, { 3.106, 2.754, 2.397 }, { -0.043, 0.603, 0.174 } },
			},
		},
		{
			kind = "CrackedBoulder",
			variant = "A",
			centre = { 0, 0.988, 0 },
			pieces = {
				Host = { 123515393937777, { 3.006, 1.975, 2.354 }, { 0, 0, 0 } },
				Vein1 = { 134764809615746, { 1.608, 1.372, 1.983 }, { -0.641, -0.135, 0.083 } },
				Vein2 = { 132475579395371, { 1.369, 1.25, 1.819 }, { 0.761, -0.169, 0.073 } },
				Moss = { 82487395045845, { 2.843, 1.348, 1.9 }, { -0.042, 0.388, 0.161 } },
				Snow = { 122975660028978, { 3.17, 2.077, 2.615 }, { 0.031, 0.17, -0.019 } },
				Glow = { 101286265773616, { 3.606, 2.211, 2.042 }, { -0.412, 0.277, 0.079 } },
			},
		},
		{
			kind = "CrackedBoulder",
			variant = "B",
			centre = { 0, 0.955, 0 },
			pieces = {
				Host = { 100630014533328, { 2.92, 1.909, 2.392 }, { 0, 0, 0 } },
				Vein1 = { 93012071548500, { 1.958, 1.203, 2.052 }, { -0.485, -0.059, 0.084 } },
				Vein2 = { 131449379256182, { 1.749, 1.369, 1.981 }, { 0.574, -0.099, -0.145 } },
				Moss = { 95470563986109, { 2.913, 1.496, 1.946 }, { -0.017, 0.263, 0.135 } },
				Snow = { 85402746195194, { 3.15, 1.948, 2.587 }, { -0.028, 0.166, -0.049 } },
				Glow = { 102541556185071, { 3.631, 2.21, 2.268 }, { -0.39, 0.316, -0.002 } },
			},
		},
		{
			kind = "Outcrop",
			variant = "A",
			centre = { 0, 0.57, 0 },
			pieces = {
				Host = { 76321144260453, { 2.916, 1.14, 1.914 }, { 0, 0, 0 } },
				Vein1 = { 73167730011310, { 0.833, 0.377, 1.304 }, { -0.201, 0.048, 0.192 } },
				Vein2 = { 81898150064862, { 1.193, 0.417, 1.805 }, { 0.448, -0.351, -0.007 } },
				Moss = { 117901466468019, { 2.806, 1.178, 1.868 }, { -0.02, 0.057, 0.006 } },
				Snow = { 92851382181470, { 3.231, 1.326, 2.198 }, { 0.011, 0.131, 0.002 } },
				Glow = { 92695059497176, { 1.783, 1.808, 1.839 }, { 0.141, 0.337, -0.023 } },
			},
		},
		{
			kind = "Outcrop",
			variant = "B",
			centre = { 0, 0.667, 0 },
			pieces = {
				Host = { 130142943401116, { 3.238, 1.334, 1.798 }, { 0, 0, 0 } },
				Vein1 = { 79400154649592, { 1.504, 0.986, 1.52 }, { -0.53, -0.152, -0.025 } },
				Vein2 = { 96322577929774, { 0.637, 0.44, 1.153 }, { 0.51, 0.271, -0.115 } },
				Moss = { 129244625350818, { 3.091, 1.037, 1.667 }, { -0.017, 0.212, -0.022 } },
				Snow = { 94839303985408, { 3.376, 1.533, 1.991 }, { -0.037, 0.117, -0.037 } },
				Glow = { 134147863493545, { 2.379, 1.535, 1.975 }, { -0.407, 0.107, -0.25 } },
			},
		},
		{
			kind = "PebbleCluster",
			variant = "A",
			centre = { 0, 0.343, 0 },
			pieces = {
				Host = { 116131616381659, { 2.062, 0.685, 1.776 }, { 0, 0, 0 } },
				Vein1 = { 127956204159935, { 0.979, 0.604, 0.994 }, { -0.127, 0.013, -0.059 } },
				Vein2 = { 140288429621552, { 0.755, 0.485, 0.797 }, { 0.643, -0.064, -0.307 } },
				Moss = { 93389463678447, { 1.806, 0.516, 1.257 }, { 0.127, 0.151, -0.087 } },
				Snow = { 72316176267224, { 2.331, 0.864, 2.025 }, { 0.004, 0.138, 0.004 } },
				Glow = { 72506631534828, { 1.971, 0.999, 1.401 }, { 0.007, 0.185, -0.294 } },
			},
		},
		{
			kind = "PebbleCluster",
			variant = "B",
			centre = { 0, 0.274, 0 },
			pieces = {
				Host = { 140068358947807, { 2.362, 0.548, 1.642 }, { 0, 0, 0 } },
				Vein1 = { 118195742752744, { 0.868, 0.493, 0.88 }, { -0.275, 0.023, 0.148 } },
				Vein2 = { 107968526158919, { 0.78, 0.42, 0.757 }, { 0.527, -0.029, 0.358 } },
				Moss = { 130260208165473, { 1.746, 0.478, 1.128 }, { 0.111, 0.111, 0.183 } },
				Snow = { 126355289210718, { 2.614, 0.745, 1.871 }, { -0.015, 0.117, -0.011 } },
				Glow = { 129233942409876, { 1.99, 0.919, 1.341 }, { -0.109, 0.214, 0.054 } },
			},
		},
		{
			kind = "Slab",
			variant = "A",
			centre = { 0, 0.41, 0 },
			pieces = {
				Host = { 89071774904778, { 3.164, 0.82, 2.16 }, { 0, 0, 0 } },
				Vein1 = { 76053001678761, { 1.274, 0.554, 1.884 }, { -0.469, -0.119, 0.153 } },
				Vein2 = { 74075404917586, { 0.858, 0.554, 1.84 }, { 0.627, -0.119, -0.039 } },
				Moss = { 120054350575997, { 3.126, 0.746, 2.052 }, { 0.015, 0.113, 0.024 } },
				Snow = { 84286722746349, { 3.415, 0.88, 2.442 }, { -0.02, 0.18, -0.011 } },
				Glow = { 127108880483384, { 2.641, 1.02, 2.765 }, { -0.314, 0.104, -0.318 } },
			},
		},
		{
			kind = "Slab",
			variant = "B",
			centre = { 0, 0.586, 0 },
			pieces = {
				Host = { 83797901809117, { 4.074, 1.172, 1.986 }, { 0, 0, 0 } },
				Vein1 = { 140599043656529, { 1.232, 0.495, 1.747 }, { -1.283, -0.325, 0.135 } },
				Vein2 = { 102972490912638, { 0.884, 0.496, 1.671 }, { -0.15, -0.325, -0.045 } },
				Moss = { 107045585185064, { 4.07, 1.082, 1.893 }, { -0.009, 0.099, 0.016 } },
				Snow = { 112030824525124, { 4.317, 1.233, 2.21 }, { -0.004, 0.174, 0.042 } },
				Glow = { 140345419460828, { 2.519, 0.885, 2.748 }, { -1.031, -0.139, -0.396 } },
			},
		},
		{
			kind = "Spire",
			variant = "A",
			centre = { 0, 1.317, 0 },
			pieces = {
				Host = { 116736395836828, { 2.12, 2.635, 1.446 }, { 0, 0, 0 } },
				Vein1 = { 78415289115581, { 1.405, 0.942, 1.208 }, { -0.101, -0.392, 0.106 } },
				Vein2 = { 124596463310175, { 1.135, 0.965, 1.025 }, { -0.005, 0.406, 0.093 } },
				Moss = { 89464630244395, { 1.247, 2.25, 1.207 }, { -0.131, 0.256, 0.099 } },
				Snow = { 129384016726186, { 2.424, 2.708, 1.678 }, { -0.002, 0.128, -0.004 } },
				Glow = { 133514845456052, { 2.093, 1.68, 1.802 }, { -0.419, 0.012, -0.203 } },
			},
		},
		{
			kind = "Spire",
			variant = "B",
			centre = { 0, 1.31, 0 },
			pieces = {
				Host = { 98952222683990, { 1.844, 2.62, 1.524 }, { 0, 0, 0 } },
				Vein1 = { 111560392695120, { 0.958, 0.826, 1.194 }, { 0.103, 0.003, 0.063 } },
				Vein2 = { 97286944998962, { 1.203, 0.829, 1.5 }, { -0.068, -0.874, 0.016 } },
				Moss = { 140021699860349, { 1.699, 2.24, 1.452 }, { -0.037, 0.262, 0.021 } },
				Snow = { 103763403133102, { 2.059, 2.622, 1.749 }, { -0.019, 0.224, 0.007 } },
				Glow = { 139498143650556, { 1.163, 2.844, 1.436 }, { -0.028, 0.118, 0.005 } },
			},
		},
	}

	local function near(a, list, what)
		local b = Vector3.new(list[1], list[2], list[3])
		t.ok((a - b).Magnitude < 1e-3, what .. " expected " .. tostring(b) .. " got " .. tostring(a))
	end

	t.test("every kind has A and B with all six slots at the uploaded numbers", function()
		t.eq(#EXPECTED, 12)
		local seen = {}
		for _, row in ipairs(EXPECTED) do
			local spec = RockModels.Get(row.kind, row.variant)
			local tag = row.kind .. row.variant
			t.ok(spec, tag)
			near(spec.hostCentre, row.centre, tag .. " hostCentre")
			for key, want in pairs(row.pieces) do
				local piece = spec[key]
				t.eq(piece.meshId, want[1], tag .. " " .. key .. " id")
				t.ok(piece.meshId ~= 0, tag .. " " .. key .. " is uploaded")
				near(piece.size, want[2], tag .. " " .. key .. " size")
				near(piece.offset, want[3], tag .. " " .. key .. " offset")
				t.eq(seen[piece.meshId], nil, tag .. " " .. key .. " id is unique")
				seen[piece.meshId] = true
			end
			near(spec.Host.offset, { 0, 0, 0 }, tag .. " host offset")
		end
		for _, kind in ipairs(RockModels.Shapes) do
			t.ok(RockModels.Get(kind, "A") and RockModels.Get(kind, "B"), kind)
			t.eq(RockModels.Get(kind), RockModels.Get(kind, "A"), "default is A")
		end
		t.eq(#RockModels.Shapes, 6)
		t.eq(RockModels.Get("Nope"), nil)
	end)

	t.test("MeshIds walks both variants and the scenery, once each", function()
		local ids = RockModels.MeshIds()
		t.eq(#ids, 12 * 6 + 12, "72 rock pieces and 12 scenery pieces")
		for i = 2, #ids do
			t.ok(ids[i] > ids[i - 1], "sorted and unique")
		end
	end)

	t.test("KindFor maps the six ore shapes and passes kind names through", function()
		local function check(shape, kind, variant, moss)
			local k, v, m = RockModels.KindFor(shape)
			t.eq(k, kind, shape .. " kind")
			t.eq(v, variant, shape .. " variant")
			t.eq(m, moss, shape .. " moss")
		end
		check("boulder", "Boulder", "A", false)
		check("split", "CrackedBoulder", "A", false)
		check("standing", "Spire", "A", false)
		check("slab", "Slab", "A", false)
		check("mossy", "Boulder", "B", true)
		check("pebbles", "PebbleCluster", "A", false)
		for _, kind in ipairs(RockModels.Shapes) do
			check(kind, kind, "A", false)
		end
		check("nonsense", "Boulder", "A", false)
		check("nonsense", "Boulder", "A", false)
	end)

	t.test("the mine mouth and rubble pieces carry the uploaded ids", function()
		local mouth = RockModels.Scenery("CaveMouth")
		t.eq(mouth.pieces.Body.meshId, 101341694885371)
		t.eq(mouth.pieces.Frame.meshId, 99645603164777)
		t.eq(mouth.pieces.Glow.meshId, 95595144644129)
		t.eq(mouth.pieces.Collision.meshId, 105311834374970)
		near(mouth.hostCentre, { 0, 10.117, 0 }, "mouth hostCentre")
		near(mouth.pieces.Body.size, { 39.42, 20.233, 15.26 }, "Body size")
		near(mouth.pieces.Frame.offset, { -0.052, -1.873, -2.958 }, "Frame offset")
		near(mouth.pieces.Glow.size, { 17.62, 1.05, 0.52 }, "Glow size")
		near(mouth.pieces.Collision.size, { 32, 20, 15 }, "Collision size")
		local boulders = RockModels.Scenery("RubbleBoulders")
		t.eq(boulders.pieces.Body.meshId, 92619823907586)
		t.eq(boulders.pieces.Moss.meshId, 126856307775172)
		t.eq(boulders.pieces.Marks.meshId, 113108254107488)
		t.eq(boulders.pieces.Collision.meshId, 122883454923856)
		near(boulders.pieces.Collision.size, { 16, 12, 6 }, "rubble blocker size")
		local tunnel = RockModels.Scenery("RubbleTunnel")
		t.eq(tunnel.pieces.Body.meshId, 125645204407135)
		t.eq(tunnel.pieces.Timber.meshId, 130502799772380)
		t.eq(tunnel.pieces.Marks.meshId, 123210761799280)
		t.eq(tunnel.pieces.Collision.meshId, 121885047697204)
		near(tunnel.pieces.Collision.size, { 16, 12, 6 }, "tunnel blocker size")
		t.eq(RockModels.Scenery("Nope"), nil)
	end)

	t.test("every id RockModels.MeshIds() returns has a MeshTemplates file", function()
		local fs = require("@lune/fs")
		local ids = RockModels.MeshIds()
		t.eq(#ids, 84)
		for _, id in ipairs(ids) do
			local path = "src/ReplicatedStorage/MeshTemplates/" .. tostring(id) .. ".model.json"
			t.ok(fs.isFile(path), "missing template " .. path)
			local text = fs.readFile(path)
			t.ok(string.find(text, '"className": "MeshPart"', 1, true) ~= nil, path .. " is a MeshPart")
			t.ok(string.find(text, "rbxassetid://" .. tostring(id) .. '"', 1, true) ~= nil, path .. " names its own id")
		end
	end)
end
