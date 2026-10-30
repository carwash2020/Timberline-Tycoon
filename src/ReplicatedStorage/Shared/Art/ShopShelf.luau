--!strict
-- ShopShelf: a honey board stock sits on. MeshId 0 until the shopfit mesh
-- is uploaded; the board is the on-style fallback (PlankHoney, not a bare
-- block). `top` is the centre of the board's top face.

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local ShopShelf = {}

export type Seat = {
	x: number,
	z: number,
	size: Vector3,
	color: Color3,
	price: string,
}

function ShopShelf.Add(parent: Instance, top: CFrame, wide: number, deep: number): (Model, BasePart)
	local model = Kit.model("ShopShelf", parent)
	model:SetAttribute("MeshId", 0)
	local thick = 0.16
	local board = Kit.decor(
		Kit.part(
			model,
			"ShelfBoard",
			Vector3.new(wide, thick, deep),
			top * CFrame.new(0, -thick / 2, 0),
			Palette.PlankHoney,
			Enum.Material.WoodPlanks
		),
		false
	)
	return model, board
end

-- An item whose bottom is the board's top, and a cream tag with a gold price.
function ShopShelf.Seat(model: Model, board: BasePart, seat: Seat): BasePart
	local item = Kit.decor(
		Kit.part(
			model,
			"ShopItem",
			seat.size,
			board.CFrame * CFrame.new(seat.x, board.Size.Y / 2 + seat.size.Y / 2, seat.z),
			seat.color,
			Enum.Material.Wood
		),
		false
	)
	local tag = Kit.decor(
		Kit.part(
			model,
			"ShelfPrice",
			Vector3.new(math.min(seat.size.X + 0.15, 0.9), 0.28, 0.05),
			board.CFrame * CFrame.new(seat.x, board.Size.Y / 2 + 0.18, -board.Size.Z / 2 - 0.04),
			Palette.SignCream,
			Enum.Material.SmoothPlastic
		),
		false
	)
	Kit.signText(
		tag,
		seat.price,
		Palette.CoinGold,
		{ Enum.NormalId.Front, Enum.NormalId.Back },
		Enum.Font.GothamBold,
		0
	)
	return item
end

return ShopShelf
