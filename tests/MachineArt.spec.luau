--!nocheck
-- The placed sawmill: intake, outfeed, the cut panel, and a see-through ghost.
return function(t)
	local loader = t.loader()
	local MachineArt = loader:load("ReplicatedStorage/Shared/Art/MachineArt")
	local Catalog = loader:shared("ItemCatalog")

	local function find(model, name, class)
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == name and (not class or d:IsA(class)) then
				return d
			end
		end
		return nil
	end

	local function parts(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		return n
	end

	t.test("a mill has an intake, an outfeed and a panel of cut buttons", function()
		local model = MachineArt.Build("SawmillRickety", false)
		t.eq(model.PrimaryPart, find(model, "Root", "BasePart"))
		t.eq(model:GetAttribute("MillId"), "SawmillRickety")
		local intake = find(model, "Intake", "BasePart")
		t.ok(intake and intake.Transparency == 1 and not intake.CanCollide, "the intake is a sensor")
		local output = find(model, "Output", "Attachment")
		t.ok(output, "an Output attachment")
		t.ok(output.CFrame.LookVector.Z > 0.9, "planks leave toward +Z")
		local panel = find(model, "Panel", "BasePart")
		t.ok(panel.CFrame.LookVector.X > 0.9, "the panel faces out the side")
		t.ok(panel.Size.X > panel.Size.Z and panel.Size.Y > panel.Size.Z, "the front face is the big one")
		local axes = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("TextButton") then
				axes[d.Name] = { d:GetAttribute("Axis"), d:GetAttribute("Dir") }
			end
		end
		t.eq(axes, {
			XMinus = { "x", -1 },
			XPlus = { "x", 1 },
			YMinus = { "y", -1 },
			YPlus = { "y", 1 },
		})
		MachineArt.SetCut(model, 1.2, 0.8, "up to 1.8 × 1.2 u, steps of 0.2")
		t.eq(find(model, "CutReadout", "TextLabel").Text, "1.20 × 0.80 u")
		t.eq(
			find(model, "LimitReadout", "TextLabel").Text,
			"up to 1.8 × 1.2 u, steps of 0.2",
			"the limit sits under the size"
		)
		t.ok(model:HasTag("Sawmill"), "the mill is tagged")
		local blade = find(model, "SawBlade")
		t.ok(blade:HasTag("SawBlade"), "the blade spins with the town's")
		t.ok(not blade.CanCollide and not blade.CanTouch, "the blade is looks only")
		local belt = find(model, "Conveyor")
		t.ok(belt.CanCollide and belt.CollisionGroup == "MillBelt", "the belt carries logs")
		t.ok(belt.CFrame.LookVector.Z > 0.9, "the belt runs toward the outfeed")
		t.eq(belt.CanTouch, false)
		MachineArt.AimBelt(model)
		t.ok(math.abs(belt.AssemblyLinearVelocity.Z - 4) < 1e-3, "conveyor speed, out the front")
		local walls, rails, guards = 0, 0, 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "Wall" or d.Name == "GuardRail" or d.Name == "Deck" then
					t.ok(d.CanCollide and d.CollisionGroup == "Default", d.Name .. " stops a log")
					t.eq(d.CanTouch, false)
					if d.Name == "Wall" then
						walls += 1
					elseif d.Name == "GuardRail" then
						rails += 1
					end
				elseif d.Name == "FeedGuard" or d.Name == "BladeGuard" or d.Name == "Roof" then
					t.ok(d.CanCollide and d.CollisionGroup == "Mill", d.Name .. " stops a player")
					t.eq(d.CanTouch, false)
					if d.Name ~= "Roof" then
						t.eq(d.Transparency, 1, d.Name .. " is invisible")
						guards += 1
					end
				end
			end
		end
		t.eq(walls, 2, "a wall each side")
		t.eq(rails, 2, "a rail each side of the belt")
		t.eq(guards, 3, "two end guards and the blade guard")
		t.ok(parts(model) <= MachineArt.Budget(1), "a small model: " .. parts(model))
		for _, mill in ipairs(Catalog.SawmillList()) do
			local built = MachineArt.Build(mill.id, false)
			t.ok(built and find(built, "Intake") and find(built, "Output"), mill.id)
		end
	end)

	t.test("the placement ghost is the same mill with nothing to click", function()
		local ghost = MachineArt.Build("Millmaster200L", true)
		t.eq(find(ghost, "Panel"), nil)
		t.ok(find(ghost, "Intake"), "the intake is still there")
		t.ok(find(ghost, "Output"), "still an outfeed, so the shape matches")
		for _, d in ipairs(ghost:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Root" and d.Name ~= "Intake" then
				t.eq(d.CanCollide, false, d.Name)
			end
			t.ok(not d:IsA("SurfaceGui"), "no buttons on a ghost")
		end
		t.eq(MachineArt.Build("NotAMill", false), nil)
	end)

	t.test(
		"the Sky Bin: BuildingArt's bin on a footprint-sized pivot, tagged for its prompt; a ghost is see-through",
		function()
			local SkyBinLogic = loader:shared("SkyBinLogic")
			local bin = MachineArt.BuildSkyBin(false)
			t.eq(bin.Name, "SkyBin")
			t.eq(bin.PrimaryPart, find(bin, "Root", "BasePart"))
			local fp = SkyBinLogic.Footprint()
			t.eq({ bin.PrimaryPart.Size.X, bin.PrimaryPart.Size.Z }, { fp.X, fp.Y })
			local part = find(bin, "SkyBin", "BasePart")
			t.ok(part and part.CanCollide, "the bin part collides: the prompt goes on it")
			t.ok(bin:HasTag(SkyBinLogic.Tag), "tagged for AetherService and WorldUI")
			t.eq(bin:GetAttribute("MachineId"), "SkyBin")
			local ghost = MachineArt.BuildSkyBin(true)
			t.ok(not ghost:HasTag(SkyBinLogic.Tag), "a ghost is not a bin")
			for _, d in ipairs(ghost:GetDescendants()) do
				if d:IsA("BasePart") then
					t.eq(d.CanCollide, false, d.Name)
				end
			end
		end
	)

	t.test(
		"every sawmill tier looks different: more detail and better materials as it climbs, inside its part budget",
		function()
			local counts, roofs, walls = {}, {}, {}
			for i, mill in ipairs(Catalog.SawmillList()) do
				local built = MachineArt.Build(mill.id, false)
				counts[i] = parts(built)
				t.ok(counts[i] <= MachineArt.Budget(mill.tier), mill.id .. " keeps its budget: " .. counts[i])
				t.eq(built:GetAttribute("Tier"), mill.tier)
				t.eq(built:GetAttribute("TierName"), mill.tierName)
				local sign = find(built, "TierSign", "BasePart")
				t.ok(sign ~= nil, mill.id .. " carries its tier label")
				local label = find(sign, "TextLabel")
				t.eq(label.Text, string.upper(mill.tierName))
				roofs[i] = find(built, "Roof", "BasePart").Material
				walls[i] = find(built, "Wall", "BasePart").Material
				-- Detail never collides: a log slides past the stack and the boiler.
				for _, d in ipairs(built:GetDescendants()) do
					if d.Name == "Post" or d.Name == "Stack" or d.Name == "Boiler" or d.Name == "Gantry" then
						t.eq(d.CanCollide, false, d.Name)
					end
				end
			end
			for i = 2, #counts do
				t.ok(counts[i] > counts[i - 1], "tier " .. i .. " has more detail than tier " .. (i - 1))
			end
			t.ok(roofs[1] ~= roofs[3] and roofs[3] ~= roofs[5] and roofs[1] ~= roofs[5], "the roof material changes")
			t.ok(walls[1] ~= walls[4], "the walls get better")
			t.ok(find(MachineArt.Build("Millmaster200", false), "Boiler"), "the Steam tier has its boiler")
			t.ok(find(MachineArt.Build("Millmaster200L", false), "Gantry"), "the Industrial tier has its gantry")
			t.eq(find(MachineArt.Build("SawmillRickety", false), "Boiler"), nil)
			-- The footprint is unchanged by detail: it stays inside the mill's width and depth.
			local big = MachineArt.Build("Millmaster200L", false)
			local fp = Catalog.GetSawmill("Millmaster200L")
			for _, d in ipairs(big:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "Panel" and d.Name ~= "Output" then
					t.ok(math.abs(d.CFrame.Position.X) <= fp.width / 2 + 0.01, d.Name .. " inside the footprint (x)")
					t.ok(math.abs(d.CFrame.Position.Z) <= fp.depth / 2 + 3, d.Name .. " inside the footprint (z)")
				end
			end
		end
	)

	t.test(
		"every planer tier: intake, outfeed, belt, a size panel, a tier sign, tagged, more detail as it climbs",
		function()
			local PlanerLogic = loader:shared("PlanerLogic")
			local last = 0
			for _, machine in ipairs(PlanerLogic.List()) do
				local model = MachineArt.BuildPlaner(machine.id, false)
				t.eq(model:GetAttribute("PlanerId"), machine.id)
				t.ok(model:HasTag("Planer"), "tagged for PlanerService and the panel")
				t.ok(find(model, "Intake", "BasePart"), "an intake")
				local output = find(model, "Output", "Attachment")
				t.ok(output and output.CFrame.LookVector.Z > 0.9, "boards leave toward +Z")
				local belt = find(model, "Conveyor", "BasePart")
				t.ok(belt.CanCollide and belt.CollisionGroup == "MillBelt", "a belt carries the plank through")
				t.ok(
					find(model, "CutReadout", "TextLabel") and find(model, "LimitReadout", "TextLabel"),
					"size and limit"
				)
				t.ok(find(model, "CutPrompt", "ProximityPrompt"), "the owner's prompt")
				local axes = {}
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("TextButton") then
						axes[d.Name] = { d:GetAttribute("Axis"), d:GetAttribute("Dir") }
					end
				end
				t.eq(axes, { XMinus = { "x", -1 }, XPlus = { "x", 1 }, YMinus = { "y", -1 }, YPlus = { "y", 1 } })
				local sign = find(model, "TierSign", "BasePart")
				t.eq(find(sign, "TextLabel").Text, string.upper(machine.tierName))
				local n = parts(model)
				t.ok(n <= MachineArt.Budget(machine.planer.tier), machine.id .. " keeps its budget: " .. n)
				t.ok(n > last, machine.id .. " has more detail than the tier below")
				last = n
				-- The belt must carry the widest plank this tier takes.
				local widest = math.max(machine.planer.maxX, machine.planer.maxY) * 1.6
				t.ok(belt.Size.X >= widest, machine.id .. " belt is wide enough")
			end
			t.eq(MachineArt.BuildPlaner("PlanerNope", false), nil)
			local ghost = MachineArt.BuildPlaner("PlanerSteam", true)
			t.eq(find(ghost, "Panel"), nil)
			t.ok(not ghost:HasTag("Planer"), "a ghost is not a planer")
			for _, d in ipairs(ghost:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "Root" and d.Name ~= "Intake" then
					t.eq(d.CanCollide, false, d.Name)
				end
			end
		end
	)

	t.test("BuildAny gives the right model for each plot machine", function()
		t.eq(MachineArt.BuildAny("SawmillSturdy", false):GetAttribute("MillId"), "SawmillSturdy")
		t.eq(MachineArt.BuildAny("PlanerBench", false):GetAttribute("PlanerId"), "PlanerBench")
		t.eq(MachineArt.BuildAny("ConveyorTurn", false):GetAttribute("BeltShape"), "turn")
		t.eq(MachineArt.BuildAny("SkyBin", true).Name, "SkyBin")
		t.eq(MachineArt.BuildAny("ChopSaw", false):GetAttribute("MachineId"), "ChopSaw")
		t.eq(MachineArt.BuildAny("Chair", false), nil)
	end)
end
