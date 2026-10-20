--!nocheck
-- StoreModelSlots: one model slot per store item (Barrel, Crate, Glow Wire, Sky Bin,
-- the Robux coins, the Parcel fallback, the three gear items, the lamp post). The same
-- slot serves the shop box (and so the carried box), the placed item and its ghost.
-- The new GLBs have no Roblox mesh id yet, so the rules pinned here are: an unset id
-- never errors and the part-built look stays; a mesh that is there replaces the part
-- build in the box and on the plot, fitted to the item's own size; the GLB sources are
-- in the repo and match the data; an item with no model of its own gets the Parcel.
-- Lune cannot load meshes, so a spec hands MeshKit an Override and PreviewIds (the same
-- seam tools/preview/export.luau uses). Every test gets a fresh Loader, so the box sizes
-- ItemModel and ItemBox cache never leak from a test with ids to one without.
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	local EPS = 0.02

	-- What a store item is, for the box: its kind and id.
	local ITEMS = {
		{ kind = "Blueprint", id = "Barrel", slot = "Barrel" },
		{ kind = "Blueprint", id = "Crate", slot = "Crate" },
		{ kind = "Logic", id = "GlowWire", slot = "GlowWire" },
		{ kind = "Machine", id = "SkyBin", slot = "SkyBin" },
		{ kind = "Gear", id = "InsulatedCoat", slot = "InsulatedCoat" },
		{ kind = "Gear", id = "HeatBoots", slot = "HeatBoots" },
		{ kind = "Gear", id = "FeatherfallCloak", slot = "FeatherfallCloak" },
		{ kind = "Cosmetic", id = "LampPost", slot = "LampPost" },
	}

	-- GLBs in assets/glb/store-items that another lane wires (Hearth and Home, PR 183):
	-- they have no slot here on purpose, and the folder check below knows them.
	local OTHER_LANE = { Flashlight = true, Lantern = true, WoodSign = true, ShedBlueprint = true }

	-- A fresh set of modules. `meshes`: every slot piece without an id gets a made-up one
	-- and MeshKit hands back a MeshPart of the asked size, as export.luau does for a render.
	local function world(meshes)
		local loader = t.loader()
		local W = {
			Slots = loader:shared("StoreModelSlots"),
			StoreModelArt = loader:load("ReplicatedStorage/Shared/Art/StoreModelArt"),
			MeshKit = loader:load("ReplicatedStorage/Shared/Art/MeshKit"),
			ItemModel = loader:load("ReplicatedStorage/Shared/Art/ItemModel"),
			BoxArt = loader:load("ReplicatedStorage/Shared/Art/BoxArt"),
			MachineArt = loader:load("ReplicatedStorage/Shared/Art/MachineArt"),
			RobuxBoxArt = loader:load("ReplicatedStorage/Shared/Art/RobuxBoxArt"),
			MeshManifest = loader:load("ReplicatedStorage/Shared/Art/MeshManifest"),
			TownMeshes = loader:load("ReplicatedStorage/Shared/Art/TownMeshes"),
			BlueprintModels = loader:shared("BlueprintModels"),
			PlotData = loader:shared("PlotData"),
			ItemBox = loader:shared("ItemBox"),
			BoxSize = loader:shared("BoxSize"),
		}
		-- The town meshes are off in the game (GameConfig.TownMeshes = false).
		W.TownMeshes.Enabled = false
		if meshes then
			local preview = {}
			local n = 0
			for _, slot in ipairs(W.Slots.All) do
				for _, piece in ipairs(slot.pieces) do
					if piece.meshId == 0 then
						n += 1
						preview[slot.id .. "/" .. piece.name] = 9000000000000 + n
					end
				end
			end
			W.Slots.PreviewIds = preview
			W.MeshKit.Override = function(_, name, size)
				local part = Instance.new("MeshPart")
				part.Name = name
				part.Size = size
				return part
			end
		end
		return W
	end

	-- The slot's own meshes under `root` (not a town mesh the same model may also wear).
	local function meshParts(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("MeshPart") and d:GetAttribute("StoreModel") ~= nil then
				table.insert(out, d)
			end
		end
		return out
	end

	local function bounds(parts)
		local lo, hi
		for _, p in ipairs(parts) do
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local c = p.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
						lo = if lo then lo:Min(c) else c
						hi = if hi then hi:Max(c) else c
					end
				end
			end
		end
		return lo, hi
	end

	local function box(W, kind, id, extra)
		local size = W.ItemBox.Size(kind, id)
		local model = Instance.new("Model")
		local body = Instance.new("Part")
		body.Name = "Box"
		body.Size = size
		body.CFrame = CFrame.new(0, size.Y / 2, 0)
		body.Parent = model
		local spec = { name = id, kind = kind, itemId = id }
		for k, v in pairs(extra or {}) do
			spec[k] = v
		end
		W.BoxArt.Dress(model, body, spec)
		return model, body
	end

	t.test("each of Barrel, Crate, Glow Wire, Sky Bin resolves exactly one slot, the same for every path", function()
		local W = world(false)
		for _, item in ipairs(ITEMS) do
			local slot = W.Slots.ForItem(item.id, item.kind)
			t.ok(slot ~= nil, item.id .. " has a slot")
			t.eq(slot.id, item.slot)
			-- Resolve is the same answer, and it is not the fallback.
			local resolved, parcel = W.Slots.Resolve(item.id, item.kind)
			t.eq(resolved, slot)
			t.eq(parcel, false)
			-- The display path (box, carried box) uses it ...
			t.eq(W.ItemModel.Get(item.kind, item.id).slot, slot, item.id .. " box")
			-- ... and so does the kind-less lookup the placed paths use.
			t.eq(W.Slots.ForItem(item.id, nil), slot, item.id .. " placed")
		end
		-- No two slots claim one item, and every slot has a GLB path and a piece.
		local owner = {}
		for _, slot in ipairs(W.Slots.All) do
			t.ok(#slot.pieces >= 1 and #slot.pieces <= 2, slot.id .. " pieces")
			t.ok(string.match(slot.glb, "%.glb$") ~= nil, slot.id .. " glb")
			for _, id in ipairs(slot.items) do
				t.eq(owner[id], nil, id .. " claimed twice")
				owner[id] = slot.id
			end
		end
	end)

	t.test("the Robux box uses the RobuxCoins slot, by kind", function()
		local W = world(false)
		local slot = W.Slots.ForItem(nil, "Robux")
		t.eq(slot.id, "RobuxCoins")
		t.eq(W.Slots.ForItem("Cash1k", "Robux"), slot)
		t.eq(W.ItemModel.Get("Robux", "").slot, slot)
		t.eq(W.Slots.ForItem("SteelAxe", "Axe"), nil, "an axe has no slot")
	end)

	t.test("Parcel fallback: an item with no slot gets the Parcel, an item with one never does", function()
		local W = world(false)
		local slot, parcel = W.Slots.Resolve("NoSuchThing", "Gear")
		t.eq(slot.id, "Parcel")
		t.eq(parcel, true)
		t.eq(W.Slots.Parcel(), slot)
		t.eq(W.Slots.Resolve(nil, nil), W.Slots.Parcel())
		t.eq(select(2, W.Slots.Resolve("Barrel", "Blueprint")), false)
		-- The box of a made-up gear item is the generic parcel, from the Parcel slot.
		local shown = W.ItemModel.Get("Gear", "NoSuchThing")
		t.eq(shown.generic, true)
		t.eq(shown.slot, slot)
		t.eq(shown.fallback, true)
		-- A real item's display is not a fallback.
		t.eq(W.ItemModel.Get("Blueprint", "Barrel").fallback, false)
		-- Axes, trucks and the rest have no slot and no parcel: their own models.
		t.eq(W.ItemModel.Get("Axe", "SteelAxe").slot, nil)
		t.eq(W.ItemModel.Get("Axe", "SteelAxe").fallback, false)
	end)

	t.test("uploaded ids never error: every item still builds its box and its plot model", function()
		local W = world(false)
		t.eq(W.Slots.PreviewIds, nil)
		for _, slot in ipairs(W.Slots.All) do
			if slot.source == "store-items" then
				-- 13 Oct 2026: every store-items model is uploaded (one baked mesh each).
				t.eq(W.Slots.IsUploaded(slot), true, slot.id .. " is uploaded")
				t.eq(W.Slots.HasMesh(slot), true, slot.id .. " has a mesh to load")
			end
		end
		for _, item in ipairs(ITEMS) do
			local model = box(W, item.kind, item.id)
			t.ok(model:FindFirstChild("Contents") ~= nil, item.id .. " box has contents")
			if not W.Slots.HasMesh(W.Slots.ForItem(item.id, item.kind)) then
				t.eq(#meshParts(model), 0, item.id .. " box stays part-built")
				t.ok(#model:FindFirstChild("Contents"):GetChildren() > 0, item.id .. " parts are there")
			end
		end
		-- The placed plans and the placed Sky Bin.
		for _, id in ipairs({ "Barrel", "Crate", "GlowWire" }) do
			local placed = W.BlueprintModels.Build(W.PlotData.Blueprint(id), false)
			t.eq(#meshParts(placed), 0, id .. " placed is part-built")
			t.eq(placed:FindFirstChild("Part1").Transparency, 0, id .. " boxes are the look")
		end
		local bin = W.MachineArt.BuildSkyBin(false)
		t.eq(#meshParts(bin), 0)
		t.eq(bin:FindFirstChild("SkyBin").Transparency, 0)
		-- The gold Robux box keeps its coin heap.
		local gold = Instance.new("Model")
		local body = Instance.new("Part")
		body.Size = W.BoxSize.Class("S").size
		body.Parent = gold
		W.RobuxBoxArt.Dress(gold, body, { name = "Cash", key = "Cash1k" })
		t.ok(gold:FindFirstChild("Contents"):FindFirstChild("CoinHeap") ~= nil)
		-- Asking the art for a slot with no id yields nothing and builds nothing.
		for _, slot in ipairs(W.Slots.All) do
			if not W.Slots.HasMesh(slot) then
				t.eq(W.StoreModelArt.Build(slot, CFrame.identity), nil, slot.id)
			end
		end
	end)

	t.test("a mesh id that cannot load (a failed asset) keeps the part build and says nothing", function()
		local W = world(true)
		W.MeshKit.Override = function()
			return nil
		end
		for _, item in ipairs(ITEMS) do
			local model, body = box(W, item.kind, item.id)
			t.eq(#meshParts(model), 0, item.id)
			local kept = model:FindFirstChild("Contents"):GetChildren()
			t.ok(#kept > 0, item.id .. " parts stay")
			-- The part build standing in for a mesh that did not load is inside the box (the box
			-- is sized for the model), standing on the floor.
			local lo, hi = bounds(kept)
			local half = body.Size / 2
			local at = body.CFrame.Position
			t.ok(lo.X >= at.X - half.X - EPS and hi.X <= at.X + half.X + EPS, item.id .. " stand-in X")
			t.ok(lo.Z >= at.Z - half.Z - EPS and hi.Z <= at.Z + half.Z + EPS, item.id .. " stand-in Z")
			t.ok(hi.Y <= at.Y + half.Y + EPS, item.id .. " stand-in height")
			t.ok(math.abs(lo.Y - (at.Y - half.Y + W.BoxSize.Floor)) < 0.4, item.id .. " stand-in on the floor")
		end
		local placed = W.BlueprintModels.Build(W.PlotData.Blueprint("Barrel"), false)
		t.eq(#meshParts(placed), 0)
		t.eq(placed:FindFirstChild("Part1").Transparency, 0)
	end)

	t.test("a slot with a mesh replaces the part build in the box, fitted inside the item's own bounds", function()
		local W = world(true)
		for _, item in ipairs(ITEMS) do
			local slot = W.Slots.ForItem(item.id, item.kind)
			local model, body = box(W, item.kind, item.id)
			local meshes = meshParts(model:FindFirstChild("Contents"))
			t.eq(#meshes, #slot.pieces, item.id .. " one mesh per piece")
			t.eq(#model:FindFirstChild("Contents"):GetChildren(), #slot.pieces, item.id .. " the part build is gone")
			for _, mesh in ipairs(meshes) do
				t.eq(mesh:GetAttribute("StoreModel"), slot.id)
				t.eq(mesh.CanCollide, false)
				t.eq(mesh.Massless, true)
			end
			-- Inside the box, standing on its floor, never through the walls.
			local lo, hi = bounds(meshes)
			local half = body.Size / 2
			local at = body.CFrame.Position
			t.ok(lo.X >= at.X - half.X - EPS and hi.X <= at.X + half.X + EPS, item.id .. " X")
			t.ok(lo.Z >= at.Z - half.Z - EPS and hi.Z <= at.Z + half.Z + EPS, item.id .. " Z")
			t.ok(lo.Y >= at.Y - half.Y + W.BoxSize.Floor - EPS, item.id .. " stands on the floor, not in it")
			t.ok(lo.Y <= at.Y - half.Y + W.BoxSize.Floor + 0.3, item.id .. " stands on the floor, not above it")
			t.ok(hi.Y <= at.Y + half.Y + EPS, item.id .. " below the top")
			-- Part budget: a mesh is never more parts than the part build was allowed.
			t.ok(#meshes <= W.ItemModel.ModelBudget[item.kind], item.id .. " budget")
		end
	end)

	t.test("the box depends on whether a slot has an id, never on whether the mesh has loaded", function()
		-- Id set, mesh loaded or not: the same box. (The part build is the fallback inside it.)
		local loaded = world(true)
		local pending = world(true)
		pending.MeshKit.Override = function()
			return nil
		end
		for _, item in ipairs(ITEMS) do
			t.eq(loaded.ItemBox.Size(item.kind, item.id), pending.ItemBox.Size(item.kind, item.id), item.id)
		end
		-- Id unset: the display is the part build's, exactly as before the slot existed.
		local bare = world(false)
		-- Every store model is uploaded now, so take the ids away to see the part build.
		for _, slot in ipairs(bare.Slots.All) do
			if slot.source == "store-items" then
				for _, piece in ipairs(slot.pieces) do
					piece.meshId = 0
				end
			end
		end
		for _, item in ipairs({ { "Blueprint", "Barrel" }, { "Blueprint", "Crate" }, { "Logic", "GlowWire" } }) do
			t.ok(#bare.ItemModel.Get(item[1], item[2]).parts > 0, item[2])
		end
		-- With an id the box is sized for the model, not the part build: the Glow Wire's spool
		-- (2.16 x 1.3 x 1.02) is deeper and taller than its 0.3 stud bar, and narrower than the
		-- bar is long. Without one the part build sizes it, as before the slot existed.
		local wire = loaded.ItemModel.Get("Logic", "GlowWire").extent
		local part = bare.ItemModel.Get("Logic", "GlowWire").extent
		local layout = loaded.Slots.Layout(loaded.Slots.Get("GlowWire")).size
		t.ok((wire - layout).Magnitude < 1e-4, "the extent is the model's")
		t.ok(wire.Y > part.Y and wire.Z > part.Z, "the spool is taller and deeper than the bar")
		t.ok(wire.X < part.X, "and shorter")
	end)

	t.test("the Parcel shows on a box for an item with no model, and the parts stay when neither exists", function()
		-- Neither: the made-up item has no slot mesh, so the part-built parcel is what shows.
		local plain = box(world(false), "Gear", "NoSuchThing")
		t.eq(#meshParts(plain), 0)
		t.ok(#plain:FindFirstChild("Contents"):GetChildren() > 0)
		local W = world(true)
		local model = box(W, "Gear", "NoSuchThing")
		local meshes = meshParts(model:FindFirstChild("Contents"))
		t.eq(#meshes, 1)
		t.eq(meshes[1]:GetAttribute("StoreModel"), "Parcel")
		t.eq(#model:FindFirstChild("Contents"):GetChildren(), 1)
	end)

	t.test("a placed Barrel, Crate and Glow Wire wear the model, the boxes stay as the collider", function()
		local W = world(true)
		for _, id in ipairs({ "Barrel", "Crate", "GlowWire" }) do
			local slot = W.Slots.ForItem(id, nil)
			local bp = W.PlotData.Blueprint(id)
			local placed = W.BlueprintModels.Build(bp, false)
			local meshes = meshParts(placed)
			t.eq(#meshes, 1, id)
			t.eq(meshes[1]:GetAttribute("StoreModel"), slot.id)
			t.eq(meshes[1]:GetAttribute("ItemVisual"), true)
			t.eq(meshes[1].Transparency, 0)
			t.eq(placed:FindFirstChild("Part1").Transparency, 1, id .. " the box steps back")
			-- On the ground, inside the footprint, the size of the part-built item.
			local lo, hi = bounds(meshes)
			t.ok(math.abs(lo.Y) < EPS, id .. " stands on the ground")
			t.ok(hi.X - lo.X <= bp.footprint.X + EPS and hi.Z - lo.Z <= bp.footprint.Y + EPS, id .. " in its footprint")
			local layout = W.Slots.Layout(slot)
			t.ok(layout.size.X <= slot.fit.X + EPS and layout.size.Y <= slot.fit.Y + EPS, id .. " fits")
			-- The ghost never wears the model (T380): the boxes, as a hologram.
			local ghost = W.BlueprintModels.Build(bp, true)
			t.eq(#meshParts(ghost), 0, id .. " ghost has no mesh")
			t.ok(math.abs(ghost:FindFirstChild("Part1").Transparency - 0.6) < 0.001, id .. " ghost")
		end
	end)

	t.test("the placed Sky Bin wears the bin model and keeps its flume, cloud and labelled collider", function()
		local W = world(true)
		local bin = W.MachineArt.BuildSkyBin(false)
		local meshes = meshParts(bin)
		t.eq(#meshes, 1)
		t.eq(meshes[1]:GetAttribute("StoreModel"), "SkyBin")
		t.eq(bin:FindFirstChild("BinBase").Transparency, 1)
		t.eq(bin:FindFirstChild("SkyBin").Transparency, 1)
		t.eq(bin:FindFirstChild("SkyBin").CanCollide, true, "the collider stays")
		t.ok(bin:FindFirstChild("Flume") ~= nil and bin:FindFirstChild("Flume").Transparency == 0, "the flume stays")
		t.ok(bin:FindFirstChild("Cloud") ~= nil and bin:FindFirstChild("Cloud").Transparency == 0, "the cloud stays")
		local lo, hi = bounds(meshes)
		t.ok(math.abs(lo.Y) < EPS, "on the ground")
		t.ok(hi.X - lo.X <= 4 + EPS and hi.Z - lo.Z <= 4 + EPS, "inside the bin's 4 stud body")
	end)

	t.test(
		"the Robux crate wears the coin model: a pile on the mesh crate's lid, on the floor of the part-built one",
		function()
			local W = world(true)
			local model = Instance.new("Model")
			local body = Instance.new("Part")
			body.Size = W.BoxSize.Class("S").size
			body.CFrame = CFrame.new(0, body.Size.Y / 2, 0)
			body.Parent = model
			W.RobuxBoxArt.Dress(model, body, { name = "Large Cash Pack", key = "Cash10k" })
			local coins = {}
			for _, mesh in ipairs(meshParts(model)) do
				if mesh:GetAttribute("StoreModel") == "RobuxCoins" then
					table.insert(coins, mesh)
				end
			end
			t.eq(#coins, 1)
			local lo, hi = bounds(coins)
			t.ok(hi.X - lo.X <= body.Size.X + EPS and hi.Z - lo.Z <= body.Size.Z + EPS, "no wider than the crate")
			t.ok(lo.Y > 0, "over the crate floor")
		end
	)

	t.test(
		"the slot layout: fit by the smallest ratio, yaw swaps X and Z, the frame is the middle of the feet",
		function()
			local Slots = world(false).Slots
			local barrel = Slots.Get("Barrel")
			local layout = Slots.Layout(barrel)
			t.ok(math.abs(layout.size.Y - 2.2) < EPS, "Barrel is 2.2 tall (the part build)")
			t.ok(layout.size.X <= 1.75 + EPS)
			-- A limit tighter than the fit wins.
			local small = Slots.Layout(barrel, Vector3.new(1, 1, 1))
			t.ok(small.scale < layout.scale)
			t.ok(math.max(small.size.X, small.size.Y, small.size.Z) <= 1 + EPS)
			-- GlowWire is turned a quarter: the GLB's 2.16 (Z) becomes the length along X.
			local wire = Slots.Get("GlowWire")
			t.eq(wire.yaw, 90)
			local turned = Slots.Layout(wire)
			t.ok(turned.size.X > turned.size.Z, "the wire lies along the 4 stud side")
			-- The piece is centred on the frame in X and Z, whatever its own centre was.
			local coins = Slots.Layout(Slots.Get("RobuxCoins"))
			local half = Slots.Get("RobuxCoins").pieces[1].size * coins.scale / 2
			local offset = coins.pieces[1].offset
			t.ok(math.abs(offset.Y - half.Y) < EPS, "the coin pile stands on y = 0")
			-- Two pieces of one slot keep their place in each other (the boots and their glow).
			local boots = Slots.Layout(Slots.Get("HeatBoots"))
			t.ok(boots.pieces[2].offset.Y < boots.pieces[1].offset.Y, "the glow strip is under the boot")
		end
	)

	-- The GLB's JSON chunk: the nodes and their bounding boxes.
	local function glbNodes(path)
		local data = fs.readFile(path)
		t.eq(string.sub(data, 1, 4), "glTF", path .. " is a GLB")
		local length = string.unpack("<I4", data, 13)
		local doc = serde.decode("json", string.sub(data, 21, 20 + length))
		local out = {}
		for _, node in ipairs(doc.nodes) do
			if node.mesh ~= nil then
				local lo, hi = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
				for _, prim in ipairs(doc.meshes[node.mesh + 1].primitives) do
					local acc = doc.accessors[prim.attributes.POSITION + 1]
					for i = 1, 3 do
						lo[i] = math.min(lo[i], acc.min[i])
						hi[i] = math.max(hi[i], acc.max[i])
					end
				end
				out[node.name] = { lo = lo, hi = hi }
			end
		end
		return out
	end

	t.test("GLB sources are in the repo and the slot data is each GLB's own bounding box", function()
		local Slots = world(false).Slots
		for _, slot in ipairs(Slots.All) do
			t.ok(fs.isFile(slot.glb), slot.id .. " GLB missing: " .. slot.glb)
			local nodes = glbNodes(slot.glb)
			for _, piece in ipairs(slot.pieces) do
				local node = nodes[piece.name]
				t.ok(node ~= nil, slot.id .. " has no node " .. piece.name)
				local size = { node.hi[1] - node.lo[1], node.hi[2] - node.lo[2], node.hi[3] - node.lo[3] }
				local centre = {
					(node.hi[1] + node.lo[1]) / 2,
					(node.hi[2] + node.lo[2]) / 2,
					(node.hi[3] + node.lo[3]) / 2,
				}
				for i, axis in ipairs({ "X", "Y", "Z" }) do
					t.ok(
						math.abs(size[i] - piece.size[axis]) < 0.02,
						string.format(
							"%s/%s size %s: glb %.3f, data %.3f",
							slot.id,
							piece.name,
							axis,
							size[i],
							piece.size[axis]
						)
					)
					t.ok(
						math.abs(centre[i] - piece.centre[axis]) < 0.02,
						string.format(
							"%s/%s centre %s: glb %.3f, data %.3f",
							slot.id,
							piece.name,
							axis,
							centre[i],
							piece.centre[axis]
						)
					)
				end
			end
		end
	end)

	t.test("every GLB in assets/glb/store-items has a slot, or is another lane's on purpose", function()
		local have = {}
		for _, slot in ipairs(world(false).Slots.All) do
			have[slot.id] = true
		end
		for _, file in ipairs(fs.readDir("assets/glb/store-items")) do
			local name = string.match(file, "^(.+)%.glb$")
			t.ok(name ~= nil, file .. " is a GLB")
			t.ok(have[name] or OTHER_LANE[name], name .. " is registered nowhere")
			if OTHER_LANE[name] then
				t.eq(have[name], nil, name .. " belongs to the other lane (Hearth and Home): no slot here")
			end
		end
	end)

	t.test("the preview export registers every slot GLB (tools/preview/export.luau)", function()
		local source = fs.readFile("tools/preview/export.luau")
		t.ok(string.find(source, "registerStoreSlots", 1, true) ~= nil)
		t.ok(string.find(source, "PreviewIds", 1, true) ~= nil)
		t.ok(string.find(source, "PREVIEW_STORE_GLBS", 1, true) ~= nil)
	end)

	t.test("only uploaded ids are preloaded, and a slot's ids are read from the one place they live", function()
		local W = world(false)
		local ids = W.Slots.MeshIds()
		for _, id in ipairs(ids) do
			t.ok(id ~= 0)
		end
		local seen = {}
		for _, group in ipairs(W.MeshManifest.Groups(false)) do
			for _, entry in ipairs(group.entries) do
				seen[entry.id] = true
			end
		end
		for _, id in ipairs(ids) do
			t.ok(seen[id], tostring(id) .. " is in the preload")
		end
		-- The gear reads BacklogModels (no second copy of an id).
		local BacklogModels = t.load("ReplicatedStorage/Shared/Art/BacklogModels")
		local coat = BacklogModels.Get("InsulatedCoat").pieces[1]
		t.eq(W.Slots.Get("InsulatedCoat").pieces[1].meshId, coat.meshId)
		-- The lamp post is the plot item's mesh (ItemMeshData), the placed item's own ids.
		local ItemMeshData = t.shared("ItemMeshData")
		t.eq(
			W.Slots.Get("LampPost").pieces[1].meshId,
			tonumber(string.match(ItemMeshData.List("LampPost")[1].meshId, "%d+"))
		)
		-- Placed lamp posts stay with ItemMeshes: the slot adds no second mesh to a plan.
		local M = world(true)
		local lamp = M.BlueprintModels.Build(M.PlotData.Blueprint("LampPost"), false)
		for _, mesh in ipairs(meshParts(lamp)) do
			t.ok(mesh:GetAttribute("StoreModel") == nil, "no StoreModel mesh on a placed lamp post")
		end
	end)

	t.test("a made-up id is only a preview seam: with it off an unset id stays 0", function()
		local W = world(false)
		local barrel = W.Slots.Get("Barrel")
		local uploaded = barrel.pieces[1].meshId
		barrel.pieces[1].meshId = 0
		t.eq(W.Slots.MeshIdOf(barrel, barrel.pieces[1]), 0)
		W.Slots.PreviewIds = { ["Barrel/Barrel"] = 123 }
		t.eq(W.Slots.MeshIdOf(barrel, barrel.pieces[1]), 123)
		W.Slots.PreviewIds = nil
		t.eq(W.Slots.MeshIdOf(barrel, barrel.pieces[1]), 0)
		barrel.pieces[1].meshId = uploaded
	end)
end
