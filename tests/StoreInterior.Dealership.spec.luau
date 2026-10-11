--!nocheck
-- The Dealership's interior in the new store look (copy of the Tool Shed template,
-- StoreInterior.ToolShed.spec). The Dealership has no shelf placements: its vehicles,
-- plinths and tier stands are DealershipLot's, so the stand tests read the lot. What it pins:
--   * the interior stays inside the part budget (ShopKit.Budget, about 400);
--   * every vehicle is under exactly one header (TRUCKS / TRAILERS) and one sub-sign, and
--     every sign is tall enough, and wide enough for its words, to read at 667 x 375;
--   * a tier stand per vehicle in the tier colour, with its T-flag and hover tag;
--   * lights are warm and modest, no big or near-white Neon (the display vehicles' too);
--   * nothing the kit adds collides, everything is inside the hall, signs do not overlap.
return function(t)
	local roblox = t.roblox
	local Color3, Vector3, Instance = roblox.Color3, roblox.Vector3, roblox.Instance
	local KIND = "Dealership"
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopInterior = t.load("ReplicatedStorage/Shared/Art/ShopInterior")
	local Builder = t.load("ReplicatedStorage/Shared/Art/ShopInteriors/Dealership")
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local ShopKit = t.load("ReplicatedStorage/Shared/Art/ShopKit")
	local ItemBox = t.shared("ItemBox")
	local ItemCatalog = t.shared("ItemCatalog")
	local StoreTier = t.shared("StoreTier")
	local HoverTag = t.shared("HoverTag")

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

	local function aabb(part)
		local cf, size = part.CFrame, part.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
		local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
		local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
		local p = cf.Position
		return p.X - hx, p.X + hx, p.Y - hy, p.Y + hy, p.Z - hz, p.Z + hz
	end

	local function textOf(part)
		for _, d in ipairs(part:GetDescendants()) do
			if d:IsA("TextLabel") then
				return d.Text
			end
		end
		return nil
	end

	local scale = BuildingArt.Scale[KIND] or 1
	local frame = BuildingArt.InteriorFrame(KIND, scale).frame

	-- The interior alone (what ShopInterior.Add builds), with a stand-in for the
	-- shell's counter (where BuildingArt puts it) so the checkout sign has something to read.
	local function interior()
		local model = Instance.new("Model")
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(10, 3.9, 2.5)
		counter.CFrame = roblox.CFrame.new(-64.17, 1.95, 25.82)
		counter.Parent = model
		local info = BuildingArt.InteriorFrame(KIND, scale)
		ShopInterior.Add(model, KIND, info.frame, info.extra, BuildingArt.DealershipBays())
		return model
	end

	t.test("the interior stays inside its part budget", function()
		local model = interior()
		local n = ShopKit.CountParts(model) - 1 -- (not the stand-in counter)
		t.ok(n <= ShopKit.Budget, string.format("%s interior is %d parts, over the %d budget", KIND, n, ShopKit.Budget))
		t.ok(n >= 60, "and it is dressed: " .. n)
	end)

	t.test("every vehicle is under one header and one sub-sign, and every sign reads on a phone", function()
		local seen = {}
		local runs = Builder.Runs()
		for _, run in ipairs(runs) do
			t.ok(#run.header <= 18, run.header .. " is short enough to stay on one line")
			t.ok(run.header == "TRUCKS" or run.header == "TRAILERS", "a real category: " .. run.header)
			for _, id in ipairs(run.ids) do
				t.eq(seen[id], nil, id .. " is under two headers")
				seen[id] = run.header
				local want = if run.kind == "Truck" then ItemCatalog.GetTruck(id) else ItemCatalog.GetTrailer(id)
				t.ok(want ~= nil, id .. " is a real vehicle of the right kind")
			end
		end
		for _, entry in ipairs(ItemBox.Showroom) do
			t.ok(seen[entry.id], entry.id .. " is under a header")
		end
		local layout = DealershipLot.Layout().bays
		for i = 1, #layout - 1 do
			t.ok(layout[i].row <= layout[i + 1].row, "the runs follow the bays' own order")
		end
		-- the signs themselves
		local model = interior()
		local headers, subs = named(model, "HeaderSign"), named(model, "SubSign")
		t.eq(#headers, #runs + 1, "a header per run, and SHOWROOM")
		t.eq(#subs, #ItemBox.Showroom, "a sub-sign per vehicle")
		local sawTrucks, sawTrailers = false, false
		for _, h in ipairs(headers) do
			local text = textOf(h)
			sawTrucks = sawTrucks or text == "TRUCKS"
			sawTrailers = sawTrailers or text == "TRAILERS"
			-- the text is the board's height, unless the words are wider than the board
			local textH = math.min(0.84 * h.Size.Y, 0.88 * h.Size.X / (#text * 0.6))
			t.ok(
				ShopKit.TextPx(textH / 0.84, ShopKit.HeaderViewDist) >= ShopKit.MinTextPx,
				text .. " header is readable on a phone"
			)
			t.ok(h.Size.Y >= ShopKit.HeaderMinHeight, text .. " header is tall enough")
		end
		t.ok(sawTrucks and sawTrailers, "TRUCKS and TRAILERS are both there")
		for _, s in ipairs(subs) do
			local text = textOf(s)
			t.ok(#text <= 16, text .. " fits one line")
			local textH = math.min(0.84 * s.Size.Y, 0.88 * s.Size.X / (#text * 0.6))
			t.ok(
				ShopKit.TextPx(textH / 0.84, ShopKit.SubViewDist) >= ShopKit.MinTextPx,
				text .. " is readable on a phone"
			)
		end
		-- the checkout sign over the counter, and the plaque on its face
		t.eq(#named(model, "CheckoutSign"), 1, "the CHECKOUT board")
		t.eq(#named(model, "CheckoutPlaque"), 1, "the CHECKOUT plaque")
		t.eq(#named(model, "KeeperMat"), 1, "the keeper's mat")
	end)

	t.test("the sub-signs say what each vehicle hauls, from the catalog", function()
		t.eq(Builder.SubText("Truck", "Rustbucket"), "BED: 6 LOGS")
		t.eq(Builder.SubText("Truck", "ScoutATV"), "NO BED")
		t.eq(Builder.SubText("Truck", "LoggingRig"), "BED: 48 LOGS")
		t.eq(Builder.SubText("Trailer", "RanchTrailer"), "+12 BED SPACE")
	end)

	t.test("signs never overlap: headers, sub-signs and the checkout board keep apart", function()
		local model = interior()
		local boards = {}
		for _, p in ipairs(parts(model)) do
			if p.Name == "HeaderSign" or p.Name == "SubSign" or p.Name == "CheckoutSign" then
				table.insert(boards, p)
			end
		end
		for i, a in ipairs(boards) do
			local ax0, ax1, ay0, ay1, az0, az1 = aabb(a)
			for j = i + 1, #boards do
				local bx0, bx1, by0, by1, bz0, bz1 = aabb(boards[j])
				local overlap = ax0 < bx1 and bx0 < ax1 and ay0 < by1 and by0 < ay1 and az0 < bz1 and bz0 < az1
				t.eq(overlap, false, "sign " .. i .. " and sign " .. j .. " overlap")
			end
		end
	end)

	t.test("one tier stand per vehicle: tier colour, T-flag, hover tag, no lock for a vehicle today", function()
		local lot = DealershipLot.Build()
		local layout = DealershipLot.Layout()
		local flags = named(lot, "TierFlag")
		t.eq(#flags, #layout.bays, "a T-flag per vehicle")
		t.eq(#named(lot, "LockChip"), 0, "no vehicle has a lock, so no lock chip")
		local plinths = {}
		for _, d in ipairs(lot:GetChildren()) do
			if d.Name == "Plinth" then
				plinths[d:GetAttribute("ItemId")] = d
			end
		end
		for _, bay in ipairs(layout.bays) do
			local tier = StoreTier.Of(bay.kind, bay.id)
			t.ok(tier ~= nil, bay.id .. " has a tier")
			local flag
			for _, f in ipairs(flags) do
				local spec = HoverTag.SpecOf(f)
				if spec and spec.itemId == bay.id then
					flag = f
				end
			end
			t.ok(flag, bay.id .. " has its flag")
			t.eq(flag.Color, StoreTier.Color(tier), bay.id .. " flag colour")
			t.eq(textOf(flag), StoreTier.Label(tier), bay.id .. " flag text")
			t.eq(HoverTag.SpecOf(flag).shop, "Dealership")
			-- inside its plinth, above its top, at the aisle edge but never past it
			local px0, px1, py0, py1, pz0, pz1 = aabb(plinths[bay.id])
			local fx0, fx1, fy0, fy1, fz0, fz1 = aabb(flag)
			t.ok(fx0 >= px0 and fx1 <= px1, bay.id .. " flag is over its plinth in x")
			t.ok(fz0 >= pz0 and fz1 <= pz1, bay.id .. " flag is over its plinth in z")
			t.ok(fy0 >= py1, bay.id .. " flag is above the plinth")
			local stripe, band
			for _, d in ipairs(lot:GetChildren()) do
				if not d:IsA("BasePart") then
					continue
				end
				local x0, x1, _, _, z0, z1 = aabb(d)
				if d.Name == "PlinthStripe" and x0 >= px0 and x1 <= px1 and z0 >= pz0 and z1 <= pz1 then
					stripe = d
				elseif d.Name == "PlinthBand" and x0 >= px0 - 0.01 and x1 <= px1 + 0.01 then
					local _, _, _, _, bz0, bz1 = aabb(d)
					if bz1 >= pz0 - 0.2 and bz0 <= pz1 + 0.2 then
						band = d
					end
				end
			end
			t.ok(stripe and band, bay.id .. " has its stripe and band")
			t.eq(stripe.Color, StoreTier.Color(tier), bay.id .. " stripe is the tier colour")
			t.eq(band.Color, StoreTier.Color(tier), bay.id .. " band is the tier colour")
		end
		-- vehicles: the tiers are the price order within each kind, and distinct within a kind
		local seen = {}
		for _, bay in ipairs(layout.bays) do
			local key = bay.kind .. StoreTier.Of(bay.kind, bay.id)
			t.eq(seen[key], nil, bay.id .. " shares a tier within its kind")
			seen[key] = true
		end
	end)

	t.test("lights are warm and modest; no big or near-white Neon; nothing the kit adds collides", function()
		local model = interior()
		local lights = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				lights += 1
				t.ok(d.Brightness <= ShopKit.MaxLightBrightness, "brightness " .. d.Brightness)
				t.ok(d.Range <= ShopKit.MaxLightRange, "range " .. d.Range)
				t.eq(d.Shadows, false)
				t.ok(d.Color.R >= d.Color.G and d.Color.G >= d.Color.B and d.Color.B < 0.8, "warm light")
			end
		end
		t.ok(lights >= 6, "lit well enough to read at night: " .. lights .. " lights")
		for _, p in ipairs(parts(model)) do
			if p.Material.Name == "Neon" then
				t.ok(math.max(p.Size.X, p.Size.Y, p.Size.Z) <= 1.5, "no big Neon plane: " .. p.Name)
				t.ok(not ShopKit.NearWhite(p.Color), "no near-white Neon: " .. p.Name)
			end
		end
		local KIT = {
			HeaderSign = true,
			HeaderSignFrame = true,
			HeaderSignAccent = true,
			HeaderSignChain = true,
			SubSign = true,
			SubSignFrame = true,
			SubSignAccent = true,
			SubSignChain = true,
			CheckoutSign = true,
			CheckoutPlaque = true,
			CheckoutPlaqueAccent = true,
			KeeperMat = true,
			KeeperMatEdge = true,
			CeilingBeam = true,
			CeilingRafter = true,
			LampChain = true,
			LanternGlow = true,
			AisleRunner = true,
			AisleRunnerEdge = true,
			AisleStripe = true,
			LobbyRunner = true,
			LobbyRunnerEdge = true,
			FloorBoards = true,
			FloorPlank = true,
			FloorBorder = true,
		}
		for _, p in ipairs(parts(model)) do
			if KIT[p.Name] then
				t.eq(p.CanCollide, false, p.Name .. " is looks only")
			end
		end
	end)

	t.test(
		"the display vehicles' lamps are not near-white either, and the lot adds no light of its own over the cap",
		function()
			local lot = DealershipLot.Build()
			for _, d in ipairs(lot:GetDescendants()) do
				if d:IsA("BasePart") and d.Material.Name == "Neon" then
					t.ok(
						not ShopKit.NearWhite(d.Color),
						"near-white Neon in the lot: " .. d.Parent.Name .. " " .. d.Name
					)
					t.ok(math.max(d.Size.X, d.Size.Y, d.Size.Z) <= 1.5, "big Neon in the lot: " .. d.Name)
				elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
					t.ok(d.Brightness <= ShopKit.MaxLightBrightness, "lot light " .. d.Brightness)
					t.ok(d.Range <= ShopKit.MaxLightRange, "lot range " .. d.Range)
				end
			end
		end
	)

	t.test("nothing in the whole shop is near-white Neon or a light over the cap", function()
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 109, 181))
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Material.Name == "Neon" then
				t.ok(not ShopKit.NearWhite(d.Color), "near-white Neon: " .. d.Name)
				t.ok(math.max(d.Size.X, d.Size.Y, d.Size.Z) <= 1.5, "big Neon: " .. d.Name)
			elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				t.ok(d.Brightness <= 1.5, d.Parent.Name .. " light " .. d.Brightness)
				t.ok(d.Range <= 25, d.Parent.Name .. " range " .. d.Range)
			end
		end
		t.eq(ShopKit.NearWhite(Color3.fromRGB(255, 255, 255)), true)
		t.eq(ShopKit.NearWhite(Color3.fromRGB(255, 200, 110)), false, "the lantern amber is fine")
	end)

	t.test("everything the kit adds is inside the hall, under the ceiling, above the floor", function()
		local model = interior()
		local tol = 0.31
		for _, p in ipairs(parts(model)) do
			if p.Name ~= "Counter" then
				local x0, x1, y0, y1, z0, z1 = aabb(p)
				local label = KIND .. " " .. p.Name
				t.ok(x0 >= -frame.halfW - tol and x1 <= frame.halfW + tol, label .. " x " .. x0 .. ".." .. x1)
				t.ok(z0 >= -frame.halfD - tol and z1 <= frame.halfD + tol, label .. " z " .. z0 .. ".." .. z1)
				t.ok(y0 >= frame.floorTop - 0.2, label .. " above the floor")
				t.ok(y1 <= (Builder.TopY or frame.ceilY) + 0.25, label .. " under the top: " .. y1)
			end
		end
	end)

	t.test("the whole shop is still inside its part budget", function()
		local model = BuildingArt.Shop(KIND, KIND, Color3.fromRGB(47, 109, 181))
		-- (BuildingArt.spec pins the cap for the shop; the interior has the 400 above)
		t.ok(ShopKit.CountParts(model) <= 400, "parts: " .. ShopKit.CountParts(model))
	end)
end
