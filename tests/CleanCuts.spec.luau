--!nocheck
-- T389 clean cuts: every cut end (stump top, both log ends, both ends of a
-- section) is one flat plate of core wood, 0.005 stud proud of the end,
-- with nothing else standing out. Seeded heights over an upright trunk, a
-- tilted branch and a horizontal log; Notch and hit dress go with the split.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
	local players = {
		GetPlayers = function()
			return {}
		end,
	}
	local loader = t.loader({ services = { Players = players, PhysicsService = {} } })
	local Wood = loader:server("WoodService")
	local GameConfig = t.shared("GameConfig")
	local SectionLogic = t.shared("SectionLogic")
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local WoodData = t.shared("WoodData")
	local def = WoodData.Get("oak")

	local LENGTH, THICK = 8, 1.2
	local DRESS = { "Notch", "Chip", "HitMark", "HitHighlight" }
	local poses = {
		upright = CFrame.new(3, LENGTH / 2, 4),
		branch = CFrame.new(3, 6, 4) * CFrame.Angles(0, 0.7, 0.9),
		log = CFrame.new(3, 1, 4) * CFrame.Angles(0, 0.3, -math.pi / 2),
	}

	local function part(parent, name, size, cf)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Anchored = true
		p.Parent = parent
		return p
	end

	-- A section with the dress an axe hit leaves on it.
	local function build(pose)
		local model = Instance.new("Model")
		local s = part(model, "Section", Vector3.new(THICK, LENGTH, THICK), pose)
		s:SetAttribute("Section", 1)
		for _, name in ipairs(DRESS) do
			local d = part(model, name, Vector3.new(0.4, 0.35, 0.4), pose * CFrame.new(0.4, 1, 0))
			d:SetAttribute("Section", 1)
		end
		local hl = Instance.new("Highlight")
		hl.Parent = s
		TreeArt.CutFace(def, s, true)
		TreeArt.CutFace(def, s, false)
		return model, s
	end

	local function count(model, name)
		local n = 0
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == name then
				n += 1
			end
		end
		return n
	end

	local function volume(model)
		local v = 0
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == "Section" then
				v += d.Size.X * d.Size.Y * d.Size.Z
			end
		end
		return v
	end

	t.test("a cut leaves two flat ends, each with exactly one plate 0.005 proud, at 60 seeded heights", function()
		local state = 389
		local rng = {
			NextNumber = function(_, lo, hi)
				state = (state * 1103515245 + 12345) % 2147483648
				return lo + (hi - lo) * state / 2147483648
			end,
		}
		for name, pose in pairs(poses) do
			for _ = 1, 20 do
				local model, s = build(pose)
				local h = SectionLogic.ClampHeight(rng:NextNumber(-LENGTH / 2, LENGTH / 2), LENGTH)
				local before = volume(model)
				local partsBefore = #model:GetChildren()
				local plane = pose:PointToWorldSpace(Vector3.new(0, h - LENGTH / 2, 0))
				local high = Wood.SplitPart(s, h, 2)
				TreeArt.CutFace(def, s, true)
				TreeArt.CutFace(def, high, false)
				for _, sec in ipairs({ s, high }) do
					t.ok(sec.Size.Y >= 0.5 - 1e-9, name .. ": no section shorter than 0.5")
					t.ok(sec.CFrame.UpVector:Dot(pose.UpVector) > math.cos(math.rad(1)), name .. ": square to the axis")
				end
				local lowEnd = s.CFrame:PointToWorldSpace(Vector3.new(0, s.Size.Y / 2, 0))
				local highEnd = high.CFrame:PointToWorldSpace(Vector3.new(0, -high.Size.Y / 2, 0))
				t.ok(
					(lowEnd - plane).Magnitude <= 0.05 and (highEnd - plane).Magnitude <= 0.05,
					name .. ": on the plane"
				)
				-- One plate per new end, its outer face 0.005 off the end.
				for _, e in ipairs({ { s, true }, { high, false } }) do
					local sec, top = e[1], e[2]
					local found = 0
					for _, d in ipairs(model:GetChildren()) do
						if d.Name == "CutFace" and d:GetAttribute("Section") == sec:GetAttribute("Section") then
							local y = sec.CFrame:PointToObjectSpace(d.CFrame.Position).Y
							if (y > 0) == top and math.abs(math.abs(y) - sec.Size.Y / 2) < 0.1 then
								found += 1
								local outer = math.abs(y) + d.Size.Y / 2
								t.ok(math.abs(outer - sec.Size.Y / 2) <= 0.01, name .. ": outer face within 0.01")
								t.ok(math.abs(outer - sec.Size.Y / 2 - 0.005) < 1e-4, name .. ": 0.005 proud")
								t.ok(d.Size.X <= sec.Size.X and d.Size.Z <= sec.Size.X, "no cap wider than the log")
								t.ok(not d.CanCollide and not d.CanQuery and not d.CanTouch, "plate is looks only")
								t.ok(not d.CastShadow and d.Massless, "plate casts no shadow and is massless")
							end
						end
					end
					t.eq(found, 1, name .. ": exactly one CutFace on the end")
				end
				-- Hit dress is gone; nothing else was added.
				for _, gone in ipairs(DRESS) do
					t.eq(count(model, gone), 0, name .. ": " .. gone .. " left")
				end
				t.eq(#s:GetChildren() + #high:GetChildren(), 0, "no highlight left on either piece")
				t.ok(math.abs(volume(model) - before) / before < 0.005, name .. ": volume kept")
				-- Before: 1 section, 4 dress, 2 plates. After: 2 sections, 4 plates.
				t.eq(#model:GetChildren(), partsBefore - #DRESS + 1 + 2, name .. ": the new section and plates only")
			end
		end
	end)

	t.test("cuts keep half a stud from the ends, so no part near the cut is shorter than 0.5", function()
		t.eq(GameConfig.CutEdge, 0.5)
		t.eq(SectionLogic.ClampHeight(-LENGTH / 2, LENGTH), 0.5, "0.5 above the base")
		t.eq(SectionLogic.ClampHeight(LENGTH, LENGTH), LENGTH - 0.5)
		-- A second cut 0.2 stud from the first lands on the shorter section
		-- and is clamped 0.5 in from its end.
		local _, s = build(poses.upright)
		Wood.SplitPart(s, 3, 2)
		local again = SectionLogic.ClampHeight(s.Size.Y / 2 - 0.2, s.Size.Y)
		t.ok(s.Size.Y - again >= 0.5 - 1e-9 and again >= 0.5 - 1e-9, "leaves 0.5 or more each side")
	end)

	t.test("a stump top is level with one plate; a second plate on the same end replaces the first", function()
		local model, s = build(poses.upright)
		Wood.SplitPart(s, 0.5, 2)
		local face = TreeArt.CutFace(def, s, true)
		TreeArt.CutFace(def, s, true)
		local tops = 0
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == "CutFace" and d:GetAttribute("End") == "Top" and d:GetAttribute("Section") == 1 then
				tops += 1
			end
		end
		t.eq(tops, 1)
		t.ok(not face.Parent, "the older plate went")
		t.ok(math.abs(s.CFrame.UpVector.Y - 1) < 1e-9, "the stump top is level")
	end)
end
