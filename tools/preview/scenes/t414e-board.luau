--!nocheck
-- T414e: the town board, filled with ten names, seen from the street at phone distance.
-- 1 about 14 studs out (across the street), 2 about 30 studs out, 3 the back and a post close up.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local C3 = roblox.Color3
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 160, C3.fromRGB(150, 138, 120))
		local TownBoardArt = ctx.art("TownBoardArt")
		local TownBoardLogic = ctx.shared("TownBoardLogic")
		local board = TownBoardArt.Build()
		local list = {}
		for i = 1, 10 do
			table.insert(list, { rank = i, name = "Lumberjack" .. i, score = 2000000 - i * 123456 })
		end
		TownBoardArt.Fill(board, TownBoardLogic.View(list, false))
		board.Parent = root
		return {
			root = root,
			fov = 70,
			cameras = {
				{ pos = { 0, 5, -14 }, target = { 0, 5.5, 0 }, label = "14 studs out" },
				{ pos = { 0, 4.5, -30 }, target = { 0, 5.5, 0 }, label = "30 studs out" },
				{ pos = { 9, 5, 7 }, target = { 0, 5.5, 0 }, label = "the back, three-quarter" },
			},
		}
	end,
}
