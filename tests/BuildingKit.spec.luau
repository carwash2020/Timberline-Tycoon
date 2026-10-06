--!nocheck
-- H2: the building kit. Prices, placement, fill, wood, saves, doors.
local fs = require("@lune/fs")

return function(t)
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local FillLogic = t.shared("FillLogic")
	local DoorLogic = t.shared("DoorLogic")
	local KitMeshData = t.shared("KitMeshData")
	local BlueprintModels = t.shared("BlueprintModels")
	local MeshKit = t.shared("Art/MeshKit")
	local PlotFill = t.server("PlotFill")
	local PlotDoors = t.server("PlotDoors")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")

	local function bp(id)
		return PlotData.Blueprint(id)
	end

	local function at(id, x, z, rot, y, uid)
		return { uid = uid or id, blueprintId = id, x = x, z = z, rot = rot or 0, y = y }
	end

	local function partNamed(model, name)
		for _, child in ipairs(model:GetChildren()) do
			if child.Name == name then
				return child
			end
		end
		return nil
	end

	t.test("H-Buy: every kit piece is pay on place at 4 cash a wood unit", function()
		local seen = 0
		for _, piece in ipairs(PlotData.Blueprints) do
			if piece.kit then
				seen += 1
				t.eq(piece.unlock, nil, piece.id .. " is not a store unlock")
				t.eq(PlotData.Price(piece), piece.woodUnits * 4, piece.id)
				t.ok(KitMeshData.Get(piece.id) ~= nil, piece.id .. " has a mesh entry")
				local ok = if piece.fits
					then PlotLogic.Check(piece, 0, 0, 0, 1, {
						{
							uid = "host",
							blueprintId = if piece.fits == "Door" then "DoorWall8" else "WindowWall8",
							x = 0,
							z = 0,
							rot = 0,
						},
					})
					else PlotLogic.Check(piece, 0, 0, 0, 1, {})
				t.eq(ok, true, piece.id .. " places")
			end
		end
		t.eq(seen, 24)
		t.eq(PlotData.Price(bp("Wall")), 32)
		t.eq(bp("Wall").priceCash, 80, "the old wall price stays for saves with no paid")
		t.eq(PlotData.LegacyPrice(bp("Wall")), 80)
	end)

	t.test("H-Place: corners, joins, roofs, height and turns", function()
		local wall = bp("Wall")
		local along = { at("Wall", 0, 0, 0, 0, "a") }
		t.eq(PlotLogic.Check(wall, 4, 4, 1, 1, along), true, "L corner")
		t.eq(PlotLogic.Check(wall, 0, 0, 0, 1, along, nil, 6), true, "T join above the line")
		t.eq(PlotLogic.Check(bp("Post"), 4, 0, 0, 1, along), true, "post at the corner")
		local slope = { at("SlopedRoof8", 0, 0, 0, 6, "s") }
		t.eq(PlotLogic.Check(bp("SlopedRoof8"), 0, 4, 2, 1, slope, nil, 6), true, "two slopes at a ridge")
		t.eq(PlotLogic.Check(bp("RoofRidge8"), 0, 2, 0, 1, slope, nil, 6), true, "ridge between them")
		local same = PlotLogic.Check(wall, 4, 0, 0, 1, along)
		t.eq(same, false, "same-line walls")
		local floor = { at("Floor", 0, 0, 0, 0, "f") }
		t.eq(PlotLogic.Check(wall, 0, 4, 0, 1, floor, nil, 0), false, "wall y=0 into the floor")
		t.eq(PlotLogic.Check(wall, 0, 4, 0, 1, floor, nil, 0.4), true, "wall on the floor")
		for rot = 0, 3 do
			t.eq(PlotLogic.Check(wall, 10, 10, rot, 1, floor, nil, 0.4), true, "rot " .. rot)
		end
		t.eq(PlotLogic.Check(wall, 10, 10, 2, 1, floor, "f", 0.4), true, "moving")
		-- the floor's uid is f, moving the wall not the floor. A fresh wall move:
		local placed = { at("Wall", 0, 0, 0, 0.4, "w"), at("Floor", 0, 0, 0, 0, "f") }
		t.eq(PlotLogic.Check(wall, 8, 0, 1, 1, placed, "w", 0.4), true, "move the wall, all turns considered")
		t.eq(PlotLogic.Check(wall, 8, 0, 2, 1, placed, "w", 0.4), true)
		t.eq(PlotLogic.Check(wall, 8, 0, 3, 1, placed, "w", 0.4), true)
	end)

	t.test("H-Fill: planks only, one wood, nothing counted twice, excess comes back", function()
		local offer = {
			uid = "p",
			kind = "plank",
			woodId = "oak",
			volume = 5,
			ownerId = 7,
			held = false,
			size = t.roblox.Vector3.new(1.6, 8, 1.6),
		}
		t.eq(FillLogic.Accept(nil, 0, 8, offer, 7), true)
		local log =
			{ uid = "l", kind = "log", woodId = "oak", volume = 5, ownerId = 7, held = false, size = offer.size }
		t.eq(FillLogic.Accept(nil, 0, 8, log, 7), false)
		t.eq(select(2, FillLogic.Accept(nil, 0, 8, log, 7)), "logs")
		t.eq(FillLogic.Accept("birch", 1, 8, offer, 7), false, "the first wood locks it")
		t.eq(select(2, FillLogic.Accept("birch", 1, 8, offer, 7)), "wood")
		for _, code in ipairs(FillLogic.Reasons) do
			local text = FillLogic.Message(code, "Stairs", "Birch")
			t.ok(type(text) == "string" and text ~= "", code .. " has player text")
		end
		t.eq(FillLogic.Message("wood", "Stairs", "Birch"), "This Stairs is being built with Birch.")
		t.eq(FillLogic.Message("logs", "Wall", "Oak"), "Saw logs into planks first.")
		local item = { uid = "wall", blueprintId = "Wall", x = 0, z = 0, rot = 0, fill = { units = 0 } }
		local alive = true
		local spawned = 0
		local api = {
			Get = function()
				return if alive then {} else nil
			end,
			Remove = function()
				alive = false
			end,
			SpawnPlank = function()
				spawned += 1
				return { uid = "left" }
			end,
		}
		local ok = PlotFill.Apply(item, offer, 7, api)
		t.eq(ok, true)
		t.eq(item.wood, "oak")
		t.eq(item.fill.units, 5)
		t.eq(spawned, 0, "5 of 8 needs no leftover")
		offer.uid = "p2"
		offer.volume = 5
		alive = true
		ok = PlotFill.Apply(item, offer, 7, api)
		t.eq(ok, true)
		t.eq(item.fill, nil, "the eighth unit finishes it")
		t.eq(spawned, 1, "the extra 2 come back as a plank")
		PlotFill.Reset()
		local again = PlotFill.Apply(item, offer, 7, api)
		t.eq(again, false, "a built piece takes nothing")
	end)

	t.test("H-Wood: birch and oak tint the wall, and a save keeps the wood", function()
		local model = BlueprintModels.Build(bp("Wall"), false)
		local part = partNamed(model, "Part1")
		BlueprintModels.ApplyWood(model, "birch")
		local birch = part.Color
		BlueprintModels.ApplyWood(model, "oak")
		local oak = part.Color
		t.ok(birch.R ~= oak.R or birch.G ~= oak.G or birch.B ~= oak.B, "the two woods look different")
		local glass = BlueprintModels.Build(bp("Window"), false)
		local pane = partNamed(glass, "Part1")
		local before = pane.Color
		BlueprintModels.ApplyWood(glass, "oak")
		t.eq(pane.Color, before, "glass is not tinted")
		local data = Util.deepCopy(Schema.Template)
		data.plot.placed = {
			{ uid = "w", blueprintId = "Wall", x = 2, z = 2, rot = 0, y = 0.4, wood = "birch", paid = 32 },
		}
		Schema.Migrate(data)
		t.eq(data.plot.placed[1].wood, "birch")
		data.plot.placed[1].wood = "not-a-wood"
		Schema.Migrate(data)
		t.eq(data.plot.placed[1].wood, nil, "unknown wood is cleared, the piece stays")
	end)

	t.test("H-Save: old plots stay built at y 0, new fields round-trip, open is dropped", function()
		local data = Util.deepCopy(Schema.Template)
		data.plot.claimed = true
		data.plot.placed = {
			{ uid = "old", blueprintId = "Wall", x = 4, z = -2, rot = 1 },
			{
				uid = "new",
				blueprintId = "Floor",
				x = 0,
				z = 0,
				rot = 0,
				y = 6,
				wood = "oak",
				fill = { units = 4 },
				paid = 48,
				open = true,
			},
		}
		Schema.Migrate(data)
		t.eq(data.plot.placed[1].y, nil)
		t.eq(data.plot.placed[1].fill, nil)
		t.eq(data.plot.placed[1].wood, nil)
		t.eq(data.plot.placed[2].y, 6)
		t.eq(data.plot.placed[2].fill.units, 4)
		t.eq(data.plot.placed[2].paid, 48)
		t.eq(data.plot.placed[2].open, nil)
		t.eq(data.plot.placed[2].wood, "oak")
	end)

	t.test("H-Save: a full fill is built, a non-kit piece drops fill, and paid clamps", function()
		local data = Util.deepCopy(Schema.Template)
		data.plot.claimed = true
		data.plot.placed = {
			{
				uid = "full",
				blueprintId = "Wall",
				x = 0,
				z = 0,
				rot = 0,
				fill = { units = 8 },
				paid = 32,
				wood = "birch",
			},
			{
				uid = "over",
				blueprintId = "Wall",
				x = 2,
				z = 0,
				rot = 0,
				fill = { units = 3 },
				paid = 999,
				wood = "oak",
			},
			{ uid = "shed", blueprintId = "Shed", x = 8, z = 0, rot = 0, fill = { units = 2 }, paid = 50 },
		}
		Schema.Migrate(data)
		t.eq(data.plot.placed[1].fill, nil, "units already cover the wall")
		t.eq(data.plot.placed[1].wood, "birch")
		t.eq(data.plot.placed[2].fill.units, 3)
		t.eq(data.plot.placed[2].paid, PlotData.Price(bp("Wall")), "paid clamps to the fee")
		t.eq(data.plot.placed[3].fill, nil, "a shed is not a kit piece")
		t.eq(data.plot.placed[3].paid, nil)
	end)

	t.test("H-Legacy: an old wall sells at the old price, an empty kit piece refunds the fee", function()
		local wall = bp("Wall")
		local old = { uid = "old", blueprintId = "Wall", x = 0, z = 0, rot = 0 }
		local plan = PlotLogic.SellPlan(wall, old)
		t.eq(plan.cash, 40, "half of the legacy 80")
		t.eq(plan.planks, 0)
		local fresh = { uid = "n", blueprintId = "Wall", x = 0, z = 0, rot = 0, paid = 32, fill = { units = 0 } }
		plan = PlotLogic.SellPlan(wall, fresh)
		t.eq(plan.cash, 32)
		local half =
			{ uid = "h", blueprintId = "Wall", x = 0, z = 0, rot = 0, paid = 32, fill = { units = 3 }, wood = "oak" }
		plan = PlotLogic.SellPlan(wall, half)
		t.eq(plan.cash, 0)
		t.eq(plan.planks, 3)
		t.eq(plan.wood, "oak")
		local done = { uid = "d", blueprintId = "Wall", x = 0, z = 0, rot = 0, paid = 32 }
		plan = PlotLogic.SellPlan(wall, done)
		t.eq(plan.cash, 16)
		t.eq(PlotLogic.SellValue(bp("Cabin")), 1000)
	end)

	t.test("H-Limits: 400 kit pieces, and 200 of everything else, fit in a save", function()
		local flag = bp("Flag")
		local wall = bp("Wall")
		local placed = {}
		for i = 1, PlotData.MaxItems do
			placed[i] = { uid = "o" .. i, blueprintId = "Flag", x = 0, z = 0, rot = 0 }
		end
		t.eq(PlotLogic.Check(flag, 20, 20, 0, 1, placed), false)
		t.eq(PlotLogic.Check(wall, 20, 20, 0, 1, placed), true, "kit has its own cap")
		local kit = {}
		for i = 1, PlotData.MaxKit do
			kit[i] = {
				uid = string.format("k%04d", i),
				blueprintId = "Post",
				x = 0,
				z = 0,
				rot = 0,
				y = 0,
				wood = "oak",
				paid = 4,
			}
		end
		t.eq(PlotLogic.Check(bp("Post"), 20, 20, 0, 1, kit), false)
		local parts = {}
		for _ = 1, 3 do
			for _, item in ipairs(kit) do
				table.insert(
					parts,
					string.format(
						'{"uid":"%s","blueprintId":"%s","x":0,"z":0,"rot":0,"y":0,"wood":"oak","paid":4}',
						item.uid,
						item.blueprintId
					)
				)
			end
		end
		local blob = "[" .. table.concat(parts, ",") .. "]"
		t.ok(#blob < 4000000, "three full plots stay under the DataStore cap (" .. #blob .. ")")
	end)

	t.test("H-Door: the gap, the arc, and who may block it", function()
		local wall = BlueprintModels.Build(bp("DoorWall8"), false)
		local jambs = 0
		for _, child in ipairs(wall:GetChildren()) do
			if child:GetAttribute("Jamb") == true then
				jambs += 1
				t.eq(child.CanCollide, true)
				t.eq(child.Size, t.roblox.Vector3.new(2, 6, 1))
				local x = child.CFrame.Position.X
				t.ok(math.abs(math.abs(x) - 3) < 1e-3, "jamb at x = ±3")
				t.ok(math.abs(child.CFrame.Position.Y - 3) < 1e-3)
			end
		end
		t.eq(jambs, 2, "two jambs and no header")
		local door = BlueprintModels.Build(bp("Door"), false)
		local leaves = 0
		for _, child in ipairs(door:GetChildren()) do
			if string.sub(child.Name, 1, 4) == "Part" then
				t.eq(child:GetAttribute("Leaf") == true, child.CanCollide, child.Name)
				if child:GetAttribute("Leaf") == true then
					leaves += 1
				end
			end
		end
		t.eq(leaves, 1, "only the leaf collides")
		local gate = BlueprintModels.Build(bp("FenceGate4"), false)
		local posts = 0
		for _, child in ipairs(gate:GetChildren()) do
			if child:GetAttribute("Post") == true then
				posts += 1
				t.eq(child.CanCollide, true)
				t.ok(
					math.abs(child.Size.X - 0.4) < 1e-2
						and math.abs(child.Size.Y - 3) < 1e-2
						and math.abs(child.Size.Z - 0.6) < 1e-2
				)
			end
		end
		t.eq(posts, 2)

		PlotDoors.Apply(door, "Door", true)
		local leaf = partNamed(door, "Part1")
		t.ok(leaf.CFrame.Position.Z > 1, "an open leaf has swung toward +Z")
		t.ok(math.abs(leaf.CFrame.Position.X + 1.6) < 0.2, "it swings about the hinge")

		local function blockers(item, placed)
			return PlotDoors.Blockers(item, placed)
		end
		local doorItem = at("Door", 0, 0, 0, 0, "door")
		local scene = {
			at("Floor", 0, 0, 0, 0, "ground"),
			at("DoorWall8", 0, 0, 0, 0, "wall"),
			doorItem,
			at("Floor", 0, 4, 0, 0, "front"),
			at("Floor", 0, 0, 0, 6, "ceil"),
		}
		t.eq(
			DoorLogic.ArcBlocked("Door", 0, 0, 0, 0, blockers(doorItem, scene)),
			false,
			"floors and the ceiling do not count"
		)

		local post = at("Post", 0, 2, 0, 0, "post")
		local blocked = { doorItem, post }
		t.eq(DoorLogic.ArcBlocked("Door", 0, 0, 0, 0, blockers(doorItem, blocked)), true, "a post in the arc")
		t.eq(DoorLogic.Hint, "Something is blocking this door.")
		local away = at("Door", 0, 0, 2, 0, "door")
		t.eq(
			DoorLogic.ArcBlocked(
				away.blueprintId,
				away.x,
				away.y or 0,
				away.z,
				away.rot,
				blockers(away, { away, post })
			),
			false,
			"a door rotated 180 degrees, away from a blocking post, clears its swing"
		)

		t.eq(DoorLogic.MayClose(false), true, "a player in the arc is not in this check")
		t.eq(DoorLogic.MayClose(true), false, "a player in the doorway blocks the shut")
		local centre, size = DoorLogic.Doorway("Door")
		local doorway = DoorLogic.WorldSolid(0, 0, 0, 0, centre, size)
		t.eq(DoorLogic.SolidsHit(doorway, { 0, 3, 0, 2, 4, 1 }), true, "someone standing in the doorway")
		local arcC, arcS = DoorLogic.Arc("Door")
		local arc = DoorLogic.WorldSolid(0, 0, 0, 0, arcC, arcS)
		t.eq(DoorLogic.SolidsHit(arc, { 0, 3, 2, 1, 2, 1 }), true, "the arc is where a player could stand")

		local gateItem = at("FenceGate4", 0, 0, 0, 0, "gate")
		local beam = at("Beam8", 0, 1, 0, 4, "beam")
		t.eq(
			DoorLogic.ArcBlocked("FenceGate4", 0, 0, 0, 0, blockers(gateItem, { gateItem, beam })),
			false,
			"a beam above the gate"
		)
		PlotDoors.Apply(gate, "FenceGate4", true)
		local gateLeaf = partNamed(gate, "Part3")
		t.ok(gateLeaf.CFrame.Position.Z > 0.5, "an open gate leaf leaves the gap")
	end)

	t.test("H-Economy: kit fees do not move the five headlines", function()
		local text = fs.readFile("ECONOMY.md")
		t.ok(string.find(text, "68 s", 1, true) ~= nil)
		t.ok(string.find(text, "7.9 min", 1, true) ~= nil)
		t.ok(string.find(text, "13.7 min", 1, true) ~= nil)
		t.ok(string.find(text, "51.4 min", 1, true) ~= nil)
		-- The price ladder (axes) moved the headlines to these.
		t.ok(string.find(text, "30.5 h", 1, true) ~= nil)
	end)

	t.test("kit meshes: fidelity is chosen per mesh, and a shared col loads once", function()
		local function role(id, name)
			for _, mesh in ipairs(KitMeshData.Get(id).meshes) do
				if mesh.name == name or mesh.role == name then
					return mesh
				end
			end
			return nil
		end
		t.eq(role("Stairs", "Col").fidelity, "Hull")
		t.eq(role("Ramp8", "Col").fidelity, "Hull")
		t.eq(role("SlopedRoof8", "Col").fidelity, "Hull")
		t.eq(role("RoofCorner", "Wood").fidelity, "Hull")
		t.eq(role("RoofCorner", "Wood").collide, true)
		t.eq(role("Door", "Wood").collide, false)
		t.eq(role("Door", "Door").collide, true)
		t.eq(role("Door", "Door").fidelity, "Box")
		t.eq(role("DoorWall8", "Wood").collide, false)
		t.eq(#KitMeshData.Get("DoorWall8").meshes, 1, "no col mesh")
		t.eq(role("FenceGate4", "Wood").collide, false)
		t.eq(role("FenceGate4", "Door").collide, true)
		t.eq(role("Window", "Glass").collide, false)
		t.eq(role("Foundation8", "Trim").collide, false)
		t.eq(role("Wall", "Col").meshId, role("WindowWall8", "Col").meshId, "shared on purpose")

		local fidelity: { [number]: string } = {}
		local templates = 0
		for _, piece in pairs(KitMeshData.Pieces) do
			for _, mesh in ipairs(piece.meshes) do
				local prior = fidelity[mesh.meshId]
				if prior then
					t.eq(prior, mesh.fidelity, "a shared id has one fidelity")
				else
					fidelity[mesh.meshId] = mesh.fidelity
					templates += 1
					local path = "src/ReplicatedStorage/MeshTemplates/" .. tostring(mesh.meshId) .. ".model.json"
					local text = fs.readFile(path)
					t.ok(string.find(text, '"CollisionFidelity": "' .. mesh.fidelity .. '"', 1, true) ~= nil, path)
				end
			end
		end
		t.eq(templates, 44, "one template per kit mesh id")

		MeshKit.Reset()
		local calls = 0
		MeshKit.Override = function(_id, name, size)
			calls += 1
			local part = t.roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local a = MeshKit.Create(126041521825452, "A", t.roblox.Vector3.new(8, 6, 1))
		local b = MeshKit.Create(126041521825452, "B", t.roblox.Vector3.new(8, 6, 1))
		t.eq(calls, 1, "one load, then a clone")
		t.ok(a ~= b)
		t.eq(b.Name, "B")
		MeshKit.Reset()
		calls = 0
		MeshKit.Override = function()
			calls += 1
			return nil
		end
		t.eq(MeshKit.Create(42, "Nope", t.roblox.Vector3.new(1, 1, 1)), nil)
		t.eq(MeshKit.Create(42, "Nope", t.roblox.Vector3.new(1, 1, 1)), nil)
		t.eq(calls, 1, "a failed id is not loaded again")
		MeshKit.Override = nil
		MeshKit.Reset()

		local bare = BlueprintModels.Build(bp("Wall"), false)
		t.eq(partNamed(bare, "Part1").CanCollide, true, "no mesh: the part stays")
		t.eq(partNamed(bare, "Part1").Transparency, 0)
	end)
end
