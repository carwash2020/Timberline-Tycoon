--!nocheck
-- TownMarkers (StarterPlayerScripts/TownMarkers, TWN-04): a marker over
-- each service (SELL LOGS, AXES, TRUCKS, BLUEPRINTS & GEAR, GONDOLA), each
-- on its own building; a UITheme card (cream FredokaOne on bark, an ink
-- edge, an icon chip drawn from Frames); unlit, not on top, hidden past
-- 350 studs, standing 16-34 studs up, clear of its roof; it fades within
-- 25 studs and while a shop is open; and from the spawn on an iPhone 14 in
-- landscape all six are on screen, apart, with text 14 px or more, clear
-- of the sawmill's crest.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame
	local loader = t.loader({
		services = {
			CollectionService = {},
			Players = { LocalPlayer = {} },
			GuiService = {},
			TextChatService = {},
			TweenService = {},
			UserInputService = {},
		},
	})
	local TownMarkers = loader:load("StarterPlayer/StarterPlayerScripts/TownMarkers")
	local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
	local WorldPlan = loader:load("ReplicatedStorage/Shared/World/WorldPlan")
	local BuildingArt = loader:load("ReplicatedStorage/Shared/Art/BuildingArt")
	local Kit = loader:load("ReplicatedStorage/Shared/Art/Kit")
	local C = UITheme.Colors
	local town = WorldPlan.Town()

	local function byName(name)
		for _, m in ipairs(TownMarkers.Markers) do
			if m.name == name then
				return m
			end
		end
		return nil
	end

	-- The marked parts where MapBuilder puts them (their names are checked
	-- against the built map in MapBuilder.spec), and the buildings they mark.
	local shops = {}
	for _, spot in ipairs(town.shops) do
		local model = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
		Kit.placeAt(model, spot.cframe)
		shops[spot.kind] = { model = model, spot = spot }
	end
	local station = BuildingArt.GondolaStation()
	Kit.placeAt(station, town.gondola)
	local sawmill = BuildingArt.Sawmill()
	Kit.placeAt(sawmill, town.sawmill)
	-- The sell station beside the mill: SELL LOGS floats over its pad.
	local sellStation = BuildingArt.SellStation(WorldPlan.SellPadWidth, WorldPlan.SellPadDepth)
	Kit.placeAt(sellStation, town.sellPad)
	local StoreBoard = loader:load("ReplicatedStorage/Shared/StoreBoard")
	local storeBoard = StoreBoard.Build()
	Kit.placeAt(storeBoard, StoreBoard.CFrame)
	local function partFor(marker)
		local top, name = marker.path[1], marker.path[2]
		if top == "StoreBoard" then
			local part = storeBoard:FindFirstChild(name)
			return part and part.CFrame.Position, storeBoard
		elseif top == "SellArea" and name == "SellZone" then
			return town.sellZone.Position, sellStation
		elseif top == "GondolaTown" and name == "Platform" then
			return station.PrimaryPart.CFrame.Position, station
		elseif shops[top] then
			local part = shops[top].model:FindFirstChild(name)
			return part and part.CFrame.Position, shops[top].model
		end
		return nil
	end

	-- A model's footprint (x, z) from its colliding parts.
	local function footprint(model)
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide then
				local h = d.Size / 2
				for _, sx in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = d.CFrame * Vector3.new(h.X * sx, 0, h.Z * sz)
						x0, x1, z0, z1 = math.min(x0, p.X), math.max(x1, p.X), math.min(z0, p.Z), math.max(z1, p.Z)
					end
				end
			end
		end
		return x0, x1, z0, z1
	end

	t.test("six markers, one per service and the store board, each over its own building", function()
		local expect = {
			{ "SellLogs", "SellArea", "SellZone", "SELL LOGS" },
			{ "Axes", "ToolShed", "Counter", "AXES" },
			{ "Trucks", "Dealership", "Counter", "TRUCKS" },
			{ "Gear", "HearthAndHome", "Counter", "GENERAL\nSTORE" },
			{ "Gondola", "GondolaTown", "Platform", "GONDOLA" },
			{ "Store", "StoreBoard", "Board", "STORE" },
		}
		t.eq(#TownMarkers.Markers, #expect)
		for _, e in ipairs(expect) do
			local m = byName(e[1])
			t.ok(m, e[1] .. " is there")
			t.eq(m.path, { e[2], e[3] })
			t.eq(m.text, e[4])
			local at, building = partFor(m)
			t.ok(at, e[1] .. "'s part exists")
			-- Floating over the building it names (the sell zone: the station's pad).
			local over = at + m.offset
			if building == sellStation then
				local pad = town.sellPad.Position
				t.ok(
					math.abs(over.X - pad.X) <= WorldPlan.SellPadWidth / 2
						and math.abs(over.Z - pad.Z) <= WorldPlan.SellPadDepth / 2,
					"SELL LOGS floats over the pad"
				)
			else
				local x0, x1, z0, z1 = footprint(building)
				t.ok(
					over.X > x0 and over.X < x1 and over.Z > z0 and over.Z < z1,
					string.format("%s floats over its building at (%.1f, %.1f)", e[1], over.X, over.Z)
				)
			end
		end
		-- Each stands clear above the roof in front of it (between it and the
		-- street), so its bottom edge never sinks into it (AlwaysOnTop off).
		for _, m in ipairs(TownMarkers.Markers) do
			local at, building = partFor(m)
			local over = at + m.offset
			local roof = -math.huge
			for _, d in ipairs(building:GetDescendants()) do
				if d:IsA("BasePart") then
					local h = d.Size / 2
					for _, sx in ipairs({ -1, 1 }) do
						for _, sy in ipairs({ -1, 1 }) do
							for _, sz in ipairs({ -1, 1 }) do
								local p = d.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
								if math.abs(p.X - over.X) <= 4 and p.Z <= over.Z then
									roof = math.max(roof, p.Y)
								end
							end
						end
					end
				end
			end
			t.ok(
				over.Y >= roof + 1,
				string.format("%s's bottom (%.1f up) clears the roof (%.1f)", m.name, over.Y, roof)
			)
		end
		-- The shops' chips are their accents.
		t.eq(byName("Axes").chip, shops.ToolShed.spot.accent)
		t.eq(byName("Trucks").chip, shops.Dealership.spot.accent)
		t.eq(byName("Gear").chip, shops.HearthAndHome.spot.accent)
		-- The store marker floats over the board and its arch, and the arch
		-- is wider than the chip so the chip never hides a lantern's post.
		local board = byName("Store")
		local boardAt = partFor(board)
		t.ok(boardAt.Y + board.offset.Y >= boardAt.Y + StoreBoard.BoardSize.Y / 2 + StoreBoard.BannerRise + 2)
		t.eq(board.offset.X, 0)
		t.eq(board.offset.Z, 0)
	end)

	t.test("each is a UITheme card: cream FredokaOne on bark, an ink edge, an icon chip drawn from Frames", function()
		for _, m in ipairs(TownMarkers.Markers) do
			for _, phone in ipairs({ true, false }) do
				local gui = TownMarkers.Build(m, phone)
				t.eq(gui.ClassName, "BillboardGui")
				local edge = gui:FindFirstChild("Edge")
				t.ok(edge and edge.BackgroundColor3 == C.Ink, m.name .. ": an ink drop edge")
				local face = edge:FindFirstChild("Face")
				t.ok(face and face.BackgroundColor3 == C.Bark, m.name .. ": a bark face")
				t.ok(face.Size.Y.Scale < 1, m.name .. ": the edge shows under the face")
				local label = face:FindFirstChild("Label")
				t.ok(label and label:IsA("TextLabel"), m.name .. ": a label")
				t.eq(label.Text, m.text)
				t.eq(label.Font, UITheme.Fonts.Heading)
				t.eq(label.TextColor3, C.Cream)
				t.eq(label.TextScaled, true)
				local chip = face:FindFirstChild("Chip")
				t.ok(chip and chip.BackgroundColor3 == m.chip, m.name .. ": a chip in its colour")
				local frames = 0
				for _, d in ipairs(chip:GetDescendants()) do
					if d:IsA("Frame") then
						frames += 1
					end
				end
				t.ok(frames >= 2, m.name .. ": an icon drawn in the chip")
				for _, d in ipairs(gui:GetDescendants()) do
					t.ok(
						not (d:IsA("ImageLabel") or d:IsA("ImageButton") or d:IsA("Decal")),
						m.name .. ": no uploaded image"
					)
					if d:IsA("GuiObject") then
						-- Everything inside is laid out in Scale, so it keeps its shape.
						t.eq(d.Size.X.Offset, 0, m.name .. "'s " .. d.Name .. " width offset")
						t.eq(d.Size.Y.Offset, 0, m.name .. "'s " .. d.Name .. " height offset")
					end
				end
				-- The chip is a square.
				local w = gui.Size.X.Scale * face.Size.X.Scale * chip.Size.X.Scale
				local h = gui.Size.Y.Scale * face.Size.Y.Scale * chip.Size.Y.Scale
				t.ok(math.abs(w - h) < 1e-6, m.name .. ": a square chip")
			end
		end
	end)

	t.test(
		"unlit, not drawn on top, hidden past 350 studs, 16 to 34 studs up, sized in studs with a pixel floor",
		function()
			for _, m in ipairs(TownMarkers.Markers) do
				local gui = TownMarkers.Build(m, true)
				t.eq(gui.LightInfluence, 0)
				t.eq(gui.AlwaysOnTop, false)
				t.eq(gui.MaxDistance, 350)
				t.eq(gui.ResetOnSpawn, false, "it lives in PlayerGui")
				t.eq(gui.Enabled, false, "hidden until its part streams in")
				t.ok(gui.StudsOffsetWorldSpace.Y >= 16 and gui.StudsOffsetWorldSpace.Y <= 34, m.name .. " 16-34 up")
				t.eq(gui.SizeOffset, roblox.Vector2.new(0, 0.5), m.name .. " stands on its point (its bottom edge)")
				local size = gui.Size
				t.ok(size.X.Scale > 0 and size.Y.Scale > 0, m.name .. " has a size in studs")
				t.ok(size.X.Offset > 0 and size.Y.Offset > 0, m.name .. " has a pixel floor")
				-- The same shape in studs and in pixels.
				t.ok(math.abs(size.X.Scale / size.Y.Scale - size.X.Offset / size.Y.Offset) < 0.05, m.name .. "'s shape")
				-- A phone gets a bigger floor than a computer.
				t.ok(TownMarkers.Size(m, true).Y.Offset > TownMarkers.Size(m, false).Y.Offset, m.name .. " phone floor")
			end
		end
	)

	t.test("it fades within 25 studs (back past 27) and while a shop screen is open", function()
		local V = TownMarkers.Visible
		t.eq(V(60, false, true), true)
		t.eq(V(24.9, false, true), false, "walked up: it fades")
		t.eq(V(26, false, false), false, "and stays gone on the line")
		t.eq(V(27.1, false, false), true, "walked away: back")
		t.eq(V(25.5, false, true), true, "and stays on the line coming in")
		t.eq(V(60, true, true), false, "a shop screen is open")
		t.eq(V(nil, false, false), true, "no character yet: shown")
		t.eq(V(nil, true, true), false)
		t.eq(TownMarkers.Check, 0.25)
		t.eq(TownMarkers.FadeWithin, 25)
	end)

	-- From the spawn on an iPhone 14 in landscape (844 x 390 points, a
	-- 70-degree field of view, the notch up to 47 points in from either
	-- side), with three cameras: eye level (the town preview's view 1),
	-- Roblox's default (12.5 studs behind the head, 15 degrees down) and
	-- zoomed out to 20 studs.
	t.test("from the spawn on a phone: all six on screen, apart, text 14 px or more, clear of the crest", function()
		local W, H, FOV, NOTCH = 844, 390, 70, 47
		local focal = (H / 2) / math.tan(math.rad(FOV / 2))
		local GLYPH = 0.66 -- a FredokaOne capital's width over its size, about
		local function camera(eye, look)
			look = look.Unit
			local right = look:Cross(Vector3.new(0, 1, 0)).Unit
			local up = right:Cross(look)
			return function(p)
				local v = p - eye
				local z = v:Dot(look)
				return W / 2 + v:Dot(right) / z * focal, H / 2 - v:Dot(up) / z * focal, z
			end
		end
		local head = town.spawn + Vector3.new(0, 4, 0)
		local pitch = math.rad(-15)
		local north = Vector3.new(0, math.sin(pitch), math.cos(pitch))
		local eye = Vector3.new(2, 6.5, 32)
		local cameras = {
			{ name = "eye level", view = camera(eye, Vector3.new(0, 9, 110) - eye) },
			{ name = "default", view = camera(head - north * 12.5, north) },
			{ name = "zoomed out", view = camera(head - north * 20, north) },
		}
		local crest
		for _, d in ipairs(sawmill:GetDescendants()) do
			if d:IsA("SurfaceGui") and d.Parent.Name == "Sign" then
				crest = d.Parent
			end
		end
		t.ok(crest, "the sawmill's crest board")
		for _, cam in ipairs(cameras) do
			local rects = {}
			for _, m in ipairs(TownMarkers.Markers) do
				local at = partFor(m) + m.offset
				local x, y, z = cam.view(at)
				t.ok(z > 0, m.name .. " is ahead")
				local size = TownMarkers.Size(m, true)
				local h = size.Y.Offset + size.Y.Scale * focal / z
				local w = size.X.Offset + size.X.Scale * focal / z
				-- It stands on its point (SizeOffset (0, 0.5)): its bottom edge there.
				local r = { name = m.name, x0 = x - w / 2, x1 = x + w / 2, y0 = y - h, y1 = y }
				table.insert(rects, r)
				local where =
					string.format("%s: %s at x %.0f..%.0f, y %.0f..%.0f", cam.name, m.name, r.x0, r.x1, r.y0, r.y1)
				-- The store board's chip is the tallest of the lot, over a
				-- board 31 studs from the spawn: it is on screen at eye level
				-- (the walk's view) and may ride off the top of the two
				-- tilted-down cameras, but it never lands on another chip.
				-- The showroom hall stands far to the east (x 114 to 262): 60 or
				-- more degrees off the walk, past the edge of a phone's view, so
				-- its TRUCKS marker is not asked to be on screen from the spawn.
				local mustShow = (m.name ~= "Store" or cam.name == "eye level") and m.name ~= "Trucks"
				if mustShow then
					t.ok(r.x0 >= NOTCH and r.x1 <= W - NOTCH and r.y0 >= 0 and r.y1 <= H, where .. " is off screen")
				end

				-- The label's text (TextScaled): as big as its lines' height
				-- allows, or its width, whichever is less.
				local lines, longest = TownMarkers.Lines(m.text)
				local face = TownMarkers.Build(m, true).Edge.Face
				local label = face.Label
				local labelW = w * face.Size.X.Scale * label.Size.X.Scale
				local labelH = h * face.Size.Y.Scale * label.Size.Y.Scale
				local text = math.min(labelH / lines, labelW / (longest * GLYPH))
				t.ok(text >= 14, string.format("%s: text %.1f px", where, text))
			end
			for i = 1, #rects do
				for j = i + 1, #rects do
					local a, b = rects[i], rects[j]
					local apart = a.x1 <= b.x0 or b.x1 <= a.x0 or a.y1 <= b.y0 or b.y1 <= a.y0
					t.ok(apart, string.format("%s: %s and %s overlap", cam.name, a.name, b.name))
				end
			end
			-- SELL LOGS keeps the sawmill's crest in view (it floats over the
			-- station, east of the mill, so it is well clear of it).
			local cx, cy, cz = cam.view(crest.CFrame.Position)
			local cw, ch = crest.Size.X * focal / cz, crest.Size.Y * focal / cz
			local sell = rects[1]
			t.eq(sell.name, "SellLogs")
			local clear = sell.y1 <= cy - ch / 2
				or sell.y0 >= cy + ch / 2
				or sell.x1 <= cx - cw / 2
				or sell.x0 >= cx + cw / 2
			t.ok(clear, cam.name .. ": SELL LOGS covers the TIMBERLINE SAWMILL crest")
		end
	end)
end
