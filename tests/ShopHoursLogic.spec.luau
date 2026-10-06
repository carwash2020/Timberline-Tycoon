--!nocheck
-- Shop hours (K1-K6): pure open/close, the Studio clock, signs built from
-- each shop's own span, and a door that only changes colour.
return function(t)
	local Hours = t.shared("ShopHoursLogic")
	local Dialogue = t.shared("DialogueData")
	local fs = require("@lune/fs")

	local function near(a, b)
		return math.abs(a - b) < 1e-6
	end

	t.test("exact open and close, 24/7, and a span that wraps midnight", function()
		t.eq(Hours.ToolShedOpen, 6)
		t.eq(Hours.ToolShedClose, 20)
		t.eq(Hours.IsOpen("ToolShed", 6), true, "open at 6:00")
		t.eq(Hours.IsOpen("ToolShed", 5.999), false)
		t.eq(Hours.IsOpen("ToolShed", 19.999), true)
		t.eq(Hours.IsOpen("ToolShed", 20), false, "closed at 20:00")
		t.eq(Hours.IsOpen("ToolShed", 0), false)
		t.eq(Hours.IsOpen("ToolShed", 24), false)
		t.eq(Hours.NextOpen("ToolShed", 3), 6)
		t.eq(Hours.NextOpen("ToolShed", 22), 6)

		t.eq(Hours.IsOpen("HearthAndHome", 7), true, "open at 7:00")
		t.eq(Hours.IsOpen("HearthAndHome", 6.999), false)
		t.eq(Hours.IsOpen("HearthAndHome", 20.999), true)
		t.eq(Hours.IsOpen("HearthAndHome", 21), false, "closed at 21:00")
		t.eq(Hours.IsOpen("HearthAndHome", 22), false)
		t.eq(Hours.IsOpen("HearthAndHome", 3), false)
		t.eq(Hours.NextOpen("HearthAndHome", 22), Hours.HearthOpen)
		t.eq(Hours.NextOpen("HearthAndHome", 3), Hours.HearthOpen)
		t.eq(Hours.NextOpen("HearthAndHome", 10), Hours.HearthOpen)

		t.eq(Hours.IsOpen("Dealership", 7), true, "open at 7:00")
		t.eq(Hours.IsOpen("Dealership", 6.999), false)
		t.eq(Hours.IsOpen("Dealership", 19.999), true)
		t.eq(Hours.IsOpen("Dealership", 20), false, "closed at 20:00")
		t.eq(Hours.IsOpen("Dealership", 8), true)
		t.eq(Hours.NextOpen("Dealership", 22), Hours.DealerOpen)
		t.eq(Hours.NextOpen("Dealership", 3), Hours.DealerOpen)

		t.eq(Hours.IsOpen("NotAShop", 3), true, "an unknown id stays open")
		t.eq(near(Hours.NextOpen("NotAShop", 27), 3), true)

		t.eq(Hours.OpenAt(22, 6, 3), true, "a wrap is open at 3:00")
		t.eq(Hours.OpenAt(22, 6, 22), true, "open at the first minute")
		t.eq(Hours.OpenAt(22, 6, 6), false, "closed at the last minute")
		t.eq(Hours.OpenAt(22, 6, 12), false)
		t.eq(Hours.OpenAt(22, 6, 21.999), false)
		t.eq(Hours.NextOpenAt(22, 6, 12), 22)
		t.eq(Hours.NextOpenAt(22, 6, 3), 22)

		t.eq(Hours.FormatHour(7), "7:00 AM")
		t.eq(Hours.FormatHour(7.5), "7:30 AM")
		t.eq(Hours.FormatHour(21), "9:00 PM")
		t.eq(Hours.FormatHour(0), "12:00 AM")
		t.eq(Hours.FormatHour(12), "12:00 PM")
		t.eq(Hours.FormatHour(23.99), "11:59 PM")
	end)

	t.test("Now reads WorldTime.Hour, so a Studio clock override is the shop hour", function()
		local ClockOverride = t.shared("ClockOverride")
		local loader = t.loader({
			services = {
				RunService = {
					IsStudio = function()
						return true
					end,
				},
			},
			globals = {
				workspace = {
					GetServerTimeNow = function()
						return 0
					end,
					GetAttribute = function(_, name)
						if name == ClockOverride.Attribute then
							return 22
						end
						return nil
					end,
				},
			},
		})
		local clock = loader:shared("ShopHoursLogic")
		t.eq(clock.Now(), 22)
		t.eq(clock.IsOpen("HearthAndHome", clock.Now()), false)
		t.eq(clock.IsOpen("Dealership", clock.Now()), false)
		t.eq(clock.IsOpen("ToolShed", clock.Now()), false, "the Tool Shed shuts at night too")
	end)

	t.test("a closed shop says when it opens, on the sign and in the keeper's line", function()
		for _, shop in ipairs(Hours.Shops()) do
			local span = Hours.Span(shop)
			for _, hour in ipairs({ 3, 8, 22 }) do
				local text = Hours.SignText(shop, hour)
				if span == nil then
					t.eq(text, "Open all day", shop)
				elseif Hours.IsOpen(shop, hour) then
					t.eq(
						text,
						string.format("Open %s to %s", Hours.FormatHour(span.open), Hours.FormatHour(span.close)),
						shop .. " " .. tostring(hour)
					)
				else
					local when = Hours.FormatHour(Hours.NextOpen(shop, hour))
					t.eq(text, "Closed, opens " .. when, shop .. " " .. tostring(hour))
					local line = Dialogue.Sleepy(shop, hour)
					t.ok(string.find(line, when, 1, true) ~= nil, line)
				end
			end
		end
		t.eq(#Dialogue.Idles("ToolShed"), 3)
		t.eq(#Dialogue.Idles("HearthAndHome"), 3)
		t.eq(#Dialogue.Idles("Dealership"), 3)
		t.eq(Hours.MayOpenDoor(false, true), false, "outside, closed")
		t.eq(Hours.MayOpenDoor(false, false), true, "inside, closed")
		t.eq(Hours.MayOpenDoor(true, true), true, "open")
	end)

	t.test("every shop sign matches that shop, with no fixed hour string in the source", function()
		local paths = {
			"src/ReplicatedStorage/Shared/ShopHoursLogic.luau",
			"src/ReplicatedStorage/Shared/Art/BuildingArt.luau",
			"src/ReplicatedStorage/Shared/DialogueData.luau",
			"src/ServerScriptService/NPCService.luau",
			"src/ServerScriptService/ShopService.luau",
		}
		for _, path in ipairs(paths) do
			t.eq(string.find(fs.readFile(path), "7:00 to 20:00", 1, true), nil, path)
		end
		local BuildingArt = t.loader():load("ReplicatedStorage/Shared/Art/BuildingArt")
		local C3 = t.roblox.Color3
		local shops = {
			{ "ToolShed", C3.fromRGB(150, 62, 44) },
			{ "HearthAndHome", C3.fromRGB(122, 90, 60) },
			{ "Dealership", C3.fromRGB(47, 109, 181) },
		}
		for _, shop in ipairs(shops) do
			local model = BuildingArt.Shop(shop[1], shop[1], shop[2])
			local before = #model:GetDescendants()
			local board = model:FindFirstChild("HoursBoard")
			t.ok(board and board:IsA("BasePart"), shop[1] .. " hours board")
			t.eq(board:GetAttribute("ShopId"), shop[1])
			t.ok(math.abs(board.Size.X - Hours.SignWidthStuds) < 1e-3, "4 studs wide")
			t.ok(math.abs(board.Size.Y - Hours.SignHeightStuds) < 1e-3, "2 studs tall")
			t.eq(board.CanCollide, false)
			local gui = board:FindFirstChild("HoursGui")
			t.eq(gui.PixelsPerStud, Hours.SignPixelsPerStud)
			local leaf = false
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("HoursLeaf") == true then
					leaf = true
				end
			end
			t.eq(leaf, true, shop[1] .. " has a door leaf")
			local color = nil
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("HoursLeaf") == true then
					color = d.Color
					break
				end
			end
			BuildingArt.PaintDoor(model, true)
			t.eq(#model:GetDescendants(), before, "locking adds no parts")
			local locked = nil
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("HoursLeaf") == true then
					locked = d
					break
				end
			end
			t.ok(math.abs(locked.Transparency - BuildingArt.LockedDoorTransparency) < 1e-4, "locked transparency")
			t.ok(locked.Color ~= color, "the leaf changes colour")
			BuildingArt.PaintDoor(model, false)
			t.eq(locked.Color, color, "opening restores the leaf")
			for _, hour in ipairs({ 8, 22 }) do
				Hours.WriteSigns(model, hour)
				local label = gui:FindFirstChild("Hours")
				t.eq(label.Text, Hours.SignText(shop[1], hour), shop[1] .. " " .. tostring(hour))
			end
		end
	end)
end
