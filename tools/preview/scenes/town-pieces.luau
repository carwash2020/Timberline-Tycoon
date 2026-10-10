--!nocheck
-- The shops, the sawmill and the gondola station each on their own patch of
-- ground, facing -Z as the town places them, to check every piece sits where
-- it should (signs on their frames, roofs on walls, nothing floating, sunk,
-- backwards). 1-3 the Tool Shed (front, from the side, from above), 4-6
-- Hearth & Home, 7-9 the Dealership, 10-11 the sawmill, 12 the station.
local process = require("@lune/process")
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		-- The game ships GameConfig.TownMeshes = false (MapBuilder sets it), so the
		-- part-built town is what players see; TOWN_MESHES=1 previews the
		-- uploaded meshes dressed on instead (what flipping the switch would do).
		ctx.art("TownMeshes").Enabled = process.env.TOWN_MESHES == "1"
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 1200, C3.fromRGB(116, 164, 84), V3.new(300, -0.5, 0))
		local function place(model, x)
			Kit.placeAt(model, CF.new(x, 0, 0))
			model.Parent = root
		end
		place(BuildingArt.Shop("ToolShed", "TOOL SHED", C3.fromRGB(184, 53, 40)), 0)
		place(BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", C3.fromRGB(47, 93, 58)), 100)
		place(BuildingArt.Shop("Dealership", "DEALERSHIP", C3.fromRGB(30, 80, 150)), 200)
		place(BuildingArt.Sawmill(), 300)
		place(BuildingArt.GondolaStation(), 400)
		local function cams(x, label, dist, h, tz)
			return {
				{ pos = { x, h, -dist }, target = { x, h * 0.6, tz }, label = label .. " front" },
				{ pos = { x + dist, h * 0.8, -dist * 0.4 }, target = { x, h * 0.6, tz }, label = label .. " side" },
				{
					pos = { x - dist * 0.7, h * 2.2, -dist * 0.9 },
					target = { x, h * 0.6, tz },
					label = label .. " above",
				},
			}
		end
		local cameras = {}
		for _, set in ipairs({
			cams(0, "ToolShed", 90, 14, 0),
			cams(100, "Hearth", 90, 14, 0),
			cams(200, "Dealership", 110, 14, 0),
		}) do
			for _, c in ipairs(set) do
				table.insert(cameras, c)
			end
		end
		table.insert(cameras, { pos = { 300, 14, -60 }, target = { 300, 10, 0 }, label = "Sawmill front" })
		table.insert(cameras, { pos = { 340, 12, -30 }, target = { 300, 8, 0 }, label = "Sawmill side" })
		table.insert(cameras, { pos = { 400, 9, -24 }, target = { 400, 6, 0 }, label = "Station front" })
		return { root = root, shadowRadius = 120, fov = 50, cameras = cameras }
	end,
}
