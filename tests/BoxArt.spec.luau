--!nocheck
-- BoxArt: the dark window box (after Lumber Tycoon 2): a near-black body, an
-- accent band and edge per kind of goods, big glass windows on the front and
-- top (and the aisle side) showing the REAL item, a name strip with no price,
-- everything welded to the body, and the item inside is weightless decor.
return function(t)
	local BoxArt = t.load("ReplicatedStorage/Shared/Art/BoxArt")
	local BoxLook = t.shared("BoxLook")
	local BoxLogic = t.shared("BoxLogic")
	local BoxSize = t.shared("BoxSize")
	local ItemBox = t.shared("ItemBox")
	local StoreStock = t.shared("StoreStock")
	local roblox = t.roblox
	local Instance, Vector3, CFrame, Color3, Enum =
		roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

	local function dressed(kind, id, spec)
		local size = ItemBox.Size(kind, id or "")
		local model = Instance.new("Model")
		local body = Instance.new("Part")
		body.Name = "Box"
		body.Size = size
		body.CFrame = CFrame.new(0, size.Y / 2, 0)
		body.Parent = model
		local full = { name = "Item", kind = kind, itemId = id, color = Color3.fromRGB(60, 90, 160) }
		for k, v in pairs(spec or {}) do
			full[k] = v
		end
		BoxArt.Dress(model, body, full)
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

	local SHELL = {
		Box = true,
		Base = true,
		Left = true,
		Right = true,
		Back = true,
		Window = true,
		WindowTop = true,
		SideWindow = true,
		Strip = true,
	}

	local function luma(c)
		return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	end

	t.test(
		"a box is a dark body, a floor, walls, front and top windows and a name strip, with the item inside",
		function()
			local model = dressed("Axe", "CobaltAxe", { name = "Cobalt Axe" })
			local names = {}
			for _, p in ipairs(parts(model)) do
				names[p.Name] = (names[p.Name] or 0) + 1
			end
			for _, n in ipairs({ "Box", "Base", "Left", "Right", "Back", "Window", "WindowTop", "Strip" }) do
				t.ok(names[n] == 1, n)
			end
			t.eq(names.SideWindow, nil, "no side window unless a side faces an aisle")
			local contents = model:FindFirstChild("Contents")
			t.ok(contents ~= nil and #contents:GetChildren() >= 5, "the axe is in the window")
			t.ok(contents.Parent == model, "the item is part of the box model, so it goes when the box does")
			local shell = 0
			for _, p in ipairs(parts(model)) do
				if SHELL[p.Name] then
					shell += 1
				end
			end
			t.ok(shell <= BoxLogic.ShellPartCap, "the shell is " .. shell .. " parts")
			t.ok(#parts(model) <= BoxLogic.BoxPartCap, "the whole box is under the cap")
			local text =
				model:FindFirstChild("Strip"):FindFirstChildWhichIsA("SurfaceGui"):FindFirstChildWhichIsA("TextLabel")
			t.eq(text.Text, "Cobalt Axe", "the strip shows the item's name")
		end
	)

	t.test(
		"the body is near-black, the edge and the name strip are the accent, the box itself is see-through",
		function()
			local model, body = dressed("Sawmill", "Millmaster100", { name = "Millmaster 100" })
			t.eq(body.Transparency, 1, "the collider is invisible: the walls and windows are what you see")
			for _, n in ipairs({ "Left", "Right", "Back" }) do
				local wall = model:FindFirstChild(n)
				t.ok(luma(wall.Color) < 0.2, n .. " is near-black")
				t.eq(wall.Transparency, 0, n .. " is solid")
			end
			local accent = BoxLook.Accent("Sawmill", "Millmaster100")
			t.eq(model:FindFirstChild("Strip").Color, accent, "the name strip is the sawmill accent")
			t.eq(model:FindFirstChild("Base").Color, accent, "and so is the edge round the foot")
			t.ok(model:FindFirstChild("Base").Size.X > body.Size.X, "a hair wider than the box: a coloured edge")
			-- Text is readable on the band.
			local gui = model:FindFirstChild("Strip"):FindFirstChildWhichIsA("SurfaceGui")
			local ink = gui:FindFirstChildWhichIsA("TextLabel").TextColor3
			t.ok(math.abs(luma(ink) - luma(accent)) > 0.35, "the name reads on the band")
		end
	)

	t.test(
		"the windows are glass that collides like the box, stand off the walls, and sit on the front and the top",
		function()
			local model, body = dressed("Truck", "Pickup", { name = "Pickup" })
			local size = body.Size
			for _, n in ipairs({ "Window", "WindowTop" }) do
				local w = model:FindFirstChild(n)
				t.eq(w.Material, Enum.Material.Glass, n .. " is Glass")
				t.ok(w.Transparency >= 0.4 and w.Transparency <= 0.5, n .. " is see-through, " .. w.Transparency)
				t.eq(w.CanCollide, body.CanCollide, n .. " collides as the box does")
				t.eq(w.CanQuery, true, n .. " can be aimed at and grabbed through")
				t.eq(w.CanTouch, false)
				t.eq(w.Massless, true)
				local weld = w:FindFirstChildWhichIsA("WeldConstraint")
				t.ok(weld and weld.Part0 == body and weld.Part1 == w, n .. " welded to the body")
			end
			local front = model:FindFirstChild("Window")
			local rel = body.CFrame:PointToObjectSpace(front.CFrame.Position)
			t.ok(
				-rel.Z - front.Size.Z / 2 - size.Z / 2 >= 0.03 - 1e-4,
				"the front window stands 0.03 stud or more off the box"
			)
			t.ok(front.Size.X > size.X * 0.8 and front.Size.Y > size.Y * 0.6, "and is a large window")
			local top = model:FindFirstChild("WindowTop")
			local up = body.CFrame:PointToObjectSpace(top.CFrame.Position)
			t.ok(
				up.Y - top.Size.Y / 2 - size.Y / 2 >= 0.03 - 1e-4,
				"the top window stands 0.03 stud or more off the box"
			)
			t.ok(top.Size.X > size.X * 0.8 and top.Size.Z > size.Z * 0.8, "and is a large window")
		end
	)

	t.test("no two visible faces of the shell share a plane over the same patch (no z-fighting)", function()
		local function faces(p)
			local out = {}
			local axes = { p.CFrame.XVector, p.CFrame.YVector, p.CFrame.ZVector }
			local half = { p.Size.X / 2, p.Size.Y / 2, p.Size.Z / 2 }
			for i = 1, 3 do
				local j, k = i % 3 + 1, (i + 1) % 3 + 1
				for _, sign in ipairs({ -1, 1 }) do
					local n = axes[i] * sign
					local c = p.CFrame.Position + n * half[i]
					table.insert(
						out,
						{ part = p, n = n, s = n:Dot(c), c = c, u = axes[j], v = axes[k], hu = half[j], hv = half[k] }
					)
				end
			end
			return out
		end
		local function patch(a, b)
			local d = b.c - a.c
			for _, axis in ipairs({ a.u, a.v, b.u, b.v }) do
				local ra = math.abs(a.u:Dot(axis)) * a.hu + math.abs(a.v:Dot(axis)) * a.hv
				local rb = math.abs(b.u:Dot(axis)) * b.hu + math.abs(b.v:Dot(axis)) * b.hv
				if ra + rb - math.abs(d:Dot(axis)) < 0.02 then
					return false
				end
			end
			return true
		end
		for _, case in ipairs({
			{ "Axe", "SteelAxe", nil },
			{ "Sawmill", "Millmaster200L", "Right" },
			{ "Truck", "Rustbucket", "Left" },
			{ "Gear", "Lantern", nil },
		}) do
			local model = dressed(case[1], case[2], { side = case[3] })
			local all = {}
			for _, p in ipairs(parts(model)) do
				if SHELL[p.Name] and p.Transparency < 1 then
					for _, f in ipairs(faces(p)) do
						table.insert(all, f)
					end
				end
			end
			for i = 1, #all do
				for j = i + 1, #all do
					local a, b = all[i], all[j]
					if a.part ~= b.part and a.n:Dot(b.n) > 0.999 and math.abs(a.s - b.s) < 0.02 and patch(a, b) then
						t.ok(false, case[2] .. ": " .. a.part.Name .. " and " .. b.part.Name .. " share a plane")
					end
				end
			end
		end
		t.ok(true)
	end)

	t.test(
		"the item in the window is weightless decor: welded, no collision, no raycasts, no lights, no scripts",
		function()
			for _, case in ipairs({
				{ "Axe", "GoldAxe" },
				{ "Sawmill", "Millmaster200L" },
				{ "Truck", "LoggingRig" },
				{ "Machine", "ChopSaw" },
			}) do
				local model, body = dressed(case[1], case[2])
				local contents = model:FindFirstChild("Contents")
				t.ok(#contents:GetChildren() > 0, case[2])
				for _, p in ipairs(contents:GetChildren()) do
					t.ok(p:IsA("BasePart"), p.Name .. " is a part")
					t.eq(p.CanCollide, false, case[2] .. " " .. p.Name)
					t.eq(p.CanQuery, false, case[2] .. " " .. p.Name .. " is never aimed at")
					t.eq(p.CanTouch, false)
					t.eq(p.Massless, true, "weighs nothing")
					local weld = p:FindFirstChildWhichIsA("WeldConstraint")
					t.ok(
						weld and weld.Part0 == body and weld.Part1 == p,
						case[2] .. " " .. p.Name .. " welded to the body"
					)
				end
				for _, d in ipairs(model:GetDescendants()) do
					t.ok(
						not (
								d:IsA("LuaSourceContainer")
								or d:IsA("Light")
								or d:IsA("ParticleEmitter")
								or d:IsA("Seat")
								or d:IsA("VehicleSeat")
							),
						case[2] .. " carries a " .. d.ClassName
					)
				end
			end
		end
	)

	t.test(
		"the shell: only the windows and the body collide; walls, edge and strip are looks only and welded",
		function()
			local model, body = dressed("Gear", "Lantern", { side = "Left" })
			for _, p in ipairs(parts(model)) do
				if p ~= body and SHELL[p.Name] then
					t.eq(p.Massless, true, p.Name)
					t.eq(p.CanTouch, false, p.Name)
					local weld = p:FindFirstChildWhichIsA("WeldConstraint")
					t.ok(weld and weld.Part0 == body and weld.Part1 == p, p.Name .. " welded to the body")
					if p.Name == "Window" or p.Name == "WindowTop" or p.Name == "SideWindow" then
						t.eq(p.CanCollide, true, p.Name)
					else
						t.eq(p.CanCollide, false, p.Name)
					end
				end
			end
		end
	)

	t.test("the side that faces the aisle gets a window of its own instead of a wall", function()
		local right = dressed("Axe", "SteelAxe", { side = "Right" })
		t.ok(
			right:FindFirstChild("SideWindow") ~= nil
				and right:FindFirstChild("Right") == nil
				and right:FindFirstChild("Left") ~= nil
		)
		t.ok(right:FindFirstChild("SideWindow").CFrame.Position.X > 0, "on the east face")
		local left = dressed("Axe", "SteelAxe", { side = "Left" })
		t.ok(
			left:FindFirstChild("SideWindow") ~= nil
				and left:FindFirstChild("Left") == nil
				and left:FindFirstChild("Right") ~= nil
		)
		t.ok(left:FindFirstChild("SideWindow").CFrame.Position.X < 0, "on the west face")
		t.eq(BoxArt.AisleSide(-10), "Right", "on the west side the aisle is to the east")
		t.eq(BoxArt.AisleSide(10), "Left")
		t.eq(BoxArt.AisleSide(0), nil)
	end)

	t.test("an accent colour per kind of goods, an axe by its tier, and none is lost on the dark body", function()
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
			"Planer",
			"Belt",
		}) do
			t.ok(BoxLook.Categories[kind] ~= nil, kind .. " has a colour")
		end
		local seen = {}
		for kind, color in pairs(BoxLook.Categories) do
			local key = tostring(color)
			t.ok(seen[key] == nil, kind .. " has its own colour, not " .. tostring(seen[key]))
			seen[key] = kind
			t.ok(math.abs(luma(color) - luma(BoxLook.Charcoal)) > 0.25, kind .. " shows on charcoal")
		end
		t.eq(BoxLook.CategoryOf("Machine", "PlanerBench"), "Planer")
		t.eq(BoxLook.CategoryOf("Machine", "ConveyorTurn"), "Belt")
		t.eq(BoxLook.CategoryOf("Machine", "ChopSaw"), "Machine")
		t.eq(BoxLook.CategoryOf("Machine", "SkyBin"), "Machine")
		t.eq(BoxLook.Accent("Machine", "PlanerHand"), BoxLook.Categories.Planer)
		t.eq(BoxLook.Accent("Truck", "Pickup"), BoxLook.Categories.Truck)
		t.eq(BoxLook.Accent("Axe", "???"), BoxLook.Categories.Axe, "an unknown axe keeps the axe colour")
		t.eq(BoxArt.CategoryColor("???"), BoxArt.DefaultCategory)
		-- Every axe the shop sells has its own tier colour.
		local ItemCatalog = t.shared("ItemCatalog")
		local tiers = {}
		for _, axe in ipairs(ItemCatalog.AxeLadder()) do
			local c = BoxLook.Accent("Axe", axe.id)
			t.ok(tiers[tostring(c)] == nil, axe.id .. " has its own tier colour")
			tiers[tostring(c)] = axe.id
			t.ok(math.abs(luma(c) - luma(BoxLook.Charcoal)) > 0.2, axe.id .. " shows on charcoal")
		end
	end)

	t.test("opening a box takes the item and the windows out and leaves the dark box, twice over", function()
		local model, body = dressed("Axe", "SteelAxe", { side = "Right" })
		t.ok(model:FindFirstChild("Contents") ~= nil and model:FindFirstChild("Window") ~= nil)
		BoxArt.Open(model)
		t.eq(model:FindFirstChild("Contents"), nil)
		for _, n in ipairs({ "Window", "WindowTop", "SideWindow" }) do
			t.eq(model:FindFirstChild(n), nil, n .. " is gone")
		end
		for _, n in ipairs({ "Box", "Base", "Back", "Left", "Strip" }) do
			t.ok(model:FindFirstChild(n) ~= nil, n .. " stays")
		end
		t.eq(body.CanCollide, true, "the box still collides")
		BoxArt.Open(model)
		t.eq(model:GetAttribute("Open"), true)
	end)

	t.test("a Robux box is a dark gold box with gold coins inside; the tier line is on the foot", function()
		local model = dressed("Robux", nil, { name = "2x Cash", gold = true })
		t.eq(model:FindFirstChild("Strip").Color, BoxLook.Gold)
		t.eq(model:FindFirstChild("Back").Color, BoxLook.CharcoalGold)
		t.ok(#model:FindFirstChild("Contents"):GetChildren() == 3, "three coins")
		local tiered = dressed("Sawmill", "SawmillSturdy", { tier = "STURDY, TIER 2 OF 5" })
		local gui = tiered:FindFirstChild("Base"):FindFirstChildWhichIsA("SurfaceGui")
		t.eq(gui:FindFirstChildWhichIsA("TextLabel").Text, "STURDY, TIER 2 OF 5")
		local plain = dressed("Axe", "SteelAxe")
		t.eq(plain:FindFirstChild("Base"):FindFirstChildWhichIsA("SurfaceGui"), nil, "no tier, no line")
		-- No model for an id: a generic parcel stands in.
		local unknown = dressed("Gear", "NoSuchGear")
		t.ok(#unknown:FindFirstChild("Contents"):GetChildren() >= 1, "a generic icon")
	end)

	t.test("a box carries no price text and no billboard, on the strip, the foot or anywhere", function()
		for _, slot in ipairs(StoreStock.All()) do
			local model = dressed(
				slot.itemKind,
				slot.itemId,
				{ name = slot.displayName, tier = StoreStock.TierLabel(slot.itemKind, slot.itemId) }
			)
			for _, d in ipairs(model:GetDescendants()) do
				t.ok(not d:IsA("BillboardGui"), slot.slotId .. " floats nothing")
				if d:IsA("TextLabel") then
					t.ok(not string.find(d.Text, "[$]"), slot.slotId .. " prints no dollar amount: " .. d.Text)
					t.ok(not string.find(d.Text, "R[$]", 1), slot.slotId .. " prints no R$ price")
					t.ok(d.Name ~= "Price", slot.slotId)
				end
			end
		end
	end)

	t.test(
		"BoxService boxes: size from the item, the dark box, hover marks on the model, one collision group",
		function()
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
			local Stock = loader:shared("StoreStock")
			local counter = Instance.new("Part")
			counter.Name = "Counter"
			counter.Size = Vector3.new(10, 2, 6)
			counter.CFrame = CFrame.new(0, 3, 0)
			local small = Box.Make({ slotId = "toolshed-SteelAxe", cf = CFrame.new(-8, 5, 0), counter = counter })
			local big = Box.Make({ slotId = "toolshed-Millmaster200L", cf = CFrame.new(8, 6, 0), counter = counter })
			local function near(a, b)
				return math.abs(a.X - b.X) < 0.01 and math.abs(a.Y - b.Y) < 0.01 and math.abs(a.Z - b.Z) < 0.01
			end
			t.ok(near(small.part.Size, Stock.BoxSizeOf(Stock.Get("toolshed-SteelAxe"))))
			t.ok(near(big.part.Size, Stock.BoxSizeOf(Stock.Get("toolshed-Millmaster200L"))))
			t.ok(small.part.Size.X > 2 * small.part.Size.Z, "the axe's box is long and thin")
			t.ok(big.part.Size.X > small.part.Size.Z * 2, "the mill's box is wide")
			for _, rec in ipairs({ small, big }) do
				local n = 0
				for _, d in ipairs(rec.model:GetDescendants()) do
					if d:IsA("BasePart") then
						n += 1
						t.eq(d.CollisionGroup, "Boxes", d.Name .. " is in the Boxes group")
					end
					t.ok(not d:IsA("Decal"), "no flat decals: the look is the window")
				end
				t.ok(n >= 8 and n <= BoxLogic.BoxPartCap, "box parts, " .. n)
				t.ok(rec.model:FindFirstChild("Contents") ~= nil, "the item is in the window")
				t.eq(rec.part.Transparency, 1, "the body is the invisible collider")
				t.eq(rec.part.CanCollide, true)
				-- The hover tag still finds the box (the attributes are on the model).
				t.eq(rec.model:GetAttribute("HoverKind"), rec.itemKind)
				t.eq(rec.model:GetAttribute("HoverId"), rec.itemId)
				t.ok(rec.model:GetAttribute("HoverKey") ~= nil)
				t.eq(rec.model:GetAttribute("ForSale"), true)
				t.eq(rec.model:GetAttribute("OnShelf"), true)
				t.ok(rec.model:HasTag("HoverItem"), "tagged for the hover tag")
				t.ok(rec.model:HasTag("ShopBox"))
				-- Aiming through the window: the glass answers a raycast, the item does not.
				t.eq(rec.model:FindFirstChild("Window").CanQuery, true)
				for _, p in ipairs(rec.model:FindFirstChild("Contents"):GetChildren()) do
					t.eq(p.CanQuery, false)
				end
				local prices, billboards, texts = 0, 0, 0
				for _, d in ipairs(rec.model:GetDescendants()) do
					if d.Name == "Price" and d:IsA("TextLabel") then
						prices += 1
					elseif d:IsA("BillboardGui") then
						billboards += 1
					elseif d:IsA("TextLabel") and string.find(d.Text, "$", 1, true) then
						texts += 1
					end
				end
				t.eq(prices, 0, "no price on the box")
				t.eq(texts, 0, "no dollar amount anywhere on it")
				t.eq(billboards, 0, "and nothing floating over it")
			end
			t.ok(small.model:FindFirstChild("SideWindow") ~= nil, "a west-side box shows a window to the aisle")
			t.ok(
				big.model:FindFirstChild("Base"):FindFirstChildWhichIsA("SurfaceGui") ~= nil,
				"a sawmill's tier is on the foot of its box"
			)
		end
	)

	t.test("the accent band is 0.1 deep and a brass plate sits on it, with no price", function()
		local model, body = dressed("Axe", "SteelAxe", { name = "Steel Axe" })
		local strip = model:FindFirstChild("Strip")
		t.ok(math.abs(strip.Size.Z - 0.1) < 1e-3, "the band is 0.1 deep")
		t.ok(model:FindFirstChild("Base").Size.X > body.Size.X + 0.15, "the foot flange is the accent too")
		local logo = model:FindFirstChild("Logo")
		t.ok(logo, "a logo plate")
		t.ok(math.abs(logo.Size.X - 0.6) < 1e-3 and math.abs(logo.Size.Y - 0.3) < 1e-3, "0.6 by 0.3")
		t.eq(logo:FindFirstChildWhichIsA("SurfaceGui"), nil, "the plate prints nothing")
		local shell = 0
		for _, p in ipairs(parts(model)) do
			if p.Name ~= "Contents" and (p.Parent == model) then
				shell += 1
			end
		end
		t.ok(shell <= BoxLogic.ShellPartCap, "shell " .. shell)
	end)

	t.test("the brass plate sits under the name and the two rects do not overlap", function()
		local function span(part)
			local c, s = part.CFrame.Position, part.Size
			return c.X - s.X / 2, c.X + s.X / 2, c.Y - s.Y / 2, c.Y + s.Y / 2
		end
		local cases = {
			{ "Axe", "SteelAxe", "Steel Axe" },
			{ "Sawmill", "Millmaster100", "Millmaster 100" },
			{ "Gear", "Lantern", "Lantern" },
			{ "Truck", "Rustbucket", "Rustbucket" },
		}
		for _, row in ipairs(cases) do
			local model = dressed(row[1], row[2], { name = row[3] })
			local strip = model:FindFirstChild("Strip")
			local logo = model:FindFirstChild("Logo")
			local label = strip:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChild("Name")
			local pad = label:FindFirstChildWhichIsA("UIPadding")
			local x0, x1, y0, y1 = span(strip)
			local lx0 = x0 + (x1 - x0) * pad.PaddingLeft.Scale
			local lx1 = x1 - (x1 - x0) * pad.PaddingRight.Scale
			local ly0 = y0 + (y1 - y0) * pad.PaddingBottom.Scale
			local ly1 = y1 - (y1 - y0) * pad.PaddingTop.Scale
			local px0, px1, py0, py1 = span(logo)
			local overlaps = px0 < lx1 - 1e-4 and px1 > lx0 + 1e-4 and py0 < ly1 - 1e-4 and py1 > ly0 + 1e-4
			t.ok(not overlaps, row[3] .. " plate covers the name")
			t.ok(py1 <= y0 + 1e-3, row[3] .. " plate is below the band")
		end
	end)
end
