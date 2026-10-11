--!nocheck
-- TreeGen (Shared): the v2 section tree's skeleton (V2_PLAN.md §3a, §3b,
-- §3j). Pure and deterministic, so these pin it for every wood:
--   * the same wood, seed and scale always give the same tree; different
--     seeds give different trees (at least 3 skeletons in 5 seeds);
--   * mature heights land inside the wood's band for every seed and size
--     (small low, large high), an Elder 1.6-1.7x a normal tree and never
--     over 95 studs;
--   * the trunk's base is trunkThickness x scale (within 5%), children are
--     never thicker than their parents;
--   * part budgets (sections plus dress) hold over 200 seeds x 3 sizes and
--     the Elder, and sections stay under maxSections and the hard cap;
--   * the sections form one tree: parents first, joints that meet, every
--     section reachable from the root; nothing below ground; limbs start
--     at least 8 studs up (a truck's roof);
--   * conifer tiers narrow going up; every dress entry rides an existing
--     section and sits on it (leaves within reach of its top);
--   * growth stages hide the deep sections, shrink the rest and stay inside
--     the budget.
return function(t)
	local TreeGen = t.shared("TreeGen")
	local WoodData = t.shared("WoodData")
	local ForestData = t.shared("ForestData")
	local Vector3 = t.roblox.Vector3

	local woods = WoodData.All()
	local SIZES = { TreeGen.SizeLo, 1, TreeGen.SizeHi }
	local ELDER = ForestData.Elder.scale

	local function shapeOf(id)
		return WoodData.Get(id).v2.shape
	end

	-- Every scale a tree can have: the size roll and the Elder.
	local function each(seeds, fn)
		for _, def in ipairs(woods) do
			for _, seed in ipairs(seeds) do
				for _, scale in ipairs(SIZES) do
					fn(def, seed, scale, TreeGen.Skeleton(def.id, seed, scale), false)
				end
				fn(def, seed, ELDER, TreeGen.Skeleton(def.id, seed, ELDER, { elder = true }), true)
			end
		end
	end

	local function range(n)
		local out = {}
		for i = 1, n do
			table.insert(out, i)
		end
		return out
	end

	-- A skeleton as a string, to compare two of them.
	local function signature(skel)
		local parts = { tostring(#skel.sections) }
		for _, s in ipairs(skel.sections) do
			local p = s.cf.Position
			table.insert(
				parts,
				string.format(
					"%d:%s:%.3f,%.3f,%.3f:%.3f:%.3f",
					s.id,
					tostring(s.parent),
					p.X,
					p.Y,
					p.Z,
					s.length,
					s.thickness
				)
			)
			for _, d in ipairs(s.dress) do
				local q = d.cf.Position
				table.insert(parts, string.format("%s%d@%.3f,%.3f,%.3f", d.kind, d.parts, q.X, q.Y, q.Z))
			end
		end
		return table.concat(parts, "|")
	end

	local function corners(s)
		local h = s.thickness / 2
		local out = {}
		for _, y in ipairs({ 0, s.length }) do
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					table.insert(out, s.cf * Vector3.new(sx * h, y, sz * h))
				end
			end
		end
		return out
	end

	t.test("every wood has a v2 shape with the plan's numbers", function()
		for _, def in ipairs(woods) do
			local shape = def.v2 and def.v2.shape
			t.ok(shape, def.id .. " has v2.shape")
			t.ok(#shape.height == 2 and shape.height[1] < shape.height[2], def.id .. " height band")
			t.ok(shape.trunkSegments >= 2, def.id .. ": the trunk is cut into sections")
			t.ok(shape.maxSections <= TreeGen.HardCap, def.id .. ": maxSections under the hard cap")
			t.ok(#shape.leafColors >= 3, def.id .. " leaf colours")
		end
		-- A few of §3a's values, pinned.
		t.eq(shapeOf("oak").height, { 22, 30 })
		t.eq(shapeOf("pine").height, { 45, 60 })
		t.eq(shapeOf("oak").trunkThickness, 2.0)
		t.eq(shapeOf("pine").trunkThickness, 2.6)
		t.eq(shapeOf("lumenwood").trunkThickness, 2.6)
		t.eq(shapeOf("birch").leader, true)
		t.eq(shapeOf("palmwood").lean, 0.2)
		t.eq(TreeGen.HardCap, 40)
	end)

	t.test("the same wood, seed and scale always give the same tree", function()
		local other = t.loader():shared("TreeGen")
		for _, def in ipairs(woods) do
			for _, seed in ipairs({ 1, 77, 4242 }) do
				for _, scale in ipairs({ TreeGen.SizeLo, 1, ELDER }) do
					local a = signature(TreeGen.Skeleton(def.id, seed, scale))
					t.eq(signature(TreeGen.Skeleton(def.id, seed, scale)), a, def.id .. " twice")
					t.eq(signature(other.Skeleton(def.id, seed, scale)), a, def.id .. " from a fresh load")
				end
			end
		end
	end)

	t.test("at least 3 different trees in 5 seeds of every wood", function()
		for _, def in ipairs(woods) do
			local seen, n = {}, 0
			for seed = 1, 5 do
				local sig = signature(TreeGen.Skeleton(def.id, seed, 1))
				if not seen[sig] then
					seen[sig] = true
					n += 1
				end
			end
			t.ok(n >= 3, def.id .. ": only " .. n .. " different trees in 5 seeds")
		end
	end)

	t.test("mature heights are inside the band, small low and large high; Elders 1.6-1.7x", function()
		for _, def in ipairs(woods) do
			local band = shapeOf(def.id).height
			for seed = 1, 40 do
				local small = TreeGen.Skeleton(def.id, seed, TreeGen.SizeLo)
				local normal = TreeGen.Skeleton(def.id, seed, 1)
				local large = TreeGen.Skeleton(def.id, seed, TreeGen.SizeHi)
				for _, skel in ipairs({ small, normal, large }) do
					t.ok(
						skel.height >= band[1] - 0.05 and skel.height <= band[2] + 0.05,
						string.format(
							"%s seed %d x%.2f: %.2f studs, band %d-%d",
							def.id,
							seed,
							skel.scale,
							skel.height,
							band[1],
							band[2]
						)
					)
				end
				t.ok(
					small.height < normal.height and normal.height < large.height,
					def.id .. ": bigger rolls are taller"
				)
				local elder = TreeGen.Skeleton(def.id, seed, ELDER, { elder = true })
				local ratio = elder.height / normal.height
				t.ok(
					(ratio >= 1.6 and ratio <= 1.71) or elder.height >= ForestData.Elder.maxHeight - 0.05,
					string.format("%s seed %d: an Elder is %.2fx", def.id, seed, ratio)
				)
				t.ok(elder.height <= ForestData.Elder.maxHeight + 0.05, def.id .. ": an Elder is capped")
			end
		end
		-- The cap bites on a huge scale.
		t.ok(TreeGen.TargetHeight(shapeOf("pine"), 1, 3, true) <= ForestData.Elder.maxHeight)
		t.eq(ForestData.Elder.maxHeight, 95)
	end)

	t.test("the trunk's base is trunkThickness x scale, and nothing thickens going up", function()
		each({ 1, 2, 3, 9, 31 }, function(def, seed, scale, skel)
			local want = shapeOf(def.id).trunkThickness * scale
			local base = skel.sections[1].thickness
			t.ok(
				math.abs(base / want - 1) <= 0.05,
				string.format("%s seed %d x%.2f: base %.2f, want %.2f", def.id, seed, scale, base, want)
			)
			for _, s in ipairs(skel.sections) do
				if s.parent then
					t.ok(
						s.thickness <= skel.sections[s.parent].thickness + 1e-6,
						def.id .. ": a child thicker than its parent"
					)
				end
				t.ok(s.thickness > 0.2 and s.length > 0.3, def.id .. ": a usable section")
			end
		end)
	end)

	t.test("budgets: sections plus dress over 200 seeds, every size and the Elder", function()
		t.eq(TreeGen.Budgets, {
			oak = 38,
			birch = 32,
			pine = 44,
			maple = 44,
			palmwood = 32,
			frostwood = 60,
			emberwood = 42,
			phantomwood = 44,
			lumenwood = 40,
			lanternwood = 48,
			bogcypress = 44, -- Lane R
			ironwood = 44, -- Lane R
		})
		local line = {}
		for _, def in ipairs(woods) do
			local budget = TreeGen.Budgets[def.id]
			local shape = shapeOf(def.id)
			local most, total, n = 0, 0, 0
			for seed = 1, 200 do
				for _, scale in ipairs({ TreeGen.SizeLo, 1, TreeGen.SizeHi, ELDER }) do
					local skel = TreeGen.Skeleton(def.id, seed, scale, { elder = scale == ELDER })
					local parts = TreeGen.PartCount(skel)
					if parts > budget then
						error(
							string.format("%s seed %d x%.2f: %d parts, budget %d", def.id, seed, scale, parts, budget)
						)
					end
					if #skel.sections > shape.maxSections + (if shape.spire then 1 else 0) then
						error(
							string.format(
								"%s seed %d: %d sections, maxSections %d",
								def.id,
								seed,
								#skel.sections,
								shape.maxSections
							)
						)
					end
					t.ok(#skel.sections <= TreeGen.HardCap, def.id .. ": over the hard cap")
					most = math.max(most, parts)
					total += parts
					n += 1
				end
			end
			table.insert(line, string.format("%s %d (avg %.1f)", def.id, most, total / n))
		end
		print("    section tree parts (most per wood): " .. table.concat(line, ", "))
	end)

	t.test("one connected tree: parents first, joints that meet, all reachable", function()
		each({ 1, 2, 5, 13, 99 }, function(def, seed, scale, skel)
			local sections = skel.sections
			t.eq(sections[1].parent, nil, def.id .. ": section 1 is the root")
			t.eq(sections[1].depth, 0)
			local seenChild = {}
			for i, s in ipairs(sections) do
				t.eq(s.id, i, def.id .. ": ids are 1..n")
				if i > 1 then
					local p = sections[s.parent]
					t.ok(p and s.parent < i, def.id .. ": a parent comes first")
					t.ok(table.find(p.children, s.id), def.id .. ": the parent lists its child")
					t.eq(s.depth, p.depth + 1, def.id .. ": depth counts from the root")
					-- The child starts on its parent's top, sunk in at most half its width.
					local gap = (s.cf.Position - (p.cf * Vector3.new(0, p.length, 0))).Magnitude
					t.ok(gap <= s.thickness / 2 + 1e-3, string.format("%s: a joint %.3f apart", def.id, gap))
				end
				for _, c in ipairs(s.children) do
					t.ok(not seenChild[c], def.id .. ": a section with two parents")
					seenChild[c] = true
					t.eq(sections[c].parent, s.id)
				end
			end
			local reached, stack = {}, { 1 }
			while #stack > 0 do
				local id = table.remove(stack)
				reached[id] = true
				for _, c in ipairs(sections[id].children) do
					table.insert(stack, c)
				end
			end
			for _, s in ipairs(sections) do
				t.ok(reached[s.id], def.id .. ": section " .. s.id .. " can't be reached from the root")
			end
			-- Section 1 stands on the ground, upright.
			t.ok(sections[1].cf.Position.Magnitude < 1e-6, def.id .. ": the trunk starts at the origin")
			t.ok(sections[1].cf.YVector.Y > 0.999, def.id .. ": the trunk's foot is upright")
		end)
	end)

	t.test("nothing below ground; limbs start at least 8 studs up", function()
		each({ 1, 3, 8, 21, 55, 144 }, function(def, seed, scale, skel)
			local shape = shapeOf(def.id)
			for _, s in ipairs(skel.sections) do
				for _, c in ipairs(corners(s)) do
					t.ok(c.Y >= -1e-3, string.format("%s seed %d: section %d dips to %.2f", def.id, seed, s.id, c.Y))
				end
				local top = TreeGen.TopOf(s)
				t.ok(top.Y >= TreeGen.MinEndY, def.id .. ": a section ends near the ground")
				for _, d in ipairs(s.dress) do
					if d.kind ~= "flare" then
						local bottom = if d.points then math.huge else d.cf.Position.Y - d.size.Y / 2
						if d.points then
							for _, p in ipairs(d.points) do
								bottom = math.min(bottom, p.Y)
							end
						elseif d.kind == "tier" or d.kind == "cap" then
							bottom = d.cf.Position.Y
						end
						t.ok(bottom >= 0, string.format("%s: %s dress below ground (%.2f)", def.id, d.kind, bottom))
					end
				end
			end
			if shape.maxDepth > 0 then
				local trunkTop = TreeGen.TopOf(skel.sections[shape.trunkSegments])
				t.ok(
					trunkTop.Y >= TreeGen.FirstBranchMin - 1e-3,
					string.format("%s x%.2f: the first limb starts %.2f up", def.id, scale, trunkTop.Y)
				)
			end
		end)
	end)

	t.test("conifer tiers narrow going up, and frostwood wears snow caps", function()
		for _, id in ipairs({ "pine", "frostwood" }) do
			for _, seed in ipairs({ 1, 4, 16, 64 }) do
				for _, scale in ipairs({ TreeGen.SizeLo, 1, TreeGen.SizeHi, ELDER }) do
					local skel = TreeGen.Skeleton(id, seed, scale, { elder = scale == ELDER })
					local tiers, caps = {}, 0
					for _, s in ipairs(skel.sections) do
						for _, d in ipairs(s.dress) do
							if d.kind == "tier" then
								table.insert(tiers, d)
							elseif d.kind == "cap" then
								caps += 1
							end
						end
					end
					t.eq(#tiers, shapeOf(id).tiers, id .. ": every tier")
					table.sort(tiers, function(a, b)
						return a.cf.Position.Y < b.cf.Position.Y
					end)
					for i = 2, #tiers do
						t.ok(tiers[i].size.X < tiers[i - 1].size.X, id .. ": a tier wider than the one below")
						-- Overlapping: each starts inside the one below.
						t.ok(
							tiers[i].cf.Position.Y < tiers[i - 1].cf.Position.Y + tiers[i - 1].size.Y,
							id .. ": a gap between tiers"
						)
					end
					t.ok(
						tiers[1].cf.Position.Y >= shapeOf(id).firstTierAt * scale - 1e-3,
						id .. ": the trunk's clear below the tiers"
					)
					t.eq(caps, if id == "frostwood" then shapeOf(id).snowCaps else 0, id .. " snow caps")
				end
			end
		end
	end)

	t.test("every dress entry rides an existing section, on it", function()
		each({ 1, 2, 3, 7, 50 }, function(def, seed, scale, skel)
			local shape = shapeOf(def.id)
			local leaf = (shape.leafSize or TreeGen.WispSize) * scale
			for _, s in ipairs(skel.sections) do
				local top = TreeGen.TopOf(s)
				for _, d in ipairs(s.dress) do
					t.eq(d.section, s.id, def.id .. ": dress listed on another section")
					t.ok(d.parts >= 1, def.id .. ": a dress entry makes parts")
					if d.kind == "leaves" or d.kind == "wisp" then
						-- Its section's top is inside the mass (grown by a leaf size).
						local rel = d.cf:PointToObjectSpace(top)
						local half = d.size / 2 + Vector3.one * leaf
						t.ok(
							math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z,
							string.format(
								"%s seed %d: a %s %.1f studs from its section's top",
								def.id,
								seed,
								d.kind,
								rel.Magnitude
							)
						)
					elseif d.kind == "flare" then
						t.eq(s.id, 1, def.id .. ": flares are on the first section")
					elseif d.kind == "mark" or d.kind == "crack" or d.kind == "vein" or d.kind == "ring" then
						t.ok(s.depth < shape.trunkSegments, def.id .. ": bark detail on the trunk")
						local rel = s.cf:PointToObjectSpace(d.cf.Position)
						t.ok(rel.Y >= -0.5 and rel.Y <= s.length + 0.5, def.id .. ": bark detail off its section")
						t.ok(
							math.max(math.abs(rel.X), math.abs(rel.Z)) <= s.thickness * 0.7 + 0.2,
							def.id .. ": bark detail off the bark"
						)
					elseif d.kind == "tier" or d.kind == "cap" then
						t.ok(s.depth < shape.trunkSegments, def.id .. ": tiers ride the trunk")
					elseif d.kind == "frond" or d.kind == "coconut" then
						t.eq(s.id, shape.trunkSegments, def.id .. ": the crown is on the top segment")
						t.ok(
							(d.cf.Position - top).Magnitude <= 2 * scale,
							def.id .. ": the crown sits on the trunk's top"
						)
					elseif d.kind == "pod" then
						t.ok((d.cf.Position - top).Magnitude <= 3 * scale, def.id .. ": a pod hangs from its tip")
					end
				end
			end
		end)
	end)

	t.test("growth stages: deep sections hidden, the rest shrunk, inside the budget", function()
		for _, def in ipairs(woods) do
			local shape = shapeOf(def.id)
			for _, seed in ipairs({ 1, 2, 3 }) do
				local mature = TreeGen.Skeleton(def.id, seed, 1)
				t.eq(TreeGen.AtStage(mature, 1), mature, "stage 1 is the tree itself")
				local lastHeight, lastCount = 0, 0
				for _, s in ipairs(TreeGen.Stages) do
					local skel = TreeGen.AtStage(mature, s)
					t.eq(skel.stage, s)
					local limit = (mature.maxDepth + mature.trunkSegments) * s
					for _, sec in ipairs(skel.sections) do
						t.ok(sec.id == 1 or sec.depth <= limit, def.id .. ": a hidden section shows")
						if sec.parent then
							t.ok(skel.sections[sec.parent], def.id .. ": a section without its parent")
						end
						for _, c in ipairs(corners(sec)) do
							t.ok(c.Y >= -1e-3, def.id .. ": a young tree below ground")
						end
					end
					if s < 1 then
						t.ok(
							math.abs(skel.sections[1].thickness - mature.sections[1].thickness * s) < 1e-6,
							def.id .. ": thickness shrinks by s"
						)
					end
					t.ok(skel.height > lastHeight, def.id .. ": taller each stage")
					t.ok(#skel.sections >= lastCount, def.id .. ": sections come, never go")
					t.ok(TreeGen.PartCount(skel) <= TreeGen.Budgets[def.id], def.id .. ": a young tree over the budget")
					lastHeight, lastCount = skel.height, #skel.sections
					-- A leafy tree has leaves on every tip that shows (a mass
					-- dresses the tips it lists; a young tree's sit on each tip).
					if shape.canopy == "clusters" or shape.canopy == "embers" then
						local covered = {}
						for _, sec in ipairs(skel.sections) do
							for _, d in ipairs(sec.dress) do
								if d.kind == "leaves" then
									for _, id in ipairs(d.tips or { d.section }) do
										covered[id] = true
									end
								end
							end
						end
						for _, sec in ipairs(skel.sections) do
							if #sec.children == 0 and sec.depth > 0 then
								t.ok(covered[sec.id], def.id .. " stage " .. s .. ": a bare tip")
							end
						end
					end
				end
			end
		end
	end)

	t.test("size classes map to the v2 scales", function()
		t.eq(TreeGen.ScaleFor("small"), 0.85)
		t.eq(TreeGen.ScaleFor("normal"), 1)
		t.eq(TreeGen.ScaleFor("large"), 1.15)
		t.eq(TreeGen.ScaleFor("elder"), 1, "anything else is normal")
		t.eq(TreeGen.SizeLo, 0.85)
		t.eq(TreeGen.SizeHi, 1.15)
	end)
end
