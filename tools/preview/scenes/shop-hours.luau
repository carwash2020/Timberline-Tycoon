--!nocheck
-- Each shop at 08:00 and at 22:00, for the hours-sign screenshots.
-- Views 1-3 are 08:00 (Tool Shed, Hearth & Home, Dealership).
-- Views 4-6 are 22:00, with the night preset.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local Hours = ctx.load("ReplicatedStorage/Shared/ShopHoursLogic")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 420, C3.fromRGB(116, 164, 84), V3.new(80, -0.5, 50))

		local shops = {
			{ "ToolShed", "TOOL SHED", C3.fromRGB(150, 62, 44) },
			{ "HearthAndHome", "HEARTH & HOME", C3.fromRGB(122, 90, 60) },
			{ "Dealership", "DEALERSHIP", C3.fromRGB(47, 109, 181) },
		}
		local cameras = {}
		local function place(kind, title, accent, hour, x, z, label, night)
			local model = BuildingArt.Shop(kind, title, accent)
			BuildingArt.PaintDoor(model, not Hours.IsOpen(kind, hour))
			Hours.WriteSigns(model, hour)
			Kit.placeAt(model, CF.new(x, 0, z))
			model.Parent = root
			local board = model:FindFirstChild("HoursBoard", true)
			local p = if board then board.CFrame.Position else V3.new(x, 8, z)
			table.insert(cameras, {
				pos = { p.X, p.Y + 1.5, p.Z - 16 },
				target = { p.X, p.Y, p.Z },
				label = label,
				fov = 36,
				night = night,
			})
		end
		for i, shop in ipairs(shops) do
			local x = (i - 1) * 70
			place(shop[1], shop[2], shop[3], 8, x, 0, shop[1] .. " 08:00", false)
			place(shop[1], shop[2], shop[3], 22, x, 90, shop[1] .. " 22:00", true)
		end
		-- Views follow the screenshot list: each shop at 08:00, then at 22:00.
		local ordered = {
			cameras[1],
			cameras[3],
			cameras[5],
			cameras[2],
			cameras[4],
			cameras[6],
		}
		return { root = root, cameras = ordered }
	end,
}
