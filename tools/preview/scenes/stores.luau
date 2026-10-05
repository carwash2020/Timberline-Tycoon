--!nocheck
-- The three shops with their roofs off, as the game builds them, stocked:
-- a box on every shelf slot (the cash shelves, grey-brown; the Robux shelf,
-- gold), and a six-stud-tall figure carrying a box down each aisle, so a
-- carried box and the aisle can be judged at a glance. Views: 1 Tool Shed
-- from above, 2 Tool Shed from the door, 3 Hearth & Home from above,
-- 4 Hearth & Home from the door, 5 Dealership from above.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
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

		local function stock(model)
			local counter = model:FindFirstChild("Counter")
			if not counter then
				return
			end
			for _, att in ipairs(counter:GetChildren()) do
				if att:IsA("Attachment") and (att.Name == "ShelfSlot" or att.Name == "RobuxSlot") then
					local at = counter.CFrame:PointToWorldSpace(att.Position)
					local gold = att.Name == "RobuxSlot"
					local box = Kit.part(
						root,
						"Box",
						V3.new(2, 1.2, 1.6),
						CF.new(at),
						if gold then C3.fromRGB(227, 183, 60) else C3.fromRGB(196, 148, 90),
						roblox.Enum.Material.Wood
					)
					box.CanCollide = false
				end
			end
		end

		-- A 5-stud person with a box held out in front, walking +Z.
		local function walker(x, z)
			Kit.part(root, "Person", V3.new(2, 5, 1), CF.new(x, 2.5 + 0.75, z), C3.fromRGB(60, 90, 160))
			Kit.part(root, "Head", V3.new(1.4, 1.4, 1.4), CF.new(x, 6.1, z), C3.fromRGB(235, 200, 160))
			Kit.part(root, "CarriedBox", V3.new(2, 1.2, 1.6), CF.new(x, 4.2, z + 1.8), C3.fromRGB(196, 148, 90))
		end

		local cameras = {}
		local function shop(kind, title, accent, x, z, label)
			local model = BuildingArt.Shop(kind, title, accent)
			strip(model)
			Kit.placeAt(model, CF.new(x, 0, z))
			model.Parent = root
			stock(model)
			return model
		end

		shop("ToolShed", "TOOL SHED", C3.fromRGB(150, 62, 44), 0, 0)
		walker(0, -6)
		walker(-4, 10)
		table.insert(cameras, { pos = { 0, 62, -22 }, target = { 0, 0, 2 }, label = "Tool Shed from above" })
		table.insert(cameras, { pos = { 0, 11, -26 }, target = { 0, 3, 6 }, label = "Tool Shed from the door" })

		shop("HearthAndHome", "GENERAL STORE", C3.fromRGB(122, 90, 60), 90, 0)
		walker(90, -10)
		table.insert(cameras, { pos = { 90, 46, -34 }, target = { 90, 2, 6 }, label = "Hearth & Home from above" })
		table.insert(
			cameras,
			{ pos = { 90, 9, -24 }, target = { 90, 5, 8 }, label = "Hearth & Home from the door", fov = 85 }
		)

		shop("Dealership", "DEALERSHIP", C3.fromRGB(47, 109, 181), 160, 0)
		table.insert(cameras, { pos = { 160, 62, -26 }, target = { 160, 0, 1 }, label = "Dealership from above" })

		return {
			root = root,
			shadowRadius = 160,
			cameras = cameras,
		}
	end,
}
