--!strict
-- StoreModelSlots: ONE model slot per store item. The same slot draws the item
-- in the shop box (display and the carried box), in your hand, and placed on
-- your plot, so a model is wired once and every path picks it up.
--
-- Pure data and pure functions (no engine calls), so it is unit-tested and the
-- preview tooling reads it. The engine side (MeshKit, welds) is
-- Art/StoreModelArt.
--
-- A slot names a GLB in the repo and, per piece, a Roblox mesh id. A piece
-- with `meshId = 0` is NOT UPLOADED yet: nothing is asked of Roblox, nothing
-- errors, and the item keeps its part-built look (ItemModel, BlueprintModels,
-- MachineArt). When Connor uploads a GLB he pastes its id over the 0 in the
-- `meshId = 0` of that item's row below, and nothing else changes (STATUS.md,
-- "Store item models", has the steps; ASSETS.md lists every slot). Slots over models that were uploaded earlier (the gear, the lamp
-- post) do not repeat their ids: they read them from BacklogModels /
-- ItemMeshData, the one place each id is written.
--
-- Orientation and size. Every GLB is Y-up with its feet on y = 0. A slot
-- stands the model on the ground at the middle of its footprint (the
-- "frame"), turned `yaw` degrees about Y, and scales it uniformly so it fits
-- `fit`, the item's own part-built size in studs (never stretched). The
-- display fits the same box inside the part-built extent as well, so a shelf
-- box never changes size when a mesh lands (BoxSize reads the part build).
--
-- The Parcel slot is the fallback: an item with no slot of its own and no
-- part-built model of its own shows the generic gift parcel (Resolve).

local BacklogModels = require(script.Parent.Art.BacklogModels)
local ItemMeshData = require(script.Parent.ItemMeshData)

local StoreModelSlots = {}

export type Piece = {
	name: string, -- the mesh part's name, also the GLB node's name
	meshId: number, -- 0 = not uploaded: the part-built look stays
	textureId: number, -- 0 = none (a vertex-coloured mesh); an image id for a textured GLB
	size: Vector3, -- the mesh's own size in studs (the GLB bounding box), unscaled
	centre: Vector3, -- the middle of that box in the GLB's own space (origin = the model's origin)
}

export type Slot = {
	id: string, -- also the GLB's name
	items: { string }, -- the item ids this slot draws
	kinds: { string }, -- item kinds that use it whatever their id (the Robux box)
	glb: string, -- repo path of the source GLB, for the preview tooling and ASSETS.md
	source: string, -- "store-items" (the new GLBs), "backlog" (BacklogModels) or "items" (ItemMeshData)
	fit: Vector3, -- the item's part-built size in studs: the model is scaled to fit this
	yaw: number, -- degrees about Y (0, 90, 180 or 270) so the model lies the way the item does
	fallback: boolean, -- the generic parcel
	pieces: { Piece },
}

local V = Vector3.new

local function digits(uri: string): number
	return tonumber(string.match(uri, "%d+")) or 0
end

-- A piece of an asset BacklogModels already holds (the id is read, not copied).
local function backlog(asset: string, name: string, centre: Vector3): Piece
	local row = BacklogModels.Get(asset)
	assert(row ~= nil, "no BacklogModels asset " .. asset)
	for _, piece in ipairs(row.pieces) do
		if piece.name == name then
			return { name = name, meshId = piece.meshId, textureId = 0, size = piece.size, centre = centre }
		end
	end
	error("no piece " .. name .. " in " .. asset)
end

-- A piece of a plot item ItemMeshData already holds.
local function itemMesh(item: string, name: string, centre: Vector3): Piece
	for _, def in ipairs(ItemMeshData.List(item)) do
		if def.name == name then
			return { name = name, meshId = digits(def.meshId), textureId = 0, size = def.size, centre = centre }
		end
	end
	error("no piece " .. name .. " in " .. item)
end

local STORE = "assets/glb/store-items/"

-- Sizes and centres below are each GLB's own bounding box (tests/StoreModelSlots.spec
-- reads the files and checks them).
local ALL: { Slot } = {
	{
		id = "Barrel",
		items = { "Barrel" },
		kinds = {},
		glb = STORE .. "Barrel.glb",
		source = "store-items",
		fit = V(1.75, 2.2, 1.75), -- DecorData Barrel: 1.6 x 2.2 body, 1.75 hoop
		yaw = 0,
		fallback = false,
		pieces = { { name = "Barrel", meshId = 0, textureId = 0, size = V(2.19, 3.26, 2.19), centre = V(0, 1.63, 0) } },
	},
	{
		id = "Crate",
		items = { "Crate" },
		kinds = {},
		glb = STORE .. "Crate.glb",
		source = "store-items",
		fit = V(2, 2, 2), -- DecorData Crate: 1.8 body, 2 wide lid, 2 high
		yaw = 0,
		fallback = false,
		pieces = { { name = "Crate", meshId = 0, textureId = 0, size = V(2.6, 2.5, 2.6), centre = V(0, 1.25, 0) } },
	},
	{
		id = "GlowWire",
		items = { "GlowWire" },
		kinds = {},
		glb = STORE .. "GlowWire.glb",
		source = "store-items",
		fit = V(4, 1.3, 2), -- LogicItems GlowWire's footprint, 4 x 2 (the part build is a 3.7 stud bar on two posts)
		yaw = 90, -- the GLB is a wire spool on its side with its tail along Z: turned so the discs face the front and the tail runs along the 4 stud side
		fallback = false,
		pieces = {
			{ name = "GlowWire", meshId = 0, textureId = 0, size = V(1.02, 1.3, 2.16), centre = V(0.02, 0.65, 0.43) },
		},
	},
	{
		id = "SkyBin",
		items = { "SkyBin" },
		kinds = {},
		glb = STORE .. "SkyBin.glb",
		source = "store-items",
		fit = V(4, 4, 4), -- BuildingArt.SkyBin's "SkyBin" part, 4 x 4 x 4 (the flume and cloud are not in the GLB)
		yaw = 0,
		fallback = false,
		pieces = { { name = "SkyBin", meshId = 0, textureId = 0, size = V(3.82, 3.36, 3.82), centre = V(0, 1.68, 0) } },
	},
	{
		id = "RobuxCoins",
		items = {},
		kinds = { "Robux" },
		glb = STORE .. "RobuxCoins.glb",
		source = "store-items",
		fit = V(2.3, 0.8, 2.3), -- the pile over the Robux crate's floor (RobuxBoxArt)
		yaw = 0,
		fallback = false,
		pieces = {
			{
				name = "RobuxCoins",
				meshId = 0,
				textureId = 0,
				size = V(2.709, 0.782, 2.51),
				centre = V(0.6755, 0.391, 0.375),
			},
		},
	},
	{
		id = "Parcel",
		items = {},
		kinds = {},
		glb = STORE .. "Parcel.glb",
		source = "store-items",
		fit = V(1.4, 1.6, 1.4), -- ItemModel's part-built parcel: 1.4 box, 1.6 with the bow
		yaw = 0,
		fallback = true,
		pieces = {
			{ name = "Parcel", meshId = 0, textureId = 0, size = V(1.44, 1.57, 1.45), centre = V(0, 0.785, 0.005) },
		},
	},
	-- Models uploaded earlier (the ids live in BacklogModels / ItemMeshData). Gear is
	-- shown in the box only: nothing in the game wears or holds it.
	{
		id = "InsulatedCoat",
		items = { "InsulatedCoat" },
		kinds = {},
		glb = "assets/glb/backlog/gear/InsulatedCoat/InsulatedCoat.glb",
		source = "backlog",
		fit = V(2.5, 1.9, 1.0), -- ItemModel's part-built coat
		yaw = 0,
		fallback = false,
		pieces = { backlog("InsulatedCoat", "Body", V(0, 1.75, -0.0125)) },
	},
	{
		id = "HeatBoots",
		items = { "HeatBoots" },
		kinds = {},
		glb = "assets/glb/backlog/gear/HeatBoots/HeatBoots.glb",
		source = "backlog",
		fit = V(2.05, 1.4, 1.5), -- ItemModel's part-built pair
		yaw = 0,
		fallback = false,
		pieces = {
			backlog("HeatBoots", "Body", V(0, 0.935, -0.15)),
			backlog("HeatBoots", "Glow", V(0, 0.05, -0.5)),
		},
	},
	{
		id = "FeatherfallCloak",
		items = { "FeatherfallCloak" },
		kinds = {},
		glb = "assets/glb/backlog/gear/FeatherfallCloak/FeatherfallCloak.glb",
		source = "backlog",
		fit = V(2.0, 2.25, 0.7), -- ItemModel's part-built cloak
		yaw = 0,
		fallback = false,
		pieces = {
			backlog("FeatherfallCloak", "Body", V(0, 1.524, 0.09)),
			backlog("FeatherfallCloak", "Glow", V(0, 2.5, -0.5)),
		},
	},
	{
		-- The store's lamp post is the PLOT item's mesh (assets/meshes/items/LampPost,
		-- 1.25 x 8.4: the lamp you buy and place), not environment/LampPost, the 10.6 stud
		-- street lamp with its arm that is town scenery. ItemMeshData already places it.
		id = "LampPost",
		items = { "LampPost" },
		kinds = {},
		glb = "assets/meshes/items/LampPost/LampPost.glb",
		source = "items",
		fit = V(1.25, 8.425, 1.25),
		yaw = 0,
		fallback = false,
		pieces = {
			itemMesh("LampPost", "Body", V(0, 4.2125, 0)),
			itemMesh("LampPost", "Glow", V(0, 7.4, 0)),
		},
	},
}

local BY_ID: { [string]: Slot } = {}
local BY_ITEM: { [string]: Slot } = {}
local BY_KIND: { [string]: Slot } = {}
local PARCEL: Slot? = nil
for _, slot in ipairs(ALL) do
	assert(BY_ID[slot.id] == nil, "duplicate slot " .. slot.id)
	BY_ID[slot.id] = slot
	for _, item in ipairs(slot.items) do
		assert(BY_ITEM[item] == nil, "two slots for item " .. item)
		BY_ITEM[item] = slot
	end
	for _, kind in ipairs(slot.kinds) do
		BY_KIND[kind] = slot
	end
	if slot.fallback then
		PARCEL = slot
	end
end

StoreModelSlots.All = ALL

-- Preview tooling only (tools/preview/export.luau): a piece with no uploaded id
-- gets a made-up one here, keyed "<slot>/<piece>", and the export registers the
-- GLB under it so renders show the real model. nil in the game, where an unset
-- id stays unset.
StoreModelSlots.PreviewIds = nil :: { [string]: number }?

function StoreModelSlots.Get(id: string): Slot?
	return BY_ID[id]
end

-- The slot that draws `itemId` (and the kinds that use one whatever the id),
-- or nil: the item has no model of its own.
function StoreModelSlots.ForItem(itemId: string?, kind: string?): Slot?
	if itemId ~= nil and itemId ~= "" and BY_ITEM[itemId] ~= nil then
		return BY_ITEM[itemId]
	end
	if kind ~= nil then
		return BY_KIND[kind]
	end
	return nil
end

function StoreModelSlots.Parcel(): Slot
	return PARCEL :: Slot
end

-- THE fallback rule: the item's slot, else the Parcel. Returns (slot, usedParcel).
-- The part-built look is a separate, last step: a slot whose pieces are not
-- uploaded draws nothing and the caller keeps its parts (see HasMesh).
function StoreModelSlots.Resolve(itemId: string?, kind: string?): (Slot, boolean)
	local own = StoreModelSlots.ForItem(itemId, kind)
	if own ~= nil then
		return own, false
	end
	return PARCEL :: Slot, true
end

-- The mesh id a piece loads: its own, or (previews only) the made-up one. 0 = none.
function StoreModelSlots.MeshIdOf(slot: Slot, piece: Piece): number
	if piece.meshId ~= 0 then
		return piece.meshId
	end
	local preview = StoreModelSlots.PreviewIds
	if preview ~= nil then
		return preview[slot.id .. "/" .. piece.name] or 0
	end
	return 0
end

-- True when every piece has an id to load (uploaded, or made up for a preview).
function StoreModelSlots.HasMesh(slot: Slot): boolean
	for _, piece in ipairs(slot.pieces) do
		if StoreModelSlots.MeshIdOf(slot, piece) == 0 then
			return false
		end
	end
	return #slot.pieces > 0
end

-- True when the slot's pieces are all uploaded for real (ids, not previews).
function StoreModelSlots.IsUploaded(slot: Slot): boolean
	for _, piece in ipairs(slot.pieces) do
		if piece.meshId == 0 then
			return false
		end
	end
	return #slot.pieces > 0
end

-- The ids MeshManifest preloads: only real, uploaded ids.
function StoreModelSlots.MeshIds(): { number }
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, slot in ipairs(ALL) do
		for _, piece in ipairs(slot.pieces) do
			if piece.meshId ~= 0 and not seen[piece.meshId] then
				seen[piece.meshId] = true
				table.insert(out, piece.meshId)
			end
		end
	end
	return out
end

-- Rotates a vector about Y by 0, 90, 180 or 270 degrees.
local function turn(v: Vector3, yaw: number): Vector3
	local q = math.floor(yaw / 90 + 0.5) % 4
	if q == 1 then
		return V(v.Z, v.Y, -v.X)
	elseif q == 2 then
		return V(-v.X, v.Y, -v.Z)
	elseif q == 3 then
		return V(-v.Z, v.Y, v.X)
	end
	return v
end

export type PieceLayout = {
	name: string,
	size: Vector3, -- scaled, in the GLB's own axes (the part is turned by `yaw`)
	offset: Vector3, -- the piece's middle, in the frame (feet middle of the whole model)
	origin: Vector3, -- the GLB's origin in the frame (for a mesh whose pivot is authored)
}

export type Layout = {
	scale: number,
	size: Vector3, -- the whole model as placed (after yaw and scale)
	yaw: number, -- radians
	pieces: { PieceLayout },
}

-- Where each piece goes. The frame is the middle of the model's feet. `limit` is
-- an extra box the model must fit (the display's part-built extent); the scale
-- is the largest that fits both it and the slot's own `fit`.
function StoreModelSlots.Layout(slot: Slot, limit: Vector3?): Layout
	local lo: Vector3? = nil
	local hi: Vector3? = nil
	for _, piece in ipairs(slot.pieces) do
		local h = piece.size / 2
		local a, b = piece.centre - h, piece.centre + h
		lo = if lo then lo:Min(a) else a
		hi = if hi then hi:Max(b) else b
	end
	local low, high = lo :: Vector3, hi :: Vector3
	local whole = high - low
	local turned = turn(whole, slot.yaw)
	local size = V(math.abs(turned.X), math.abs(turned.Y), math.abs(turned.Z))
	local box = slot.fit
	if limit then
		box = box:Min(limit)
	end
	local scale = math.min(box.X / size.X, box.Y / size.Y, box.Z / size.Z)
	local base = V((low.X + high.X) / 2, low.Y, (low.Z + high.Z) / 2)
	local pieces: { PieceLayout } = {}
	for _, piece in ipairs(slot.pieces) do
		table.insert(pieces, {
			name = piece.name,
			size = piece.size * scale,
			offset = turn(piece.centre - base, slot.yaw) * scale,
			origin = turn(-base, slot.yaw) * scale,
		})
	end
	return { scale = scale, size = size * scale, yaw = math.rad(slot.yaw), pieces = pieces }
end

return StoreModelSlots
