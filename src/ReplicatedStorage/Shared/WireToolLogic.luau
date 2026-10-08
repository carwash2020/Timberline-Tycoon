--!strict
-- WireToolLogic: the rules of the wiring tool (StarterPlayerScripts/WireTool).
-- Pure, so tests can run a whole wiring session without a client.
--
-- In BUILD mode, WIRE starts the tool. Pick a Wall Switch, then tap a Spark
-- Lamp or a Door to wire it (the switch stays picked, so one switch can feed
-- several). Pick any wired piece and CUT clears its wires. Everything is an
-- intent for the server's Wire remote: (fromUid, 1, toUid, 1) or
-- ("cut", uid); LogicService checks it all again.
--
-- The client learns the wires from each switch model's "Wires" attribute
-- (target uids, comma joined). Lines are drawn only for your own plot and
-- never more than MaxLines of them.

local WireLogic = require(script.Parent.WireLogic)

local WireToolLogic = {}

WireToolLogic.MaxLines = WireLogic.MaxWires
WireToolLogic.AimDegrees = 12 -- how close to the crosshair a piece must be (gamepad)
WireToolLogic.TapPx = 44 -- a tap this near a piece's centre on screen picks it (touch target)
WireToolLogic.LineThickness = 0.14

-- Where on each piece the wire is tied, studs above its base.
WireToolLogic.Height = {
	switch = 3.4,
	lamp = 5.5,
	door = 4,
	button = 1.2,
	lever = 2.4,
	plate = 0.4,
	gate = 1.2,
	invert = 1.2,
	delay = 1.2,
	sustain = 1.2,
	clock = 1.7,
	glow = 0.6,
	hatch = 0.4,
} :: { [string]: number }

-- Shown once per session, in order, while the tool is open.
WireToolLogic.Lessons = { "Pick an output", "Pick an input", "Done: flip it" }

-- `step` is 1..3 while teaching and 4 once the session has seen all three.
function WireToolLogic.Lesson(step: number): string?
	return WireToolLogic.Lessons[step]
end

function WireToolLogic.Advance(step: number, event: string): number
	if step >= 4 then
		return 4
	end
	if event == "source" and step <= 1 then
		return 2
	elseif event == "link" and step <= 2 then
		return 3
	elseif event == "done" and step >= 3 then
		return 4
	end
	return if step < 1 then 1 else step
end

export type Piece = { uid: string, blueprintId: string, x: number, y: number?, z: number }
export type Action = { op: "link", from: string, to: string, toPort: number? } | { op: "cut", uid: string }
export type Segment =
	{ from: string, to: string, ax: number, ay: number, az: number, bx: number, by: number, bz: number }

local function roleOf(pieces: { Piece }, uid: string?): string?
	if uid == nil then
		return nil
	end
	for _, piece in ipairs(pieces) do
		if piece.uid == uid then
			return WireLogic.Role(piece.blueprintId)
		end
	end
	return nil
end

-- A tap on `tapped` (nil for empty ground) with `picked` already chosen.
-- Returns the new pick and, when a wire should be made, that action.
function WireToolLogic.Tap(picked: string?, tapped: string?, pieces: { Piece }): (string?, Action?)
	local role = roleOf(pieces, tapped)
	if tapped == nil or role == nil then
		return nil, nil
	end
	if WireLogic.IsSource(role) then
		if picked == tapped then
			return nil, nil
		end
		return tapped, nil
	end
	-- An input (a lamp, a door, a gate, a timer).
	if picked ~= nil and WireLogic.IsSource(roleOf(pieces, picked)) then
		return picked, { op = "link", from = picked, to = tapped }
	end
	return tapped, nil
end

-- The CUT button: clears the wires on the picked piece.
function WireToolLogic.Cut(picked: string?, pieces: { Piece }): Action?
	if picked ~= nil and roleOf(pieces, picked) ~= nil then
		return { op = "cut", uid = picked }
	end
	return nil
end

-- What the Wire remote is fired with for an action.
function WireToolLogic.Args(action: Action): { any }
	if action.op == "link" then
		return { action.from, WireLogic.Port, action.to, action.toPort or WireLogic.Port }
	end
	return { "cut", action.uid }
end

-- The bar's one line of help, for what is picked.
function WireToolLogic.Help(picked: string?, pieces: { Piece }): string
	local role = roleOf(pieces, picked)
	if role == "switch" then
		return "Tap a Spark Lamp or a Door to wire it. CUT clears this switch."
	elseif WireLogic.IsSource(role) then
		return "Tap an input to wire it. CUT clears this piece."
	elseif role ~= nil then
		return "Tap an output to wire it here. CUT clears this piece."
	end
	return "Tap a Wall Switch to start a wire."
end

-- The lowest input port on `blueprintId` that `toUid` does not already use.
-- When every port is used, another wire ORs onto port 1.
function WireToolLogic.NextIn(wires: { WireLogic.Wire }, toUid: string, blueprintId: string): number
	local spec = WireLogic.Spec(blueprintId)
	if not spec then
		return WireLogic.Port
	end
	for _, port in ipairs(spec.ins) do
		local used = false
		for _, wire in ipairs(wires) do
			if wire.to == toUid and (wire.toPort or 1) == port then
				used = true
				break
			end
		end
		if not used then
			return port
		end
	end
	return spec.ins[1] or WireLogic.Port
end

-- The target uids in a switch model's "Wires" attribute.
function WireToolLogic.Parse(text: unknown): { string }
	local out: { string } = {}
	if type(text) ~= "string" then
		return out
	end
	for token in string.gmatch(text, "[^,]+") do
		local uid = string.match(token, "^[^@]+")
		if uid and uid ~= "" then
			table.insert(out, uid)
		end
	end
	return out
end

-- The { from, to } list the client knows, for WireLogic.Check's pre-flight.
function WireToolLogic.WireList(wires: { [string]: string }): { WireLogic.Wire }
	local out: { WireLogic.Wire } = {}
	local uids: { string } = {}
	for uid in pairs(wires) do
		table.insert(uids, uid)
	end
	table.sort(uids)
	for _, from in ipairs(uids) do
		for _, to in ipairs(WireToolLogic.Parse(wires[from])) do
			table.insert(out, { from = from, to = to })
		end
	end
	return out
end

-- The lines to draw, plot-local, at most MaxLines. `wires` maps a switch uid
-- to the text of its "Wires" attribute. Pieces that are gone are skipped.
function WireToolLogic.Segments(pieces: { Piece }, wires: { [string]: string }): { Segment }
	local by: { [string]: Piece } = {}
	for _, piece in ipairs(pieces) do
		by[piece.uid] = piece
	end
	local out: { Segment } = {}
	local function tie(piece: Piece): (number, number, number)
		local role = WireLogic.Role(piece.blueprintId)
		return piece.x, (piece.y or 0) + (WireToolLogic.Height[role or ""] or 3), piece.z
	end
	local uids: { string } = {}
	for uid in pairs(wires) do
		table.insert(uids, uid)
	end
	table.sort(uids)
	for _, fromUid in ipairs(uids) do
		local a = by[fromUid]
		if a and WireLogic.IsSource(WireLogic.Role(a.blueprintId)) then
			for _, toUid in ipairs(WireToolLogic.Parse(wires[fromUid])) do
				local b = by[toUid]
				if b and WireLogic.IsTarget(WireLogic.Role(b.blueprintId)) then
					if #out >= WireToolLogic.MaxLines then
						return out
					end
					local ax, ay, az = tie(a)
					local bx, by2, bz = tie(b)
					table.insert(out, {
						from = fromUid,
						to = toUid,
						ax = ax,
						ay = ay,
						az = az,
						bx = bx,
						by = by2,
						bz = bz,
					})
				end
			end
		end
	end
	return out
end

-- Gamepad: the wireable piece nearest the crosshair. The eye and the look
-- direction are plot-local; `dir` need not be a unit vector. A piece must
-- be within AimDegrees of the crosshair and WireLogic.Reach * 1.5 away.
function WireToolLogic.Aim(
	pieces: { Piece },
	ex: number,
	ey: number,
	ez: number,
	dx: number,
	dy: number,
	dz: number
): string?
	local dlen = math.sqrt(dx * dx + dy * dy + dz * dz)
	if dlen < 1e-6 or dlen ~= dlen then
		return nil
	end
	local best: string? = nil
	local bestAngle = math.rad(WireToolLogic.AimDegrees)
	for _, piece in ipairs(pieces) do
		if WireLogic.Role(piece.blueprintId) ~= nil then
			local px, py, pz =
				piece.x - ex,
				(piece.y or 0) + (WireToolLogic.Height[WireLogic.Role(piece.blueprintId) or ""] or 3) - ey,
				piece.z - ez
			local plen = math.sqrt(px * px + py * py + pz * pz)
			if plen > 0.01 and plen <= WireLogic.Reach * 1.5 then
				local cos = math.clamp((px * dx + py * dy + pz * dz) / (plen * dlen), -1, 1)
				local angle = math.acos(cos)
				if angle < bestAngle or (angle == bestAngle and best ~= nil and piece.uid < best) then
					bestAngle = angle
					best = piece.uid
				end
			end
		end
	end
	return best
end

-- Screen pick: the wireable piece whose on-screen point (px) is nearest the
-- tap, within TapPx. `points` maps uid to its screen {x, y}.
function WireToolLogic.NearestOnScreen(
	pieces: { Piece },
	points: { [string]: { number } },
	tapX: number,
	tapY: number
): string?
	local best: string? = nil
	local bestD = WireToolLogic.TapPx
	for _, piece in ipairs(pieces) do
		local p = points[piece.uid]
		if p and WireLogic.Role(piece.blueprintId) ~= nil then
			local d = math.sqrt((p[1] - tapX) ^ 2 + (p[2] - tapY) ^ 2)
			if d < bestD or (d == bestD and best ~= nil and piece.uid < best) then
				bestD = d
				best = piece.uid
			end
		end
	end
	return best
end

return WireToolLogic
