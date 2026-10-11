--!nocheck
-- Lane X: the town leaderboard board, as the game builds it (TownBoardArt
-- with TownBoardLogic's view). Two boards on one lawn, MainStreet in front:
--   the board at x = 0 holds ten opted-in players, the one at x = 200 is the
--   empty state (nobody opted in). Both stand 8 studs north of the street's
--   edge, front toward the street (-Z), as the plan has them.
-- The viewer draws each label centred in its own box (it cannot left-align
-- text and has no rounded plates), so row text is centred here; in game the
-- names sit left of the cash line, on a plate, beside a rank medal.
--   1 day, 3/4 from the street   2 night, 3/4   3 from the street at 30 studs
--   4 from the street, eye height   5 up close   6 empty state   7 failed
--   8 from the side   9 from behind
local Common = require("./_common")

local NAMES = {
	{ "TimberTom", 1998765 },
	{ "AxelWoods", 1764200 },
	{ "PineQueen", 1320450 },
	{ "StumpJumper", 987300 },
	{ "CedarSam", 754120 },
	{ "BirchBaron", 512890 },
	{ "OakOllie", 301450 },
	{ "MapleMae", 188200 },
	{ "FernFoster", 96400 },
	{ "WillowWren", 41250 },
}

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local TownBoardArt = ctx.art("TownBoardArt")
		local TownBoardLogic = ctx.shared("TownBoardLogic")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 900, C3.fromRGB(104, 152, 74), V3.new(100, -0.5, 0))
		-- MainStreet: its north edge is 8 studs south of the board's middle.
		Kit.part(root, "Street", V3.new(500, 0.2, 22), CF.new(100, 0.05, -8 - 11), C3.fromRGB(150, 150, 146))
		local cameras = {}

		local function stand(model, x)
			Kit.placeAt(model, CF.new(x, 0, 0))
			model.Parent = root
		end

		local rows = {}
		for i, entry in ipairs(NAMES) do
			table.insert(rows, { rank = i, name = entry[1], score = entry[2] })
		end
		local full = TownBoardArt.Build()
		TownBoardArt.Fill(full, TownBoardLogic.View(rows, false))
		stand(full, 0)
		local empty = TownBoardArt.Build()
		TownBoardArt.Fill(empty, TownBoardLogic.View({}, false))
		stand(empty, 200)
		local failed = TownBoardArt.Build()
		TownBoardArt.Fill(failed, TownBoardLogic.View(nil, true))
		stand(failed, 400)

		-- Preview only: fill lights in front of each board so the night shot is
		-- not black (named LampGlow, switched off: the viewer lights them at night).
		for bx = 0, 400, 200 do
			for i, at in ipairs({
				V3.new(bx, 7, -8),
				V3.new(bx + 6, 10, -14),
				V3.new(bx - 6, 6, -18),
				V3.new(bx + 9, 6, -6),
			}) do
				local fill = Kit.part(root, "LampGlow", V3.new(0.2, 0.2, 0.2), CF.new(at), C3.new(1, 1, 1))
				fill.Transparency = 1
				fill.CanCollide = false
				local light = roblox.Instance.new("PointLight")
				light.Name = "PreviewFill" .. i
				light.Range = 60
				light.Brightness = 14
				light.Color = C3.fromRGB(255, 236, 205)
				light.Enabled = false
				light.Parent = fill
			end
		end

		local function add(label, pos, target, fov, night)
			table.insert(cameras, { pos = pos, target = target, label = label, fov = fov, night = night })
		end
		add("day-3q", { 15, 12.5, -20 }, { 0.3, 5.8, 0 }, 46, false)
		add("night-3q", { 15, 12.5, -20 }, { 0.3, 5.8, 0 }, 46, true)
		add("street-30", { 4, 5.6, -30 }, { 0, 6.3, 0 }, 55, false)
		add("street-eye", { 3, 5.6, -13 }, { 0, 6.8, 0 }, 70, false)
		add("closeup", { 4, 6.6, -11 }, { 0, 5.7, 0 }, 58, false)
		add("empty", { 215, 12.5, -20 }, { 200.3, 5.8, 0 }, 46, false)
		add("failed", { 415, 12.5, -20 }, { 400.3, 5.8, 0 }, 46, false)
		add("side", { -17, 8, -9 }, { 0, 5.5, 0 }, 50, false)
		add("back", { -12, 10, 17 }, { 0, 5.6, 0 }, 50, false)
		return { root = root, shadowRadius = 60, fov = 50, cameras = cameras }
	end,
}
