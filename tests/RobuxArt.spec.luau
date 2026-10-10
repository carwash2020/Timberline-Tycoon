--!nocheck
-- Lane P art: the gold crates and the Tool Shed's gold table, cheap and
-- solid where a player stands, decor everywhere else.
return function(t)
	local roblox = t.roblox
	local Instance, CFrame = roblox.Instance, roblox.CFrame
	local RobuxBoxArt = t.shared("Art/RobuxBoxArt")
	local RobuxShelf = t.shared("RobuxShelf")
	local BoxSize = t.shared("BoxSize")

	local function crate(key)
		local model = Instance.new("Model")
		local body = Instance.new("Part")
		body.Name = "Box"
		body.Size = BoxSize.Class(RobuxShelf.Class).size
		body.CFrame = CFrame.new(0, body.Size.Y / 2, 0)
		body.Parent = model
		local added = RobuxBoxArt.Dress(model, body, { name = "Large Cash Pack", key = key })
		return model, body, added
	end

	t.test("a crate is eight shell parts and three coin parts, all inside the box", function()
		local model, body, added = crate("Cash10k")
		t.eq(#added, RobuxBoxArt.ShellParts + RobuxBoxArt.CoinParts)
		t.eq(#model:FindFirstChild("Contents"):GetChildren(), RobuxBoxArt.CoinParts)
		local half = body.Size / 2
		for _, p in ipairs(added) do
			t.eq(p.CanCollide, false, p.Name .. " is decor")
			t.eq(p.Massless, true, p.Name)
			local c = p.CFrame.Position - body.CFrame.Position
			local h = p.Size / 2
			t.ok(math.abs(c.X) + math.min(h.X, 2) <= half.X + 0.1, p.Name .. " inside in x")
			t.ok(c.Y - h.Y >= -half.Y - 1e-3, p.Name .. " not under the box")
			t.ok(math.abs(c.Z) <= half.Z + 0.1, p.Name .. " inside in z")
		end
		t.eq(model:FindFirstChild("Tag"):FindFirstChild("Name", true).Text, "Large Cash Pack")
	end)

	t.test("the coins stand over the low front and under the walls' top", function()
		for _, key in ipairs({ "Cash1k", "Cash10k", "DoubleCash" }) do
			local model, body = crate(key)
			local bottom = body.CFrame.Position.Y - body.Size.Y / 2
			local floorTop = bottom + RobuxBoxArt.Floor
			local pile = RobuxBoxArt.PileHeight(key)
			t.ok(floorTop + pile > floorTop + RobuxBoxArt.FrontH - 0.3, key .. " shows over the front")
			t.ok(pile + 0.35 <= body.Size.Y - RobuxBoxArt.Floor, key .. " stays in the box")
			t.ok(model:FindFirstChild("Front").Size.Y < model:FindFirstChild("Left").Size.Y, key)
		end
		t.ok(RobuxBoxArt.PileHeight("Cash10k") > RobuxBoxArt.PileHeight("Cash1k"), "the big pack is fuller")
	end)

	t.test("the gold table: seven parts, solid where it stands, the sign says TIMBERLINE STORE", function()
		local RobuxTableArt = t.load("ReplicatedStorage/Shared/Art/RobuxTableArt")
		local model = Instance.new("Model")
		RobuxTableArt.Build(model, 0.4)
		local parts, solid = 0, {}
		local sign = nil
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
				if d.CanCollide then
					solid[d.Name] = true
				end
			elseif d:IsA("TextLabel") and d.Text == "TIMBERLINE STORE" then
				sign = d
			end
		end
		t.eq(parts, RobuxTableArt.Parts)
		t.ok(solid.GoldTable and solid.GoldTableTop and solid.GoldRiser, "the table and riser hold boxes")
		t.ok(sign ~= nil, "the sign")
		local riser = model:FindFirstChild("GoldRiser")
		local top = riser.CFrame.Position.Y + riser.Size.Y / 2
		t.ok(
			math.abs(top - (RobuxShelf.TableTop + RobuxShelf.RiserH)) < 1e-3,
			"the riser is the back row's floor: " .. top .. " vs " .. (RobuxShelf.TableTop + RobuxShelf.RiserH)
		)
	end)

	t.test("in the Tool Shed no gold crate cuts into anything but the surface it stands on", function()
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		local shed = BuildingArt.Shop("ToolShed", "TOOL SHED", roblox.Color3.fromRGB(58, 111, 216))
		local size = BoxSize.Class(RobuxShelf.Class).size
		local hits = {}
		for _, place in ipairs(RobuxShelf.Placements()) do
			local lo = roblox.Vector3.new(place.x - size.X / 2, place.y - size.Y / 2 + 0.02, place.z - size.Z / 2)
			local hi = roblox.Vector3.new(place.x + size.X / 2, place.y + size.Y / 2, place.z + size.Z / 2)
			for _, p in ipairs(shed:GetDescendants()) do
				if p:IsA("BasePart") and p.Transparency < 1 then
					local c, h = p.CFrame.Position, p.Size / 2
					-- Axis-aligned parts only (the shop's interior is), with a hair of slack.
					local e = 0.01
					if
						c.X - h.X < hi.X - e
						and c.X + h.X > lo.X + e
						and c.Y - h.Y < hi.Y - e
						and c.Y + h.Y > lo.Y + e
						and c.Z - h.Z < hi.Z - e
						and c.Z + h.Z > lo.Z + e
					then
						table.insert(hits, place.slotId .. " x " .. p.Name)
					end
				end
			end
		end
		t.eq(hits, {})
	end)
end
