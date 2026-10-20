--!nocheck
-- A placed blueprint is the blueprint's boxes, where its ghost drew them: the
-- Shed (and every PlotData blueprint) at all four turns, in every fill state
-- (finished, empty, one unit, half, full, and filled after it was turned), and
-- when it comes back from an old save. Every part of the placed model keeps
-- its ghost box's CFrame relative to the root (0.05 studs, 1 degree) and the
-- walls and roof never sit more than 0.05 inside the floor.
return function(t)
	local roblox = t.roblox
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local BuildCost = t.shared("BuildCost")
	local BlueprintModels = t.shared("BlueprintModels")
	local MeshKit = t.shared("Art/MeshKit")
	local Util = t.shared("Util")
	local ProfileSchema = t.server("ProfileSchema")

	local POS_TOL, ROT_TOL = 0.05, 1 -- studs, degrees
	local PLOT = CFrame.new(-212, 6, 340) * CFrame.Angles(0, math.rad(23), 0)

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

	local function angleBetween(a, b)
		local _, angle = (a:Inverse() * b):ToAxisAngle()
		return math.deg(math.abs(angle))
	end

	local function rel(model, part)
		return model.PrimaryPart.CFrame:ToObjectSpace(part.CFrame)
	end

	-- PlotService.buildItem and its fill step, as the server runs them: the same
	-- BlueprintModels calls in the same order, on a saved item.
	local function build(item)
		local bp = PlotLogic.Blueprint(item.blueprintId)
		local model = BlueprintModels.Build(bp, false)
		if bp.kit then
			model:SetAttribute("Kit", true)
			if item.fill then
				model:SetAttribute("FillUnits", BuildCost.TakenOf(bp, item))
			end
			BlueprintModels.ApplySize(model, bp, item.len, item.lenX, item.lenZ)
		end
		BlueprintModels.Place(model, PLOT, item.x, item.z, item.rot, item.y)
		if bp.kit then
			BlueprintModels.Refresh(model, item.wood, item.paint, if PlotLogic.IsBuilt(bp, item) then nil else true)
		end
		return model, bp
	end

	-- The server's fill step on an already placed model.
	local function fillTo(model, bp, item, units)
		item.fill = { units = units }
		model:SetAttribute("FillUnits", BuildCost.TakenOf(bp, item))
		BlueprintModels.Refresh(model, item.wood, item.paint, not PlotLogic.IsBuilt(bp, item))
	end

	local function ghostOf(bp, item)
		local ghost = BlueprintModels.Build(bp, true)
		BlueprintModels.Place(ghost, PLOT, item.x, item.z, item.rot, item.y)
		return ghost
	end

	local function expectMatch(model, ghost, bp, label)
		for i = 1, #bp.boxes do
			local g, f = ghost:FindFirstChild("Part" .. i), model:FindFirstChild("Part" .. i)
			t.ok(g and f, label .. " Part" .. i .. " exists in both")
			if g and f then
				local a, b = rel(ghost, g), rel(model, f)
				t.ok(
					(a.Position - b.Position).Magnitude <= POS_TOL,
					label .. " Part" .. i .. " position " .. tostring(a.Position) .. " vs " .. tostring(b.Position)
				)
				t.ok(angleBetween(a, b) <= ROT_TOL, label .. " Part" .. i .. " rotation")
				t.ok((g.Size - f.Size).Magnitude <= POS_TOL, label .. " Part" .. i .. " size")
				-- the world pose too: the same root, the same offset
				t.ok(
					(g.CFrame.Position - f.CFrame.Position).Magnitude <= POS_TOL
						and angleBetween(g.CFrame, f.CFrame) <= ROT_TOL,
					label .. " Part" .. i .. " world CFrame"
				)
			end
		end
		t.ok(
			(model.PrimaryPart.CFrame.Position - ghost.PrimaryPart.CFrame.Position).Magnitude <= POS_TOL
				and angleBetween(model.PrimaryPart.CFrame, ghost.PrimaryPart.CFrame) <= ROT_TOL,
			label .. " root"
		)
		-- Nothing else is in the model that a ghost lacks: no stray prop, log, beam or slab.
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and child.Name ~= "Root" and string.sub(child.Name, 1, 4) ~= "Part" then
				t.ok(child:IsA("MeshPart"), label .. " has an unexpected part " .. child.Name)
			end
		end
	end

	-- The deepest any part of a building goes into its base slab, in the root's own space.
	local function sunkInto(model, base, part)
		local function extent(p)
			local c, s = rel(model, p), p.Size
			-- upright quarter-turns only: half extents along the root's axes
			local ex = math.abs(c.RightVector.X) * s.X / 2
				+ math.abs(c.UpVector.X) * s.Y / 2
				+ math.abs(c.LookVector.X) * s.Z / 2
			local ey = math.abs(c.RightVector.Y) * s.X / 2
				+ math.abs(c.UpVector.Y) * s.Y / 2
				+ math.abs(c.LookVector.Y) * s.Z / 2
			local ez = math.abs(c.RightVector.Z) * s.X / 2
				+ math.abs(c.UpVector.Z) * s.Y / 2
				+ math.abs(c.LookVector.Z) * s.Z / 2
			return c.Position, Vector3.new(ex, ey, ez)
		end
		local ap, ae = extent(base)
		local bp, be = extent(part)
		return math.min(ap.X + ae.X, bp.X + be.X) - math.max(ap.X - ae.X, bp.X - be.X),
			math.min(ap.Y + ae.Y, bp.Y + be.Y) - math.max(ap.Y - ae.Y, bp.Y - be.Y),
			math.min(ap.Z + ae.Z, bp.Z + be.Z) - math.max(ap.Z - ae.Z, bp.Z - be.Z)
	end

	local function fillStates(bp)
		local units = bp.woodUnits or 1
		local states = { { name = "finished (no fill)", fill = nil } }
		table.insert(states, { name = "empty", fill = { units = 0 } })
		table.insert(states, { name = "1 unit", fill = { units = math.min(1, units) } })
		table.insert(states, { name = "half", fill = { units = math.floor(units / 2) } })
		table.insert(states, { name = "full", fill = { units = units } })
		return states
	end

	t.test("every blueprint: each filled part is its ghost box, at every turn and in every fill state", function()
		withMeshes(function()
			local n = 0
			for _, bp in ipairs(PlotData.Blueprints) do
				for rot = 0, 3 do
					for _, state in ipairs(bp.kit and fillStates(bp) or { { name = "built", fill = nil } }) do
						local item = {
							uid = "u",
							blueprintId = bp.id,
							x = 7,
							z = -11,
							rot = rot,
							fill = state.fill and { units = state.fill.units } or nil,
							wood = if bp.kit then "birch" else nil,
						}
						local model = build(item)
						expectMatch(model, ghostOf(bp, item), bp, bp.id .. " rot " .. rot .. " " .. state.name)
						n += 1
					end
				end
			end
			t.ok(n > 100, "combinations checked: " .. n)
		end)
	end)

	t.test("the Shed: a hologram while empty, faded wood with one unit, solid when full", function()
		withMeshes(function()
			local bp = PlotData.Blueprint("Shed")
			for rot = 0, 3 do
				local item =
					{ uid = "s", blueprintId = "Shed", x = 0, z = 0, rot = rot, fill = { units = 0 }, wood = nil }
				local model = build(item)
				local part = model:FindFirstChild("Part2")
				t.eq(part:GetAttribute("Holo"), true, "rot " .. rot .. " empty: hologram")
				fillTo(model, bp, item, 1)
				item.wood = "birch"
				fillTo(model, bp, item, 1)
				t.ok(part:GetAttribute("Holo") ~= true, "rot " .. rot .. " 1 unit: real wood, not the blue")
				t.ok(part.Transparency > 0 and part.Transparency < 1, "rot " .. rot .. " 1 unit: faded")
				fillTo(model, bp, item, bp.woodUnits)
				t.eq(part.Transparency, 0, "rot " .. rot .. " full: solid")
				t.eq(part.CanCollide, true, "rot " .. rot .. " full: collides")
			end
		end)
	end)

	t.test("a Shed turned while empty, then filled step by step, still matches its ghost", function()
		withMeshes(function()
			local bp = PlotData.Blueprint("Shed")
			for from = 0, 3 do
				for to = 0, 3 do
					local item = {
						uid = "s",
						blueprintId = "Shed",
						x = 4,
						z = 6,
						rot = from,
						fill = { units = 0 },
						wood = "oak",
					}
					local model = build(item)
					item.rot = to
					BlueprintModels.Place(model, PLOT, item.x, item.z, item.rot, item.y) -- PlotService.placeModel
					for _, units in ipairs({ 1, 30, 59, 60 }) do
						fillTo(model, bp, item, units)
						expectMatch(model, ghostOf(bp, item), bp, "turned " .. from .. "->" .. to .. " then " .. units)
					end
				end
			end
		end)
	end)

	t.test(
		"old saves: every rot an old or hand-edited save can hold loads to a quarter turn that matches the ghost",
		function()
			withMeshes(function()
				local bp = PlotData.Blueprint("Shed")
				local rots = { 0, 1, 2, 3, 4, 5, -1, -2, -3, -4, 1.5, 2.9, -0.5, 7, 400 }
				local data = Util.deepCopy(ProfileSchema.Template)
				data.plot.claimed = true
				data.plot.placed = {}
				for i, rot in ipairs(rots) do
					table.insert(data.plot.placed, {
						uid = "old" .. i,
						blueprintId = "Shed",
						x = 3 * i,
						z = -2 * i,
						rot = rot,
						-- the oldest sheds had no fill, paid, paint, wood or y at all
					})
				end
				-- junk that must not load as a shed
				table.insert(data.plot.placed, { uid = "bad1", blueprintId = "Shed", x = 0, z = 0, rot = 0 / 0 })
				table.insert(data.plot.placed, { uid = "bad2", blueprintId = "Shed", x = 0, z = 0, rot = math.huge })
				table.insert(data.plot.placed, { uid = "bad3", blueprintId = "Shed", x = 0, z = 0 })
				ProfileSchema.Migrate(data)
				t.eq(#data.plot.placed, #rots, "the junk entries are dropped, the real ones kept")
				for i, item in ipairs(data.plot.placed) do
					t.ok(
						item.rot == math.floor(item.rot) and item.rot >= 0 and item.rot <= 3,
						"rot " .. rots[i] .. " -> " .. item.rot
					)
					t.eq(item.rot, math.floor(rots[i]) % 4, "rot " .. rots[i] .. " normalises by floor then mod 4")
					-- as an old finished shed, as an empty plan, a half-filled one and a full one
					for _, fill in ipairs({ false, 0, 30, 60 }) do
						local copy = Util.deepCopy(item)
						if fill ~= false then
							copy.fill = { units = fill }
							copy.wood = "birch"
						end
						local model = build(copy)
						expectMatch(
							model,
							ghostOf(bp, copy),
							bp,
							"old save rot " .. rots[i] .. " fill " .. tostring(fill)
						)
					end
				end
			end)
		end
	)

	t.test("an old save with a fill of the old shape or an unknown wood still loads the same boxes", function()
		withMeshes(function()
			local bp = PlotData.Blueprint("Shed")
			local data = Util.deepCopy(ProfileSchema.Template)
			data.plot.claimed = true
			data.plot.placed = {
				{
					uid = "a",
					blueprintId = "Shed",
					x = 0,
					z = 0,
					rot = 1,
					fill = { units = 12 },
					wood = "no-such-wood",
					paid = 240,
				},
				{ uid = "b", blueprintId = "Shed", x = 20, z = 0, rot = 2, fill = {}, paint = "junk" },
				{ uid = "c", blueprintId = "Shed", x = 40, z = 0, rot = 3, fill = { units = -5 }, wood = 7 },
			}
			ProfileSchema.Migrate(data)
			t.ok(#data.plot.placed >= 1, "kept some")
			for _, item in ipairs(data.plot.placed) do
				local model = build(item)
				expectMatch(model, ghostOf(bp, item), bp, "old save " .. item.uid)
			end
		end)
	end)

	t.test(
		"the Shed's walls and roof sit no more than 0.05 inside its floor, ghost and placed, at every turn",
		function()
			withMeshes(function()
				local checked = 0
				for _, bp in ipairs(PlotData.Blueprints) do
					if bp.id == "Shed" or (bp.category == "Buildings" and bp.kit) then
						for rot = 0, 3 do
							for _, fill in ipairs({ 0, 1, bp.woodUnits or 1 }) do
								local item = {
									uid = "f",
									blueprintId = bp.id,
									x = 2,
									z = 3,
									rot = rot,
									fill = { units = fill },
									wood = "birch",
								}
								for _, model in ipairs({ ghostOf(bp, item), (build(item)) }) do
									local floor = model:FindFirstChild("Part1")
									-- Part1 is the floor slab of the Shed; other buildings are checked only when it is flat
									if floor and floor.Size.Y <= 2.1 then
										for i = 2, #bp.boxes do
											local part = model:FindFirstChild("Part" .. i)
											local ox, oy, oz = sunkInto(model, floor, part)
											checked += 1
											t.ok(
												not (
														ox > POS_TOL + 1e-3
														and oy > POS_TOL + 1e-3
														and oz > POS_TOL + 1e-3
													),
												bp.id
													.. " rot "
													.. rot
													.. " Part"
													.. i
													.. " sinks "
													.. string.format("%.2f", oy)
											)
										end
									end
								end
							end
						end
					end
				end
				t.ok(checked >= 4 * 3 * 2 * 4, "parts checked: " .. checked)
			end)
		end
	)

	t.test("a placed Shed holds only the floor, three walls and the roof: nothing else dresses it", function()
		withMeshes(function()
			local item =
				{ uid = "x", blueprintId = "Shed", x = 0, z = 0, rot = 0, fill = { units = 60 }, wood = "birch" }
			local model = build(item)
			local names = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(names, d.Name)
				end
			end
			table.sort(names)
			t.eq(names, { "Part1", "Part2", "Part3", "Part4", "Part5", "Root" }, "the parts of a filled Shed")
		end)
	end)
end
