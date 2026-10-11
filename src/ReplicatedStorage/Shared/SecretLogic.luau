--!strict
-- SecretLogic: which secrets a save has found. The server decides; this
-- module only knows the rules. Lane E reads Count for the field guide.
-- Pay once per slot. A second claim, and a second migrate, change nothing.

local UndergroundData = require(script.Parent.World.UndergroundData)

local SecretLogic = {}

SecretLogic.Total = 5

export type Found = { [string]: boolean }

function SecretLogic.FoundMap(profile: any): Found
	if type(profile) == "table" and type(profile.secrets) == "table" then
		return profile.secrets
	end
	return {}
end

function SecretLogic.Count(profile: any): (number, number)
	local found = SecretLogic.FoundMap(profile)
	local n = 0
	for _, secret in ipairs(UndergroundData.Secrets) do
		if found[secret.id] == true then
			n += 1
		end
	end
	return n, SecretLogic.Total
end

function SecretLogic.HasGear(gear: { string }?, id: string?): boolean
	if id == nil then
		return true
	end
	if type(gear) ~= "table" then
		return false
	end
	return table.find(gear, id) ~= nil
end

-- True when this visit is the first time the player is inside the zone
-- with the gate open. Does not pay. Does not write the save.
function SecretLogic.CanFind(profile: any, id: string, x: number, z: number, night: boolean, gear: { string }?): boolean
	local secret = nil
	for _, s in ipairs(UndergroundData.Secrets) do
		if s.id == id then
			secret = s
		end
	end
	if not secret then
		return false
	end
	if SecretLogic.FoundMap(profile)[id] == true then
		return false
	end
	local dx, dz = x - secret.x, z - secret.z
	if dx * dx + dz * dz > secret.radius * secret.radius then
		return false
	end
	if secret.night and not night then
		return false
	end
	if not SecretLogic.HasGear(gear, secret.gear) then
		return false
	end
	return true
end

-- Stamp the find. Returns the cash to pay, or 0 if it was already found.
-- Calling it twice pays once. Safe if profile.secrets is missing: the
-- caller keeps the returned map and A1's field stores it when it exists.
function SecretLogic.Claim(profile: any, id: string): (number, Found)
	local found = SecretLogic.FoundMap(profile)
	if found[id] == true then
		return 0, found
	end
	local pay = 0
	for _, secret in ipairs(UndergroundData.Secrets) do
		if secret.id == id then
			pay = secret.pay
		end
	end
	if pay <= 0 then
		return 0, found
	end
	found[id] = true
	if type(profile) == "table" then
		profile.secrets = found
	end
	return pay, found
end

-- A save whose worldVersion is below the live constant does not put
-- truckAt or groundLoad back on the terrain. Idempotent.
function SecretLogic.RestoresIntoTerrain(saveVersion: number, worldVersion: number): boolean
	return saveVersion >= worldVersion
end

return SecretLogic
