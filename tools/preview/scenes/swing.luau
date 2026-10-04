--!nocheck
-- The two-handed chop at phone size (375x667): wind-up apex, impact, and
-- the deepest follow-through, on flat ground and on a slope, R15 and R6.
-- The blocks are SwingLogic.Figure, the same pose the clearance spec measures.
-- A slope eases the follow-through the way the client's ground ray does.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local SwingLogic = ctx.shared("SwingLogic")
		local root = roblox.Instance.new("Model")
		local LEN = 3.5

		local function eased(rig, clip)
			local function clear(scale)
				local low = SwingLogic.BladeLow(rig, LEN, clip, "bite", scale)
				local foot = SwingLogic.FootPlane(rig)
				local worldY = low.Y - foot
				local ground = math.max(0, -0.55 * low.Z)
				return worldY >= ground + SwingLogic.GroundStop
			end
			if clear(1) then
				return 1
			end
			local lo, hi = 0, 1
			for _ = 1, 6 do
				local mid = (lo + hi) / 2
				if clear(mid) then
					lo = mid
				else
					hi = mid
				end
			end
			return lo
		end

		local shots = {
			{ rig = "R15", clip = SwingLogic.Apex, slope = false, label = "R15 wind-up, flat" },
			{ rig = "R15", clip = SwingLogic.Impact, slope = false, label = "R15 impact, flat" },
			{ rig = "R15", clip = SwingLogic.FollowEnd, slope = false, label = "R15 follow-through, flat" },
			{ rig = "R15", clip = SwingLogic.Apex, slope = true, label = "R15 wind-up, slope" },
			{ rig = "R15", clip = SwingLogic.Impact, slope = true, label = "R15 impact, slope" },
			{ rig = "R15", clip = SwingLogic.FollowEnd, slope = true, label = "R15 follow-through, slope" },
			{ rig = "R6", clip = SwingLogic.Apex, slope = false, label = "R6 wind-up, flat" },
			{ rig = "R6", clip = SwingLogic.Impact, slope = false, label = "R6 impact, flat" },
			{ rig = "R6", clip = SwingLogic.FollowEnd, slope = false, label = "R6 follow-through, flat" },
			{ rig = "R6", clip = SwingLogic.Apex, slope = true, label = "R6 wind-up, slope" },
			{ rig = "R6", clip = SwingLogic.Impact, slope = true, label = "R6 impact, slope" },
			{ rig = "R6", clip = SwingLogic.FollowEnd, slope = true, label = "R6 follow-through, slope" },
		}

		local cameras = {}
		for i, shot in ipairs(shots) do
			local x = (i - 1) * 24
			local scale = if shot.slope then eased(shot.rig, shot.clip) else 1
			local contact = if shot.clip >= SwingLogic.Impact then "bite" else nil
			local blocks = SwingLogic.Figure(shot.rig, LEN, shot.clip, contact, scale)
			local foot = SwingLogic.FootPlane(shot.rig)
			local stand = CF.new(x, -foot, 0)
			for _, b in ipairs(blocks) do
				Kit.part(root, b.name, b.size, stand * b.cf, b.color, Enum.Material.SmoothPlastic)
			end
			local bark = C3.fromRGB(92, 64, 40)
			Kit.part(root, "Trunk", V3.new(1.6, 8, 1.6), CF.new(x, 4, -3.2), bark, Enum.Material.Wood)
			if shot.slope then
				local ramp = Kit.part(
					root,
					"Slope",
					V3.new(14, 0.4, 16),
					CF.new(x, 0.6, -1) * CF.Angles(math.rad(-28), 0, 0),
					C3.fromRGB(96, 122, 64),
					Enum.Material.Grass
				)
				ramp.CFrame = CF.new(x, 1.1, -2.2) * CF.Angles(math.rad(-28), 0, 0)
			else
				Kit.part(
					root,
					"Ground",
					V3.new(16, 1, 16),
					CF.new(x, -0.5, 0),
					C3.fromRGB(118, 156, 78),
					Enum.Material.Grass
				)
			end
			local focus = V3.new(x, 2.2, -0.4)
			local eye = focus + V3.new(7.2, 1.6, 6.4)
			table.insert(cameras, {
				pos = { eye.X, eye.Y, eye.Z },
				target = { focus.X, focus.Y, focus.Z },
				label = shot.label,
				fov = 32,
			})
		end

		return {
			root = root,
			shadowRadius = 40,
			fov = 32,
			cameras = cameras,
		}
	end,
}
