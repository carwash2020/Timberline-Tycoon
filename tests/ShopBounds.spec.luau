--!nocheck
-- Furniture and decor stay clear of the walls: a grindstone, its crank, a
-- table or a sign never pokes into or through a wall plank, and everything
-- the interior adds stays inside the room's bounds.
return function(t)
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local Color3 = t.roblox.Color3

	local function aabb(part)
		local cf, size = part.CFrame, part.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
		local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
		local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
		local p = cf.Position
		return p.X - hx, p.X + hx, p.Y - hy, p.Y + hy, p.Z - hz, p.Z + hz
	end

	local function walls(kind)
		local s = BuildingArt.Scale[kind]
		if kind == "ToolShed" then
			return BuildingArt.ToolShedHalfWidth * s, BuildingArt.ToolShedHalfDepth * s, 0.6 * s
		elseif kind == "HearthAndHome" then
			return BuildingArt.HearthHalfWidth * s, BuildingArt.HearthHalfDepth * s, 0.6 * s
		end
		local frame = BuildingArt.InteriorFrame(kind, s)
		return frame.frame.halfW + 0.4, frame.frame.halfD + 0.4, 0.8
	end

	-- Names that are furniture or props, which must never straddle a wall.
	local FURNITURE = {
		Grindstone = true,
		GrindTrough = true,
		GrindLeg = true,
		Axle = true,
		Crank = true,
		CrankHandle = true,
		ChoppingBlock = true,
		Counter = true,
		CounterTop = true,
		Register = true,
		LedgerCover = true,
		ToolChest = true,
		Drawer = true,
		DisplayTable = true,
		Shelf = true,
		GoldTable = true,
		GoldTableTop = true,
		AisleSign = true,
		Ledge = true,
		SwatchBoard = true,
	}

	t.test("furniture and props never straddle a wall plane (the grindstone and its crank are clear)", function()
		for _, kind in ipairs({ "ToolShed", "HearthAndHome", "Dealership" }) do
			local model = BuildingArt.Shop(kind, kind, Color3.fromRGB(150, 62, 44))
			local hx, hz, thick = walls(kind)
			local margin = 0.25
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and (FURNITURE[d.Name] or FURNITURE[string.gsub(d.Name, "Top$", "")]) then
					local x0, x1, _, _, z0, z1 = aabb(d)
					local function crosses(lo, hi, plane)
						return lo < plane + thick / 2 + margin and hi > plane - thick / 2 - margin
					end
					-- Only the planes that are real walls here. The Dealership's
					-- centre is not its origin, so its hall check is by its bounds.
					if kind ~= "Dealership" then
						t.eq(crosses(x0, x1, -hx), false, kind .. " " .. d.Name .. " clips the west wall")
						t.eq(crosses(x0, x1, hx), false, kind .. " " .. d.Name .. " clips the east wall")
						t.eq(crosses(z0, z1, -hz), false, kind .. " " .. d.Name .. " clips the front wall")
						t.eq(crosses(z0, z1, hz), false, kind .. " " .. d.Name .. " clips the back wall")
					else
						local frame = BuildingArt.InteriorFrame(kind, 1).frame
						t.ok(
							x0 > -frame.halfW - 0.5 and x1 < frame.halfW + 0.5,
							kind .. " " .. d.Name .. " inside in x"
						)
						t.ok(
							z0 > -frame.halfD - 0.5 and z1 < frame.halfD + 0.5,
							kind .. " " .. d.Name .. " inside in z"
						)
					end
				end
			end
		end
	end)

	t.test("the grindstone and the chopping block stand out front, whole, clear of the door's opening", function()
		local model = BuildingArt.Shop("ToolShed", "TOOL SHED", Color3.fromRGB(150, 62, 44))
		local hx, hz = walls("ToolShed")
		for _, d in ipairs(model:GetDescendants()) do
			if
				d:IsA("BasePart")
				and (
					d.Name == "Grindstone"
					or d.Name == "Crank"
					or d.Name == "CrankHandle"
					or d.Name == "GrindTrough"
					or d.Name == "ChoppingBlock"
				)
			then
				local x0, x1, _, _, z0, z1 = aabb(d)
				t.ok(z1 < -hz - 0.3, d.Name .. " is wholly in front of the front wall")
				t.ok(x1 < -7.5 - 0.3 or x0 > 7.5 + 0.3, d.Name .. " is not in the doorway")
				t.ok(x0 > -hx and x1 < hx, d.Name .. " is not past the side walls")
			end
		end
	end)

	t.test("everything the interior adds stays inside the room", function()
		for _, kind in ipairs({ "ToolShed", "HearthAndHome" }) do
			local model = BuildingArt.Shop(kind, kind, Color3.fromRGB(150, 62, 44))
			local frame = BuildingArt.InteriorFrame(kind, BuildingArt.Scale[kind]).frame
			local added = {
				FloorBoards = true,
				AisleRunner = true,
				AisleRunnerEdge = true,
				CeilingBeam = true,
				AisleSign = true,
				AisleSignFrame = true,
				AisleSignChain = true,
				LampChain = true,
				LanternGlow = false,
				ShelfBack = true,
				WallShelf = true,
				GoldTable = true,
				GoldTableTop = true,
				DisplayTable = true,
				Shelf = true,
			}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and added[d.Name] then
					local x0, x1, y0, y1, z0, z1 = aabb(d)
					local tol = 0.31
					t.ok(
						x0 >= -frame.halfW - tol and x1 <= frame.halfW + tol,
						kind .. " " .. d.Name .. " x " .. x0 .. ".." .. x1
					)
					t.ok(
						z0 >= -frame.halfD - tol and z1 <= frame.halfD + tol,
						kind .. " " .. d.Name .. " z " .. z0 .. ".." .. z1
					)
					t.ok(y0 >= frame.floorTop - 0.2, kind .. " " .. d.Name .. " above the floor")
					t.ok(y1 <= frame.ceilY + 0.2, kind .. " " .. d.Name .. " below the ceiling")
				end
			end
		end
	end)
end
