--!nocheck
-- TreeArt.FromSkeleton (Shared/Art): the v2 section tree's model (V2_PLAN.md
-- §3c, §3e, §3j), and ForestArt's clues on a section.
--   * Exactly the parts TreeGen counted. Sections are colliding, queryable,
--     untouchable Wood blocks in group "Wood", tagged WoodSection with
--     their Section id; every other part is dress: never collides or fires
--     touches, can be queried, in group "Leaves", riding a real section,
--     named as WindSway and CanopyFade expect.
--   * The model: tag Tree, Atomic streaming, PrimaryPart section 1, the
--     plan's attributes; built at the origin, ground at y = 0.
--   * Silhouettes: oak at least 0.7 as wide as tall, birch at most 0.45,
--     maple at least 0.85; pine and frostwood are cones. The model's top is
--     TreeGen's height.
--   * Cut faces and notches show the wood's core colour and material.
--   * The grown-up sapling grows; today's sapling, trees, stumps and logs
--     are untouched (TreeArt.spec still pins them).
--   * The world's trees, rebuilt as section trees from the real WorldPlan
--     spots, average at most 48 parts (§3c) and cost at most 1.2x today's
--     trees on the same spots (with 500 spots that kept the 27,874-part
--     world under §16's 31k).
return function(t)
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local ForestArt = t.load("ReplicatedStorage/Shared/Art/ForestArt")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
	local TreeGen = t.shared("TreeGen")
	local TreeLogic = t.shared("TreeLogic")
	local WoodData = t.shared("WoodData")
	local ForestData = t.shared("ForestData")
	local roblox = t.roblox
	local Enum, Vector3, CFrame, Color3 = roblox.Enum, roblox.Vector3, roblox.CFrame, roblox.Color3

	local woods = WoodData.All()
	local ELDER = ForestData.Elder.scale

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- A part's world box: lowest and highest corner.
	local function bounds(p)
		local cf, s = p.CFrame, p.Size / 2
		local ext = Vector3.new(
			math.abs(cf.XVector.X) * s.X + math.abs(cf.YVector.X) * s.Y + math.abs(cf.ZVector.X) * s.Z,
			math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z,
			math.abs(cf.XVector.Z) * s.X + math.abs(cf.YVector.Z) * s.Y + math.abs(cf.ZVector.Z) * s.Z
		)
		local c = cf.Position
		return c - ext, c + ext
	end

	local DRESS_NAMES = {
		Leaves = true,
		Frond = true,
		Facet = true,
		Root = true,
		BarkMark = true,
		Crack = true,
		Vein = true,
		PalmRing = true,
		Coconut = true,
		Pod = true,
		PodStem = true,
	}

	local function build(id, seed, scale, stage)
		local opts = if scale == ELDER then { elder = true } else nil
		local skel = TreeGen.Skeleton(id, seed, scale, opts)
		if stage then
			skel = TreeGen.AtStage(skel, stage)
		end
		return TreeArt.FromSkeleton(WoodData.Get(id), skel, { uid = "t1", planterId = 7 }), skel
	end

	t.test("exactly the parts TreeGen counted, every wood, size, stage and Elder", function()
		for _, def in ipairs(woods) do
			for _, seed in ipairs({ 1, 2, 3, 40 }) do
				for _, scale in ipairs({ TreeGen.SizeLo, 1, TreeGen.SizeHi, ELDER }) do
					local model, skel = build(def.id, seed, scale)
					t.eq(#parts(model), TreeGen.PartCount(skel), def.id .. " seed " .. seed)
					t.ok(#parts(model) <= TreeGen.Budgets[def.id], def.id .. ": over budget")
				end
				for _, s in ipairs({ 0.25, 0.5, 0.75 }) do
					local model, skel = build(def.id, seed, 1, s)
					t.eq(#parts(model), TreeGen.PartCount(skel), def.id .. " stage " .. s)
				end
			end
		end
	end)

	t.test("leaf crowns are crystal-cut wedges; bark follows the wood", function()
		for _, id in ipairs({ "oak", "birch", "pine", "maple", "frostwood", "phantomwood", "lumenwood" }) do
			local model = build(id, 4, 1)
			local def = WoodData.Get(id)
			local crown, tilted = 0, 0
			local signed = false
			for _, p in ipairs(parts(model)) do
				if p.Name == "Leaves" or p.Name == "Facet" then
					crown += 1
					t.ok(p:IsA("WedgePart"), id .. " " .. p.Name .. " is a crystal facet")
					if math.abs(p.CFrame.UpVector.Y) < 0.99 then
						tilted += 1
					end
				elseif p.Name == "Section" then
					t.eq(p.Material, TreeArt.BarkMaterial(def), id .. " bark")
				end
				if p:GetAttribute("Signature") == TreeArt.Signatures[id] then
					signed = true
				end
			end
			t.ok(crown >= 4, id .. " has a crown")
			t.ok(tilted >= 1, id .. " facets are cut, not flat cubes")
			t.ok(signed, id .. " carries its signature (" .. tostring(TreeArt.Signatures[id]) .. ")")
		end
		t.eq(TreeArt.BarkMaterial(WoodData.Get("oak")), Enum.Material.Wood)
		t.eq(TreeArt.BarkMaterial(WoodData.Get("frostwood")), Enum.Material.SmoothPlastic)
		t.eq(TreeArt.BarkMaterial(WoodData.Get("lumenwood")), Enum.Material.SmoothPlastic)
		t.eq(TreeArt.BarkMaterial(WoodData.Get("phantomwood")), Enum.Material.Concrete)
	end)

	t.test("each species' signature is the one you can name, and seeds vary the colour", function()
		local function colorsOf(id, seed)
			local model = build(id, seed, 1)
			local out = {}
			for _, p in ipairs(parts(model)) do
				if p.Name == "Leaves" or p.Name == "Facet" then
					table.insert(out, p.Color:ToHex())
				end
			end
			table.sort(out)
			return out
		end
		t.ok(colorsOf("oak", 1) ~= nil)
		local a, b = colorsOf("maple", 2), colorsOf("maple", 9)
		local same = true
		if #a ~= #b then
			same = false
		else
			for i = 1, #a do
				if a[i] ~= b[i] then
					same = false
				end
			end
		end
		t.ok(not same, "two maples of different seeds are not the same green")
		local oak = build("oak", 3, 1)
		local heart = TreeArt.HeartColor(WoodData.Get("oak"))
		local knot = false
		for _, p in ipairs(parts(oak)) do
			if p:GetAttribute("Signature") == "sap-knot" then
				knot = true
				t.eq(p.Material, Enum.Material.Wood, "the sap knot is cut wood")
				t.eq(string.upper(p.Color:ToHex()), string.upper(heart:ToHex()), "the sap knot is heartwood")
			end
		end
		t.ok(knot, "an oak shows a sap knot")
		local frost = build("frostwood", 3, 1)
		local caps = 0
		for _, p in ipairs(parts(frost)) do
			if p:GetAttribute("Signature") == "frost-tip" then
				caps += 1
				t.eq(p.Material, Enum.Material.Snow)
			end
		end
		t.ok(caps >= 4, "frost tips sit on the upper tiers")
		for _, id in ipairs({ "emberwood", "palmwood" }) do
			local model = build(id, 1, 1)
			local signed = false
			for _, p in ipairs(parts(model)) do
				if p:GetAttribute("Signature") == TreeArt.Signatures[id] then
					signed = true
				end
			end
			t.ok(signed, id .. " carries " .. TreeArt.Signatures[id])
		end
	end)

	t.test("the tutorial grove oaks are the same crystal oak", function()
		-- MapBuilder plants these: small, seeds 4101..4103 (TutorialGrove.Trees).
		for i = 1, 3 do
			local model = build("oak", 4100 + i, TreeGen.ScaleFor("small"))
			local knot, wedges = false, 0
			for _, p in ipairs(parts(model)) do
				if p.Name == "Leaves" then
					wedges += 1
					t.ok(p:IsA("WedgePart"), "grove oak leaves are facets")
				end
				if p:GetAttribute("Signature") == "sap-knot" then
					knot = true
				end
				if p.Name == "Section" then
					t.eq(p.Shape, Enum.PartType.Block, "the grove oak is still cut by its sections")
				end
			end
			t.ok(wedges >= 4, "grove oak " .. i .. " has a crown")
			t.ok(knot, "grove oak " .. i .. " has its sap knot")
		end
	end)

	t.test("seasonal tint and quality extras stay off the phone tier", function()
		t.eq(TreeArt.SeasonIndex(0), 0)
		t.eq(TreeArt.SeasonIndex(TreeArt.SeasonSeconds), 1)
		t.eq(TreeArt.SeasonIndex(TreeArt.SeasonSeconds * 5 + 10), 1)
		local green = Color3.fromRGB(80, 140, 60)
		t.eq(TreeArt.TintLeaf(green, "maple", 1, 1), green, "summer is the painted colour")
		t.eq(TreeArt.TintLeaf(green, "maple", 2, 0), green, "amount 0 leaves it")
		local autumn = TreeArt.TintLeaf(green, "maple", 2, 1)
		t.ok(autumn.R > green.R and autumn.B < green.B, "autumn warms a maple")
		local pineWinter = TreeArt.TintLeaf(green, "pine", 3, 1)
		local oakWinter = TreeArt.TintLeaf(green, "oak", 3, 1)
		t.ok(pineWinter.B > oakWinter.B, "winter cools a pine more than an oak")
		t.eq(TreeArt.Cosmetics("low"), { tint = 0, accents = false })
		t.eq(TreeArt.Cosmetics("medium").accents, false)
		t.ok(TreeArt.Cosmetics("medium").tint > 0 and TreeArt.Cosmetics("medium").tint < 1)
		t.eq(TreeArt.Cosmetics("high"), { tint = 1, accents = true })
		t.eq(TreeArt.AccentColor("oak"), nil, "oak's signature is the knot, not a mote")
		t.ok(TreeArt.AccentColor("frostwood") ~= nil)
		t.ok(TreeArt.AccentColor("maple") ~= nil)
		t.eq(TreeArt.AccentColor("emberwood"), nil, "emberwood already sheds sparks")
	end)

	t.test("sections collide and can be chopped; dress never collides", function()
		for _, def in ipairs(woods) do
			for _, seed in ipairs({ 1, 9 }) do
				local model, skel = build(def.id, seed, 1)
				local ids = {}
				for _, s in ipairs(skel.sections) do
					ids[s.id] = s
				end
				local sections = 0
				for _, p in ipairs(parts(model)) do
					if p.Name == "Section" then
						sections += 1
						local s = ids[p:GetAttribute("Section")]
						t.ok(s, def.id .. ": a section part with no skeleton section")
						t.ok(p.CanCollide and p.CanQuery and not p.CanTouch and p.Anchored, def.id .. ": section flags")
						t.eq(p.Material, TreeArt.BarkMaterial(def))
						t.eq(p.CollisionGroup, "Wood")
						t.ok(p:HasTag("WoodSection"), def.id .. ": tagged WoodSection")
						t.eq(p.Shape, Enum.PartType.Block, "square sections")
						t.ok(
							math.abs(p.Size.X - s.thickness) < 1e-4
								and math.abs(p.Size.Z - s.thickness) < 1e-4
								and math.abs(p.Size.Y - s.length) < 1e-4,
							def.id .. ": the part is the section's size"
						)
						-- Its bottom centre is the skeleton's cf.
						local bottom = p.CFrame * Vector3.new(0, -p.Size.Y / 2, 0)
						t.ok(
							(bottom - s.cf.Position).Magnitude < 1e-3,
							def.id .. ": the section is where the skeleton says"
						)
					else
						local section = p:GetAttribute("Section")
						t.ok(ids[section], def.id .. ": " .. p.Name .. " rides no section")
						t.ok(not p.CanCollide and not p.CanTouch and p.CanQuery, def.id .. ": " .. p.Name .. " flags")
						t.eq(p.CollisionGroup, "Leaves", def.id .. " " .. p.Name)
						t.ok(DRESS_NAMES[p.Name], def.id .. ": an unexpected part " .. p.Name)
					end
				end
				t.eq(sections, #skel.sections, def.id .. ": every section built")
			end
		end
	end)

	t.test("canopy parts carry the names WindSway and CanopyFade look for", function()
		for _, def in ipairs(woods) do
			local model = build(def.id, 1, 1)
			local canopy = 0
			for _, p in ipairs(parts(model)) do
				local inTier = p.Parent and p.Parent.Name == "Tier"
				if p.Name == "Leaves" or p.Name == "Frond" or p.Name == "Facet" or inTier then
					canopy += 1
				end
			end
			t.ok(canopy >= 4, def.id .. ": a canopy")
		end
	end)

	t.test("the model: tag Tree, Atomic, section 1 its PrimaryPart, the plan's attributes", function()
		for _, def in ipairs(woods) do
			local model, skel = build(def.id, 3, 1)
			t.ok(model:HasTag("Tree"), def.id .. " tagged Tree")
			t.eq(model.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
			t.eq(model.PrimaryPart.Name, "Section")
			t.eq(model.PrimaryPart:GetAttribute("Section"), 1)
			t.eq(model:GetAttribute("WoodId"), def.id)
			t.eq(model:GetAttribute("Seed"), 3)
			t.eq(model:GetAttribute("Stage"), 1)
			t.eq(model:GetAttribute("Scale"), 1)
			t.eq(model:GetAttribute("Elder"), false)
			t.eq(model:GetAttribute("Felled"), false)
			t.eq(model:GetAttribute("Dormant"), false)
			t.eq(model:GetAttribute("PlanterId"), 7)
			t.eq(model:GetAttribute("Uid"), "t1")
			-- Ground at y = 0: the trunk's foot.
			local low = math.huge
			for _, p in ipairs(parts(model)) do
				if p.Name == "Section" then
					local lo = bounds(p)
					low = math.min(low, lo.Y)
				end
			end
			t.ok(math.abs(low) < 1e-3, def.id .. ": the trunk stands on y = 0")
			-- The top is TreeGen's height (the leaves reach their boxes' tops).
			local top = -math.huge
			for _, p in ipairs(parts(model)) do
				local _, hi = bounds(p)
				top = math.max(top, hi.Y)
			end
			t.ok(
				top <= skel.height + 0.05,
				string.format("%s: the model tops %.2f, TreeGen said %.2f", def.id, top, skel.height)
			)
			t.ok(
				top >= skel.height - 2,
				string.format("%s: the model tops %.2f, TreeGen said %.2f", def.id, top, skel.height)
			)
		end
		local elder = build("oak", 1, ELDER)
		t.eq(elder:GetAttribute("Elder"), true)
	end)

	-- How wide the leaves spread (the larger of the X and Z extents) and how
	-- tall the whole tree stands.
	local function canopyRatio(model)
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		local top = 0
		for _, p in ipairs(parts(model)) do
			local a, b = bounds(p)
			top = math.max(top, b.Y)
			if p.Name ~= "Section" and p.Name ~= "Root" then
				lo, hi = lo:Min(a), hi:Max(b)
			end
		end
		local span = hi - lo
		return math.max(span.X, span.Z) / top
	end

	t.test("silhouettes: oak broad, birch slim, maple wide, the conifers cones", function()
		local want = { oak = { 0.7, math.huge }, birch = { 0, 0.45 }, maple = { 0.85, math.huge } }
		for id, band in pairs(want) do
			for seed = 1, 12 do
				for _, scale in ipairs({ TreeGen.SizeLo, 1, TreeGen.SizeHi }) do
					local r = canopyRatio(build(id, seed, scale))
					t.ok(
						r >= band[1] and r <= band[2],
						string.format("%s seed %d x%.2f: width/height %.2f", id, seed, scale, r)
					)
				end
			end
		end
		for _, id in ipairs({ "pine", "frostwood" }) do
			for _, seed in ipairs({ 1, 5, 9 }) do
				local model = build(id, seed, 1)
				local tiers = {}
				for _, d in ipairs(model:GetChildren()) do
					if d:IsA("Model") and d.Name == "Tier" then
						-- How far its facets sit from the trunk's axis, on average
						-- (whatever way it's turned, however many sides it has).
						local low, sum, n = math.huge, 0, 0
						for _, p in ipairs(d:GetChildren()) do
							local c = p.CFrame.Position
							sum += Vector3.new(c.X, 0, c.Z).Magnitude
							n += 1
							low = math.min(low, c.Y)
						end
						table.insert(tiers, { y = low, w = sum / n })
					end
				end
				table.sort(tiers, function(a, b)
					return a.y < b.y
				end)
				t.ok(#tiers >= 4, id .. ": its tiers")
				for i = 2, #tiers do
					t.ok(tiers[i].w < tiers[i - 1].w, id .. ": a cone narrows going up")
				end
			end
		end
	end)

	t.test("the glow woods glow; frostwood and the starter woods don't", function()
		local function neon(model)
			local n = 0
			for _, p in ipairs(parts(model)) do
				if p.Material == Enum.Material.Neon then
					n += 1
				end
			end
			return n
		end
		local function light(model)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("PointLight") then
					t.eq(d.Shadows, false, "lights cast no shadows")
					return true
				end
			end
			return false
		end
		for _, id in ipairs({ "emberwood", "phantomwood", "lumenwood" }) do
			local model = build(id, 1, 1)
			t.ok(neon(model) >= 2, id .. " glows")
			t.ok(light(model), id .. " has its light")
		end
		for _, id in ipairs({ "oak", "birch", "pine", "maple", "frostwood" }) do
			t.eq(neon(build(id, 1, 1)), 0, id .. " has no neon")
		end
	end)

	t.test("a cut face is a thin plate of the wood's core, proud of the end", function()
		local cores = {
			oak = { "#E2BE84", Enum.Material.Wood },
			frostwood = { "#E4F2FA", Enum.Material.Ice },
			emberwood = { "#FFB25A", Enum.Material.CrackedLava },
			phantomwood = { "#C8B5F0", Enum.Material.Foil },
			lumenwood = { "#FFF6DA", Enum.Material.Neon },
		}
		for id, core in pairs(cores) do
			local def = WoodData.Get(id)
			local color, material = TreeArt.Core(def)
			t.eq(string.upper(color:ToHex()), string.sub(core[1], 2))
			t.eq(material, core[2])
			local model = build(id, 1, 1)
			local s = model.PrimaryPart
			for _, top in ipairs({ true, false }) do
				local face = TreeArt.CutFace(def, s, top)
				t.eq(face.Name, "CutFace")
				t.eq(face.Material, core[2])
				t.ok(math.abs(face.Size.Y - 0.06) < 1e-3, "0.06 thick")
				t.ok(math.abs(face.Size.X - s.Size.X * 0.86) < 1e-3, "0.86 of the width")
				t.ok(
					not face.CanCollide and not face.CanQuery and not face.CanTouch and face.Massless,
					"a face is looks only"
				)
				t.ok(face.Anchored, "anchored on a standing tree")
				t.eq(face:GetAttribute("Section"), 1)
				local local_ = s.CFrame:PointToObjectSpace(face.CFrame.Position)
				local edge = s.Size.Y / 2
				if top then
					t.ok(local_.Y > edge - 0.01 and local_.Y < edge + 0.06, "on the top end")
				else
					t.ok(local_.Y < -edge + 0.01 and local_.Y > -edge - 0.06, "on the bottom end")
				end
			end
		end
		-- On a loose piece the face is welded, not anchored.
		local def = WoodData.Get("oak")
		local loose = build("oak", 2, 1).PrimaryPart
		loose.Anchored = false
		local face = TreeArt.CutFace(def, loose, true)
		t.ok(not face.Anchored, "unanchored on a loose piece")
		local weld = face:FindFirstChildOfClass("WeldConstraint")
		t.ok(weld and weld.Part0 == loose and weld.Part1 == face, "welded to its section")
	end)

	t.test("a notch cuts in from the face it was hit on, as deep as the damage", function()
		local def = WoodData.Get("oak")
		local model = build("oak", 1, 1)
		local s = model.PrimaryPart
		local tW = s.Size.X
		local color = TreeArt.Core(def)
		for _, case in ipairs({
			{ normal = s.CFrame.XVector, axis = "X", sign = 1 },
			{ normal = -s.CFrame.XVector, axis = "X", sign = -1 },
			{ normal = s.CFrame.ZVector + s.CFrame.XVector * 0.2, axis = "Z", sign = 1 },
			{ normal = -s.CFrame.ZVector, axis = "Z", sign = -1 },
		}) do
			for _, frac in ipairs({ 0.1, 0.5, 0.9, 1.4 }) do
				local n = TreeArt.Notch(def, s, 1.2, case.normal, frac * 10, 10)
				local depth = tW * math.min(TreeArt.NotchMaxDepth, frac)
				t.eq(n.Name, "Notch")
				t.ok(math.abs(n.Size.Y - 0.35) < 1e-3, "0.35 tall")
				local along = if case.axis == "X" then n.Size.X else n.Size.Z
				local across = if case.axis == "X" then n.Size.Z else n.Size.X
				t.ok(math.abs(along - (depth + 0.02)) < 1e-3, "as deep as the damage")
				t.ok(math.abs(across - (tW + 0.04)) < 1e-3, "as wide as the section")
				-- Its outer face is flush with the section's face (a hair proud).
				local rel = s.CFrame:PointToObjectSpace(n.CFrame.Position)
				local c = if case.axis == "X" then rel.X else rel.Z
				local outer = c * case.sign + along / 2
				t.ok(math.abs(outer - (tW / 2 + 0.02)) < 1e-3, "flush with the face it was hit on")
				t.ok(math.abs(rel.Y - (1.2 - s.Size.Y / 2)) < 1e-3, "at the height hit")
				t.ok(n.Color:Lerp(Kit.shade(color, -0.25), 1) == n.Color, "core, shaded")
				t.eq(n:GetAttribute("Section"), 1)
				t.eq(n:GetAttribute("Height"), 1.2)
				t.eq(n:GetAttribute("Damage"), frac * 10)
				t.eq(n:GetAttribute("Required"), 10)
				t.ok(not n.CanCollide and not n.CanQuery and n.Anchored, "anchored on a standing tree")
				n:Destroy()
			end
		end
		t.eq(TreeArt.NotchDepth(2, 5, 10), 1)
		t.eq(TreeArt.NotchDepth(2, 50, 10), 1.9, "never all the way")
	end)

	t.test("the grown-up sapling grows, and today's sapling is as it was", function()
		for _, def in ipairs(woods) do
			local small = TreeArt.Sapling(def, 4, 0)
			local big = TreeArt.Sapling(def, 4, 1)
			local function top(m)
				local hi = 0
				for _, p in ipairs(parts(m)) do
					local _, b = bounds(p)
					hi = math.max(hi, b.Y)
					t.ok(not p.CanCollide and not p.CanQuery, def.id .. ": a sapling can't be chopped")
				end
				return hi
			end
			t.ok(top(big) > top(small) + 1, def.id .. ": it grows")
			t.ok(
				top(big) < TreeGen.AtStage(TreeGen.Skeleton(def.id, 4, 1), 0.25).height + 4,
				def.id .. ": up to its first stage"
			)
			t.eq(big.PrimaryPart.Name, "Stem")
			-- Today's (no growth given): the stem and its leaves, as before.
			local v1 = TreeArt.Sapling(def, 4)
			t.eq(v1.PrimaryPart.Name, "Stem")
			t.eq(v1.PrimaryPart.Shape, Enum.PartType.Cylinder, "today's sapling keeps its round stem")
		end
	end)

	t.test("bark clues lie on a section's square sides and ride it", function()
		local def = WoodData.Get("maple")
		local model = build("maple", 1, 1)
		local section = ForestArt.ClueSection(model)
		t.ok(section and section:GetAttribute("Section") == 2, "the clue goes on the second trunk section")
		local half = section.Size.X / 2
		for _, figure in ipairs({ "curly", "birdseye", "quilted", "burl", "starfall", "stormgrain" }) do
			local clue = ForestArt.SectionClue(model, section, def, figure, 5)
			t.eq(clue:GetAttribute("Section"), 2)
			t.eq(clue:GetAttribute("Figure"), figure)
			local n = 0
			for _, p in ipairs(parts(clue)) do
				n += 1
				t.eq(p:GetAttribute("Section"), 2, figure .. ": a clue part rides the section")
				t.ok(not p.CanCollide and not p.CanQuery, figure .. ": clues are looks only")
				-- On the bark: within reach of the section's sides, not inside its middle.
				local rel = section.CFrame:PointToObjectSpace(p.CFrame.Position)
				local out = math.max(math.abs(rel.X), math.abs(rel.Z))
				t.ok(out >= half * 0.4 and out <= half * 2.6, figure .. ": on the bark")
				t.ok(math.abs(rel.Y) <= section.Size.Y / 2 + 1, figure .. ": on its section")
			end
			t.ok(n > 0, figure .. " has parts")
			clue:Destroy()
		end
		-- Today's round trunk is untouched by the square path.
		local old = TreeArt.Build(def, 1, 1)
		local a = ForestArt.BarkClue(old, old.PrimaryPart, def, "curly", 5)
		local b = ForestArt.BarkClue(old, old.PrimaryPart, def, "curly", 5)
		t.eq(#parts(a), #parts(b))
		t.ok((parts(a)[1].CFrame.Position - parts(b)[1].CFrame.Position).Magnitude < 1e-6, "deterministic")
		local trunkR = old.PrimaryPart.Size.Y / 2
		local rel = old.PrimaryPart.CFrame:PointToObjectSpace(parts(a)[1].CFrame.Position)
		t.ok(
			math.abs(Vector3.new(0, rel.Y, rel.Z).Magnitude - trunkR) < 0.4,
			"a round trunk's clue sits on its round bark"
		)
	end)

	t.test("the world's trees as section trees stay inside the part budget", function()
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local v1, v2, n = 0, 0, 0
		for _, spot in ipairs(WorldPlan.Trees()) do
			local def = WoodData.Get(spot.woodId)
			local p = spot.position
			local seed = Kit.seedAt(p.X, p.Z)
			local size = TreeLogic.SizeFor(Kit.rng(seed + 101):next())
			v1 += #parts(TreeArt.Build(def, seed, size.scale))
			v2 += TreeGen.PartCount(TreeGen.Skeleton(def.id, seed, TreeGen.ScaleFor(size.name)))
			n += 1
		end
		t.ok(n > 400, "the world's tree spots")
		local avg = v2 / n
		print(
			string.format(
				"    world trees: %d spots, v1 %d parts, v2 %d parts (avg %.1f, %+d, x%.2f)",
				n,
				v1,
				v2,
				avg,
				v2 - v1,
				v2 / v1
			)
		)
		t.ok(avg <= 48, string.format("the weighted average is %.1f parts", avg))
		-- Bigger trees for at most a fifth more parts than today's, on the
		-- same spots (500 spots: +2,850, x1.16, which keeps a 27,874-part
		-- world under §16's 31k; the forest ring's 775 spots: x1.18).
		t.ok(v2 <= v1 * 1.2, string.format("section trees cost x%.2f today's trees' parts", v2 / v1))
	end)
end
