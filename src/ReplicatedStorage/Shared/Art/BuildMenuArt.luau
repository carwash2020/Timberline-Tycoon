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
	Wall4 = 92842358266440,
	Wall = 86550202777226,
	Wall12 = 108892390175386,
	TallWall4 = 118510627023228,
	TallWall8 = 139403394294140,
	HalfWall8 = 77705674414345,
	DoorWall8 = 139483815247517,
	WindowWall8 = 119580612467352,
	SandWall4 = 101540232796086,
	-- Floors
	Floor4 = 76806516513061,
	Floor = 75250800048919,
	Foundation8 = 119751956634108,
	SandFloor4 = 127151332175823,
	-- Doors
	Door = 129667061247803,
	Window = 79862725176572,
	SandArch8 = 106846463557323,
	-- Stairs
	Stairs = 129339358927246,
	Ramp8 = 120964721900413,
	-- Roofs
	FlatRoof8 = 134465310509336,
	SlopedRoof8 = 125670163927603,
	RoofCorner = 116794497037747,
	RoofRidge8 = 137796210136032,
	Beam8 = 101208648433783,
	-- Fences
	Fence = 103322964153573,
	FenceGate4 = 113058872060641,
	Railing8 = 125034478716312,
	Post = 139049659672272,
	-- Indoor
	Table = 99087401024844,
	Chair = 99371857814337,
	Bookshelf = 70989331700923,
	Rug = 70711995310942,
	Barrel = 71603683407649,
	Crate = 129449296785611,
	FirePit = 100509616365938,
	-- Decor
	Bench = 120497108828121,
	LampPost = 134098639266080,
	Mailbox = 117112872769349,
	Flag = 110363427357974,
	WoodSign = 117910836146163,
	FlowerBed = 117406104145018,
	LogPile = 85183453302861,
	PaintCan = 110156619881861,
	-- Houses
	Shed = 91958482001483,
	Cabin = 136128514682007,
	Warehouse = 132742643091735,
	AxeRack = 100484944176781,
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
