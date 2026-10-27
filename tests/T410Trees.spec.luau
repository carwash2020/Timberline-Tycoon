--!nocheck
-- T410-fix: oak and birch cut where the server ray hits, fall toward the
-- notched face, and stay square PartType.Block logs. Prices stay on the
-- square side t (volume t^2 * L). Live fall and a 200-stud truck drive are
-- playtest: this file pins the pure rules. No section is a cylinder.
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
	local SectionMetrics = t.load("ReplicatedStorage/Shared/SectionMetrics")

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

	t.test("1 notch is the server ray, not the client's height; CutWindow is 1.0", function()
		t.eq(GameConfig.CoreLoop, 2)
		t.eq(GameConfig.CutWindow, 1.0, "full band is 1.0; half is 0.5")
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
		local from = Vector3.new(4, 3, 0)
		local hit = SectionLogic.AimAt(cf, size, from, Vector3.new(1, 3, 0), nil)
		local eye2 = Vector3.new(4, 4.5, 0)
		local honest = SectionLogic.NotchHeight(eye2, hit, cf, size)
		local want = SectionLogic.ClampHeight(cf:PointToObjectSpace(hit).Y, size.Y)
		t.ok(math.abs(honest - want) < 0.05, "honest aim stays on the same band")
	end)

	t.test("2 the notch is on the hit face and the fall is toward that face", function()
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
		t.eq(TreeArt.NotchShade, -0.25)
		local model = build("oak", 3)
		local sec = sectionsOf(model)[1]
		local side = SectionMetrics.SquareSide(sec)
		local frame = SectionMetrics.BlockFrame(sec)
		local notch = TreeArt.Notch(WoodData.Get("oak"), sec, 4, frame.XVector, 1, 1)
		t.eq(notch.Shape, Enum.PartType.Block, "the notch is a face wedge, not a ring")
		t.ok(math.abs(notch.Size.Z - (side + 0.04)) < 1e-3, "the wedge spans the hit face")
		local local_ = frame:PointToObjectSpace(notch.CFrame.Position)
		t.ok(local_.X > 0, "the wedge sits on the +X face that was hit")
		t.ok(math.abs(math.abs(local_.X) + notch.Size.X / 2 - (side / 2 + 0.02)) < 1e-3, "outer face proud of the bark")
	end)

	t.test("3 every wood section is a Block; oak and birch keep their colours", function()
		for _, id in ipairs({ "oak", "birch", "pine", "emberwood" }) do
			local model = build(id, 3)
			local n = 0
			local def = WoodData.Get(id)
			for _, p in ipairs(sectionsOf(model)) do
				n += 1
				t.eq(p.ClassName, "Part", id .. " section is a Part")
				t.ok(not p:IsA("MeshPart"), id .. " section is not a MeshPart")
				t.eq(p.Shape, Enum.PartType.Block, id .. " section is a Block")
				t.ok(p.Shape ~= Enum.PartType.Cylinder, id .. " is not a cylinder")
				t.eq(SectionMetrics.IsCylinder(p), false)
				t.eq(SectionMetrics.IsRound(p), false)
				t.eq(p.Material, TreeArt.BarkMaterial(def))
				t.ok(p.Material ~= Enum.Material.Neon, "bark is never Neon")
				t.ok(p.Material ~= Enum.Material.SmoothPlastic or id == "frostwood" or id == "lumenwood")
				local _, logical = SectionMetrics.BlockFrame(p)
				local side = SectionMetrics.SquareSide(p)
				t.ok(math.abs(p.Size.X - side) < 1e-4 and math.abs(p.Size.Z - side) < 1e-4, id .. " square side")
				t.ok(math.abs(p.Size.Y - logical.Y) < 1e-4, id .. " length on Y")
				t.ok(math.abs(SectionMetrics.Radius(p) - side / 2) < 1e-6, id .. " rest radius is half the side")
				t.eq(p:GetAttribute("BarkStuds"), 4)
				t.eq(TreeArt.BarkStuds, 4)
				local priced = logical.X * logical.Y * logical.Z
				local box = p.Size.X * p.Size.Y * p.Size.Z
				t.ok(math.abs(priced - box) / priced < 0.01, id .. " priced volume is the Block")
				t.ok(math.abs(priced - side * side * logical.Y) < 1e-3, id .. " priced volume is t^2 * L")
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
		t.eq(birch.v2.shape.leafColors[1], "#A6CE5C")
		t.eq(birch.v2.core, "#F1E3C2")
		t.eq(birch.v2.shape.trunkThickness, 1.6)
		t.eq(oak.v2.logPrice, 1.5)
		t.eq(birch.v2.logPrice, 2.25)
		local plank = roblox.Instance.new("Part")
		plank.Name = "Section"
		local holder = roblox.Instance.new("Model")
		holder:SetAttribute("Kind", "plank")
		plank.Parent = holder
		SectionMetrics.ApplyBlockFrame(plank, CFrame.new(0, 1, 0), Vector3.new(1, 2, 0.4))
		t.eq(plank.Shape, Enum.PartType.Block, "a plank stays a board")
		t.ok(
			math.abs(plank.Size.X - 1) < 1e-3
				and math.abs(plank.Size.Y - 2) < 1e-3
				and math.abs(plank.Size.Z - 0.4) < 1e-3
		)
	end)

	t.test("4 a mid cut keeps the priced volume within 1%", function()
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
		t.ok(math.abs(whole - SectionLogic.Volume(2, 20, 2)) < 1e-6, "priced volume is t^2 * L")
		t.eq(low.thickness, 2)
		t.eq(high.thickness, 2)
	end)

	t.test("5 a cut under 2.5 clears; at 2.5 the stump is one square Block", function()
		t.eq(StumpLogic.MinHeight, 2.5)
		t.eq(StumpLogic.IsBaseCut(2.49), true)
		t.eq(StumpLogic.IsBaseCut(2.5), false)
		t.eq(StumpLogic.WeatherStart, 90)
		t.eq(StumpLogic.WeatherFull, 170)
		t.eq(StumpLogic.FadeStart, 180)
		t.eq(StumpLogic.FadeEnd, 190)
		t.eq(StumpLogic.SinkDepth, 0.3)
		local shape = StumpLogic.Shape({ { length = 20, thickness = 2 } }, 3)
		local model = roblox.Instance.new("Model")
		local parts = TreeArt.StumpDress(WoodData.Get("oak"), model, CFrame.identity, shape, {})
		local blocks = 0
		for _, p in ipairs(parts) do
			if p.Name == "StumpMesh" then
				blocks += 1
				t.eq(p.ClassName, "Part")
				t.eq(p.Shape, Enum.PartType.Block)
				t.ok(p.Shape ~= Enum.PartType.Cylinder)
				t.ok(math.abs(p.Size.X - 2) < 1e-3 and math.abs(p.Size.Z - 2) < 1e-3, "side is the trunk thickness")
				t.ok(math.abs(p.Size.Y - 3) < 1e-3, "as tall as the cut")
			end
		end
		t.eq(blocks, 1, "one square stump")
		local cap = nil
		for _, p in ipairs(parts) do
			if p.Name == "StumpCap" then
				cap = p
			end
		end
		t.ok(cap ~= nil and cap.Shape == Enum.PartType.Block, "square cap")
		t.ok(math.abs(cap.CFrame.Position.Y + cap.Size.Y / 2 - 3) < 1e-3, "cap flush on top")
	end)

	t.test("6 cargo, the mill and a sale read the square side", function()
		t.eq(CargoLock.SettleSec, 0.2)
		t.eq(CargoLock.RestSpeed, 0.6)
		t.eq(CargoLock.MinInside, 0.5)
		t.eq(CargoLock.ContactGap, 0.45)
		t.eq(CargoLock.LiveDrive, "playtest")
		t.eq(CargoLock.DriveStuds, 200)
		t.eq(CargoLock.DriveTurns, 2)
		local side, length = 2, 8
		local part = roblox.Instance.new("Part")
		part.Name = "Section"
		SectionMetrics.ApplyBlockFrame(part, CFrame.identity, Vector3.new(side, length, side))
		t.eq(part.Shape, Enum.PartType.Block)
		t.eq(part.Size, Vector3.new(side, length, side))
		-- Length along the bed (world Z), square cross-section sitting on the deck.
		local bed = Vector3.new(side + 0.05, 0.5, length + 2)
		local rel = CFrame.new(0, bed.Y / 2 + side / 2, 0) * CFrame.Angles(math.pi / 2, 0, 0)
		part.CFrame = rel
		local poseCf, poseSize, poseShape = SectionMetrics.CargoPose(part)
		t.eq(poseShape, nil, "wood is a box, not a cylinder")
		t.eq(poseSize, part.Size)
		t.eq(poseCf, part.CFrame)
		t.eq(SectionMetrics.IsRound(part), false)
		t.eq(SectionMetrics.IsCylinder(part), false)
		local share = CargoLock.InsideShare(bed, poseCf, poseSize, poseShape)
		t.ok(share > 0.99, string.format("a bed of side+0.05 fits the square (%.3f)", share))
		t.ok(CargoLock.ContactsBed(bed, poseCf, poseSize, nil, poseShape), "the square log touches the bed")
		-- A roll is a box: corners can leave the bed. The geometry stays the Block.
		local rolled = rel * CFrame.Angles(0, 0, math.rad(45))
		local spin = CargoLock.InsideShare(bed, rolled, poseSize, nil)
		t.ok(spin <= share + 1e-6, "a rolled square is not treated as a round log")
		local mesh = roblox.Instance.new("MeshPart")
		mesh.Name = "Section"
		mesh.Size = Vector3.new(side, length, side)
		mesh:SetAttribute(SectionMetrics.SquareSideAttr, side)
		local _, meshSize, meshShape = SectionMetrics.CargoPose(mesh)
		t.eq(meshShape, nil)
		t.eq(meshSize, mesh.Size, "a MeshPart section is not turned into a round diameter")
		t.eq(SectionMetrics.IsRound(mesh), false)
		local mill = { maxWidth = 4, maxLength = 16 }
		local piece = {
			kind = "log",
			sections = {
				{
					length = length,
					sx = side,
					sz = side,
					dir = Vector3.yAxis,
					children = 0,
					root = true,
				},
			},
		}
		local accepted, why = SawmillLogic.Accepts(piece, mill)
		t.eq(accepted, true, "the square side fits the mill: " .. tostring(why))
		local volume = SawmillLogic.SectionVolume(piece.sections[1])
		t.ok(math.abs(volume - SectionLogic.Volume(side, length, side)) < 1e-6, "mill volume is t^2 * L")
		local price = WoodData.Get("oak").v2.logPrice
		t.ok(math.abs(SectionLogic.Value(volume, price) - volume * price) < 1e-6, "sale is volume times price")
		local tooWide = {
			kind = "log",
			sections = {
				{
					length = length,
					sx = mill.maxWidth * GameConfig.WoodUnit + 0.5,
					sz = mill.maxWidth * GameConfig.WoodUnit + 0.5,
					dir = Vector3.yAxis,
					children = 0,
					root = true,
				},
			},
		}
		local wideOk, wideWhy = SawmillLogic.Accepts(tooWide, mill)
		t.eq(wideOk, false)
		t.eq(wideWhy, "thick")
		t.eq(SawmillLogic.Toast("long", mill), "Too big for this mill (max 16.0 u long)")
		local cut = { height = 3, damage = 4, damageBy = { [7] = 3, [8] = 1 } }
		t.eq(SectionLogic.Owner(cut, 1), 7)
	end)

	t.test("MeshId dresses the crown only; the section stays a Block; split only past 20k tris", function()
		t.eq(TreeModels.TriHardCap, 20000)
		t.eq(TreeModels.PiecesFor(150), 1)
		t.eq(TreeModels.PiecesFor(20000), 1)
		t.eq(TreeModels.PiecesFor(20001), 2)
		t.eq(TreeModels.PiecesFor(40000), 2)
		t.ok(TreeModels.UsesMesh(TreeModels.SectionMesh("oak", 1)))
		t.ok(TreeModels.UsesMesh(TreeModels.SectionMesh("birch", 1)))
		MeshKit.Reset()
		MeshKit.Override = function(id, name, size)
			local made = roblox.Instance.new("MeshPart")
			made.Name = name
			made.Size = size
			made:SetAttribute("MeshId", tostring(id))
			return made
		end
		local model = build("oak", 4)
		MeshKit.Override = nil
		MeshKit.Reset()
		t.eq(model:GetAttribute("TreeMesh"), true)
		local crowns = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Section" then
				t.eq(d.ClassName, "Part", "the section stays a Part")
				t.eq(d.Shape, Enum.PartType.Block, "the section stays a Block")
				t.ok(d:GetAttribute("MeshId") == nil, "the section mesh is not the section")
			elseif d.Name == "Leaves" and d:IsA("Part") then
				t.ok(false, "the part-built leaf stand-in is gone")
			elseif d.Name == "Leaves" and d:IsA("MeshPart") then
				crowns += 1
				t.ok(d:GetAttribute("MeshId") ~= nil and d:GetAttribute("MeshId") ~= "0")
				t.eq(d.CanCollide, false, "a crown mesh does not collide")
			end
		end
		t.ok(crowns >= 1, "a crown mesh landed")
	end)

	t.test("a resting log uses half the square side and does not sink", function()
		t.ok(type(FallLogic.RestCentre) == "function", "RestCentre")
		t.ok(type(FallLogic.ClearsGround) == "function", "ClearsGround")
		t.ok(type(FallLogic.RestOnPlane) == "function", "RestOnPlane")
		t.eq(FallLogic.WaterPolicy, "drag")
		local radius = 1
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

	t.test("two players, a re-cut and a standing stump stay server-owned", function()
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

	t.test("MustKeep, WorldHalf and the near grove stay", function()
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
		local model = build("oak", 1)
		local face = TreeArt.CutFace(WoodData.Get("oak"), model.PrimaryPart, true)
		local crack = nil
		for _, d in ipairs(face:GetChildren()) do
			if d.Name == "CutCrack" then
				crack = d
			end
		end
		t.ok(crack ~= nil and crack:IsA("Part") and crack.Shape == Enum.PartType.Block, "a thin crack on the cut face")
		t.ok(crack.Size.Z < crack.Size.X, "the crack is a line, not a disc")
	end)
end
