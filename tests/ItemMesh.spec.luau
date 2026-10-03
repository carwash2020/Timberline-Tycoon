--!nocheck
-- H1: plot meshes are visual only, the Stairs collider is a wedge, and a
-- save from before meshes still loads. No new save fields.
return function(t)
	local PlotData = t.shared("PlotData")
	local ItemMeshData = t.shared("ItemMeshData")
	local ItemMeshes = t.shared("ItemMeshes")
	local BlueprintModels = t.shared("BlueprintModels")

	local function near(a, b)
		return math.abs(a - b) < 1e-3
	end

	local function sameVec(part, box, id)
		t.ok(
			near(part.Size.X, box.size.X) and near(part.Size.Y, box.size.Y) and near(part.Size.Z, box.size.Z),
			id .. " size"
		)
		t.ok(
			near(part.CFrame.Position.X, box.offset.X)
				and near(part.CFrame.Position.Y, box.offset.Y)
				and near(part.CFrame.Position.Z, box.offset.Z),
			id .. " offset"
		)
	end

	local function partNamed(model, name)
		for _, child in ipairs(model:GetChildren()) do
			if child.Name == name then
				return child
			end
		end
		return nil
	end

	t.test("H1: every uploaded item has 1 to 4 visible meshes and no collision mesh", function()
		local ids = {}
		for id in pairs(ItemMeshData.Items) do
			table.insert(ids, id)
		end
		table.sort(ids)
		t.eq(#ids, 21)
		for _, id in ipairs(ids) do
			local list = ItemMeshData.List(id)
			t.ok(#list >= 1 and #list <= ItemMeshData.MaxMeshes, id .. " mesh count " .. #list)
			for _, def in ipairs(list) do
				t.ok(def.name ~= "Collision", id .. " must not use the collision mesh")
				t.ok(string.match(def.meshId, "^rbxassetid://%d+$") ~= nil, id)
			end
		end
	end)

	t.test("H1: footprints stay put and Stairs is a wedge rising 4 toward +Z", function()
		local expect = {
			Wall = { 8, 1 },
			Floor = { 8, 8 },
			Door = { 4, 1 },
			Window = { 4, 1 },
			Stairs = { 4, 8 },
			Shed = { 10, 8 },
			WoodSign = { 4, 1 },
			PaintCan = { 2, 2 },
			Mailbox = { 2, 2 },
			Fence = { 8, 1 },
			FlowerBed = { 4, 4 },
			Bench = { 4, 2 },
			LampPost = { 2, 2 },
			LogPile = { 6, 4 },
			Flag = { 2, 4 },
			Cabin = { 12, 10 },
			Warehouse = { 16, 12 },
			AxeRack = { 6, 2 },
		}
		for id, fp in pairs(expect) do
			local bp = PlotData.Blueprint(id)
			t.eq({ bp.footprint.X, bp.footprint.Y }, fp, id)
			t.eq(bp.priceCash > 0, true, id)
		end
		local stairs = PlotData.Blueprint("Stairs")
		local box = stairs.boxes[1]
		t.eq(box.shape, "Wedge")
		t.eq({ box.size.X, box.size.Y, box.size.Z }, { 4, 4, 8 })
		t.eq({ box.offset.X, box.offset.Y, box.offset.Z }, { 0, 2, 0 })
		t.eq(box.offset.Y - box.size.Y / 2, 0, "the low end sits on the ground")
	end)

	t.test("H1: a missing mesh keeps the old parts, including the stair wedge", function()
		ItemMeshes.Install(nil)
		for _, bp in ipairs(PlotData.Blueprints) do
			local model = BlueprintModels.Build(bp, false)
			local visual = 0
			for _, child in ipairs(model:GetChildren()) do
				if child:GetAttribute("ItemVisual") == true then
					visual += 1
				end
			end
			t.eq(visual, 0, bp.id)
			for i, box in ipairs(bp.boxes) do
				local part = partNamed(model, "Part" .. i)
				t.ok(part, bp.id .. " part " .. i)
				sameVec(part, box, bp.id)
				t.eq(part.Transparency, 0, bp.id)
				t.eq(part.CanCollide, true, bp.id)
				if box.shape == "Wedge" then
					t.eq(part.ClassName, "WedgePart", bp.id)
				end
			end
		end
		ItemMeshes.Install(nil)
	end)

	t.test("H1: a loaded mesh is visual only and the collider box is unchanged", function()
		ItemMeshes.Install(nil)
		local function template(id)
			local model = t.roblox.Instance.new("Model")
			model.Name = id
			for _, def in ipairs(ItemMeshData.List(id)) do
				local part = t.roblox.Instance.new("Part")
				part.Name = def.name
				part.Size = def.size
				part.Parent = model
			end
			local collision = t.roblox.Instance.new("Part")
			collision.Name = "Collision"
			collision.Parent = model
			return model
		end
		for _, bp in ipairs(PlotData.Blueprints) do
			ItemMeshes.Install(bp.id, template(bp.id))
			local model = BlueprintModels.Build(bp, false)
			local visuals = {}
			for _, child in ipairs(model:GetChildren()) do
				if child:GetAttribute("ItemVisual") == true then
					table.insert(visuals, child)
				end
			end
			t.eq(#visuals, ItemMeshData.Count(bp.id), bp.id)
			for _, mesh in ipairs(visuals) do
				t.eq(mesh.Name ~= "Collision", true, bp.id)
				t.eq(mesh.Massless, true, bp.id)
				t.eq(mesh.CanCollide, false, bp.id)
				t.eq(mesh.CanTouch, false, bp.id)
				t.eq(mesh.CanQuery, false, bp.id)
				t.ok(mesh:FindFirstChild("MeshWeld"), bp.id .. " weld")
			end
			for i, box in ipairs(bp.boxes) do
				local part = partNamed(model, "Part" .. i)
				sameVec(part, box, bp.id)
				t.eq(part.Transparency, 1, bp.id .. " collider hidden")
				t.eq(part.CanCollide, true, bp.id .. " still collides")
			end
			ItemMeshes.Install(bp.id, nil)
		end
		ItemMeshes.Install(nil)
	end)

	t.test("H1: an old plot save round-trips with no mesh fields", function()
		local Schema = t.server("ProfileSchema")
		local Util = t.shared("Util")
		local data = Util.deepCopy(Schema.Template)
		data.plot.claimed = true
		data.plot.placed = {
			{ uid = "wall-1", blueprintId = "Wall", x = 4, z = -2, rot = 1 },
			{ uid = "stair-1", blueprintId = "Stairs", x = 8, z = 0, rot = 0 },
		}
		Schema.Migrate(data)
		t.eq(#data.plot.placed, 2)
		t.eq(data.plot.placed[1].blueprintId, "Wall")
		t.eq(data.plot.placed[1].x, 4)
		t.eq(data.plot.placed[1].rot, 1)
		t.eq(data.plot.placed[1].wood, nil)
		t.eq(data.plot.placed[1].y, nil)
		local bp = PlotData.Blueprint(data.plot.placed[2].blueprintId)
		local model = BlueprintModels.Build(bp, false)
		local wedge = partNamed(model, "Part1")
		t.eq(wedge.ClassName, "WedgePart")
		t.eq({ wedge.Size.X, wedge.Size.Y, wedge.Size.Z }, { 4, 4, 8 })
	end)
end
