--!nocheck
-- The town's models (Shared/Art/BuildingArt): the named parts other code
-- looks up, the part budgets, and the space gameplay needs kept clear.
return function(t)
	local roblox = t.roblox
	local V3, C3 = roblox.Vector3, roblox.Color3
	local loader = t.loader()
	local BuildingArt = loader:load("ReplicatedStorage/Shared/Art/BuildingArt")

	local SHOPS = {
		{ kind = "ToolShed", title = "TOOL SHED", accent = C3.fromRGB(150, 62, 44) },
		{ kind = "Dealership", title = "DEALERSHIP", accent = C3.fromRGB(47, 109, 181) },
		{ kind = "HearthAndHome", title = "HEARTH & HOME", accent = C3.fromRGB(122, 90, 60) },
	}

	local function near(a, b)
		return (a - b).Magnitude < 1e-3
	end

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function find(model, name)
		for _, p in ipairs(parts(model)) do
			if p.Name == name then
				return p
			end
		end
		return nil
	end

	-- A part's world-space bounding box.
	local function bounds(p)
		local cf, s = p.CFrame, p.Size / 2
		local lo, hi
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					local c = cf * V3.new(s.X * x, s.Y * y, s.Z * z)
					lo = if lo then lo:Min(c) else c
					hi = if hi then hi:Max(c) else c
				end
			end
		end
		return lo, hi
	end

	local function overlaps(p, lo, hi)
		local a, b = bounds(p)
		return a.X < hi.X and b.X > lo.X and a.Y < hi.Y and b.Y > lo.Y and a.Z < hi.Z and b.Z > lo.Z
	end

	-- Collidable parts (other than `except`) inside the box lo..hi.
	local function blockers(model, lo, hi, except)
		local out = {}
		for _, p in ipairs(parts(model)) do
			if p.CanCollide and p ~= except and overlaps(p, lo, hi) then
				table.insert(out, p.Name)
			end
		end
		return out
	end

	local function texts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("TextLabel") then
				out[d.Text] = true
			end
		end
		return out
	end

	t.test("the sawmill: a spinnable SawBlade, a smoking Smokestack, under budget", function()
		local mill = BuildingArt.Sawmill()
		local blade = mill:FindFirstChild("SawBlade")
		t.ok(blade and blade:IsA("BasePart"), "SawBlade is a direct child part")
		t.eq(blade.Shape, roblox.Enum.PartType.Cylinder)
		t.ok(math.abs(blade.CFrame.XVector.Z) > 0.999, "the blade's axis (its X) runs along world Z")
		t.ok(not blade.CanCollide and blade.Anchored, "the blade is anchored and doesn't collide")
		local welded = 0
		for _, p in ipairs(parts(mill)) do
			local weld = p:FindFirstChildOfClass("WeldConstraint")
			if weld and weld.Part0 == blade then
				t.ok(not p.Anchored and p.Massless, p.Name .. " turns with the blade")
				welded += 1
			end
		end
		t.ok(welded >= 18, "the teeth are welded to the blade")
		local stack = find(mill, "Smokestack")
		t.ok(stack and stack:FindFirstChildOfClass("Smoke"), "Smokestack has a Smoke")
		t.ok(stack.CFrame.Position.Y > 20, "the smoke leaves the top of the stack")
		t.ok(#parts(mill) <= 404, "sawmill parts: " .. #parts(mill))
		t.ok(texts(mill)["TIMBERLINE SAWMILL"], "the sign")
		-- The blade stays non-colliding (it spins). SawGuard covers its
		-- centre, and the rails close the way in from the deck and the east
		-- opening. All three are anchored and untouchable.
		local guard = find(mill, "SawGuard")
		t.ok(guard and guard.CanCollide and guard.Transparency == 1 and not guard.CanTouch, "SawGuard blocks the blade")
		t.ok(guard.CastShadow == false, "an invisible guard casts no shadow")
		local gLo, gHi = bounds(guard)
		local bladePos = blade.CFrame.Position
		t.ok(
			bladePos.X > gLo.X and bladePos.X < gHi.X and bladePos.Y > gLo.Y and bladePos.Y < gHi.Y,
			"the guard covers the blade"
		)
		local rails = 0
		for _, p in ipairs(parts(mill)) do
			if p.Name == "GuardRail" then
				rails += 1
				t.ok(p.CanCollide and p.Anchored and not p.CanTouch, "a guard rail blocks the way in")
			end
		end
		t.eq(rails, 2, "front rail and east rail")
	end)

	t.test("the sawmill has a clear stand for the foreman beside the office door", function()
		local mill = BuildingArt.Sawmill()
		local spot = find(mill, "MillForemanSpot")
		t.ok(spot and spot.Anchored and spot.Transparency == 1, "a transparent anchored stand")
		t.ok(not spot.CanCollide and not spot.CanQuery and not spot.CanTouch, "not a hitbox")
		t.ok(spot.CFrame.LookVector:Dot(V3.new(0, 0, -1)) > 0.99, "faces the road")
		t.ok(texts(mill)["DAILY JOBS"], "the chalkboard")
		local board = 0
		for _, p in ipairs(parts(mill)) do
			if p.Name == "JobPost" or p.Name == "JobBoard" then
				board += 1
			end
		end
		t.ok(board >= 1 and board <= 12, "the board is at most 12 parts: " .. board)
		-- Six studs of flat ground around the stand. The floor it stands on
		-- (top at or under 1.6) and roofs overhead (bottom above 7) are not
		-- something to walk into.
		local slo, shi = bounds(spot)
		for _, p in ipairs(parts(mill)) do
			if p ~= spot and p.CanCollide then
				local lo, hi = bounds(p)
				if hi.Y > 1.6 and lo.Y < 7 then
					local dx = math.max(slo.X - hi.X, lo.X - shi.X, 0)
					local dz = math.max(slo.Z - hi.Z, lo.Z - shi.Z, 0)
					local gap = math.sqrt(dx * dx + dz * dz)
					t.ok(gap >= 6 - 1e-3, string.format("%s is %.2f studs from the stand", p.Name, gap))
				end
			end
		end
	end)

	t.test("the sawmill leaves the sell pad clear", function()
		-- Its design-size numbers, scaled (BuildingArt.Scale, TWN-13); and at
		-- its design size too.
		for _, s in ipairs({ BuildingArt.Scale.Sawmill, 1 }) do
			local mill = BuildingArt.Sawmill(s)
			local front = -13.05 * s
			-- The pad (24 x 18) starts at its front; only things over 8 studs
			-- up (lanterns, the crest sign) reach over it.
			for _, p in ipairs(parts(mill)) do
				local lo, hi = bounds(p)
				if lo.X < 12 and hi.X > -12 and lo.Y < 8 then
					t.ok(lo.Z >= front, p.Name .. " reaches into the sell pad at z " .. lo.Z)
				end
				t.ok(lo.Y > -0.6 * s or p.Name == "Sawdust", p.Name .. " sinks into the ground") -- sawdust mounds are half buried
				t.ok(
					math.abs(lo.X) < 23 * s and math.abs(hi.X) < 23 * s and lo.Z > -15 * s and hi.Z < 17 * s,
					p.Name .. " is outside the footprint"
				)
			end
		end
	end)

	t.test(
		"TWN-13: the sawmill and the shops are built 1.5x (the showroom hall at its real size), with no more parts; counters stay waist high",
		function()
			t.eq(BuildingArt.Scale, { Sawmill = 1.5, ToolShed = 1.5, Dealership = 1, HearthAndHome = 1.5 })
			local function extent(model)
				local lo, hi
				for _, p in ipairs(parts(model)) do
					local a, b = bounds(p)
					lo = if lo then lo:Min(a) else a
					hi = if hi then hi:Max(b) else b
				end
				return hi - lo
			end
			local small, big = BuildingArt.Sawmill(1), BuildingArt.Sawmill()
			t.eq(#parts(big), #parts(small), "scaling adds no parts")
			t.ok(near(extent(big), extent(small) * 1.5), "the sawmill is 1.5x in every dimension")
			local blade, smallBlade = big:FindFirstChild("SawBlade"), small:FindFirstChild("SawBlade")
			t.ok(math.abs(blade.Size.Y - smallBlade.Size.Y * 1.5) < 1e-3, "the blade grew")
			for _, p in ipairs(parts(big)) do
				local weld = p:FindFirstChildOfClass("WeldConstraint")
				if weld and weld.Part0 == blade then
					t.ok(weld.Enabled and not p.Anchored, p.Name .. " stays welded and unanchored")
				end
			end
			for _, shop in ipairs(SHOPS) do
				local s = BuildingArt.Scale[shop.kind]
				local a = BuildingArt.Shop(shop.kind, shop.title, shop.accent, 1)
				local b = BuildingArt.Shop(shop.kind, shop.title, shop.accent)
				-- (the floorboards are laid by width, a plank or so either way)
				t.ok(
					math.abs(#parts(b) - #parts(a)) <= 4,
					shop.kind .. ": scaling adds no parts: " .. #parts(a) .. " vs " .. #parts(b)
				)
				-- The shell (its walls) is scaled; the interior and the door are added at
				-- their real size afterwards, so they are not part of this comparison.
				local function shell(model)
					local lo, hi
					for _, p in ipairs(parts(model)) do
						if p.Name == "Wall" then
							local c, d = bounds(p)
							lo = if lo then lo:Min(c) else c
							hi = if hi then hi:Max(d) else d
						end
					end
					return hi - lo
				end
				local ea, eb = shell(a), shell(b)
				t.ok(
					math.abs(eb.X - ea.X * s) < 0.05 and math.abs(eb.Z - ea.Z * s) < 0.05,
					shop.kind .. " walls are scaled across"
				)
				local ca, cb = a:FindFirstChild("Counter"), b:FindFirstChild("Counter")
				t.ok(near(cb.Size, ca.Size), shop.kind .. " counter keeps its size")
				local pa, pb = ca.CFrame.Position, cb.CFrame.Position
				local bottomA, bottomB = pa.Y - ca.Size.Y / 2, pb.Y - cb.Size.Y / 2
				t.ok(math.abs(bottomB - bottomA * s) < 1e-3, shop.kind .. " counter stands on the raised floor")
				t.ok(
					math.abs(pb.X - pa.X * s) < 1e-3 and math.abs(pb.Z - pa.Z * s) < 1e-3,
					shop.kind .. " counter moved out"
				)
				-- What stands on it came along (the register, the ledger).
				local onTop = 0
				for _, p in ipairs(parts(b)) do
					local lp = cb.CFrame:PointToObjectSpace(p.CFrame.Position)
					if
						p ~= cb
						and math.abs(lp.X) < cb.Size.X / 2
						and lp.Y > cb.Size.Y / 2
						and lp.Y < cb.Size.Y / 2 + 2
					then
						onTop += 1
					end
				end
				t.ok(onTop >= 3, shop.kind .. " keeps its counter top, register and ledger on it: " .. onTop)
			end
		end
	)

	t.test("shops: a direct-child Counter you can walk up to, under budget", function()
		for _, shop in ipairs(SHOPS) do
			local model = BuildingArt.Shop(shop.kind, shop.title, shop.accent)
			t.eq(model.Name, shop.kind)
			local counter = model:FindFirstChild("Counter")
			t.ok(counter and counter:IsA("BasePart"), shop.kind .. " has a direct-child Counter")
			t.ok(counter.CanCollide, shop.kind .. " counter collides")
			local cf = counter.CFrame
			t.ok(
				cf.XVector:Dot(V3.xAxis) > 0.999 and cf.ZVector:Dot(V3.zAxis) > 0.999,
				shop.kind .. " counter is axis-aligned"
			)
			-- Clear floor from the open front to the counter's customer side.
			local front = cf.Position.Z - counter.Size.Z / 2
			local x = cf.Position.X
			local s = BuildingArt.Scale[shop.kind]
			-- The general store's door is further south than the old cottage.
			local pathStart = if shop.kind == "HearthAndHome" then -19 elseif shop.kind == "ToolShed" then -19 else -26
			local hit = blockers(model, V3.new(x - 1.5, 0.7 * s, pathStart), V3.new(x + 1.5, 6, front - 0.05), counter)
			t.eq(hit, {}, shop.kind .. " path to the counter")
			-- Raised deliberately for the real stores: tables, shelf units, aisle
			-- signs, ceiling beams and lamps, the door (leaves, blocker, sensor,
			-- closed sign), and for the Dealership the whole showroom hall. Raised
			-- again for store polish: floors, facades (windows, awnings, planters),
			-- price tags, hanging goods, the cash desk's furnishings, and the Tool
			-- Shed's rack of eight real axe models (about 20 parts each).
			local budget = ({ ToolShed = 250, HearthAndHome = 250, Dealership = 250 })[shop.kind]
			t.ok(#parts(model) <= budget, shop.kind .. " parts: " .. #parts(model))
			t.ok(texts(model)[shop.title], shop.kind .. " sign shows its title")
			for _, p in ipairs(parts(model)) do
				local lo, hi = bounds(p)
				local minX, maxX, minZ, maxZ = -12 * s, 12.5 * s, -11.6 * s, 9.2 * s
				if shop.kind == "ToolShed" then
					-- 30 x 40.5 studs once scaled, plus the porch, the firewood and the sign.
					minX, maxX = -23, 23
					minZ = -(BuildingArt.ToolShedHalfDepth + 5) * s
					maxZ = (BuildingArt.ToolShedHalfDepth + 2.2) * s
				end
				if shop.kind == "HearthAndHome" then
					-- 49.5 x 39 studs once scaled, plus the sign over the door and
					-- the two door leaves swung out (built open).
					minX, maxX, minZ, maxZ = -27, 27, -31, 24.5
				end
				if shop.kind == "Dealership" then
					-- The showroom hall: its inside, its walls and roof overhang.
					local hall = loader:load("ReplicatedStorage/Shared/Art/DealershipLot").Hall()
					minX, maxX = -hall.innerW / 2 - 5, hall.innerW / 2 + 5
					minZ, maxZ = -hall.innerD / 2 - 6, hall.innerD / 2 + 5
				end
				t.ok(
					lo.X > minX and hi.X < maxX and lo.Z > minZ and hi.Z < maxZ,
					shop.kind .. " " .. p.Name .. " is outside the footprint"
				)
			end
		end
	end)

	t.test("an unknown shop kind still builds a store with a Counter", function()
		local model = BuildingArt.Shop("Bakery", "BAKERY", C3.fromRGB(200, 120, 80))
		t.ok(model:FindFirstChild("Counter"), "Counter")
	end)

	t.test("the gondola station: Platform is the 10 x 1 x 10 PrimaryPart, the cabin has room", function()
		local station = BuildingArt.GondolaStation()
		local platform = station.PrimaryPart
		t.ok(platform and platform.Name == "Platform", "PrimaryPart is Platform")
		t.ok(near(platform.Size, V3.new(10, 1, 10)), "Platform is 10 x 1 x 10")
		t.ok(math.abs(platform.CFrame.Position.Y + platform.Size.Y / 2 - 1) < 1e-4, "its top is at y = 1")
		t.ok(platform.CanCollide, "it collides")
		-- The 5 x 5 cabin rides from the platform's middle out the back (+Z).
		t.eq(blockers(station, V3.new(-2.6, 1.2, -2.6), V3.new(2.6, 7.5, 9), platform), {}, "cabin path")
		t.ok(#parts(station) <= 140, "station parts: " .. #parts(station))
	end)

	t.test("sign lamps (TWN-07): every shop sign and the lit signpost have gooseneck LampBulbs", function()
		local function bulbs(model)
			local out = {}
			for _, p in ipairs(parts(model)) do
				if p.Name == "LampBulb" then
					table.insert(out, p)
					local l = p:FindFirstChildOfClass("PointLight")
					t.ok(l and not l.Shadows, model.Name .. " bulb has a shadowless light")
					t.ok(not p.CanCollide and not p.CanQuery, model.Name .. " bulb is looks-only")
				end
			end
			return out
		end
		for _, shop in ipairs(SHOPS) do
			t.eq(#bulbs(BuildingArt.Shop(shop.kind, shop.title, shop.accent)), 2, shop.kind .. " sign lamps")
		end
		t.eq(#bulbs(BuildingArt.Signpost("SELL LOGS HERE", true)), 2, "a lit signpost has two lamps")
		t.eq(#bulbs(BuildingArt.Signpost("TO THE WOODS")), 0, "a plain signpost has none")
		-- The bulbs only glow at night: LightingController switches parts by
		-- name, so the name must be one of its GLOW_NAMES.
		local fs = require("@lune/fs")
		local controller = fs.readFile("src/StarterPlayer/StarterPlayerScripts/LightingController.luau")
		local list = string.match(controller, "local GLOW_NAMES[^=]*= {([^}]*)}")
		t.ok(list and string.find(list, "LampBulb = true", 1, true), "LampBulb is a night light")
		-- Two town signs are lit: SELL LOGS HERE, and the south exit
		-- (sawmill north, first grove south). The rest stay dark.
		local WorldPlan = loader:load("ReplicatedStorage/Shared/World/WorldPlan")
		for _, sign in ipairs(WorldPlan.Town().signs) do
			local should = sign.text == "SELL LOGS HERE" or string.find(sign.text, "FIRST GROVE", 1, true) ~= nil
			t.eq(sign.lit == true, should, sign.text .. " lit")
		end
	end)

	t.test(
		"bold name signs (phase 12): big boards over the street in the shop's colours, lit, out of the way",
		function()
			local function lum(c)
				return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
			end
			-- The name boards before phase 12, at design size (width, height).
			local OLD = {
				Sawmill = { 17, 3.4 },
				ToolShed = { 9.6, 2.3 },
				Dealership = { 11.2, 2.3 },
				HearthAndHome = { 8, 1.9 },
			}
			-- The sign's own parts: the board, its frame and posts, its lamps.
			local OWN =
				{ Sign = true, SignFrame = true, SignPost = true, LampArm = true, LampShade = true, LampBulb = true }
			local list = {
				{
					kind = "Sawmill",
					model = BuildingArt.Sawmill(),
					s = BuildingArt.Scale.Sawmill,
					title = "TIMBERLINE SAWMILL",
				},
			}
			for _, shop in ipairs(SHOPS) do
				table.insert(list, {
					kind = shop.kind,
					model = BuildingArt.Shop(shop.kind, shop.title, shop.accent),
					s = BuildingArt.Scale[shop.kind],
					title = shop.title,
					accent = shop.accent,
				})
			end
			for _, b in ipairs(list) do
				local kind, model, s = b.kind, b.model, b.s
				local sign = model:FindFirstChild("Sign")
				t.ok(sign and sign:IsA("BasePart"), kind .. ": a direct-child Sign board")
				-- Much bigger than before: 1.4x as wide or more (the Dealership's is
				-- held to its false front by its footprint and by the TRUCKS marker
				-- over its office), 1.3x as tall or more.
				local old = OLD[kind]
				t.ok(sign.Size.X >= old[1] * s * 1.4, string.format("%s: the board is %.1f wide", kind, sign.Size.X))
				t.ok(sign.Size.Y >= old[2] * s * 1.3, string.format("%s: the board is %.1f tall", kind, sign.Size.Y))
				-- Upright, facing the street (-Z).
				t.ok(sign.CFrame.LookVector:Dot(V3.new(0, 0, -1)) > 0.999, kind .. " faces the street")
				t.ok(sign.CFrame.UpVector.Y > 0.999, kind .. " stands upright")
				-- Its title, light on dark, as big as the board allows: Roblox draws
				-- TextScaled text 100 px tall at most, so the text box gets about
				-- that many pixels (Kit's 40 a stud would cap the letters at about
				-- 2.5 studs, however big the board).
				local front = false
				for _, gui in ipairs(sign:GetChildren()) do
					if gui:IsA("SurfaceGui") then
						local label = gui:FindFirstChildOfClass("TextLabel")
						t.eq(label.Text, b.title, kind .. " sign text")
						t.ok(label.TextScaled, kind .. ": the text scales to the board")
						front = front or gui.Face == roblox.Enum.NormalId.Front
						local pad = label:FindFirstChildOfClass("UIPadding")
						local box = sign.Size.Y
							* (1 - pad.PaddingTop.Scale - pad.PaddingBottom.Scale)
							* gui.PixelsPerStud
						t.ok(box >= 85 and box <= 101, string.format("%s: the text box is %.0f px tall", kind, box))
						t.ok(lum(label.TextColor3) - lum(sign.Color) >= 0.5, kind .. ": light ink on a dark board")
					end
				end
				t.ok(front, kind .. ": the title is on the front")
				-- The Tool Shed's and the Dealership's boards are their accents.
				if b.accent and kind ~= "HearthAndHome" then
					local c, a = sign.Color, b.accent
					local d = math.max(math.abs(c.R - a.R), math.abs(c.G - a.G), math.abs(c.B - a.B))
					t.ok(d < 1.5 / 255, kind .. ": the board is the shop's accent")
				end
				-- The board and its frame: looks only, above every doorway, behind
				-- the building's front, and nothing of the building in their way
				-- (no roof, wall or post through them).
				local lo, hi = bounds(sign)
				for _, p in ipairs(parts(model)) do
					if p.Name == "SignFrame" then
						local a, c = bounds(p)
						if
							a.Y > lo.Y - 1.5 * s
							and c.Y < hi.Y + 1.5 * s
							and a.X > lo.X - 1.5 * s
							and c.X < hi.X + 1.5 * s
						then
							lo, hi = lo:Min(a), hi:Max(c)
							t.ok(not p.CanCollide and not p.CanQuery, kind .. ": its frame is looks only")
						end
					end
				end
				t.ok(not sign.CanCollide and not sign.CanQuery, kind .. ": the board is looks only")
				t.ok(lo.Y >= 9 * s - 0.01, string.format("%s: the sign's bottom is %.1f up", kind, lo.Y))
				local front0 = math.huge
				for _, p in ipairs(parts(model)) do
					if p.CanCollide then
						front0 = math.min(front0, (bounds(p)).Z)
					end
				end
				t.ok(lo.Z >= front0 - 0.5 * s, string.format("%s: the sign hangs out past the building's front", kind))
				local tol = 0.02
				for _, p in ipairs(parts(model)) do
					if not OWN[p.Name] then
						local a, c = bounds(p)
						local through = a.X < hi.X - tol
							and c.X > lo.X + tol
							and a.Y < hi.Y - tol
							and c.Y > lo.Y + tol
							and a.Z < hi.Z - tol
							and c.Z > lo.Z + tol
						t.ok(not through, string.format("%s: its %s is in the sign's way", kind, p.Name))
					end
				end
				-- Lit at night: both lamps hang over the board's front, at its top.
				local lamps = 0
				for _, p in ipairs(parts(model)) do
					if p.Name == "LampBulb" then
						local at = p.CFrame.Position
						if
							at.X > lo.X
							and at.X < hi.X
							and at.Y > hi.Y - 0.5 * s
							and at.Y < hi.Y + 2 * s
							and at.Z < lo.Z
						then
							lamps += 1
						end
					end
				end
				t.eq(lamps, 2, kind .. ": two lamps over the sign")
			end
		end
	)

	t.test("street furniture keeps its named parts", function()
		local sign = BuildingArt.Signpost("TO THE WOODS")
		t.ok(find(sign, "Board") and texts(sign)["TO THE WOODS"], "Signpost board and text")
		local lamp = BuildingArt.LampPost()
		local glow = find(lamp, "LampGlow")
		t.ok(glow and glow:FindFirstChildOfClass("PointLight"), "LampGlow with its light")
		t.eq(glow.Material, roblox.Enum.Material.Neon)
		for _, length in ipairs({ 6, 18, 31 }) do
			local fence = BuildingArt.Fence(length)
			local lo, hi
			for _, p in ipairs(parts(fence)) do
				local a, b = bounds(p)
				lo = if lo then lo:Min(a) else a
				hi = if hi then hi:Max(b) else b
			end
			t.ok(math.abs((hi.X - lo.X) - length) < 1.2, "fence " .. length .. " spans its length")
		end
	end)

	t.test("a parking bay (TWN-06): the slot keeps its contract; lines, a stop bar, its number, a dim lamp", function()
		local Kit = loader:load("ReplicatedStorage/Shared/Art/Kit")
		local Enum = roblox.Enum
		local cf = roblox.CFrame.new(40, 0.1, 45)
		local size = loader:load("ReplicatedStorage/Shared/World/WorldPlan").ParkingSlotSize -- 10 x 60 (M1.5)
		local slot = Kit.part(roblox.Instance.new("Folder"), "ParkingSlot_7", size, cf, C3.fromRGB(186, 168, 140))
		slot.CanCollide = false
		BuildingArt.ParkingBay(slot, 7)
		-- What VehicleService reads is untouched; only the look changes.
		t.ok(
			near(slot.CFrame.Position, cf.Position) and slot.CFrame.LookVector:Dot(cf.LookVector) > 0.9999,
			"the slot keeps its CFrame"
		)
		t.ok(near(slot.Size, size), "the slot keeps its size")
		t.eq(slot.Transparency, 1)
		t.ok(not slot.CanCollide, "the slot still doesn't collide")
		local named, lights = {}, {}
		for _, d in ipairs(slot:GetDescendants()) do
			if d:IsA("BasePart") then
				named[d.Name] = (named[d.Name] or 0) + 1
				t.ok(
					not d.CanCollide and not d.CanQuery and not d.CanTouch and not d.CastShadow,
					d.Name .. " is looks-only"
				)
				-- Inside the bay (the stop bar runs 0.5 past each side, meeting
				-- the next bay's: slots stand 11 apart), not under the ground,
				-- and flat but for the lamp's light holder.
				local local_ = cf:PointToObjectSpace(d.CFrame.Position)
				local lo, hi = bounds(d)
				local half = (d.CFrame.RightVector * d.Size.X / 2).Magnitude
				t.ok(
					math.abs(local_.X) + (if d.Name == "StopBar" then half else 0) <= size.X / 2 + 0.5 + 1e-3
						and math.abs(local_.Z) <= size.Z / 2,
					d.Name .. " is in the bay"
				)
				t.ok(lo.Y >= -1e-3, d.Name .. " is above the ground")
				if d.Transparency < 1 then
					t.ok(hi.Y <= 0.25, d.Name .. " is flat paint")
				end
			elseif d:IsA("PointLight") then
				table.insert(lights, d)
			end
		end
		t.eq(named.BayLine, 2)
		t.eq(named.StopBar, 1)
		t.eq(named.BayNumber, 1)
		t.eq(named.LanternGlow, 2) -- the glowing plate and the light's holder
		for _, d in ipairs(slot:GetChildren()) do
			if d.Name == "BayLine" then
				t.ok(math.abs(d.Size.X - 0.35) < 1e-4, "bay lines are 0.35 wide")
				t.eq(d.Color:ToHex(), C3.fromRGB(230, 222, 200):ToHex())
				t.eq(d.Material, Enum.Material.SmoothPlastic)
			elseif d.Name == "StopBar" then
				t.ok(
					cf:PointToObjectSpace(d.CFrame.Position).Z < -(size.Z / 2 - 1.5),
					"the stop bar is at the head (-Z)"
				)
				t.ok(math.abs(d.Size.X - (size.X + 1)) < 1e-4, "the stop bar spans the slot and the stud to the next")
			end
		end
		t.ok(texts(slot)["7"], "the bay's number is painted on")
		-- One dim light, switched off until LightingController's dusk, in a
		-- LanternGlow (the name that lights it at night).
		t.eq(#lights, 1)
		local l = lights[1]
		t.eq(l.Parent.Name, "LanternGlow")
		t.eq(l.Range, 16)
		t.ok(math.abs(l.Brightness - 0.8) < 1e-4, "brightness 0.8")
		t.ok(not l.Shadows and not l.Enabled, "no shadows, off by day")
	end)

	t.test("the sell pad: SellPad doesn't collide, nothing on it does or stands tall", function()
		local art = BuildingArt.SellPad(24, 18)
		local pad = find(art, "SellPad")
		t.ok(pad, "SellPad")
		t.ok(near(pad.Size, V3.new(24, 0.2, 18)), "SellPad is w x 0.2 x d")
		t.ok(not pad.CanCollide, "SellPad CanCollide off")
		local gui = pad:FindFirstChildOfClass("SurfaceGui")
		t.ok(gui and gui.Face == roblox.Enum.NormalId.Top, "text on the top face")
		t.ok(texts(art)["SELL LOGS HERE"], "SELL LOGS HERE")
		for _, p in ipairs(parts(art)) do
			local _, hi = bounds(p)
			t.ok(not p.CanCollide and hi.Y <= 0.3, p.Name .. " is flat paint")
		end
	end)

	t.test(
		"the sell station: a flat pad with marked slots, a clear lane, a scale, a rack, a Weigh House and lights",
		function()
			local art = BuildingArt.SellStation(28, 32)
			local pad = find(art, "SellPad")
			t.ok(pad, "SellPad")
			t.ok(near(pad.Size, V3.new(28, 0.2, 32)), "SellPad is w x 0.2 x d")
			t.ok(not pad.CanCollide, "SellPad CanCollide off")
			local gui = pad:FindFirstChildOfClass("SurfaceGui")
			t.ok(gui and gui.Face == roblox.Enum.NormalId.Top, "text on the top face")
			t.ok(texts(art)["SELL LOGS HERE"], "SELL LOGS HERE")
			-- Marked slots: three for logs, two for planks, each labelled.
			local logs, planks, labels = 0, 0, 0
			for _, p in ipairs(parts(art)) do
				if p.Name == "SlotLabel" then
					labels += 1
					local label = p:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel")
					if label.Text == "LOGS" then
						logs += 1
					elseif label.Text == "PLANKS" then
						planks += 1
					end
					t.ok(not p.CanCollide, "a slot label is paint")
				end
			end
			t.eq({ labels, logs, planks }, { 5, 3, 2 }, "three LOGS slots and two PLANKS slots")
			-- Everything the station has: a scale (post + dial), a log rack, a
			-- Weigh House with its counter and sign, lanterns that glow at night.
			t.ok(find(art, "ScalePost") and find(art, "ScaleDial"), "the scale")
			t.ok(find(art, "LogRack") and find(art, "RackLog"), "the log rack")
			local house = art:FindFirstChild("WeighHouse")
			t.ok(house and find(house, "HouseCounter") and find(house, "HouseRoof"), "the Weigh House")
			t.ok(texts(art)["WEIGH HOUSE"], "WEIGH HOUSE sign")
			local glows = 0
			for _, p in ipairs(parts(art)) do
				if p.Name == "LanternGlow" then
					glows += 1
					t.ok(p:FindFirstChildOfClass("PointLight") ~= nil, "a lantern has a light")
				end
			end
			t.ok(glows >= 4, "lanterns on the rack and the Weigh House: " .. glows)
			t.ok(#parts(art) <= 330, "station parts: " .. #parts(art))
			-- The pad's own paint is flat and walkable; the lane the trucks use
			-- (6.3 studs either side of the middle) is clear of anything solid
			-- up to the rack across the back (z 11.5 from the pad's middle).
			for _, p in ipairs(parts(art)) do
				local lo, hi = bounds(p)
				if p.CanCollide then
					t.ok(
						not (hi.X > -6.3 and lo.X < 6.3 and lo.Z < 11.5 and hi.Z > -16),
						p.Name .. " stands in the lane"
					)
				elseif p.Name == "SellPad" or p.Name == "PadBorder" or p.Name == "SlotLine" or p.Name == "LaneLine" then
					t.ok(hi.Y <= 0.3, p.Name .. " is flat paint")
				end
			end
			-- The Weigh House's window faces the pad (west, -X), on the east side.
			local counter = find(house, "HouseCounter")
			t.ok(
				counter.CFrame.X > 14 and counter.CFrame.LookVector:Dot(V3.new(-1, 0, 0)) > 0.99,
				"its window faces the pad"
			)
			-- The 24 x 18 pad is still the old one, for the mesh.
			t.ok(
				near(find(BuildingArt.SellPad(24, 18), "SellPad").Size, V3.new(24, 0.2, 18)),
				"SellPad(24, 18) unchanged"
			)
		end
	)

	t.test("Murph's camp and the campfire: Embers with Fire and light", function()
		for _, model in ipairs({ BuildingArt.Campfire(), BuildingArt.Campsite() }) do
			local embers = find(model, "Embers")
			t.ok(embers, model.Name .. " has Embers")
			t.ok(embers:FindFirstChildOfClass("Fire") and embers:FindFirstChildOfClass("PointLight"), "Fire + light")
		end
		local camp = BuildingArt.Campsite()
		t.ok(#parts(camp) <= 110, "camp parts: " .. #parts(camp))
		-- Room for Murph in front of the fire.
		t.eq(blockers(camp, V3.new(-1, 0.2, -4), V3.new(1, 5, -2.4)), {}, "Murph's spot")
	end)

	t.test("every prop builds; unknown names build a crate", function()
		local names = BuildingArt.PropNames()
		for _, name in ipairs({
			"LogPile",
			"Crate",
			"Barrel",
			"Bench",
			"Well",
			"Cart",
			"SawdustPile",
			"WaterTower",
			"Mailbox",
			"FlowerBox",
			"Haybale",
			"Wheelbarrow",
			"ToolRack",
			"Lantern",
			"Planter",
			"MillBell",
		}) do
			t.ok(table.find(names, name), name .. " is listed")
		end
		for i, name in ipairs(names) do
			local model = BuildingArt.Prop(name, i)
			t.eq(model.Name, name)
			t.ok(#parts(model) > 0 and #parts(model) <= 60, name .. " parts: " .. #parts(model))
		end
		local odd = BuildingArt.Prop("Teapot", 3)
		t.eq(odd.Name, "Teapot")
		t.ok(find(odd, "Crate"), "an unknown prop is a crate")
		t.ok(find(BuildingArt.Prop("Lantern", 1), "LanternGlow"), "the Lantern prop glows")
	end)

	t.test("town trees: only the Trunk collides, seated in a stone ring outside the roots, under budget", function()
		for _, woodId in ipairs({ "birch", "maple", "pine" }) do
			for _, scale in ipairs({ 0.82, 1, 1.22 }) do
				for seed = 1, 4 do
					local label = string.format("%s %.2f seed %d", woodId, scale, seed)
					local tree = BuildingArt.TownTree(woodId, seed, scale)
					t.eq(tree.Name, "TownTree")
					local trunk = tree.PrimaryPart
					t.ok(trunk and trunk.Name == "Trunk", label .. ": PrimaryPart Trunk")
					t.ok(trunk.CanCollide and trunk.CanQuery, label .. ": the trunk collides")
					t.eq(#tree:GetTags(), 0, label .. " is tagged")
					local reach, stones = 0, 0
					local inner = math.huge
					for _, p in ipairs(parts(tree)) do
						if p ~= trunk then
							t.ok(
								not p.CanCollide and not p.CanQuery and not p.CanTouch,
								label .. ": " .. p.Name .. " is decoration"
							)
						end
						t.eq(#p:GetTags(), 0, label .. ": " .. p.Name .. " is tagged")
						if p.Name == "Root" or p.Name == "RingStone" then
							-- The nearest and farthest its footprint comes to the trunk's axis.
							local h = p.Size / 2
							local near, far = math.huge, 0
							for _, x in ipairs({ -1, 1 }) do
								for _, z in ipairs({ -1, 1 }) do
									for _, y in ipairs({ -1, 1 }) do
										local c = p.CFrame * V3.new(h.X * x, h.Y * y, h.Z * z)
										local r = math.sqrt(c.X * c.X + c.Z * c.Z)
										near, far = math.min(near, r), math.max(far, r)
									end
								end
							end
							if p.Name == "Root" then
								reach = math.max(reach, far)
							else
								stones += 1
								-- A stone's middle-of-inner-face, nearer than its corners.
								local mid = p.CFrame.Position
								inner = math.min(inner, math.sqrt(mid.X * mid.X + mid.Z * mid.Z) - h.Z)
							end
						end
					end
					t.ok(stones >= 7, label .. ": a ring of stones")
					t.ok(
						inner > reach,
						string.format("%s: the ring (%.2f) sits outside the roots (%.2f)", label, inner, reach)
					)
					t.ok(find(tree, "RingSoil"), label .. ": soil in the ring")
					t.ok(#parts(tree) <= 70, label .. " parts: " .. #parts(tree))
				end
			end
		end
		-- An unknown wood grows a birch.
		t.eq(#parts(BuildingArt.TownTree("teak", 1, 1)), #parts(BuildingArt.TownTree("birch", 1, 1)))
	end)

	t.test("town greenery: bushes and flower beds are looks only, a rock's stones collide, deterministic", function()
		for _, kind in ipairs({ "bush", "flowers", "rock", "mystery" }) do
			for _, size in ipairs({ 1.6, 2.4, 3 }) do
				local model = BuildingArt.Greenery(kind, size, 11, nil)
				local all = parts(model)
				t.ok(#all > 0 and #all <= 40, kind .. " parts: " .. #all)
				local stones = 0
				for _, p in ipairs(all) do
					if kind == "rock" and p.Name == "Rock" then
						-- COL-01: a rock you'd walk into stops you, like a boulder.
						stones += 1
						t.ok(p.CanCollide and p.CanQuery, "a rock's " .. p.Name .. " collides")
					else
						t.ok(
							not p.CanCollide and not p.CanQuery and not p.CanTouch,
							kind .. ": " .. p.Name .. " is decoration"
						)
					end
					local lo, hi = bounds(p)
					t.ok(lo.Y > -0.4 * size and hi.Y < size + 1.5, kind .. ": " .. p.Name .. " sits on the ground")
				end
				t.eq(stones, if kind == "rock" then 3 else 0, kind .. "'s solid stones")
				local again = parts(BuildingArt.Greenery(kind, size, 11, nil))
				t.eq(#again, #all)
				for i = 1, #all do
					t.ok(
						all[i].CFrame == again[i].CFrame and all[i].Color == again[i].Color,
						kind .. ": the same every time"
					)
				end
			end
		end
		t.eq(BuildingArt.Greenery("mystery", 2, 1).Name, "Bush", "an unknown kind is a bush")
		t.eq(BuildingArt.Greenery("tree", 1, 1, "pine").Name, "TownTree")
	end)

	t.test("the Sky Bin: a 4 x 4 x 4 SkyBin at y = 2 with its text on SurfaceGuis", function()
		local art = BuildingArt.SkyBin()
		local bin = art:FindFirstChild("SkyBin")
		t.ok(bin and bin.CanCollide, "SkyBin collides")
		t.ok(near(bin.Size, V3.new(4, 4, 4)), "SkyBin is 4 x 4 x 4")
		t.ok(math.abs(bin.CFrame.Position.Y - 2) < 1e-4, "centred at y = 2")
		local labels = 0
		for _, gui in ipairs(bin:GetChildren()) do
			if gui:IsA("SurfaceGui") and gui:FindFirstChildWhichIsA("TextLabel", true) then
				labels += 1
			end
		end
		t.eq(labels, 2)
	end)

	t.test("the isle pieces keep CloudChute and StarfallForge", function()
		local chute = find(BuildingArt.CloudChute(), "CloudChute")
		t.ok(chute and chute.CanCollide, "CloudChute collides")
		t.ok(near(chute.Size, V3.new(4, 3, 4)), "CloudChute is 4 x 3 x 4")
		t.ok(math.abs(chute.CFrame.Position.Y - 1.5) < 1e-4, "centred at y = 1.5")
		local forge = BuildingArt.StarfallForge()
		local anvil = forge:FindFirstChild("StarfallForge")
		t.ok(anvil and anvil:FindFirstChildOfClass("PointLight"), "StarfallForge glows")
		t.ok(anvil:FindFirstChildOfClass("ParticleEmitter"), "and sparkles")
	end)

	t.test("bridges: planks' tops run through both ends; a zero-length bridge is empty", function()
		local a, b = V3.new(10, 50, 0), V3.new(10, 52, 30)
		local bridge = BuildingArt.Bridge(a, b, 6)
		t.ok(find(bridge, "Deck"), "Deck")
		local dir = (b - a).Unit
		for _, p in ipairs(parts(bridge)) do
			if p.Name == "Plank" then
				local top = p.CFrame * V3.new(0, p.Size.Y / 2, 0)
				local along = (top - a):Dot(dir)
				local onLine = a + dir * along
				t.ok((top - onLine).Magnitude < 0.2, "plank top on the a-b line")
				t.ok(p.CanCollide, "planks are walkable")
			end
		end
		t.eq(#parts(BuildingArt.Bridge(a, a, 6)), 0)
	end)

	t.test("bridges (COL-01): an invisible guard under each rope, deck to rail height, end to end", function()
		local a, b, width = V3.new(10, 50, 0), V3.new(10, 52, 30), 6
		local bridge = BuildingArt.Bridge(a, b, width)
		local span, dir = (b - a).Magnitude, (b - a).Unit
		local across = V3.new(-dir.Z, 0, dir.X).Unit -- level, square to the bridge
		local h = BuildingArt.BridgeGuardHeight
		t.ok(math.abs(h - 3.2) < 1e-6, "guards reach the rope rails' height at the posts")
		local guards, sides = {}, {}
		for _, p in ipairs(parts(bridge)) do
			if p.Name == "BridgeGuard" then
				table.insert(guards, p)
				t.ok(p.CanCollide, "a guard collides")
				t.eq(p.Transparency, 1)
				t.ok(not p.CanTouch and not p.CastShadow, "a guard is never touched and casts no shadow")
				t.ok(p.Anchored, "anchored")
				t.ok(math.abs(p.Size.Z - span) < 1e-3, "a guard runs the bridge's whole length")
				t.ok(p.CFrame.LookVector:Dot(dir) > 0.9999 or p.CFrame.LookVector:Dot(dir) < -0.9999, "along it")
				-- Its middle under a rope: width / 2 + 0.25 to the side of the a-b line.
				local mid = p.CFrame.Position - (a + b) / 2
				local side = mid:Dot(across)
				t.ok(math.abs(math.abs(side) - (width / 2 + 0.25)) < 1e-3, "under the rope: " .. side)
				table.insert(sides, if side > 0 then 1 else -1)
				-- Its inner face at the deck's edge, so the walkway stays `width` wide.
				t.ok(math.abs(side) - p.Size.X / 2 >= width / 2 - 1e-3, "the walkway stays clear")
				-- From under the planks' tops (the a-b line) up to h over it.
				local top = p.CFrame * V3.new(0, p.Size.Y / 2, 0)
				local bottom = p.CFrame * V3.new(0, -p.Size.Y / 2, 0)
				local function overLine(v)
					local onLine = a + dir * (v - a):Dot(dir)
					return (v - onLine):Dot(p.CFrame.UpVector)
				end
				t.ok(math.abs(overLine(top) - h) < 0.05, "its top at rail height")
				t.ok(overLine(bottom) < -0.2, "its bottom under the planks' tops")
			end
		end
		t.eq(#guards, 2, "one guard each side")
		t.ok(sides[1] ~= sides[2], "on both sides")
	end)

	t.test("COL-01: the town's solid-looking props and fittings collide", function()
		-- Every part called `name` in `model` (at least one) collides and can be
		-- clicked; `count` of them if given.
		local function solid(model, name, label, count)
			local n, all = 0, 0
			for _, p in ipairs(parts(model)) do
				if p.Name == name then
					all += 1
					if p.CanCollide and p.CanQuery then
						n += 1
					end
				end
			end
			t.ok(all > 0 and n == all, string.format("%s: %d of %d %ss collide", label, n, all, name))
			if count then
				t.eq(all, count, label .. ": " .. name .. "s")
			end
		end
		local function decor(model, name, label)
			local all = 0
			for _, p in ipairs(parts(model)) do
				if p.Name == name then
					all += 1
					t.ok(not p.CanCollide and not p.CanQuery, label .. ": " .. p.Name .. " is looks only")
				end
			end
			t.ok(all > 0, label .. " has a " .. name)
		end
		for seed = 1, 6 do
			solid(BuildingArt.Prop("LogPile", seed), "Log", "a log pile", 6) -- every row, not just the bottom
			solid(BuildingArt.Prop("Bench", seed), "BenchBack", "a bench", 2)
			solid(BuildingArt.Prop("Bench", seed), "Seat", "a bench", 2)
			local cart = BuildingArt.Prop("Cart", seed)
			solid(cart, "CartSide", "a hand cart", 4)
			solid(cart, "Wheel", "a hand cart", 2)
			solid(cart, "Log", "a hand cart's load", 3)
			solid(BuildingArt.Prop("ToolRack", seed), "Rail", "a tool rack", 2)
			solid(BuildingArt.Prop("ToolRack", seed), "Post", "a tool rack", 2)
			-- The mailbox: its box (over the post all round, at chest height)
			-- collides; the thin post and the round lid are looks only.
			local mailbox = BuildingArt.Prop("Mailbox", seed)
			local boxes = 0
			for _, p in ipairs(parts(mailbox)) do
				if p.Name == "Mailbox" and p.Shape == roblox.Enum.PartType.Block then
					boxes += 1
					t.ok(p.CanCollide and p.CanQuery, "the mailbox's box collides")
					local lo, hi = bounds(p)
					t.ok(lo.Y < 4 and hi.Y > 3.4, "at chest height")
					t.ok(hi.X - lo.X > 1 and hi.Z - lo.Z > 1.6, "wider than its post")
				end
			end
			t.eq(boxes, 1)
			decor(mailbox, "Post", "the mailbox")
			-- The wheelbarrow stands on the plaza by the sell pad: looks only.
			for _, p in ipairs(parts(BuildingArt.Prop("Wheelbarrow", seed))) do
				t.ok(not p.CanCollide, "the wheelbarrow's " .. p.Name .. " is looks only")
			end
		end
		local mill = BuildingArt.Sawmill()
		solid(mill, "Log", "the sawmill (slip, log deck, carriage)", 8)
		solid(mill, "Crate", "the sawmill", 2)
		solid(mill, "Carriage", "the sawmill")
		local shed = BuildingArt.Shop(SHOPS[1].kind, SHOPS[1].title, SHOPS[1].accent)
		solid(shed, "GrindTrough", "the Tool Shed's grindstone", 1)
		solid(shed, "Grindstone", "the Tool Shed's grindstone", 1)
		solid(shed, "DisplayTable", "the Tool Shed's display tables", 2)
		solid(shed, "GoldTable", "the Tool Shed's Robux table", 1)
		solid(shed, "Log", "the Tool Shed's firewood", 3)
		solid(shed, "ChoppingBlock", "the Tool Shed's chopping block", 1)
		local garage = BuildingArt.Shop(SHOPS[2].kind, SHOPS[2].title, SHOPS[2].accent)
		solid(garage, "Tyre", "the Dealership's tyre stack", 4)
		local store = BuildingArt.Shop(SHOPS[3].kind, SHOPS[3].title, SHOPS[3].accent)
		solid(store, "Counter", "the general store", 1)
		solid(store, "Shelf", "the general store", 4)
		local aisle = 0
		for _, p in ipairs(parts(store)) do
			if p.Name == "Shelf" and p.CanCollide then
				aisle += 1
				-- (The islands' inner edges stand 5 studs either side of the middle: a 10-stud aisle.)
				t.ok(math.abs(p.CFrame.Position.X) - p.Size.X / 2 >= 5 - 1e-6, "shelves stay out of the centre aisle")
			end
		end
		t.eq(aisle, 4, "two shelves each side")
		-- The gondola station's lectern stand (not its sloped top).
		local stands = 0
		for _, p in ipairs(parts(BuildingArt.GondolaStation())) do
			if p.Name == "Lectern" and p.CanCollide then
				stands += 1
				t.ok(near(p.Size, V3.new(1.2, 2.6, 0.9)), "the lectern's stand")
			end
		end
		t.eq(stands, 1)
		-- Murph's camp: the log seats, the firewood behind the tent, its rocks.
		local camp = BuildingArt.Campsite()
		solid(camp, "Log", "Murph's camp", 7)
		solid(camp, "Rock", "Murph's camp", 6)
		-- Signposts: the posts collide; the board only when asked (the biome
		-- road signs); the rocks at their feet never.
		local WorldPlan = loader:load("ReplicatedStorage/Shared/World/WorldPlan")
		for _, sign in ipairs(WorldPlan.Town().signs) do
			-- As MapBuilder builds the town's: people walk under TO THE WOODS's
			-- board (the spawn to Murph), a Logging Rig drives under SELL LOGS
			-- HERE's.
			local post = BuildingArt.Signpost(sign.text, sign.lit)
			solid(post, "Post", sign.text, 2)
			decor(post, "Board", sign.text)
			decor(post, "Rock", sign.text)
		end
		local road = BuildingArt.Signpost("THE HILLS\npine · maple", nil, true)
		solid(road, "Board", "a road sign", 1)
		decor(road, "Rock", "a road sign")
		decor(BuildingArt.Signpost("SELL LOGS HERE", true), "Board", "the lit signpost")
	end)

	t.test("art rules: CFrame only, deterministic, decoration can't be clicked", function()
		local models = { BuildingArt.Sawmill(), BuildingArt.GondolaStation(), BuildingArt.Campsite() }
		for _, shop in ipairs(SHOPS) do
			table.insert(models, BuildingArt.Shop(shop.kind, shop.title, shop.accent))
		end
		for _, model in ipairs(models) do
			for _, p in ipairs(parts(model)) do
				local setPosition = pcall(function()
					return p.Position
				end)
				t.ok(not setPosition, model.Name .. " " .. p.Name .. " was placed with .Position")
				if not p.CanCollide and p.Name ~= "SellPad" and p.Name ~= "DoorSensor" then
					t.ok(not p.CanQuery and not p.CanTouch, model.Name .. " " .. p.Name .. " decoration can be clicked")
				end
			end
		end
		local one, two = parts(BuildingArt.Sawmill()), parts(BuildingArt.Sawmill())
		t.eq(#one, #two)
		for i = 1, #one do
			t.ok(one[i].CFrame == two[i].CFrame and one[i].Color == two[i].Color, "same sawmill every time")
		end
	end)

	t.test("shops: the front opening is about 12 studs wide or more, so a carried box walks in", function()
		local StoreStock = loader:shared("StoreStock")
		t.ok(StoreStock ~= nil)
		for _, shop in ipairs(SHOPS) do
			local model = BuildingArt.Shop(shop.kind, shop.title, shop.accent)
			local s = BuildingArt.Scale[shop.kind]
			local front = if shop.kind == "ToolShed"
				then -BuildingArt.ToolShedHalfDepth * s
				elseif shop.kind == "Dealership" then -loader
					:load("ReplicatedStorage/Shared/Art/DealershipLot")
					.Hall().innerD / 2 - 0.4
				else -BuildingArt.HearthHalfDepth * s
			-- Chest height, in the wall's own line: what a carried box meets.
			local best, run = 0, 0
			local spec = BuildingArt.DoorSpec(shop.kind, s, shop.accent)
			local centre = (spec.x0 + spec.x1) / 2
			for i = -80, 80 do
				local x = centre + i * 0.25
				local hit = blockers(model, V3.new(x - 0.12, 1.8, front - 0.3), V3.new(x + 0.12, 5.5, front + 0.3))
				if #hit == 0 then
					run += 0.25
					best = math.max(best, run)
				else
					run = 0
				end
			end
			t.ok(best >= 14, string.format("%s's door is %.2f wide", shop.kind, best))
		end
	end)

	t.test("the Tool Shed's boxes stand on its tables, and Hearth & Home's on its shelves and islands", function()
		local StoreStock = loader:shared("StoreStock")
		local RobuxShelf = loader:shared("RobuxShelf")
		-- A box sits with its bottom on the top, within a hair, and wholly on
		-- it (its footprint inside the board's), so a big box never overhangs.
		local function sits(model, names, place, size, label)
			local bottom = place.y - size.Y / 2
			local ok = false
			for _, p in ipairs(parts(model)) do
				if names[p.Name] then
					local lo, hi = bounds(p)
					if
						place.x - size.X / 2 >= lo.X - 0.01
						and place.x + size.X / 2 <= hi.X + 0.01
						and place.z - size.Z / 2 >= lo.Z - 0.01
						and place.z + size.Z / 2 <= hi.Z + 0.01
						and math.abs(hi.Y - bottom) < 0.06
					then
						ok = true
					end
				end
			end
			t.ok(ok, label .. " rests wholly on a table or shelf top")
		end
		-- A shelf box stands on a PLINTH (a block in its accent colour) which stands
		-- on its row's STEP of the stepped display unit.
		local function standsOnPlinth(model, steps, place, size, label)
			sits(model, { Plinth = true }, place, size, label .. " (box on plinth)")
			local plinthPlace = { x = place.x, z = place.z, y = place.y - StoreStock.PlinthHeight }
			sits(model, steps, plinthPlace, size, label .. " (plinth on step)")
		end
		local shed = BuildingArt.Shop("ToolShed", "TOOL SHED", C3.fromRGB(150, 62, 44))
		for _, place in ipairs(StoreStock.Placements("ToolShed")) do
			standsOnPlinth(shed, { DisplayTableStep = true }, place, place.size, place.slotId)
		end
		local robuxSize = loader:shared("BoxSize").Class(RobuxShelf.Class).size
		for _, place in ipairs(RobuxShelf.Placements()) do
			sits(shed, { GoldTableTop = true }, place, robuxSize, place.slotId)
		end
		local hearth = BuildingArt.Shop("HearthAndHome", "STORE", C3.fromRGB(122, 90, 60))
		for _, place in ipairs(StoreStock.Placements("HearthAndHome")) do
			local depth = place.count * place.size.Z + (place.count - 1) * (place.pitch - place.size.Z)
			standsOnPlinth(hearth, { ShelfStep = true }, place, V3.new(place.size.X, place.size.Y, depth), place.slotId)
		end
	end)

	t.test("the Tool Shed is deeper than it was, and its meshes stretch to match, along Z only", function()
		t.eq(BuildingArt.ToolShedHalfDepth, 15)
		local stretch = BuildingArt.MeshStretch("ToolShed")
		t.eq(stretch.X, 1)
		t.eq(stretch.Y, 1)
		t.ok(math.abs(stretch.Z - 15 / 7) < 1e-6)
		for _, kind in ipairs({ "Dealership", "HearthAndHome", "Sawmill" }) do
			t.eq(BuildingArt.MeshStretch(kind), V3.one, kind .. " is not stretched")
		end
		-- Nothing has to be rebuilt at the old depth: the walls reach the new back.
		local model = BuildingArt.Shop("ToolShed", "TOOL SHED", C3.fromRGB(150, 62, 44))
		local backZ = -math.huge
		for _, p in ipairs(parts(model)) do
			if p.Name == "Wall" or p.Name == "Footing" then
				local _, hi = bounds(p)
				backZ = math.max(backZ, hi.Z)
			end
		end
		t.ok(backZ >= 15 * BuildingArt.Scale.ToolShed - 1e-6, "the back wall is 45 studs from the front")
	end)

	t.test("the gold table carries the shelf's name, and only the Tool Shed has one", function()
		local shed = BuildingArt.Shop("ToolShed", "TOOL SHED", C3.fromRGB(150, 62, 44))
		t.ok(find(shed, "GoldTable") ~= nil)
		t.ok(texts(shed)["ROBUX SHELF"], "the sign over it says ROBUX SHELF")
		t.eq(find(shed, "GoldTrim"), nil, "no plinth board in front of the table")
		for _, kind in ipairs({ "Dealership", "HearthAndHome" }) do
			local other = BuildingArt.Shop(kind, kind, C3.fromRGB(90, 60, 40))
			t.eq(find(other, "GoldTable"), nil, kind .. " has no gold table")
		end
	end)

	t.test("new buildings: signatures, footprints, named bits, no prices", function()
		local function extent(model)
			local lo, hi
			for _, p in ipairs(parts(model)) do
				local a, b = bounds(p)
				lo = if lo then lo:Min(a) else a
				hi = if hi then hi:Max(b) else b
			end
			return lo, hi
		end
		local function noPrice(model)
			for text in pairs(texts(model)) do
				t.ok(string.find(text, "%$", 1, true) == nil, model.Name .. " prints a price: " .. text)
			end
		end
		local kiosk = BuildingArt.GateKiosk(C3.fromRGB(58, 111, 216))
		local lo, hi = extent(kiosk)
		t.ok(hi.X - lo.X <= 8.2 and hi.Z - lo.Z <= 6.2, "gate kiosk is 8 x 6")
		t.ok(lo.Y >= -0.01, "feet on the ground")
		t.ok(#parts(kiosk) <= 40, "kiosk parts")
		noPrice(kiosk)
		local odds = BuildingArt.OddsAndEnds()
		lo, hi = extent(odds)
		t.ok(hi.X - lo.X <= 20.4 and hi.Z - lo.Z <= 16.4, "odds and ends lot")
		t.ok(texts(odds)["CHARGES"], "charges sign")
		local crates = 0
		for _, p in ipairs(parts(odds)) do
			if p.Name == "Crate" or p.Name == "CratePost" or p.Name == "CrateBand" or p.Name == "CrateSlat" then
				crates += 1
			end
		end
		t.eq(crates, 26, "two 13-part crates")
		noPrice(odds)
		local spark = BuildingArt.Sparkworks()
		local board = find(spark, "DemoBoard")
		t.ok(board and math.abs(board.Size.X - 6) < 0.01 and math.abs(board.Size.Y - 4) < 0.01, "DemoBoard 6 x 4")
		t.eq(board:FindFirstChildOfClass("SurfaceGui"), nil, "the demo board is empty")
		lo, hi = extent(spark)
		t.ok(hi.X - lo.X <= 20.4 and hi.Z - lo.Z <= 16.4, "sparkworks lot")
		t.ok(#parts(BuildingArt.SkyForgeCourt()) < 300, "forge court budget")
		local court = BuildingArt.SkyForgeCourt()
		t.ok(find(court, "Anvil"):FindFirstChild("TemperSpot"), "TemperSpot")
		t.ok(find(court, "OrderBoard"):FindFirstChild("OrderBoard"), "OrderBoard gui")
		local keeper = nil
		for _, d in ipairs(court:GetDescendants()) do
			if d.Name == "KeeperSpot" then
				keeper = d
			end
		end
		t.ok(keeper and keeper:IsA("Attachment"), "KeeperSpot")
		-- Lune attachments have no WorldCFrame; the parent part is axis-aligned.
		local world = (keeper.Parent :: BasePart).CFrame * keeper.CFrame
		t.ok(world.LookVector:Dot(V3.new(0, 0, -1)) > 0.99, "KeeperSpot faces -Z")
		for _, name in ipairs({ "Socket_FrostRelic", "Socket_EmberRelic", "Socket_GloamRelic", "Socket_LumenRelic" }) do
			local found = false
			for _, d in ipairs(court:GetDescendants()) do
				if d.Name == name then
					found = true
				end
			end
			t.ok(found, name)
		end
		local map = BuildingArt.PlotMapBoard()
		t.ok(find(map, "Board"):FindFirstChild("Map"), "Map gui")
		lo, hi = extent(map)
		t.ok(hi.X - lo.X <= 10.2 and hi.Y - lo.Y >= 6, "plot map 10 wide")
		local arch = BuildingArt.ArrivalArch()
		lo, hi = extent(arch)
		t.ok(math.abs((hi.X - lo.X) - 12) < 0.2, "arch is 12 wide")
		local turn = BuildingArt.SkyTurnstile()
		t.ok(texts(turn)["Gondola Pass"], "gondola pass sign")
		lo, hi = extent(turn)
		t.ok(hi.X - lo.X <= 4.2 and hi.Z - lo.Z <= 2.2, "turnstile 4 x 2")
		local market = BuildingArt.SkyMarket()
		lo, hi = extent(market)
		t.ok(hi.X - lo.X <= 10.2 and hi.Z - lo.Z <= 8.2, "sky market 10 x 8")
		noPrice(court)
		noPrice(BuildingArt.LandOffice())
		t.ok(texts(BuildingArt.LandOffice())["LAND OFFICE"], "land office sign")
	end)
end
