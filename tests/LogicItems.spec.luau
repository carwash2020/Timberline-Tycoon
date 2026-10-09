--!nocheck
-- Gate faces: each kind wears one label, and no two kinds share it.
return function(t)
	local fs = require("@lune/fs")
	local Enum = t.roblox.Enum
	local LogicItems = t.shared("LogicItems")
	local PlotData = t.shared("PlotData")
	local Models = t.shared("BlueprintModels")

	local KINDS = { "GateAnd", "GateOr", "GateXor", "GateNot", "Delay", "Sustain", "Clock" }

	t.test("every gate kind has a unique label", function()
		local theme = fs.readFile("src/StarterPlayer/StarterPlayerScripts/UITheme.luau")
		local seenLabel = {}
		local seenAccent = {}
		for _, id in ipairs(KINDS) do
			local label = LogicItems.Mark[id]
			local accent = LogicItems.Accent[id]
			t.ok(type(label) == "string" and label ~= "", id .. " label")
			t.eq(seenLabel[label], nil, label .. " is shared")
			seenLabel[label] = id
			t.eq(seenAccent[accent], nil, accent .. " is shared")
			seenAccent[accent] = id
			t.ok(string.find(theme, accent, 1, true) ~= nil, id .. " accent is a UITheme token")
			local bp = PlotData.Blueprint(id)
			t.ok(#bp.boxes <= 5, id .. " part budget")
			local wore = false
			for _, box in ipairs(bp.boxes) do
				if box.color == accent then
					wore = true
				end
			end
			t.eq(wore, true, id .. " wears its strip")
			local model = Models.Build(bp, false)
			local text, font, face = nil, nil, nil
			local guis = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("SurfaceGui") then
					guis += 1
					face = d.Face
					local mark = d:FindFirstChildWhichIsA("TextLabel")
					if mark then
						text = mark.Text
						font = mark.Font
						t.eq(mark.TextScaled, true, id .. " text scales")
					end
				end
			end
			t.eq(guis, 1, id .. " one SurfaceGui")
			t.eq(text, label, id)
			t.eq(font, Enum.Font.GothamBold, id)
			t.eq(face, Enum.NormalId.Top, id)
		end
		local count = 0
		for _ in pairs(seenLabel) do
			count += 1
		end
		t.eq(count, #KINDS, "one label each")
	end)

	t.test("a missing MeshTemplates model keeps the part build and is logged once", function()
		LogicItems.InstallMesh(nil)
		local model = Models.Build(PlotData.Blueprint("Lever"), false)
		t.eq(model:FindFirstChild("Body"), nil)
		t.eq(model:FindFirstChild("Moving"), nil)
		local handle = model:FindFirstChild("Part3")
		t.eq(handle.Transparency, 0)
		t.eq(LogicItems.FellBack("Lever"), true)
		Models.Build(PlotData.Blueprint("Lever"), false)
		t.eq(LogicItems.FellBack("Lever"), true)
	end)

	t.test("a MeshTemplates model supplies the named slots and the gate label", function()
		local function part(name)
			local made = t.roblox.Instance.new("Part")
			made.Name = name
			made.Size = t.roblox.Vector3.new(1, 0.4, 1)
			made.CFrame = t.roblox.CFrame.new(0, 0.5, 0)
			made.Color = t.roblox.Color3.fromRGB(40, 40, 40)
			return made
		end
		local template = t.roblox.Instance.new("Model")
		for _, name in ipairs({ "Body", "Indicator", "Moving", "LabelFace" }) do
			local piece = part(name)
			piece.Parent = template
		end
		LogicItems.InstallMesh("GateAnd", template)
		local model = Models.Build(PlotData.Blueprint("GateAnd"), false)
		for _, name in ipairs(LogicItems.Slots) do
			t.ok(model:FindFirstChild(name), name)
		end
		local mark = model:FindFirstChild("Mark", true)
		t.eq(mark.Parent.Name, "LabelFace")
		t.eq(mark:FindFirstChild("Label").Text, "AND")
		t.eq(model:FindFirstChild("Part1").Transparency, 1, "the boxes step back")
		t.eq(LogicItems.FellBack("GateAnd"), false)
		LogicItems.InstallMesh("GateAnd", nil)
	end)
end
