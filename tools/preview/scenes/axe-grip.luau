--!nocheck
-- Every axe held in the right hand, the way Roblox holds a Tool: R6's
-- RightGrip is the arm's bottom face, its -Z down the arm; the "hold" pose
-- raises the arm forward, and the Handle sits at RightGrip * Tool.Grip:Inverse().
-- Three cameras per axe: side-on, three-quarter from behind, straight from
-- behind. The figures face -Z, so the cutting edge must point at -Z, away
-- from the player, at the trunk. For the grip fix (previews/axe-grip).

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local AxeArt = ctx.art("AxeArt")
		local CharacterArt = ctx.art("CharacterArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local root = roblox.Instance.new("Model")

		local axes = ItemCatalog.AxeLadder()
		local have = {}
		for _, d in ipairs(axes) do
			have[d.id] = true
		end
		local rest = {}
		for id, d in pairs(ItemCatalog.Axes) do
			if not have[id] then
				table.insert(rest, d)
			end
		end
		table.sort(rest, function(a, b)
			return a.id < b.id
		end)
		for _, d in ipairs(rest) do
			table.insert(axes, d)
		end
		local GAP = 16
		Kit.part(
			root,
			"Ground",
			V3.new(#axes * GAP + 30, 1, 60),
			CF.new((#axes - 1) * GAP / 2, -0.5, 0),
			C3.fromRGB(196, 176, 140),
			Enum.Material.WoodPlanks
		)
		local cameras = {}
		local function cam(x, y, z, tx, ty, tz, label)
			table.insert(cameras, { pos = { x, y, z }, target = { tx, ty, tz }, label = label })
		end
		for i, def in ipairs(axes) do
			local x = (i - 1) * GAP
			local fig = CharacterArt.Build({
				name = "Holder" .. i,
				skin = C3.fromHex("#E8B994"),
				shirt = C3.fromHex("#B8382E"),
				stripe = C3.fromHex("#3A1A16"),
				pants = C3.fromHex("#3D5A8C"),
				hair = C3.fromHex("#5A3A22"),
				hat = "cap",
				hatColor = C3.fromHex("#4C7A3E"),
				tag = false,
			})
			local arm = fig.RightArm
			local shoulder = arm.CFrame * CF.new(0, 0.55, 0)
			local raise = shoulder * CF.Angles(math.pi / 2, 0, 0) * shoulder:Inverse()
			local moving = { arm }
			for _, d in ipairs(arm:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(moving, d)
				end
			end
			for _, p in ipairs(moving) do
				p.CFrame = raise * p.CFrame
			end
			local axe = AxeArt.Held(def)
			local grip = arm.CFrame * CF.new(0, -1, 0) * CF.Angles(-math.pi / 2, 0, 0)
			axe:PivotTo(grip * AxeArt.Grip(def):Inverse())
			axe.Parent = fig
			Kit.placeAt(fig, CF.new(x, 0, 0))
			fig.Parent = root
			-- The trunk, 6.5 studs ahead (-Z): where the edge should point.
			Kit.part(
				root,
				"Trunk",
				V3.new(1.6, 9, 1.6),
				CF.new(x, 4.5, -6.5),
				C3.fromRGB(96, 66, 40),
				Enum.Material.Wood
			)
			local name = def.displayName
			cam(x + 14, 5.2, -1.4, x, 4.6, -1.4, name .. " side")
			cam(x + 9, 6.5, 9, x, 4.4, -1.4, name .. " 3/4 from behind")
			cam(x, 5.5, 13, x, 4.4, -1.4, name .. " from behind")
		end
		return { root = root, shadowRadius = 60, fov = 35, cameras = cameras }
	end,
}
