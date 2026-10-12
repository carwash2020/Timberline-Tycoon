--!strict
-- The picture URL for a store card's art disc.
--
-- StoreData keeps one number per card (`image`): a Roblox IMAGE asset id that
-- Connor uploaded. An ImageLabel loads an Image id through rbxassetid://, but
-- Roblox's asset thumbnail URL renders any image-like asset id (an Image or a
-- Decal), so every consumer (the store panel and the in-world board) goes
-- through here and nothing builds an rbxassetid:// for a store image.
--
-- Unverified without Roblox: that each of the nine ids renders the right
-- picture (the sandbox cannot reach Roblox). scripts/check-store-icons.ps1
-- checks the six newest on Connor's machine.

local StoreArt = {}

-- Thumbnail sizes Roblox serves for assets. Small cards use Small; the
-- big board disc uses Large.
StoreArt.Small = 150
StoreArt.Large = 420

-- "" for a 0 (or any non-positive, fractional or non-number) id, so the
-- caller keeps its letter or mark; otherwise the rbxthumb URL.
function StoreArt.ImageFor(id: number?, size: number?): string
	if type(id) ~= "number" or id ~= id or id < 1 or id % 1 ~= 0 then
		return ""
	end
	local px = size or StoreArt.Small
	return string.format("rbxthumb://type=Asset&id=%d&w=%d&h=%d", id, px, px)
end

return StoreArt
