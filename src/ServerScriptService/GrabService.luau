--!strict
-- GrabService: holding loose wood in the v2 core loop (V2_PLAN.md §4a). The
-- holder's device does the dragging (DragController: its own AlignPosition
-- and AlignOrientation on the piece); this decides who may hold what and
-- keeps them honest. GameServer starts it only when the v2 loop runs
-- (Shared/CoreLoop), and Grab refuses everything under the v1 loop anyway.
--
-- Grab(part, hitPos), checked in this order: the rate (RateLimiter),
-- the arguments' types, a live character that isn't sitting, a known
-- piece (the resolver: WoodService's records once they exist, until then
-- the pieces registered here, the Studio /spawnwood ones), the hit point
-- on the part it names (GrabLogic.ClampToBox: it may have moved a little),
-- within GrabRange (+ RangeTolerance) of the character, and
-- GrabLogic.CanGrab (dead, selling, held, someone's truck bed, plot
-- permission, someone else's wood while they're here, the cutter's
-- PickupGraceSec once they've left). Then:
--   * the piece's physics goes to the holder's device (SetNetworkOwner),
--   * its parts join the WoodHeld collision group (it passes through
--     players, so nobody can ride their own log),
--   * HeldBy (their UserId) and GrabPoint (where they hold it, in its
--     PrimaryPart's space) go on the model, for everyone's ball,
--   * the record's lastHolderId and lastInteracted are set, and unowned
--     wood becomes the holder's (GrabLogic.NewOwner).
-- One piece per player: grabbing another lets go of the first.
--
-- Letting go (Release, or forced: death, leaving, sitting down, the piece
-- sold, cut or gone) puts the groups and attributes back. The dropper's
-- device keeps simulating it for ReleaseKeepOwnerSec (no stutter as it
-- falls), then ownership goes back to automatic. Someone who leaves hands
-- it straight back.
--
-- Watch (every WoodJudgeEvery seconds) is the held-wood sanity check:
-- every piece a player's device simulates (held, or in that keep window)
-- is judged with VehicleLogic.JudgeMove against WoodMaxSpeed. A piece that
-- moved further than anything can is put back where it last was, stopped,
-- and kept by the server for PutBackHoldSec. A held piece further than
-- ReleaseDistance (+ tolerance) from its holder, or a holder who died or
-- sat down, lets go.
--
-- Under v2 every character's parts are in the Players collision group
-- (WoodHeld doesn't collide with it).
--
-- Once WoodService runs (M1.3), its WoodWatch judges every piece a
-- player's device simulates, held ones included, and GameServer sets
-- GrabService.JudgeMoves = false so pieces aren't judged twice: Watch then
-- keeps only the hold's own checks (gone, died, seated, too far away).

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local GrabLogic = require(ReplicatedStorage.Shared.GrabLogic)
local Tune = require(ReplicatedStorage.Shared.Tune)
local VehicleLogic = require(ReplicatedStorage.Shared.VehicleLogic)
local RateLimiter = require(script.Parent.RateLimiter)

local GrabService = {}

GrabService.HeldGroup = "WoodHeld" -- held wood: doesn't collide with players
GrabService.PlayersGroup = "Players" -- every character's parts (v2)

-- Who's in the server, by UserId (a seam for the specs): someone else's
-- wood is theirs only while they're here (GrabLogic.CanGrab).
function GrabService.PlayerById(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end
GrabService.HitMargin = 2 -- studs: a grab may land this far off its part (the piece moved meanwhile)
GrabService.PutBackHoldSec = 1 -- a piece put back stays the server's this long
GrabService.JudgeMoves = true -- false: WoodService's WoodWatch judges moves instead

-- What GrabService needs of a piece's record (WoodService's records have
-- all of it). Times are the server's os.clock().
export type Piece = {
	model: Model, -- tagged "Wood", PrimaryPart set, every part welded to it
	ownerId: number, -- 0 = nobody
	createdAt: number,
	lastHolderId: number?,
	lastInteracted: number?,
	dead: boolean?,
	selling: boolean?,
	elder: boolean?,
	shopItem: boolean?,
	shopBox: boolean?,
}

-- Hooks for later slices. bedOwner: the player whose truck bed the piece
-- rests on (TruckLoad, M1.6); permission: false when plot permissions
-- forbid this player (M3); beforeHold: a grab that passed every check,
-- just before the piece's physics goes to the holder (TruckLoad lets go
-- of a piece it welded to a bed); onGrab / onRelease: tutorial and quest
-- events.
export type ShopGrab = {
	claimUserId: number?,
	claimUntil: number?,
	paid: boolean?,
	buyerId: number?,
	unpaidByPlayer: number?,
	unpaidOnServer: number?,
	taking: boolean?,
}

export type Hooks = {
	bedOwner: ((Piece) -> Player?)?,
	permission: ((Player, Piece) -> boolean?)?,
	beforeHold: ((Player, Piece) -> ())?,
	onGrab: ((Player, Piece) -> ())?,
	onRelease: ((Player, Piece, string) -> ())?,
	onRefused: ((Player, Piece, string) -> ())?, -- a grab that passed every check but could not take the piece's physics
	shopFacts: ((Player, Piece) -> ShopGrab?)?,
}
GrabService.Hooks = {} :: Hooks

-- Network ownership, behind a seam: Lune, which runs the specs, has no
-- physics. SetOwner returns false when the engine refuses (an anchored
-- piece, or one welded to something anchored).
GrabService.Physics = {
	SetOwner = function(part: BasePart, player: Player?): boolean
		local ok = pcall(function(): any
			part:SetNetworkOwner(player)
			return nil
		end)
		return ok
	end,
	SetAuto = function(part: BasePart)
		pcall(function(): any
			part:SetNetworkOwnershipAuto()
			return nil
		end)
	end,
}

type Hold = {
	player: Player,
	piece: Piece,
	root: BasePart, -- the PrimaryPart: the assembly's ownership and position
	grip: Vector3, -- where it's held, in root space
	groups: { [BasePart]: string }, -- each part's collision group before the grab
	lastGood: CFrame, -- the root where it was last accepted (Watch)
	lastGoodAt: number,
}

-- A piece let go of but still simulated by its dropper's device (judged,
-- until untilAt), or put back and kept by the server (not judged).
type Loose = {
	player: Player?,
	root: BasePart,
	lastGood: CFrame,
	lastGoodAt: number,
	untilAt: number,
	judge: boolean,
}

local holds: { [Player]: Hold } = {}
local holdOf: { [Model]: Hold } = {}
local loose: { [Model]: Loose } = {}
local registry: { [Model]: Piece } = {}
local groupsReady = false
local started = false
local notify: (Player, string) -> () = function(_player: Player, _message: string) end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

-- The registered piece a part belongs to (its model, or a few levels up).
local function registered(part: BasePart): Piece?
	local node: Instance? = part.Parent
	for _ = 1, 4 do
		if node == nil then
			return nil
		end
		if node:IsA("Model") then
			local piece = registry[node]
			if piece then
				return piece
			end
		end
		node = node.Parent
	end
	return nil
end

local resolve: (BasePart) -> Piece? = registered

-- Where pieces come from: WoodService's FromPart once it exists. nil puts
-- back the default (pieces registered here).
function GrabService.SetResolver(fn: ((BasePart) -> Piece?)?)
	resolve = fn or registered
end

-- Look here before the current resolver. A later SetResolver replaces
-- both, so call this after that (BoxService does, once the wood resolver
-- is installed).
function GrabService.ChainResolver(fn: (BasePart) -> Piece?)
	local inner = resolve
	resolve = function(part: BasePart): Piece?
		local found = fn(part)
		if found then
			return found
		end
		return inner(part)
	end
end

-- The piece `part` belongs to, through the current resolver (SellService
-- and TruckLoad find pieces this way), or nil.
function GrabService.PieceOf(part: BasePart): Piece?
	return resolve(part)
end

-- A piece GrabService knows without WoodService (Studio's /spawnwood).
function GrabService.Register(piece: Piece)
	registry[piece.model] = piece
end

function GrabService.Unregister(model: Model)
	registry[model] = nil
end

-- Who holds `model` right now, if anyone.
function GrabService.HeldBy(model: Model): Player?
	local h = holdOf[model]
	return if h then h.player else nil
end

-- The piece `player` holds, if any.
function GrabService.Holding(player: Player): Model?
	local h = holds[player]
	return if h then h.piece.model else nil
end

---------------------------------------------------------------------------
-- Collision groups
---------------------------------------------------------------------------

local function registerGroups(): boolean
	local ok, err = pcall(function(): any
		for _, name in ipairs({ GrabService.HeldGroup, GrabService.PlayersGroup }) do
			if not PhysicsService:IsCollisionGroupRegistered(name) then
				PhysicsService:RegisterCollisionGroup(name)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(GrabService.HeldGroup, GrabService.PlayersGroup, false)
		return nil
	end)
	if not ok then
		warn("[GrabService] Collision groups failed: " .. tostring(err))
	end
	return ok
end

-- Puts every part of `model` in WoodHeld; returns their groups before.
local function joinHeld(model: Model): { [BasePart]: string }
	local groups: { [BasePart]: string } = {}
	if not groupsReady then
		return groups
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			groups[d] = d.CollisionGroup
			d.CollisionGroup = GrabService.HeldGroup
		end
	end
	return groups
end

local function leaveHeld(groups: { [BasePart]: string })
	for part, group in pairs(groups) do
		if part.Parent and part.CollisionGroup == GrabService.HeldGroup then
			part.CollisionGroup = group
		end
	end
end

-- Puts a character's parts (and any added later) in the Players group.
function GrabService.JoinPlayers(character: Model)
	if not groupsReady then
		return
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = GrabService.PlayersGroup
		end
	end
end

---------------------------------------------------------------------------
-- Holding and letting go
---------------------------------------------------------------------------

-- The character's root part and humanoid while it's alive, else nils.
local function body(player: Player): (BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hrp:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return hrp, humanoid
end

local function finiteVector(v: Vector3): boolean
	return VehicleLogic.Finite(v)
end

local function stop(root: BasePart)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- "keep": the dropper's device keeps it for ReleaseKeepOwnerSec (judged);
-- "server": the server keeps it for PutBackHoldSec; "auto": back to
-- automatic now; "none": it's gone, nothing to hand back.
type How = "keep" | "server" | "auto" | "none"

local function finish(h: Hold, reason: string, how: How)
	local model = h.piece.model
	local now = os.clock()
	if holds[h.player] == h then
		holds[h.player] = nil
	end
	if holdOf[model] == h then
		holdOf[model] = nil
	end
	leaveHeld(h.groups)
	if model.Parent then
		model:SetAttribute("HeldBy", 0)
		model:SetAttribute("GrabPoint", nil)
	end
	h.piece.lastInteracted = now
	if how == "keep" then
		loose[model] = {
			player = h.player,
			root = h.root,
			lastGood = h.lastGood,
			lastGoodAt = h.lastGoodAt,
			untilAt = now + (Tune.Get("ReleaseKeepOwnerSec") :: number),
			judge = true,
		}
	elseif how == "server" then
		GrabService.Physics.SetOwner(h.root, nil)
		loose[model] = {
			player = nil,
			root = h.root,
			lastGood = h.lastGood,
			lastGoodAt = now,
			untilAt = now + GrabService.PutBackHoldSec,
			judge = false,
		}
	elseif how == "auto" then
		loose[model] = nil
		GrabService.Physics.SetAuto(h.root)
	else
		loose[model] = nil
	end
	local onRelease = GrabService.Hooks.onRelease
	if onRelease then
		onRelease(h.player, h.piece, reason)
	end
end

-- Takes a piece back from a device that moved it further than anything
-- can (an exploiter teleporting wood): back where it was last accepted,
-- stopped, simulated by the server for a moment.
local function putBack(model: Model, root: BasePart, lastGood: CFrame, who: string, moved: number, dt: number)
	warn(string.format("[AntiExploit] %s's wood moved %d studs in %.1fs; putting it back", who, math.floor(moved), dt))
	GrabService.Physics.SetOwner(root, nil)
	model:PivotTo(lastGood)
	stop(root)
end

-- Lets go of whatever `player` holds (forced: died, seated, left...).
function GrabService.ReleasePlayer(player: Player, reason: string)
	local h = holds[player]
	if h then
		finish(h, reason, if reason == "left" then "auto" else "keep")
	end
end

-- Lets go of `model` whoever holds it: it's being sold or cut.
function GrabService.ReleasePiece(model: Model, reason: string?)
	local h = holdOf[model]
	if h then
		finish(h, reason or "taken", "auto")
	end
	loose[model] = nil
end

-- The Grab remote: see the header. Returns whether it's held now, and
-- why not.
function GrabService.Grab(player: Player, part: unknown, hitPos: unknown): (boolean, string?)
	if not CoreLoop.V2() then
		return false, "off"
	end
	if not RateLimiter.Allow(player, "Grab") then
		return false, "rate"
	end
	if typeof(part) ~= "Instance" or typeof(hitPos) ~= "Vector3" then
		return false, "bad"
	end
	local inst = part :: Instance
	local hit = hitPos :: Vector3
	if not inst:IsA("BasePart") or not finiteVector(hit) then
		return false, "bad"
	end
	local basePart = inst :: BasePart
	local hrp, humanoid = body(player)
	if not hrp or not humanoid then
		return false, "dead"
	end
	if humanoid.SeatPart ~= nil then
		return false, "seated"
	end
	local piece = resolve(basePart)
	local model = if piece then piece.model else nil
	local root = if model then model.PrimaryPart else nil
	if not piece or not model or not root or not basePart:IsDescendantOf(model) then
		return false, "unknown"
	end
	local grip = GrabLogic.ClampToBox(basePart.CFrame, basePart.Size, hit, GrabService.HitMargin)
	if not grip then
		return false, "bad"
	end
	local reach = (Tune.Get("GrabRange") :: number) + GameConfig.RangeTolerance
	if (grip - hrp.Position).Magnitude > reach then
		notify(player, GrabLogic.Message("far") :: string)
		return false, "far"
	end
	local now = os.clock()
	local current = holdOf[model]
	local hooks = GrabService.Hooks
	local bedOwner = if hooks.bedOwner then hooks.bedOwner(piece) else nil
	local ownerPlayer = if piece.ownerId ~= 0 then GrabService.PlayerById(piece.ownerId) else nil
	local facts: GrabLogic.Facts = {
		userId = player.UserId,
		ownerId = piece.ownerId,
		createdAt = piece.createdAt,
		now = now,
		heldBy = if current then current.player.UserId else 0,
		dead = piece.dead,
		selling = piece.selling,
		elder = piece.elder,
		shopItem = piece.shopItem,
		shopBox = piece.shopBox,
		bedOwnerId = if bedOwner then bedOwner.UserId else nil,
		ownerHere = ownerPlayer ~= nil,
		plotAllows = if hooks.permission then hooks.permission(player, piece) else nil,
	}
	if piece.shopBox and hooks.shopFacts then
		local extra = hooks.shopFacts(player, piece)
		if extra then
			facts.claimUserId = extra.claimUserId
			facts.claimUntil = extra.claimUntil
			facts.paid = extra.paid
			facts.buyerId = extra.buyerId
			facts.unpaidByPlayer = extra.unpaidByPlayer
			facts.unpaidOnServer = extra.unpaidOnServer
			facts.taking = extra.taking
		end
	end
	local ok, reason = GrabLogic.CanGrab(facts)
	if not ok then
		local who = if reason == "bed" then bedOwner elseif reason == "owned" then ownerPlayer else nil
		local message = GrabLogic.Message(reason, facts, if who then who.DisplayName else nil)
		if message then
			notify(player, message)
		end
		return false, reason
	end
	local localGrip = root.CFrame:PointToObjectSpace(grip)
	local mine = holds[player]
	if mine and mine.piece.model == model then
		-- A new grip on the piece already in hand.
		mine.grip = localGrip
		model:SetAttribute("GrabPoint", localGrip)
		return true, nil
	end
	if mine then
		finish(mine, "switch", "keep")
	end
	local beforeHold = hooks.beforeHold
	if beforeHold then
		beforeHold(player, piece)
	end
	if root.Anchored or not GrabService.Physics.SetOwner(root, player) then
		-- beforeHold may already have freed the piece (a shop box off its
		-- shelf): the owner of that hook puts things back, and nothing here
		-- was recorded as held.
		local onRefused = hooks.onRefused
		if onRefused then
			onRefused(player, piece, "stuck")
		end
		return false, "stuck"
	end
	loose[model] = nil
	local h: Hold = {
		player = player,
		piece = piece,
		root = root,
		grip = localGrip,
		groups = joinHeld(model),
		lastGood = root.CFrame,
		lastGoodAt = now,
	}
	holds[player] = h
	holdOf[model] = h
	local owner = GrabLogic.NewOwner(facts)
	if owner ~= piece.ownerId then
		piece.ownerId = owner
		model:SetAttribute("Owner", owner)
	end
	piece.lastHolderId = player.UserId
	piece.lastInteracted = now
	model:SetAttribute("HeldBy", player.UserId)
	model:SetAttribute("GrabPoint", localGrip)
	local onGrab = hooks.onGrab
	if onGrab then
		onGrab(player, piece)
	end
	return true, nil
end

-- The Release remote: lets go of what `player` holds (`part`, if given,
-- must be on it; nil when it has streamed out on their device).
function GrabService.Release(player: Player, part: unknown)
	if not CoreLoop.V2() or not RateLimiter.Allow(player, "Release") then
		return
	end
	local h = holds[player]
	if not h then
		return
	end
	if part ~= nil then
		if typeof(part) ~= "Instance" or not (part :: Instance):IsDescendantOf(h.piece.model) then
			return
		end
	end
	finish(h, "released", "keep")
end

---------------------------------------------------------------------------
-- The watch
---------------------------------------------------------------------------

-- One sanity pass over every piece a player's device simulates (see the
-- header). GameServer's Heartbeat runs it every WoodJudgeEvery seconds.
function GrabService.Watch(now: number)
	local maxSpeed = Tune.Get("WoodMaxSpeed") :: number
	local releaseDistance = Tune.Get("ReleaseDistance") :: number
	for player, h in pairs(holds) do
		local model = h.piece.model
		if model.Parent == nil or not h.root:IsDescendantOf(model) then
			finish(h, "gone", "none")
			continue
		end
		local hrp, humanoid = body(player)
		if not hrp or not humanoid then
			finish(h, "died", "keep")
			continue
		end
		if humanoid.SeatPart ~= nil then
			finish(h, "seated", "keep")
			continue
		end
		local cf = h.root.CFrame
		local verdict: VehicleLogic.MoveVerdict = if GrabService.JudgeMoves
			then VehicleLogic.JudgeMove(h.lastGood.Position, cf.Position, now - h.lastGoodAt, maxSpeed)
			else "ok"
		if verdict == "tooFar" then
			local lastGood = h.lastGood
			finish(h, "teleport", "server")
			putBack(
				model,
				h.root,
				lastGood,
				player.Name,
				(cf.Position - lastGood.Position).Magnitude,
				now - h.lastGoodAt
			)
			continue
		elseif verdict == "ok" then
			h.lastGood = cf
			h.lastGoodAt = now
		end
		local gripAt = cf:PointToWorldSpace(h.grip)
		if GrabLogic.TooFar((gripAt - hrp.Position).Magnitude, releaseDistance, GameConfig.RangeTolerance) then
			finish(h, "far", "keep")
		end
	end
	for model, l in pairs(loose) do
		if model.Parent == nil then
			loose[model] = nil
			continue
		end
		if l.judge and GrabService.JudgeMoves then
			local cf = l.root.CFrame
			local verdict = VehicleLogic.JudgeMove(l.lastGood.Position, cf.Position, now - l.lastGoodAt, maxSpeed)
			if verdict == "tooFar" then
				local who = if l.player then l.player.Name else "?"
				putBack(
					model,
					l.root,
					l.lastGood,
					who,
					(cf.Position - l.lastGood.Position).Magnitude,
					now - l.lastGoodAt
				)
				l.judge = false
				l.player = nil
				l.untilAt = now + GrabService.PutBackHoldSec
				continue
			elseif verdict == "ok" then
				l.lastGood = cf
				l.lastGoodAt = now
			end
		end
		if now >= l.untilAt then
			loose[model] = nil
			GrabService.Physics.SetAuto(l.root)
		end
	end
	for model in pairs(registry) do
		if model.Parent == nil then
			registry[model] = nil
		end
	end
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------

local function watchCharacter(player: Player, character: Model)
	GrabService.JoinPlayers(character)
	character.DescendantAdded:Connect(function(d: Instance)
		if groupsReady and d:IsA("BasePart") then
			d.CollisionGroup = GrabService.PlayersGroup
		end
	end)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			GrabService.ReleasePlayer(player, "died")
		end)
		humanoid.Seated:Connect(function(active: boolean)
			if active then
				GrabService.ReleasePlayer(player, "seated")
			end
		end)
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(watchCharacter, player, character)
	end)
	player.CharacterRemoving:Connect(function()
		GrabService.ReleasePlayer(player, "died")
	end)
	local character = player.Character
	if character then
		task.spawn(watchCharacter, player, character)
	end
end

-- A player leaving: what they hold, or still simulate, goes back to the
-- server at once.
function GrabService.PlayerRemoving(player: Player)
	GrabService.ReleasePlayer(player, "left")
	for model, l in pairs(loose) do
		if l.player == player then
			loose[model] = nil
			GrabService.Physics.SetAuto(l.root)
		end
	end
end

-- `remotes` are the Grab and Release RemoteEvents; `notifyFn` shows a
-- toast (GameServer's notify). Only under the v2 loop (GameServer checks).
function GrabService.Init(remotes: { Grab: RemoteEvent, Release: RemoteEvent }, notifyFn: (Player, string) -> ())
	notify = notifyFn
	if started then
		return
	end
	started = true
	groupsReady = registerGroups()
	remotes.Grab.OnServerEvent:Connect(function(player: Player, part: unknown, hitPos: unknown)
		GrabService.Grab(player, part, hitPos)
	end)
	remotes.Release.OnServerEvent:Connect(function(player: Player, part: unknown)
		GrabService.Release(player, part)
	end)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(GrabService.PlayerRemoving)
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since >= GameConfig.WoodJudgeEvery then
			since = 0
			GrabService.Watch(os.clock())
		end
	end)
end

return GrabService
