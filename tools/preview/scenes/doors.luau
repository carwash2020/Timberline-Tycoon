--!nocheck
-- The shop doors, from the street: the Tool Shed's barn doors, Hearth &
-- Home's double doors and the showroom's roll-up shutter, each shown OPEN
-- (as built) and CLOSED (the closed pose, with the "Closed - opens at 7 AM"
-- sign the server writes). Views: 1 Hearth & Home open, 2 Hearth & Home
-- closed, 3 Tool Shed open, 4 Tool Shed closed, 5 showroom open, 6 showroom
-- closed, 7 to 9 each shop three-quarters from the street.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local DealershipLot = ctx.art("DealershipLot")
		local ShopDoorLogic = ctx.shared("ShopDoorLogic")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 700, C3.fromRGB(116, 164, 84), V3.new(120, -0.5, 0))

		local function closeDoor(model, hour, shopId)
			local door = model:FindFirstChild("ShopDoor")
			local counter = model:FindFirstChild("Counter")
			for _, p in ipairs(door:GetChildren()) do
				if p:GetAttribute("DoorLeaf") then
					p.CFrame = counter.CFrame * p:GetAttribute("ClosedCFrame")
				end
			end
			local sign = door:FindFirstChild("DoorClosedSign")
			sign.Transparency = 0
			local gui = sign:FindFirstChild("ClosedGui")
			gui.Enabled = true
			gui.ClosedText.Text = ShopDoorLogic.ClosedText(shopId, hour)
		end

		local function shop(kind, title, accent, x, closed, shopId)
			local model = BuildingArt.Shop(kind, title, accent)
			Kit.placeAt(model, CF.new(x, 0, 0))
			model.Parent = root
			if closed then
				closeDoor(model, 22, shopId)
			end
			return model
		end

		local hall = DealershipLot.Hall()
		shop("HearthAndHome", "GENERAL STORE", C3.fromRGB(122, 90, 60), 0, false, "HearthAndHome")
		shop("HearthAndHome", "GENERAL STORE", C3.fromRGB(122, 90, 60), 80, true, "HearthAndHome")
		shop("ToolShed", "TOOL SHED", C3.fromRGB(150, 62, 44), 160, false, "ToolShed")
		shop("ToolShed", "TOOL SHED", C3.fromRGB(150, 62, 44), 200, true, "ToolShed")
		local showroom = BuildingArt.Shop("Dealership", "DEALERSHIP", C3.fromRGB(47, 109, 181))
		Kit.placeAt(showroom, CF.new(400, 0, 0))
		showroom.Parent = root
		local closedHall = BuildingArt.Shop("Dealership", "DEALERSHIP", C3.fromRGB(47, 109, 181))
		Kit.placeAt(closedHall, CF.new(400, 0, 90))
		closedHall.Parent = root
		closeDoor(closedHall, 22, "Dealership")

		local lobby = -hall.innerW / 2 + 8
		return {
			root = root,
			shadowRadius = 300,
			cameras = {
				{ pos = { 0, 7, -46 }, target = { 0, 5, -19 }, label = "1 Hearth & Home, open", fov = 70 },
				{ pos = { 80, 7, -46 }, target = { 80, 5, -19 }, label = "2 Hearth & Home, closed", fov = 70 },
				{ pos = { 160, 7, -46 }, target = { 160, 5, -20 }, label = "3 Tool Shed, open", fov = 70 },
				{ pos = { 200, 7, -46 }, target = { 200, 5, -20 }, label = "4 Tool Shed, closed", fov = 70 },
				{
					pos = { 400 + lobby, 8, -hall.innerD / 2 - 30 },
					target = { 400 + lobby, 6, -hall.innerD / 2 },
					label = "5 showroom, open",
					fov = 70,
				},
				{
					pos = { 400 + lobby, 8, 90 - hall.innerD / 2 - 30 },
					target = { 400 + lobby, 6, 90 - hall.innerD / 2 },
					label = "6 showroom, closed",
					fov = 70,
				},
				-- The shops' street sides, roof on, from three-quarters: the facades,
				-- awnings, windows, raised name boards and the doors.
				{
					pos = { 160 - 40, 22, -62 },
					target = { 160, 10, -14 },
					label = "7 Tool Shed, three-quarter",
					fov = 62,
				},
				{ pos = { -50, 22, -62 }, target = { 0, 8, -14 }, label = "8 Hearth & Home, three-quarter", fov = 62 },
				{
					pos = { 400 + lobby - 40, 24, -hall.innerD / 2 - 62 },
					target = { 400 + lobby + 10, 8, -hall.innerD / 2 },
					label = "9 showroom, three-quarter",
					fov = 62,
				},
			},
		}
	end,
}
