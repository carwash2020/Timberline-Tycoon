--!strict
-- PermissionLogic: who may visit a plot and what they may do there.
-- The owner always may. Everyone else uses the "anyone" row, then a row
-- for their user id if the owner set one. Pure, so the server and the
-- Settings tab agree, and tests can run a refusal without DataStores.
--
-- "build" is place and move. It also allows destroy, so one tick covers
-- taking a piece apart. "destroy" on its own allows that and not building.
-- Collision groups are stored here; the wood system reads the flag later.

local PermissionLogic = {}

-- Phone toggles in the Settings tab are at least this tall.
PermissionLogic.Tap = 44

-- Named people besides "anyone". Open to tuning: a busy plot rarely
-- lists more than the people in the server.
PermissionLogic.MaxPeople = 24

PermissionLogic.Anyone = "anyone"

PermissionLogic.Flags = {
	"visit",
	"sit",
	"collisions",
	"build",
	"destroy",
	"grab",
	"interact",
	"drive",
	"saveItems",
}

PermissionLogic.Label = {
	visit = "Visit",
	sit = "Sit",
	collisions = "Collisions",
	build = "Build",
	destroy = "Destroy",
	grab = "Grab",
	interact = "Interact",
	drive = "Drive",
	saveItems = "Save items",
} :: { [string]: string }

local FLAG: { [string]: boolean } = {}
for _, name in ipairs(PermissionLogic.Flags) do
	FLAG[name] = true
end

export type Row = { [string]: boolean }

-- visit starts on so a stranger can walk across until you turn it off.
-- collisions starts on: that is how the world behaves until the flag is applied.
-- Open to tuning: both defaults.
function PermissionLogic.DefaultRow(): Row
	return {
		visit = true,
		sit = false,
		collisions = true,
		build = false,
		destroy = false,
		grab = false,
		interact = false,
		drive = false,
		saveItems = false,
	}
end

function PermissionLogic.IsFlag(flag: string): boolean
	return FLAG[flag] == true
end

function PermissionLogic.Target(value: unknown): string?
	if value == PermissionLogic.Anyone then
		return PermissionLogic.Anyone
	end
	if type(value) == "number" and value == math.floor(value) and value >= 1 and value <= 1e15 then
		return string.format("%d", value)
	end
	if type(value) == "string" and string.match(value, "^[1-9]%d*$") ~= nil then
		local n = tonumber(value)
		if n and n >= 1 and n <= 1e15 then
			return value
		end
	end
	return nil
end

local function applyRow(into: Row, row: any)
	if type(row) ~= "table" then
		return
	end
	for _, flag in ipairs(PermissionLogic.Flags) do
		if row[flag] == true or row[flag] == false then
			into[flag] = row[flag]
		end
	end
end

-- Plot bans (owner only, PlotService.Moderate). A ban is a marker on that
-- person's row in the same saved `permissions` table (so it is saved with
-- the slot and needs no new field): { banned = true, bannedName, bannedAt }.
-- A banned person resolves to every flag off, so the one rule that decides
-- visiting, building, grabbing and the doors (Allows, CanVisit, MustLeave,
-- PlotLogic.CanEdit) refuses them with no extra check at each caller.
PermissionLogic.MaxBans = 30

function PermissionLogic.IsBanned(permissions: any, userId: number): boolean
	if type(permissions) ~= "table" or type(userId) ~= "number" then
		return false
	end
	local row = permissions[tostring(userId)]
	return type(row) == "table" and row.banned == true
end

local function nothing(): Row
	local row: Row = {}
	for _, flag in ipairs(PermissionLogic.Flags) do
		row[flag] = false
	end
	return row
end

-- The row that applies to `userId`: defaults, then anyone, then that
-- person. A banned person gets every flag off.
function PermissionLogic.Resolve(permissions: any, userId: number): Row
	if PermissionLogic.IsBanned(permissions, userId) then
		return nothing()
	end
	local row = PermissionLogic.DefaultRow()
	if type(permissions) == "table" then
		applyRow(row, permissions[PermissionLogic.Anyone])
		applyRow(row, permissions[tostring(userId)])
	end
	return row
end

-- What the Settings toggle shows (the stored bit, or the default).
function PermissionLogic.Stored(permissions: any, target: string, flag: string): boolean
	local defaults = PermissionLogic.DefaultRow()
	if not FLAG[flag] then
		return false
	end
	if type(permissions) ~= "table" then
		return defaults[flag] == true
	end
	local function read(row: any): boolean?
		if type(row) == "table" and (row[flag] == true or row[flag] == false) then
			return row[flag] == true
		end
		return nil
	end
	local own = read(permissions[target])
	if own ~= nil then
		return own
	end
	if target ~= PermissionLogic.Anyone then
		local shared = read(permissions[PermissionLogic.Anyone])
		if shared ~= nil then
			return shared
		end
	end
	return defaults[flag] == true
end

function PermissionLogic.Allows(permissions: any, userId: number, flag: string): boolean
	if not FLAG[flag] then
		return false
	end
	local row = PermissionLogic.Resolve(permissions, userId)
	if flag == "destroy" then
		return row.destroy == true or row.build == true
	end
	return row[flag] == true
end

-- A stranger with visit off is put off the yard. The owner never is.
function PermissionLogic.MustLeave(permissions: any, userId: number, ownerId: number): boolean
	if userId == ownerId then
		return false
	end
	return not PermissionLogic.Allows(permissions, userId, "visit")
end

-- May `viewerId` walk over to `ownerId`'s plot? Never your own (you have
-- the spawn pad), and only while the owner's visit flag lets you.
function PermissionLogic.CanVisit(permissions: any, viewerId: number, ownerId: number): boolean
	if viewerId == ownerId then
		return false
	end
	return PermissionLogic.Allows(permissions, viewerId, "visit")
end

export type Candidate = { userId: number, name: string, hasPlot: boolean, permissions: any }

-- The Visit list: players in the server who own a plot and whose
-- permissions allow `viewerId` in, sorted by name (then user id).
-- Pure, so the Settings tab and its tests agree with the server's check.
function PermissionLogic.VisitList(candidates: { Candidate }, viewerId: number): { { userId: number, name: string } }
	local out: { { userId: number, name: string } } = {}
	for _, c in ipairs(candidates) do
		if c.hasPlot and PermissionLogic.CanVisit(c.permissions, viewerId, c.userId) then
			table.insert(out, { userId = c.userId, name = c.name })
		end
	end
	table.sort(out, function(a, b)
		local la, lb = string.lower(a.name), string.lower(b.name)
		if la ~= lb then
			return la < lb
		end
		return a.userId < b.userId
	end)
	return out
end

-- A user id from the VisitPlot remote: a whole number, nothing else.
function PermissionLogic.VisitTarget(value: unknown): number?
	if type(value) == "number" and value == math.floor(value) and value >= 1 and value <= 1e15 then
		return value
	end
	return nil
end

local function people(permissions: { [string]: any }): number
	local count = 0
	for key, row in pairs(permissions) do
		if key ~= PermissionLogic.Anyone and type(row) == "table" and row.banned ~= true then
			count += 1
		end
	end
	return count
end

-- Writes one flag. False leaves `permissions` unchanged.
function PermissionLogic.Set(permissions: any, target: string, flag: string, on: boolean): boolean
	if type(permissions) ~= "table" or not FLAG[flag] or type(on) ~= "boolean" then
		return false
	end
	if PermissionLogic.Target(target) ~= target then
		return false
	end
	local existing = permissions[target]
	if type(existing) == "table" and existing.banned == true then
		return false -- a ban is lifted with Unban, not by a toggle
	end
	if
		target ~= PermissionLogic.Anyone
		and type(permissions[target]) ~= "table"
		and people(permissions) >= PermissionLogic.MaxPeople
	then
		return false
	end
	local row = permissions[target]
	if type(row) ~= "table" then
		row = {}
		permissions[target] = row
	end
	row[flag] = on
	return true
end

-- A name safe to keep and show: a Roblox user name (letters, digits,
-- underscore), else a plain stand-in.
local function safeName(name: unknown, userId: string): string
	if type(name) == "string" and string.match(name, "^[%w_]+$") ~= nil and #name <= 20 then
		return name
	end
	return "Player " .. userId
end

-- Bans `userId` from this plot. False (with a reason a toast can use) for a
-- bad id, yourself, someone already banned or a full list.
function PermissionLogic.Ban(
	permissions: any,
	ownerId: number,
	userId: unknown,
	name: unknown,
	now: number
): (boolean, string?)
	if type(permissions) ~= "table" then
		return false, "bad"
	end
	local target = PermissionLogic.VisitTarget(userId)
	if not target then
		return false, "bad"
	end
	if target == ownerId then
		return false, "You can't ban yourself."
	end
	if PermissionLogic.IsBanned(permissions, target) then
		return false, "They are already banned from your plot."
	end
	if #PermissionLogic.Bans(permissions) >= PermissionLogic.MaxBans then
		return false, string.format("Your ban list is full (%d). Unban someone first.", PermissionLogic.MaxBans)
	end
	local key = string.format("%d", target)
	local row = nothing() :: { [string]: any }
	row.banned = true
	row.bannedName = safeName(name, key)
	row.bannedAt = if type(now) == "number" then now else 0
	permissions[key] = row
	return true, nil
end

-- Lifts a ban and drops that person's row (back to the "anyone" rules).
function PermissionLogic.Unban(permissions: any, userId: unknown): boolean
	local target = PermissionLogic.VisitTarget(userId)
	if not target or not PermissionLogic.IsBanned(permissions, target) then
		return false
	end
	permissions[string.format("%d", target)] = nil
	return true
end

export type Ban = { userId: number, name: string, at: number }

-- The ban list, oldest first (then by id).
function PermissionLogic.Bans(permissions: any): { Ban }
	local out: { Ban } = {}
	if type(permissions) ~= "table" then
		return out
	end
	for key, row in pairs(permissions) do
		if
			type(row) == "table"
			and row.banned == true
			and PermissionLogic.Target(key) == key
			and key ~= PermissionLogic.Anyone
		then
			table.insert(out, {
				userId = tonumber(key) :: number,
				name = safeName(row.bannedName, key),
				at = if type(row.bannedAt) == "number" then row.bannedAt else 0,
			})
		end
	end
	table.sort(out, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.userId < b.userId
	end)
	return out
end

-- The PlotBans attribute: "id:name;id:name". The ban list is the owner's
-- to read in Settings, so it rides on their own player.
function PermissionLogic.EncodeBans(permissions: any): string
	local parts = {}
	for _, ban in ipairs(PermissionLogic.Bans(permissions)) do
		table.insert(parts, string.format("%d:%s", ban.userId, (string.gsub(ban.name, "[:;]", ""))))
	end
	return table.concat(parts, ";")
end

function PermissionLogic.DecodeBans(text: unknown): { { userId: number, name: string } }
	local out: { { userId: number, name: string } } = {}
	if type(text) ~= "string" or text == "" then
		return out
	end
	for chunk in string.gmatch(text, "[^;]+") do
		local id, name = string.match(chunk, "^(%d+):(.+)$")
		local userId = if id then PermissionLogic.VisitTarget(tonumber(id)) else nil
		if userId and name then
			table.insert(out, { userId = userId, name = name })
		end
	end
	return out
end

local function piece(target: string, row: any): string?
	if type(row) ~= "table" then
		return nil
	end
	local bits = {}
	for _, flag in ipairs(PermissionLogic.Flags) do
		if row[flag] == true or row[flag] == false then
			table.insert(bits, flag .. "=" .. (if row[flag] == true then "1" else "0"))
		end
	end
	if #bits == 0 then
		return nil
	end
	return target .. ":" .. table.concat(bits, ",")
end

-- Compact form for the PlotPermissions attribute. Empty when nothing is set.
function PermissionLogic.Encode(permissions: any): string
	if type(permissions) ~= "table" then
		return ""
	end
	local parts = {}
	local anyone = piece(PermissionLogic.Anyone, permissions[PermissionLogic.Anyone])
	if anyone then
		table.insert(parts, anyone)
	end
	local ids = {}
	for key, row in pairs(permissions) do
		if key ~= PermissionLogic.Anyone and type(row) == "table" then
			table.insert(ids, key)
		end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local text = piece(id, permissions[id])
		if text then
			table.insert(parts, text)
		end
	end
	return table.concat(parts, ";")
end

function PermissionLogic.Decode(text: unknown): { [string]: Row }
	local out: { [string]: Row } = {}
	if type(text) ~= "string" or text == "" then
		return out
	end
	for chunk in string.gmatch(text, "[^;]+") do
		local target, rest = string.match(chunk, "^([^:]+):(.+)$")
		if target and rest and PermissionLogic.Target(target) == target then
			local row: Row = {}
			for bit in string.gmatch(rest, "[^,]+") do
				local flag, value = string.match(bit, "^([%a]+)=([01])$")
				if flag and FLAG[flag] then
					row[flag] = value == "1"
				end
			end
			out[target] = row
		end
	end
	return out
end

return PermissionLogic
