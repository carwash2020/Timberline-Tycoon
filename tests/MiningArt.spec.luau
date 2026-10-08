--!nocheck
-- MiningArt: part caps, the ore-rock veins, and none of the sell-station names.

return function(t)
	local MiningArt = t.load("ReplicatedStorage/Shared/Mining/MiningArt")
	local OreData = t.load("ReplicatedStorage/Shared/Mining/OreData")
	local OreRock = t.load("ReplicatedStorage/Shared/Mining/OreRockArtAdapter")
	local PickaxeData = t.load("ReplicatedStorage/Shared/Mining/PickaxeData")

	local FORBIDDEN = { SellFurnace = true, SellStation = true, SellZone = true, SellPoint = true }

	local function walk(root, fn)
		fn(root)
		for _, d in ipairs(root:GetDescendants()) do
			fn(d)
		end
	end

	local function clean(root)
		walk(root, function(inst)
			t.eq(FORBIDDEN[inst.Name], nil, inst.Name)
			if inst.GetTags then
				for _, tag in ipairs(inst:GetTags()) do
					t.eq(FORBIDDEN[tag], nil, tag)
				end
			end
		end)
	end

	t.test("every ore node is a rock of at most 8 parts, with 2 or 3 vein wedges", function()
		for _, ore in ipairs(OreData.All()) do
			local node = MiningArt.Node(ore)
			local parts = MiningArt.PartCount(node)
			t.ok(parts <= MiningArt.MaxNodeParts and parts <= OreRock.MaxParts, ore.id .. " " .. parts)
			local veins = 0
			local lights = 0
			local rocks = 0
			local tilted = false
			local sunk = false
			walk(node, function(inst)
				if inst.Name == "Vein" and inst:IsA("WedgePart") then
					veins += 1
					local thin = math.min(inst.Size.X, inst.Size.Y, inst.Size.Z)
					t.ok(thin <= 0.15, ore.id .. " vein proud " .. thin)
				end
				if inst.Name == "Rock" and inst:IsA("BasePart") then
					rocks += 1
					local look = inst.CFrame.LookVector
					if look.X * look.X + look.Y * look.Y > 0.006 then
						tilted = true
					end
					if inst.CFrame.Position.Y - inst.Size.Magnitude / 2 < 0 then
						sunk = true
					end
				end
				if inst:IsA("PointLight") then
					lights += 1
					t.eq(inst.Shadows, false)
					t.ok(inst.Range <= 12)
				end
			end)
			t.ok(rocks >= 3 and rocks <= 5, ore.id .. " rocks " .. rocks)
			t.eq(tilted, true, ore.id .. " tilt")
			t.eq(sunk, true, ore.id .. " sunk")
			t.ok(veins == 2 or veins == 3, ore.id .. " veins " .. veins)
			t.eq(lights, if ore.glow then 1 else 0, ore.id)
			t.eq(node:GetAttribute("HoverKind"), "Ore")
			t.eq(node:GetAttribute("HoverNeed"), ore.hardness)
			MiningArt.ClearNode(node)
			t.eq(node:GetAttribute("HoverKey"), nil)
			clean(node)
		end
	end)

	t.test("gear budgets", function()
		local lamp = MiningArt.MinersLamp()
		t.ok(MiningArt.PartCount(lamp) <= 6)
		t.eq(MiningArt.LightCount(lamp), 1)
		local light = lamp:FindFirstChild("LampLight", true)
		t.eq(light.Range, 12)
		t.eq(light.Shadows, false)
		t.eq(light.Enabled, false)
		local hat = MiningArt.Hardhat()
		t.ok(MiningArt.PartCount(hat) <= 6)
		t.eq(MiningArt.LightCount(hat), 0)
		t.ok(hat:FindFirstChild("HeadWeld", true) ~= nil)
		local ladder = MiningArt.RopeLadder()
		local n = MiningArt.PartCount(ladder)
		t.ok(n >= 7 and n <= 9, "ladder " .. n)
		t.eq(ladder:GetAttribute("Length"), 12)
		t.ok(MiningArt.PartCount(MiningArt.LampPost()) <= 10)
		t.ok(MiningArt.PartCount(MiningArt.Chest()) <= 14)
		clean(lamp)
		clean(hat)
		clean(ladder)
	end)

	t.test("the furnace is one light, under 60 parts, and not a sell station", function()
		local furnace = MiningArt.SmeltingFurnace()
		t.eq(furnace.Name, "SmeltingFurnace")
		t.ok(MiningArt.PartCount(furnace) <= MiningArt.MaxFurnaceParts)
		t.eq(MiningArt.LightCount(furnace), 1)
		local intake = furnace:FindFirstChild("SmeltIntake", true)
		t.ok(intake ~= nil)
		t.eq(intake:GetAttribute("SmeltIntake"), true)
		local particles = false
		walk(furnace, function(inst)
			if inst:IsA("ParticleEmitter") then
				particles = true
			end
			if inst:IsA("PointLight") then
				t.eq(inst.Shadows, false)
			end
		end)
		t.eq(particles, false)
		clean(furnace)
		clean(MiningArt.Prospector())
		clean(MiningArt.CraftBench())
		clean(MiningArt.Rubble("mine-mid", 2))
		for _, pick in ipairs(PickaxeData.All()) do
			local model = MiningArt.Pickaxe(pick)
			t.eq(model.PrimaryPart.Name, "Handle")
			t.ok(MiningArt.PartCount(model) <= 12, pick.id)
			if pick.id == "LuxPickaxe" then
				t.eq(MiningArt.LightCount(model), 0)
			end
			clean(model)
		end
	end)
end
