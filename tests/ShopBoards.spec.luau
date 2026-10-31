--!nocheck
-- T416 item 1: the hanging boards in Hearth & Home and the Tool Shed (HOME PLANS, BUILD PLANS, GEAR, LAMPS,
-- AXES & BELTS, MACHINES and the shop's own name) are house signs: SignCream board, SignInk text on the
-- board's own faces, a TimberBrown frame, Brass brackets, and no blue anywhere on them. Written first.
return function(t)
	local roblox = t.roblox
	local ShopPlace = t.load("ReplicatedStorage/Shared/Art/ShopPlace")
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")

	local EXPECT = {
		HearthAndHome = { "GEAR", "BUILD PLANS", "HOME PLANS", "LAMPS", "HEARTH & HOME" },
		ToolShed = { "AXES & BELTS", "MACHINES" },
	}

	local function build(kind)
		return ShopPlace.Build(kind, kind, roblox.Color3.fromRGB(196, 154, 99))
	end

	-- A sign board: a part with SignText named HeaderSign or StoreSign.
	local function boards(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if
				d:IsA("BasePart")
				and d:GetAttribute("SignText")
				and (d.Name == "HeaderSign" or d.Name == "StoreSign")
			then
				table.insert(out, d)
			end
		end
		return out
	end

	local function siblings(board, suffix)
		local out = {}
		for _, d in ipairs(board.Parent:GetChildren()) do
			if d:IsA("BasePart") and d.Name == "HeaderSign" .. suffix then
				table.insert(out, d)
			end
		end
		return out
	end

	-- The sign's own parts nearest to this board: frame, accent bar, brackets, chains (matched by x span).
	local function setOf(board)
		local parts = { board }
		local half = board.Size.X / 2 + 0.6
		for _, suffix in ipairs({ "Frame", "Accent", "Bracket", "Chain" }) do
			for _, p in ipairs(siblings(board, suffix)) do
				if
					math.abs(p.CFrame.Position.X - board.CFrame.Position.X) <= half
					and math.abs(p.CFrame.Position.Z - board.CFrame.Position.Z) < 0.01
				then
					table.insert(parts, p)
				end
			end
		end
		return parts
	end

	local function isBlue(c)
		local r, g, b = c.R, c.G, c.B
		local mx, mn = math.max(r, g, b), math.min(r, g, b)
		if mx - mn < 0.18 then
			return false
		end
		if mx ~= b then
			return false
		end
		return b > r + 0.1 and b >= g
	end

	for kind, texts in pairs(EXPECT) do
		t.test(kind .. " has every board, as a house sign", function()
			local model = build(kind)
			local found = {}
			for _, board in ipairs(boards(model)) do
				found[board:GetAttribute("SignText")] = board
			end
			for _, text in ipairs(texts) do
				local board = found[text]
				t.ok(board ~= nil, kind .. " board " .. text)
				if board == nil then
					continue
				end
				t.eq(board.Color, Palette.SignCream, text .. " board is SignCream")
				local labels = {}
				for _, d in ipairs(board:GetChildren()) do
					if d:IsA("SurfaceGui") then
						t.eq(d.Parent, board, text .. " text sits on the board")
						local label = d:FindFirstChildWhichIsA("TextLabel")
						t.ok(label ~= nil, text .. " label")
						if label then
							t.eq(label.TextColor3, Palette.SignInk, text .. " ink")
							t.eq(label.Text, text)
							table.insert(labels, label)
						end
					end
				end
				t.ok(#labels >= 2, text .. " reads from both sides")
				local frames = {}
				for _, p in ipairs(siblings(board, "Frame")) do
					if
						math.abs(p.CFrame.Position.X - board.CFrame.Position.X) < 0.3
						and math.abs(p.CFrame.Position.Z - board.CFrame.Position.Z) < 0.01
						and math.abs(p.CFrame.Position.Y - board.CFrame.Position.Y) < board.Size.Y / 2 + 1
					then
						table.insert(frames, p)
					end
				end
				t.ok(#frames >= 1, text .. " has a frame")
				for _, p in ipairs(frames) do
					t.eq(p.Color, Palette.TimberBrown, text .. " frame is TimberBrown")
				end
				for _, p in ipairs(siblings(board, "Accent")) do
					t.eq(p.Color, Palette.TimberBrown, text .. " under-rail is TimberBrown")
				end
				local brackets = {}
				for _, p in ipairs(siblings(board, "Bracket")) do
					local top = board.CFrame.Position.Y + board.Size.Y / 2
					if
						math.abs(p.CFrame.Position.X - board.CFrame.Position.X) <= board.Size.X / 2
						and math.abs(p.CFrame.Position.Z - board.CFrame.Position.Z) < 0.01
						and math.abs(p.CFrame.Position.Y - top) < 1.2
					then
						table.insert(brackets, p)
					end
				end
				t.eq(#brackets, 1, text .. " has its brass bracket bar")
				for _, p in ipairs(brackets) do
					t.eq(p.Color, Palette.Brass, text .. " bracket is Brass")
					-- the bar spans both chain hooks
					for _, chain in ipairs(siblings(board, "Chain")) do
						if math.abs(chain.CFrame.Position.X - board.CFrame.Position.X) < board.Size.X / 2 then
							t.ok(
								math.abs(chain.CFrame.Position.X - p.CFrame.Position.X) <= p.Size.X / 2,
								text .. " chain hangs from the bar"
							)
						end
					end
					-- a bracket sits on the board's top edge, never over its lettering
					t.ok(
						p.CFrame.Position.Y - p.Size.Y / 2 >= board.CFrame.Position.Y + board.Size.Y / 2 - 0.05,
						text .. " bracket clear of the face"
					)
				end
			end
		end)

		t.test(kind .. " boards carry no blue", function()
			local model = build(kind)
			local n = 0
			for _, board in ipairs(boards(model)) do
				n += 1
				for _, p in ipairs(setOf(board)) do
					t.ok(not isBlue(p.Color), board:GetAttribute("SignText") .. " " .. p.Name .. " is blue")
				end
			end
			t.ok(n >= #EXPECT[kind], kind .. " boards found: " .. n)
		end)
	end

	t.test("the names and attributes other code reads are kept", function()
		for kind, texts in pairs(EXPECT) do
			local model = build(kind)
			local seen = 0
			for _, board in ipairs(boards(model)) do
				t.eq(type(board:GetAttribute("SignText")), "string")
				seen += 1
			end
			t.ok(seen >= #texts)
		end
	end)

	t.test("a Sparkworks board is not changed by the house style (it keeps its own look)", function()
		local model = ShopPlace.Build("Sparkworks", "Sparkworks", roblox.Color3.fromRGB(196, 154, 99))
		local any = false
		for _, board in ipairs(boards(model)) do
			any = true
			t.ok(board.Color ~= Palette.SignCream, "Sparkworks board stays its own colour")
		end
		t.ok(any, "Sparkworks has header boards")
	end)
end
