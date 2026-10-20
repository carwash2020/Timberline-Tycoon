--!nocheck
-- T380: the blueprint ghost is the whole blueprint (its boxes, no mesh, no
-- extra part) and a blue hologram; a placed blueprint that holds nothing is the
-- same hologram until the first material goes in.
return function(t)
	local roblox = t.roblox
	local fs = require("@lune/fs")
	local PlotData = t.shared("PlotData")
	local BlueprintModels = t.shared("BlueprintModels")
	local MeshKit = t.shared("Art/MeshKit")

	local BLUE = roblox.Color3.fromHex("#4FA8FF")
	local EDGE = roblox.Color3.fromHex("#CFE8FF")
	local BAD = roblox.Color3.fromHex("#FF5A4F")

	-- Every MeshKit mesh is a template-sized MeshPart (no network).
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

	-- A placed, empty blueprint as PlotService builds it.
	local function placed(bp)
		local model = BlueprintModels.Build(bp, false)
		if bp.kit then
			model:SetAttribute("Kit", true)
			model:SetAttribute("FillUnits", 0)
			BlueprintModels.ApplySize(model, bp, nil, nil, nil)
			BlueprintModels.ApplyWood(model, nil)
			BlueprintModels.SetFaded(model, true)
		end
		return model
	end

	local function meshParts(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("MeshPart") then
				n += 1
			end
		end
		return n
	end

	-- The bounds of the gameplay boxes (Root and PartN), meshes left out.
	local function boxBounds(model)
		local probe = roblox.Instance.new("Model")
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("VisualMesh") ~= true and d.Parent == model then
				d:Clone().Parent = probe
			end
		end
		return probe:GetBoundingBox()
	end

	t.test("the ghost has no mesh at all, for every blueprint, with every mesh available", function()
		withMeshes(function()
			for _, bp in ipairs(PlotData.Blueprints) do
				local ghost = BlueprintModels.Build(bp, true)
				t.eq(meshParts(ghost), 0, bp.id .. ": a ghost is boxes only")
				local boxes = 0
				for _, c in ipairs(ghost:GetChildren()) do
					if c:IsA("BasePart") and c.Name ~= "Root" then
						boxes += 1
						t.ok(c.Transparency < 1, bp.id .. " " .. c.Name .. " stays visible")
					end
				end
				t.eq(boxes, #bp.boxes, bp.id .. ": every box, and nothing extra")
			end
		end)
	end)

	t.test("ghost bounds equal the placed blueprint's box bounds on every axis, Wall included", function()
		for _, stubbed in ipairs({ false, true }) do
			local function check()
				for _, bp in ipairs(PlotData.Blueprints) do
					local ghost = BlueprintModels.Build(bp, true)
					local gc, gs = ghost:GetBoundingBox()
					local pc, ps = boxBounds(placed(bp))
					local label = bp.id .. (if stubbed then " (meshes stubbed)" else "")
					t.ok((gc.Position - pc.Position).Magnitude <= 0.05, label .. ": centre")
					t.ok(math.abs(gs.X - ps.X) <= 0.05, label .. ": X")
					t.ok(math.abs(gs.Y - ps.Y) <= 0.05, label .. ": Y")
					t.ok(math.abs(gs.Z - ps.Z) <= 0.05, label .. ": Z")
				end
				-- The 8 stud wall by name: the ghost is the whole 8 x 6 x 1.
				local wall = PlotData.Blueprint("Wall")
				local _, size = BlueprintModels.Build(wall, true):GetBoundingBox()
				t.ok(
					math.abs(size.X - 8) <= 0.05 and math.abs(size.Y - 6) <= 0.05 and math.abs(size.Z - 1) <= 0.05,
					"Wall ghost is 8 x 6 x 1"
				)
			end
			if stubbed then
				withMeshes(check)
			else
				check()
			end
		end
	end)

	t.test("with a mesh stubbed, a placed wall has its mesh and the ghost never does", function()
		withMeshes(function()
			local wall = PlotData.Blueprint("Wall")
			t.ok(meshParts(placed(wall)) > 0, "the placed wall is dressed")
			t.eq(meshParts(BlueprintModels.Build(wall, true)), 0, "the ghost is not")
		end)
	end)

	local function visual(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Root" and d.Transparency < 1 then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("every visual part of a ghost is blue SmoothPlastic at 0.6, casting no shadow, not colliding", function()
		for _, bp in ipairs(PlotData.Blueprints) do
			local ghost = BlueprintModels.Build(bp, true)
			local parts = visual(ghost)
			t.ok(#parts > 0, bp.id .. " has something to see")
			for _, p in ipairs(parts) do
				t.eq(p.Color, BLUE, bp.id .. " " .. p.Name .. " color")
				t.eq(p.Material, roblox.Enum.Material.SmoothPlastic, bp.id .. " material")
				t.ok(math.abs(p.Transparency - 0.6) < 1e-4, bp.id .. " transparency")
				t.eq(p.CastShadow, false, bp.id .. " shadow")
				t.eq(p.CanCollide, false, bp.id .. " collision")
			end
			local light = ghost:FindFirstChild("Hologram")
			t.ok(light ~= nil and light:IsA("Highlight"), bp.id .. " has the highlight")
			t.eq(light.FillColor, BLUE)
			t.ok(math.abs(light.FillTransparency - 0.75) < 1e-4)
			t.eq(light.OutlineColor, EDGE)
			t.eq(light.OutlineTransparency, 0)
			t.eq(light.DepthMode, roblox.Enum.HighlightDepthMode.Occluded)
		end
	end)

	t.test("a fresh placed kit blueprint is the same hologram, collision untouched", function()
		withMeshes(function()
			for _, bp in ipairs(PlotData.Blueprints) do
				if bp.kit then
					local model = placed(bp)
					local parts = visual(model)
					t.ok(#parts > 0, bp.id .. " has something to see")
					for _, p in ipairs(parts) do
						t.eq(p.Color, BLUE, bp.id .. " " .. p.Name .. " color")
						t.eq(p.Material, roblox.Enum.Material.SmoothPlastic, bp.id .. " material")
						t.ok(math.abs(p.Transparency - 0.6) < 1e-4, bp.id .. " transparency")
						t.eq(p.CastShadow, false, bp.id .. " shadow")
					end
				end
			end
		end)
	end)

	t.test("the first material puts the real wood back; a repaint while empty waits for it", function()
		local wall = PlotData.Blueprint("Wall")
		local model = placed(wall)
		BlueprintModels.ApplyWood(model, "oak") -- painted while still empty
		local part = model:FindFirstChild("Part1")
		t.eq(part.Color, BLUE, "still blue while empty")
		model:SetAttribute("FillUnits", 3)
		BlueprintModels.SetFaded(model, true)
		t.ok(part.Color ~= BLUE, "oak wood once a unit is in")
		t.ok(math.abs(part.Transparency - 0.45) < 1e-4, "faded, not a hologram")
		t.eq(model:FindFirstChild("Hologram"), nil, "the highlight is gone")
		t.eq(part.CastShadow, true)
		model:SetAttribute("FillUnits", 8)
		BlueprintModels.SetFaded(model, false)
		t.eq(part.Transparency, 0, "solid when built")
	end)

	t.test("the verdict tint: blue where it fits, BlueprintBad where it does not, never green", function()
		local ghost = BlueprintModels.Build(PlotData.Blueprint("Wall"), true)
		BlueprintModels.HologramTint(ghost, false)
		for _, p in ipairs(visual(ghost)) do
			t.eq(p.Color, BAD)
		end
		t.eq(ghost:FindFirstChild("Hologram").FillColor, BAD)
		BlueprintModels.HologramTint(ghost, true)
		for _, p in ipairs(visual(ghost)) do
			t.eq(p.Color, BLUE)
		end
		t.eq(ghost:FindFirstChild("Hologram").OutlineColor, EDGE)
		local placer = fs.readFile("src/StarterPlayer/StarterPlayerScripts/BlueprintPlacer.luau")
		t.eq(string.find(placer, "Colors.Green", 1, true), nil, "no green tint")
		t.eq(string.find(placer, "Color3.fromRGB(255, 80, 80)", 1, true), nil, "no hardcoded red")
	end)

	t.test("UITheme carries the three hologram colours, equal to BlueprintModels'", function()
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/UITheme.luau")
		for name, hex in pairs({ BlueprintBlue = "#4FA8FF", BlueprintEdge = "#CFE8FF", BlueprintBad = "#FF5A4F" }) do
			t.ok(string.find(src, name .. ' = Color3.fromHex("' .. hex .. '")', 1, true), name)
		end
		t.eq(BlueprintModels.HoloColor, BLUE)
		t.eq(BlueprintModels.HoloEdge, EDGE)
		t.eq(BlueprintModels.HoloBad, BAD)
	end)
end
