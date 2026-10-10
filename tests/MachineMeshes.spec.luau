--!nocheck
-- Job 15 (K-wirein): the Blender machines on the plot machines and the logic
-- pieces. Lune cannot load meshes, so these tests hand MeshKit an Override
-- (a MeshPart stand-in of the asked size) and check the mesh path, then clear
-- it. The part build is the fallback; it is checked with the ids forced to 0.
return function(t)
	local fs = require("@lune/fs")
	local roblox = t.roblox
	local Instance, Vector3, Enum = roblox.Instance, roblox.Vector3, roblox.Enum
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local MachineMeshes = t.load("ReplicatedStorage/Shared/Art/MachineMeshes")
	local MachineSkin = t.load("ReplicatedStorage/Shared/Art/MachineSkin")
	local MachineArt = t.load("ReplicatedStorage/Shared/Art/MachineArt")
	local MiningArt = t.load("ReplicatedStorage/Shared/Mining/MiningArt")
	local MeshManifest = t.load("ReplicatedStorage/Shared/Art/MeshManifest")
	local Catalog = t.shared("ItemCatalog")
	local PlanerLogic = t.shared("PlanerLogic")
	local Automation = t.shared("AutomationLogic")
	local ChopSawLogic = t.shared("ChopSawLogic")
	local Config = t.shared("GameConfig")
	local PlotData = t.shared("PlotData")
	local Models = t.shared("BlueprintModels")
	local LogicItems = t.shared("LogicItems")

	-- The ids as pasted in jobs/15-K-wirein-machine-meshes.md and the TLD-1 addendum
	-- (section E; those replace the first uploads of the same names).
	local IDS = {
		BeltDrop = {
			Body = 89409509121237,
			Belt = 112639701527136,
			ArrowDecal = 91366713649077,
			Rollers = 86020839494315,
		},
		BeltSupport = { Body = 135923007231029 },
		Button = { Body = 100690134624125, Cap = 96005605350652 },
		ChopSaw = {
			Body = 82676669720780,
			Belt = 139694883139382,
			ArrowDecal = 111005337162220,
			Rollers = 139928656274744,
			SawBlade = 138618194266659,
		},
		Clock = { Body = 82339447914092, Lamp = 120603346606193 },
		ConveyorFunnel = {
			Body = 116590874132562,
			Belt = 92661088659948,
			ArrowDecal = 113894795100118,
			Rollers = 102496882690265,
		},
		ConveyorLong = {
			Body = 73545583088683,
			Belt = 122001219822338,
			ArrowDecal = 90697262252511,
			Rollers = 93317397092855,
		},
		ConveyorReversible = {
			Body = 134980836676411,
			Belt = 115448717961056,
			ArrowDecal = 122822891842924,
			Rollers = 123259738546019,
			Lever = 103684402243704,
		},
		ConveyorShort = {
			Body = 103732749952811,
			Belt = 72953111751969,
			ArrowDecal = 90697262252511,
			Rollers = 91466161753932,
		},
		ConveyorStraight = {
			Body = 121102816278486,
			Belt = 115448717961056,
			ArrowDecal = 90697262252511,
			Rollers = 123259738546019,
		},
		ConveyorTurn = {
			Body = 117039337469037,
			Belt = 113546975286857,
			ArrowDecal = 138942464537519,
			Rollers = 133528114022350,
		},
		CraftBench = { Body = 87960541936824, Vise = 126020693020676 },
		Delay = { Body = 139422150822446, Lamp = 84002178124720 },
		GateAnd = { Body = 72286730685700, Lamp = 105665496849508 },
		GateNot = { Body = 113453812028789, Lamp = 105665496849508 },
		GateOr = { Body = 137720818161182, Lamp = 105665496849508 },
		GateXor = { Body = 115955909858686, Lamp = 105665496849508 },
		Hatch = { Body = 128997736032155, Leaf = 128713390516912 },
		LaserEmitter = { Body = 106615415699429 },
		LaserReceiver = { Body = 135048878861651 },
		Lever = { Body = 109761930546365, Handle = 120019028738936 },
		Millmaster100 = {
			Body = 93421084152103,
			Belt = 122001219822338,
			ArrowDecal = 97534746945740,
			Rollers = 93317397092855,
			SawBlade = 73060656632976,
		},
		Millmaster200 = {
			Body = 106669780577580,
			Belt = 105997146156742,
			ArrowDecal = 110256564557891,
			Rollers = 89434911284365,
			SawBlade = 115802333263725,
		},
		Millmaster200L = {
			Body = 123176708762563,
			Belt = 134657591217029,
			ArrowDecal = 138487741009210,
			Rollers = 110422189957775,
			SawBlade = 115802333263725,
			Glow = 114169088509905,
		},
		OreChute = { Body = 91355579985009, Flap = 88488176788503 },
		PlanerBench = {
			Body = 99523857231670,
			Belt = 84630483083532,
			ArrowDecal = 106971447046383,
			Rollers = 118736500953369,
			CutterHead = 110350458529864,
		},
		PlanerHand = {
			Body = 139485036599751,
			Belt = 115448717961056,
			ArrowDecal = 113894795100118,
			Rollers = 84416832568991,
			CutterHead = 85226167018473,
		},
		PlanerIndustrial = {
			Body = 140368307046506,
			Belt = 122001219822338,
			ArrowDecal = 117725368152383,
			Rollers = 127677393146989,
			CutterHead = 99962089066042,
			Glow = 131460205123643,
		},
		PlanerSteam = {
			Body = 95941118078808,
			Belt = 79470088816517,
			ArrowDecal = 83223296721881,
			Rollers = 108851068260356,
			CutterHead = 99962089066042,
		},
		PressurePlate = { Body = 79598607884838, Plate = 132100885502137 },
		Prospector = { Body = 76460785351208 },
		SawmillRickety = {
			Body = 82316315960701,
			Belt = 79470088816517,
			ArrowDecal = 71616383391365,
			Rollers = 100124805556860,
			SawBlade = 105278917546675,
		},
		SawmillSturdy = {
			Body = 115352495869068,
			Belt = 139811009092137,
			ArrowDecal = 112648169356270,
			Rollers = 135820135088645,
			SawBlade = 75946719790138,
		},
		SmeltingFurnace = {
			Body = 124635139968707,
			Belt = 121687094617487,
			ArrowDecal = 106971447046383,
			Rollers = 111156364093830,
			FurnaceDoor = 79585722300617,
		},
		SparkLamp = { Body = 126493171652000, Lamp = 134332595127508 },
		SparkSwitch = { Body = 97549717154510, Toggle = 79992582768558 },
		Sustain = { Body = 96783433225204, Lamp = 84002178124720 },
		SwitchBelt = {
			Body = 134774202798715,
			Belt = 89756778448978,
			ArrowDecal = 115037553348084,
			Rollers = 136667181767213,
			Gate = 113470506420777,
		},
		TiltedBelt = {
			Body = 109275806413936,
			Belt = 98887369971807,
			ArrowDecal = 126887593045235,
			Rollers = 90906606656930,
		},
		WoodDetector = {
			Body = 115084242039300,
			Belt = 72953111751969,
			Rollers = 91466161753932,
			Lamp = 81734615468033,
		},
		WoodSweeper = { Body = 77144912159181, Arm = 85325867332742 },
	}

	-- Every machine with a part builder, and how to build it. The four TLD-1 pieces the
	-- catalog does not sell yet (BeltDrop, ConveyorShort, ConveyorLong, ConveyorReversible)
	-- have data and templates but no builder.
	local BUILD = {}
	for _, mill in ipairs(Catalog.SawmillList()) do
		BUILD[mill.id] = function(ghost)
			return MachineArt.Build(mill.id, ghost)
		end
	end
	for _, machine in ipairs(PlanerLogic.List()) do
		BUILD[machine.id] = function(ghost)
			return MachineArt.BuildPlaner(machine.id, ghost)
		end
	end
	BUILD.ChopSaw = function(ghost)
		return MachineArt.BuildChopSaw(ghost)
	end
	for _, id in ipairs({
		"ConveyorStraight",
		"ConveyorTurn",
		"ConveyorFunnel",
		"SwitchBelt",
		"TiltedBelt",
		"BeltSupport",
		"WoodDetector",
	}) do
		BUILD[id] = function(ghost)
			return MachineArt.BuildBelt(id, ghost)
		end
	end
	BUILD.SmeltingFurnace = function()
		return MiningArt.SmeltingFurnace()
	end
	BUILD.Prospector = function()
		return MiningArt.Prospector()
	end
	BUILD.OreChute = BUILD.Prospector
	BUILD.CraftBench = function()
		return MiningArt.CraftBench()
	end
	local LOGIC = {
		"Button",
		"Lever",
		"PressurePlate",
		"SparkSwitch",
		"SparkLamp",
		"Hatch",
		"GateAnd",
		"GateOr",
		"GateXor",
		"GateNot",
		"Delay",
		"Clock",
		"Sustain",
		"WoodSweeper",
		"LaserEmitter",
		"LaserReceiver",
	}
	for _, id in ipairs(LOGIC) do
		BUILD[id] = function(ghost)
			return Models.Build(PlotData.Blueprint(id), ghost == true)
		end
	end

	local function withMeshes(fn)
		MeshKit.Reset()
		MachineSkin.Reset()
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		MeshKit.Reset()
		MachineSkin.Reset()
		if not ok then
			error(err, 0)
		end
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

	local function meshParts(model)
		local out = {}
		for _, p in ipairs(parts(model)) do
			if p:GetAttribute("VisualMesh") == true then
				table.insert(out, p)
			end
		end
		return out
	end

	local function find(model, name)
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end

	local function near(a, b, eps, label)
		t.ok(math.abs(a - b) <= (eps or 0.001), (label or "") .. ": " .. tostring(a) .. " vs " .. tostring(b))
	end

	t.test("every machine has every piece with its uploaded meshId, and every id has a template", function()
		local count = 0
		for name, pieces in pairs(IDS) do
			local asset = MachineMeshes.Get(name)
			t.ok(asset ~= nil, name .. " has an entry")
			local seen = 0
			for _, piece in ipairs(asset.pieces) do
				seen += 1
				t.ok(piece.meshId ~= 0, name .. "." .. piece.name .. " is not left at 0")
				t.eq(piece.meshId, pieces[piece.name], name .. "." .. piece.name)
				t.ok(piece.size.X > 0 and piece.size.Y > 0 and piece.size.Z > 0, name .. "." .. piece.name .. " size")
				local path = "src/ReplicatedStorage/MeshTemplates/" .. tostring(piece.meshId) .. ".model.json"
				t.ok(fs.isFile(path), "template for " .. tostring(piece.meshId))
				local body = fs.readFile(path)
				t.ok(string.find(body, '"MeshId": "rbxassetid://' .. tostring(piece.meshId) .. '"', 1, true), path)
				t.ok(string.find(body, '"className": "MeshPart"', 1, true), path)
			end
			local expected = 0
			for _ in pairs(pieces) do
				expected += 1
			end
			t.eq(seen, expected, name .. " has all its pieces")
			count += 1
		end
		t.eq(count, 41, "25 TLD-1 assets and the 16 older pieces")
		t.eq(#MachineMeshes.Ids(), 41)
		-- The old and new uploads of the same name are not both used: a TLD-1 name keeps one set.
		t.eq(MachineMeshes.Get("SawmillRickety").source, "tld1")
		t.eq(MachineMeshes.Get("Lever").source, "job15")
		-- The Open Cloud model container is never a MeshId.
		for _, id in ipairs(MachineMeshes.Ids()) do
			local asset = MachineMeshes.Get(id)
			for _, piece in ipairs(asset.pieces) do
				t.ok(piece.meshId ~= asset.modelAssetId, id .. " uses its model container as a mesh")
			end
		end
	end)

	t.test("the MeshManifest preloads every machine mesh once and keeps the blender group", function()
		local groups = MeshManifest.Groups(false)
		local names = {}
		local machines
		for _, group in ipairs(groups) do
			table.insert(names, group.name)
			if group.name == "machines" then
				machines = group
			end
		end
		t.ok(machines ~= nil, "a machines group")
		t.eq(names[#names], "machines", "added after the blender group")
		t.ok(table.find(names, "blender") ~= nil, "job 14's blender group is kept")
		local seen = {}
		for _, entry in ipairs(machines.entries) do
			t.eq(seen[entry.id], nil, "each id once")
			seen[entry.id] = true
		end
		for _, id in ipairs(MachineMeshes.MeshIds()) do
			local inEarlier = false
			for _, group in ipairs(groups) do
				if group.name ~= "machines" then
					for _, entry in ipairs(group.entries) do
						if entry.id == id then
							inEarlier = true
						end
					end
				end
			end
			t.ok(seen[id] or inEarlier, tostring(id) .. " is preloaded")
		end
	end)

	t.test("TLD-1 line standard: deck top 0.72, plate 6.0, channel 5.0, rollers at 1.0 pitch", function()
		local S = MachineMeshes.Standard
		t.eq(S.DeckTop, 0.72)
		t.eq(S.PlateWidth, 6.0)
		t.eq(S.Channel, 5.0)
		t.eq(S.RollerPitch, 1.0)
		t.eq(S.RollerFirst, 0.5)
		t.eq(S.RollerAxleY, 0.5)
		t.eq(S.RailTop, 1.32)
		t.eq(S.Lift, 2.0)
		t.eq(Automation.DeckTop, S.DeckTop)
		t.eq(Automation.PlateWidth, S.PlateWidth)
		t.eq(Automation.Channel, S.Channel)
		t.eq(Automation.RollerPitch, S.RollerPitch)
		t.eq(Automation.Lift, S.Lift)
		t.eq(ChopSawLogic.TableTop, S.DeckTop, "the chop saw's deck is the line's deck")
		t.eq(ChopSawLogic.TableWidth, S.Channel)
		-- A straight belt, part-built: the plate is 6.0, the Conveyor band 5.0 with its top at 0.72,
		-- rails at x +-2.7 up to 1.32, and rollers every 1.0 with the first 0.5 from each port face.
		local model = MachineArt.BuildBelt("ConveyorStraight", false)
		local depth = Catalog.GetMachine("ConveyorStraight").belt.depth
		local plate = find(model, "Plate")
		near(plate.Size.X, 6.0, 1e-4, "plate width")
		local band = find(model, "Conveyor")
		near(band.Size.X, 5.0, 1e-4, "channel")
		near(band.CFrame.Position.Y + band.Size.Y / 2, 0.72, 1e-4, "deck top")
		near(band.Size.Z, depth, 1e-4, "flush to both port faces")
		local rails = 0
		for _, p in ipairs(parts(model)) do
			if p.Name == "GuardRail" then
				rails += 1
				near(math.abs(p.CFrame.Position.X), 2.7, 1e-4, "rail x")
				near(p.CFrame.Position.Y + p.Size.Y / 2, 1.32, 1e-4, "rail top")
			end
		end
		t.eq(rails, 2)
		local zs = {}
		for _, p in ipairs(parts(model)) do
			if p.Name == "Roller" then
				near(p.CFrame.Position.Y, 0.5, 1e-4, "axle height")
				table.insert(zs, p.CFrame.Position.Z)
			end
		end
		table.sort(zs)
		t.eq(#zs, depth, "one roller a stud")
		near(zs[1], -depth / 2 + 0.5, 1e-4, "first roller 0.5 from the port face")
		near(zs[#zs], depth / 2 - 0.5, 1e-4, "last roller 0.5 from the port face")
		for i = 2, #zs do
			near(zs[i] - zs[i - 1], 1.0, 1e-4, "pitch")
		end
		-- Two straights end to end make one deck: the pitch is 1.0 across the joint too.
		near(zs[1] + depth - zs[#zs], 1.0, 1e-4, "pitch across a joint")
		-- Every TLD-1 mill's Belt (the pan) is the 5.0 channel, and its Rollers are 5.9 wide and the
		-- deck's length less 0.593 (rollers 0.5 from each port face plus their caps).
		for _, id in ipairs({ "SawmillRickety", "SawmillSturdy", "Millmaster100", "Millmaster200", "Millmaster200L" }) do
			local layout = MachineMeshes.Layout(id)
			local belt = MachineMeshes.Piece(id, "Belt")
			local rollers = MachineMeshes.Piece(id, "Rollers")
			near(belt.size.X, 5.0, 1e-6, id .. " pan width")
			near(belt.size.Z, layout.footprint.Y, 1e-6, id .. " pan runs port face to port face")
			near(rollers.size.X, 5.9, 1e-6, id .. " rollers width")
			near(rollers.size.Z, layout.footprint.Y - 0.593, 1e-6, id .. " rollers")
			near(belt.offset.Y, 0.33, 1e-6, id .. " pan height")
			near(rollers.offset.Y, 0.5, 1e-6, id .. " axle height")
		end
	end)

	t.test("TLD-1 footprints: mills and planers run along the feed, the straight is 6 wide", function()
		local want = {
			SawmillRickety = { 8, 12 },
			SawmillSturdy = { 8, 14 },
			Millmaster100 = { 10, 16 },
			Millmaster200 = { 10, 18 },
			Millmaster200L = { 10, 26 },
		}
		for id, wh in pairs(want) do
			local mill = Catalog.GetSawmill(id)
			t.eq({ mill.width, mill.depth }, wh, id)
			local layout = MachineMeshes.Layout(id)
			t.eq({ layout.footprint.X, layout.footprint.Y }, wh, id .. " layout")
		end
		local planers =
			{ PlanerHand = { 8, 8 }, PlanerBench = { 8, 10 }, PlanerSteam = { 8, 12 }, PlanerIndustrial = { 8, 16 } }
		for id, wh in pairs(planers) do
			local _, def = PlanerLogic.Get(id)
			t.eq({ def.width, def.depth }, wh, id)
			local layout = MachineMeshes.Layout(id)
			t.eq({ layout.footprint.X, layout.footprint.Y }, wh, id .. " layout")
		end
		t.eq(Catalog.GetMachine("ConveyorStraight").belt.width, 6)
		t.eq(Catalog.GetMachine("SwitchBelt").belt.width, 12)
		t.eq(Catalog.GetMachine("TiltedBelt").belt.width, 6)
		t.eq(Catalog.GetMachine("BeltSupport").belt.width, 6)
		t.eq(Catalog.GetMachine("BeltSupport").belt.depth, 2)
		-- The chop saw: 6 x 56 (52 stud bed on the 2-stud grid plus the 4 stud head).
		local fp = ChopSawLogic.Footprint()
		t.eq({ fp.X, fp.Y }, { 6, 56 })
		t.eq(ChopSawLogic.TableLength(), 52)
		local layout = MachineMeshes.Layout("ChopSaw")
		t.eq({ layout.footprint.X, layout.footprint.Y }, { 6, 56 })
		-- Port faces sit on the footprint ends: the pan is the whole length.
		for _, id in ipairs({ "PlanerHand", "PlanerBench", "PlanerSteam", "PlanerIndustrial", "ChopSaw" }) do
			local planLayout = MachineMeshes.Layout(id)
			near(MachineMeshes.Piece(id, "Belt").size.Z, planLayout.footprint.Y, 1e-6, id .. " pan")
		end
	end)

	t.test("moving parts and named points: arbor, cutter, hinges, ports", function()
		for _, id in ipairs({ "SawmillRickety", "SawmillSturdy", "Millmaster100", "Millmaster200", "Millmaster200L" }) do
			local arbor = MachineMeshes.Point(id, "arbor")
			local blade = MachineMeshes.Piece(id, "SawBlade")
			t.eq(arbor.X, 0)
			near(arbor.Z, 0.35, 1e-6, id .. " arbor z")
			near(arbor.Y, 0.72 + blade.size.X / 2, 0.05, id .. " arbor y is the deck top plus the blade's radius")
			t.eq(blade.offset, arbor, id .. " the blade turns about its arbor")
			t.ok(blade.size.Z < blade.size.X / 4, id .. " a disc whose axle is Z")
		end
		for _, id in ipairs({ "PlanerHand", "PlanerBench", "PlanerSteam", "PlanerIndustrial" }) do
			local cutter = MachineMeshes.Point(id, "cutter")
			local head = MachineMeshes.Piece(id, "CutterHead")
			t.eq(head.offset, Vector3.new(0, cutter.Y, 0), id .. " the drum turns about the cutter line")
			t.ok(head.size.X > head.size.Y, id .. " the drum's axle is X")
		end
		t.eq(MachineMeshes.Piece("ChopSaw", "SawBlade").offset, Vector3.new(0, 2.0, 24))
		t.eq(MachineMeshes.Point("SwitchBelt", "GateHinge"), Vector3.new(0, 0.72, 3.35))
		t.eq(MachineMeshes.Point("SmeltingFurnace", "DoorHinge"), Vector3.new(-0.85, 2.1, -1.72))
		t.eq(MachineMeshes.Point("SmeltingFurnace", "SmeltIntake"), Vector3.new(0, 1.5, -3.65))
		t.eq(MachineMeshes.Point("SmeltingFurnace", "OutputTray"), Vector3.new(0, 1.3, 3.9))
		t.eq(MachineMeshes.Point("LaserEmitter", "BeamPort"), Vector3.new(0, 1.92, 0.72))
		t.eq(MachineMeshes.Point("LaserReceiver", "BeamPort"), Vector3.new(0, 1.92, -0.64))
		near(MachineMeshes.Piece("WoodSweeper", "Arm").offset.Y, 1.82, 1e-6)
		t.eq(MachineMeshes.Pose("Lever").hinge, Vector3.new(0, 2.15, 0.2))
		t.eq(MachineMeshes.Pose("SparkSwitch").hinge, Vector3.new(0, 3.15, 0.18))
		t.eq(MachineMeshes.Pose("Hatch").hinge, Vector3.new(0, 0.22, 1.45))
	end)

	t.test("each piece lands at the mesh origin times its offset (within 0.001)", function()
		withMeshes(function()
			local built = 0
			for _, id in ipairs(MachineMeshes.Ids()) do
				local make = BUILD[id]
				if make == nil then
					continue
				end
				local model = make(false)
				t.ok(model ~= nil, id .. " builds")
				built += 1
				local asset = MachineMeshes.Get(id)
				local on = meshParts(model)
				t.ok(#on >= #asset.pieces, id .. " wears its meshes")
				for _, piece in ipairs(asset.pieces) do
					local found
					for _, p in ipairs(on) do
						if p:GetAttribute("MeshId") == tostring(piece.meshId) then
							found = p
						end
					end
					t.ok(found ~= nil, id .. "." .. piece.name .. " is on the model")
					if found then
						-- The Prospector's chute stands at (4.2, 0, 0) on the stall.
						local origin = if id == "OreChute" then Vector3.new(4.2, 0, 0) else Vector3.zero
						-- A logic piece's moving part starts in its "off" pose (lever back, hatch shut).
						local pose = MachineMeshes.Pose(id)
						local moved = pose ~= nil and pose.piece == piece.name
						if not moved then
							local at = found.CFrame.Position
							near(at.X, origin.X + piece.offset.X, 0.001, id .. "." .. piece.name .. " x")
							near(at.Y, origin.Y + piece.offset.Y, 0.001, id .. "." .. piece.name .. " y")
							near(at.Z, origin.Z + piece.offset.Z, 0.001, id .. "." .. piece.name .. " z")
							near(found.Size.X, piece.size.X, 0.001, id .. "." .. piece.name .. " size")
							near(found.Size.Y, piece.size.Y, 0.001, id .. "." .. piece.name .. " size")
							near(found.Size.Z, piece.size.Z, 0.001, id .. "." .. piece.name .. " size")
						end
					end
				end
			end
			t.ok(built >= 37, "every machine that has a builder was checked: " .. built)
		end)
	end)

	t.test("a mesh piece is looks only; the see-through shell still collides", function()
		withMeshes(function()
			for _, id in ipairs(MachineMeshes.Ids()) do
				local make = BUILD[id]
				if make == nil then
					continue
				end
				local model = make(false)
				for _, p in ipairs(meshParts(model)) do
					t.eq(p.CanCollide, false, id .. " " .. p.Name)
					t.eq(p.CanQuery, false, id .. " " .. p.Name)
					t.eq(p.CanTouch, false, id .. " " .. p.Name)
					t.eq(p.Anchored, true, id .. " " .. p.Name)
				end
			end
			for _, name in ipairs({ "SawmillRickety", "Millmaster200L" }) do
				local model = MachineArt.Build(name, false)
				for _, d in ipairs(parts(model)) do
					if d.Name == "Wall" or d.Name == "GuardRail" or d.Name == "Roof" then
						t.eq(d.Transparency, 1, name .. " " .. d.Name .. " is see-through under the mesh")
						t.eq(d.CanCollide, true, name .. " " .. d.Name .. " still collides")
					end
				end
			end
		end)
	end)

	t.test("with an id forced to 0 the part build is unchanged", function()
		local function signature(model)
			local rows = {}
			for _, p in ipairs(parts(model)) do
				table.insert(
					rows,
					string.format(
						"%s|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%s|%s|%s|%.2f",
						p.Name,
						p.Size.X,
						p.Size.Y,
						p.Size.Z,
						p.CFrame.Position.X,
						p.CFrame.Position.Y,
						p.CFrame.Position.Z,
						p.CollisionGroup,
						tostring(p.CanCollide),
						tostring(p.Anchored),
						p.Transparency
					)
				)
			end
			table.sort(rows)
			return rows
		end
		for _, id in ipairs(MachineMeshes.Ids()) do
			local make = BUILD[id]
			if make == nil then
				continue
			end
			local plain = signature(make(false))
			withMeshes(function()
				-- One piece at 0 (the last): the whole machine keeps its parts, nothing half-dressed.
				local asset = MachineMeshes.Get(id)
				local last = asset.pieces[#asset.pieces]
				-- The stall and its chute are one model: both go to 0 together.
				local twin = if id == "Prospector" then "OreChute" elseif id == "OreChute" then "Prospector" else nil
				if twin then
					MachineMeshes.ForcedZero[twin] = true
				end
				MachineMeshes.ForcedZero[id .. "." .. last.name] = true
				local forced = make(false)
				MachineMeshes.ForcedZero[id .. "." .. last.name] = nil
				t.eq(#meshParts(forced), 0, id .. " wears no mesh when one piece is missing")
				t.eq(signature(forced), plain, id .. " part build unchanged")
				MachineMeshes.ForcedZero[id] = true
				local zero = make(false)
				MachineMeshes.ForcedZero[id] = nil
				if twin then
					MachineMeshes.ForcedZero[twin] = nil
				end
				t.eq(signature(zero), plain, id .. " whole machine at 0")
			end)
		end
	end)

	t.test("a missing template is logged once per machine and never boxes a MISSING MESH in", function()
		MeshKit.Reset()
		MachineSkin.Reset()
		MeshKit.Override = function()
			return nil
		end
		local ok, err = pcall(function()
			for _ = 1, 3 do
				local model = MachineArt.Build("SawmillRickety", false)
				t.eq(#meshParts(model), 0)
				for _, d in ipairs(model:GetDescendants()) do
					t.ok(not string.find(d.Name, "MISSING", 1, true), "no stand-in box")
				end
			end
		end)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
		t.eq(MachineSkin.Logged("SawmillRickety"), true)
		t.eq(MachineSkin.Misses(), 1, "one line, however many builds")
		MachineSkin.Reset()
	end)

	t.test("gameplay parts keep their name, size, CFrame and collision group under the meshes", function()
		local KEEP = {
			"Root",
			"Conveyor",
			"FeedGuard",
			"BladeGuard",
			"Intake",
			"Panel",
			"Blockage",
			"SmeltIntake",
			"FireMouth",
			"OreChute",
			"Infeed",
			"Base",
			"Eye",
			"Wall",
			"Roof",
			"GuardRail",
		}
		-- (The furnace's gable wedges are looks only and are not built under the mesh.)
		local function gameplay(model)
			local rows = {}
			for _, p in ipairs(parts(model)) do
				if
					table.find(KEEP, p.Name)
					and p:GetAttribute("VisualMesh") ~= true
					and not (p.Name == "Roof" and not p.CanCollide)
				then
					table.insert(
						rows,
						string.format(
							"%s|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%s|%s",
							p.Name,
							p.Size.X,
							p.Size.Y,
							p.Size.Z,
							p.CFrame.Position.X,
							p.CFrame.Position.Y,
							p.CFrame.Position.Z,
							p.CollisionGroup,
							tostring(p.CanCollide)
						)
					)
				end
			end
			table.sort(rows)
			return rows
		end
		for _, id in ipairs(MachineMeshes.Ids()) do
			local make = BUILD[id]
			if make == nil or MachineMeshes.Get(id).family == "logic" then
				continue
			end
			local plain = gameplay(make(false))
			withMeshes(function()
				t.eq(gameplay(make(false)), plain, id)
			end)
		end
		-- The Output attachment still points out the +Z end, and the mill belt still carries wood +Z.
		withMeshes(function()
			local model = MachineArt.Build("Millmaster100", false)
			local output = find(model, "Output")
			t.ok(output.CFrame.LookVector.Z > 0.99, "Output looks along +Z, the mesh's outfeed")
			near((output.Parent.CFrame * output.CFrame).Position.Z, 6.6, 1e-3, "on the outfeed rollers")
			MachineArt.AimBelt(model)
			local belt = find(model, "Conveyor")
			near(belt.AssemblyLinearVelocity.Z, Config.ConveyorSpeed, 1e-3)
			t.eq(belt.CollisionGroup, "MillBelt")
		end)
	end)

	t.test("the furnace's FireMouth is unchanged and the only glow", function()
		withMeshes(function()
			local model = MiningArt.SmeltingFurnace()
			local mouth = find(model, "FireMouth")
			near(mouth.Size.X, 1.6, 1e-4)
			near(mouth.Size.Y, 1.1, 1e-4)
			near(mouth.Size.Z, 0.2, 1e-4)
			near((mouth.CFrame.Position - Vector3.new(0, 2.1, -1.65)).Magnitude, 0, 1e-4)
			t.eq(mouth.Material, Enum.Material.Neon)
			t.eq(mouth.Color, roblox.Color3.fromHex("#FF6A1E"))
			local glows, lights = 0, 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
					glows += 1
				end
				if d:IsA("PointLight") then
					lights += 1
					t.eq(d.Shadows, false)
				end
			end
			t.eq(glows, 1, "no mesh glow")
			t.eq(lights, 1)
			t.ok(MiningArt.PartCount(model) <= MiningArt.MaxFurnaceParts)
			-- The mesh's recess is 1.7 x 1.2, a hair larger than the 1.6 x 1.1 mouth.
			t.ok(1.7 > mouth.Size.X and 1.2 > mouth.Size.Y)
			t.eq(MiningArt.SetFurnaceDoor(model, true), true)
			t.eq(MiningArt.SetFurnaceDoor(model, false), true)
		end)
	end)

	t.test("part budgets hold with the meshes on and off, and TierSign stays a part", function()
		local function count(model)
			return #parts(model)
		end
		for _, mill in ipairs(Catalog.SawmillList()) do
			local off = count(MachineArt.Build(mill.id, false))
			t.ok(off <= MachineArt.Budget(mill.tier), mill.id .. " meshes off: " .. off)
			withMeshes(function()
				local model = MachineArt.Build(mill.id, false)
				local on = count(model)
				t.ok(on <= MachineArt.Budget(mill.tier), mill.id .. " meshes on: " .. on)
				local sign = find(model, "TierSign")
				t.ok(
					sign ~= nil and sign:IsA("BasePart") and sign:GetAttribute("VisualMesh") ~= true,
					"TierSign is a part"
				)
				for _, name in ipairs({ "Post", "Stack", "Boiler", "Gantry", "MakerPlate", "Lamp", "Gauge" }) do
					t.eq(find(model, name), nil, mill.id .. " skips the decor " .. name)
				end
			end)
		end
		for _, machine in ipairs(PlanerLogic.List()) do
			local off = count(MachineArt.BuildPlaner(machine.id, false))
			t.ok(off <= MachineArt.Budget(machine.planer.tier), machine.id .. " meshes off: " .. off)
			withMeshes(function()
				local model = MachineArt.BuildPlaner(machine.id, false)
				t.ok(count(model) <= MachineArt.Budget(machine.planer.tier), machine.id .. " meshes on")
				t.ok(find(model, "TierSign") ~= nil)
			end)
		end
		withMeshes(function()
			t.ok(count(MiningArt.SmeltingFurnace()) <= MiningArt.MaxFurnaceParts)
		end)
	end)

	t.test("belts: the same bands carry wood at the same speed in the same group with or without the meshes", function()
		local function bands(model)
			local out = {}
			for _, p in ipairs(parts(model)) do
				if p.Name == "Conveyor" then
					table.insert(
						out,
						string.format(
							"%s|%.2f|%.2f,%.2f,%.2f",
							p.CollisionGroup,
							p.AssemblyLinearVelocity.Magnitude,
							p.Size.X,
							p.Size.Y,
							p.Size.Z
						)
					)
				end
			end
			table.sort(out)
			return out
		end
		for _, id in ipairs({
			"ConveyorStraight",
			"ConveyorTurn",
			"ConveyorFunnel",
			"TiltedBelt",
			"SwitchBelt",
			"WoodDetector",
		}) do
			local plain = bands(MachineArt.BuildBelt(id, false))
			t.ok(#plain >= 1, id)
			withMeshes(function()
				local model = MachineArt.BuildBelt(id, false)
				t.ok(#meshParts(model) >= 4, id .. " is meshed")
				t.eq(bands(model), plain, id)
				for _, row in ipairs(bands(model)) do
					t.ok(string.find(row, "MillBelt|4.00", 1, true) ~= nil, id .. " " .. row)
				end
			end)
		end
	end)

	t.test("the Switch Belt's mesh gate throws toward the side it is set to, about its hinge", function()
		withMeshes(function()
			local model = MachineArt.BuildBelt("SwitchBelt", false)
			local gate = find(model, "Gate")
			t.eq(gate:GetAttribute("VisualMesh"), true)
			local hinge = Vector3.new(0, 0.72, 3.35)
			local right = gate.CFrame.Position
			MachineArt.SetSwitchSide(model, -1)
			local left = gate.CFrame.Position
			t.eq(model:GetAttribute("GateSide"), -1)
			-- Turned a quarter about the hinge: the same distance from it, a different place.
			near((right - hinge).Magnitude, (left - hinge).Magnitude, 1e-6, "radius about the hinge")
			t.ok((right - left).Magnitude > 1, "the paddle moved")
			MachineArt.SetSwitchSide(model, 1)
			near((gate.CFrame.Position - right).Magnitude, 0, 1e-6, "back where it was")
		end)
	end)

	t.test("a ghost wears the meshes at 0.45 and nothing collides", function()
		withMeshes(function()
			for _, id in ipairs({ "SawmillRickety", "PlanerHand", "ChopSaw", "ConveyorStraight", "Lever", "GateAnd" }) do
				local model = BUILD[id](true)
				local worn = meshParts(model)
				t.ok(#worn >= 2, id)
				for _, p in ipairs(worn) do
					near(p.Transparency, 0.45, 1e-6, id .. " " .. p.Name)
					t.eq(p.CanCollide, false)
				end
				for _, p in ipairs(parts(model)) do
					t.eq(p.CanCollide, false, id .. " " .. p.Name)
				end
			end
		end)
	end)

	t.test("logic pieces: the meshes fill the Body, Indicator and Moving slots and start in their off pose", function()
		withMeshes(function()
			for _, id in ipairs(LOGIC) do
				if id == "LaserEmitter" or id == "LaserReceiver" then
					continue
				end
				local model = BUILD[id](false)
				t.eq(model:GetAttribute("MeshAsset"), id)
				t.ok(model:FindFirstChild("Body"), id .. " Body")
				local asset = MachineMeshes.Get(id)
				local wantLamp, wantMoving = false, false
				for _, piece in ipairs(asset.pieces) do
					if piece.name == "Lamp" then
						wantLamp = true
					elseif piece.name ~= "Body" then
						wantMoving = true
					end
				end
				t.eq(model:FindFirstChild("Indicator") ~= nil, wantLamp, id .. " Indicator")
				t.eq(model:FindFirstChild("Moving") ~= nil, wantMoving, id .. " Moving")
				-- The gate symbol is raised geometry on the mesh, not a SurfaceGui label.
				if LogicItems.Mark[id] then
					t.eq(find(model, "Mark"), nil, id .. " has no label gui")
				end
				-- The boxes stay as colliders, see-through.
				local part1 = model:FindFirstChild("Part1")
				t.ok(part1 ~= nil and part1.Transparency == 1, id .. " collider")
			end
			-- A hinged piece carries its pose; swinging it moves it about the hinge.
			local lever = BUILD.Lever(false)
			local handle = lever:FindFirstChild("Moving")
			t.ok(MachineSkin.Hinged(handle))
			local off = handle.CFrame
			MachineSkin.PoseAbout(lever, handle, true)
			t.ok((handle.CFrame.Position - off.Position).Magnitude > 0.1, "tipped on")
			-- On is the modelled pose.
			near(handle.CFrame.Position.Y, MachineMeshes.Piece("Lever", "Handle").offset.Y, 1e-3)
		end)
	end)

	t.test("no machine code binds ButtonR2 and no machine code uses InsertService", function()
		for _, path in ipairs({
			"src/ReplicatedStorage/Shared/Art/MachineMeshes.luau",
			"src/ReplicatedStorage/Shared/Art/MachineSkin.luau",
			"src/ReplicatedStorage/Shared/Art/MachineArt.luau",
			"src/ReplicatedStorage/Shared/Mining/MiningArt.luau",
			"src/ReplicatedStorage/Shared/LogicItems.luau",
		}) do
			local body = fs.readFile(path)
			t.eq(string.find(body, "ButtonR2", 1, true), nil, path)
			t.eq(string.find(body, "InsertService", 1, true), nil, path)
		end
	end)
end
