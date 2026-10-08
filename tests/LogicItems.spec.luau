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
end
