--!nocheck
-- T391, tier signs only on upgrades: trucks and trailers show no tier sign unless they are an upgraded
-- version of an existing one (ItemCatalog `upgradeOf`, nil on all nine real entries). An upgrade gets
-- one small plaque on its name sign ("Mk II" over "Upgrade of <name>", cream board, brass frame, sign ink);
-- no tier colour, no flag. Axes and mills keep their tiers.
return function(t)
	local fs = require("@lune/fs")
	local roblox = t.roblox

	local TIER_PARTS = { TierPost = true, TierBacking = true, TierFlag = true }

	local function fresh()
		local loader = t.loader()
		return {
			catalog = loader:shared("ItemCatalog"),
			tier = loader:shared("StoreTier"),
			lot = loader:load("ReplicatedStorage/Shared/Art/DealershipLot"),
			art = loader:load("ReplicatedStorage/Shared/Art/TruckArt"),
			stock = loader:shared("StoreStock"),
			box = loader:shared("ItemBox"),
		}
	end

	local function offenders(root)
		local bad = {}
		for _, d in ipairs(root:GetDescendants()) do
			if TIER_PARTS[d.Name] or d.Name == "StandTier" or d:GetAttribute("StandTier") ~= nil then
				table.insert(bad, d.Name)
			end
		end
		if TIER_PARTS[root.Name] or root:GetAttribute("StandTier") ~= nil then
			table.insert(bad, root.Name)
		end
		return bad
	end

	local function named(root, name)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == name then
				table.insert(out, d)
			end
		end
		return out
	end

	local function textsOf(part)
		local out = {}
		for _, d in ipairs(part:GetDescendants()) do
			if d:IsA("TextLabel") then
				table.insert(out, d.Text)
			end
		end
		return out
	end

	---------------------------------------------------------------------------
	-- 1. no tier sign on any real vehicle or trailer
	---------------------------------------------------------------------------

	t.test("no TierPost, TierBacking, TierFlag or StandTier on any vehicle or trailer", function()
		local m = fresh()
		-- the world model: the display lot (plinths, bands, stripes, name signs, the vehicles)
		local lot = m.lot.Build()
		t.eq(offenders(lot), {}, "the display lot")
		t.eq(#named(lot, "UpgradePlaque"), 0, "and no plaque: nothing in the real data is an upgrade")
		-- the pad
		local pad =
			m.lot.BuildPad(roblox.Instance.new("Folder"), roblox.CFrame.new(), roblox.Color3.new(1, 0, 0), 20, 10)
		t.eq(offenders(pad), {}, "the spawn pad")
		-- a spawned (bought) truck, alone and towing each trailer
		local pickup = m.catalog.GetTruck("Pickup")
		for _, def in ipairs(m.catalog.TruckList()) do
			t.eq(offenders(m.art.Build(def)), {}, def.id .. " spawned")
		end
		for _, trailer in ipairs(m.catalog.TrailerList()) do
			t.eq(offenders(m.art.Build(pickup, nil, trailer)), {}, trailer.id .. " spawned behind a Pickup")
		end
		-- the price board and the store card: no tier word for a vehicle anywhere
		for _, v in ipairs(m.box.Showroom) do
			t.eq(m.tier.Of(v.kind, v.id), nil, v.id .. " has no tier")
			t.eq(m.tier.LockOf(v.kind, v.id), nil, v.id .. " has no lock")
			t.eq(m.tier.UpgradeOf(v.kind, v.id), nil, v.id .. " is no upgrade")
			t.eq(m.stock.TierLabel(v.kind, v.id), nil, v.id .. " has no box tier line")
		end
		for _, def in pairs(m.catalog.Trucks) do
			t.eq(def.upgradeOf, nil, def.id .. " upgradeOf is nil")
		end
		for _, def in pairs(m.catalog.Trailers) do
			t.eq(def.upgradeOf, nil, def.id .. " upgradeOf is nil")
		end
	end)

	---------------------------------------------------------------------------
	-- 2. a fixture upgrade gets exactly one plaque, naming the base
	---------------------------------------------------------------------------

	t.test("a fixture with upgradeOf (never in real data) gets exactly one plaque naming the base", function()
		local m = fresh()
		m.catalog.Trucks.Pickup.upgradeOf = "Rustbucket"
		t.eq(m.tier.UpgradeOf("Truck", "Pickup"), "Rustbucket")
		t.eq(m.tier.Of("Truck", "Pickup"), 2, "it is a second mark")
		local lot = m.lot.Build()
		t.eq(offenders(lot), {}, "still no flag, post or tier stand")
		local plaques = named(lot, "UpgradePlaque")
		t.eq(#plaques, 1, "exactly one plaque")
		local plaque = plaques[1]
		local hex = roblox.Color3.fromHex
		t.eq(plaque.Color, hex("#F3E7C9"), "SignCream board")
		local frames = named(lot, "UpgradePlaqueFrame")
		t.eq(#frames, 1, "one frame")
		t.eq(frames[1].Color, hex("#C9A24A"), "Brass frame")
		t.ok(frames[1].Size.X >= 2.8 and frames[1].Size.X <= 3.2, "about 3 studs wide: " .. frames[1].Size.X)
		t.ok(frames[1].Size.Y >= 0.9 and frames[1].Size.Y <= 1.1, "about 1 stud tall: " .. frames[1].Size.Y)
		t.eq(plaque.CanCollide, false)
		local base = m.catalog.GetTruck("Rustbucket").displayName
		local seen = {}
		for _, d in ipairs(plaque:GetDescendants()) do
			if d:IsA("TextLabel") then
				t.eq(d.TextColor3, hex("#2A2420"), "SignInk text")
				local limit = d:FindFirstChildOfClass("UITextSizeConstraint")
				t.ok(limit and limit.MinTextSize == 14, "MinTextSize 14")
				seen[d.Text] = d.Font.Name
			end
		end
		t.eq(seen["Mk II"], "FredokaOne", "line 1")
		t.eq(seen["Upgrade of " .. base], "Gotham", "line 2 names the base")
		-- it stands on the Pickup's own name sign
		local pickupSign
		for _, sign in ipairs(named(lot, "NameSign")) do
			if table.concat(textsOf(sign), " "):find(m.catalog.GetTruck("Pickup").displayName, 1, true) then
				pickupSign = sign
			end
		end
		t.ok(pickupSign, "the Pickup has its name sign")
		t.ok(math.abs(plaque.CFrame.Position.X - pickupSign.CFrame.Position.X) < 0.01, "on the name sign")
		t.ok(plaque.CFrame.Position.Y > pickupSign.CFrame.Position.Y, "above it")
	end)

	t.test("a trailer fixture with upgradeOf gets its plaque too", function()
		local m = fresh()
		m.catalog.Trailers.RanchTrailer.upgradeOf = "PonyTrailer"
		local lot = m.lot.Build()
		t.eq(#named(lot, "UpgradePlaque"), 1)
		t.eq(offenders(lot), {})
	end)

	---------------------------------------------------------------------------
	-- 3. a bad upgradeOf fails validation and never crashes the Dealership
	---------------------------------------------------------------------------

	t.test(
		"upgradeOf at a missing id, at itself, or at something it does not beat is no upgrade, and nothing crashes",
		function()
			local cases = {
				{
					label = "a missing id",
					set = function(c)
						c.Trucks.Pickup.upgradeOf = "NoSuchTruck"
					end,
				},
				{
					label = "itself",
					set = function(c)
						c.Trucks.Pickup.upgradeOf = "Pickup"
					end,
				},
				{
					label = "a dearer truck",
					set = function(c)
						c.Trucks.Pickup.upgradeOf = "Flatbed"
					end,
				},
				{
					label = "a truck of the same bed",
					set = function(c)
						c.Trucks.Pickup.upgradeOf = "TimberClassic"
					end,
				},
				{
					label = "a trailer id",
					set = function(c)
						c.Trucks.Pickup.upgradeOf = "PonyTrailer"
					end,
				},
				{
					label = "a non-string",
					set = function(c)
						c.Trucks.Pickup.upgradeOf = 7
					end,
				},
				{
					label = "a missing trailer",
					set = function(c)
						c.Trailers.RanchTrailer.upgradeOf = "Nope"
					end,
				},
				{
					label = "itself (trailer)",
					set = function(c)
						c.Trailers.RanchTrailer.upgradeOf = "RanchTrailer"
					end,
				},
			}
			for _, case in ipairs(cases) do
				local m = fresh()
				case.set(m.catalog)
				t.eq(m.tier.UpgradeOf("Truck", "Pickup"), nil, case.label .. ": truck")
				t.eq(m.tier.UpgradeOf("Trailer", "RanchTrailer"), nil, case.label .. ": trailer")
				t.eq(m.tier.Of("Truck", "Pickup"), nil, case.label .. ": no tier")
				local ok, lot = pcall(m.lot.Build)
				t.ok(ok, case.label .. " crashed the Dealership: " .. tostring(lot))
				if ok then
					t.eq(#named(lot, "UpgradePlaque"), 0, case.label .. ": no plaque")
					t.eq(offenders(lot), {}, case.label .. ": no tier sign")
				end
			end
		end
	)

	t.test("unknown kinds and ids have no upgrade", function()
		local m = fresh()
		t.eq(m.tier.UpgradeOf("Axe", "RustyAxe"), nil)
		t.eq(m.tier.UpgradeOf("Truck", "Nope"), nil)
		t.eq(m.tier.UpgradeOf("Trailer", "Nope"), nil)
	end)

	---------------------------------------------------------------------------
	-- 4. no tier text hardcoded outside data; axes and mills keep their tiers
	---------------------------------------------------------------------------

	t.test("no tier text is hardcoded in the dealership builders: the plaque's words come from StoreTier", function()
		for _, path in ipairs({
			"src/ReplicatedStorage/Shared/Art/DealershipLot.luau",
			"src/ReplicatedStorage/Shared/Art/ShopInteriors/Dealership.luau",
		}) do
			local text = fs.readFile(path)
			for _, banned in ipairs({ '"Mk II"', "Mk II", "Upgrade of", '"T"', "TIER " }) do
				t.eq(string.find(text, banned, 1, true), nil, path .. " has " .. banned)
			end
			t.eq(string.find(text, '"T%d'), nil, path .. " has a hardcoded T label")
		end
		local tierText = fs.readFile("src/ReplicatedStorage/Shared/StoreTier.luau")
		t.ok(string.find(tierText, 'StoreTier.UpgradeMark = "Mk II"', 1, true), "the words live in StoreTier")
		-- no source file outside StoreTier says "Mk II"
		local function walk(dir, out)
			for _, name in ipairs(fs.readDir(dir)) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					if name ~= "Vendor" then
						walk(path, out)
					end
				elseif string.match(name, "%.luau$") then
					table.insert(out, path)
				end
			end
			return out
		end
		for _, path in ipairs(walk("src", {})) do
			if path ~= "src/ReplicatedStorage/Shared/StoreTier.luau" then
				t.eq(string.find(fs.readFile(path), "Mk II", 1, true), nil, path .. " hardcodes the plaque's tier text")
			end
		end
	end)

	t.test("axes and mills keep their tiers", function()
		local m = fresh()
		for i, axe in ipairs(m.catalog.AxeLadder()) do
			t.eq(m.tier.Of("Axe", axe.id), i, axe.id)
		end
		for _, mill in ipairs(m.catalog.SawmillList()) do
			t.eq(m.tier.Of("Sawmill", mill.id), mill.tier, mill.id)
		end
		t.eq(m.tier.Of("Machine", "PlanerHand"), 1)
		t.eq(m.tier.Of("Machine", "PlanerIndustrial"), 4)
	end)
end
