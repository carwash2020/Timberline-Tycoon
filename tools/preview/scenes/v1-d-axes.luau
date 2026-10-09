--!nocheck
-- Lane D: the axe ladder in a 3/4 view (30 degrees off the side, 15 degrees
-- down) so each head reads as a solid. Rows of four. Name plaques stand
-- behind and above the head, so the axe from butt to tip stays clear.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local AxeArt = ctx.art("AxeArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local root = roblox.Instance.new("Model")

		local axes = {}
		for _, def in ipairs(ItemCatalog.AxeLadder()) do
			table.insert(axes, def)
		end
		local lux = ItemCatalog.GetAxe("LuxAxe")
		local maul = ItemCatalog.GetAxe("HermitsMaul")
		if lux then
			table.insert(axes, lux)
		end
		if maul then
			table.insert(axes, maul)
		end

		local GAP = 5.4
		local PER = 4
		-- Camera sits on -Z. The first row is the near one.
		local ROW_Z = { -9, 0, 9 }
		local turn = CF.Angles(0, math.pi / 2, 0)

		local function corners(cf, size)
			local out = {}
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						table.insert(out, cf * V3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2))
					end
				end
			end
			return out
		end

		local function absorb(minv, maxv, cf, size)
			for _, p in ipairs(corners(cf, size)) do
				minv = V3.new(math.min(minv.X, p.X), math.min(minv.Y, p.Y), math.min(minv.Z, p.Z))
				maxv = V3.new(math.max(maxv.X, p.X), math.max(maxv.Y, p.Y), math.max(maxv.Z, p.Z))
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

		local function emptyBounds()
			return V3.new(math.huge, math.huge, math.huge), V3.new(-math.huge, -math.huge, -math.huge)
		end

		local function topY(model)
			local minv, maxv = modelBounds(model, emptyBounds())
			return maxv.Y
		end

		local placed = {}
		local rowCount = math.ceil(#axes / PER)
		local rowN = {}
		for r = 1, rowCount do
			rowN[r] = math.min(PER, #axes - (r - 1) * PER)
		end

		for i, def in ipairs(axes) do
			local axe = AxeArt.Build(def)
			local r = math.floor((i - 1) / PER) + 1
			local col = (i - 1) % PER + 1
			local x = (col - (rowN[r] + 1) / 2) * GAP
			local z = ROW_Z[r]
			axe:PivotTo(CF.new(x, 0, z) * turn)
			axe.Parent = root
			placed[i] = { axe = axe, def = def, x = x, z = z, row = r }
		end

		-- Each row stands above the one in front, signs included, so a
		-- 15-degree camera does not hide the back row behind the front.
		local heights = {}
		for r = 1, rowCount do
			heights[r] = 0
		end
		for _, row in ipairs(placed) do
			heights[row.row] = math.max(heights[row.row], topY(row.axe))
		end
		local foot = { 0 }
		for r = 2, rowCount do
			foot[r] = foot[r - 1] + heights[r - 1] + 1.4
		end
		for _, row in ipairs(placed) do
			row.foot = foot[row.row]
			if row.foot > 0 then
				row.axe:PivotTo(CF.new(row.x, row.foot, row.z) * turn)
			end
		end

		for r = 2, rowCount do
			Kit.part(
				root,
				"Step",
				V3.new((rowN[r] - 1) * GAP + 4, foot[r], 3.4),
				CF.new(0, foot[r] / 2, ROW_Z[r]),
				C3.fromHex("#7A5230"), -- TimberBrown
				Enum.Material.Wood
			)
		end

		-- A small plaque above the head and a stud behind it (further from
		-- the camera), so it never covers the butt or the blade.
		local labels = {}
		for i, row in ipairs(placed) do
			local top = topY(row.axe)
			local h = 0.38
			local sign = Kit.part(
				root,
				"Label",
				V3.new(2.1, h, 0.08),
				CF.new(row.x, top + 0.5 + h / 2, row.z + 1.15),
				C3.fromHex("#F3E7C9"), -- SignCream
				Enum.Material.SmoothPlastic
			)
			Kit.signText(sign, row.def.displayName, C3.fromHex("#2A2420"), { Enum.NormalId.Front }) -- SignInk
			labels[i] = sign
		end

		local minv, maxv = emptyBounds()
		for _, row in ipairs(placed) do
			minv, maxv = modelBounds(row.axe, minv, maxv)
		end
		for _, sign in ipairs(labels) do
			minv, maxv = absorb(minv, maxv, sign.CFrame, sign.Size)
		end
		local span = maxv - minv
		Kit.part(
			root,
			"Ground",
			V3.new(span.X + 16, 1, span.Z + 20),
			CF.new((minv.X + maxv.X) / 2, -0.5, (minv.Z + maxv.Z) / 2),
			C3.fromRGB(186, 166, 132),
			Enum.Material.WoodPlanks
		)

		-- 30 degrees off the side view, 15 degrees down. Pull back until
		-- every corner of the subject sits inside the 1280x800 frame.
		local FOV = 32
		local ASPECT = 1280 / 800
		local function frame(subjects, label, margin)
			local lo, hi = emptyBounds()
			for _, inst in ipairs(subjects) do
				if inst:IsA("Model") then
					lo, hi = modelBounds(inst, lo, hi)
				elseif inst:IsA("BasePart") then
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
			local function boxCorners()
				local out = {}
				for _, x in ipairs({ lo.X, hi.X }) do
					for _, y in ipairs({ lo.Y, hi.Y }) do
						for _, z in ipairs({ lo.Z, hi.Z }) do
							table.insert(out, V3.new(x, y, z))
						end
					end
				end
				return out
			end
			local dist = 12
			for _ = 1, 6 do
				local eye = eyeAt(dist)
				local forward = (center - eye).Unit
				local right = forward:Cross(V3.new(0, 1, 0)).Unit
				local up = right:Cross(forward)
				local maxR, maxU = 0, 0
				for _, p in ipairs(boxCorners()) do
					local d = p - eye
					local z = math.max(d:Dot(forward), 0.05)
					maxR = math.max(maxR, math.abs(d:Dot(right) / z))
					maxU = math.max(maxU, math.abs(d:Dot(up) / z))
				end
				local vHalf = math.tan(math.rad(FOV / 2))
				local hHalf = vHalf * ASPECT
				dist *= math.max(maxR / hHalf, maxU / vHalf, 0.5)
			end
			dist *= margin or 1.5
			local eye = eyeAt(dist)
			return { pos = { eye.X, eye.Y, eye.Z }, target = { center.X, center.Y, center.Z }, label = label }
		end

		local all = {}
		for _, row in ipairs(placed) do
			table.insert(all, row.axe)
		end
		for _, sign in ipairs(labels) do
			table.insert(all, sign)
		end
		local cameras = {
			frame(all, "eleven axes, three-quarter"),
		}
		local groups = {
			{ 1, 3, "Rusty, Steel, Hardened" },
			{ 4, 6, "Silver, Cobalt, Gold" },
			{ 7, 9, "Obsidian, Inferno, Starfall" },
			{ 10, 11, "Lux and the Hermit's Maul" },
		}
		for _, g in ipairs(groups) do
			local subjects = {}
			for i = g[1], g[2] do
				table.insert(subjects, placed[i].axe)
				table.insert(subjects, labels[i])
			end
			table.insert(cameras, frame(subjects, g[3], 1.5))
		end
		for i, row in ipairs(placed) do
			table.insert(cameras, frame({ row.axe, labels[i] }, row.def.displayName, 1.55))
		end
		return {
			root = root,
			shadowRadius = 80,
			fov = FOV,
			cameras = cameras,
		}
	end,
}
