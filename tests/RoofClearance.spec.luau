--!nocheck
-- T404: porch and awning roofs stay outside the walls and under the main eave, and a second roof never
-- shows through a building's front. Pure maths on the built models (no workspace raycast: a ray against
-- each part's box).
--   a) once the town mesh has dressed a shop, no visible Awning*, Porch* or door-frame part is left over it
--   b) on the parts-only shops every awning or porch roof part stands at or in front of the wall face, under
--      the main eave, at a 15 to 25 degree pitch
--   c) a ray straight up from the floor grid inside each shop hits no porch roof, and no roof part under
--      the main roof (the first roof or ceiling hit is the roof or ceiling itself)
--   d) the main eave stands 1 stud (plus or minus 0.1) out from each wall
-- Everything runs at the shops' own Scale (1.5), at 2.25, and the Dealership (built at its real size, 1) at 1.
-- The code-built Sawmill (mill shed, lean-to over the log slip) runs the same four checks at 1.5 and 2.25.
return function(t)
	local roblox = t.roblox
	local V3, C3 = roblox.Vector3, roblox.Color3
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local TownMeshes = t.load("ReplicatedStorage/Shared/Art/TownMeshes")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local ShopFacade = t.load("ReplicatedStorage/Shared/Art/ShopFacade")

	local ACCENT = C3.fromRGB(120, 80, 60)
	-- (kind, scales): the Dealership's facade and hall are in absolute studs, so it only builds at 1
	local CASES = {
		{ kind = "ToolShed", scales = { 1.5, 2.25 } },
		{ kind = "HearthAndHome", scales = { 1.5, 2.25 } },
		{ kind = "Sparkworks", scales = { 1.5, 2.25 } },
		{ kind = "Dealership", scales = { 1 } },
	}
	local EPS = 1e-4

	local function withMeshes(fn)
		MeshKit.Reset()
		TownMeshes.ResetFallbacks()
		MeshKit.Override = function(_id, name, size)
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	local function partsOf(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- A part's world-space bounding box.
	local function bounds(p)
		local cf, s = p.CFrame, p.Size / 2
		local lo, hi
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					local c = cf * V3.new(s.X * x, s.Y * y, s.Z * z)
					lo = if lo then lo:Min(c) else c
					hi = if hi then hi:Max(c) else c
				end
			end
		end
		return lo, hi
	end

	-- The distance along a ray where it enters the part's box (nil on a miss), exact for a rotated part.
	local function rayBox(origin, dir, p)
		local o = p.CFrame:PointToObjectSpace(origin)
		local d = p.CFrame:VectorToObjectSpace(dir)
		local half = p.Size / 2
		local tMin, tMax = -math.huge, math.huge
		for _, axis in ipairs({ "X", "Y", "Z" }) do
			local oa, da, h = o[axis], d[axis], half[axis]
			if math.abs(da) < 1e-9 then
				if oa < -h or oa > h then
					return nil
				end
			else
				local t0, t1 = (-h - oa) / da, (h - oa) / da
				if t0 > t1 then
					t0, t1 = t1, t0
				end
				tMin, tMax = math.max(tMin, t0), math.min(tMax, t1)
				if tMin > tMax then
					return nil
				end
			end
		end
		if tMax < 0 then
			return nil
		end
		return math.max(tMin, 0)
	end

	-- An awning or porch ROOF part. The posts under one hold it up and are not the roof (PorchPost is the
	-- Hearth & Home's timber post inside its front wall).
	local function isPorchRoof(name)
		return (
			string.sub(name, 1, 6) == "Awning"
			or string.sub(name, 1, 5) == "Porch"
			or string.sub(name, 1, 6) == "Canopy"
		) and string.sub(name, -4) ~= "Post"
	end
	-- What a mesh dressing must not leave visible over its own porch and door frame.
	local function isPorchOrFrame(name)
		return string.sub(name, 1, 6) == "Awning"
			or string.sub(name, 1, 5) == "Porch"
			or string.sub(name, 1, 9) == "DoorFrame"
			or string.sub(name, 1, 8) == "DoorPost"
			or name == "DoorThreshold"
	end
	local function isRoofClass(name)
		return isPorchRoof(name) or string.sub(name, 1, 4) == "Roof"
	end

	local function build(kind, scale)
		return BuildingArt.Shop(kind, kind, ACCENT, scale), BuildingArt.FacadeSpec(kind, scale, ACCENT)
	end

	for _, case in ipairs(CASES) do
		for _, scale in ipairs(case.scales) do
			local label = string.format("%s at scale %s", case.kind, tostring(scale))

			t.test(
				"RoofClearance: "
					.. label
					.. ": porch roofs stand out of the walls, under the eave, at 15 to 25 degrees",
				function()
					local model, spec = build(case.kind, scale)
					t.eq(model:GetAttribute("TownMesh"), nil, "parts only")
					local n = 0
					for _, p in ipairs(partsOf(model)) do
						if isPorchRoof(p.Name) then
							n += 1
							local lo, hi = bounds(p)
							-- the wall's outside face is at frontZ (the street side is -Z): nothing of the roof is behind it
							t.ok(
								hi.Z <= spec.frontZ + EPS,
								p.Name .. " back edge is in front of the wall: " .. hi.Z .. " vs " .. spec.frontZ
							)
							t.ok(hi.Y <= spec.wallTop - 0.2 + EPS, p.Name .. " top is under the main eave: " .. hi.Y)
							t.ok(lo.Y > spec.groundY, p.Name .. " is in the air")
							if p.Name == "AwningStripe" then
								local pitch = math.deg(math.abs((p.CFrame:ToEulerAnglesXYZ())))
								t.ok(
									pitch >= 15 - 1e-3 and pitch <= 25,
									p.Name .. " pitch is 15 to 25 degrees: " .. pitch
								)
							end
						end
					end
					t.ok(n > 0, "there is an awning to measure")
				end
			)

			t.test(
				"RoofClearance: " .. label .. ": a ray up from the floor grid hits no porch roof and no second roof",
				function()
					local model, spec = build(case.kind, scale)
					local roofs = {}
					for _, p in ipairs(partsOf(model)) do
						if isRoofClass(p.Name) then
							table.insert(roofs, p)
						end
					end
					local up = V3.new(0, 1, 0)
					local step = 2
					local inset = 0.6
					local x0, z0 = -spec.halfW + inset, spec.frontZ + inset
					local rays = 0
					local x = x0
					while x <= spec.halfW - inset do
						local z = z0
						while z <= -spec.frontZ - inset do
							rays += 1
							local origin = V3.new(x, spec.groundY + 0.1, z)
							local mainY = math.huge
							local others = {}
							for _, p in ipairs(roofs) do
								local d = rayBox(origin, up, p)
								if d then
									if isPorchRoof(p.Name) then
										error(
											string.format(
												"%s: a ray up from (%.1f, %.1f) hits the porch roof %s",
												label,
												x,
												z,
												p.Name
											),
											0
										)
									elseif p.Name == "Roof" then
										mainY = math.min(mainY, origin.Y + d)
									else
										table.insert(others, { name = p.Name, y = origin.Y + d })
									end
								end
							end
							if mainY == math.huge then
								error(string.format("%s: a ray up from (%.1f, %.1f) meets no roof", label, x, z), 0)
							end
							for _, o in ipairs(others) do
								if o.y < mainY - EPS then
									error(
										string.format(
											"%s: %s at y %.2f is a second roof under the main roof (y %.2f) over (%.1f, %.1f)",
											label,
											o.name,
											o.y,
											mainY,
											x,
											z
										),
										0
									)
								end
							end
							z += step
						end
						x += step
					end
					t.ok(rays > 100, "the grid covers the floor: " .. rays .. " rays")
				end
			)

			t.test("RoofClearance: " .. label .. ": the main eave stands 1 stud out from each wall", function()
				local model = build(case.kind, scale)
				local wallLo, wallHi, roofLo, roofHi
				for _, p in ipairs(partsOf(model)) do
					if p.Name == "Wall" or p.Name == "Roof" then
						local lo, hi = bounds(p)
						if p.Name == "Wall" then
							wallLo = if wallLo then wallLo:Min(lo) else lo
							wallHi = if wallHi then wallHi:Max(hi) else hi
						else
							roofLo = if roofLo then roofLo:Min(lo) else lo
							roofHi = if roofHi then roofHi:Max(hi) else hi
						end
					end
				end
				local function near(name, got)
					t.ok(
						math.abs(got - 1) <= 0.1 + EPS,
						string.format("%s eave overhang is %.3f (want 1 +- 0.1)", name, got)
					)
				end
				near("east", roofHi.X - wallHi.X)
				near("west", wallLo.X - roofLo.X)
				near("back", roofHi.Z - wallHi.Z)
				near("front", wallLo.Z - roofLo.Z)
			end)
		end
	end

	-- (a) the shops that have an uploaded mesh: the mesh brings its own porch roof and door frame
	for _, kind in ipairs({ "ToolShed", "HearthAndHome" }) do
		for _, scale in ipairs({ 1.5, 2.25 }) do
			t.test(
				string.format(
					"RoofClearance: %s at scale %s: with the mesh dressing no awning, porch or door frame stays visible",
					kind,
					tostring(scale)
				),
				function()
					withMeshes(function()
						local model = build(kind, scale)
						t.ok(model:GetAttribute("TownMesh") ~= nil, "the mesh dressing succeeded")
						for _, p in ipairs(partsOf(model)) do
							if isPorchOrFrame(p.Name) then
								t.ok(p.Transparency >= 1, p.Name .. " is still visible over the mesh")
							end
						end
					end)
				end
			)
		end
		t.test("RoofClearance: " .. kind .. ": the parts-only fallback keeps its awning and door frame", function()
			local model = build(kind, 1.5)
			t.eq(model:GetAttribute("TownMesh"), nil)
			local awning, posts = 0, 0
			for _, p in ipairs(partsOf(model)) do
				if p.Name == "AwningStripe" then
					awning += 1
				elseif p.Name == "DoorPost" then
					posts += 1
				end
			end
			t.eq(awning, 6, "six awning stripes")
			t.eq(posts, 2, "two door posts")
		end)
	end

	-- The code-built Sawmill (the mill shed, the office cabin on its west and the lean-to over the log slip on its east
	-- at design size: shed x -11..11, z -11.5..13, walls to y 13). It has no awning; its shed roof is the lean-to.
	for _, scale in ipairs({ 1.5, 2.25 }) do
		local label = "Sawmill at scale " .. tostring(scale)
		local function shed(model)
			-- the mill shed's walls and gables (the office cabin's walls are further out than |x| 11.7)
			local out = {}
			for _, p in ipairs(partsOf(model)) do
				if p.Name == "Wall" or p.Name == "Gable" then
					local lo, hi = bounds(p)
					if hi.X <= 11.4 * scale and lo.X >= -11.7 * scale then
						table.insert(out, p)
					end
				end
			end
			return out
		end

		t.test(
			"RoofClearance: "
				.. label
				.. ": the lean-to roof stands outside the east wall, 15 to 25 degrees, under the eave",
			function()
				local model = BuildingArt.Sawmill(scale)
				t.eq(model:GetAttribute("TownMesh"), nil, "parts only")
				local wallX = -math.huge
				for _, p in ipairs(shed(model)) do
					local _, hi = bounds(p)
					wallX = math.max(wallX, hi.X)
				end
				local found = 0
				for _, p in ipairs(partsOf(model)) do
					if p.Name == "Roof" and p.CFrame.Position.X > 11.4 * scale then
						found += 1
						local lo, hi = bounds(p)
						t.ok(lo.X >= wallX - EPS, "its back edge is outside the east wall: " .. lo.X .. " vs " .. wallX)
						t.ok(hi.Y <= 13 * scale - 0.2 + EPS, "its top is under the main eave: " .. hi.Y)
						local pitch = math.deg(math.acos(p.CFrame.UpVector.Y))
						t.ok(pitch >= 15 and pitch <= 25, "pitch " .. pitch)
					end
				end
				t.eq(found, 1, "one lean-to roof")
			end
		)

		t.test("RoofClearance: " .. label .. ": a ray up from the mill shed floor hits no second roof", function()
			local model = BuildingArt.Sawmill(scale)
			local roofs = {}
			for _, p in ipairs(partsOf(model)) do
				if isRoofClass(p.Name) then
					table.insert(roofs, p)
				end
			end
			local up = V3.new(0, 1, 0)
			local rays = 0
			local x = -11 * scale + 0.6
			while x <= 11 * scale - 0.6 do
				local z = -11.5 * scale + 0.6
				while z <= 13 * scale - 0.6 do
					rays += 1
					local origin = V3.new(x, 1 * scale + 0.1, z)
					local mainY = math.huge
					local others = {}
					for _, p in ipairs(roofs) do
						local d = rayBox(origin, up, p)
						if d then
							if isPorchRoof(p.Name) then
								error(label .. ": a ray hits the porch roof " .. p.Name, 0)
							elseif p.Name == "Roof" then
								mainY = math.min(mainY, origin.Y + d)
							else
								table.insert(others, origin.Y + d)
							end
						end
					end
					t.ok(mainY < math.huge, "the shed has a roof over (" .. x .. ", " .. z .. ")")
					for _, y in ipairs(others) do
						t.ok(y >= mainY - EPS, "no second roof under the main roof")
					end
					z += 2
				end
				x += 2
			end
			t.ok(rays > 100, "the grid covers the floor: " .. rays)
		end)

		t.test("RoofClearance: " .. label .. ": the shed's eave stands 1 stud out from each wall", function()
			local model = BuildingArt.Sawmill(scale)
			local wallLo, wallHi, roofLo, roofHi
			for _, p in ipairs(shed(model)) do
				local lo, hi = bounds(p)
				wallLo = if wallLo then wallLo:Min(lo) else lo
				wallHi = if wallHi then wallHi:Max(hi) else hi
			end
			for _, p in ipairs(partsOf(model)) do
				if p.Name == "Roof" and math.abs(p.CFrame.Position.X) < 11.4 * scale then
					local lo, hi = bounds(p)
					roofLo = if roofLo then roofLo:Min(lo) else lo
					roofHi = if roofHi then roofHi:Max(hi) else hi
				end
			end
			local function near(name, got)
				t.ok(
					math.abs(got - 1) <= 0.1 + EPS,
					string.format("%s eave overhang is %.3f (want 1 +- 0.1)", name, got)
				)
			end
			near("east", roofHi.X - wallHi.X)
			near("west", wallLo.X - roofLo.X)
			near("back", roofHi.Z - wallHi.Z)
			near("front", wallLo.Z - roofLo.Z)
		end)

		t.test(
			"RoofClearance: " .. label .. ": with the mesh dressing no awning, porch or door frame stays visible",
			function()
				withMeshes(function()
					local model = BuildingArt.Sawmill(scale)
					t.ok(model:GetAttribute("TownMesh") ~= nil, "the mesh dressing succeeded")
					for _, p in ipairs(partsOf(model)) do
						if isPorchOrFrame(p.Name) then
							t.ok(p.Transparency >= 1, p.Name .. " is still visible over the mesh")
						end
					end
				end)
			end
		)
	end

	t.test("RoofClearance: the awning pitch is the shared 15 degrees and the Dealership canopy stays", function()
		t.ok(math.abs(math.deg(ShopFacade.Pitch) - 15) < 1e-6)
		local a = ShopFacade.DealerAwning
		t.ok(math.deg(a.tilt) >= 15 and math.deg(a.tilt) <= 25, "DealerAwning is " .. math.deg(a.tilt) .. " degrees")
		t.eq(a.backY, 12.15)
		t.eq(a.reach, 4.8)
	end)

	-- The part-built porch and door frame. PorchPost is the Hearth's post inside the front wall, not this.
	local function isSecondPorch(name)
		return string.sub(name, 1, 6) == "Awning"
			or string.sub(name, 1, 9) == "DoorFrame"
			or string.sub(name, 1, 8) == "DoorPost"
			or name == "DoorThreshold"
	end

	-- MapBuilder does not wait for meshes. Dress returns before TownMesh is set, ShopFacade then
	-- builds the awning, and the swap dresses the mesh later. That swap used to leave the awning
	-- posts as invisible solids and destroy the door and lanterns added in between.
	t.test("RoofClearance: a mesh that lands after the facade leaves no porch and keeps the door", function()
		MeshKit.Reset()
		TownMeshes.ResetFallbacks()
		MeshKit.Override = nil
		local jobs = {}
		local savedScheduler = MeshKit.Scheduler
		local savedEngine = MeshKit.EngineLoad
		MeshKit.Scheduler = {
			spawn = function(fn)
				table.insert(jobs, fn)
			end,
			wait = function() end,
			clock = os.clock,
		}
		MeshKit.EngineLoad = function(_meshId, _fidelity)
			local part = roblox.Instance.new("MeshPart")
			part.Size = roblox.Vector3.new(4, 4, 4)
			return part, nil
		end
		local function meshPart(_id, name, size)
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local function runJobs()
			local n = 0
			while #jobs > 0 and n < 40 do
				n += 1
				local batch = jobs
				jobs = {}
				for _, fn in ipairs(batch) do
					fn()
				end
			end
		end
		local function visibleCount(model, name)
			local n = 0
			for _, p in ipairs(partsOf(model)) do
				if p.Name == name and p.Transparency < 1 then
					n += 1
				end
			end
			return n
		end
		local ok, err = pcall(function()
			local expect = {
				ToolShed = { leaf = "BarnDoor", arm = "LampArm" },
				HearthAndHome = { leaf = "DoorLeaf", planter = "Planter" },
			}
			for _, kind in ipairs({ "ToolShed", "HearthAndHome" }) do
				MeshKit.Reset()
				TownMeshes.ResetFallbacks()
				MeshKit.Override = nil
				table.clear(jobs)
				local model = BuildingArt.Shop(kind, kind, ACCENT, 1.5)
				model.Parent = roblox.Instance.new("Folder")
				local before = 0
				for _, p in ipairs(partsOf(model)) do
					if isSecondPorch(p.Name) then
						before += 1
					end
				end
				t.ok(before > 0, kind .. " still builds the awning while the mesh is pending")
				t.eq(model:GetAttribute("TownMesh"), nil, kind .. " has no TownMesh yet")
				MeshKit.Override = meshPart
				runJobs()
				t.ok(model:GetAttribute("TownMesh") ~= nil, kind .. " mesh landed")
				local left = {}
				for _, p in ipairs(partsOf(model)) do
					if isSecondPorch(p.Name) then
						table.insert(
							left,
							string.format(
								"%s transparency %s CanCollide %s",
								p.Name,
								tostring(p.Transparency),
								tostring(p.CanCollide)
							)
						)
					end
				end
				t.eq(left, {}, kind .. " porch and door frame are gone, not left as invisible solids")
				local want = expect[kind]
				t.ok(visibleCount(model, want.leaf) >= 1, kind .. " door leaf is still visible")
				if want.arm then
					t.ok(visibleCount(model, want.arm) >= 2, kind .. " lantern arms are still visible")
				end
				if want.planter then
					t.ok(visibleCount(model, want.planter) >= 2, kind .. " planters are still visible")
				end
			end
		end)
		MeshKit.Scheduler = savedScheduler
		MeshKit.EngineLoad = savedEngine
		MeshKit.Override = nil
		MeshKit.Reset()
		TownMeshes.ResetFallbacks()
		if not ok then
			error(err, 0)
		end
	end)
end
