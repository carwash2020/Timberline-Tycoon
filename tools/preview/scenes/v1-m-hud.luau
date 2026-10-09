--!nocheck
-- Stand-in of the mining chip and shop on a phone frame. Thumbstick and
-- jump zones are marked. The live UI is MiningUI.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local root = roblox.Instance.new("Model")
		local w, h = 16, 9
		local ink = C3.fromRGB(60, 40, 20)
		local cream = C3.fromRGB(245, 235, 215)
		local paper = C3.fromRGB(240, 225, 195)
		local bark = C3.fromRGB(74, 52, 32)
		local money = C3.fromRGB(63, 122, 52)
		local danger = C3.fromRGB(192, 80, 58)
		Kit.part(
			root,
			"Screen",
			V3.new(w, h, 0.2),
			CF.new(0, 0, 0),
			C3.fromRGB(28, 36, 32),
			Enum.Material.SmoothPlastic
		)
		local stick = Kit.part(
			root,
			"Thumbstick",
			V3.new(w * 0.4, h * 0.5, 0.12),
			CF.new(-w * 0.3, -h * 0.25, 0.4),
			C3.fromRGB(40, 70, 90),
			Enum.Material.SmoothPlastic
		)
		Kit.signText(stick, "thumbstick", cream, { Enum.NormalId.Back })
		local jump = Kit.part(
			root,
			"Jump",
			V3.new(2.4, 2.6, 0.12),
			CF.new(w / 2 - 1.2, -h / 2 + 1.3, 0.4),
			C3.fromRGB(50, 80, 60),
			Enum.Material.SmoothPlastic
		)
		Kit.signText(jump, "jump", cream, { Enum.NormalId.Back })
		local chip = Kit.part(
			root,
			"Chip",
			V3.new(5.2, 0.9, 0.16),
			CF.new(w / 2 - 2.9, h / 2 - 0.7, 0.55),
			bark,
			Enum.Material.SmoothPlastic
		)
		Kit.signText(chip, "Iron Pick  ·  Lv 3  ·  Bombs 2  ·  Lamp", cream, { Enum.NormalId.Back })
		local panel = Kit.part(
			root,
			"Shop",
			V3.new(6.4, 3.4, 0.16),
			CF.new(-w / 2 + 3.6, h / 2 - 2.4, 0.5),
			paper,
			Enum.Material.SmoothPlastic
		)
		Kit.signText(panel, "Prospector", ink, { Enum.NormalId.Back })
		local function row(text, y, afford)
			local button = Kit.part(
				root,
				"Buy",
				V3.new(5.6, 0.7, 0.18),
				CF.new(-w / 2 + 3.6, y, 0.75),
				if afford then money else danger,
				Enum.Material.SmoothPlastic
			)
			Kit.signText(button, text, cream, { Enum.NormalId.Back })
		end
		row("Copper Pick  $450", 2.2, true)
		row("Iron Pick  $3000", 1.3, false)
		row("Bomb  $220", 0.4, true)
		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label, fov = 32 }
		end
		return {
			root = root,
			shadowRadius = 12,
			fov = 32,
			cameras = {
				cam(0, 0, 16, 0, 0, 0, "mining hud"),
			},
		}
	end,
}
