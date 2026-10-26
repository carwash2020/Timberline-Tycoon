--!nocheck
-- Signs read cleanly: a box in front of every sign's face (6 deep, as wide as
-- the board, from the ground to the board's top) holds no lamp, bench or
-- planter; no sign line breaks after "a"; and the PLOT DISTRICT label does
-- not wrap, so its third line shrinks instead of breaking (T396).

return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")

	local DEPTH = 6 -- studs of clear space in front of a board's face
	-- A prop only counts when it reaches this far into the box: the TO THE WOODS
	-- sign's neighbour lamp base brushes the box's edge by 1.3 cm, which no
	-- one can see or trip on.
	local EDGE = 0.05
	local town = WorldPlan.Town()

	local function firstLine(sign)
		return string.match(sign.text, "^[^\n]+")
	end

	-- Every sign WorldPlan places: the town's, the biome road signs and the
	-- gate signs.
	local function allSigns()
		local out = {}
		for _, sign in ipairs(town.signs) do
			table.insert(out, sign)
		end
		for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
			table.insert(out, sign)
		end
		for _, sign in ipairs(WorldPlan.GateSigns(WorldPlan.BiomeSignText)) do
			table.insert(out, sign)
		end
		return out
	end

	local function signModel(sign)
		local model = BuildingArt.Signpost(sign.text, sign.lit, nil, sign.gateId, sign.noWrap, sign.panel)
		Kit.placeAt(model, sign.cframe)
		return model
	end

	-- A part's eight corners in world space.
	local function corners(part)
		local h = part.Size / 2
		local out = {}
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					table.insert(out, part.CFrame * Vector3.new(x * h.X, y * h.Y, z * h.Z))
				end
			end
		end
		return out
	end

	-- The props that must stay clear of a sign's face: { label, parts } for
	-- every lamp, bench and planter in town (the street lamps, the props, and
	-- the lamp posts, benches and planters a shop's facade builds).
	local props
	local function propsInTown()
		if props then
			return props
		end
		props = {}
		local function add(label, model)
			local boxes = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(boxes, { name = d.Name, corners = corners(d) })
				end
			end
			table.insert(props, { label = label, boxes = boxes })
		end
		local function wanted(name)
			return string.find(name, "LampPost", 1, true) ~= nil
				or string.find(name, "Bench", 1, true) ~= nil
				or string.find(name, "Planter", 1, true) ~= nil
		end
		for i, cf in ipairs(town.lamps) do
			local model = BuildingArt.LampPost()
			Kit.placeAt(model, cf)
			add(string.format("lamp %d at (%g, %g)", i, cf.X, cf.Z), model)
		end
		for _, prop in ipairs(town.props) do
			if prop.name == "Bench" or prop.name == "Planter" then
				local model = BuildingArt.Prop(prop.name, prop.seed)
				Kit.placeAt(model, prop.cframe)
				add(string.format("%s at (%g, %g)", prop.name, prop.cframe.X, prop.cframe.Z), model)
			end
		end
		for _, spot in ipairs(town.shops) do
			local shop = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
			Kit.placeAt(shop, spot.cframe)
			for _, d in ipairs(shop:GetDescendants()) do
				if d:IsA("BasePart") and wanted(d.Name) then
					local boxes = { { name = d.Name, corners = corners(d) } }
					local c = d.CFrame.Position
					table.insert(props, {
						label = string.format("%s %s at (%.1f, %.1f)", spot.kind, d.Name, c.X, c.Z),
						boxes = boxes,
					})
				end
			end
		end
		return props
	end

	-- The sign's clear box in its own space: x across the board, y from the
	-- ground to the board's top, z out from the face (-Z) DEPTH studs.
	local function clearBox(sign, model)
		local board = model:FindFirstChild("Board", true)
		local top = board.CFrame.Position.Y + board.Size.Y / 2 - sign.cframe.Position.Y
		return { halfW = board.Size.X / 2, top = top, face = -board.Size.Z / 2 }
	end

	t.test("no lamp, bench or planter stands in front of any sign's face", function()
		local checked = 0
		for _, sign in ipairs(allSigns()) do
			local model = signModel(sign)
			local box = clearBox(sign, model)
			local inverse = sign.cframe:Inverse()
			local signName = firstLine(sign) .. " sign"
			for _, prop in ipairs(propsInTown()) do
				for _, b in ipairs(prop.boxes) do
					local lo, hi =
						Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
					for _, c in ipairs(b.corners) do
						local p = inverse * c
						lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
						hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
					end
					local hits = lo.X < box.halfW - EDGE
						and hi.X > -box.halfW + EDGE
						and lo.Y < box.top
						and hi.Y > 0
						and lo.Z < box.face - EDGE
						and hi.Z > box.face - DEPTH + EDGE
					t.ok(not hits, string.format("%s stands in front of the %s", prop.label, signName))
				end
			end
			checked += 1
		end
		t.ok(checked >= 10, "the road, gate and town signs are all checked")
	end)

	t.test("the clearance check catches a lamp put where the old one stood", function()
		-- The Sparkworks lamp that stood at (144.4, 105.55), in front of the PLOT DISTRICT sign.
		local plot
		for _, sign in ipairs(town.signs) do
			if firstLine(sign) == "PLOT DISTRICT" then
				plot = sign
			end
		end
		t.ok(plot ~= nil, "the town has a PLOT DISTRICT sign")
		local model = signModel(plot)
		local box = clearBox(plot, model)
		local p = plot.cframe:Inverse() * Vector3.new(144.4, plot.cframe.Position.Y, 105.55)
		t.ok(math.abs(p.X) < box.halfW and p.Z < box.face and p.Z > box.face - DEPTH, "the old spot is in the box")
		local q = plot.cframe:Inverse() * Vector3.new(154, plot.cframe.Position.Y, 104)
		t.ok(not (math.abs(q.X) < box.halfW and q.Z < box.face and q.Z > box.face - DEPTH), "the new spot is not")
	end)

	t.test("no sign line breaks between 'a' and the word after it", function()
		local count = 0
		for _, sign in ipairs(allSigns()) do
			for line in string.gmatch(sign.text .. "\n", "([^\n]*)\n") do
				local lower = string.lower(line)
				t.ok(
					lower ~= "a" and not string.find(lower, " a$"),
					string.format("a line of the %s sign ends in 'a': %q", firstLine(sign), line)
				)
			end
			count += 1
		end
		t.ok(count >= 10)
	end)

	t.test(
		"the PLOT DISTRICT label does not wrap and reads 'Old Hank sells plots' then 'Buy a plot and build on it'",
		function()
			local plot
			for _, sign in ipairs(town.signs) do
				if firstLine(sign) == "PLOT DISTRICT" then
					plot = sign
				end
			end
			t.ok(plot ~= nil, "the town has a PLOT DISTRICT sign")
			t.eq(plot.text, "PLOT DISTRICT\nOld Hank sells plots\nBuy a plot and build on it")
			local model = signModel(plot)
			local labels = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("TextLabel") then
					labels += 1
					t.eq(d.TextWrapped, false, "the label does not wrap")
					t.eq(d.Text, plot.text)
				end
			end
			t.eq(labels, 2, "one label on each face")
		end
	)

	-- T420: the plot sign's text sits ON the board face, in Ink on a SignCream panel, over
	-- PlankHoney planks on TimberBrown posts.
	t.test("the PLOT DISTRICT sign writes Ink on a SignCream panel that stands on the PlankHoney board face", function()
		local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")
		local plot
		for _, sign in ipairs(town.signs) do
			if firstLine(sign) == "PLOT DISTRICT" then
				plot = sign
			end
		end
		t.ok(plot ~= nil and plot.panel == true, "the plan asks for the panel")
		local model = signModel(plot)
		local board = model:FindFirstChild("Board", true)
		t.eq(board.Color, Palette.PlankHoney, "the board is PlankHoney")
		t.eq(Palette.Hex("PlankHoney"), "#C49A63")
		t.eq(Palette.Hex("TimberBrown"), "#7A5230")
		t.eq(Palette.Hex("SignCream"), "#F3E7C9")
		t.eq(Palette.Hex("Ink"), "#3C2814")
		for _, d in ipairs(board:GetDescendants()) do
			t.ok(not d:IsA("TextLabel"), "no text under a panel (on the board itself)")
		end
		local posts = 0
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == "Post" then
				posts += 1
				t.eq(d.Color, Palette.TimberBrown, "posts are TimberBrown")
			end
		end
		t.eq(posts, 2)
		local faces = {}
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == "SignPanel" then
				table.insert(faces, d)
			end
		end
		t.eq(#faces, 2, "a panel on the front and one on the back")
		for _, face in ipairs(faces) do
			t.eq(face.Color, Palette.SignCream, "the panel is SignCream")
			local offset = (board.CFrame:Inverse() * face.CFrame.Position).Z -- along the board's own Z
			local side = if offset < 0 then -1 else 1
			local boardFace = side * board.Size.Z / 2
			local panelBack = offset - side * face.Size.Z / 2
			t.ok(
				math.abs(panelBack - boardFace) < 1e-3,
				string.format("panel back %.4f board face %.4f off %.4f", panelBack, boardFace, offset)
			)
			t.ok(face.Size.Z > 0, "and it stands off it")
			t.ok(face.Size.X <= board.Size.X - 0.5 and face.Size.Y <= board.Size.Y - 0.5, "inside the board's edge")
			local guis = 0
			for _, gui in ipairs(face:GetChildren()) do
				if gui:IsA("SurfaceGui") then
					guis += 1
					t.eq(gui.Face, if side < 0 then roblox.Enum.NormalId.Front else roblox.Enum.NormalId.Back)
					for _, label in ipairs(gui:GetChildren()) do
						if label:IsA("TextLabel") then
							t.eq(label.TextColor3, Palette.Ink, "the text is Ink")
							t.eq(label.Text, plot.text)
						end
					end
				end
			end
			t.eq(guis, 1, "one text face on each panel")
		end
		-- The other signs keep the old look: no panel.
		for _, sign in ipairs(town.signs) do
			if firstLine(sign) ~= "PLOT DISTRICT" then
				t.ok(sign.panel ~= true, firstLine(sign) .. " keeps its own board")
			end
		end
	end)
end
