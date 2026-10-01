--!nocheck
-- CharacterArt (Shared/Art): the townsfolk's rigs. What QuestUI, NPCService
-- and NPCController rely on: named parts, joints, an anchored root holding
-- everything else up, a name tag, eyes to blink, and a phone-friendly
-- part budget.

return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Color3 = roblox.Vector3, roblox.CFrame, roblox.Color3
	local CharacterArt = t.load("ReplicatedStorage/Shared/Art/CharacterArt")
	local NPCData = t.shared("NPCData")

	local MAX_PARTS = 90

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function near(a, b, eps)
		return (a.Position - b.Position).Magnitude < (eps or 1e-3)
			and (a.LookVector - b.LookVector).Magnitude < (eps or 1e-3)
			and (a.UpVector - b.UpVector).Magnitude < (eps or 1e-3)
	end

	local function murph()
		return CharacterArt.Build(NPCData.Get("Murph").look)
	end

	t.test("Murph has the parts QuestUI's portrait clones, as direct children", function()
		local m = murph()
		for _, name in ipairs({ "Head", "Beard", "Beanie", "Torso", "LeftArm", "RightArm" }) do
			local p = m:FindFirstChild(name)
			t.ok(p and p:IsA("BasePart"), name .. " missing")
		end
		t.ok(m:FindFirstChild("Torso"):IsA("BasePart"), "Torso (the Talk prompt's home)")
	end)

	t.test("the face comes along when the Head is cloned (it's under the Head)", function()
		local head = murph().Head
		local eyes = 0
		for _, d in ipairs(head:GetChildren()) do
			if d.Name == "Eye" then
				eyes += 1
				t.ok(d:FindFirstChild("EyeShine"), "an eye without a shine")
			end
		end
		t.eq(eyes, 2)
		t.ok(head:FindFirstChild("Nose") and head:FindFirstChild("Mouth"), "nose and mouth")
	end)

	t.test("rig: anchored root as PrimaryPart, everything else hangs off it", function()
		for _, npc in ipairs(NPCData.All()) do
			local m = CharacterArt.Build(npc.look)
			local root = m.PrimaryPart
			t.ok(root and root.Name == "HumanoidRootPart", npc.id .. ": PrimaryPart")
			t.ok(root.Anchored, npc.id .. ": root anchored")
			t.eq(root.Transparency, 1)
			for _, p in ipairs(parts(m)) do
				if p ~= root then
					t.ok(not p.Anchored, npc.id .. ": " .. p.Name .. " is anchored")
					t.ok(p.Massless, npc.id .. ": " .. p.Name .. " has mass")
					t.ok(not p.CanCollide, npc.id .. ": " .. p.Name .. " collides")
				end
			end
		end
	end)

	t.test("Motor6Ds named like a Roblox rig, joining the right parts", function()
		local m = murph()
		local root, torso = m.HumanoidRootPart, m.Torso
		local want = {
			RootJoint = { root, root, torso },
			Neck = { torso, torso, m.Head },
			LeftShoulder = { torso, torso, m.LeftArm },
			RightShoulder = { torso, torso, m.RightArm },
			LeftHip = { torso, torso, m.LeftLeg },
			RightHip = { torso, torso, m.RightLeg },
		}
		for name, w in pairs(want) do
			local motor = w[1]:FindFirstChild(name)
			t.ok(motor and motor:IsA("Motor6D"), name .. " missing")
			t.ok(motor.Part0 == w[2] and motor.Part1 == w[3], name .. " joins the wrong parts")
			-- At rest the joint holds Part1 exactly where it was built.
			t.ok(near(motor.Part0.CFrame * motor.C0 * motor.C1:Inverse(), motor.Part1.CFrame), name .. " offset")
			-- Joint frames line up with the model's axes (so Angles(a, 0, 0) swings forward).
			local frame = motor.Part0.CFrame * motor.C0
			t.ok((frame.LookVector - Vector3.new(0, 0, -1)).Magnitude < 1e-4, name .. " frame turned")
		end
		t.eq(#CharacterArt.Joints, 6)
	end)

	t.test("every detail is welded to the part it moves with, in place", function()
		for _, npc in ipairs(NPCData.All()) do
			local m = CharacterArt.Build(npc.look)
			local motored = {}
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("Motor6D") then
					motored[d.Part1] = true
				end
			end
			for _, p in ipairs(parts(m)) do
				if p ~= m.PrimaryPart and not motored[p] then
					local weld = p:FindFirstChild("Weld")
					t.ok(weld and weld:IsA("Weld") and weld.Part1 == p, npc.id .. ": " .. p.Name .. " isn't welded")
					t.ok(near(weld.Part0.CFrame * weld.C0, p.CFrame), npc.id .. ": " .. p.Name .. " weld offset")
					-- Welded to a body part (directly under the model), never to another detail.
					t.ok(weld.Part0.Parent == m, npc.id .. ": " .. p.Name .. " welded to a detail")
				end
			end
		end
	end)

	t.test("about the size of a Roblox avatar, standing on y = 0", function()
		for _, npc in ipairs(NPCData.All()) do
			local m = CharacterArt.Build(npc.look)
			local s = npc.look.scale or 1
			local h = m:GetAttribute("Height")
			t.ok(h >= 5.2 * s and h <= 6.6 * s, string.format("%s is %.2f tall", npc.id, h))
			local low = math.huge
			for _, p in ipairs({ m.LeftLeg, m.RightLeg }) do
				low = math.min(low, p.CFrame.Position.Y - p.Size.Y / 2)
			end
			t.ok(math.abs(low) < 1e-3, npc.id .. "'s feet aren't on the ground")
			t.ok(math.abs(m:GetAttribute("RootHeight") - m.PrimaryPart.CFrame.Position.Y) < 1e-3, "RootHeight")
			t.eq(m:GetAttribute("RootHeight"), CharacterArt.RootHeight(npc.look))
		end
	end)

	t.test("part budget: at most " .. MAX_PARTS .. " parts a person", function()
		for _, npc in ipairs(NPCData.All()) do
			local n = #parts(CharacterArt.Build(npc.look))
			t.ok(n <= MAX_PARTS, string.format("%s has %d parts", npc.id, n))
		end
	end)

	t.test("a name tag (name, then role) over the head, seen from 60 studs", function()
		local m = murph()
		local tag = m.Head:FindFirstChild("NameTag")
		t.ok(tag and tag:IsA("BillboardGui"), "NameTag")
		t.eq(tag.MaxDistance, 60)
		t.eq(tag:FindFirstChild("Name").Text, "Murph")
		t.eq(tag:FindFirstChild("Role").Text, "Retired lumberjack")
		t.ok(tag.StudsOffset.Y > m:GetAttribute("TopOffset"), "the tag sits above the hat")
		local plain = CharacterArt.Build({
			name = "Nobody",
			skin = Color3.new(1, 0.8, 0.6),
			shirt = Color3.new(0.5, 0.5, 0.5),
			pants = Color3.new(0.2, 0.2, 0.4),
			tag = false,
		})
		t.eq(plain.Head:FindFirstChild("NameTag"), nil)
	end)

	t.test("every style builds (hats, beards, hair, things to hold), any scale", function()
		local base = {
			skin = Color3.new(1, 0.8, 0.6),
			shirt = Color3.new(0.6, 0.2, 0.2),
			pants = Color3.new(0.2, 0.2, 0.4),
		}
		local options = {
			hat = { "beanie", "cap", "capBack", "hardhat", "conductor", "bandana", "flatcap", "none" },
			beard = { "big", "stubble", "mustache", "handlebar", "goatee", "none" },
			hairStyle = { "short", "bun", "long", "curly", "ponytail", "bald", "none" },
			carry = { "mug", "clipboard", "wrench", "basket", "cane", "scroll", "lantern", "sapling", "none" },
		}
		for field, values in pairs(options) do
			for _, v in ipairs(values) do
				local spec = table.clone(base)
				spec.name = field .. "_" .. v
				spec[field] = v
				spec.scale = 0.8
				spec.stripe = Color3.new(0.1, 0.1, 0.1)
				spec.glasses = Color3.new(0.3, 0.2, 0.1)
				local m = CharacterArt.Build(spec)
				t.ok(m.PrimaryPart and m:FindFirstChild("Head"), spec.name)
				t.ok(#parts(m) <= MAX_PARTS, spec.name .. " over budget")
			end
		end
		-- Every outfit piece at once still fits.
		local all = table.clone(base)
		all.name = "Everything"
		all.stripe, all.overalls, all.apron, all.vest =
			Color3.new(0, 0, 0), Color3.new(0, 0, 1), Color3.new(1, 0, 0), Color3.new(0, 1, 0)
		all.scarf, all.gloves, all.suspenders, all.kneePatch =
			Color3.new(1, 1, 0), Color3.new(1, 1, 1), Color3.new(0.5, 0, 0), Color3.new(0, 0, 0)
		all.toolbelt, all.rolledSleeves, all.cuffs, all.stout = true, true, true, true
		all.hat, all.beard, all.hairStyle, all.carry = "beanie", "big", "long", "basket"
		all.glasses = Color3.new(0, 0, 0)
		local n = #parts(CharacterArt.Build(all))
		t.ok(n <= 140, "everything at once: " .. n .. " parts")
	end)

	t.test("hats and beards are direct children, their bits welded to the head", function()
		local m = murph()
		local beanie = m.Beanie
		t.eq(beanie.Weld.Part0, m.Head)
		t.ok(beanie:FindFirstChild("Pompom"), "a pompom on the beanie")
		t.eq(m.Beard.Weld.Part0, m.Head)
		for _, d in ipairs(m.Beard:GetDescendants()) do
			if d:IsA("BasePart") then
				t.eq(d.Weld.Part0, m.Head)
			end
		end
	end)

	t.test("the same spec builds the same figure", function()
		local a, b = murph(), murph()
		local pa, pb = parts(a), parts(b)
		t.eq(#pa, #pb)
		for i = 1, #pa do
			t.ok(near(pa[i].CFrame, pb[i].CFrame) and pa[i].Color == pb[i].Color, "differs at " .. pa[i].Name)
		end
		local _ = CFrame
	end)
end
