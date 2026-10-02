--!nocheck
-- Kit (the art kit): sign text is laid out on its board's own shape.

return function(t)
	local roblox = t.roblox
	local Enum, Vector3, CFrame, Color3 = roblox.Enum, roblox.Vector3, roblox.CFrame, roblox.Color3
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
			BuildingArt.SkyBin(),
			BuildingArt.GondolaStation(),
			BuildingArt.Campsite(),
			BuildingArt.Shop("ToolShed", "TOOL SHED", Color3.new(1, 0, 0)),
			BuildingArt.Shop("Dealership", "DEALERSHIP", Color3.new(0, 0, 1)),
			BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", Color3.new(0, 1, 0)),
		}
		local guis = 0
		for _, model in ipairs(models) do
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("SurfaceGui") then
					guis += 1
					t.ok(sizedToFace(d), string.format("%s's %s text is stretched", model.Name, d.Parent.Name))
				end
			end
		end
		t.ok(guis >= 10, string.format("only %d signs", guis))
	end)
end
