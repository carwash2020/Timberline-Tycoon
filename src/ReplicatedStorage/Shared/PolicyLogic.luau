--!strict
-- PolicyLogic: what Roblox's PolicyService says a player's region and age
-- allow, as pure rules. ServerScriptService/PolicyGate fetches the answer
-- (pcall'd, cached per player); this module turns it into decisions the
-- server (the purchase handler) and the client (the store) share.
--
-- Fail safe: a missing, partial or wrong-typed answer is the strictest one.
-- Paid random items are restricted unless Roblox said they are not; trading
-- is off unless Roblox said it is on; no external link is allowed unless
-- listed. A restriction only ever hides or refuses a *new* purchase: a
-- receipt for something already bought is always granted (Monetization).
--
-- The game sells no paid random item and no tradable item today (V1 has no
-- trading or gifting). The gates exist so the first one added is covered:
-- mark a StoreData entry `paidRandom = true` (or `tradable = true`) and it
-- is hidden and refused where the policy says so, with no other change.

local PolicyLogic = {}

export type Policy = {
	known: boolean, -- Roblox answered (false = the strict default)
	paidRandomRestricted: boolean, -- ArePaidRandomItemsRestricted
	tradingAllowed: boolean, -- IsPaidItemTradingAllowed
	externalLinks: { string }, -- AllowedExternalLinkReferences ("Discord", "YouTube", ...)
}

-- The attributes PolicyGate writes on the Player so the client can read them.
PolicyLogic.Attr = {
	known = "PolicyKnown",
	paidRandomRestricted = "PolicyPaidRandomRestricted",
	tradingAllowed = "PolicyTradingAllowed",
}

function PolicyLogic.Strict(): Policy
	return { known = false, paidRandomRestricted = true, tradingAllowed = false, externalLinks = {} }
end

-- A PolicyService answer (a table of fields) as a Policy. Anything that is
-- not exactly what Roblox documents keeps the strict value for that field.
function PolicyLogic.Normalize(info: unknown): Policy
	local policy = PolicyLogic.Strict()
	if type(info) ~= "table" then
		return policy
	end
	local raw = info :: { [string]: any }
	policy.known = true
	if raw.ArePaidRandomItemsRestricted == false then
		policy.paidRandomRestricted = false
	end
	if raw.IsPaidItemTradingAllowed == true then
		policy.tradingAllowed = true
	end
	if type(raw.AllowedExternalLinkReferences) == "table" then
		for _, name in ipairs(raw.AllowedExternalLinkReferences) do
			if type(name) == "string" and name ~= "" then
				table.insert(policy.externalLinks, name)
			end
		end
	end
	return policy
end

-- Why this item may not be offered to this player now, or nil if it may.
-- `item` is a StoreData pass or product (extra fields are optional).
function PolicyLogic.Restriction(policy: Policy, item: { [string]: any }): string?
	if item.paidRandom == true and policy.paidRandomRestricted then
		return "paidRandom"
	end
	if item.tradable == true and not policy.tradingAllowed then
		return "trading"
	end
	return nil
end

function PolicyLogic.Allows(policy: Policy, item: { [string]: any }): boolean
	return PolicyLogic.Restriction(policy, item) == nil
end

-- `entries` (StoreData.Ordered rows) the player may be offered.
function PolicyLogic.Filter<T>(policy: Policy, entries: { T }): { T }
	local out: { T } = {}
	for _, entry in ipairs(entries) do
		local item = (entry :: any).item
		if type(item) ~= "table" or PolicyLogic.Allows(policy, item) then
			table.insert(out, entry)
		end
	end
	return out
end

-- Whether a link to `name` ("Discord") may be shown to this player.
function PolicyLogic.LinkAllowed(policy: Policy, name: string): boolean
	return table.find(policy.externalLinks, name) ~= nil
end

-- The toast for a refused purchase.
PolicyLogic.Refusal = "That item isn't available in your region."

-- A Policy from the attributes on a Player (client side). A missing
-- attribute is the strict value, so nothing restricted flashes up first.
function PolicyLogic.FromAttributes(get: (string) -> unknown): Policy
	local policy = PolicyLogic.Strict()
	if get(PolicyLogic.Attr.known) ~= true then
		return policy
	end
	policy.known = true
	policy.paidRandomRestricted = get(PolicyLogic.Attr.paidRandomRestricted) ~= false
	policy.tradingAllowed = get(PolicyLogic.Attr.tradingAllowed) == true
	return policy
end

return PolicyLogic
