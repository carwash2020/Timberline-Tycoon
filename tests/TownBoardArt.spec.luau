--!nocheck
-- TownBoardArt: fourteen parts (T414e added four brass corners), no light, a SurfaceGui on the front (the street
-- side) with real text, nothing floating or sunk, and every state fits.
return function(t)
	local TownBoardArt = t.shared("Art/TownBoardArt")
	local TownBoardLogic = t.shared("TownBoardLogic")

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function named(model, name)
		local out = {}
		for _, p in ipairs(parts(model)) do
			if p.Name == name then
				table.insert(out, p)
			end
		end
		return out
	end

	local function face(model)
		return model:FindFirstChild("Board"):FindFirstChild("Face")
	end

	local function box(label)
		return {
			x0 = label.Position.X.Scale,
			y0 = label.Position.Y.Scale,
			x1 = label.Position.X.Scale + label.Size.X.Scale,
			y1 = label.Position.Y.Scale + label.Size.Y.Scale,
		}
	end

	local function texts(model)
		local out = {}
		for _, d in ipairs(face(model):GetChildren()) do
			if d:IsA("TextLabel") and d.Text ~= "" then
				table.insert(out, d)
			end
		end
		return out
	end

	local function rows(n)
		local list = {}
		for i = 1, n do
			table.insert(list, { rank = i, name = "Lumberjack" .. i, score = 2000000 - i * 1234 })
		end
		return list
	end

	t.test("fourteen parts, no light, a persistent-ready model with one front face", function()
		local model = TownBoardArt.Build()
		t.eq(model.Name, "TownBoard")
		t.eq(#parts(model), 14)
		t.eq(#named(model, "FrameCorner"), 4)
		t.ok(#parts(model) <= TownBoardLogic.PartCap)
		for _, d in ipairs(model:GetDescendants()) do
			t.ok(not d:IsA("Light"), "no light: " .. d.Name)
		end
		t.eq(#named(model, "Post"), 2)
		t.eq(#named(model, "PostCap"), 2)
		t.eq(#named(model, "FrameRail"), 2)
		t.eq(#named(model, "FrameStile"), 2)
		local gui = face(model)
		t.ok(gui ~= nil and gui:IsA("SurfaceGui"))
		t.eq(gui.Face, t.roblox.Enum.NormalId.Front, "the front (-Z) is the street side")
		t.eq(gui.MaxDistance, 120)
		t.eq(gui.CanvasSize, TownBoardLogic.CanvasSize)
		local count = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("SurfaceGui") then
				count += 1
			end
		end
		t.eq(count, 3, "the board's face, its back's title and the plaque's")
		local backs = 0
		for _, d in ipairs(model:FindFirstChild("Board"):GetChildren()) do
			if d:IsA("SurfaceGui") and d.Face == t.roblox.Enum.NormalId.Back then
				backs += 1
			end
		end
		t.eq(backs, 1, "the back is a sign, with no rows on it")
	end)

	t.test("nothing floats or sinks: the posts reach into the ground, the rest sits on it", function()
		local model = TownBoardArt.Build()
		for _, p in ipairs(parts(model)) do
			local bottom = p.CFrame.Position.Y - p.Size.Y / 2
			if p.Name == "Post" then
				t.ok(bottom < 0 and bottom >= -2, "a post sinks a stud: " .. bottom)
			else
				t.ok(bottom >= -1e-6, p.Name .. " is not under the ground: " .. bottom)
			end
		end
		local post = named(model, "Post")[1]
		local board = model:FindFirstChild("Board")
		local plaque = model:FindFirstChild("Plaque")
		local postTop = post.CFrame.Position.Y + post.Size.Y / 2
		t.ok(postTop > board.CFrame.Position.Y + board.Size.Y / 2, "the posts stand over the field")
		-- The plaque hangs under the frame, with a gap, and between the posts.
		local frameBottom = board.CFrame.Position.Y - board.Size.Y / 2 - TownBoardLogic.Frame
		t.ok(plaque.CFrame.Position.Y + plaque.Size.Y / 2 < frameBottom, "plaque under the frame")
		t.ok(plaque.CFrame.Position.Y - plaque.Size.Y / 2 >= 0, "plaque off the ground")
		for _, p in ipairs(named(model, "Post")) do
			local px = p.CFrame.Position.X
			local inner = px - math.sign(px) * p.Size.X / 2
			t.ok(math.abs(inner) >= plaque.Size.X / 2 - 1e-3, "the plaque does not sit inside a post")
		end
		-- The board is centred between the posts, the frame flush with them.
		t.ok(math.abs(board.CFrame.Position.X) < 1e-6)
		for _, stile in ipairs(named(model, "FrameStile")) do
			local outer = math.abs(stile.CFrame.Position.X) + stile.Size.X / 2
			t.ok(
				math.abs(outer - (TownBoardLogic.PostX - TownBoardLogic.PostWidth / 2)) < 1e-3,
				"frame flush with a post"
			)
		end
	end)

	t.test("T414e: a TimberBrown frame and posts, a SignCream face, Brass corners, SignInk lettering", function()
		local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")
		local model = TownBoardArt.Build()
		t.eq(model:FindFirstChild("Board").Color, Palette.SignCream, "the face")
		for _, name in ipairs({ "FrameRail", "FrameStile", "Post", "Plaque" }) do
			for _, p in ipairs(named(model, name)) do
				t.eq(p.Color, Palette.TimberBrown, name)
			end
		end
		for _, name in ipairs({ "FrameCorner", "PostCap" }) do
			for _, p in ipairs(named(model, name)) do
				t.eq(p.Color, Palette.Brass, name)
			end
		end
		t.eq(face(model):FindFirstChild("Title").TextColor3, Palette.SignInk, "the title is ink on the cream")
		-- Nothing on the board is the old walnut or a wood-planks slab.
		t.ok(model:FindFirstChild("Board").Material ~= t.roblox.Enum.Material.Metal)
	end)

	t.test("T414e: it reads at phone distance, and the plate text has the contrast to do it", function()
		-- A phone (667 x 375, 70 degree vertical field): pixels a stud covers at a distance.
		local function phonePx(studsHigh, distance)
			return studsHigh * 375 / (2 * distance * math.tan(math.rad(35)))
		end
		local per = TownBoardLogic.PxPerStud
		t.ok(phonePx(TownBoardLogic.TitleTextPx / per, 30) >= 10, "the title from 30 studs")
		t.ok(phonePx(TownBoardLogic.NameTextPx / per, 14) >= 10, "a name from the far side of the street")
		t.ok(phonePx(TownBoardLogic.CashTextPx / per, 14) >= 7, "the cash line from there")
		local function luma(c)
			return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
		end
		local model = TownBoardArt.Build()
		TownBoardArt.Fill(model, TownBoardLogic.View(rows(10), false))
		local gui = face(model)
		local field = luma(model:FindFirstChild("Board").Color)
		t.ok(math.abs(luma(gui:FindFirstChild("Title").TextColor3) - field) >= 0.5, "title on the face")
		t.ok(math.abs(luma(gui:FindFirstChild("Message").TextColor3) - field) >= 0.5, "the message line on the face")
		for _, name in ipairs({ "Name1", "Name4", "Cash1", "Rank1", "Rank4" }) do
			local plate = luma(gui:FindFirstChild("Plate1").BackgroundColor3)
			t.ok(math.abs(luma(gui:FindFirstChild(name).TextColor3) - plate) >= 0.4, name .. " on its plate")
		end
		t.eq(gui.MaxDistance, TownBoardLogic.MaxDistance)
	end)

	t.test("T414e: the board does not block the walk: a wide opening between the posts, a thin solid", function()
		local model = TownBoardArt.Build()
		local posts = named(model, "Post")
		local gap = 2 * TownBoardLogic.PostX - TownBoardLogic.PostWidth
		t.ok(gap >= 12, "the posts stand " .. gap .. " apart")
		for _, p in ipairs(parts(model)) do
			if p.CanCollide then
				t.ok(p.Size.Z <= 1, p.Name .. " is no deeper than a stud")
			end
		end
		t.eq(#posts, 2)
	end)

	t.test("only the posts, the field and the plaque collide", function()
		local model = TownBoardArt.Build()
		for _, p in ipairs(parts(model)) do
			local solid = p.Name == "Post" or p.Name == "Board" or p.Name == "Plaque"
			t.eq(p.CanCollide, solid, p.Name)
		end
	end)

	t.test("a new board reads Loading, and every label sits on the face", function()
		local model = TownBoardArt.Build()
		local said = {}
		for _, label in ipairs(texts(model)) do
			said[label.Name] = label.Text
			local b = box(label)
			t.ok(b.x0 >= 0 and b.y0 >= 0 and b.x1 <= 1 and b.y1 <= 1, label.Name .. " is on the canvas")
		end
		t.eq(said.Title, "TOP LUMBERJACKS")
		t.eq(said.Message, "Loading the board...")
		t.eq(model:GetAttribute("State"), "loading")
	end)

	t.test("ten rows fill the face: every line is on screen, nothing overlaps, top three are amber", function()
		local model = TownBoardArt.Build()
		TownBoardArt.Fill(model, TownBoardLogic.View(rows(10), false))
		local list = texts(model)
		local names, cashes, ranks = 0, 0, 0
		for _, label in ipairs(list) do
			if string.sub(label.Name, 1, 4) == "Name" then
				names += 1
			elseif string.sub(label.Name, 1, 4) == "Cash" then
				cashes += 1
			elseif string.sub(label.Name, 1, 4) == "Rank" then
				ranks += 1
			end
		end
		t.eq({ names, cashes, ranks }, { 10, 10, 10 })
		t.eq(face(model):FindFirstChild("Message").Text, "", "no message over the rows")
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = box(list[i]), box(list[j])
				local apart = a.x1 <= b.x0 + 1e-5 or b.x1 <= a.x0 + 1e-5 or a.y1 <= b.y0 + 1e-5 or b.y1 <= a.y0 + 1e-5
				t.ok(apart, list[i].Name .. " overlaps " .. list[j].Name)
			end
		end
		local L = TownBoardArt.Look
		t.eq(face(model):FindFirstChild("Rank1").TextColor3, L.Amber)
		t.eq(face(model):FindFirstChild("Rank4").TextColor3, L.Cream)
		t.eq(face(model):FindFirstChild("Name1").TextColor3, L.Amber)
		t.eq(face(model):FindFirstChild("Name3").TextColor3, L.Amber)
		t.eq(face(model):FindFirstChild("Name4").TextColor3, L.Cream)
		t.eq(face(model):FindFirstChild("Name1").Text, "Lumberjack1")
		t.eq(face(model):FindFirstChild("Cash1").Text, "$1,998,766 earned")
		t.eq(face(model):FindFirstChild("Rank10").Text, "10")
		t.eq(face(model):FindFirstChild("Plate10").Visible, true)
		t.eq(model:GetAttribute("State"), "rows")
	end)

	t.test("a shorter list clears the rows below it; the empty and failed states show one line", function()
		local model = TownBoardArt.Build()
		TownBoardArt.Fill(model, TownBoardLogic.View(rows(10), false))
		TownBoardArt.Fill(model, TownBoardLogic.View(rows(3), false))
		local gui = face(model)
		t.eq(gui:FindFirstChild("Name3").Text, "Lumberjack3")
		t.eq(gui:FindFirstChild("Name4").Text, "", "no stale name")
		t.eq(gui:FindFirstChild("Cash10").Text, "")
		t.eq(gui:FindFirstChild("Plate4").Visible, false)
		t.eq(gui:FindFirstChild("Plate3").Visible, true)

		TownBoardArt.Fill(model, TownBoardLogic.View({}, false))
		local lines = {}
		for _, label in ipairs(texts(model)) do
			table.insert(lines, label.Name)
		end
		table.sort(lines)
		t.eq(lines, { "Message", "Title" }, "the title and the one line")
		t.eq(gui:FindFirstChild("Message").Text, "No one is on the board yet. Turn it on in Settings, Leaderboard.")
		t.eq(gui:FindFirstChild("Plate1").Visible, false)
		t.eq(model:GetAttribute("State"), "empty")

		TownBoardArt.Fill(model, TownBoardLogic.View(nil, true))
		t.eq(gui:FindFirstChild("Message").Text, "The board couldn't load. Try again soon.")
		t.eq(model:GetAttribute("State"), "failed")
		TownBoardArt.Fill(model, TownBoardLogic.View(rows(2), false))
		t.eq(gui:FindFirstChild("Message").Text, "", "rows replace the message")
	end)

	t.test("the plaque's sign line points at the opt-in", function()
		local model = TownBoardArt.Build()
		local plaque = model:FindFirstChild("Plaque")
		local found
		for _, d in ipairs(plaque:GetDescendants()) do
			if d:IsA("TextLabel") then
				found = d
			end
		end
		t.ok(found ~= nil)
		t.ok(string.find(found.Text, "Settings", 1, true) and string.find(found.Text, "Leaderboard", 1, true))
		local gui = plaque:FindFirstChildWhichIsA("SurfaceGui")
		t.eq(gui.Face, t.roblox.Enum.NormalId.Front)
	end)

	t.test("no price, no Robux and no speech bubble on the board", function()
		local model = TownBoardArt.Build()
		TownBoardArt.Fill(model, TownBoardLogic.View(rows(10), false))
		for _, d in ipairs(model:GetDescendants()) do
			t.ok(not d:IsA("BillboardGui"), "no floating bubble")
			if d:IsA("TextLabel") then
				t.eq(string.find(d.Text, "R$", 1, true), nil, "no Robux")
				t.eq(string.find(string.lower(d.Text), "robux", 1, true), nil)
			end
		end
	end)
end
