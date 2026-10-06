--!nocheck
-- The shop doors: one open/closed rule (the shopkeeper's hours), a blocker
-- that is up only while closed, nobody shut in, a 12-hour closed sign, and
-- leaves that carry their own open and closed poses.
return function(t)
	local Logic = t.shared("ShopDoorLogic")
	local Hours = t.shared("ShopHoursLogic")
	local Instance, Vector3, CFrame, Color3 = t.roblox.Instance, t.roblox.Vector3, t.roblox.CFrame, t.roblox.Color3

	t.test("the door uses the shop hours and no second rule", function()
		for _, shop in ipairs(Hours.Shops()) do
			for hour = 0, 23.5, 0.5 do
				t.eq(Logic.IsOpen(shop, hour), Hours.IsOpen(shop, hour), shop .. " " .. hour)
				-- With nobody holding and nobody in the doorway, locked is exactly closed.
				t.eq(Logic.Locked(shop, hour, false, false), not Hours.IsOpen(shop, hour), shop .. " " .. hour)
			end
		end
		t.eq(Logic.Locked("ToolShed", 3, false, false), false, "the Tool Shed never shuts")
		t.eq(Logic.Locked("HearthAndHome", 22, false, false), true)
		t.eq(Logic.Locked("HearthAndHome", 7, false, false), false, "open at 7:00 on the dot")
		t.eq(Logic.Locked("HearthAndHome", 21, false, false), true, "closed at 21:00")
		t.eq(Logic.Locked("Dealership", 19.99, false, false), false)
		t.eq(Logic.Locked("Dealership", 20, false, false), true)
	end)

	t.test("nobody is trapped: a hold or a body in the doorway keeps it open", function()
		t.eq(Logic.Locked("HearthAndHome", 22, true, false), false, "held open by someone inside")
		t.eq(Logic.Locked("HearthAndHome", 22, false, true), false, "it never shuts on someone in the doorway")
		local cf = CFrame.new(0, 5, 0)
		local size = Vector3.new(15, 10, 1.4)
		t.eq(Logic.Occupied({ Vector3.new(0, 3, 0) }, cf, size), true)
		t.eq(Logic.Occupied({ Vector3.new(7.5 + Logic.DoorwayPad, 3, 0) }, cf, size), true, "the pad counts")
		t.eq(Logic.Occupied({ Vector3.new(7.5 + Logic.DoorwayPad + 0.1, 3, 0) }, cf, size), false)
		t.eq(Logic.Occupied({ Vector3.new(0, 3, 30) }, cf, size), false, "far outside is not in the doorway")
		t.eq(Logic.Occupied({}, cf, size), false)
		-- The sensor stands beyond the blocker, on the inside only.
		t.ok(Logic.SensorInset > 0 and Logic.SensorDepth > 0)
	end)

	t.test("the closed sign reads in 12-hour form from one helper", function()
		t.eq(Logic.FormatClock(7), "7 AM")
		t.eq(Logic.FormatClock(7.5), "7:30 AM")
		t.eq(Logic.FormatClock(0), "12 AM")
		t.eq(Logic.FormatClock(12), "12 PM")
		t.eq(Logic.FormatClock(13.25), "1:15 PM")
		t.eq(Logic.FormatClock(19), "7 PM")
		t.eq(Logic.FormatClock(24 + 7), "7 AM", "wraps")
		t.eq(Logic.ClosedText("HearthAndHome", 22), "Closed - opens at 7 AM")
		t.eq(Logic.ClosedText("Dealership", 3), "Closed - opens at 7 AM")
		t.eq(Logic.ClosedText("HearthAndHome", 12), "", "no sign while open")
		t.eq(Logic.ClosedText("ToolShed", 3), "")
	end)

	t.test("the client's tween steps toward the state and never overshoots", function()
		t.eq(Logic.StepAlpha(0, 1, Logic.TweenSeconds / 2), 0.5)
		t.eq(Logic.StepAlpha(0.9, 1, 5), 1)
		t.eq(Logic.StepAlpha(1, 0, Logic.TweenSeconds / 4), 0.75)
		t.eq(Logic.StepAlpha(0.1, 0, 5), 0)
		t.eq(Logic.StepAlpha(1, 1, 1), 1)
		t.eq(Logic.Ease(0), 0)
		t.eq(Logic.Ease(1), 1)
		t.ok(Logic.Ease(0.5) == 0.5 and Logic.Ease(0.25) < 0.25)
	end)

	local function shop(kind)
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		return BuildingArt.Shop(kind, kind, Color3.fromRGB(150, 62, 44))
	end

	t.test("every shop has a door: leaves with both poses, a blocker, a sensor and a closed sign", function()
		for _, kind in ipairs({ "ToolShed", "HearthAndHome", "Dealership" }) do
			local model = shop(kind)
			local door = model:FindFirstChild("ShopDoor")
			t.ok(door and door:IsA("Model"), kind .. " has a ShopDoor")
			local counter = model:FindFirstChild("Counter")
			local leaves = 0
			for _, p in ipairs(door:GetChildren()) do
				if p:GetAttribute("DoorLeaf") then
					leaves += 1
					t.eq(p.CanCollide, false, kind .. " leaf is looks only")
					t.eq(typeof(p:GetAttribute("ClosedCFrame")), "CFrame")
					t.eq(typeof(p:GetAttribute("OpenCFrame")), "CFrame")
					t.eq(p.Anchored, true)
				end
			end
			t.ok(leaves >= 2, kind .. " has leaves")
			local block = door:FindFirstChild("DoorBlock")
			t.eq(block.CanCollide, false, "open by default: players walk in")
			t.eq(block.Transparency, 1)
			t.ok(block.Size.X >= 14, kind .. " door is wide enough for a boxed item: " .. block.Size.X)
			t.ok(block.Size.Y >= 9.5, kind .. " door is tall")
			local sensor = door:FindFirstChild("DoorSensor")
			t.eq(sensor.CanTouch, true)
			t.eq(sensor.CanCollide, false)
			-- The sensor is on the inside (+Z of the block), beyond reach of the outside.
			t.ok(
				sensor.CFrame.Position.Z - sensor.Size.Z / 2 > block.CFrame.Position.Z + block.Size.Z / 2,
				kind .. " sensor is inside"
			)
			local sign = door:FindFirstChild("DoorClosedSign")
			t.ok(sign and sign:FindFirstChild("ClosedGui"), kind .. " closed sign")
			t.eq(sign:FindFirstChild("ClosedGui").Enabled, false)
			t.ok(counter ~= nil)
		end
	end)

	t.test("the closed pose fills the doorway and the open pose clears it", function()
		for _, kind in ipairs({ "ToolShed", "HearthAndHome", "Dealership" }) do
			local model = shop(kind)
			local door = model:FindFirstChild("ShopDoor")
			local counter = model:FindFirstChild("Counter")
			local block = door:FindFirstChild("DoorBlock")
			local bx0 = block.CFrame.Position.X - block.Size.X / 2
			local bx1 = block.CFrame.Position.X + block.Size.X / 2
			local closedMin, closedMax = math.huge, -math.huge
			local openInside = false
			for _, p in ipairs(door:GetChildren()) do
				if p:GetAttribute("DoorLeaf") then
					local closed = counter.CFrame * p:GetAttribute("ClosedCFrame")
					local open = counter.CFrame * p:GetAttribute("OpenCFrame")
					local reach = (math.abs(closed.RightVector.X) * p.Size.X + math.abs(closed.LookVector.X) * p.Size.Z)
						/ 2
					closedMin = math.min(closedMin, closed.Position.X - reach)
					closedMax = math.max(closedMax, closed.Position.X + reach)
					-- The leaf is built in the open pose.
					t.ok((open.Position - p.CFrame.Position).Magnitude < 1e-3, kind .. " built open")
					local oreach = (math.abs(open.RightVector.X) * p.Size.X + math.abs(open.LookVector.X) * p.Size.Z)
						/ 2
					if
						p.Name ~= "ShutterSlat"
						and open.Position.X + oreach > bx0 + 1
						and open.Position.X - oreach < bx1 - 1
						and kind ~= "HearthAndHome"
					then
						openInside = true
					end
				end
			end
			if kind ~= "Dealership" then
				t.ok(closedMin <= bx0 + 1 and closedMax >= bx1 - 1, kind .. " closed leaves span the doorway")
			end
			t.eq(openInside, false, kind .. " open leaves are out of the way")
		end
	end)
end
