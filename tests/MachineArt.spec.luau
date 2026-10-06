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
		MachineArt.SetCut(model, 1.2, 0.8)
		t.eq(find(model, "CutReadout", "TextLabel").Text, "1.2 × 0.8 u")
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
		t.ok(parts(model) <= 20, "a small model: " .. parts(model))
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
end
