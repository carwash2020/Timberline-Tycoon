--!strict
-- ProductInfo: the one wrapper round Roblox's product lookup.
-- GetProductInfoAsync is the current method; GetProductInfo (deprecated)
-- is the fallback for clients that don't have it yet. Errors propagate
-- (callers pcall and retry). `market` is MarketplaceService, or a stand-in
-- in tests.

local ProductInfo = {}

function ProductInfo.Get(market: any, id: number, kind: string): any
	local infoType = if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
	local hasAsync = false
	pcall(function()
		hasAsync = type(market.GetProductInfoAsync) == "function"
	end)
	if hasAsync then
		return market:GetProductInfoAsync(id, infoType)
	end
	return market:GetProductInfo(id, infoType)
end

-- Tries up to `tries` times, waiting 2 s, 4 s, 8 s between. Returns the
-- info table or nil. `wait` is task.wait (tests pass a stub).
function ProductInfo.Fetch(market: any, id: number, kind: string, tries: number, wait: (number) -> ()): any
	for attempt = 1, tries do
		local ok, info = pcall(ProductInfo.Get, market, id, kind)
		if ok and type(info) == "table" then
			return info
		end
		if attempt < tries then
			wait(2 ^ attempt)
		end
	end
	return nil
end

return ProductInfo
