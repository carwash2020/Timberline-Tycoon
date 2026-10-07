--!strict
-- PaidItems: every item sold for Robux, as one list the owner hub can give
-- and take back. The list is BUILT from Shared/StoreData (the same passes and
-- products the Robux store and MonetizationService use), never typed twice:
-- add a pass or a product to StoreData and it shows up in the owner's Paid
-- items tab with its name, kind and how it is granted. Pure, so it is tested
-- (tests/PaidItems.spec); MonetizationService does the granting (OwnerGrant,
-- OwnerRevoke) through the same effect rules a real purchase uses.
--
-- Kinds (what the owner sees):
--   pass        a permanent pass (2x Cash, Tow Service, ...)
--   tool        a permanent pass that is an axe (Lux Axe)
--   cosmetic    a permanent pass that is only looks (Paint Shop)
--   consumable  a one-off (a cash pack, Instant Delivery)
--   booster     a timed boost (2x Wood)
-- A StoreData entry may say `kind` itself; otherwise it is worked out:
-- a pass whose key is an axe is a tool, any other pass is a pass, a product
-- with `boostHours` is a booster, any other product is a consumable.
--
-- Effects (EffectOf), shared with MonetizationService.grantProduct so a
-- grant and a purchase can never drift apart:
--   pass     switches the pass on (a grant is saved apart, in ownerGrants)
--   cash     adds `cash` to the wallet
--   boost    runs a timed boost for `boostHours`
--   counter  adds one Instant Delivery use
--   none     the store sells it but the game has no effect for it yet

local ItemCatalog = require(script.Parent.ItemCatalog)
local StoreData = require(script.Parent.StoreData)

local PaidItems = {}

-- Kind: "pass", "tool", "cosmetic", "consumable" or "booster". Effect: "pass",
-- "cash", "boost", "counter" or "none" (plain strings: the UI and the specs compare them).
export type Kind = string
export type Effect = string

export type Item = {
	id: string, -- "pass_LuxAxe" / "product_Cash1k": letters, digits, underscore
	source: string, -- "Pass" or "Product"
	key: string, -- the StoreData key
	name: string,
	description: string,
	kind: Kind,
	effect: Effect,
	revocable: boolean,
	forSale: boolean, -- the Creator Hub id is pasted (a grant works either way)
	cash: number?,
	hours: number?, -- boosters: the length a purchase gives, the default for a grant
	how: string, -- how it is granted, in plain words
	revokeHow: string, -- what revoking does (or why it can't)
}

PaidItems.KindLabels = {
	pass = "Permanent pass",
	tool = "Tool / axe",
	cosmetic = "Cosmetic",
	consumable = "Consumable",
	booster = "Timed booster",
} :: { [string]: string }

-- Boost lengths the hub offers for a grant, in hours; the server takes any
-- whole number from 1 to MaxHours.
PaidItems.HourChoices = { 1, 24, 48, 168 } :: { number }
PaidItems.MaxHours = 720

-- The saved log of owner grants and revokes keeps this many entries.
PaidItems.LogCap = 30
-- The same grant for the same item inside this many seconds is a double press.
PaidItems.RepeatSeconds = 3

local KINDS: { [string]: boolean } = { pass = true, tool = true, cosmetic = true, consumable = true, booster = true }

function PaidItems.Id(source: string, key: string): string
	return string.lower(source) .. "_" .. key
end

-- What a developer product does when it is granted. One rule for the
-- purchase and the owner's grant.
function PaidItems.EffectOf(product: StoreData.Product): Effect
	if product.cash then
		return "cash"
	elseif product.boostHours then
		return "boost"
	elseif product.key == "InstantDelivery" then
		return "counter"
	end
	return "none"
end

local function kindOf(declared: unknown, fallback: Kind): Kind
	if type(declared) == "string" and KINDS[declared] then
		return declared
	end
	return fallback
end

local function fmtCash(n: number): string
	local out = tostring(math.floor(n))
	while true do
		local replaced, count = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then
			break
		end
	end
	return "$" .. out
end

local function passItem(pass: StoreData.Pass): Item
	local isAxe = ItemCatalog.GetAxe(pass.key) ~= nil
	local kind = kindOf((pass :: any).kind, if isAxe then "tool" else "pass")
	local revocable = (pass :: any).revocable ~= false
	local how =
		"Switched on at once, the way a real purchase does it, and kept after they rejoin. Saved as an owner grant, so a revoke never touches a purchase."
	if isAxe then
		how =
			"The axe is added to their axes (one copy, like the pass) and kept after they rejoin. Saved as an owner grant."
	end
	local revokeHow = "Can't be taken back: it already changed their save."
	if revocable then
		revokeHow = if isAxe
			then "Takes the owner-granted pass and its axe away. A pass they bought stays."
			else "Takes the owner-granted pass away. A pass they bought stays."
	end
	return {
		id = PaidItems.Id("Pass", pass.key),
		source = "Pass",
		key = pass.key,
		name = pass.name,
		description = pass.description,
		kind = kind,
		effect = "pass",
		revocable = revocable,
		forSale = StoreData.IsForSale(pass.id),
		how = how,
		revokeHow = revokeHow,
	}
end

local function productItem(product: StoreData.Product): Item
	local effect = PaidItems.EffectOf(product)
	local how = "The store sells it but the game has no effect for it yet, so it can't be given."
	local revokeHow = "Nothing to take back."
	local revocable = false
	local fallback: Kind = "consumable"
	if effect == "cash" then
		how = string.format("Adds %s to their wallet. Needs room under the wallet cap.", fmtCash(product.cash or 0))
		revokeHow = "Cash isn't taken back here. Use TAKE CASH on the Gifts tab."
	elseif effect == "boost" then
		fallback = "booster"
		how = string.format(
			"Starts the boost for the hours you pick (a purchase gives %d). Refused while one is running.",
			product.boostHours or 0
		)
		revokeHow = "Ends the boost now, whoever it came from."
		revocable = true
	elseif effect == "counter" then
		how = "Adds one use. Refused while they still hold one."
		revokeHow = "Takes one use away."
		revocable = true
	end
	return {
		id = PaidItems.Id("Product", product.key),
		source = "Product",
		key = product.key,
		name = product.name,
		description = product.description,
		kind = kindOf((product :: any).kind, fallback),
		effect = effect,
		revocable = revocable,
		forSale = StoreData.IsForSale(product.id),
		cash = product.cash,
		hours = product.boostHours,
		how = how,
		revokeHow = revokeHow,
	}
end

-- The list for a store (StoreData, or a stand-in in a test). Passes first,
-- then products, each in store order. Rebuilt on every call: nothing is
-- cached, so an item added to the store data is in the next list.
function PaidItems.Build(store: { Passes: { StoreData.Pass }, Products: { StoreData.Product } }): { Item }
	local out: { Item } = {}
	for _, pass in ipairs(store.Passes) do
		table.insert(out, passItem(pass))
	end
	for _, product in ipairs(store.Products) do
		table.insert(out, productItem(product))
	end
	return out
end

function PaidItems.All(): { Item }
	return PaidItems.Build(StoreData)
end

function PaidItems.Find(list: { Item }, id: unknown): Item?
	if type(id) ~= "string" then
		return nil
	end
	for _, item in ipairs(list) do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Search: every word typed must be in the name, kind or id.
function PaidItems.Filter(list: { Item }, query: unknown): { Item }
	local words: { string } = {}
	if type(query) == "string" then
		for w in string.gmatch(string.lower(query), "%S+") do
			table.insert(words, w)
		end
	end
	local out: { Item } = {}
	for _, item in ipairs(list) do
		local hay = string.lower(item.name .. " " .. (PaidItems.KindLabels[item.kind] or item.kind) .. " " .. item.id)
		local all = true
		for _, w in ipairs(words) do
			if not string.find(hay, w, 1, true) then
				all = false
				break
			end
		end
		if all then
			table.insert(out, item)
		end
	end
	return out
end

-- A boost length in hours: nil gives the item's own, else a whole number from
-- 1 to MaxHours. Returns the hours, or nil for anything else.
function PaidItems.CleanHours(item: Item, hours: unknown): number?
	if hours == nil then
		return item.hours
	end
	if type(hours) ~= "number" or hours ~= hours or hours % 1 ~= 0 or hours < 1 or hours > PaidItems.MaxHours then
		return nil
	end
	return hours
end

---------------------------------------------------------------------------
-- What a player owns of an item, and what may be done about it
---------------------------------------------------------------------------

export type State = {
	owned: boolean,
	bought: boolean, -- it came from a purchase (or Roblox says they own the pass)
	granted: boolean, -- an owner grant is on it
	count: number, -- counters: uses left
	untilAt: number, -- boosters: unix time it ends (0 = none)
	label: string, -- "OWNED (granted)", "ACTIVE (47 h left)", ...
}

local function hoursLeft(untilAt: number, now: number): string
	return string.format("%d h left", math.ceil(math.max(0, untilAt - now) / 3600))
end

-- `live` is whether the running server believes they own the pass (a
-- confirmed purchase or a grant switched on this session).
function PaidItems.StateOf(item: Item, profile: any, live: boolean, now: number): State
	local st: State = { owned = false, bought = false, granted = false, count = 0, untilAt = 0, label = "" }
	local isTable = type(profile) == "table"
	local passes = if isTable and type(profile.passes) == "table" then profile.passes else {}
	local grants = if isTable and type(profile.ownerGrants) == "table" then profile.ownerGrants else {}
	if item.effect == "pass" then
		st.granted = grants[item.key] ~= nil
		st.bought = passes[item.key] == true or (live and not st.granted)
		st.owned = st.bought or st.granted
		if st.bought and st.granted then
			st.label = "OWNED (bought and granted)"
		elseif st.bought then
			st.label = "OWNED (bought)"
		elseif st.granted then
			st.label = "OWNED (granted)"
		else
			st.label = "NOT OWNED"
		end
	elseif item.effect == "boost" then
		local untilAt = if isTable and type(profile.doubleWoodUntil) == "number" then profile.doubleWoodUntil else 0
		st.untilAt = untilAt
		st.owned = untilAt > now
		st.label = if st.owned then "ACTIVE (" .. hoursLeft(untilAt, now) .. ")" else "NOT RUNNING"
	elseif item.effect == "counter" then
		local n = if isTable and type(profile.instantDeliveries) == "number" then profile.instantDeliveries else 0
		st.count = n
		st.owned = n > 0
		st.label = if n > 0 then string.format("HAS %d", n) else "NONE LEFT"
	end
	return st
end

export type Wallet = { cash: number, cap: number }

-- (true, nil) or (false, why) for giving `item` to a player in state `st`.
function PaidItems.CanGrant(item: Item, st: State, wallet: Wallet?): (boolean, string?)
	if item.effect == "none" then
		return false, item.name .. " has no effect in the game yet, so it can't be given."
	elseif item.effect == "pass" then
		if st.granted then
			return false, "They already have " .. item.name .. " from an owner grant."
		elseif st.bought then
			return false, "They already own " .. item.name .. "."
		end
	elseif item.effect == "cash" then
		if wallet and wallet.cash + (item.cash or 0) > wallet.cap then
			return false, "Their wallet can't hold that much (the cap is " .. fmtCash(wallet.cap) .. ")."
		end
	elseif item.effect == "boost" then
		if st.owned then
			return false, item.name .. " is already running (" .. string.lower(st.label) .. ")."
		end
	elseif item.effect == "counter" then
		if st.count > 0 then
			return false, "They still have " .. item.name .. " to use."
		end
	end
	return true, nil
end

function PaidItems.CanRevoke(item: Item, st: State): (boolean, string?)
	if item.effect == "none" then
		return false, "Nothing to take back."
	elseif item.effect == "cash" then
		return false, item.revokeHow
	elseif not item.revocable then
		return false, item.name .. " can't be taken back: it already changed their save."
	elseif item.effect == "pass" then
		if not st.granted then
			if st.bought then
				return false, "They own " .. item.name .. " from a purchase. Only an owner grant can be revoked."
			end
			return false, "They don't have " .. item.name .. "."
		end
	elseif item.effect == "boost" then
		if not st.owned then
			return false, item.name .. " isn't running."
		end
	elseif item.effect == "counter" then
		if st.count <= 0 then
			return false, "They have no " .. item.name .. " left."
		end
	end
	return true, nil
end

---------------------------------------------------------------------------
-- The saved record (profile.ownerGrants, profile.ownerGrantLog)
---------------------------------------------------------------------------

export type Grant = { at: number, by: number, byName: string }
export type LogEntry = {
	at: number,
	by: number,
	byName: string,
	action: string, -- "give" or "revoke"
	item: string, -- PaidItems.Item.id
	name: string,
	detail: string?,
}

local function num(v: unknown): number?
	if type(v) == "number" and v == v and v > -math.huge and v < math.huge then
		return v
	end
	return nil
end

-- A save's ownerGrants cleaned: a table of pass key -> {at, by, byName}.
-- Anything malformed is dropped. Idempotent.
function PaidItems.CleanGrants(raw: unknown): { [string]: Grant }
	local out: { [string]: Grant } = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, g in pairs(raw :: { [unknown]: unknown }) do
		if type(key) == "string" and #key <= 40 and type(g) == "table" then
			local entry = g :: { [string]: unknown }
			local at, by = num(entry.at), num(entry.by)
			if at and by then
				local byName = if type(entry.byName) == "string" then string.sub(entry.byName, 1, 40) else ""
				out[key] = { at = at, by = by, byName = byName }
			end
		end
	end
	return out
end

-- A save's ownerGrantLog cleaned and trimmed to the newest LogCap entries.
function PaidItems.CleanLog(raw: unknown): { LogEntry }
	local out: { LogEntry } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, e in ipairs(raw :: { unknown }) do
		if type(e) == "table" then
			local entry = e :: { [string]: unknown }
			local at, by = num(entry.at), num(entry.by)
			if at and by and type(entry.action) == "string" and type(entry.item) == "string" then
				table.insert(out, {
					at = at,
					by = by,
					byName = if type(entry.byName) == "string" then string.sub(entry.byName, 1, 40) else "",
					action = string.sub(entry.action, 1, 12),
					item = string.sub(entry.item, 1, 48),
					name = if type(entry.name) == "string" then string.sub(entry.name, 1, 60) else "",
					detail = if type(entry.detail) == "string" then string.sub(entry.detail, 1, 80) else nil,
				})
			end
		end
	end
	while #out > PaidItems.LogCap do
		table.remove(out, 1)
	end
	return out
end

-- Adds an entry (oldest first, newest last) and trims to LogCap.
function PaidItems.PushLog(list: { LogEntry }, entry: LogEntry)
	table.insert(list, entry)
	while #list > PaidItems.LogCap do
		table.remove(list, 1)
	end
end

-- Whether the newest log entry is this same action on this item moments ago.
function PaidItems.IsRepeat(list: { LogEntry }, action: string, itemId: string, now: number): boolean
	local last = list[#list]
	return last ~= nil
		and last.action == action
		and last.item == itemId
		and now - last.at >= 0
		and now - last.at < PaidItems.RepeatSeconds
end

-- Whether a profile carries an owner grant for a pass key (for the places
-- that read the save, not the live set).
function PaidItems.HasGrant(profile: any, key: string): boolean
	return type(profile) == "table" and type(profile.ownerGrants) == "table" and profile.ownerGrants[key] ~= nil
end

-- A pass the save knows: bought and confirmed, or granted by the owner.
function PaidItems.SaveHasPass(profile: any, key: string): boolean
	if type(profile) ~= "table" then
		return false
	end
	local passes = profile.passes
	return (type(passes) == "table" and passes[key] == true) or PaidItems.HasGrant(profile, key)
end

return PaidItems
