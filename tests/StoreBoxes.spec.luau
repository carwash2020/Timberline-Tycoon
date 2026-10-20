--!nocheck
-- Store boxes (T383): every box in every store is built all round (floor, walls or the
-- aisle pane, the glass front and top, a name strip, a price tag plate, a rim) with the real
-- item inside: the item's mesh when it has loaded, its part-built copy only while it has not.
-- The Switch Belt and the Wood Detector used to lose their frame to the machine mesh and show
-- loose bars: their display is the part build now, and the MachineMeshes pieces are the contents.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame, Color3, Enum =
		roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

	local function fresh()
		local loader = t.loader()
		return {
			BoxArt = loader:load("ReplicatedStorage/Shared/Art/BoxArt"),
			ItemModel = loader:load("ReplicatedStorage/Shared/Art/ItemModel"),
			MeshKit = loader:load("ReplicatedStorage/Shared/Art/MeshKit"),
			MachineMeshes = loader:load("ReplicatedStorage/Shared/Art/MachineMeshes"),
			StoreModelSlots = loader:shared("StoreModelSlots"),
			ItemBox = loader:shared("ItemBox"),
			StoreStock = loader:shared("StoreStock"),
			BoxLogic = loader:shared("BoxLogic"),
			BoxSize = loader:shared("BoxSize"),
		}
	end
	local env = fresh()

	-- Every StoreData item: the interior shops' slots and the Sparkworks counter's.
	local function allSlots()
		local out = {}
		for _, slot in ipairs(env.StoreStock.All()) do
			table.insert(out, slot)
		end
		for _, slot in ipairs(env.StoreStock.Sparkworks()) do
			table.insert(out, slot)
		end
		return out
	end

	-- `loaded`: every mesh asks MeshKit gets a part (the engine after the preload); false:
	-- none does (a mesh still loading, or failed).
	local function withMeshes(e, loaded, fn)
		e.MeshKit.Reset()
		e.MeshKit.Override = function(id, name, size)
			if not loaded then
				return nil
			end
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local ok, err = pcall(fn)
		e.MeshKit.Override = nil
		e.MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	local function dress(e, kind, id, side)
		local size = e.ItemBox.Size(kind, id)
		local model = Instance.new("Model")
		local body = Instance.new("Part")
		body.Name = "Box"
		body.Size = size
		body.CFrame = CFrame.new(0, size.Y / 2, 0)
		body.Parent = model
		e.BoxArt.Dress(model, body, { name = id, kind = kind, itemId = id, side = side })
		return model, body
	end

	local function contentsParts(model)
		local out = {}
		local contents = model:FindFirstChild("Contents")
		if contents then
			for _, d in ipairs(contents:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(out, d)
				end
			end
		end
		return out
	end

	-- The axis-aligned bounds of parts, turned corners included.
	local function bounds(list)
		local lo, hi
		for _, p in ipairs(list) do
			local h = p.Size / 2
			for _, x in ipairs({ -1, 1 }) do
				for _, y in ipairs({ -1, 1 }) do
					for _, z in ipairs({ -1, 1 }) do
						local c = p.CFrame * Vector3.new(h.X * x, h.Y * y, h.Z * z)
						lo = if lo then lo:Min(c) else c
						hi = if hi then hi:Max(c) else c
					end
				end
			end
		end
		return lo, hi
	end

	local BASIC = {
		Box = true,
		Base = true,
		Left = true,
		Right = true,
		Back = true,
		Window = true,
		WindowTop = true,
		SideWindow = true,
		Strip = true,
		Logo = true,
	}

	t.test("a fresh box has a floor, a far wall or pane, glass front and top, name strip and price tag", function()
		local n = 0
		for _, slot in ipairs(allSlots()) do
			for _, side in ipairs({ "none", "Left", "Right" }) do
				local model = dress(env, slot.itemKind, slot.itemId, if side == "none" then nil else side)
				local names = {}
				for _, child in ipairs(model:GetChildren()) do
					names[child.Name] = (names[child.Name] or 0) + 1
				end
				local label = slot.itemId .. " " .. side
				for _, need in ipairs({ "Base", "Back", "Window", "WindowTop", "Strip", "PriceTag", "Contents" }) do
					t.ok(names[need] == 1, label .. " has " .. need)
				end
				local walls = (names.Left or 0) + (names.Right or 0) + (names.SideWindow or 0)
				t.eq(walls, 2, label .. ": a wall or a pane on each side")
				t.ok(names.Left == 1 or names.Right == 1, label .. ": at least the far wall")
				t.eq(model:GetAttribute("Open"), nil, label .. " is unopened")
				n += 1
			end
		end
		t.ok(n >= 60, "every item was checked, " .. n)
	end)

	t.test(
		"the shell: a 0.1 charcoal rim, the glass as before, a cream price tag, no shadows from glass or decor",
		function()
			local Layout = env.BoxArt.Layout
			t.eq(Layout.glassColor, Color3.fromRGB(150, 192, 212))
			t.eq(Layout.glassTransparency, 0.5)
			for _, side in ipairs({ "none", "Right" }) do
				local model, body = dress(env, "Axe", "SteelAxe", if side == "none" then nil else side)
				local W, H, D = body.Size.X, body.Size.Y, body.Size.Z
				for _, name in ipairs({ "RimFront", "RimBack", "RimLeft", "RimRight" }) do
					local bar = model:FindFirstChild(name)
					t.ok(bar ~= nil, name)
					t.eq(bar.Color, env.BoxArt.Charcoal, name .. " is charcoal")
					local thin = math.min(bar.Size.X, bar.Size.Y, bar.Size.Z)
					t.ok(math.abs(thin - 0.1) < 1e-4 and math.abs(bar.Size.Y - 0.1) < 1e-4, name .. " is 0.1 thick")
					t.ok(math.abs(bar.CFrame.Position.Y - (H + 0.05)) < 1e-3, name .. " rides the top edge")
					t.ok(
						bar.CFrame.Position.X >= -W / 2 - 1e-3 and bar.CFrame.Position.X <= W / 2 + 1e-3,
						name .. " inside the width"
					)
					t.ok(math.abs(bar.CFrame.Position.Z) <= D / 2 + 0.06, name .. " inside the depth")
				end
				t.eq(
					model:FindFirstChild("SideEdge") ~= nil,
					side ~= "none",
					"the aisle pane's edge bar only with a pane"
				)
				local tag = model:FindFirstChild("PriceTag")
				t.ok(
					math.abs(tag.Size.X - 1.2) < 1e-4
						and math.abs(tag.Size.Y - 0.6) < 1e-4
						and math.abs(tag.Size.Z - 0.05) < 1e-4,
					"the tag is 1.2 x 0.6 x 0.05"
				)
				t.eq(tag.Material, Enum.Material.SmoothPlastic)
				t.eq(tag.Color, Color3.fromHex("#F3E7C9"), "SignCream")
				t.ok(tag.CFrame.Position.Z < -D / 2, "on the front")
				for _, p in ipairs(model:GetChildren()) do
					if p:IsA("BasePart") and p ~= body then
						t.eq(p.CastShadow, false, p.Name .. " casts no shadow")
					end
				end
				for _, name in ipairs({ "Window", "WindowTop" }) do
					local glass = model:FindFirstChild(name)
					t.eq(glass.Color, Layout.glassColor)
					t.eq(glass.Transparency, 0.5)
				end
			end
		end
	)

	t.test("a box adds at most 6 parts to the plain shell, and the whole shell stays under its cap", function()
		for _, slot in ipairs(allSlots()) do
			for _, side in ipairs({ "none", "Right" }) do
				local model = dress(env, slot.itemKind, slot.itemId, if side == "none" then nil else side)
				local added, shell = 0, 0
				for _, child in ipairs(model:GetChildren()) do
					if child:IsA("BasePart") then
						shell += 1
						if not BASIC[child.Name] then
							added += 1
						end
					end
				end
				t.ok(added <= 6, slot.itemId .. " adds " .. added)
				t.ok(shell <= env.BoxLogic.ShellPartCap, slot.itemId .. " shell " .. shell)
				t.ok(shell + #contentsParts(model) <= env.BoxLogic.BoxPartCap, slot.itemId .. " whole box")
			end
		end
	end)

	t.test(
		"at least 3 display parts, none outside the inner volume, and the display shows 70 percent of the item",
		function()
			local Floor, Margin = env.BoxSize.Floor, env.BoxSize.Margin
			for _, slot in ipairs(allSlots()) do
				local display = env.ItemModel.Get(slot.itemKind, slot.itemId)
				local label = slot.itemId
				-- (An item built from two parts has no third to show: the Spark Lamp.)
				t.ok(#display.parts >= math.min(3, display.total), label .. " keeps " .. #display.parts .. " parts")
				t.ok(#display.parts >= 1, label .. " is not empty")
				local model, body = dress(env, slot.itemKind, slot.itemId, "Right")
				local list = contentsParts(model)
				t.ok(#list >= math.min(3, display.total), label .. " contents " .. #list)
				local size = body.Size
				local lo, hi = bounds(list)
				local tol = 0.02
				t.ok(lo.X >= -size.X / 2 - tol and hi.X <= size.X / 2 + tol, label .. " inside the width")
				t.ok(lo.Z >= -size.Z / 2 - tol and hi.Z <= size.Z / 2 + tol, label .. " inside the depth")
				t.ok(lo.Y >= -tol and hi.Y <= size.Y + tol, label .. " inside the height")
				-- 70 percent of the item as the box shows it, across and deep (the part copy while
				-- no mesh is there). A slot's own model sizes the box from the model.
				local scale = env.ItemBox.For(slot.itemKind, slot.itemId).scale
				local ext = env.ItemModel.Extent(slot.itemKind, slot.itemId) * scale
				local shown = hi - lo
				local meshed = display.slot ~= nil and env.StoreModelSlots.HasMesh(display.slot)
				if not meshed then
					t.ok(shown.X >= 0.7 * ext.X - tol, label .. " fills the width: " .. shown.X .. " of " .. ext.X)
					t.ok(shown.Z >= 0.7 * ext.Z - tol, label .. " fills the depth: " .. shown.Z .. " of " .. ext.Z)
				end
				-- (And the inner width is 70 to 85 percent of the box's, down to the minimum box.)
				local inner = ext
				t.ok(inner.X <= size.X - 2 * Margin + tol, label .. " fits inside the margin")
				t.ok(size.Y >= inner.Y + Margin + Floor - tol)
			end
		end
	)

	t.test(
		"with the meshes loaded the contents are the item's mesh, and the part build stands in until then",
		function()
			local cases = { { "Machine", "SwitchBelt" }, { "Machine", "WoodDetector" }, { "Machine", "TiltedBelt" } }
			for _, case in ipairs(cases) do
				local kind, id = case[1], case[2]
				-- Still loading: the part copy, valid, and the display knows its slot.
				local unloaded = fresh()
				withMeshes(unloaded, false, function()
					local display = unloaded.ItemModel.Get(kind, id)
					t.ok(display.slot ~= nil, id .. " has a model slot")
					t.eq(display.slot.source, "machines")
					t.ok(unloaded.StoreModelSlots.HasMesh(display.slot), id .. " has mesh ids")
					t.ok(#display.parts >= 3, id .. " part copy has " .. #display.parts)
					for _, p in ipairs(display.parts) do
						t.ok(not p:IsA("MeshPart"), id .. " part copy has no mesh " .. p.Name)
					end
					t.ok(unloaded.ItemModel.Sound(display), id .. " is a sound display")
					local model = dress(unloaded, kind, id, "Right")
					local list = contentsParts(model)
					t.ok(#list >= 3, id .. " shows " .. #list .. " parts while loading")
					for _, p in ipairs(list) do
						t.eq(p:GetAttribute("StoreModel"), nil, id .. " no mesh yet")
					end
				end)
				-- Loaded: the MachineMeshes pieces, nothing of the part copy.
				local loaded = fresh()
				withMeshes(loaded, true, function()
					local display = loaded.ItemModel.Get(kind, id)
					local model, body = dress(loaded, kind, id, "Right")
					local list = contentsParts(model)
					local asset = loaded.MachineMeshes.Get(id)
					local expected = 0
					for _, piece in ipairs(asset.pieces) do
						if piece.name ~= "Gate" then
							expected += 1
						end
					end
					t.eq(#list, expected, id .. " shows every static piece and nothing else")
					for _, p in ipairs(list) do
						t.eq(p:GetAttribute("StoreModel"), id, id .. " " .. p.Name .. " is the slot's mesh")
						t.ok(p:IsA("MeshPart"))
						t.eq(p.CanCollide, false)
						t.eq(p.CanQuery, false)
						t.eq(p.Massless, true)
					end
					local lo, hi = bounds(list)
					local size = body.Size
					t.ok(lo.X >= -size.X / 2 - 0.02 and hi.X <= size.X / 2 + 0.02, id .. " inside the width")
					t.ok(lo.Z >= -size.Z / 2 - 0.02 and hi.Z <= size.Z / 2 + 0.02, id .. " inside the depth")
					t.ok(lo.Y >= -0.02 and hi.Y <= size.Y + 0.02, id .. " inside the height")
					local scale = loaded.ItemBox.For(kind, id).scale
					local ext = display.extent * scale
					t.ok(hi.X - lo.X >= 0.7 * ext.X, id .. " mesh fills the width")
					t.ok(hi.Z - lo.Z >= 0.7 * ext.Z, id .. " mesh fills the depth")
				end)
			end
		end
	)

	t.test("the display never depends on whether a mesh has loaded", function()
		for _, case in ipairs({ { "Machine", "SwitchBelt" }, { "Machine", "WoodDetector" } }) do
			local a, b = fresh(), fresh()
			local before, after
			withMeshes(a, false, function()
				before = a.ItemModel.Get(case[1], case[2])
			end)
			withMeshes(b, true, function()
				after = b.ItemModel.Get(case[1], case[2])
			end)
			t.eq(#before.parts, #after.parts)
			t.eq(before.extent, after.extent)
			t.eq(before.total, after.total)
			t.ok(#after.parts >= 3, case[2] .. " is more than loose bars")
			t.ok(after.shown.X >= 0.7 * after.extent.X, case[2] .. " the copy spans the width")
		end
	end)

	t.test(
		"a display with under 3 parts or under half the footprint is not sound, so it is not cached for good",
		function()
			local ItemModel = env.ItemModel
			local function display(parts, total, shown, built)
				local list = {}
				for i = 1, parts do
					list[i] = Instance.new("Part")
				end
				return { parts = list, total = total, shown = shown, built = built }
			end
			local V = Vector3.new
			t.eq(ItemModel.Sound(display(8, 30, V(6, 2, 6), V(6, 2, 6))), true)
			t.eq(ItemModel.Sound(display(2, 30, V(6, 2, 6), V(6, 2, 6))), false, "two loose bars")
			t.eq(ItemModel.Sound(display(3, 30, V(2.9, 2, 6), V(6, 2, 6))), false, "under half across")
			t.eq(ItemModel.Sound(display(3, 30, V(6, 2, 2.9), V(6, 2, 6))), false, "under half deep")
			t.eq(ItemModel.Sound(display(3, 30, V(6, 0.9, 6), V(6, 2, 6))), false, "under half tall")
			t.eq(ItemModel.Sound(display(2, 2, V(1, 3, 1), V(1, 3, 1))), true, "a model that really is two parts")
			-- Every store item is sound as built, so the real cache never holds a bad copy.
			for _, slot in ipairs(allSlots()) do
				t.ok(ItemModel.Sound(ItemModel.Get(slot.itemKind, slot.itemId)), slot.itemId .. " is a sound display")
			end
		end
	)

	t.test(
		"StoreModelSlots.ForMachine: the line and belt meshes without the gate, nothing for planers or the chop saw",
		function()
			local Slots, MM = env.StoreModelSlots, env.MachineMeshes
			local belt = Slots.ForMachine("SwitchBelt")
			t.ok(belt ~= nil)
			local names = {}
			for _, piece in ipairs(belt.pieces) do
				table.insert(names, piece.name)
				t.eq(piece.meshId, MM.MeshId("SwitchBelt", piece.name), "the id is MachineMeshes'")
			end
			t.eq(names, { "Body", "Belt", "ArrowDecal", "Rollers" })
			t.eq(belt.source, "machines")
			t.ok(Slots.HasMesh(belt))
			t.eq(
				Slots.ForItem("SwitchBelt", "Machine"),
				nil,
				"not a placed-item slot: the placed belt is MachineSkin's"
			)
			t.eq(Slots.ForMachine("ChopSaw"), nil)
			t.eq(Slots.ForMachine("PlanerHand"), nil)
			t.eq(Slots.ForMachine("SkyBin"), nil)
			MM.ForcedZero["SwitchBelt.Body"] = true
			local blank = Slots.ForMachine("SwitchBelt")
			MM.ForcedZero["SwitchBelt.Body"] = nil
			t.eq(Slots.HasMesh(blank), false, "a missing id keeps the part build")
			local layout = Slots.Layout(belt)
			t.ok(math.abs(layout.size.X - 12) < 0.01 and math.abs(layout.size.Z - 8) < 0.05, "the belt is 12 x 8")
		end
	)
end
