--!nocheck
-- Ore rows on the shared hover tag. HoverTag.spec is unchanged: shop
-- lines, the 0.08 s hold, and the aim ranges stay as they were.

return function(t)
	local Instance = t.roblox.Instance
	local HoverTag = t.load("ReplicatedStorage/Shared/HoverTag")
	local OreData = t.load("ReplicatedStorage/Shared/Mining/OreData")
	local PickaxeData = t.load("ReplicatedStorage/Shared/Mining/PickaxeData")

	local function oreSpec(ore)
		return {
			key = "Ore:" .. ore.id,
			name = ore.name,
			kind = "Ore",
			itemId = ore.id,
			tier = ore.tier,
			need = ore.hardness,
			anchor = true,
		}
	end

	t.test("aim ranges and the switch hold are unchanged", function()
		t.eq(HoverTag.MouseRange, 60)
		t.eq(HoverTag.HideDelay, 0.3)
		t.eq(HoverTag.GamepadRange, 12)
		t.eq(HoverTag.TouchRange, 6)
		t.eq(HoverTag.TouchSeconds, 4)
		t.eq(HoverTag.SwitchDelay, 0.08)
	end)

	t.test("every ore names its pick, with Needs only when the player is short", function()
		for _, ore in ipairs(OreData.All()) do
			local spec = oreSpec(ore)
			local pickName = PickaxeData.NameForLevel(ore.hardness)
			local belowName, belowLine, below =
				HoverTag.Lines(spec, { hour = 12, loop = 2, pickLevel = ore.hardness - 1 })
			t.eq(belowName, ore.name)
			t.eq(below.needs, true)
			t.eq(belowLine, "Needs " .. pickName)
			t.eq(string.find(belowLine, "Tier", 1, true), nil)
			t.eq(string.find(belowLine, "$", 1, true), nil)
			t.eq(string.find(belowLine, "R$", 1, true), nil)
			local _, equalLine, equalStyle = HoverTag.Lines(spec, { hour = 12, loop = 2, pickLevel = ore.hardness })
			t.eq(equalStyle.needs, false)
			t.eq(equalLine, pickName)
			local _, aboveLine, aboveStyle = HoverTag.Lines(spec, { hour = 12, loop = 2, pickLevel = ore.hardness + 1 })
			t.eq(aboveStyle.needs, false)
			t.eq(aboveLine, pickName)
			t.eq(below.nameColor, ore.color)
		end
	end)

	t.test("the rock stores the level, and clearing it leaves nothing to aim at", function()
		local part = Instance.new("Part")
		local ore = OreData.Get("Iron")
		HoverTag.Mark(part, oreSpec(ore))
		t.eq(part:GetAttribute("HoverKind"), "Ore")
		t.eq(part:GetAttribute("HoverId"), "Iron")
		t.eq(part:GetAttribute("HoverNeed"), 2)
		t.eq(part:GetAttribute("HoverTier"), 1)
		t.eq(part:GetAttribute("HoverRobux"), nil)
		t.eq(HoverTag.SpecOf(part).need, 2)
		HoverTag.Clear(part)
		t.eq(HoverTag.SpecOf(part), nil)
		t.eq(HoverTag.Choose({ device = "mouse", now = 0, hit = nil }), nil)
	end)
end
