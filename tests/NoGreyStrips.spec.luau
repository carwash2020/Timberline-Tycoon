--!nocheck
-- NoGreyStrips (T406): no thin grey bar lies on the grass round the plots and
-- the lot. The only grey allowed there is CurbConcrete #9A968C (TownGround's
-- curbs: 0.3 x 0.15, or 0.5 x 0.4 on the lot's edge). Before: each parking
-- stall had a StoneBase "Curb" block (4 x 0.45 x 0.8, #8C877E) across its
-- tail, and the Graphite plot's claimed rail was #525458 (a 0.35 x 0.4 bar
-- round the yard).
return function(t)
	local roblox = t.roblox
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local TownGround = t.load("ReplicatedStorage/Shared/World/TownGround")
	local PlotData = t.shared("PlotData")

	local CURB = "9A968C"
	local GREY_SPREAD = 16 -- channels within this of each other read grey

	local function isGrey(c)
		local r, g, b = math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
		return math.max(r, g, b) - math.min(r, g, b) <= GREY_SPREAD
	end

	-- A bar: one side at most a stud, the longest at least 3 times the middle one.
	local function isBar(size)
		local d = { size.X, size.Y, size.Z }
		table.sort(d)
		return d[1] <= 1 and d[3] >= 3 * d[2]
	end

	local function offenders(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and isGrey(d.Color) and isBar(d.Size) then
				if d.Color:ToHex() ~= CURB then
					table.insert(out, d.Name .. " " .. d.Color:ToHex())
				end
			end
		end
		return out
	end

	t.test("the checker: an old stall curb and a grey rail are caught, a CurbConcrete bar is not", function()
		local f = roblox.Instance.new("Folder")
		Kit.part(f, "Curb", roblox.Vector3.new(4, 0.45, 0.8), roblox.CFrame.new(), roblox.Color3.fromRGB(140, 135, 126))
		Kit.part(f, "Rail", roblox.Vector3.new(80, 0.35, 0.4), roblox.CFrame.new(), roblox.Color3.fromRGB(82, 84, 88))
		local ok = roblox.Instance.new("Folder")
		Kit.part(ok, "LotCurb", roblox.Vector3.new(60, 0.4, 0.5), roblox.CFrame.new(), TownGround.CurbColor)
		t.eq(#offenders(f), 2)
		t.eq(#offenders(ok), 0)
	end)

	t.test("a parking bay (lines, bar, number, lamp) has no grey bar", function()
		local town = WorldPlan.Town()
		local f = roblox.Instance.new("Folder")
		for i = 1, #town.parkingSizes do
			local slot = Kit.part(
				f,
				"ParkingSlot_" .. i,
				town.parkingSizes[i],
				roblox.CFrame.new(i * 20, 0, 0),
				roblox.Color3.new(1, 1, 1)
			)
			BuildingArt.ParkingBay(slot, i)
		end
		t.eq(offenders(f), {})
	end)

	t.test("every plot look's rail (claimed) and the free rail are not grey", function()
		for _, look in ipairs(PlotData.Looks) do
			local c = roblox.Color3.fromRGB(look.rail[1], look.rail[2], look.rail[3])
			t.ok(not isGrey(c), look.name .. "'s rail is not grey")
		end
		t.ok(not isGrey(roblox.Color3.fromRGB(196, 168, 120)), "the free rail is tan")
	end)

	t.test("the town's curbs are CurbConcrete and nothing else grey is a bar in TownGround's curb group", function()
		for _, p in ipairs(TownGround.Pieces()) do
			if p.kind == "Curb" or p.kind == "LotCurb" then
				t.eq(p.color:ToHex(), CURB, p.name)
			end
		end
	end)

	t.test("terrain sampled every 4 studs over each plot and the lot has no Asphalt, Rock or Slate", function()
		local banned = { Asphalt = true, Rock = true, Slate = true }
		local bad, checked = {}, 0
		local function sample(x0, x1, z0, z1, label)
			for x = x0, x1, 4 do
				for z = z0, z1, 4 do
					local _, material = TerrainGen.Sample(x, z)
					checked += 1
					if
						banned[material] and not TownGround.Covers(x, z, { Road = true, Yard = true, Path = true }, 0.5)
					then
						table.insert(bad, string.format("%s (%d, %d) %s", label, x, z, material))
					end
				end
			end
		end
		local half = PlotData.Tiers[1].size / 2 + PlotData.PlatformRamp
		for i, c in ipairs(PlotData.Slots) do
			sample(c.X - half, c.X + half, c.Y - half, c.Y + half, "plot " .. i)
		end
		local lot = WorldLayout.ParkingLot
		sample(lot.x0, lot.x1, lot.z0, lot.z1, "lot")
		t.ok(checked > 1000, "samples: " .. checked)
		t.eq(bad, {})
	end)
end
