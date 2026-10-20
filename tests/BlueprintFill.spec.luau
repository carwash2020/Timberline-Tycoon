--!nocheck
-- T399: a filled blueprint is the blueprint's boxes, where the ghost drew them.
-- Every PlotData blueprint, at every 90 degree turn on a plot that is itself
-- moved and turned: each part of the placed model (the boxes, and every mesh
-- dressed onto them) keeps the ghost box's place relative to the root, and the
-- shed's walls and roof stand on the floor instead of sinking into it.
return function(t)
	local roblox = t.roblox
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
	local PlotData = t.shared("PlotData")
	local BlueprintModels = t.shared("BlueprintModels")
	local MeshKit = t.shared("Art/MeshKit")

	local POS_TOL, ROT_TOL = 0.05, 1 -- studs, degrees

	local function withMeshes(fn)
		MeshKit.Reset()
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

	-- A plot that is not at the origin and not square to the world.
	local PLOT = CFrame.new(310, 4, -125) * CFrame.Angles(0, math.rad(17), 0)

	-- A blueprint as PlotService builds, places and fills it (no material means
	-- a hologram; FillUnits at the full count is the real wood).
	local function filled(bp, x, z, rot, y)
		local model = BlueprintModels.Build(bp, false)
		if bp.kit then
			model:SetAttribute("Kit", true)
			model:SetAttribute("FillUnits", bp.woodUnits or 1)
			BlueprintModels.ApplySize(model, bp, nil, nil, nil)
			BlueprintModels.ApplyWood(model, "birch")
			BlueprintModels.SetFaded(model, false)
		end
		BlueprintModels.Place(model, PLOT, x, z, rot, y)
		return model
	end

	local function ghostAt(bp, x, z, rot, y)
		local ghost = BlueprintModels.Build(bp, true)
		BlueprintModels.Place(ghost, PLOT, x, z, rot, y)
		return ghost
	end

	local function angleBetween(a, b)
		local _, angle = (a:Inverse() * b):ToAxisAngle()
		return math.deg(math.abs(angle))
	end

	local function rel(model, part)
		return model.PrimaryPart.CFrame:ToObjectSpace(part.CFrame)
	end

	t.test("every blueprint, at every 90 degrees, fills each box where its ghost box is", function()
		withMeshes(function()
			for _, bp in ipairs(PlotData.Blueprints) do
				for rot = 0, 3 do
					local ghost = ghostAt(bp, 6, -10, rot, 0.4)
					local built = filled(bp, 6, -10, rot, 0.4)
					for i = 1, #bp.boxes do
						local g, f = ghost:FindFirstChild("Part" .. i), built:FindFirstChild("Part" .. i)
						local label = bp.id .. " rot " .. rot .. " Part" .. i
						t.ok(g and f, label .. " exists in both")
						if g and f then
							local a, b = rel(ghost, g), rel(built, f)
							t.ok((a.Position - b.Position).Magnitude <= POS_TOL, label .. " position")
							t.ok(angleBetween(a, b) <= ROT_TOL, label .. " rotation")
							t.ok((g.Size - f.Size).Magnitude <= POS_TOL, label .. " size")
						end
					end
					-- The root sits where the plot, the spot and the turn say, once.
					local want = PLOT * CFrame.new(6, 0.4, -10) * CFrame.Angles(0, rot * math.pi / 2, 0)
					t.ok(
						(built.PrimaryPart.CFrame.Position - want.Position).Magnitude <= POS_TOL
							and angleBetween(built.PrimaryPart.CFrame, want) <= ROT_TOL,
						bp.id .. " rot " .. rot .. ": the root is the plot, then the spot, then one turn"
					)
				end
			end
		end)
	end)

	t.test("every dressed mesh keeps its piece's own local place at every turn (no extra turn or shift)", function()
		withMeshes(function()
			for _, bp in ipairs(PlotData.Blueprints) do
				local base = filled(bp, 0, 0, 0, 0)
				local baseRel = {}
				for _, d in ipairs(base:GetChildren()) do
					if d:IsA("MeshPart") then
						table.insert(baseRel, { name = d.Name, cf = rel(base, d) })
					end
				end
				for rot = 1, 3 do
					local built = filled(bp, 8, 12, rot, 0)
					local k = 0
					for _, d in ipairs(built:GetChildren()) do
						if d:IsA("MeshPart") then
							k += 1
							local want = baseRel[k]
							t.ok(
								want ~= nil and want.name == d.Name,
								bp.id .. " rot " .. rot .. ": same meshes in order"
							)
							if want then
								local at = rel(built, d)
								t.ok(
									(at.Position - want.cf.Position).Magnitude <= POS_TOL
										and angleBetween(at, want.cf) <= ROT_TOL,
									bp.id .. " rot " .. rot .. " " .. d.Name .. " keeps its local CFrame"
								)
							end
						end
					end
					t.eq(k, #baseRel, bp.id .. " rot " .. rot .. ": the same number of meshes")
				end
			end
		end)
	end)

	-- Where a box's three extents overlap another's, in studs, in the root's own space.
	local function overlap(a, b)
		local function span(box, axis)
			local c, s = box.offset[axis], box.size[axis]
			return c - s / 2, c + s / 2
		end
		local out = {}
		for _, axis in ipairs({ "X", "Y", "Z" }) do
			local alo, ahi = span(a, axis)
			local blo, bhi = span(b, axis)
			table.insert(out, math.min(ahi, bhi) - math.max(alo, blo))
		end
		return out
	end

	t.test("a building's floor is not entered: no part of it overlaps its base slab by more than 0.05", function()
		local checked = 0
		for _, bp in ipairs(PlotData.Blueprints) do
			if bp.category == "Buildings" then
				-- The base slab: a flat, plain block that covers most of the footprint, its underside on the ground.
				local base = nil
				for _, box in ipairs(bp.boxes) do
					local flat = box.size.Y <= 2.1 and box.shape == nil
					local wide = box.size.X * box.size.Z >= 0.6 * bp.footprint.X * bp.footprint.Y
					if flat and wide and box.offset.Y - box.size.Y / 2 <= 0.05 then
						base = box
						break
					end
				end
				if base and #bp.boxes > 1 then
					checked += 1
					for i, box in ipairs(bp.boxes) do
						if box ~= base then
							local o = overlap(base, box)
							t.ok(
								not (o[1] > POS_TOL + 1e-3 and o[2] > POS_TOL + 1e-3 and o[3] > POS_TOL + 1e-3),
								bp.id .. " Part" .. i .. " sinks " .. string.format("%.2f", o[2]) .. " into the base"
							)
						end
					end
				end
			end
		end
		t.ok(checked >= 1, "the check found at least the Shed")
	end)

	t.test("the Shed: walls stand on the floor, the roof on the walls, nothing lying across it", function()
		local shed = PlotData.Blueprint("Shed")
		local floor, back, left, right, roof = table.unpack(shed.boxes)
		t.ok(
			math.abs(back.offset.Y - back.size.Y / 2 - (floor.offset.Y + floor.size.Y / 2)) <= POS_TOL,
			"back wall on the floor"
		)
		t.ok(
			math.abs(left.offset.Y - left.size.Y / 2 - (floor.offset.Y + floor.size.Y / 2)) <= POS_TOL,
			"left wall on the floor"
		)
		t.ok(
			math.abs(right.offset.Y - right.size.Y / 2 - (floor.offset.Y + floor.size.Y / 2)) <= POS_TOL,
			"right wall on the floor"
		)
		t.ok(
			math.abs(roof.offset.Y - roof.size.Y / 2 - (left.offset.Y + left.size.Y / 2)) <= POS_TOL,
			"roof on the walls"
		)
		for i, box in ipairs(shed.boxes) do
			t.eq(box.shape, nil, "Part" .. i .. " is a plain, upright block")
		end
	end)

	t.test("no ruin, cabin or other world prop stands on a plot's biggest pad or its lawn", function()
		local WorldPlan = t.shared("World/WorldPlan")
		local TerrainGen = t.shared("World/TerrainGen")
		local half = PlotData.Tiers[#PlotData.Tiers].size / 2
		-- T397: the lawn is a distance from the pad, so its corners are round (a piece 75
		-- studs off a pad's corner is not on the lawn: the old square test said it was).
		local function onPlot(x, z, r)
			for _, slot in ipairs(PlotData.Slots) do
				local dx, dz = math.max(math.abs(x - slot.X) - half, 0), math.max(math.abs(z - slot.Y) - half, 0)
				if math.sqrt(dx * dx + dz * dz) <= TerrainGen.PlotLawn + r then
					return true
				end
			end
			return false
		end
		for _, spot in ipairs(WorldPlan.Scenery()) do
			t.ok(not onPlot(spot.center.X, spot.center.Z, spot.radius), spot.kind .. " scenery stands on a plot")
		end
		for _, poi in ipairs(WorldPlan.PointsOfInterest()) do
			local p = poi.cframe.Position
			t.ok(not onPlot(p.X, p.Z, 12), poi.kind .. " " .. poi.id .. " stands on a plot")
		end
	end)
end
