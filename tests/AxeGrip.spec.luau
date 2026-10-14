--!nocheck
-- AxeGrip: every axe in ItemCatalog (all tiers, the Lux Axe and the Hermit's
-- Maul) is held with the handle in the hand, the head up, and the cutting edge
-- pointing forward, away from the player, at the tree.
--
-- The maths. Roblox welds Tool.Handle to the hand: Handle = RightGripAttachment
-- * Tool.Grip:Inverse(). The attachment's -Z points down the arm and the
-- raised arm points forward, so in the grip frame -Z is the character's look
-- vector and +Y is up. AxeArt.Grip(def):Inverse() is therefore the Handle's
-- CFrame in that frame, and a direction d in the Handle's space is
-- handleInGrip:VectorToWorldSpace(d) in the grip frame.
--
-- Where the edge is in the Handle's space: a part-built axe has its edge at
-- the Handle's -Z (AxeArt's contract). An imported mesh piece comes out of
-- Roblox's import a half turn from its GLB (AxeModels.MeshYaw), i.e. its
-- raw edge points the mesh's own +Z, and AxeArt turns it by MeshYaw. So the
-- edge in the Handle's space is MeshHead.CFrame:VectorToWorldSpace(+Z).
-- That was the bug: without the turn every meshed axe's edge pointed +Z.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame
	local AxeArt = t.load("ReplicatedStorage/Shared/Art/AxeArt")
	local AxeModels = t.load("ReplicatedStorage/Shared/Art/AxeModels")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local ItemCatalog = t.shared("ItemCatalog")

	local FORWARD = Vector3.new(0, 0, -1) -- the character's look vector in the grip frame
	local UP = Vector3.new(0, 1, 0)

	local function allAxes()
		local out = {}
		for _, def in pairs(ItemCatalog.Axes) do
			table.insert(out, def)
		end
		table.sort(out, function(a, b)
			return a.id < b.id
		end)
		return out
	end

	local function withMeshes(fn)
		MeshKit.Reset()
		MeshKit.Override = function(id, name, size)
			local part = roblox.Instance.new("MeshPart")
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

	-- The checks for one built axe: edge direction and head position, both in
	-- the grip (hand) frame.
	local function check(def, model, edgeOf, label)
		local handle = model.PrimaryPart
		local handleInGrip = AxeArt.Grip(def):Inverse()
		local edge = handleInGrip:VectorToWorldSpace(edgeOf(model, handle))
		t.ok(edge:Dot(FORWARD) > 0.9, label .. ": the cutting edge points forward (dot " .. edge:Dot(FORWARD) .. ")")
		local top = handleInGrip:VectorToWorldSpace(Vector3.new(0, 1, 0))
		t.ok(top:Dot(UP) > 0.9, label .. ": the haft's top is up")
		-- The head: its centre, in the grip frame, is well above the hand.
		local headPart = model:FindFirstChild("MeshHead")
			or model:FindFirstChild("Head")
			or model:FindFirstChild("Blade")
		if headPart then
			local inHandle = handle.CFrame:PointToObjectSpace(headPart.CFrame.Position)
			local inGrip = handleInGrip:PointToWorldSpace(inHandle)
			t.ok(inGrip.Y > 1.2, label .. ": the head is above the hand (y " .. inGrip.Y .. ")")
			-- ...and the head sits on the edge side of the haft, not behind it.
			t.ok(inGrip.Z < 0.2, label .. ": the head is not behind the hand")
		end
	end

	local function partBuiltEdge()
		return Vector3.new(0, 0, -1) -- AxeArt's contract
	end

	local function meshEdge(model, handle)
		local mesh = model:FindFirstChild("MeshHead")
		-- The raw import's edge is the mesh's +Z (a half turn from the GLB).
		return handle.CFrame:VectorToObjectSpace(mesh.CFrame:VectorToWorldSpace(Vector3.new(0, 0, 1)))
	end

	t.test("part-built: edge forward, head up, for every axe", function()
		for _, def in ipairs(allAxes()) do
			check(def, AxeArt.Held(def), partBuiltEdge, def.id)
		end
	end)

	t.test("meshed: the import turn is undone, edge forward, head up, every axe incl. Lux", function()
		withMeshes(function()
			local meshed = 0
			for _, def in ipairs(allAxes()) do
				local model = AxeArt.Held(def)
				if model:FindFirstChild("MeshHead") then
					meshed += 1
					check(def, model, meshEdge, def.id .. " (mesh)")
				else
					t.ok(def.quest, def.id .. " has a mesh unless it is a quest axe")
				end
			end
			t.ok(meshed >= 10, "the nine rungs and the Lux Axe are meshed")
			t.ok(AxeArt.Held(ItemCatalog.GetAxe("LuxAxe")):FindFirstChild("MeshHead") ~= nil, "Lux is meshed")
		end)
	end)

	t.test("the half turn is the only thing between the import and the forward edge", function()
		t.ok(math.abs(math.abs(AxeModels.MeshYaw) - math.pi) < 1e-6, "MeshYaw is a half turn")
	end)

	t.test("every axe shares one grip: same orientation, same hand height from the foot", function()
		local first = nil
		for _, def in ipairs(allAxes()) do
			local model = AxeArt.Build(def)
			local handle = model.PrimaryPart
			local grip = AxeArt.Grip(def)
			local handleInGrip = grip:Inverse()
			-- Orientation: identical for all axes (no per-axe rotation).
			if first == nil then
				first = handleInGrip.Rotation
			else
				local a, b = handleInGrip.RightVector, first.RightVector
				t.ok((a - b).Magnitude < 1e-6, def.id .. ": same grip right")
				t.ok((handleInGrip.UpVector - first.UpVector).Magnitude < 1e-6, def.id .. ": same grip up")
				t.ok((handleInGrip.LookVector - first.LookVector).Magnitude < 1e-6, def.id .. ": same grip look")
			end
			-- The hand is GripFromFoot above the handle's foot, on the axis.
			local hand = handleInGrip:PointToObjectSpace(Vector3.new(0, 0, 0))
			t.ok(math.abs(hand.X) < 1e-6 and math.abs(hand.Z) < 1e-6, def.id .. ": the hand is on the haft's axis")
			t.ok(math.abs(hand.Y + handle.Size.Y / 2 - AxeArt.GripFromFoot) < 1e-3, def.id .. ": hand at the foot")
		end
	end)

	t.test("the Tool takes AxeArt.Grip as it is; nothing else rotates an axe's grip", function()
		local fs = require("@lune/fs")
		local service = fs.readFile("src/ServerScriptService/AxeService.luau")
		t.ok(string.find(service, "tool.Grip = AxeArt.Grip(def)", 1, true), "AxeService uses the shared grip")
		local count = 0
		for _ in string.gmatch(service, "%.Grip%s*=") do
			count += 1
		end
		t.eq(count, 1, "AxeService sets Tool.Grip once")
	end)
end
