--!nocheck
-- Kit (the art kit): sign text is laid out on its board's own shape;
-- a rock collides (COL-01); scaleModel scales about the origin.

return function(t)
	local roblox = t.roblox
	local Enum, Vector3, CFrame, Color3 = roblox.Enum, roblox.Vector3, roblox.CFrame, roblox.Color3
	local Instance = roblox.Instance
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")

	-- A SurfaceGui left at its default FixedSize lays text out on an 800 x 600
	-- canvas and stretches it onto the face; sized by PixelsPerStud, the
	-- canvas takes the face's shape (a 17 x 3.4 crest is 680 x 136).
	local function sizedToFace(gui)
		return gui.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud and gui.PixelsPerStud == 40
	end

	t.test("signText puts its text on both faces, sized to the board", function()
		local model = Kit.model("Board")
		local board = Kit.part(model, "Board", Vector3.new(17, 3.4, 0.4), CFrame.identity, Color3.new(1, 1, 1))
		local labels = Kit.signText(board, "TIMBERLINE SAWMILL", Color3.new(0, 0, 0))
		t.eq(#labels, 2)
		for _, label in ipairs(labels) do
			t.eq(label.Text, "TIMBERLINE SAWMILL")
			t.ok(sizedToFace(label.Parent), "sized by PixelsPerStud")
		end
	end)

	t.test("sign text reads at night: LightInfluence 0.25 unless asked otherwise (TWN-07)", function()
		local board =
			Kit.part(Kit.model("Board"), "Board", Vector3.new(9, 2.3, 0.4), CFrame.identity, Color3.new(1, 1, 1))
		for _, label in ipairs(Kit.signText(board, "TOOL SHED", Color3.new(0, 0, 0))) do
			t.ok(math.abs(label.Parent.LightInfluence - 0.25) < 1e-4, "default 0.25")
		end
		local glow = Kit.part(Kit.model("Board"), "Board", Vector3.new(4, 1, 0.4), CFrame.identity, Color3.new(1, 1, 1))
		local labels = Kit.signText(glow, "HI", Color3.new(0, 0, 0), { Enum.NormalId.Front }, nil, 0.7)
		t.eq(#labels, 1)
		t.ok(math.abs(labels[1].Parent.LightInfluence - 0.7) < 1e-4, "an explicit value is kept")
	end)

	t.test("every sign in town is sized to its board", function()
		local models = {
			BuildingArt.Signpost("TO THE WOODS"),
			BuildingArt.Sawmill(),
			BuildingArt.SellPad(24, 18),
			BuildingArt.SellStation(28, 32),
			BuildingArt.SkyBin(),
			BuildingArt.GondolaStation(),
			BuildingArt.Campsite(),
			BuildingArt.Shop("ToolShed", "TOOL SHED", Color3.new(1, 0, 0)),
			BuildingArt.Shop("Dealership", "DEALERSHIP", Color3.new(0, 0, 1)),
			BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", Color3.new(0, 1, 0)),
		}
		-- The sawmill's and the shops' big name boards ("Sign", phase 12) take
		-- fewer pixels a stud, by their height, so their letters can fill them
		-- (Roblox stops TextScaled at 100 px; BuildingArt.spec checks them):
		-- still sized to the face, never stretched. The hours board is 4 x 2
		-- at its own pixels-per-stud, so a 200 x 100 canvas matches the face.
		local Hours = t.shared("ShopHoursLogic")
		local named = { Sawmill = true, ToolShed = true, Dealership = true, HearthAndHome = true }
		local guis = 0
		for _, model in ipairs(models) do
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("SurfaceGui") then
					guis += 1
					local sized = if named[model.Name] and d.Parent.Name == "Sign"
						then d.SizingMode == Enum.SurfaceGuiSizingMode.PixelsPerStud and d.PixelsPerStud <= 40
						elseif d.Parent.Name == "HoursBoard" then d.SizingMode
								== Enum.SurfaceGuiSizingMode.PixelsPerStud
							and d.PixelsPerStud == Hours.SignPixelsPerStud
						else sizedToFace(d)
					t.ok(sized, string.format("%s's %s text is stretched", model.Name, d.Parent.Name))
				end
			end
		end
		t.ok(guis >= 10, string.format("only %d signs", guis))
	end)

	t.test("COL-01: Kit.rock's stones collide; Kit.solid undoes Kit.decor's collisions and clicks", function()
		local model = Kit.model("Rocks")
		local stones = Kit.rock(model, CFrame.new(3, 0, 4), 1.6, Kit.rng(7), { Color3.new(0.5, 0.5, 0.5) })
		t.eq(#stones, 3)
		for _, p in ipairs(stones) do
			t.ok(p.CanCollide and p.CanQuery, "a rock's stone collides and can be clicked")
			t.ok(not p.CanTouch, "nothing listens for its touches")
			t.eq(p.Name, "Rock")
			t.eq(p.Parent, model)
		end
		local part =
			Kit.decor(Kit.part(model, "Trough", Vector3.new(2, 1, 1), CFrame.identity, Color3.new(1, 1, 1)), false)
		t.ok(not part.CanCollide and not part.CanQuery and not part.CastShadow, "decor first")
		t.eq(Kit.solid(part), part, "returns the part")
		t.ok(part.CanCollide and part.CanQuery, "then solid")
		t.ok(not part.CanTouch and not part.CastShadow, "still untouched and shadowless")
	end)

	t.test("scaleModel scales sizes, positions, lights and attachments about the origin (TWN-13)", function()
		local model = Kit.model("M")
		local turn = CFrame.Angles(0, 0.5, 0)
		local box = Kit.part(model, "Box", Vector3.new(2, 4, 6), CFrame.new(1, 2, -3) * turn, Color3.new(1, 1, 1))
		local light = Instance.new("PointLight")
		light.Range = 10
		light.Parent = box
		local at = Instance.new("Attachment")
		at.Position = Vector3.new(0, 1, 0)
		at.Parent = box
		local tooth = Kit.part(model, "Tooth", Vector3.new(1, 1, 1), CFrame.new(1, 4, -3), Color3.new(1, 1, 1))
		tooth.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1, weld.Parent = box, tooth, tooth
		local kept = Kit.part(model, "Counter", Vector3.new(4, 3, 2), CFrame.new(2, 2, 2), Color3.new(1, 1, 1))
		local before = #model:GetDescendants()
		Kit.scaleModel(model, 1.5, { [kept] = Vector3.new(2, 0.5, 2) })
		t.eq(#model:GetDescendants(), before, "adds nothing")
		t.ok((box.Size - Vector3.new(3, 6, 9)).Magnitude < 1e-4, "sizes scale")
		t.ok((box.CFrame.Position - Vector3.new(1.5, 3, -4.5)).Magnitude < 1e-4, "positions scale about the origin")
		t.ok(box.CFrame.LookVector:Dot(turn.LookVector) > 0.9999, "turns are kept")
		t.eq(light.Range, 15)
		t.ok((at.Position - Vector3.new(0, 1.5, 0)).Magnitude < 1e-4, "attachments follow")
		t.ok((tooth.CFrame.Position - Vector3.new(1.5, 6, -4.5)).Magnitude < 1e-4, "welded parts move too")
		t.ok(weld.Enabled and weld.Part0 == box and weld.Part1 == tooth, "the weld is back on")
		t.ok((kept.Size - Vector3.new(4, 3, 2)).Magnitude < 1e-4, "a rigid part keeps its size")
		t.ok((kept.CFrame.Position - Vector3.new(3, 2.25, 3)).Magnitude < 1e-4, "and moves with its anchor")
	end)
end
