--!strict
-- Travel-pin label boxes for the T413 map shot. Pure. The preview scene
-- places these rects; the spec checks they do not intersect.
--
-- The shot looks straight down from 95 studs, fov 48, viewport height 800.
-- px/stud = 800 / (2 * 95 * tan(24°)) ≈ 9.46, so 4 px is about 0.42 studs.
-- Gap is 0.5 studs, which is more than 4 px.

local TravelPinLayout = {}

export type Pin = { name: string, x: number, z: number, w: number, d: number }
export type Rect = { name: string, x: number, z: number, w: number, d: number, homeX: number, homeZ: number }

TravelPinLayout.CameraHeight = 95
TravelPinLayout.CameraFov = 48
TravelPinLayout.ViewHeight = 800
TravelPinLayout.Gap = 0.5

function TravelPinLayout.PixelsPerStud(): number
	local half = TravelPinLayout.CameraHeight * math.tan(math.rad(TravelPinLayout.CameraFov / 2))
	return TravelPinLayout.ViewHeight / (2 * half)
end

local function overlaps(a: Rect, b: Rect, gap: number): boolean
	return math.abs(a.x - b.x) < (a.w + b.w) / 2 + gap and math.abs(a.z - b.z) < (a.d + b.d) / 2 + gap
end

-- The two shop piles on the pin map. Each is stacked in a column so the
-- boxes cannot sit on each other. Leader lines in the preview point home.
local CLUSTERS: { { string } } = {
	{ "ToolShed", "WeighHouse", "LandOffice", "Dealership", "HearthAndHome" },
	{ "CoatKiosk", "SkyMarket", "SkyForge" },
}

local function inCluster(name: string): boolean
	for _, cluster in ipairs(CLUSTERS) do
		for _, entry in ipairs(cluster) do
			if entry == name then
				return true
			end
		end
	end
	return false
end

-- Stack labels that share space. Cluster shops get their own column, to the
-- side of the pile. Everything else keeps its pin and steps up if it must.
function TravelPinLayout.Place(pins: { Pin }): { Rect }
	local byName: { [string]: Pin } = {}
	for _, pin in ipairs(pins) do
		byName[pin.name] = pin
	end
	local out: { Rect } = {}
	local gap = TravelPinLayout.Gap
	local function taken(x: number, z: number, w: number, d: number): boolean
		local probe: Rect = { name = "", x = x, z = z, w = w, d = d, homeX = x, homeZ = z }
		for _, other in ipairs(out) do
			if overlaps(probe, other, gap) then
				return true
			end
		end
		return false
	end
	local function commit(pin: Pin, x: number, z: number)
		table.insert(out, {
			name = pin.name,
			x = x,
			z = z,
			w = pin.w,
			d = pin.d,
			homeX = pin.x,
			homeZ = pin.z,
		})
	end
	for _, pin in ipairs(pins) do
		if not inCluster(pin.name) then
			local z = pin.z
			for _ = 1, 24 do
				if not taken(pin.x, z, pin.w, pin.d) then
					break
				end
				z -= pin.d + gap
			end
			commit(pin, pin.x, z)
		end
	end
	for _, cluster in ipairs(CLUSTERS) do
		local members: { Pin } = {}
		local cx, cz = 0, 0
		for _, name in ipairs(cluster) do
			local pin = byName[name]
			if pin then
				table.insert(members, pin)
				cx += pin.x
				cz += pin.z
			end
		end
		local n = #members
		if n > 0 then
			cx /= n
			cz /= n
			local step = members[1].d + gap
			local x = cx - 16
			local z0 = cz - (n - 1) * step / 2
			-- Keep the column inside the pin camera (target z 1100).
			local halfZ = TravelPinLayout.CameraHeight * math.tan(math.rad(TravelPinLayout.CameraFov / 2))
			local zMax = 1100 + halfZ - members[1].d / 2 - 2
			local zMin = 1100 - halfZ + members[1].d / 2 + 2
			local bottom = z0 + (n - 1) * step
			if bottom > zMax then
				z0 -= bottom - zMax
			end
			if z0 < zMin then
				z0 = zMin
			end
			for shift = 0, 10 do
				local tryX = x - shift * 8
				local clear = true
				for i, pin in ipairs(members) do
					if taken(tryX, z0 + (i - 1) * step, pin.w, pin.d) then
						clear = false
						break
					end
				end
				if clear then
					x = tryX
					break
				end
			end
			for i, pin in ipairs(members) do
				commit(pin, x, z0 + (i - 1) * step)
			end
		end
	end
	return out
end

function TravelPinLayout.Separated(a: Rect, b: Rect): boolean
	return not overlaps(a, b, TravelPinLayout.Gap - 1e-4)
end

return TravelPinLayout
