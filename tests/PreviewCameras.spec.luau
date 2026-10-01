--!nocheck
-- The preview cameras that frame one subject (ACT-16): built the way
-- tools/preview/export.luau builds a scene, each view's subject is near
-- the middle of the view and nothing opaque stands between the eye and it.
--   npcs 9    Murph at his camp, from by the spawn
--   npcs 20   QuestUI's portrait of Murph (its numbers read from QuestUI)
--   axes 8    both holders and their axes, from the side and behind
--   trucks    a seated driver in every truck, the Burl in the Pickup's bed,
--             and the "seated driver" view of the Pickup's driver
local fs = require("@lune/fs")
local luau = require("@lune/luau")

return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame

	local DIR = "tools/preview/scenes/"
	local function scene(name)
		local function req(path)
			local file = DIR .. string.gsub(path, "^%./", "") .. ".luau"
			return luau.load(fs.readFile(file), { debugName = file })()
		end
		local path = DIR .. name .. ".luau"
		local def = luau.load(fs.readFile(path), { debugName = path, environment = { require = req } })()
		local loader = t.loader()
		return def.build({
			loader = loader,
			shared = function(n)
				return loader:shared(n)
			end,
			art = function(n)
				return loader:load("ReplicatedStorage/Shared/Art/" .. n)
			end,
			load = function(p)
				return loader:load(p)
			end,
			roblox = roblox,
		})
	end

	local function v(list)
		return Vector3.new(list[1], list[2], list[3])
	end

	-- Does the segment a -> b pass through `part`'s (oriented) box?
	local function crosses(part, a, b)
		local inv = part.CFrame:Inverse()
		local p0, p1 = inv * a, inv * b
		local h = part.Size / 2
		local lo, hi = 0, 1
		for _, axis in ipairs({ "X", "Y", "Z" }) do
			local s, d, half = p0[axis], p1[axis] - p0[axis], h[axis]
			if math.abs(d) < 1e-9 then
				if math.abs(s) > half then
					return false
				end
			else
				local u0, u1 = (-half - s) / d, (half - s) / d
				if u0 > u1 then
					u0, u1 = u1, u0
				end
				lo, hi = math.max(lo, u0), math.min(hi, u1)
				if lo > hi then
					return false
				end
			end
		end
		return true
	end

	-- The first opaque part (not one of `subject`'s) between the eye and
	-- `point`, or nil. Glass and see-through parts don't block.
	local function blocker(root, subject, eye, point)
		for _, p in ipairs(root:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 0.3 and not subject:IsAncestorOf(p) then
				if crosses(p, eye, point) then
					return p
				end
			end
		end
		return nil
	end

	local function offAxis(cam, point)
		local eye = v(cam.pos)
		local look = (v(cam.target) - eye).Unit
		return math.deg(math.acos(math.clamp(look:Dot((point - eye).Unit), -1, 1)))
	end

	-- Is `point` inside the rendered frame (render.mjs: 1280 x 800, the
	-- viewer's default fov 55), `margin` (0..1) of the way in from its edges?
	local function inFrame(built, cam, point, margin)
		local eye = v(cam.pos)
		local forward = (v(cam.target) - eye).Unit
		local right = forward:Cross(Vector3.yAxis).Unit
		local up = right:Cross(forward)
		local d = point - eye
		local z = d:Dot(forward)
		local half = math.tan(math.rad(cam.fov or built.fov or 55) / 2) * (1 - margin)
		return z > 0 and math.abs(d:Dot(up) / z) <= half and math.abs(d:Dot(right) / z) <= half * 1280 / 800
	end

	local function seen(built, cam, subject, points, label)
		local eye = v(cam.pos)
		for name, point in pairs(points) do
			local p = blocker(built.root, subject, eye, point)
			t.ok(p == nil, string.format("%s: %s hides the subject's %s", label, p and p:GetFullName() or "", name))
		end
	end

	local function models(root, name)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Model") and d.Name == name and d.PrimaryPart then
				table.insert(out, d)
			end
		end
		return out
	end

	local function flat(a, b)
		return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
	end

	t.test("npcs 9: Murph at his camp, centred and in plain view", function()
		local built = scene("npcs")
		local cam = built.cameras[9]
		local spot = Vector3.new(-25, 0, 41.8) -- NPCData's Murph
		local murph
		for _, m in ipairs(models(built.root, "Murph")) do
			if flat(m.PrimaryPart.CFrame.Position, spot) < 1 then
				murph = m
			end
		end
		t.ok(murph, "Murph stands at his camp")
		local head, torso = murph.Head.CFrame.Position, murph.Torso.CFrame.Position
		local hatTop = head + Vector3.new(0, murph:GetAttribute("TopOffset") - 0.15, 0)
		seen(built, cam, murph, { head = head, torso = torso, beanie = hatTop }, "npcs 9")
		t.ok(offAxis(cam, (head + torso) / 2) < 4, "npcs 9: Murph is in the middle of the view")
	end)

	t.test("npcs 20: QuestUI's portrait, with QuestUI's own numbers", function()
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/QuestUI.luau")
		local fov = tonumber(string.match(src, "camera%.FieldOfView = ([%d%.]+)"))
		local ex, ey, ez = string.match(src, "head%.CFrame %* CFrame%.new%(([%d%.%-]+), ([%d%.%-]+), ([%d%.%-]+)%)")
		local tx, ty, tz = string.match(src, "head%.Position %+ Vector3%.new%(([%d%.%-]+), ([%d%.%-]+), ([%d%.%-]+)%)")
		t.ok(fov and ex and tx, "QuestUI's portrait camera (FieldOfView, eye and target) can be read")
		local built = scene("npcs")
		local cam = built.cameras[20]
		local murph
		for _, m in ipairs(models(built.root, "Murph")) do
			local at = m.PrimaryPart.CFrame.Position
			if at.X > 200 and math.abs(at.Z + 60) < 1 then -- the line-up, not the poses row
				murph = m
			end
		end
		t.ok(murph, "Murph in the line-up")
		local head = murph.Head
		local eye = (head.CFrame * CFrame.new(tonumber(ex), tonumber(ey), tonumber(ez))).Position
		local target = head.CFrame.Position + Vector3.new(tonumber(tx), tonumber(ty), tonumber(tz))
		t.eq(cam.fov, fov, "npcs 20 uses QuestUI's field of view")
		t.ok((v(cam.pos) - eye).Magnitude < 1e-3, "npcs 20's eye is QuestUI's")
		t.ok((v(cam.target) - target).Magnitude < 1e-3, "npcs 20 looks where QuestUI looks")
		seen(built, cam, murph, { head = head.CFrame.Position }, "npcs 20")
	end)

	t.test("axes 8: both holders and their axes, in plain view", function()
		local built = scene("axes")
		local cam = built.cameras[8]
		local heads = {}
		for _, name in ipairs({ "Holder1", "Holder2" }) do
			local fig = models(built.root, name)[1]
			t.ok(fig, name)
			local axe = fig:FindFirstChildOfClass("Model")
			t.ok(axe and axe.PrimaryPart, name .. " holds an axe")
			local points = { head = fig.Head.CFrame.Position, axe = axe.PrimaryPart.CFrame.Position }
			table.insert(heads, points.head)
			seen(built, cam, fig, points, "axes 8 " .. name)
			-- The whole axe in the frame, blade and all.
			for _, p in ipairs(axe:GetDescendants()) do
				if p:IsA("BasePart") then
					local where = p.CFrame.Position
					t.ok(
						inFrame(built, cam, where, 0.08),
						string.format("axes 8: %s's %s is in the view", name, p.Name)
					)
				end
			end
		end
		t.ok(offAxis(cam, (heads[1] + heads[2]) / 2) < 8, "axes 8: the pair is in the middle of the view")
	end)

	t.test("trucks: a seated driver in every truck, the Burl in the Pickup, the seated-driver view", function()
		local built = scene("trucks")
		local drivers = models(built.root, "Driver")
		local trucks = 0
		for _, truck in ipairs(built.root:GetChildren()) do
			local seat = truck:IsA("Model") and truck:FindFirstChild("DriverSeat")
			if seat then
				trucks += 1
				local top = seat.CFrame * Vector3.new(0, seat.Size.Y / 2, 0)
				local driver
				for _, d in ipairs(drivers) do
					if (d.PrimaryPart.CFrame.Position - top).Magnitude < 1.5 then
						driver = d
					end
				end
				t.ok(driver, truck.Name .. " has a driver on its seat")
				local hat = driver:FindFirstChild("Hat")
				local hatTop = hat.CFrame.Y + hat.Size.Y / 2
				t.ok(
					math.abs(hatTop - top.Y - 3.85) < 0.05,
					truck.Name .. ": the driver's hat top is 3.85 over the seat"
				)
				local roof = truck:FindFirstChild("Roof")
				if roof then
					t.ok(hatTop < roof.CFrame.Y - roof.Size.Y / 2, truck.Name .. ": the hat is under the roof")
				end
				if truck.Name == "Pickup" then
					built.pickup, built.pickupDriver = truck, driver
				end
			end
		end
		t.eq(trucks, 6, "five trucks in the line-up and the lone Rustbucket")

		-- One Burl log, banded, in the Pickup's bed.
		local floor = built.pickup:FindFirstChild("BedFloor")
		local burls = 0
		for _, log in ipairs(models(built.root, "BedLog")) do
			local band = log.PrimaryPart:FindFirstChild("FigureBand")
			if band and band:GetAttribute("Figure") == "burl" then
				local rel = floor.CFrame:Inverse() * log.PrimaryPart.CFrame.Position
				t.ok(
					math.abs(rel.Z) < floor.Size.Z / 2 and math.abs(rel.X) < floor.Size.X / 2,
					"the Burl is in the bed"
				)
				burls += 1
			end
		end
		t.eq(burls, 1, "one Burl log in the Pickup's bed")

		local cam
		for _, c in ipairs(built.cameras) do
			if string.find(c.label, "seated driver") then
				cam = c
			end
		end
		t.ok(cam, "a seated-driver view")
		local driver = built.pickupDriver
		local head, hat = driver.Head.CFrame.Position, driver.Hat.CFrame.Position
		seen(built, cam, driver, { head = head, hat = hat }, "trucks, seated driver")
		t.ok(offAxis(cam, head) < 8, "the seated driver is near the middle of the view")
	end)
end
