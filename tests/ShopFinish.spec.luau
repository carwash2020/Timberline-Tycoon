--!nocheck
-- T414d shop finish. Written first. Ceilings, dressed booths, hanging signs,
-- runners, thresholds, and the headroom over the walk. Do not loosen these to
-- make a build pass.
return function(t)
	local roblox = t.roblox
	local Enum = roblox.Enum
	local ShopPlace = t.load("ReplicatedStorage/Shared/Art/ShopPlace")
	local ShopBounds = t.load("ReplicatedStorage/Shared/World/ShopBounds")
	local Clearance = t.load("ReplicatedStorage/Shared/World/Clearance")

	local SHOPS = {
		"ToolShed",
		"HearthAndHome",
		"Dealership",
		"CoatKiosk",
		"HeatBoots",
		"OddsAndEnds",
		"SecretShop",
	}
	local BOOTHS = { "CoatKiosk", "HeatBoots", "OddsAndEnds", "SecretShop" }

	local CEILING = roblox.Color3.fromHex("#C49A63")
	local RUNNER = roblox.Color3.fromHex("#8A3B2E")
	local SLATE = roblox.Color3.fromHex("#8C877E")

	-- The opening's own frame. Furniture is not on this list.
	local FRAME = { Wall = true, DoorJamb = true, DoorHeader = true, DoorTrack = true, DoorFrame = true }

	local function build(kind)
		return ShopPlace.Build(kind, kind, roblox.Color3.fromRGB(196, 154, 99))
	end

	local function named(model, ...)
		local want = {}
		for _, n in ipairs({ ... }) do
			want[n] = true
		end
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and want[d.Name] then
				table.insert(out, d)
			end
		end
		return out
	end

	local function same(a, b)
		return math.abs(a.R - b.R) < 0.005 and math.abs(a.G - b.G) < 0.005 and math.abs(a.B - b.B) < 0.005
	end

	t.test("every shop has a plank ceiling in #C49A63", function()
		for _, kind in ipairs(SHOPS) do
			local model = build(kind)
			local ceilings = named(model, "ShopCeiling", "CeilingBoards")
			t.ok(#ceilings >= 1, kind .. " has no ceiling")
			for _, c in ipairs(ceilings) do
				t.ok(same(c.Color, CEILING), kind .. " ceiling colour")
				t.eq(c.Material, Enum.Material.WoodPlanks, kind .. " ceiling material")
				t.eq(c.CanCollide, false, kind .. " ceiling collides")
			end
		end
	end)

	t.test("every shop has at least 10 studs of clear height over the walk", function()
		for _, kind in ipairs(SHOPS) do
			local model = build(kind)
			local door = ShopBounds.Door(model)
			local walk = ShopBounds.Walk(model)
			t.ok(door ~= nil and walk ~= nil, kind .. " door and walk")
			local floorY = door.cf.Position.Y - door.size.Y / 2
			local column =
				Clearance.Box(walk.cf * roblox.CFrame.new(0, 40, 0), roblox.Vector3.new(walk.size.X, 80, walk.size.Z))
			local lowest = math.huge
			local who = ""
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and (d.CanCollide or d.Name == "ShopCeiling" or d.Name == "CeilingBoards") then
					if Clearance.BoxDepth(column, Clearance.Box(d.CFrame, d.Size)) > 0.05 then
						local cf, s = d.CFrame, d.Size
						local hy = (
							math.abs(cf.RightVector.Y) * s.X
							+ math.abs(cf.UpVector.Y) * s.Y
							+ math.abs(cf.LookVector.Y) * s.Z
						) / 2
						local bottom = cf.Position.Y - hy
						if bottom > floorY + 6 and bottom < lowest then
							lowest = bottom
							who = d.Name
						end
					end
				end
			end
			t.ok(lowest - floorY >= 10, kind .. " headroom " .. (lowest - floorY) .. " under " .. who)
		end
	end)

	t.test("the bare booths are dressed on the walls, off the walk", function()
		for _, kind in ipairs(BOOTHS) do
			local model = build(kind)
			local shelves = named(model, "WallShelf")
			local stock = named(model, "WallStock")
			t.ok(#shelves >= 2, kind .. " wall shelves " .. #shelves)
			t.ok(#stock >= 6, kind .. " wall stock " .. #stock)
			for _, part in ipairs(shelves) do
				t.eq(part.CanCollide, false, kind .. " shelf collides")
			end
			for _, item in ipairs(stock) do
				local best = math.huge
				for _, shelf in ipairs(shelves) do
					local gap = ShopBounds.RestGap(item, shelf)
					if math.abs(gap) < math.abs(best) then
						best = gap
					end
				end
				t.ok(best >= -1e-4 and best <= 0.05, kind .. " stock rests on a shelf, gap " .. best)
			end
		end
	end)

	t.test("every shop hangs a sign from chains, and the booths' sign hangs under the ceiling", function()
		for _, kind in ipairs(SHOPS) do
			local model = build(kind)
			local signs = named(model, "ShopHangSign", "AisleSign", "HeaderSign")
			t.ok(#signs >= 1, kind .. " hanging sign")
			local chains = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and string.sub(d.Name, -5) == "Chain" then
					chains += 1
				end
			end
			t.ok(chains >= 2, kind .. " chains " .. chains)
		end
		for _, kind in ipairs(BOOTHS) do
			local model = build(kind)
			local sign = named(model, "ShopHangSign")[1]
			t.ok(sign ~= nil, kind .. " ShopHangSign")
			local ceiling = named(model, "ShopCeiling")[1]
			t.ok(ceiling ~= nil, kind .. " ShopCeiling")
			t.ok(
				sign.CFrame.Position.Y + sign.Size.Y / 2 < ceiling.CFrame.Position.Y - ceiling.Size.Y / 2,
				kind .. " sign hangs under the ceiling"
			)
			t.eq(sign.CanCollide, false, kind .. " sign collides")
			local labels = 0
			for _, d in ipairs(sign:GetDescendants()) do
				if d:IsA("TextLabel") then
					labels += 1
				end
			end
			t.eq(labels, 2, kind .. " sign text on both faces")
		end
	end)

	t.test("runners are #8A3B2E fabric, and the Dealership is striped", function()
		for _, kind in ipairs(SHOPS) do
			local model = build(kind)
			local runners = named(model, "AisleRunner", "LobbyRunner")
			t.ok(#runners >= 1, kind .. " runner")
			for _, r in ipairs(runners) do
				t.ok(same(r.Color, RUNNER), kind .. " runner colour")
				t.eq(r.Material, Enum.Material.Fabric, kind .. " runner material")
			end
		end
		local stripes = named(build("Dealership"), "AisleStripe", "LobbyStripe")
		t.ok(#stripes >= 4, "Dealership painted stripes " .. #stripes)
		for _, s in ipairs(stripes) do
			t.eq(s.Material, Enum.Material.SmoothPlastic, "stripes are paint")
		end
	end)

	t.test("every door has a slate threshold and wood plank frames", function()
		for _, kind in ipairs(SHOPS) do
			local model = build(kind)
			local thresholds = named(model, "DoorThreshold")
			t.ok(#thresholds >= 1, kind .. " threshold")
			for _, th in ipairs(thresholds) do
				t.ok(same(th.Color, SLATE), kind .. " threshold colour")
				t.eq(th.Material, Enum.Material.Slate, kind .. " threshold material")
			end
			local frames = named(model, "DoorFrame", "DoorPost")
			t.ok(#frames >= 2, kind .. " frame boards " .. #frames)
			for _, f in ipairs(frames) do
				t.eq(f.Material, Enum.Material.WoodPlanks, kind .. " frame " .. f.Name .. " material")
			end
		end
	end)

	t.test("the shoulders are three studs and stay clear in every shop", function()
		t.eq(ShopBounds.Shoulder, 3)
		for _, kind in ipairs(SHOPS) do
			local model = build(kind)
			local door = ShopBounds.Door(model)
			local counter = model:FindFirstChild("Counter")
			for _, shoulder in ipairs(ShopBounds.Shoulders(door, counter.CFrame.Position, ShopBounds.Shoulder)) do
				t.eq(shoulder.size.X, 3, kind .. " shoulder width")
				t.eq(#ShopBounds.Hits(model, shoulder, FRAME), 0, kind .. " solid on a shoulder")
			end
		end
	end)
end
