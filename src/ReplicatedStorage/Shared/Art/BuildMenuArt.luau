--!strict
-- BuildMenuArt: the picture on each build-menu card. `Images[pieceId]` is a
-- Roblox Image id for that piece's render. The renders are transparent PNGs
-- in the handoff folder (handoff/ui-t309/mock/art/<PieceId>.png); they are
-- uploaded as Images (not models or decals) and the ids pasted here. An id of
-- 0, or an image that fails to load, shows the card's colour swatch instead
-- (the colour BuildMenuUI takes from the piece: no grey stand-in, no
-- placeholder text), so the menu works before any upload. Never invent an id.

local BuildMenuArt = {}

BuildMenuArt.Images = {
	-- Walls
	Wall4 = 0,
	Wall = 0,
	Wall12 = 0,
	TallWall4 = 0,
	TallWall8 = 0,
	HalfWall8 = 0,
	DoorWall8 = 0,
	WindowWall8 = 0,
	SandWall4 = 0,
	-- Floors
	Floor4 = 0,
	Floor = 0,
	Foundation8 = 0,
	SandFloor4 = 0,
	-- Doors
	Door = 0,
	Window = 0,
	SandArch8 = 0,
	-- Stairs
	Stairs = 0,
	Ramp8 = 0,
	-- Roofs
	FlatRoof8 = 0,
	SlopedRoof8 = 0,
	RoofCorner = 0,
	RoofRidge8 = 0,
	Beam8 = 0,
	-- Fences
	Fence = 0,
	FenceGate4 = 0,
	Railing8 = 0,
	Post = 0,
	-- Indoor
	Table = 0,
	Chair = 0,
	Bookshelf = 0,
	Rug = 0,
	Barrel = 0,
	Crate = 0,
	FirePit = 0,
	-- Decor
	Bench = 0,
	LampPost = 0,
	Mailbox = 0,
	Flag = 0,
	WoodSign = 0,
	FlowerBed = 0,
	LogPile = 0,
	PaintCan = 0,
	-- Houses
	Shed = 0,
	Cabin = 0,
	Warehouse = 0,
	AxeRack = 0,
} :: { [string]: number }

-- The id to draw for a piece, or nil while it is 0 (draw the swatch).
function BuildMenuArt.ImageFor(pieceId: string): number?
	local id = BuildMenuArt.Images[pieceId]
	if type(id) == "number" and id > 0 then
		return id
	end
	return nil
end

return BuildMenuArt
