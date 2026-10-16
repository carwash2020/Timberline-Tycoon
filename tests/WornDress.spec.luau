--!nocheck
-- The rope ladder's tiles and the V2 blueprint scroll: id 0 keeps the part-built
-- prop, the real ids (or a fake one) take the mesh path, and the pieces sit
-- where the brief puts them.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame, Color3 = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3
	local MiningArt = t.load("ReplicatedStorage/Shared/Mining/MiningArt")
	local BlueprintArt = t.load("ReplicatedStorage/Shared/Art/BlueprintArt")
	local WornModels = t.load("ReplicatedStorage/Shared/Art/WornModels")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")

	local function withMeshes(fn)
		MeshKit.Reset()
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	local function withId(asset, piece, id, fn)
		local p = WornModels.Piece(asset, piece)
		local before = p.meshId
		p.meshId = id
		local ok, err = pcall(fn)
		p.meshId = before
		if not ok then
			error(err, 0)
		end
	end

	local function near(a, b)
		return (a - b).Magnitude < 0.01
	end

	---------------------------------------------------------------------------
	-- The rope ladder
	---------------------------------------------------------------------------

	t.test("rope ladder: id 0 keeps the part-built ladder (rails, rungs, hook), Length 12", function()
		withMeshes(function()
			withId("RopeLadderSeg", "Body", 0, function()
				local ladder = MiningArt.RopeLadder()
				t.eq(ladder:GetAttribute("Length"), 12)
				t.ok(ladder:FindFirstChild("Hook") ~= nil, "the hook stays")
				local rungs = 0
				for _, d in ipairs(ladder:GetChildren()) do
					if d.Name == "Rung" then
						rungs += 1
					end
				end
				t.eq(rungs, 5)
				t.ok(ladder:FindFirstChild("LadderTop") == nil, "no mesh")
			end)
		end)
	end)

	t.test("rope ladder: three 4-stud segments and the top at the brief's centres, rails kept as proxies", function()
		withMeshes(function()
			local ladder = MiningArt.RopeLadder()
			t.eq(ladder:GetAttribute("Length"), 12, "Length stays 12")
			local foot = Vector3.new(0, 0, 0) -- the ladder is built with its foot at the origin
			for i, y in ipairs({ 2, 6, 10 }) do
				local seg = ladder:FindFirstChild("LadderSeg" .. i)
				t.ok(seg ~= nil, "segment " .. i)
				t.ok(near(seg.CFrame.Position, foot + Vector3.new(0, y, 0)), "segment " .. i .. " centre y " .. y)
				t.ok(math.abs(seg.Size.Y - 4) < 1e-3, "4 studs tall")
				t.eq(seg.Color, Color3.new(1, 1, 1))
				t.eq(seg.TextureID, "")
			end
			local top = ladder:FindFirstChild("LadderTop")
			t.ok(top ~= nil and near(top.CFrame.Position, Vector3.new(0, 12.37, 0.375)), "the top at (0, 12.37, 0.375)")
			t.ok(
				ladder:FindFirstChild("Rung") == nil and ladder:FindFirstChild("Hook") == nil,
				"rungs and hook are gone"
			)
			local rails = 0
			for _, d in ipairs(ladder:GetChildren()) do
				if d.Name == "Rail" then
					rails += 1
					t.eq(d.Transparency, 1, "a rail is an invisible proxy")
				end
			end
			t.eq(rails, 2, "both rails stay")
			t.ok(ladder.PrimaryPart ~= nil and ladder.PrimaryPart.Name == "Rail", "the primary part is still a rail")
			local welds = 0
			for _, d in ipairs(ladder:GetDescendants()) do
				if d:IsA("Weld") and d.Parent.Name:sub(1, 6) == "Ladder" then
					welds += 1
				end
			end
			t.eq(welds, 4, "each tile is welded to the primary rail")
		end)
	end)

	t.test("rope ladder: the tiles follow the ladder when it is moved", function()
		withMeshes(function()
			local ladder = MiningArt.RopeLadder()
			ladder:PivotTo(CFrame.new(40, 5, -12) * CFrame.Angles(0, 1, 0))
			local rail = ladder.PrimaryPart
			-- A tile is welded: its offset from the rail is the same as at the origin.
			local seg = ladder:FindFirstChild("LadderSeg2")
			local w = seg:FindFirstChildOfClass("Weld")
			t.ok(w ~= nil and w.Part0 == rail)
		end)
	end)

	t.test("rope ladder: a mesh that is not loaded leaves the part-built ladder", function()
		MeshKit.Reset()
		MeshKit.Override = function()
			return nil
		end
		local ladder = MiningArt.RopeLadder()
		t.ok(ladder:FindFirstChild("Hook") ~= nil and ladder:FindFirstChild("LadderTop") == nil)
		MeshKit.Override = nil
		MeshKit.Reset()
	end)

	---------------------------------------------------------------------------
	-- The V2 blueprint scroll
	---------------------------------------------------------------------------

	local S = 0.625

	t.test("scroll: id 0 keeps the part-built roll", function()
		withMeshes(function()
			withId("BlueprintScrollV2", "Handle", 0, function()
				local model = BlueprintArt.Held("Wall")
				t.ok(model:FindFirstChild("Seal") and model:FindFirstChild("Twine"), "the part-built roll and wax seal")
				t.ok(model:FindFirstChild("ScrollRoll") == nil)
				t.eq(model.PrimaryPart.Transparency, 0)
			end)
		end)
	end)

	t.test("scroll: a fake non-zero id takes the mesh path", function()
		withMeshes(function()
			withId("BlueprintScrollV2", "Handle", 1234567890123, function()
				local model = BlueprintArt.Held("Wall")
				local roll = model:FindFirstChild("ScrollRoll")
				t.ok(roll ~= nil)
				t.eq(roll:GetAttribute("MeshId"), "1234567890123")
			end)
		end)
	end)

	t.test("scroll: the roll is 0.625 scale, lifted, upright over the invisible Handle, welded", function()
		withMeshes(function()
			local model = BlueprintArt.Build("Wall")
			local handle = model.PrimaryPart
			local roll = model:FindFirstChild("ScrollRoll")
			t.ok(roll ~= nil)
			local piece = WornModels.Piece("BlueprintScrollV2", "Handle")
			t.ok((roll.Size - piece.size * S).Magnitude < 1e-3, "scaled 0.625")
			-- The Handle's middle is at y = LEN / 2 = 0.75; the roll sits (1.281 - 1.2) * 0.625 above it.
			t.ok(
				near(roll.CFrame.Position, Vector3.new(0, 0.75 + (1.281 - 1.2) * S, 0)),
				"the middle stays in the hand"
			)
			t.eq(roll.Color, Color3.new(1, 1, 1))
			t.eq(roll.TextureID, "")
			t.eq(handle.Transparency, 1, "the part-built Handle is invisible but kept")
			t.ok(model.PrimaryPart.Name == "Handle")
			local w = roll:FindFirstChildOfClass("Weld")
			t.ok(w ~= nil and w.Part0 == handle, "welded to the Handle")
			t.ok(
				model:FindFirstChild("Edge") == nil
					and model:FindFirstChild("Twine") == nil
					and model:FindFirstChild("Curl") == nil
			)
			-- The grip is as it was.
			t.ok(BlueprintArt.Grip() ~= nil)
		end)
	end)

	t.test("scroll: the seal is 0.625 scale at its offset, tinted by plan kind (Buildings, Decor, other)", function()
		withMeshes(function()
			local want = {
				Wall = BlueprintArt.SealColor("Wall"), -- Buildings: blue
				Fence = BlueprintArt.SealColor("Fence"), -- Decor: green
				NoSuchPlan = BlueprintArt.SealColor("NoSuchPlan"), -- anything else: amber
			}
			t.ok(
				want.Wall ~= want.Fence and want.Fence ~= want.NoSuchPlan and want.Wall ~= want.NoSuchPlan,
				"three colours"
			)
			for id, color in pairs(want) do
				local model = BlueprintArt.Build(id)
				local seal = model:FindFirstChild("ScrollSeal")
				t.ok(seal ~= nil, id .. " has the seal mesh")
				t.eq(seal.Color, color, id .. " seal tint")
				local roll = model:FindFirstChild("ScrollRoll")
				local piece = WornModels.Piece("BlueprintScrollV2", "Seal")
				t.ok((seal.Size - piece.size * S).Magnitude < 1e-3, "seal size 0.625")
				local off = seal.CFrame.Position - roll.CFrame.Position
				t.ok(near(off, Vector3.new(0.023, 0.212, -0.355) * S), id .. " seal offset " .. tostring(off))
				t.ok(
					model:FindFirstChild("Tail") == nil and model:FindFirstChild("Seal") == nil,
					"the wax ball and tail are replaced"
				)
			end
		end)
	end)

	t.test("scroll: the one-line switch keeps the wax ball and tail on the V2 roll", function()
		withMeshes(function()
			BlueprintArt.SealTint = false
			local ok, err = pcall(function()
				local model = BlueprintArt.Build("Wall")
				t.ok(model:FindFirstChild("ScrollRoll") ~= nil, "the roll is on")
				t.ok(model:FindFirstChild("ScrollSeal") == nil, "no seal mesh")
				t.ok(
					model:FindFirstChild("Seal") ~= nil and model:FindFirstChild("Tail") ~= nil,
					"wax ball and tail stay"
				)
			end)
			BlueprintArt.SealTint = true
			if not ok then
				error(err, 0)
			end
		end)
	end)

	t.test("scroll: Held and Dropped follow; plans with their own slot mesh are unchanged", function()
		withMeshes(function()
			local held = BlueprintArt.Held("Wall")
			local roll = held:FindFirstChild("ScrollRoll")
			t.ok(
				roll ~= nil and not roll.Anchored and roll.Massless and not roll.CanCollide,
				"held: nothing anchored or colliding"
			)
			local dropped = BlueprintArt.Dropped("Wall")
			local dr = dropped:FindFirstChild("ScrollRoll")
			t.ok(dr ~= nil and dr.Anchored and not dr.CanCollide, "dropped: anchored, non-colliding")
			local sign = BlueprintArt.Build("WoodSign")
			t.ok(sign:FindFirstChild("ScrollRoll") == nil, "the Wood Sign keeps its own slot")
			local shed = BlueprintArt.Build("Shed")
			t.ok(shed:FindFirstChild("ScrollRoll") == nil, "the Shed Blueprint keeps its own slot")
		end)
	end)

	t.test("scroll: a mesh that is not loaded leaves the part-built roll", function()
		MeshKit.Reset()
		MeshKit.Override = function()
			return nil
		end
		local model = BlueprintArt.Build("Wall")
		t.ok(model:FindFirstChild("Seal") ~= nil and model:FindFirstChild("ScrollRoll") == nil)
		MeshKit.Override = nil
		MeshKit.Reset()
	end)
end
