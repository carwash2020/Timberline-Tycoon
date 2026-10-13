--!nocheck
local fs = require("@lune/fs")
-- ModelSlots: the four items whose real models are still being made in Blender (Flashlight, Lantern,
-- Wood Sign, Shed Blueprint) each have ONE slot and ONE mesh id. The display (box window and back
-- ledge), the held item and the placed item all read that slot, so a real mesh id dropped into it
-- swaps in everywhere with no other code change; with id 0 every path keeps its part-built look.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame, Color3 = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3
	local serde = require("@lune/serde")
	local ModelSlots = t.load("ReplicatedStorage/Shared/Art/ModelSlots")
	local TownMeshes = t.load("ReplicatedStorage/Shared/Art/TownMeshes")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local ItemModel = t.load("ReplicatedStorage/Shared/Art/ItemModel")
	local BoxArt = t.load("ReplicatedStorage/Shared/Art/BoxArt")
	local BlueprintArt = t.load("ReplicatedStorage/Shared/Art/BlueprintArt")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local BlueprintModels = t.shared("BlueprintModels")
	local PlotData = t.shared("PlotData")
	local ItemBox = t.shared("ItemBox")
	local StoreStock = t.shared("StoreStock")

	local ITEMS = {
		{ name = "Flashlight", kind = "Gear", id = "Flashlight" },
		{ name = "Lantern", kind = "Gear", id = "Lantern" },
		{ name = "WoodSign", kind = "Blueprint", id = "WoodSign" },
		{ name = "ShedBlueprint", kind = "Blueprint", id = "Shed" },
	}

	local function withMeshes(fn)
		MeshKit.Reset()
		MeshKit.Override = function(_id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	local function setId(slot, id)
		local old = slot.meshId
		slot.meshId = id
		return function()
			slot.meshId = old
		end
	end

	local function slotted(root, slot, role)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("ModelSlot") == slot.name then
				if role == nil or d:GetAttribute("SlotRole") == role then
					table.insert(out, d)
				end
			end
		end
		return out
	end

	t.test("the four items have one slot each, named, with no model yet", function()
		t.eq(#ModelSlots.Slots, 4)
		for _, item in ipairs(ITEMS) do
			local slot = ModelSlots.For(item.kind, item.id)
			t.ok(slot, item.name .. " has a slot")
			t.eq(slot.name, item.name)
			t.eq(ModelSlots.Named(item.name), slot, "one slot, found by name or by item")
			t.eq(slot.meshId, 0, item.name .. ": the model is not made yet, so the part-built look stays")
			t.eq(ModelSlots.IsSet(slot), false)
			t.ok(#slot.pivot > 10, item.name .. " says what pivot the model needs")
		end
		t.eq(ModelSlots.For("Gear", "InsulatedCoat"), nil, "other items have none")
	end)

	-- The GLB's own bounding box (the POSITION accessors' min and max), read from the file.
	local function glbBounds(path)
		local data = fs.readFile(path)
		t.eq(string.sub(data, 1, 4), "glTF", path .. " is a GLB")
		local offset = 13
		local doc
		while offset + 8 <= #data + 1 do
			local length, kind = string.unpack("<I4I4", data, offset)
			if kind == 0x4E4F534A then
				doc = serde.decode("json", string.sub(data, offset + 8, offset + 7 + length))
				break
			end
			offset += 8 + length
		end
		local lo = { math.huge, math.huge, math.huge }
		local hi = { -math.huge, -math.huge, -math.huge }
		for _, mesh in ipairs(doc.meshes) do
			for _, prim in ipairs(mesh.primitives) do
				local acc = doc.accessors[prim.attributes.POSITION + 1]
				for i = 1, 3 do
					lo[i] = math.min(lo[i], acc.min[i])
					hi[i] = math.max(hi[i], acc.max[i])
				end
			end
		end
		return Vector3.new(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
	end

	t.test("a slot's size is Connor's GLB at one uniform scale (so the model is never squashed)", function()
		for _, item in ipairs(ITEMS) do
			local slot = ModelSlots.For(item.kind, item.id)
			t.eq(slot.glb, "assets/glb/store-items/" .. item.name .. ".glb")
			local bounds = glbBounds(slot.glb)
			for _, axis in ipairs({ "X", "Y", "Z" }) do
				t.ok(
					math.abs(bounds[axis] - slot.glbSize[axis]) <= 0.002,
					string.format(
						"%s %s: the file is %.3f, glbSize says %.3f",
						item.name,
						axis,
						bounds[axis],
						slot.glbSize[axis]
					)
				)
				t.ok(
					math.abs(slot.glbSize[axis] * slot.fit - slot.size[axis]) <= 0.01,
					item.name .. " " .. axis .. ": size is glbSize times fit"
				)
			end
			-- and about the size of the part-built item it stands in for (never tiny, never huge)
			local ext = ItemModel.Extent(item.kind, item.id)
			local ratio = math.max(slot.size.X, slot.size.Y, slot.size.Z) / math.max(ext.X, ext.Y, ext.Z)
			if slot.placedAs ~= "dropped" then
				t.ok(ratio > 0.5 and ratio < 2, item.name .. " is a sensible size: " .. ratio)
			end
		end
	end)

	t.test("id 0: the display, held and placed paths keep their part-built look", function()
		for _, item in ipairs(ITEMS) do
			local slot = ModelSlots.For(item.kind, item.id)
			local size = ItemBox.Size(item.kind, item.id)
			local model = Instance.new("Model")
			local body = Instance.new("Part")
			body.Name = "Box"
			body.Size = size
			body.CFrame = CFrame.new(0, size.Y / 2, 0)
			body.Parent = model
			BoxArt.Dress(
				model,
				body,
				{ name = "Item", kind = item.kind, itemId = item.id, color = Color3.fromRGB(60, 90, 160) }
			)
			t.eq(#slotted(model, slot), 0, item.name .. " display: no slot mesh")
			local held = ItemModel.Held(item.kind, item.id)
			t.ok(held and #held:GetDescendants() > 0, item.name .. " has a held model")
			t.eq(#slotted(held, slot), 0, item.name .. " held: no slot mesh")
			local placed = ItemModel.Placed(item.kind, item.id)
			t.ok(placed and #placed:GetDescendants() > 0, item.name .. " has a placed model")
			t.eq(#slotted(placed, slot), 0, item.name .. " placed: no slot mesh")
		end
	end)

	t.test("one id in the slot swaps the real model in on the display, held and placed paths", function()
		for _, item in ipairs(ITEMS) do
			local slot = ModelSlots.For(item.kind, item.id)
			local restore = setId(slot, 123456)
			local ok, err = pcall(function()
				withMeshes(function()
					-- display: the box's window copy
					local size = ItemBox.Size(item.kind, item.id)
					local model = Instance.new("Model")
					local body = Instance.new("Part")
					body.Name = "Box"
					body.Size = size
					body.CFrame = CFrame.new(0, size.Y / 2, 0)
					body.Parent = model
					BoxArt.Dress(
						model,
						body,
						{ name = "Item", kind = item.kind, itemId = item.id, color = Color3.fromRGB(60, 90, 160) }
					)
					local shown = slotted(model, slot, "display")
					t.eq(#shown, 1, item.name .. " display uses the slot")
					t.eq(shown[1]:GetAttribute("MeshId"), "123456")
					-- held
					local held = ItemModel.Held(item.kind, item.id)
					t.eq(#slotted(held, slot, "held"), 1, item.name .. " held uses the slot")
					-- placed
					local placed = ItemModel.Placed(item.kind, item.id)
					t.eq(#slotted(placed, slot, "placed"), 1, item.name .. " placed uses the slot")
				end)
			end)
			restore()
			if not ok then
				error(err, 0)
			end
		end
	end)

	t.test("the Wood Sign on a plot takes the slot model and keeps its boxes as the collider", function()
		for _, id in ipairs({ "WoodSign" }) do
			local slot = ModelSlots.For("Blueprint", id)
			local restore = setId(slot, 123456)
			local ok, err = pcall(function()
				withMeshes(function()
					local bp = PlotData.Blueprint(id)
					local solid = BlueprintModels.Build(bp, false)
					local mesh = slotted(solid, slot, "placed")
					t.eq(#mesh, 1, id .. " placed model")
					t.eq(mesh[1].Transparency, 0)
					local ghost = BlueprintModels.Build(bp, true)
					local seen = slotted(ghost, slot, "placed")
					t.eq(#seen, 1, id .. " ghost model")
					t.ok(seen[1].Transparency > 0.3, "a ghost is see-through")
					for _, child in ipairs(solid:GetChildren()) do
						if child:IsA("BasePart") and string.sub(child.Name, 1, 4) == "Part" then
							t.eq(child.Transparency, 1, "the box is only the collider")
						end
					end
				end)
			end)
			restore()
			if not ok then
				error(err, 0)
			end
		end
	end)

	t.test("a held plan with a slot model shows it at roll size, the roll hidden", function()
		local slot = ModelSlots.For("Blueprint", "Shed")
		local restore = setId(slot, 123456)
		local ok, err = pcall(function()
			withMeshes(function()
				local held = BlueprintArt.Held("Shed")
				local mesh = slotted(held, slot, "held")
				t.eq(#mesh, 1)
				t.ok(
					math.max(mesh[1].Size.X, mesh[1].Size.Y, mesh[1].Size.Z) <= 1.6,
					"scaled down to the roll's length"
				)
				t.eq(held.PrimaryPart.Transparency, 1, "the handle stays (a Tool needs it) but is invisible")
			end)
		end)
		restore()
		if not ok then
			error(err, 0)
		end
	end)

	t.test("the General Store's back ledge shows the four slot models when they are set", function()
		local restores = {}
		for _, slot in ipairs(ModelSlots.Slots) do
			table.insert(restores, setId(slot, 123456))
		end
		local townWas = TownMeshes.Enabled
		TownMeshes.Enabled = false -- (as in the game today: the shop is part-built, so its ledge samples are parts)
		local ok, err = pcall(function()
			withMeshes(function()
				local shop = BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", Color3.fromRGB(47, 93, 58))
				for _, slot in ipairs(ModelSlots.Slots) do
					local list = slotted(shop, slot, "display")
					t.eq(#list, 1, slot.name .. " on the ledge")
					t.ok(list[1].CFrame.Position.Y > 3.3, slot.name .. " stands on the ledge, not in it")
				end
			end)
		end)
		TownMeshes.Enabled = townWas
		for _, r in ipairs(restores) do
			r()
		end
		if not ok then
			error(err, 0)
		end
		t.ok(StoreStock.Find("Gear", "Flashlight") ~= nil)
	end)

	t.test(
		"the Shed Blueprint's model is the plan: the shed ghost on a plot stays part-built, the dropped plan swaps",
		function()
			local slot = ModelSlots.For("Blueprint", "Shed")
			local restore = setId(slot, 123456)
			local ok, err = pcall(function()
				withMeshes(function()
					local ghost = BlueprintModels.Build(PlotData.Blueprint("Shed"), true)
					t.eq(#slotted(ghost, slot), 0, "you build the shed yourself: its ghost is not the blueprint model")
					local dropped = BlueprintArt.Dropped("Shed")
					t.eq(#slotted(dropped, slot, "placed"), 1, "the plan lying in the world uses the slot")
				end)
			end)
			restore()
			if not ok then
				error(err, 0)
			end
		end
	)
end
