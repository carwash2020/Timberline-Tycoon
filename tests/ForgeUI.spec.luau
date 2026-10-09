--!nocheck
-- ForgeUI: it fits a phone (667x375 and wider) and 1280x720; every button
-- is 44 px; on a phone nothing sits in the thumbstick zone, the jump button
-- or under the cash row; the rows say exact costs, and tempering shows its
-- cost and result before Temper.
return function(t)
	local Enum = t.roblox.Enum
	local Vector2 = t.roblox.Vector2
	-- UITheme.Button's signals, which @lune/roblox lacks.
	local function signal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end
	for _, name in ipairs({ "Activated", "InputBegan", "InputEnded", "SelectionLost", "MouseEnter", "MouseLeave" }) do
		pcall(t.roblox.implementProperty, "TextButton", name, signal)
		pcall(t.roblox.implementProperty, "GuiButton", name, signal)
	end
	local loader = t.loader({
		mocks = {
			HUD = { SetModal = function() end },
		},
		services = {
			GuiService = {
				SelectedObject = nil,
				IsTenFootInterface = function()
					return false
				end,
			},
			Players = { LocalPlayer = {} },
			UserInputService = {
				TouchEnabled = true,
				KeyboardEnabled = false,
				GetLastInputType = function()
					return Enum.UserInputType.Touch
				end,
			},
			TextChatService = {},
			ContextActionService = {},
		},
		globals = {
			workspace = { CurrentCamera = { ViewportSize = Vector2.new(667, 375) } },
		},
	})
	local ForgeUI = loader:load("StarterPlayer/StarterPlayerScripts/ForgeUI")

	local VIEW = {
		cash = 64000,
		shards = 9,
		starfall = {
			name = "Starfall Axe",
			cost = "$20,000 + 12 Sky Shards + 60 plain Lumenwood fed to the isle forge",
			progress = "Lumenwood 18/60 · Sky Shards 9/12 · $20,000",
			owned = 0,
			refusal = "Needs 42 more Lumenwood, 3 more Sky Shards.",
		},
		axes = {
			{
				uid = "u1",
				id = "ObsidianAxe",
				name = "Obsidian Axe",
				label = "Heavy I",
				options = {
					{
						prefix = "Keen",
						tier = 1,
						grade = "I",
						effect = "Swings 8% faster",
						cost = "$20,000 + 6 Sky Shards + 30 Gloamwood planks",
					},
					{
						prefix = "Heavy",
						tier = 2,
						grade = "II",
						effect = "Hits 20% harder",
						cost = "$50,000 + 10 Sky Shards + 40 Lumenwood planks",
						refusal = "1 more Sky Shards needed.",
					},
					{
						prefix = "Prosperous",
						tier = 1,
						grade = "I",
						effect = "Wood it fells sells for 4% more",
						cost = "$20,000 + 6 Sky Shards + 30 Gloamwood planks",
					},
				},
			},
		},
		relics = {
			{
				id = "FrostRelic",
				name = "Frost Relic",
				cost = "Figured Frostwood + 4 Sky Shards",
				pays = 22500,
				owned = true,
				color = "#BFE3F2",
			},
			{
				id = "EmberRelic",
				name = "Ember Relic",
				cost = "Figured Emberwood + 6 Sky Shards",
				pays = 37500,
				owned = false,
				color = "#FF7A1A",
			},
		},
		order = {
			text = "Lumenwood 0/10 · Gloamwood 12/30",
			pays = 18000,
			shards = 4,
			claimed = false,
			endsIn = 3 * 86400 + 7200,
		},
	}

	t.test("on phones the panel misses the thumbstick, the jump button and the cash row", function()
		for _, size in ipairs({ { 667, 375 }, { 740, 360 }, { 812, 375 }, { 896, 414 } }) do
			local w, h = size[1], size[2]
			local r = ForgeUI.Rects(w, h, true)
			local z = ForgeUI.Zones(w, h)
			local tag = w .. "x" .. h
			t.eq(ForgeUI.Overlaps(r, z.stick), false, tag .. " thumbstick")
			t.eq(ForgeUI.Overlaps(r, z.jump), false, tag .. " jump")
			t.eq(ForgeUI.Overlaps(r, z.cash), false, tag .. " cash row")
			t.ok(r.x >= 0 and r.y >= 0 and r.x + r.w <= w and r.y + r.h <= h, tag .. " on screen")
			t.ok(r.w >= 240 and r.h >= 220, tag .. " big enough: " .. r.w .. "x" .. r.h)
		end
		local pc = ForgeUI.Rects(1280, 720, false)
		t.ok(pc.x >= 0 and pc.x + pc.w <= 1280 and pc.y >= 0 and pc.y + pc.h <= 720, "1280x720 on screen")
	end)

	t.test("every button is a 44 px target, tabs included", function()
		local gui = ForgeUI.Ensure(Vector2.new(667, 375), true)
		for _, tab in ipairs(ForgeUI.Tabs) do
			ForgeUI.Show(VIEW, tab)
			local n = 0
			for _, d in ipairs(gui:GetDescendants()) do
				if d:IsA("TextButton") and d.Name == "Face" then
					n += 1
					t.ok(d.Parent.Size.Y.Offset - 3 >= 44, tab .. " " .. d.Parent.Name .. " is 44 px")
					t.ok(d.Parent.Size.X.Offset >= 44, tab .. " " .. d.Parent.Name .. " is 44 px wide")
				end
			end
			t.ok(n >= 6, tab .. " has its buttons")
		end
	end)

	t.test("rows say exact costs and pay; owned relics say so; the order says when it turns", function()
		local star = ForgeUI.RowsFor(VIEW, "Starfall")[1]
		t.eq(star.lines[1].text, VIEW.starfall.cost)
		t.eq(star.style, "cant", "short: the button says so")
		local relics = ForgeUI.RowsFor(VIEW, "Relics")
		t.eq(relics[1].button, "Done")
		t.eq(relics[1].action, nil, "a forged relic can't be forged again")
		t.eq(relics[2].lines[2].text, "Pays $37,500 once and lights its socket.")
		t.eq(relics[2].action.kind, "relic")
		local order = ForgeUI.RowsFor(VIEW, "Order")[1]
		t.eq(order.lines[2].text, "Pays $18,000 + 4 Sky Shards, once a week.")
		t.eq(order.lines[3].text, "New order in 3d 2h (Monday 00:00 UTC)")
	end)

	t.test("tempering shows the result and exact cost before anything is sent", function()
		local row = ForgeUI.RowsFor(VIEW, "Temper")[1]
		t.eq(row.name, "Obsidian Axe · Heavy I")
		t.eq(#row.choices, 3)
		t.eq(row.action, nil, "picking a temper sends nothing")
		local card = ForgeUI.ConfirmFor(VIEW, "u1", "Keen")
		t.eq(card.lines[1].text, "Result: Swings 8% faster.")
		t.eq(card.lines[2].text, "Costs $20,000 + 6 Sky Shards + 30 Gloamwood planks.")
		t.eq(card.lines[3].text, "Replaces Heavy I.")
		t.eq(card.action.kind, "temper")
		t.eq(card.action.a, "u1")
		t.eq(card.action.b, "Keen")
		local heavy = ForgeUI.ConfirmFor(VIEW, "u1", "Heavy")
		t.eq(heavy.style, "cant")
		t.eq(heavy.lines[#heavy.lines].text, "1 more Sky Shards needed.")
		for _, line in ipairs(heavy.lines) do
			t.ok(string.find(line.text, "Replaces", 1, true) == nil, "same family: nothing replaced")
		end
	end)

	t.test("temper choices sit side by side only when each fits its label", function()
		t.eq(ForgeUI.ChoicesPerRow(556, 3), 3, "1280x720: three across")
		t.eq(ForgeUI.ChoicesPerRow(221, 3), 1, "phone: one per line")
		-- The screen is built once per client (the phone one here).
		local gui = ForgeUI.Ensure(Vector2.new(667, 375), true)
		ForgeUI.Show(VIEW, "Temper")
		local n = 0
		for _, d in ipairs(gui:GetDescendants()) do
			if d:IsA("Frame") and string.match(d.Name, "^Choice%d") then
				n += 1
				t.ok(d.Size.X.Offset >= ForgeUI.ChoiceMin, d.Name .. " is " .. d.Size.X.Offset .. " wide")
			end
		end
		t.eq(n, 3, "the axe's three tempers")
	end)

	t.test("long lines wrap instead of clipping", function()
		t.eq(ForgeUI.Lines("short", 13, 200), 1)
		t.ok(ForgeUI.Lines(VIEW.starfall.cost, 13, 200) >= 2)
	end)
end
