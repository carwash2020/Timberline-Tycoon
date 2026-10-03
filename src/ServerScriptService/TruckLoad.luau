--!strict
-- TruckLoad: loose wood riding on truck beds, the v2 loop's way of hauling
-- (V2_PLAN.md §4b and §4d, M1.6). There are no bed slots: wood dragged up
-- onto a bed stays there by friction, and drives, sells and saves with the
-- truck. GameServer starts it only under the v2 loop (Shared/CoreLoop);
-- under v1 none of this runs and the bed slots work as they always have.
--
-- On the bed: a piece (any wood GrabService.PieceOf knows) rides on a
-- truck while its centre (by volume, over its solid parts) is inside one
-- of the truck's BedZones (TruckArt.AddBedZone: the inside of each bed,
-- TruckLayout.BedZoneHeight tall). Each player's truck is looked at every
-- DrivenPollSec while its owner drives it, every ParkedPollSec otherwise:
-- one box query per BedZone over the Wood folder, then the centre test.
--
-- What it does with that:
--   * Driving: the pieces on the bed are simulated by the driver's device
--     (SetNetworkOwner), like the truck, so truck and cargo move on one
--     device and friction holds. Not a piece someone holds (GrabService
--     has it) or one welded to the bed (it's part of the truck). A piece
--     that falls off stays the driver's for ReleaseKeepOwnerSec, then goes
--     back to automatic. Every look judges each piece the driver simulates
--     (VehicleLogic.JudgeMove against WoodMaxSpeed): one that moved further
--     than anything can is put back where it last was, stopped, and kept
--     by the server for PutBackHoldSec (an exploiter teleporting wood onto
--     the pad).
--   * The driver gets out: the pieces go to the server with the truck while
--     it settles; once it's parked (anchored again), back to automatic.
--   * Every bed part of a player's truck grips at BedFriction (Tune;
--     TruckArt.ApplyBedFriction). v1 trucks never get it.
--   * BedAutoWeld (Tune; off), the fallback if loads jitter on a moving bed:
--     a piece resting on the bed (moving under WeldSpeed relative to it for
--     WeldRestSec) is welded to it; grabbing it (GrabService's beforeHold)
--     or turning the setting off lets go. In Studio, Tune_BedAutoWeld = 1.
--   * Nobody but the truck's owner can grab what's on its beds
--     (GrabService's bedOwner hook, GrabLogic.CanGrab).
--   * Wood resting on its owner's bed never ages (lastInteracted).
--   * For the HUD, about once a second, on the truck and on its owner:
--     BedVolume (u³), BedValue ($, before 2x Cash), BedRoom (u³ the beds
--     carry a trip, TruckLayout.BedRoomU3) and BedLength (studs, the
--     longest bed; for the "cut it to fit" hint).
--   * Hooks.onLoaded(player, piece, volume): a piece of theirs came to rest
--     on their own bed, once per piece (the tutorial's woodLoaded).
-- VehicleService's hooks (GameServer wires them):
--   * OnDriverChanged: the hand-off above, at once.
--   * OnRebuild: Send truck home, or a switch at the Dealership. In town
--     (VehicleService decides) the pieces on the bed come along, each in
--     the same place on the same bed of the new truck; out of town they
--     stay where they are, as the truck goes (the player's alone for
--     LeftLoadGraceSec, as a v1 load left behind). On joining, profile.truckLoad
--     is rebuilt on the bed, or on the ground where the truck stood when
--     that wasn't in town (yours for LeftLoadGraceSec).
--   * LoadCount: Recall's warning before a load is left out of town.
-- A load left on the ground out of town (a rejoin, Send truck home) is
-- remembered per owner; what of it is still theirs and lying about when
-- they leave goes into profile.groundLoad (each piece where it lay) and
-- comes back there on their next join, yours for LeftLoadGraceSec.
-- Saving: your own and unowned pieces on your beds go into
-- profile.truckLoad (LeftLoad has the format), the most valuable first,
-- capped at MaxSavedPieces and MaxSavedSections: whenever the load changes
-- and every SaveEverySec, so ProfileStore's autosave has it, and on
-- leaving (PlayerRemoving, before the final save), when the saved pieces
-- leave the world with you. Someone else's piece on your bed stays behind
-- for them. Instant Delivery sells PiecesOn(player) (SellService.SellBed).
-- Until WoodService builds pieces, a saved piece is rebuilt here (Build:
-- block sections with their cut faces, registered with GrabService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SellLogic = require(ReplicatedStorage.Shared.SellLogic)
local TreeArt = require(ReplicatedStorage.Shared.Art.TreeArt)
local TruckArt = require(ReplicatedStorage.Shared.Art.TruckArt)
local Tune = require(ReplicatedStorage.Shared.Tune)
local Util = require(ReplicatedStorage.Shared.Util)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local GrabService = require(script.Parent.GrabService)
local LeftLoad = require(script.Parent.LeftLoad)

local TruckLoad = {}

TruckLoad.DrivenPollSec = 0.25 -- a driven truck's load is looked at this often
TruckLoad.ParkedPollSec = 1 -- any other truck's
TruckLoad.PublishSec = 1 -- the HUD's numbers, at most this often
TruckLoad.SaveEverySec = 5 -- profile.truckLoad refreshed at least this often
TruckLoad.WeldSpeed = 1 -- studs/s relative to the bed: slower counts as resting (BedAutoWeld)
TruckLoad.WeldRestSec = 0.5 -- resting this long gets a piece welded (BedAutoWeld)
TruckLoad.PutBackHoldSec = 1 -- a piece put back stays the server's this long
TruckLoad.Lift = 0.05 -- studs over its saved place a piece is set down (never sunk into the bed)
TruckLoad.MaxPieces = GameConfig.MaxWoodPiecesPerPlayer -- the most pieces one truck's beds track
TruckLoad.WeldName = "BedWeld"
TruckLoad.LeftText = "Your last load is waiting where you left your truck."
TruckLoad.LeftBehindText = "Your load was left where your truck stood."

export type Piece = GrabService.Piece
export type SavedPiece = LeftLoad.Piece

-- Tutorial, daily and milestone events (GameServer wires them).
export type Hooks = {
	onLoaded: ((Player, Piece, number) -> ())?,
}
TruckLoad.Hooks = {} :: Hooks

export type Deps = {
	woodFolder: Instance, -- where loose wood lives (TimberlineMap/Wood)
	truckOf: (Player) -> Model?, -- the player's truck (VehicleService.GetVehicle)
	profileOf: (Player) -> any, -- their save (ProfileService.GetProfile), nil before it loads
	notify: ((Player, string) -> ())?,
	-- Rebuilds a saved piece at `cf`, owned by the player, free to anyone
	-- else after `graceSec` (default: TruckLoad.Build; WoodService later).
	build: ((SavedPiece, Player, CFrame, number) -> Model?)?,
	forget: ((Model) -> ())?, -- drops a piece from the registries before it's destroyed
	moved: ((Model) -> ())?, -- a piece TruckLoad moved (a recall): for WoodWatch's last good spot
	-- Seams for the specs: what's in a box (over the Wood folder), the
	-- clock, who's online, whether this is Studio.
	partsInBox: ((CFrame, Vector3) -> { BasePart })?,
	now: (() -> number)?,
	players: (() -> { Player })?,
	isStudio: (() -> boolean)?,
}

type Zone = { zone: BasePart, bed: BasePart }
type Riding = { piece: Piece, zone: Zone }
-- A piece whose physics TruckLoad handed out: to the driver (owner), or
-- to the server while the truck settles (owner nil).
type Carried = {
	root: BasePart,
	owner: Player?,
	lastGood: CFrame,
	lastGoodAt: number,
	leftAt: number?, -- when it fell off the bed
}
type Still = { rel: CFrame, at: number, since: number? }
type Truck = {
	owner: Player,
	model: Model,
	zones: { Zone },
	driver: Player?,
	nextAt: number,
	publishAt: number,
	saveAt: number,
	loadKey: string,
	riding: { [Model]: Riding },
	cargo: { [Model]: Carried },
	kept: { [Model]: number }, -- put back: not handed out again before then
	welds: { [Model]: WeldConstraint },
	still: { [Model]: Still },
	friction: number?, -- the BedFriction last applied
	shown: { [string]: number }, -- the HUD numbers last published
}

local deps: Deps? = nil
local trucks: { [Player]: Truck } = {}
local loadedOnce: { [Model]: boolean } = {} -- pieces whose onLoaded has fired
-- Pieces a load left on the ground out of town, by owner (UserId): saved
-- as groundLoad when they leave, if still theirs and lying about.
local leftOf: { [number]: { [Model]: boolean } } = {}

local function trackLeft(userId: number, model: Model)
	local set = leftOf[userId]
	if not set then
		set = {}
		leftOf[userId] = set
	end
	set[model] = true
end
local query: ((CFrame, Vector3) -> { BasePart })? = nil

---------------------------------------------------------------------------
-- Pure rules
---------------------------------------------------------------------------

-- True when `point` is inside the box `size` centred at `cf`.
function TruckLoad.Inside(cf: CFrame, size: Vector3, point: Vector3): boolean
	local p = cf:PointToObjectSpace(point)
	local h = size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

-- A piece's centre: the middle of its solid parts weighted by volume (its
-- sections; massless dress such as cut faces doesn't count). Nil when it
-- has none.
function TruckLoad.Centre(model: Model): Vector3?
	local sum, total = Vector3.zero, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not d.Massless then
			local s = d.Size
			local v = s.X * s.Y * s.Z
			sum += d.CFrame.Position * v
			total += v
		end
	end
	if total <= 0 then
		return nil
	end
	return sum / total
end

-- `rel` (a place relative to a bed part) with its middle kept over a
-- BedZone `size` across and along (a carried load on a smaller bed), never
-- below the bed's floor top.
function TruckLoad.ClampOnto(rel: CFrame, size: Vector3): CFrame
	local p = rel.Position
	local hx, hz = size.X / 2, size.Z / 2
	local x, z = math.clamp(p.X, -hx, hx), math.clamp(p.Z, -hz, hz)
	local y = math.max(p.Y, 0.25)
	return rel.Rotation + Vector3.new(x, y, z)
end

-- Whether BedAutoWeld is on: the configured value (GameConfig, through
-- Tune), or in Studio the workspace attribute Tune_BedAutoWeld (1 or true
-- = on, 0 or false = off). Tune itself only overrides numbers.
function TruckLoad.AutoWeldOn(configured: unknown, override: unknown, isStudio: boolean): boolean
	if isStudio then
		if type(override) == "boolean" then
			return override
		elseif type(override) == "number" and override == override then
			return override ~= 0
		end
	end
	return configured == true or (type(configured) == "number" and configured ~= 0)
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

local function clock(): number
	local d = deps
	return if d and d.now then d.now() else os.clock()
end

local function online(): { Player }
	local d = deps
	return if d and d.players then d.players() else Players:GetPlayers()
end

local function partsIn(cf: CFrame, size: Vector3): { BasePart }
	local d = deps
	if not d then
		return {}
	end
	if d.partsInBox then
		return d.partsInBox(cf, size)
	end
	local fn = query
	if not fn then
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { d.woodFolder }
		fn = function(at: CFrame, box: Vector3): { BasePart }
			return workspace:GetPartBoundsInBox(at, box, params)
		end
		query = fn
	end
	return (fn :: (CFrame, Vector3) -> { BasePart })(cf, size)
end

local function autoWeld(): boolean
	local d = deps
	local studio = if d and d.isStudio then d.isStudio() else RunService:IsStudio()
	return TruckLoad.AutoWeldOn(Tune.Get("BedAutoWeld"), workspace:GetAttribute(Tune.Prefix .. "BedAutoWeld"), studio)
end

local function attrNumber(model: Model, name: string): number?
	local v = model:GetAttribute(name)
	return if type(v) == "number" and v == v then v else nil
end

local function attrString(model: Model, name: string): string?
	local v = model:GetAttribute(name)
	return if type(v) == "string" and v ~= "" then v else nil
end

local function volumeOf(model: Model): number
	local v = attrNumber(model, "Volume")
	return if v and v > 0 then v else 0
end

-- What a piece would sell for ($, before 2x Cash): SellLogic, from the
-- attributes only the server writes.
local function valueOf(model: Model): number
	local woodId = attrString(model, "WoodId")
	if not woodId then
		return 0
	end
	local kind: SellLogic.Kind = if model:GetAttribute("Kind") == "plank" then "plank" else "log"
	return SellLogic.PieceValue(woodId, kind, volumeOf(model), attrString(model, "Figure"), attrNumber(model, "Boost"))
end

local function stop(root: BasePart)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- The pieces riding on `zones` right now (at most MaxPieces): each with
-- its record and the zone its centre is in.
local function ridingOn(zones: { Zone }): { [Model]: Riding }
	local out: { [Model]: Riding } = {}
	local n = 0
	for _, z in ipairs(zones) do
		if z.zone.Parent == nil then
			continue
		end
		local cf, size = z.zone.CFrame, z.zone.Size
		local looked: { [Model]: boolean } = {}
		for _, part in ipairs(partsIn(cf, size)) do
			local piece = GrabService.PieceOf(part)
			local model = if piece then piece.model else nil
			if not piece or not model or out[model] or looked[model] or model.Parent == nil then
				continue
			end
			looked[model] = true
			if piece.dead or piece.selling then
				continue
			end
			local centre = TruckLoad.Centre(model)
			if centre and TruckLoad.Inside(cf, size, centre) then
				out[model] = { piece = piece, zone = z }
				n += 1
				if n >= TruckLoad.MaxPieces then
					return out
				end
			end
		end
	end
	return out
end

local function zonesOf(model: Model): { Zone }
	return TruckArt.BedZones(model)
end

local function byBed(zones: { Zone }): { [string]: Zone }
	local out: { [string]: Zone } = {}
	for _, z in ipairs(zones) do
		out[z.bed.Name] = z
	end
	return out
end

-- Every weld TruckLoad made on a piece (normally one).
local function unweldModel(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == TruckLoad.WeldName and d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

---------------------------------------------------------------------------
-- Trucks
---------------------------------------------------------------------------

local function newTruck(owner: Player, model: Model): Truck
	return {
		owner = owner,
		model = model,
		zones = zonesOf(model),
		driver = nil,
		nextAt = 0,
		publishAt = 0,
		saveAt = 0,
		loadKey = "",
		riding = {},
		cargo = {},
		kept = {},
		welds = {},
		still = {},
		friction = nil,
		shown = {},
	}
end

-- Undoes what TruckLoad did to a truck's load: its welds let go, and the
-- pieces the driver or the server simulated go back to automatic.
local function release(t: Truck)
	for _, w in pairs(t.welds) do
		if w.Parent then
			w:Destroy()
		end
	end
	table.clear(t.welds)
	for model, c in pairs(t.cargo) do
		if model.Parent and c.root:IsDescendantOf(model) and GrabService.HeldBy(model) == nil then
			GrabService.Physics.SetAuto(c.root)
		end
	end
	table.clear(t.cargo)
	table.clear(t.still)
	table.clear(t.kept)
end

-- The state of `player`'s truck (fresh when the truck was rebuilt), or nil
-- without one.
local function truckFor(player: Player): Truck?
	local d = deps
	if not d then
		return nil
	end
	local model = d.truckOf(player)
	local t: Truck? = trucks[player]
	if t and t.model ~= model then
		release(t)
		trucks[player] = nil
		t = nil
	end
	if not model then
		return nil
	end
	if not t then
		local made = newTruck(player, model)
		trucks[player] = made
		return made
	end
	return t
end

local function stateOf(model: Model): Truck?
	for _, t in pairs(trucks) do
		if t.model == model then
			return t
		end
	end
	for _, player in ipairs(online()) do
		local d = deps
		if d and d.truckOf(player) == model then
			return truckFor(player)
		end
	end
	return nil
end

-- Hands a piece riding on a driven truck to the driver's device.
local function carry(t: Truck, model: Model, driver: Player, now: number)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local c = t.cargo[model]
	if c and c.owner == driver then
		return
	end
	GrabService.ReleasePiece(model, "cargo") -- not held (checked): ends a dropper's keep window
	if GrabService.Physics.SetOwner(root, driver) then
		t.cargo[model] = { root = root, owner = driver, lastGood = root.CFrame, lastGoodAt = now, leftAt = nil }
	else
		t.cargo[model] = nil
	end
end

-- Judges a piece the driver simulates; false when it was put back.
local function judge(t: Truck, model: Model, c: Carried, now: number): boolean
	if not c.owner then
		return true -- the server's (settling): nothing to judge
	end
	local cf = c.root.CFrame
	local verdict =
		VehicleLogic.JudgeMove(c.lastGood.Position, cf.Position, now - c.lastGoodAt, Tune.Get("WoodMaxSpeed") :: number)
	if verdict == "tooFar" then
		warn(
			string.format(
				"[AntiExploit] %s's cargo moved %d studs in %.1fs; putting it back",
				t.owner.Name,
				math.floor((cf.Position - c.lastGood.Position).Magnitude),
				now - c.lastGoodAt
			)
		)
		GrabService.Physics.SetOwner(c.root, nil)
		model:PivotTo(c.lastGood * c.root.CFrame:ToObjectSpace(model:GetPivot()))
		stop(c.root)
		t.cargo[model] = nil
		t.kept[model] = now + TruckLoad.PutBackHoldSec
		return false
	elseif verdict == "ok" then
		c.lastGood = cf
		c.lastGoodAt = now
	end
	return true
end

local function weld(t: Truck, model: Model, zone: Zone, root: BasePart)
	GrabService.ReleasePiece(model, "welded") -- ends a dropper's keep window: it's the truck's now
	t.cargo[model] = nil -- part of the truck's assembly: it moves (and is owned) with the truck
	local w = Instance.new("WeldConstraint")
	w.Name = TruckLoad.WeldName
	w.Part0 = zone.bed
	w.Part1 = root
	w.Parent = root
	t.welds[model] = w
end

-- BedAutoWeld: welds pieces that have rested on the bed a moment; with
-- the setting off, lets go of any it welded.
local function weldPass(t: Truck, riding: { [Model]: Riding }, now: number)
	if not autoWeld() then
		for _, w in pairs(t.welds) do
			if w.Parent then
				w:Destroy()
			end
		end
		table.clear(t.welds)
		table.clear(t.still)
		return
	end
	for model, w in pairs(t.welds) do
		if model.Parent == nil or w.Parent == nil or not riding[model] then
			if w.Parent then
				w:Destroy()
			end
			t.welds[model] = nil
		end
	end
	for model, r in pairs(riding) do
		local root = model.PrimaryPart
		if t.welds[model] or not root or GrabService.HeldBy(model) ~= nil then
			t.still[model] = nil
			continue
		end
		local rel = r.zone.bed.CFrame:ToObjectSpace(root.CFrame)
		local s = t.still[model]
		if not s then
			t.still[model] = { rel = rel, at = now, since = nil }
			continue
		end
		local dt = now - s.at
		if dt <= 0 then
			continue
		end
		local reach = root.Size.Magnitude / 2
		local moved = math.max(
			(rel.Position - s.rel.Position).Magnitude,
			(rel.LookVector - s.rel.LookVector).Magnitude * reach,
			(rel.UpVector - s.rel.UpVector).Magnitude * reach
		)
		if moved / dt < TruckLoad.WeldSpeed then
			local since = s.since or s.at
			s.since = since
			if now - since >= TruckLoad.WeldRestSec then
				weld(t, model, r.zone, root)
				t.still[model] = nil
				continue
			end
		else
			s.since = nil
		end
		s.rel, s.at = rel, now
	end
	for model in pairs(t.still) do
		if not riding[model] then
			t.still[model] = nil
		end
	end
end

-- One look at a truck's load (see the header).
local function look(t: Truck, now: number)
	local model = t.model
	if model.Parent == nil then
		return
	end
	local friction = Tune.Get("BedFriction") :: number
	if t.friction ~= friction then
		TruckArt.ApplyBedFriction(model, friction)
		t.friction = friction
	end
	local riding = ridingOn(t.zones)
	local driver = t.driver
	local ownerId = t.owner.UserId
	local onLoaded = TruckLoad.Hooks.onLoaded
	for m, r in pairs(riding) do
		local held = GrabService.HeldBy(m) ~= nil
		if held then
			t.cargo[m] = nil -- GrabService has it now
		end
		if r.piece.ownerId == ownerId then
			r.piece.lastInteracted = now -- wood on its owner's bed never ages
			if not held and not loadedOnce[m] then
				loadedOnce[m] = true
				if onLoaded then
					onLoaded(t.owner, r.piece, volumeOf(m))
				end
			end
		end
		if driver and not held and not t.welds[m] and (t.kept[m] or 0) <= now then
			carry(t, m, driver, now)
		end
	end
	local keep = Tune.Get("ReleaseKeepOwnerSec") :: number
	for m, c in pairs(t.cargo) do
		if m.Parent == nil or not c.root:IsDescendantOf(m) or GrabService.HeldBy(m) ~= nil then
			t.cargo[m] = nil -- gone, or someone picked it up off the road: GrabService has it
			continue
		end
		if not judge(t, m, c, now) then
			continue
		end
		if riding[m] then
			c.leftAt = nil
		elseif c.owner then
			-- Fell off on the road: the driver keeps it a moment, then auto.
			local left = c.leftAt or now
			c.leftAt = left
			if now - left >= keep then
				GrabService.Physics.SetAuto(c.root)
				t.cargo[m] = nil
			end
		end
	end
	local chassis = model.PrimaryPart
	if driver == nil and chassis and chassis.Anchored then
		-- Parked: the load goes back to automatic.
		for m, c in pairs(t.cargo) do
			if m.Parent then
				GrabService.Physics.SetAuto(c.root)
			end
		end
		table.clear(t.cargo)
	end
	weldPass(t, riding, now)
	for m, untilAt in pairs(t.kept) do
		if untilAt <= now or m.Parent == nil then
			t.kept[m] = nil
		end
	end
	t.riding = riding
end

-- The HUD's numbers, on the truck and its owner (only when they change).
local function publish(t: Truck)
	local volume, value = 0, 0
	for m in pairs(t.riding) do
		if m.Parent then
			volume += volumeOf(m)
			value += valueOf(m)
		end
	end
	local room, length = 0, 0
	for _, z in ipairs(t.zones) do
		local r = z.zone:GetAttribute("Room")
		if type(r) == "number" then
			room += r
		end
		local l = z.zone:GetAttribute("Length")
		if type(l) == "number" then
			length = math.max(length, l)
		end
	end
	local numbers: { [string]: number } = {
		BedVolume = math.floor(volume * 10 + 0.5) / 10,
		BedValue = math.floor(value + 0.5),
		BedRoom = math.floor(room * 10 + 0.5) / 10,
		BedLength = length,
	}
	for name, n in pairs(numbers) do
		if t.shown[name] ~= n then
			t.shown[name] = n
			if t.model.Parent then
				t.model:SetAttribute(name, n)
			end
			t.owner:SetAttribute(name, n)
		end
	end
end

---------------------------------------------------------------------------
-- Saving and rebuilding
---------------------------------------------------------------------------

-- Which ends of `section` show a cut face (LeftLoad: 1 = +Y, 2 = -Y).
local function facesOn(section: BasePart, faces: { BasePart }): number
	local flags = 0
	local h = section.Size / 2
	for _, f in ipairs(faces) do
		local p = section.CFrame:PointToObjectSpace(f.CFrame.Position)
		if math.abs(p.X) <= h.X + 0.01 and math.abs(p.Z) <= h.Z + 0.01 then
			if p.Y >= h.Y - 0.2 and p.Y <= h.Y + 0.3 then
				flags = bit32.bor(flags, 1)
			elseif p.Y <= -h.Y + 0.2 and p.Y >= -h.Y - 0.3 then
				flags = bit32.bor(flags, 2)
			end
		end
	end
	return flags
end

-- `model` (a piece riding on `bed`) as a save record (LeftLoad.Piece), or
-- nil when it can't be saved (no root, an unknown wood, a strange bed,
-- more sections than the save holds). Its sections are the parts named
-- "Section", its root (PrimaryPart) first.
function TruckLoad.Snapshot(model: Model, bed: BasePart): SavedPiece?
	if not LeftLoad.Beds[bed.Name] then
		return nil
	end
	return TruckLoad.SnapshotAt(model, bed.CFrame, bed.Name)
end

-- `model` as a save record placed relative to `ref` (a bed's CFrame, or
-- for wood on the ground the spot it lies at), its `bed` named `bedName`.
function TruckLoad.SnapshotAt(model: Model, ref: CFrame, bedName: string): SavedPiece?
	local root = model.PrimaryPart
	local woodId = attrString(model, "WoodId")
	if not root or not woodId or not WoodData.Get(woodId) then
		return nil
	end
	local sections: { BasePart } = { root }
	local faces: { BasePart } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			if d.Name == "Section" then
				table.insert(sections, d)
			elseif d.Name == "CutFace" then
				table.insert(faces, d)
			end
		end
	end
	if #sections > GameConfig.MaxSavedSections then
		return nil
	end
	local s: { { number } } = {}
	for _, part in ipairs(sections) do
		table.insert(s, LeftLoad.EncodeSection(part.Size, root.CFrame:ToObjectSpace(part.CFrame), facesOn(part, faces)))
	end
	local boost = attrNumber(model, "Boost")
	return {
		w = woodId,
		k = if model:GetAttribute("Kind") == "plank" then "plank" else "log",
		f = attrString(model, "Figure"),
		x = if boost and boost > 1 then boost else nil,
		bed = bedName,
		at = LeftLoad.EncodeCFrame(ref:ToObjectSpace(root.CFrame)),
		s = s,
	}
end

type Entry = { saved: SavedPiece, model: Model, value: number, uid: string }

-- What the save keeps of `riding` (the pieces on `player`'s beds): their
-- own and unowned pieces nobody else holds, the most valuable first,
-- capped (LeftLoad.Fit). The records, and their models in the same order.
local function keepable(player: Player, riding: { [Model]: Riding }): ({ SavedPiece }, { Model })
	local entries: { Entry } = {}
	for m, r in pairs(riding) do
		local owner = r.piece.ownerId
		local holder = GrabService.HeldBy(m)
		if m.Parent and (owner == 0 or owner == player.UserId) and (holder == nil or holder == player) then
			local saved = TruckLoad.Snapshot(m, r.zone.bed)
			if saved then
				local uid = m:GetAttribute("Uid")
				table.insert(entries, {
					saved = saved,
					model = m,
					value = valueOf(m),
					uid = if type(uid) == "string" then uid else m.Name,
				})
			end
		end
	end
	table.sort(entries, function(a: Entry, b: Entry): boolean
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.uid < b.uid
	end)
	local list: { SavedPiece } = {}
	for i, e in ipairs(entries) do
		list[i] = e.saved
	end
	local kept = LeftLoad.Fit(list)
	local isKept: { [SavedPiece]: boolean } = {}
	for _, p in ipairs(kept) do
		isKept[p] = true
	end
	local models: { Model } = {}
	for _, e in ipairs(entries) do
		if isKept[e.saved] then
			table.insert(models, e.model)
		end
	end
	return kept, models
end

local function riderOf(player: Player): { [Model]: Riding }
	local d = deps
	local model = if d then d.truckOf(player) else nil
	return if model then ridingOn(zonesOf(model)) else {}
end

-- Saves what rides on `player`'s beds into profile.truckLoad (see the
-- header). Returns how many pieces it saved.
function TruckLoad.Save(player: Player): number
	local d = deps
	local profile = if d then d.profileOf(player) else nil
	if not profile then
		return 0
	end
	local kept = keepable(player, riderOf(player))
	profile.truckLoad = kept
	return #kept
end

-- The colour of `wood`'s bark (its v2 shape's, else today's trunk).
local function barkOf(wood: WoodData.WoodDef): Color3
	local v2 = wood.v2
	local shape = if v2 then v2.shape else nil
	if shape then
		return Color3.fromHex(shape.bark)
	end
	return wood.trunkColor
end

-- The default rebuild of a saved piece (until WoodService does it): its
-- sections as blocks of its bark, each welded to the first, with their cut
-- faces (TreeArt.CutFace), the attributes SellService and the HUD read,
-- tagged Wood in the Wood folder at `cf`, and registered with
-- GrabService: `owner`'s, anyone's to grab after `graceSec`.
function TruckLoad.Build(saved: SavedPiece, owner: Player, cf: CFrame, graceSec: number): Model?
	local d = deps
	local wood = WoodData.Get(saved.w)
	if not d or not wood then
		return nil
	end
	local physics = PhysicalProperties.new(
		Tune.Get("WoodDensity") :: number,
		Tune.Get("WoodFriction") :: number,
		Tune.Get("WoodElasticity") :: number
	)
	local uid = Util.guid()
	local model = Instance.new("Model")
	model.Name = "Wood_" .. uid
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local kind: SellLogic.Kind = if saved.k == "plank" then "plank" else "log"
	local color, material = barkOf(wood), Enum.Material.Wood
	if kind == "plank" then
		color, material = TreeArt.Core(wood)
	end
	local root: BasePart? = nil
	local volume = 0
	for i, raw in ipairs(saved.s) do
		local size, rel, faces = LeftLoad.DecodeSection(raw)
		if not size or not rel then
			continue
		end
		local part = Instance.new("Part")
		part.Name = "Section"
		part.Size = size
		part.CFrame = rel
		part.Material = material
		part.Color = color
		part.Anchored = false
		part.CanCollide = true
		part.CanQuery = true
		part.CanTouch = false
		part.CustomPhysicalProperties = physics
		part:SetAttribute("Section", i)
		part:AddTag("WoodSection")
		part.Parent = model
		local first = root
		if first then
			local w = Instance.new("WeldConstraint")
			w.Part0 = first
			w.Part1 = part
			w.Parent = part
		else
			root = part
			model.PrimaryPart = part
		end
		if kind ~= "plank" and bit32.band(faces, 1) ~= 0 then
			TreeArt.CutFace(wood, part, true)
		end
		if kind ~= "plank" and bit32.band(faces, 2) ~= 0 then
			TreeArt.CutFace(wood, part, false)
		end
		volume += SellLogic.VolumeU3(size.X, size.Y, size.Z)
	end
	if not root then
		model:Destroy()
		return nil
	end
	local value = SellLogic.PieceValue(wood.id, kind, volume, saved.f, saved.x)
	model:AddTag("Wood")
	model:SetAttribute("Uid", uid)
	model:SetAttribute("Owner", owner.UserId)
	model:SetAttribute("WoodId", wood.id)
	model:SetAttribute("Kind", kind)
	model:SetAttribute("Volume", math.floor(volume * 100 + 0.5) / 100)
	model:SetAttribute("Value", math.floor(value * 100 + 0.5) / 100)
	if saved.f then
		model:SetAttribute("Figure", saved.f)
	end
	if saved.x then
		model:SetAttribute("Boost", saved.x)
	end
	model:SetAttribute("HeldBy", 0)
	model:PivotTo(cf)
	model.Parent = d.woodFolder
	local now = clock()
	GrabService.Register({
		model = model,
		ownerId = owner.UserId,
		createdAt = now - GameConfig.PickupGraceSec + math.max(0, graceSec),
		lastInteracted = now,
	})
	return model
end

-- Moves a riding piece onto zone `z` of a new truck, at `rel` from its bed
-- (kept over the bed), stopped, physics back to automatic.
local function place(model: Model, z: Zone, rel: CFrame)
	local root = model.PrimaryPart
	if not root then
		return
	end
	local target = z.bed.CFrame * TruckLoad.ClampOnto(rel, z.zone.Size) + Vector3.new(0, TruckLoad.Lift, 0)
	GrabService.ReleasePiece(model, "moved") -- not held (checked); a keep window would judge the move a teleport
	unweldModel(model)
	model:PivotTo(target * root.CFrame:ToObjectSpace(model:GetPivot()))
	stop(root)
	GrabService.Physics.SetAuto(root)
	loadedOnce[model] = true
	local d = deps
	if d and d.moved then
		d.moved(model)
	end
end

-- Rebuilds a saved load for `player` with their new truck `truck`: on its
-- beds (`keepsLoad`), or on the ground where the old one stood (`at`).
local function restore(player: Player, truck: Model, pieces: { SavedPiece }, keepsLoad: boolean, at: CFrame?): number
	local d = deps
	if not d then
		return 0
	end
	local build: (SavedPiece, Player, CFrame, number) -> Model? = d.build or TruckLoad.Build
	local zones = byBed(zonesOf(truck))
	local pivot = truck:GetPivot()
	local grace = if keepsLoad then 0 else GameConfig.LeftLoadGraceSec
	local n = 0
	for _, p in ipairs(pieces) do
		local rel = LeftLoad.DecodeCFrame(p.at)
		if not rel then
			continue
		end
		local z = zones[p.bed] or zones.BedFloor or zones.TrailerBed
		local cf: CFrame
		if keepsLoad and z then
			cf = z.bed.CFrame * TruckLoad.ClampOnto(rel, z.zone.Size) + Vector3.new(0, TruckLoad.Lift, 0)
		else
			-- Where the truck stood (facing -Z), the bed where this truck's
			-- is: the load settles to the ground there.
			local bedOnTruck = if z then pivot:ToObjectSpace(z.bed.CFrame) else CFrame.new(0, 3, 0)
			cf = CFrame.new((at or pivot).Position) * bedOnTruck * rel
		end
		local model = build(p, player, cf, grace)
		if model then
			loadedOnce[model] = true
			n += 1
			if not keepsLoad then
				trackLeft(player.UserId, model)
			end
		end
	end
	local profile = d.profileOf(player)
	if profile then
		profile.truckLoad = {} -- rebuilt: saved again as it rides
	end
	if n > 0 and not keepsLoad and d.notify then
		d.notify(player, TruckLoad.LeftText)
	end
	return n
end

---------------------------------------------------------------------------
-- VehicleService's hooks
---------------------------------------------------------------------------

-- The owner sat in the driver seat (`driver`) or got out (nil).
function TruckLoad.OnDriverChanged(truck: Model, driver: Player?)
	local t = stateOf(truck)
	if not t then
		return
	end
	local now = clock()
	t.driver = driver
	if driver then
		look(t, now)
	else
		-- The truck settles on the server: its load goes with it.
		for m, c in pairs(t.cargo) do
			if m.Parent and GrabService.HeldBy(m) == nil then
				GrabService.Physics.SetOwner(c.root, nil)
				c.owner = nil
				c.leftAt = nil
			else
				t.cargo[m] = nil -- gone, or GrabService has it
			end
		end
	end
	t.nextAt = now + TruckLoad.DrivenPollSec
end

-- A truck is about to be built for `player` (VehicleService.Hooks.onRebuild).
function TruckLoad.OnRebuild(player: Player, old: Model?, keepsLoad: boolean, at: CFrame?): ((Model) -> ())?
	local d = deps
	if not d then
		return nil
	end
	if old then
		local riding = ridingOn(zonesOf(old))
		local t = trucks[player]
		if t and t.model == old then
			release(t)
			trucks[player] = nil
		end
		for m in pairs(riding) do
			unweldModel(m) -- its bed is going
		end
		if not keepsLoad then
			-- Out of town: the load stays where it is (it settles to the
			-- ground as the truck goes), the player's alone for
			-- LeftLoadGraceSec, as a v1 load left behind is.
			local now = clock()
			local mine = 0
			for _, r in pairs(riding) do
				local piece = r.piece
				if piece.ownerId == player.UserId then
					piece.createdAt =
						math.max(piece.createdAt, now - GameConfig.PickupGraceSec + GameConfig.LeftLoadGraceSec)
					piece.lastInteracted = now
					mine += 1
					trackLeft(player.UserId, piece.model)
				end
			end
			if mine > 0 and d.notify then
				d.notify(player, TruckLoad.LeftBehindText)
			end
			return nil
		end
		type Move = { model: Model, bed: string, rel: CFrame }
		local moving: { Move } = {}
		for m, r in pairs(riding) do
			local root = m.PrimaryPart
			if root and GrabService.HeldBy(m) == nil then
				table.insert(
					moving,
					{ model = m, bed = r.zone.bed.Name, rel = r.zone.bed.CFrame:ToObjectSpace(root.CFrame) }
				)
			end
		end
		if #moving == 0 then
			return nil
		end
		return function(truck: Model)
			local zones = byBed(zonesOf(truck))
			for _, mv in ipairs(moving) do
				local z = zones[mv.bed] or zones.BedFloor or zones.TrailerBed
				if mv.model.Parent and z then
					place(mv.model, z, mv.rel)
				end
			end
		end
	end
	-- Joining: wood left on the ground last time comes back where it lay.
	local profile = d.profileOf(player)
	if profile then
		TruckLoad.RestoreGround(player, profile)
	end
	-- And the load saved last time.
	local saved = if profile then profile.truckLoad else nil
	if type(saved) ~= "table" or #saved == 0 then
		return nil
	end
	local pieces, dropped = LeftLoad.PiecesToRestore(saved, function(id: string): boolean
		return WoodData.Get(id) ~= nil
	end)
	if dropped > 0 then
		warn(string.format("[TruckLoad] %s: %d saved piece(s) couldn't be rebuilt", player.Name, dropped))
	end
	return function(truck: Model)
		restore(player, truck, pieces, keepsLoad, at)
	end
end

TruckLoad.GroundText = "Your logs are still where you left them."

-- Rebuilds `profile.groundLoad` (wood left on the ground when `player`
-- last left) where each piece lay, theirs for LeftLoadGraceSec, and
-- empties it. Returns how many came back.
function TruckLoad.RestoreGround(player: Player, profile: any): number
	local d = deps
	local saved = profile.groundLoad
	if not d or type(saved) ~= "table" or #saved == 0 then
		return 0
	end
	local pieces, dropped = LeftLoad.GroundToRestore(saved, function(id: string): boolean
		return WoodData.Get(id) ~= nil
	end)
	if dropped > 0 then
		warn(string.format("[TruckLoad] %s: %d saved ground piece(s) couldn't be rebuilt", player.Name, dropped))
	end
	local build: (SavedPiece, Player, CFrame, number) -> Model? = d.build or TruckLoad.Build
	local n = 0
	for _, g in ipairs(pieces) do
		local turn = LeftLoad.DecodeCFrame(g.piece.at)
		if turn then
			local model = build(g.piece, player, CFrame.new(g.spot) * turn, GameConfig.LeftLoadGraceSec)
			if model then
				n += 1
				trackLeft(player.UserId, model)
			end
		end
	end
	profile.groundLoad = {}
	if n > 0 and d.notify then
		d.notify(player, TruckLoad.GroundText)
	end
	return n
end

-- What of `player`'s left-behind wood to save as groundLoad (still theirs,
-- lying about, not held by anyone else, not on someone's bed, not already
-- saved with the bed), the most valuable first, capped; and those models.
local function groundKeepable(player: Player, savedWithBed: { [Model]: boolean }): ({ any }, { Model })
	local set = leftOf[player.UserId]
	if not set then
		return {}, {}
	end
	type GroundEntry = { saved: SavedPiece, model: Model, value: number, uid: string }
	local entries: { GroundEntry } = {}
	for m in pairs(set) do
		local root = m.PrimaryPart
		if m.Parent == nil or root == nil or savedWithBed[m] then
			continue
		end
		local piece = GrabService.PieceOf(root)
		local holder = GrabService.HeldBy(m)
		if not piece or piece.ownerId ~= player.UserId or (holder ~= nil and holder ~= player) then
			continue
		end
		if TruckLoad.BedOwner(piece :: any) ~= nil then
			continue -- riding on a truck: that's the truck's to save
		end
		local spot = root.CFrame.Position
		local saved = TruckLoad.SnapshotAt(m, CFrame.new(spot), LeftLoad.GroundBed)
		if saved then
			local record = saved :: any
			record.g = {
				math.floor(spot.X * 100 + 0.5) / 100,
				math.floor(spot.Y * 100 + 0.5) / 100,
				math.floor(spot.Z * 100 + 0.5) / 100,
			}
			local uid = m:GetAttribute("Uid")
			table.insert(entries, {
				saved = saved,
				model = m,
				value = valueOf(m),
				uid = if type(uid) == "string" then uid else m.Name,
			})
		end
	end
	table.sort(entries, function(a: GroundEntry, b: GroundEntry): boolean
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.uid < b.uid
	end)
	local list: { SavedPiece } = {}
	for i, e in ipairs(entries) do
		list[i] = e.saved
	end
	local kept = LeftLoad.Fit(list)
	local isKept: { [SavedPiece]: boolean } = {}
	for _, p in ipairs(kept) do
		isKept[p] = true
	end
	local models: { Model } = {}
	for _, e in ipairs(entries) do
		if isKept[e.saved] then
			table.insert(models, e.model)
		end
	end
	return kept :: { any }, models
end

-- How many pieces ride on `truck`'s beds (Recall's warning).
function TruckLoad.LoadCount(truck: Model): number
	local n = 0
	for _ in pairs(ridingOn(zonesOf(truck))) do
		n += 1
	end
	return n
end

---------------------------------------------------------------------------
-- Everyone else's questions
---------------------------------------------------------------------------

-- Whose truck bed `piece` rests on, if anyone's (GrabService's bedOwner).
function TruckLoad.BedOwner(piece: Piece): Player?
	local d = deps
	local model = piece.model
	if not d or model.Parent == nil then
		return nil
	end
	local centre = TruckLoad.Centre(model)
	if not centre then
		return nil
	end
	for _, player in ipairs(online()) do
		local truck = d.truckOf(player)
		if truck then
			for _, z in ipairs(zonesOf(truck)) do
				if TruckLoad.Inside(z.zone.CFrame, z.zone.Size, centre) then
					return player
				end
			end
		end
	end
	return nil
end

-- The pieces riding on `player`'s beds that nobody holds, right now
-- (Instant Delivery: SellService.SellBed).
function TruckLoad.PiecesOn(player: Player): { Model }
	local out: { Model } = {}
	for m in pairs(riderOf(player)) do
		if GrabService.HeldBy(m) == nil then
			table.insert(out, m)
		end
	end
	table.sort(out, function(a: Model, b: Model): boolean
		return a.Name < b.Name
	end)
	return out
end

-- GrabService's beforeHold: a piece TruckLoad welded lets go of the bed.
function TruckLoad.Unweld(_player: Player, piece: Piece)
	local model = piece.model
	for _, t in pairs(trucks) do
		local w = t.welds[model]
		if w then
			t.welds[model] = nil
			t.still[model] = nil
			if w.Parent then
				w:Destroy()
			end
		end
	end
	unweldModel(model)
end

---------------------------------------------------------------------------
-- The loop
---------------------------------------------------------------------------

-- One pass over every player's truck that's due (see the header).
function TruckLoad.Tick()
	local d = deps
	if not d then
		return
	end
	local now = clock()
	local here: { [Player]: boolean } = {}
	for _, player in ipairs(online()) do
		here[player] = true
		local t = truckFor(player)
		if not t or now < t.nextAt then
			continue
		end
		look(t, now)
		t.nextAt = now + (if t.driver then TruckLoad.DrivenPollSec else TruckLoad.ParkedPollSec)
		if now >= t.publishAt then
			publish(t)
			t.publishAt = now + TruckLoad.PublishSec
		end
		local count, volume = 0, 0
		for m in pairs(t.riding) do
			count += 1
			volume += volumeOf(m)
		end
		local key = string.format("%d:%.2f", count, volume)
		if key ~= t.loadKey or now >= t.saveAt then
			t.loadKey = key
			t.saveAt = now + TruckLoad.SaveEverySec
			local profile = d.profileOf(player)
			if profile then
				profile.truckLoad = keepable(player, t.riding)
			end
		end
	end
	for player, t in pairs(trucks) do
		if not here[player] then
			release(t)
			trucks[player] = nil
		end
	end
	for m in pairs(loadedOnce) do
		if m.Parent == nil then
			loadedOnce[m] = nil
		end
	end
end

-- `player` is leaving: their load is saved (TruckLoad.Save's rules) and
-- the saved pieces leave the world with them. Call before the final save.
function TruckLoad.PlayerRemoving(player: Player)
	local d = deps
	local profile = if d then d.profileOf(player) else nil
	if d and profile then
		local kept, models = keepable(player, riderOf(player))
		profile.truckLoad = kept
		local withBed: { [Model]: boolean } = {}
		for _, m in ipairs(models) do
			withBed[m] = true
		end
		local ground, groundModels = groundKeepable(player, withBed)
		profile.groundLoad = ground
		for _, list in ipairs({ models, groundModels }) do
			for _, m in ipairs(list) do
				GrabService.ReleasePiece(m, "left")
				if d.forget then
					d.forget(m)
				end
				m:Destroy()
			end
		end
	end
	leftOf[player.UserId] = nil
	local t = trucks[player]
	if t then
		release(t)
		trucks[player] = nil
	end
end

local function hookUp(newDeps: Deps)
	deps = newDeps
	query = nil
	table.clear(trucks)
	table.clear(loadedOnce)
	table.clear(leftOf)
	GrabService.Hooks.bedOwner = TruckLoad.BedOwner
	GrabService.Hooks.beforeHold = TruckLoad.Unweld
end

local running = false

-- Starts watching every player's truck (GameServer, under the v2 loop).
function TruckLoad.Init(newDeps: Deps)
	hookUp(newDeps)
	if running then
		return
	end
	running = true
	task.spawn(function()
		while running do
			task.wait(TruckLoad.DrivenPollSec)
			local ok, err = pcall(function(): any
				TruckLoad.Tick()
				return nil
			end)
			if not ok then
				warn("[TruckLoad] tick failed: " .. tostring(err))
			end
		end
	end)
end

-- For the specs: start without the polling loop.
function TruckLoad._use(newDeps: Deps)
	hookUp(newDeps)
end

return TruckLoad
