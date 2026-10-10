--!strict
-- RobuxTableArt: the Tool Shed's Robux table (Lane P). A TimberBrown table
-- along the back wall with a brass edge, a riser behind its top for the
-- second row of gold crates (RobuxShelf.Placements), and a PineTrim board
-- across the front reading the store's name in cream (the bulletin board's
-- look). No price anywhere. Seven parts; only the table top and riser are
-- solid (the crates stand on them).

local Kit = require(script.Parent.Kit)
local RobuxShelf = require(script.Parent.Parent.RobuxShelf)
local StoreCopy = require(script.Parent.Parent.Store.StoreCopy)

local RobuxTableArt = {}

RobuxTableArt.TimberBrown = Color3.fromHex("#7A5230")
RobuxTableArt.TopWood = Color3.fromHex("#9A6A3E")
RobuxTableArt.Brass = Color3.fromHex("#C9A24A")
RobuxTableArt.PineTrim = Color3.fromHex("#2F5D3A")
RobuxTableArt.SignCream = Color3.fromHex("#F3E7C9")
RobuxTableArt.Parts = 7

-- Builds the table into `model`. `floorTop` is the shop floor's top (final
-- studs). Nothing when nothing has an id.
function RobuxTableArt.Build(model: Model, floorTop: number)
	if #RobuxShelf.List() == 0 then
		return
	end
	local width = RobuxShelf.RowWidth()
	local cz = RobuxShelf.TableZ
	local depth = RobuxShelf.TableDepth
	local top = RobuxShelf.TableTop
	local slab = 0.3
	local bodyH = top - slab - floorTop
	local body = Kit.part(
		model,
		"GoldTable",
		Vector3.new(width - 0.4, bodyH, depth - 0.4),
		CFrame.new(0, floorTop + bodyH / 2, cz),
		RobuxTableArt.TimberBrown,
		Enum.Material.Wood
	)
	body.CanCollide = true
	local slabPart = Kit.part(
		model,
		"GoldTableTop",
		Vector3.new(width, slab, depth),
		CFrame.new(0, top - slab / 2, cz),
		RobuxTableArt.TopWood,
		Enum.Material.WoodPlanks
	)
	slabPart.CanCollide = true
	local edge = Kit.part(
		model,
		"GoldTableEdge",
		Vector3.new(width + 0.06, 0.12, depth + 0.06),
		CFrame.new(0, top - slab - 0.06, cz),
		RobuxTableArt.Brass,
		Enum.Material.Metal
	)
	Kit.decor(edge, false)
	local riserD = depth / 2 -- the back half: the back row stands on it
	local riser = Kit.part(
		model,
		"GoldRiser",
		Vector3.new(width - 0.2, RobuxShelf.RiserH, riserD),
		CFrame.new(0, top + RobuxShelf.RiserH / 2, cz + depth / 2 - riserD / 2),
		RobuxTableArt.TopWood,
		Enum.Material.WoodPlanks
	)
	riser.CanCollide = true
	local riserEdge = Kit.part(
		model,
		"GoldRiserEdge",
		Vector3.new(width - 0.14, 0.1, 0.1),
		CFrame.new(0, top + RobuxShelf.RiserH - 0.05, cz + depth / 2 - riserD + 0.05),
		RobuxTableArt.Brass,
		Enum.Material.Metal
	)
	Kit.decor(riserEdge, false)
	-- The name on a board across the table's front (a hanging sign here
	-- would hide the axes on the rack behind).
	local board = Kit.part(
		model,
		"RobuxSign",
		Vector3.new(math.max(8.4, width - 1), 1.1, 0.12),
		CFrame.new(0, top - 0.95, cz - depth / 2 - 0.08),
		RobuxTableArt.PineTrim,
		Enum.Material.WoodPlanks
	)
	Kit.decor(board, false)
	Kit.signText(board, StoreCopy.Title, RobuxTableArt.SignCream, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
	local trim = Kit.part(
		model,
		"RobuxSignTrim",
		Vector3.new(math.max(8.4, width - 1) + 0.2, 0.12, 0.16),
		CFrame.new(0, top - 0.95 + 0.6, cz - depth / 2 - 0.08),
		RobuxTableArt.Brass,
		Enum.Material.Metal
	)
	Kit.decor(trim, false)
end

return RobuxTableArt
