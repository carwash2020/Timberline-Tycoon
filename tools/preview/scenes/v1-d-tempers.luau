--!nocheck
-- Lane D: temper colours on a Steel Axe. The lineup is every tier. The
-- last camera is Keen, Heavy and Prosperous at tier 3, side by side,
-- close enough that the band and the neon edge read.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local AxeArt = ctx.art("AxeArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local root = roblox.Instance.new("Model")

		local steel = ItemCatalog.GetAxe("SteelAxe")
		local families = { "Keen", "Heavy", "Prosperous" }
		local roman = { "I", "II", "III" }
		local GAP = 3.6
		local turn = CF.Angles(0, math.pi / 2, 0)
		local ROW_Z = { 8, 0, -8 }

		local function empty()
			return V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
		end
		local function absorb(minv, maxv, cf, size)
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = cf * V3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2)
						minv = V3.new(math.min(minv.X, p.X), math.min(minv.Y, p.Y), math.min(minv.Z, p.Z))
						maxv = V3.new(math.max(maxv.X, p.X), math.max(maxv.Y, p.Y), math.max(maxv.Z, p.Z))
					end
				end
			end
			return minv, maxv
		end
		local function modelBounds(model, minv, maxv)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					minv, maxv = absorb(minv, maxv, d.CFrame, d.Size)
				end
			end
			return minv, maxv
		end
		local function topOf(model)
			local _, hi = modelBounds(model, empty())
			return hi.Y
		end

		local grid = {}
		local tall = 0
		do
			local probe = AxeArt.Build(steel)
			probe:PivotTo(CF.new(0, 0, 0) * turn)
			tall = topOf(probe)
			probe:Destroy()
		end
		-- Clear of the plaque, which sits above the head.
		local step = tall + 1.35

		for f, family in ipairs(families) do
			local foot = (3 - f) * step
			local z = ROW_Z[f]
			if foot > 0 then
				Kit.part(
					root,
					"Step",
					V3.new(GAP * 2 + 3.4, foot, 3.2),
					CF.new(0, foot / 2, z),
					C3.fromHex("#7A5230"), -- TimberBrown
					Enum.Material.Wood
				)
			end
			for tier = 1, 3 do
				local x = (tier - 2) * GAP
				local axe = AxeArt.Build(steel)
				AxeArt.ApplyTemper(axe, family, tier)
				axe:PivotTo(CF.new(x, foot, z) * turn)
				axe.Parent = root
				local top = topOf(axe)
				local h = 0.36
				local sign = Kit.part(
					root,
					"Label",
					V3.new(2.0, h, 0.08),
					CF.new(x, top + 0.45 + h / 2, z + 1.1),
					C3.fromHex("#F3E7C9"), -- SignCream
					Enum.Material.SmoothPlastic
				)
				Kit.signText(sign, family .. " " .. roman[tier], C3.fromHex("#2A2420"), { Enum.NormalId.Front }) -- SignInk
				table.insert(grid, { axe = axe, sign = sign, family = family, tier = tier })
			end
		end

		-- The tier-3 trio, off to the side, for the close-up only.
		local trio = {}
		for i, family in ipairs(families) do
			local x = 28 + (i - 1) * 2.8
			local axe = AxeArt.Build(steel)
			AxeArt.ApplyTemper(axe, family, 3)
			axe:PivotTo(CF.new(x, 0, 40) * turn)
			axe.Parent = root
			table.insert(trio, axe)
		end

		local minv, maxv = empty()
		for _, row in ipairs(grid) do
			minv, maxv = modelBounds(row.axe, minv, maxv)
			minv, maxv = absorb(minv, maxv, row.sign.CFrame, row.sign.Size)
		end
		local span = maxv - minv
		Kit.part(
			root,
			"Ground",
			V3.new(math.max(span.X + 16, 50), 1, math.max(span.Z + 24, 70)),
			CF.new((minv.X + maxv.X) / 2, -0.5, 16),
			C3.fromRGB(186, 166, 132),
			Enum.Material.WoodPlanks
		)

		local FOV = 32
		local ASPECT = 1280 / 800
		local function frame(subjects, label, margin)
			local lo, hi = empty()
			for _, inst in ipairs(subjects) do
				if inst:IsA("Model") then
					lo, hi = modelBounds(inst, lo, hi)
				else
					lo, hi = absorb(lo, hi, inst.CFrame, inst.Size)
				end
			end
			local center = (lo + hi) / 2
			local pitch, yaw = math.rad(15), math.rad(30)
			local function eyeAt(dist)
				local horiz = dist * math.cos(pitch)
				return V3.new(
					center.X - horiz * math.sin(yaw),
					center.Y + dist * math.sin(pitch),
					center.Z - horiz * math.cos(yaw)
				)
			end
			local dist = 10
			for _ = 1, 6 do
				local eye = eyeAt(dist)
				local forward = (center - eye).Unit
				local right = forward:Cross(V3.new(0, 1, 0)).Unit
				local up = right:Cross(forward)
				local maxR, maxU = 0, 0
				for _, x in ipairs({ lo.X, hi.X }) do
					for _, y in ipairs({ lo.Y, hi.Y }) do
						for _, z in ipairs({ lo.Z, hi.Z }) do
							local d = V3.new(x, y, z) - eye
							local depth = math.max(d:Dot(forward), 0.05)
							maxR = math.max(maxR, math.abs(d:Dot(right) / depth))
							maxU = math.max(maxU, math.abs(d:Dot(up) / depth))
						end
					end
				end
				local vHalf = math.tan(math.rad(FOV / 2))
				dist *= math.max(maxR / (vHalf * ASPECT), maxU / vHalf, 0.5)
			end
			dist *= margin or 1.5
			local eye = eyeAt(dist)
			return { pos = { eye.X, eye.Y, eye.Z }, target = { center.X, center.Y, center.Z }, label = label }
		end

		local lineup = {}
		for _, row in ipairs(grid) do
			table.insert(lineup, row.axe)
			table.insert(lineup, row.sign)
		end
		local cameras = { frame(lineup, "nine temper looks") }
		for _, row in ipairs(grid) do
			table.insert(cameras, frame({ row.axe, row.sign }, row.family .. " " .. roman[row.tier], 1.45))
		end
		table.insert(cameras, frame(trio, "Keen, Heavy and Prosperous at tier 3", 1.2))
		return {
			root = root,
			shadowRadius = 80,
			fov = FOV,
			cameras = cameras,
		}
	end,
}
