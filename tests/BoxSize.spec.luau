--!nocheck
-- BoxSize: a box is the item's real bounding box plus a fixed margin (0.6 stud
-- each side and over the top, a 0.3 floor), never below a minimum that keeps
-- the name strip readable, never above the shelf's (or the showroom's)
-- maximum. The size comes from the model in the window (Art/ItemModel), so
-- these specs build every item a shop sells and measure what is in its box.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
	local BoxSize = t.shared("BoxSize")
	local BoxLogic = t.shared("BoxLogic")
	local ItemBox = t.shared("ItemBox")
	local StoreStock = t.shared("StoreStock")
	local ItemModel = t.shared("Art/ItemModel")
	local BoxArt = t.shared("Art/BoxArt")

	local EPS = 1e-4

	-- Every item a box can hold: the shop slots, the showroom's vehicles, a Robux box.
	local function everyItem()
		local out = {}
		for _, slot in ipairs(StoreStock.All()) do
			table.insert(out, { kind = slot.itemKind, id = slot.itemId, name = slot.slotId })
		end
		for _, v in ipairs(ItemBox.Showroom) do
			table.insert(out, { kind = v.kind, id = v.id, name = "dealership-" .. v.id })
		end
		table.insert(out, { kind = "Robux", id = "", name = "robux" })
		return out
	end

	-- A built box, and the bounds of what is in its window in the box's own space.
	local function built(kind, id, size)
		local model = Instance.new("Model")
		local body = Instance.new("Part")
		body.Name = "Box"
		body.Size = size
		body.CFrame = CFrame.new(0, size.Y / 2, 0)
		body.Parent = model
		BoxArt.Dress(model, body, { name = "Item", kind = kind, itemId = id, color = roblox.Color3.new(1, 0, 0) })
		local lo, hi
		local contents = model:FindFirstChild("Contents")
		for _, p in ipairs(contents:GetChildren()) do
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local c = body.CFrame:PointToObjectSpace(p.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
						lo = if lo then lo:Min(c) else c
						hi = if hi then hi:Max(c) else c
					end
				end
			end
		end
		return model, body, lo, hi
	end

	t.test("the rule: the item's bounds plus 0.6 each side and over the top and a 0.3 floor", function()
		t.eq(BoxSize.Margin, 0.6)
		t.eq(BoxSize.Floor, 0.3)
		-- A hatchet-sized axe lying down: 3.3 long, 1.8 high, 0.4 thin.
		local fit = BoxSize.Fit(Vector3.new(3.3, 1.8, 0.4), "Axe")
		t.eq(fit.scale, 1, "it fits, so it is shown at real size")
		t.ok(math.abs(fit.size.X - (3.3 + 1.2)) < EPS, "long: the length plus the margin each side")
		t.ok(math.abs(fit.size.Y - (1.8 + 0.6 + 0.3)) < EPS, "high: the margin over it and the floor under it")
		t.eq(fit.size.Z, BoxSize.Min.Z, "thin: the minimum depth that keeps the strip readable")
		-- The margin is exact whenever the minimum is not what sets the size.
		local plain = BoxSize.Fit(Vector3.new(1.8, 2, 1.8), "Blueprint")
		t.ok(
			math.abs(plain.size.X - 3) < EPS and math.abs(plain.size.Y - 2.9) < EPS and math.abs(plain.size.Z - 3) < EPS
		)
		-- A speck still gets a readable box.
		local speck = BoxSize.Fit(Vector3.new(0.2, 0.2, 0.2), "Gear")
		t.eq(speck.size, BoxSize.Min)
		-- The offset puts the item on the floor, centred across and deep.
		local at = BoxSize.ItemOffset(plain.size, plain.inner)
		t.eq(at.X, 0)
		t.eq(at.Z, 0)
		t.ok(math.abs((at.Y - plain.inner.Y / 2) - (-plain.size.Y / 2 + BoxSize.Floor)) < EPS, "its feet on the floor")
	end)

	t.test("too big for the box: shown smaller, the same shape, and the box stops at the maximum", function()
		local mill = Vector3.new(26, 11, 9.8) -- a sawmill's real size
		local fit = BoxSize.Fit(mill, "Sawmill")
		t.ok(fit.scale < 1)
		local max = BoxSize.MaxFor("Sawmill")
		t.ok(
			fit.size.X <= max.X + EPS and fit.size.Y <= max.Y + EPS and fit.size.Z <= max.Z + EPS,
			"never over the maximum"
		)
		t.ok(
			math.abs(fit.size.X - max.X) < EPS
				or math.abs(fit.size.Y - max.Y) < EPS
				or math.abs(fit.size.Z - max.Z) < EPS,
			"and not smaller than it has to be"
		)
		t.ok(math.abs(fit.inner.X / fit.inner.Y - mill.X / mill.Y) < 1e-6, "squashed? no: the same shape")
		t.ok(math.abs(fit.inner.Z / fit.inner.X - mill.Z / mill.X) < 1e-6)
		-- A family shown at one scale: a smaller group scale shrinks a smaller member too.
		local small = BoxSize.Fit(Vector3.new(12, 6.6, 7.8), "Sawmill")
		local shared = BoxSize.Fit(Vector3.new(12, 6.6, 7.8), "Sawmill", fit.scale)
		t.ok(shared.scale < small.scale and shared.size.X < small.size.X, "the small mill is smaller next to a big one")
		t.ok(math.abs(shared.scale - fit.scale) < EPS)
		-- A vehicle may have the bigger box.
		t.ok(BoxSize.MaxFor("Truck").X > BoxSize.MaxFor("Axe").X and BoxSize.MaxFor("Trailer").X > BoxSize.Max.X)
		t.eq(BoxSize.MaxFor("Gear"), BoxSize.Max)
	end)

	t.test("every shop item's box encloses what is in its window, with the margin, on the floor", function()
		local m, f = BoxSize.Margin, BoxSize.Floor
		for _, it in ipairs(everyItem()) do
			local r = ItemBox.For(it.kind, it.id)
			local size = r.size
			t.eq(
				ItemModel.Get(it.kind, it.id).generic,
				false,
				it.name .. " has a model of its own, not the generic parcel"
			)
			local model, _, lo, hi = built(it.kind, it.id, size)
			t.ok(lo ~= nil, it.name .. " shows something")
			t.ok(lo.X >= -size.X / 2 + m - EPS and hi.X <= size.X / 2 - m + EPS, it.name .. " margin across")
			t.ok(lo.Z >= -size.Z / 2 + m - EPS and hi.Z <= size.Z / 2 - m + EPS, it.name .. " margin deep")
			t.ok(lo.Y >= -size.Y / 2 + f - EPS, it.name .. " stands on the floor, not through it")
			t.ok(hi.Y <= size.Y / 2 - m + EPS, it.name .. " margin over the top")
			-- The box is the item's bounds (scaled) plus the margin, or the minimum.
			local min = BoxSize.Min
			t.ok(
				math.abs(size.X - math.max(min.X, r.extent.X * r.scale + 2 * m)) < EPS,
				it.name .. " width from the item"
			)
			t.ok(
				math.abs(size.Y - math.max(min.Y, r.extent.Y * r.scale + m + f)) < EPS,
				it.name .. " height from the item"
			)
			t.ok(
				math.abs(size.Z - math.max(min.Z, r.extent.Z * r.scale + 2 * m)) < EPS,
				it.name .. " depth from the item"
			)
			-- What the window shows is not bigger than the item, and is its shape.
			local shown = hi - lo
			t.ok(
				shown.X <= r.extent.X * r.scale + EPS
					and shown.Y <= r.extent.Y * r.scale + EPS
					and shown.Z <= r.extent.Z * r.scale + EPS,
				it.name .. " the window shows no more than the item"
			)
			model:Destroy()
		end
	end)

	t.test(
		"the box follows the item, not a size class: long and thin, long and wide, small, and bigger for bigger",
		function()
			local function size(kind, id)
				return ItemBox.Size(kind, id)
			end
			local axe = size("Axe", "SteelAxe")
			t.ok(axe.X > 2 * axe.Z, "an axe box is long and thin")
			t.ok(axe.X >= 4.4 and axe.X <= BoxSize.MaxFor("Axe").X, "and as long as the axe")
			local rig, scout = size("Truck", "LoggingRig"), size("Truck", "ScoutATV")
			t.ok(rig.X > rig.Z and rig.X > rig.Y, "a truck box is long")
			t.ok(rig.Z > axe.Z * 2, "and wide")
			t.ok(
				rig.X > scout.X and rig.X * rig.Y * rig.Z > scout.X * scout.Y * scout.Z,
				"the Rig's is bigger than the Scout's"
			)
			local last = 0
			for _, id in ipairs({
				"SawmillRickety",
				"SawmillSturdy",
				"Millmaster100",
				"Millmaster200",
				"Millmaster200L",
			}) do
				local s = size("Sawmill", id)
				t.ok(s.X > last, id .. " is a bigger box than the mill below it")
				last = s.X
			end
			last = 0
			for _, id in ipairs({ "PlanerHand", "PlanerBench", "PlanerSteam", "PlanerIndustrial" }) do
				local s = size("Machine", id)
				t.ok(s.X >= last, id .. " is not a smaller box than the planer below it")
				last = s.X
			end
			local bin = size("Machine", "SkyBin")
			t.ok(bin.Y > bin.X and bin.X < 4, "the Sky Bin is small and tall")
			t.ok(size("Gear", "Lantern").X <= 3.1 and size("Gear", "Lantern").Y >= 2, "a lantern is a small box")
			for _, id in ipairs({ "PonyTrailer", "RanchTrailer", "HeavyHauler" }) do
				t.ok(size("Trailer", id).X > size("Axe", "SteelAxe").X, id .. " is bigger than an axe's box")
			end
		end
	)

	t.test(
		"every box is within the maximum for its kind and over the minimum, and the carry rules still hold",
		function()
			for _, it in ipairs(everyItem()) do
				local size = ItemBox.Size(it.kind, it.id)
				local max, min = BoxSize.MaxFor(it.kind), BoxSize.Min
				t.ok(
					size.X <= max.X + EPS and size.Y <= max.Y + EPS and size.Z <= max.Z + EPS,
					it.name .. " within the maximum"
				)
				t.ok(size.X >= min.X - EPS and size.Y >= min.Y - EPS and size.Z >= min.Z - EPS, it.name .. " readable")
				if not BoxSize.IsVehicleKind(it.kind) then
					-- The aisle is at least 7.6 studs: a box held out across the walk (a stud
					-- of room either side) still goes down it.
					t.ok(size.X + 2 <= StoreStock.AisleGap("ToolShed"), it.name .. " carried down the aisle")
				end
			end
			t.ok(
				BoxSize.VehicleMax.X <= 15.5 and BoxSize.VehicleMax.Z <= 8.4,
				"a vehicle box is no bigger than the old biggest"
			)
		end
	)

	t.test("every box stays within its part budget: dark shell plus a low-detail copy of the item", function()
		for _, it in ipairs(everyItem()) do
			local r = ItemBox.For(it.kind, it.id)
			local budget = ItemModel.ModelBudget[it.kind] or ItemModel.ModelBudget.Generic
			t.ok(r.parts >= 1 and r.parts <= budget, it.name .. " window parts " .. r.parts .. " of " .. budget)
			t.ok(BoxLogic.ShellPartCap + r.parts <= BoxLogic.BoxPartCap, it.name .. " whole box under the cap")
			local model = built(it.kind, it.id, r.size)
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			t.ok(n <= BoxLogic.BoxPartCap, it.name .. " built box " .. n .. " parts")
			t.ok(n - r.parts <= BoxLogic.ShellPartCap, it.name .. " shell " .. (n - r.parts) .. " parts")
			model:Destroy()
		end
		t.ok(BoxLogic.BoxPartCap <= 42, "light enough to carry on a phone")
	end)

	t.test("fixed classes remain for a box with no model, and an unknown id falls back", function()
		t.eq(BoxSize.Class("S").size, Vector3.new(2.8, 2.2, 2.2))
		t.eq(BoxSize.Class("not-a-class").id, BoxSize.DefaultClass)
		t.eq(BoxSize.Pitch(3), 3 + BoxSize.RowGap, "boxes stacked along z are rows")
		t.ok(#BoxSize.All() >= 1)
	end)
end
