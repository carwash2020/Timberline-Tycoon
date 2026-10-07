--!nocheck
-- BoxArt: the packaged-goods look, inside the part cap, welded to the body.
return function(t)
	local BoxArt = t.load("ReplicatedStorage/Shared/Art/BoxArt")
	local BoxLogic = t.shared("BoxLogic")
	local BoxSize = t.shared("BoxSize")
	local Instance, Vector3, CFrame, Color3 = t.roblox.Instance, t.roblox.Vector3, t.roblox.CFrame, t.roblox.Color3

	local function dressed(size, spec)
		local model = Instance.new("Model")
		local body = Instance.new("Part")
		body.Name = "Box"
		body.Size = size
		body.CFrame = CFrame.new(0, size.Y / 2, 0)
		body.Parent = model
		BoxArt.Dress(model, body, spec)
		return model, body
	end

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("a box is a body, tape, a name label, a category stripe and trim, within the part cap", function()
		local model = dressed(BoxSize.Class("M").size, {
			name = "Cobalt Axe",
			kind = "Axe",
			color = Color3.fromRGB(60, 90, 160),
			side = "Right",
		})
		local names = {}
		for _, p in ipairs(parts(model)) do
			names[p.Name] = true
		end
		for _, n in ipairs({ "Box", "Tape", "Label", "Stripe", "Trim", "SideLabel" }) do
			t.ok(names[n], n)
		end
		t.ok(#parts(model) <= BoxLogic.BoxPartCap, "at most six parts")
		local label = model:FindFirstChild("Label")
		local text = label:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChildWhichIsA("TextLabel")
		t.eq(text.Text, "Cobalt Axe", "the label shows the item's name")
		t.eq(model:FindFirstChild("Tape").Color, Color3.fromRGB(60, 90, 160), "the tape is the item's colour")
		t.eq(model:FindFirstChild("Stripe").Color, BoxArt.CategoryColor("Axe"))
	end)

	t.test("everything but the body is looks only and welded to it", function()
		local model, body =
			dressed(Vector3.new(4.6, 3.7, 3.7), { name = "Chop Saw", kind = "Machine", color = Color3.new(1, 1, 0) })
		for _, p in ipairs(parts(model)) do
			if p ~= body then
				t.eq(p.CanCollide, false, p.Name)
				t.eq(p.CanQuery, false, p.Name)
				t.eq(p.CanTouch, false, p.Name)
				local weld = p:FindFirstChildWhichIsA("WeldConstraint")
				t.ok(weld and weld.Part0 == body and weld.Part1 == p, p.Name .. " welded to the body")
			end
		end
		t.eq(model:FindFirstChild("SideLabel"), nil, "no side label when none is asked for")
	end)

	t.test("the parts sit on the box: tape and trim wrap it, the label stands on the front, nothing floats", function()
		local size = BoxSize.Class("XL").size
		local model, body =
			dressed(size, { name = "Millmaster 100", kind = "Sawmill", color = Color3.new(1, 0, 0), side = "Left" })
		local half = size / 2
		for _, p in ipairs(parts(model)) do
			local rel = body.CFrame:PointToObjectSpace(p.CFrame.Position)
			t.ok(
				math.abs(rel.X) <= half.X + 0.2 and math.abs(rel.Y) <= half.Y + 0.2 and math.abs(rel.Z) <= half.Z + 0.2,
				p.Name .. " is on the box"
			)
		end
		local label = model:FindFirstChild("Label")
		local rel = body.CFrame:PointToObjectSpace(label.CFrame.Position)
		t.ok(rel.Z < -half.Z, "the label is on the -Z face, toward the door")
		t.ok(label.Size.X <= size.X and label.Size.Y <= size.Y, "and fits it")
		local side = model:FindFirstChild("SideLabel")
		t.ok(body.CFrame:PointToObjectSpace(side.CFrame.Position).X < -half.X, "the Left side label is on the -X face")
	end)

	t.test("a Robux box is gold, the aisle side is the side that faces the aisle, every kind has a colour", function()
		local model, body = dressed(
			BoxSize.Class("S").size,
			{ name = "2x Cash", kind = "Robux", color = Color3.new(1, 1, 1), gold = true }
		)
		t.ok(body.Color.R > 0.8 and body.Color.G > 0.6 and body.Color.B < 0.4, "gold body")
		t.eq(body.Material, t.roblox.Enum.Material.Metal)
		t.ok(model:FindFirstChild("Tape").Color ~= Color3.new(1, 1, 1), "dark gold tape, not the item colour")
		t.eq(BoxArt.AisleSide(-10), "Right", "on the west side the aisle is to the east")
		t.eq(BoxArt.AisleSide(10), "Left")
		t.eq(BoxArt.AisleSide(0), nil)
		for _, kind in ipairs({
			"Axe",
			"Sawmill",
			"Machine",
			"Gear",
			"Blueprint",
			"Cosmetic",
			"Robux",
			"Truck",
			"Trailer",
		}) do
			t.ok(BoxArt.Categories[kind] ~= nil, kind)
		end
		t.eq(BoxArt.CategoryColor("???"), BoxArt.DefaultCategory)
	end)

	t.test("BoxService boxes carry the packaging, size by class, and ONE price on the label (no billboard)", function()
		local loader = t.loader({
			mocks = {
				ShopService = {
					Loop = function()
						return 2
					end,
					ChargeAndGrant = function()
						return true, "thanks", nil
					end,
				},
				ProfileService = {
					GetProfile = function()
						return nil
					end,
				},
			},
		})
		local Box = loader:server("BoxService")
		local StoreStock = loader:shared("StoreStock")
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(10, 2, 6)
		counter.CFrame = CFrame.new(0, 3, 0)
		local small = Box.Make({ slotId = "toolshed-SteelAxe", cf = CFrame.new(-8, 5, 0), counter = counter })
		local big = Box.Make({ slotId = "toolshed-Millmaster200L", cf = CFrame.new(8, 6, 0), counter = counter })
		local function near(a, b)
			return math.abs(a.X - b.X) < 0.01 and math.abs(a.Y - b.Y) < 0.01 and math.abs(a.Z - b.Z) < 0.01
		end
		t.ok(near(small.part.Size, StoreStock.BoxSizeOf(StoreStock.Get("toolshed-SteelAxe"))))
		t.ok(near(big.part.Size, StoreStock.BoxSizeOf(StoreStock.Get("toolshed-Millmaster200L"))))
		t.ok(
			big.part.Size.X * big.part.Size.Y * big.part.Size.Z
				> 3 * small.part.Size.X * small.part.Size.Y * small.part.Size.Z,
			"the sawmill box is much bigger than the hatchet box"
		)
		for _, rec in ipairs({ small, big }) do
			local n = 0
			for _, d in ipairs(rec.model:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
					t.eq(d.CollisionGroup, "Boxes")
				end
			end
			t.ok(n >= 5 and n <= BoxLogic.BoxPartCap, "five or six parts, " .. n)
			local prices, billboards = 0, 0
			for _, d in ipairs(rec.model:GetDescendants()) do
				if d.Name == "Price" and d:IsA("TextLabel") then
					prices += 1
				elseif d:IsA("BillboardGui") then
					billboards += 1
				end
			end
			t.eq(prices, 1, "one price on the box")
			t.eq(billboards, 0, "and nothing floating over it")
		end
		t.ok(small.model:FindFirstChild("SideLabel") ~= nil, "a west-side box shows a label to the aisle")
	end)
end
