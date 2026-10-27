--!nocheck
-- T410: oak and birch cut where the server ray hits, fall toward the notch,
-- and break into round bark logs. Prices stay on the square side t
-- (pi*r^2*L = t^2*L via StumpLogic.RoundRadius). Live fall and a 200-stud
-- truck drive are playtest: this file pins the pure rules.
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local roblox = t.roblox
	local Enum, Vector3, CFrame = roblox.Enum, roblox.Vector3, roblox.CFrame

	local SectionLogic = t.shared("SectionLogic")
	local StumpLogic = t.shared("StumpLogic")
	local FallLogic = t.shared("FallLogic")
	local CargoLock = t.shared("CargoLock")
	local WoodData = t.shared("WoodData")
	local GameConfig = t.shared("GameConfig")
	local SawmillLogic = t.shared("SawmillLogic")
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local TreeGen = t.shared("TreeGen")
	local TreeModels = t.load("ReplicatedStorage/Shared/Art/TreeModels")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local NearGrove = t.load("ReplicatedStorage/Shared/World/NearGrove")
	local Geometry = t.load("ReplicatedStorage/Shared/Lint/Geometry")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")

	local metricsOk, SectionMetrics = pcall(function()
		return t.load("ReplicatedStorage/Shared/SectionMetrics")
	end)

	local function build(id, seed)
		local skel = TreeGen.Skeleton(id, seed or 1, 1)
		return TreeArt.FromSkeleton(WoodData.Get(id), skel), skel
	end

	local function sectionsOf(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Section" then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("1 notch is the server ray, not the client's height", function()
		t.eq(GameConfig.CoreLoop, 2)
		t.eq(GameConfig.CutWindow, 0.6)
		t.eq(GameConfig.CutEdge, 0.5)
		t.ok(type(SectionLogic.NotchHeight) == "function", "SectionLogic.NotchHeight")
		t.ok(type(SectionLogic.RayHit) == "function", "SectionLogic.RayHit")
		-- Box centre (0, 10, 0), size (2, 20, 2). Eye (6, 4.5, 0), lied interior (0, 16, 0).
		-- The ray meets x = 1 at y = 14.083, more than 0.5 off the lied height.
		local cf = CFrame.new(0, 10, 0)
		local size = Vector3.new(2, 20, 2)
		local eye = Vector3.new(6, 4.5, 0)
		local lied = Vector3.new(0, 16, 0)
		local h = SectionLogic.NotchHeight(eye, lied, cf, size)
		t.ok(type(h) == "number", "a hit on the box")
		t.ok(math.abs(h - 14.083333) < 0.02, "ray height " .. tostring(h))
		t.ok(math.abs(h - 16) > 0.5, "client height is ignored")
		-- An honest surface point is the ray's own hit, so the height does not move.
		local from = Vector3.new(4, 3, 0)
		local hit = SectionLogic.AimAt(cf, size, from, Vector3.new(1, 3, 0), nil)
		local eye2 = Vector3.new(4, 4.5, 0)
		local honest = SectionLogic.NotchHeight(eye2, hit, cf, size)
		local want = SectionLogic.ClampHeight(cf:PointToObjectSpace(hit).Y, size.Y)
		t.ok(math.abs(honest - want) < 0.05, "honest aim stays on the same band")
	end)

	t.test("3 fall is toward the notch, at least 9 of 10", function()
		local matched = 0
		for i = 1, 10 do
			local a = (i - 1) / 10 * math.pi * 2
			local normal = Vector3.new(math.cos(a), 0.2, math.sin(a))
			local dir = StumpLogic.FallDirection(normal)
			t.ok(dir ~= nil, "a side face has a direction")
			if dir and dir:Dot(Vector3.new(normal.X, 0, normal.Z).Unit) > 0.99 then
				matched += 1
			end
		end
		t.ok(matched >= 9, "toward the cut face: " .. matched .. "/10")
		t.eq(StumpLogic.FallDirection(Vector3.new(0, 1, 0)), nil)
		t.eq(FallLogic.LiveFall, "playtest")
		t.eq(FallLogic.MaxSpin, 2.2)
		t.eq(FallLogic.MaxSpeed, 45)
		t.eq(FallLogic.LiftGap, 0.06)
	end)

	t.test("4 no WoodSection is a Block; oak and birch are round bark", function()
		t.ok(metricsOk and SectionMetrics ~= nil, "SectionMetrics")
		for _, id in ipairs({ "oak", "birch", "pine", "emberwood" }) do
			local model = build(id, 3)
			local n = 0
			for _, p in ipairs(sectionsOf(model)) do
				n += 1
				t.ok(p.Shape ~= Enum.PartType.Block, id .. " section is not a Block")
				t.eq(p.Shape, Enum.PartType.Cylinder, id)
				t.eq(p.Material, TreeArt.BarkMaterial(WoodData.Get(id)))
				t.ok(p.Material ~= Enum.Material.Neon, "bark is never Neon")
				t.ok(p.Material ~= Enum.Material.SmoothPlastic or id == "frostwood" or id == "lumenwood")
				local side = SectionMetrics.SquareSide(p)
				local diameter = math.min(p.Size.Y, p.Size.Z)
				t.ok(math.abs(diameter - 2 * StumpLogic.RoundRadius(side)) < 1e-3, id .. " diameter")
				t.eq(p:GetAttribute("BarkStuds"), 4)
				local _, logical = SectionMetrics.BlockFrame(p)
				local priced = logical.X * logical.Y * logical.Z
				local round = math.pi * (diameter / 2) ^ 2 * p.Size.X
				t.ok(math.abs(priced - round) / priced < 0.01, id .. " priced volume is the round volume")
			end
			t.ok(n >= 1, id .. " has sections")
		end
		local oak = WoodData.Get("oak")
		local birch = WoodData.Get("birch")
		t.eq(oak.v2.shape.bark, "#7A5230")
		t.eq(oak.v2.shape.leafColors[1], "#5DA24A")
		t.eq(oak.v2.core, "#E2BE84")
		t.eq(oak.v2.shape.trunkThickness, 2.0)
		t.eq(birch.v2.shape.bark, "#D8D2C4")
		t.eq(birch.v2.core, "#F1E3C2")
		t.eq(birch.v2.shape.trunkThickness, 1.6)
		t.eq(oak.v2.logPrice, 1.5)
		t.eq(birch.v2.logPrice, 2.25)
		-- Planks stay boards.
		local plank = roblox.Instance.new("Part")
		plank.Name = "Section"
		local holder = roblox.Instance.new("Model")
		holder:SetAttribute("Kind", "plank")
		plank.Parent = holder
		SectionMetrics.ApplyBlockFrame(plank, CFrame.new(0, 1, 0), Vector3.new(1, 2, 0.4))
		t.eq(plank.Shape, Enum.PartType.Block, "a plank stays a board")
	end)

	t.test("5 a mid cut keeps the priced volume within 1%", function()
		local node = {
			id = 1,
			parent = nil,
			children = {},
			cf = CFrame.identity,
			length = 20,
			thickness = 2,
		}
		local low, high = SectionLogic.SplitSection(node, 8, 2)
		local whole = SectionLogic.NodeVolume(node)
		local sum = SectionLogic.NodeVolume(low) + SectionLogic.NodeVolume(high)
		t.ok(math.abs(sum - whole) / whole < 0.01, "volumes sum")
		t.ok(math.abs(sum - whole) < 1e-6, "the split is exact")
		-- Oak t = 2: round area equals the square, so the price does not move.
		local r = StumpLogic.RoundRadius(2)
		t.ok(math.abs(math.pi * r * r - 4) < 1e-6, "pi r^2 = t^2")
	end)

	t.test("6 a round log's bed footprint does not change when it rolls", function()
		t.eq(CargoLock.SettleSec, 0.2)
		t.eq(CargoLock.RestSpeed, 0.6)
		t.eq(CargoLock.MinInside, 0.5)
		t.eq(CargoLock.ContactGap, 0.45)
		t.eq(CargoLock.LiveDrive, "playtest")
		t.eq(CargoLock.DriveStuds, 200)
		t.eq(CargoLock.DriveTurns, 2)
		-- Narrower than the rolled box's corners, wider than the true diameter.
		local diameter = 2.26
		local bed = Vector3.new(2.5, 0.5, 14)
		local size = Vector3.new(8, diameter, diameter)
		local radius = diameter / 2
		local rel = CFrame.new(0, bed.Y / 2 + radius, 0) * CFrame.Angles(0, math.rad(90), 0)
		local rolled = rel * CFrame.Angles(math.rad(45), 0, 0)
		local flat = CargoLock.InsideShare(bed, rel, size, "cylinder")
		local spin = CargoLock.InsideShare(bed, rolled, size, "cylinder")
		t.ok(math.abs(flat - spin) < 0.02, string.format("roll-invariant %.3f vs %.3f", flat, spin))
		t.ok(flat >= CargoLock.MinInside, "the round log is on the bed")
		t.ok(CargoLock.ContactsBed(bed, rolled, size, nil, "cylinder"), "a rolled log still touches the bed")
		local sample, settled = CargoLock.NoteRest(nil, Vector3.zero, 0)
		sample, settled = CargoLock.NoteRest(sample, Vector3.new(0.05, 0, 0), CargoLock.SettleSec)
		t.eq(settled, true, "still long enough, under RestSpeed")
		-- A box of the same size still uses corners: the 4th arg is the only cylinder switch.
		local boxSpin = CargoLock.InsideShare(bed, rolled, size)
		t.ok(boxSpin < flat - 0.05, "corners overhang; the cylinder does not")
	end)

	t.test("7 and 8 the mill toast and the owner of a cut stay", function()
		local mill = { maxWidth = 4, maxLength = 16 }
		t.eq(SawmillLogic.Toast("long", mill), "Too big for this mill (max 16.0 u long)")
		local cut = { height = 3, damage = 4, damageBy = { [7] = 3, [8] = 1 } }
		t.eq(SectionLogic.Owner(cut, 1), 7)
	end)

	t.test("9 stump MinHeight stays 2.5", function()
		t.eq(StumpLogic.MinHeight, 2.5)
		t.eq(StumpLogic.IsBaseCut(2.49), true)
		t.eq(StumpLogic.IsBaseCut(2.5), false)
		t.eq(#StumpLogic.Ratios, 16)
	end)

	t.test("10 MeshId set leaves no part fallback; split only past 20k tris", function()
		t.eq(TreeModels.TriHardCap, 20000)
		t.eq(TreeModels.PiecesFor(150), 1)
		t.eq(TreeModels.PiecesFor(20000), 1)
		t.eq(TreeModels.PiecesFor(20001), 2)
		t.eq(TreeModels.PiecesFor(40000), 2)
		t.ok(TreeModels.UsesMesh(TreeModels.SectionMesh("oak", 1)))
		t.ok(TreeModels.UsesMesh(TreeModels.SectionMesh("birch", 1)))
		MeshKit.Reset()
		MeshKit.Override = function(id, name, size)
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local model = build("oak", 4)
		MeshKit.Override = nil
		MeshKit.Reset()
		t.eq(model:GetAttribute("TreeMesh"), true)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Section" then
				t.eq(d.ClassName, "MeshPart", "no Part fallback")
				t.ok(d:GetAttribute("MeshId") ~= nil and d:GetAttribute("MeshId") ~= "0")
				t.ok(not d:IsA("Part") or d.Shape ~= Enum.PartType.Block)
			end
		end
	end)

	t.test("11 and 12 a resting log touches the ground and the river bed, and does not sink", function()
		t.ok(type(FallLogic.RestCentre) == "function", "RestCentre")
		t.ok(type(FallLogic.ClearsGround) == "function", "ClearsGround")
		t.ok(type(FallLogic.RestOnPlane) == "function", "RestOnPlane")
		t.eq(FallLogic.WaterPolicy, "drag")
		local radius = 1.13
		local centre = FallLogic.RestCentre(Vector3.new(2, 8, 3), 10, radius, Vector3.new(1, 0.4, 0), 4)
		t.ok(math.abs(centre.Y - (4 + radius)) < 1e-4, "sits on the ground")
		t.ok(FallLogic.ClearsGround(centre, radius, 4))
		t.ok(centre.Y - radius >= 4 - Geometry.MinDepth)
		local function gap(grade)
			local n = Vector3.new(-grade, 1, 0).Unit
			local plane = Vector3.new(0, 20, 0)
			local at = FallLogic.RestOnPlane(plane, 10, radius, Vector3.new(0, 0, 1), plane, n)
			return (at - plane):Dot(n) - radius
		end
		t.ok(math.abs(gap(0.12)) < 1e-3, "12% road")
		t.ok(math.abs(gap(0.4)) < 1e-3, "steeper bank")
		local bed = FallLogic.RestCentre(Vector3.new(0, 9, 0), 8, radius, Vector3.new(1, 0, 0), 5)
		t.ok(bed.Y - radius >= 5 - 1e-4, "does not punch the river bed")
	end)

	t.test("13 14 15 two players, a re-cut and a standing stump stay server-owned", function()
		local claim = { userId = 4, at = 10 }
		local function here(id)
			return id == 4
		end
		t.eq(SectionLogic.ClaimBlocks(claim, 9, 11, false, here), 4)
		t.eq(SectionLogic.ClaimBlocks(claim, 4, 11, false, here), nil)
		local recut = StumpLogic.Recut(6, 4)
		t.ok(recut.cutAt <= 4 + 1e-6, "the cut does not rise")
		t.ok(recut.logLength >= StumpLogic.MinLog - 1e-6, "a real log")
	end)

	t.test("16 and 17 MustKeep, WorldHalf and the near grove stay", function()
		t.eq(WorldLayout.WorldHalf, 1350)
		t.eq(NearGrove.Outer, 70)
		local list = serde.decode("json", fs.readFile("tests/mustkeep.json"))
		local door = nil
		for _, e in ipairs(list.world) do
			if e.path == "TimberlineMap/GateLodge/Door" then
				door = e
			end
		end
		t.ok(door ~= nil, "gate lodge door is still on the list")
		t.eq(door.pos[1], -48)
		t.eq(door.pos[2], 41.21)
		t.eq(door.pos[3], 730.05)
	end)

	t.test("a cut face is core-coloured Wood, never Neon", function()
		for _, id in ipairs({ "oak", "birch", "lumenwood" }) do
			local def = WoodData.Get(id)
			local color, material = TreeArt.FaceLook(def)
			t.eq(color, TreeArt.Core(def), id)
			t.eq(material, Enum.Material.Wood, id)
			t.ok(material ~= Enum.Material.Neon)
		end
		t.eq(select(2, TreeArt.Core(WoodData.Get("lumenwood"))), Enum.Material.Neon, "Core itself stays")
	end)
end
