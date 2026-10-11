--!nocheck
-- TownBoardArt: ten parts, no light, a SurfaceGui on the front (the street
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

	t.test("ten parts, no light, a persistent-ready model with one front face", function()
		local model = TownBoardArt.Build()
		t.eq(model.Name, "TownBoard")
		t.eq(#parts(model), 10)
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
		t.eq(count, 2, "the board's face and the plaque's")
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
