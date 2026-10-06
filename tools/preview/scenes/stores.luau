--!nocheck
-- The three shops with their roofs off, as the game builds them, stocked
-- the way BoxService stocks them: every shelf slot gets the real packaged
-- box (BoxArt, sized by BoxSize), the Robux shelf its gold boxes, and a
-- six-stud-tall figure carries a medium box down each aisle, so a carried
-- box and the aisle can be judged at a glance. Views: 1 Tool Shed from
-- above, 2 Tool Shed from the door, 3 Hearth & Home from above, 4 Hearth &
-- Home from the door, 5 Dealership from above, 6 Tool Shed close on the
-- tables, 7 Hearth & Home close on a shelf.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local BoxArt = ctx.art("BoxArt")
		local StoreStock = ctx.shared("StoreStock")
		local BoxSize = ctx.shared("BoxSize")
		local RobuxShelf = ctx.shared("RobuxShelf")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 400, C3.fromRGB(116, 164, 84), V3.new(60, -0.5, 20))

		local ROOF = { Roof = true, Shingle = true, RidgeCap = true, Gable = true, Rafter = true, TieBeam = true }
		local function strip(model)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and ROOF[d.Name] then
					d:Destroy()
				end
			end
		end

		local function box(at, size, name, kind, color, gold)
			local model = roblox.Instance.new("Model")
			model.Name = "ShopItem"
			local body = Kit.part(model, "Box", size, CF.new(at), color, roblox.Enum.Material.SmoothPlastic)
			body.CanCollide = false
			BoxArt.Dress(model, body, {
				name = name,
				kind = kind,
				color = color,
				gold = gold,
				side = BoxArt.AisleSide(at.X - (model:GetAttribute("shopX") or 0)),
			})
			model.Parent = root
			return model
		end

		local function stock(model, shopX)
			local counter = model:FindFirstChild("Counter")
			if not counter then
				return
			end
			for _, att in ipairs(counter:GetChildren()) do
				if att:IsA("Attachment") and (att.Name == "ShelfSlot" or att.Name == "RobuxSlot") then
					local at = counter.CFrame:PointToWorldSpace(att.Position)
					local slotId = att:GetAttribute("SlotId")
					if att.Name == "RobuxSlot" then
						local entry = RobuxShelf.Get(slotId)
						local size = BoxSize.Class(RobuxShelf.Class).size
						local rel = V3.new(at.X - shopX, at.Y, at.Z)
						local m = roblox.Instance.new("Model")
						local body = Kit.part(
							m,
							"Box",
							size,
							CF.new(at),
							C3.fromHex(RobuxShelf.Gold),
							roblox.Enum.Material.Metal
						)
						body.CanCollide = false
						BoxArt.Dress(m, body, {
							name = entry and entry.displayName or "Robux",
							kind = "Robux",
							color = C3.fromHex(RobuxShelf.Gold),
							gold = true,
							side = BoxArt.AisleSide(rel.X),
						})
						m.Parent = root
					else
						local slot = StoreStock.Get(slotId)
						if slot then
							local size = StoreStock.BoxSizeOf(slot)
							local count = if slot.limited then 3 else 1
							for i = 1, count do
								local along = (i - (count + 1) / 2) * BoxSize.Pitch(size.Z)
								local p = V3.new(at.X, at.Y, at.Z + along)
								local m = roblox.Instance.new("Model")
								local body = Kit.part(
									m,
									"Box",
									size,
									CF.new(p),
									C3.fromHex(slot.color),
									roblox.Enum.Material.SmoothPlastic
								)
								body.CanCollide = false
								BoxArt.Dress(m, body, {
									name = slot.displayName,
									kind = slot.itemKind,
									color = C3.fromHex(slot.color),
									side = BoxArt.AisleSide(at.X - shopX),
								})
								m.Parent = root
							end
						end
					end
				end
			end
		end

		-- A 5-stud person with a medium box held out in front, walking +Z.
		local function walker(x, z)
			local m = BoxSize.Class("M").size
			Kit.part(root, "Person", V3.new(2, 5, 1), CF.new(x, 2.5 + 0.75, z), C3.fromRGB(60, 90, 160))
			Kit.part(root, "Head", V3.new(1.4, 1.4, 1.4), CF.new(x, 6.1, z), C3.fromRGB(235, 200, 160))
			box(V3.new(x, 4.4, z + 1 + m.Z / 2), m, "Cobalt Axe", "Axe", C3.fromRGB(60, 90, 160))
		end

		local cameras = {}
		local function shop(kind, title, accent, x, z)
			local model = BuildingArt.Shop(kind, title, accent)
			strip(model)
			Kit.placeAt(model, CF.new(x, 0, z))
			model.Parent = root
			stock(model, x)
			return model
		end

		shop("ToolShed", "TOOL SHED", C3.fromRGB(150, 62, 44), 0, 0)
		walker(0, -12)
		walker(-1.5, 14)
		table.insert(cameras, { pos = { 0, 78, -30 }, target = { 0, 0, 2 }, label = "1 Tool Shed from above" })
		table.insert(cameras, { pos = { 0, 12, -34 }, target = { 0, 3, 8 }, label = "2 Tool Shed from the door" })

		shop("HearthAndHome", "GENERAL STORE", C3.fromRGB(122, 90, 60), 90, 0)
		walker(90, -12)
		table.insert(cameras, { pos = { 90, 62, -36 }, target = { 90, 2, 6 }, label = "3 Hearth & Home from above" })
		table.insert(
			cameras,
			{ pos = { 90, 9, -30 }, target = { 90, 5, 8 }, label = "4 Hearth & Home from the door", fov = 85 }
		)

		shop("Dealership", "DEALERSHIP", C3.fromRGB(47, 109, 181), 160, 0)
		table.insert(cameras, { pos = { 160, 62, -34 }, target = { 160, 0, 1 }, label = "5 Dealership from above" })
		table.insert(cameras, { pos = { 14, 14, -12 }, target = { 6, 3, 2 }, label = "6 Tool Shed tables, close" })
		table.insert(
			cameras,
			{ pos = { 70, 10, -4 }, target = { 68, 3, 6 }, label = "7 Hearth & Home gear shelf, close", fov = 80 }
		)

		return {
			root = root,
			shadowRadius = 200,
			cameras = cameras,
		}
	end,
}
