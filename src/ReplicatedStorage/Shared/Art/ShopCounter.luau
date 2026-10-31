--!strict
-- ShopCounter: the honey nosing on a timber counter. The Counter part stays
-- a direct child (ShopService finds it there). MeshId 0; this trim is the
-- on-style fallback until the shopfit mesh is uploaded.

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local ShopCounter = {}

function ShopCounter.Add(parent: Instance, counter: BasePart): Model
	local model = Kit.model("ShopCounter", parent)
	model:SetAttribute("MeshId", 0)
	local size = counter.Size
	-- Proud of the customer face (-Z) and below the top plane, so it does
	-- not share a face with the counter.
	Kit.decor(
		Kit.part(
			model,
			"CounterNosing",
			Vector3.new(size.X * 0.92, 0.1, 0.12),
			counter.CFrame * CFrame.new(0, size.Y / 2 - 0.08, -size.Z / 2 - 0.12),
			Palette.PlankHoney,
			Enum.Material.WoodPlanks
		),
		false
	)
	return model
end

return ShopCounter
