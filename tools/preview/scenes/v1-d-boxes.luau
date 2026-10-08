--!nocheck
-- Lane D: shop boxes, three-quarter, so the band, the windows and the
-- plate read, and every box is inside the frame.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local BoxArt = ctx.art("BoxArt")
		local ItemBox = ctx.shared("ItemBox")
		local root = roblox.Instance.new("Model")
		local goods = {
			{ "Axe", "SteelAxe", "Steel Axe" },
			{ "Axe", "InfernoAxe", "Inferno Axe" },
			{ "Sawmill", "Millmaster100", "Millmaster 100" },
			{ "Gear", "Lantern", "Lantern" },
			{ "Truck", "Rustbucket", "Rustbucket" },
		}

		local function make(row, x, y, z)
			local size = ItemBox.Size(row[1], row[2])
			local model = roblox.Instance.new("Model")
			model.Name = row[2]
			local body = Kit.part(
				model,
				"Box",
				size,
				CF.new(0, size.Y / 2, 0),
				C3.fromRGB(34, 36, 41),
				Enum.Material.SmoothPlastic
			)
			body.CanCollide = false
			BoxArt.Dress(model, body, { name = row[3], kind = row[1], itemId = row[2] })
			model:PivotTo(CF.new(x, y, z))
			model.Parent = root
			return model, size
		end

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

		local front, back = {}, {}
		for _, row in ipairs(goods) do
			local size = ItemBox.Size(row[1], row[2])
			if size.X >= 6 or size.Y >= 4.5 then
				table.insert(back, row)
			else
				table.insert(front, row)
			end
		end

		local GAP = 1.6
		local function rowWidth(list)
			local w = 0
			for i, row in ipairs(list) do
				w += ItemBox.Size(row[1], row[2]).X
				if i < #list then
					w += GAP
				end
			end
			return w
		end
		local function placeRow(list, y, z)
			local models = {}
			local cursor = -rowWidth(list) / 2
			for _, row in ipairs(list) do
				local size = ItemBox.Size(row[1], row[2])
				local model = make(row, cursor + size.X / 2, y, z)
				models[row[2]] = model
				cursor += size.X + GAP
			end
			return models
		end

		local frontModels = placeRow(front, 0, -6)
		local frontTop = 0
		for _, model in pairs(frontModels) do
			local _, hi = modelBounds(model, empty())
			frontTop = math.max(frontTop, hi.Y)
		end
		local step = frontTop + 0.5
		local backModels = placeRow(back, step, 6)
		local backWidth = rowWidth(back) + 2
		Kit.part(
			root,
			"Step",
			V3.new(math.max(backWidth, 8), step, 8),
			CF.new(0, step / 2, 6),
			C3.fromHex("#7A5230"), -- TimberBrown
			Enum.Material.Wood
		)

		local allMin, allMax = empty()
		local byId = {}
		for id, model in pairs(frontModels) do
			byId[id] = model
			allMin, allMax = modelBounds(model, allMin, allMax)
		end
		for id, model in pairs(backModels) do
			byId[id] = model
			allMin, allMax = modelBounds(model, allMin, allMax)
		end
		local span = allMax - allMin
		Kit.part(
			root,
			"Ground",
			V3.new(span.X + 18, 1, span.Z + 24),
			CF.new((allMin.X + allMax.X) / 2, -0.5, (allMin.Z + allMax.Z) / 2),
			C3.fromRGB(186, 166, 132),
			Enum.Material.WoodPlanks
		)

		local FOV = 32
		local ASPECT = 1280 / 800
		local function frame(models, label, margin)
			local lo, hi = empty()
			for _, model in ipairs(models) do
				lo, hi = modelBounds(model, lo, hi)
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
			local dist = 14
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
			dist *= margin or 1.3
			local eye = eyeAt(dist)
			return { pos = { eye.X, eye.Y, eye.Z }, target = { center.X, center.Y, center.Z }, label = label }
		end

		local all = {}
		for _, model in pairs(byId) do
			table.insert(all, model)
		end
		return {
			root = root,
			shadowRadius = 50,
			fov = FOV,
			cameras = {
				frame(all, "five boxes"),
				frame({ byId.SteelAxe }, "Steel Axe box", 1.45),
				frame({ byId.Millmaster100 }, "sawmill box", 1.4),
			},
		}
	end,
}
