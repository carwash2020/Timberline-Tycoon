--!strict
-- The picture URL for a store card's art disc.
--
-- StoreData keeps one number per card (`image`), pasted from the Creator
-- Dashboard, and it may be a Decal id or an Image id. An ImageLabel only
-- loads an Image id through rbxassetid://; a Decal id there shows nothing.
-- Roblox's asset thumbnail URL renders the picture for either, so every
-- consumer (the store panel and the in-world board) goes through here and
-- nothing builds an rbxassetid:// for a store image.
--
-- Unverified without Studio: that each of the three ids renders.

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
