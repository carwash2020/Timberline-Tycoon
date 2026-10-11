--!nocheck
-- ShopKit: the pieces every store interior is built from. Signs are tall
-- enough to read on a phone, stands carry the tier colour and badge from
-- StoreTier, a locked item's stand knows its lock, lights stay warm and
-- modest, and a real mesh prop falls back to parts and swaps in later.
return function(t)
	local roblox = t.roblox
	local Color3, Vector3, CFrame, Instance = roblox.Color3, roblox.Vector3, roblox.CFrame, roblox.Instance
	local ShopKit = t.load("ReplicatedStorage/Shared/Art/ShopKit")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local StoreTier = t.shared("StoreTier")
	local StoreStock = t.shared("StoreStock")
	local HoverTag = t.shared("HoverTag")
	local ShowroomLight = t.shared("ShowroomLight")

	local function parts(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function named(root, name)
		local out = {}
		for _, p in ipairs(parts(root)) do
			if p.Name == name then
				table.insert(out, p)
			end
		end
		return out
	end

	local function labels(part)
		local out = {}
		for _, d in ipairs(part:GetDescendants()) do
			if d:IsA("TextLabel") then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("a header sign and a sub-sign are tall enough to read at 667 x 375, text on both faces", function()
		local model = Instance.new("Model")
		local header = ShopKit.HeaderSign(model, {
			cx = 0,
			cy = 11,
			z = -20,
			w = 11,
			h = ShopKit.HeaderMinHeight + 0.4,
			text = "AXES",
			accent = Color3.fromRGB(200, 60, 40),
			ceilY = 13.5,
		})
		local sub = ShopKit.SubSign(model, {
			cx = 0,
			cy = 9,
			z = -20,
			w = 6,
			h = ShopKit.SubMinHeight + 0.2,
			text = "BELT KIT",
			accent = Color3.fromRGB(200, 60, 40),
			ceilY = 13.5,
		})
		t.ok(ShopKit.TextPx(header.Size.Y, ShopKit.HeaderViewDist) >= ShopKit.MinTextPx, "header text px")
		t.ok(ShopKit.TextPx(sub.Size.Y, ShopKit.SubViewDist) >= ShopKit.MinTextPx, "sub-sign text px")
		t.ok(header.Size.Y >= ShopKit.HeaderMinHeight and sub.Size.Y >= ShopKit.SubMinHeight)
		t.ok(header.Size.Y > sub.Size.Y, "the header is the bigger sign")
		for _, s in ipairs({ header, sub }) do
			local ls = labels(s)
			t.eq(#ls, 2, "text on both faces")
			t.eq(ls[1].Text, s:GetAttribute("SignText"))
			t.ok(StoreTier.Contrast(ls[1].TextColor3, s.Color) >= 4.5, s.Name .. " text reads on its board")
			t.eq(s.CanCollide, false, "signs are looks only")
		end
		-- both chains reach the ceiling line
		for _, chain in ipairs(named(model, "HeaderSignChain")) do
			t.ok(math.abs(chain.CFrame.Position.Y + chain.Size.Y / 2 - 13.5) < 1e-6, "the chain reaches the beam")
		end
		t.eq(#named(model, "HeaderSignChain"), 2)
		t.eq(#named(model, "SubSignChain"), 2)
	end)

	t.test("TextPx: larger and nearer is taller on screen", function()
		t.ok(ShopKit.TextPx(2, 10) > ShopKit.TextPx(2, 20))
		t.ok(ShopKit.TextPx(3, 20) > ShopKit.TextPx(2, 20))
	end)

	local function stand(slotId, aisle)
		local model = Instance.new("Model")
		local slot = StoreStock.Get(slotId)
		local plinth = ShopKit.TierStand(model, {
			slot = slot,
			size = Vector3.new(5, 0.3, 2.2),
			at = Vector3.new(-11, 4.05, -15),
			aisle = aisle,
			flagY = 8,
			accent = Color3.fromRGB(10, 20, 30),
		})
		return model, plinth, slot
	end

	t.test("a tiered item's stand is in its tier colour with a T-badge, hover-tagged", function()
		local model, plinth, slot = stand("toolshed-CobaltAxe", 1)
		local tier = StoreTier.Of(slot.itemKind, slot.itemId)
		t.eq(tier, 5)
		t.eq(plinth.Color, StoreTier.Color(5))
		local flag = named(model, "TierFlag")[1]
		t.ok(flag ~= nil, "a tier flag")
		t.eq(flag.Color, StoreTier.Color(5))
		local label = labels(flag)[1]
		t.eq(label.Text, "T5")
		t.eq(label.TextColor3, StoreTier.Ink(5))
		t.ok(StoreTier.Contrast(label.TextColor3, flag.Color) >= 4.5, "badge text passes AA")
		-- the post stands in the plinth's margin at the aisle-side front corner, the flag over the box
		local post = named(model, "TierPost")[1]
		local p = post.CFrame.Position
		t.ok(p.X > -11 and p.X < -11 + 2.5, "the post is at the aisle side (+X)")
		t.ok(p.Z < -15, "and at the front")
		t.ok(flag.CFrame.Position.Y > 7.4, "the flag is over the box")
		-- hover tag: the item's name, kind and id; no price stored anywhere
		for _, p2 in ipairs({ plinth, flag, post }) do
			local spec = HoverTag.SpecOf(p2)
			t.ok(spec ~= nil, p2.Name .. " carries a hover tag")
			t.eq(spec.name, slot.displayName)
			t.eq(spec.kind, "Axe")
			t.eq(spec.itemId, "CobaltAxe")
			t.eq(spec.shop, "ToolShed")
			t.eq(p2:GetAttribute("HoverPrice"), nil, "the price is never stored")
		end
		t.eq(HoverTag.SpecOf(flag).anchor, true, "the tag sits over the flag")
		-- everything is looks only
		for _, p3 in ipairs(parts(model)) do
			t.eq(p3.CanCollide, false, p3.Name .. " does not collide")
			t.eq(p3.CanQuery, false)
		end
	end)

	t.test("the flag faces the aisle: turned toward it from the door", function()
		local west = named(stand("toolshed-CobaltAxe", 1), "TierFlag")[1]
		local east = named(stand("toolshed-CobaltAxe", -1), "TierFlag")[1]
		t.ok(west.CFrame.LookVector.X > 0.3 and west.CFrame.LookVector.Z < -0.3, "west lane's flag looks +X and -Z")
		t.ok(east.CFrame.LookVector.X < -0.3 and east.CFrame.LookVector.Z < -0.3, "east lane's flag looks -X and -Z")
	end)

	t.test("a locked item gets a chip and the attributes the client greys by", function()
		local model, plinth = stand("toolshed-CobaltAxe", 1)
		local chip = named(model, "LockChip")[1]
		t.ok(chip ~= nil, "a lock chip over the flag")
		t.eq(labels(chip)[1].Text, "NEEDS SILVER")
		t.eq(plinth:GetAttribute("StandRole"), "base")
		t.eq(plinth:GetAttribute("StandKind"), "Axe")
		t.eq(plinth:GetAttribute("StandItem"), "CobaltAxe")
		t.eq(plinth:GetAttribute("StandOpen"), StoreTier.Color(5))
		t.eq(chip:GetAttribute("StandRole"), "chip")
		t.ok(plinth:HasTag("StoreStand"), "tagged for the client")
		-- gear for a later stage is locked too; a plain sawmill is not
		local gearModel = stand("hearth-HeatBoots", 1)
		t.ok(named(gearModel, "LockChip")[1] ~= nil, "boots are for stage 4")
		local millModel, millPlinth = stand("toolshed-SawmillSturdy", 1)
		t.eq(named(millModel, "LockChip")[1], nil, "a sawmill has no lock")
		t.eq(millPlinth:GetAttribute("StandRole"), nil)
	end)

	t.test("an item with no tier has no flag, and keeps its category colour", function()
		local model, plinth, slot = stand("toolshed-ChopSaw", 1)
		t.eq(StoreTier.Of(slot.itemKind, slot.itemId), nil)
		t.eq(#named(model, "TierFlag"), 0)
		t.eq(plinth.Color, Color3.fromRGB(10, 20, 30))
		t.eq(HoverTag.SpecOf(plinth).anchor, true, "the plinth carries the tag")
	end)

	t.test("a warm lamp is modest, warm and casts no shadows", function()
		local model = Instance.new("Model")
		ShopKit.WarmLamp(model, 0, 10, 0, 13)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("PointLight") then
				n += 1
				t.ok(d.Brightness <= ShowroomLight.MaxBrightness, "brightness " .. d.Brightness)
				t.ok(d.Range <= ShowroomLight.MaxRange, "range " .. d.Range)
				t.eq(d.Shadows, false)
				t.ok(d.Color.R >= d.Color.G and d.Color.G > d.Color.B, "warm: red over green over blue")
				t.ok(d.Color.B <= 0.75 * d.Color.R, "not white")
			end
		end
		t.eq(n, 1)
		t.ok(ShopKit.Light.Brightness <= 1 and ShopKit.Light.Range <= 22)
	end)

	t.test("CountParts counts every part under a root", function()
		local model = Instance.new("Model")
		ShopKit.WarmLamp(model, 0, 10, 0, 13)
		t.eq(ShopKit.CountParts(model), 4, "chain, cap, base, glow")
		t.eq(ShopKit.Budget, 400)
	end)

	t.test("a real mesh prop keeps its part-built stand-in until the mesh has loaded, then swaps", function()
		MeshKit.Reset()
		-- No engine and no override (Lune): the mesh is missing, so the parts stay.
		local model = Instance.new("Model")
		local fallback = Instance.new("Model")
		fallback.Name = "CrateFallback"
		fallback.Parent = model
		local box = Instance.new("Part")
		box.Name = "Crate"
		box.Parent = fallback
		local up = ShopKit.MeshProp(model, "Crate", CFrame.new(1, 2, 3), fallback)
		t.eq(up, false, "no mesh yet")
		t.ok(fallback.Parent == model, "the fallback stays")
		t.eq(#named(model, "Body"), 0, "no mesh part yet")
		MeshKit.Reset()
		-- With the mesh available, it is dressed in and the fallback goes.
		MeshKit.Override = function(_id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local ok, err = pcall(function()
			local model2 = Instance.new("Model")
			local fb2 = Instance.new("Model")
			fb2.Parent = model2
			local up2 = ShopKit.MeshProp(model2, "Crate", CFrame.new(1, 2, 3), fb2)
			t.eq(up2, true, "the mesh is up")
			t.ok(fb2.Parent == nil, "the fallback is dropped")
			local body = model2:FindFirstChild("Body")
			t.ok(body ~= nil and body:IsA("MeshPart"), "the real mesh part")
			t.ok(math.abs(body.CFrame.Position.Y - (2 + body.Size.Y / 2)) < 1e-6, "its base is on the pivot")
			t.eq(body.CanCollide, false, "a mesh prop is looks only")
		end)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end)
end
