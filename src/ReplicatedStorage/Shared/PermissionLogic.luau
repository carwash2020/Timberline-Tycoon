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

-- The row that applies to `userId`: defaults, then anyone, then that person.
function PermissionLogic.Resolve(permissions: any, userId: number): Row
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

local function people(permissions: { [string]: any }): number
	local count = 0
	for key, row in pairs(permissions) do
		if key ~= PermissionLogic.Anyone and type(row) == "table" then
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
