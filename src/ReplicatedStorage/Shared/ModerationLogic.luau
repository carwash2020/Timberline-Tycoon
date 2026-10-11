--!strict
-- ModerationLogic: the rules for plot kick / ban (owner only) and for the
-- in-game Report a player button. Pure, so PlotService, SettingsUI and the
-- specs share one set of rules and one set of words.
--
-- Kick: an owner sends someone standing on their plot back off it, and the
-- visitor can't walk back on for KickSeconds. Kept in server memory only.
-- Ban: the visitor can't visit, build, grab or open doors on that plot, for
-- good: the ban is a marker in the slot's saved `permissions`
-- (PermissionLogic.Ban), so it survives a rejoin and a restart.
-- Report: opens Roblox's own report (Players:ReportAbuse) for one player in
-- the server; the game never reads or stores what the report says.

local PermissionLogic = require(script.Parent.PermissionLogic)

local ModerationLogic = {}

ModerationLogic.KickSeconds = 120

-- Touch targets for the moderation and report buttons (same as Settings).
ModerationLogic.Tap = 44

ModerationLogic.Actions = { "kick", "ban", "unban" }

local ACTION: { [string]: boolean } = {}
for _, name in ipairs(ModerationLogic.Actions) do
	ACTION[name] = true
end

function ModerationLogic.IsAction(value: unknown): boolean
	return type(value) == "string" and ACTION[value] == true
end

-- What a moderation request needs to know that only the server can see.
export type Context = {
	ownerId: number, -- the requester, who must own the plot
	ownsPlot: boolean, -- they have a plot in this server
	targetHere: boolean, -- the target is in this server
	targetOnPlot: boolean, -- and standing on that plot
	targetIsStaff: boolean, -- the target is the game's owner (never moderated by a plot owner)
}

-- Whether `ownerId` may do `action` to `targetRaw`. Returns (ok, userId, why):
-- `why` is a sentence for the owner's toast, or "bad" for junk that gets no
-- toast.
function ModerationLogic.Check(
	permissions: any,
	action: unknown,
	targetRaw: unknown,
	ctx: Context
): (boolean, number?, string?)
	if not ModerationLogic.IsAction(action) then
		return false, nil, "bad"
	end
	local target = PermissionLogic.VisitTarget(targetRaw)
	if not target then
		return false, nil, "bad"
	end
	if not ctx.ownsPlot then
		return false, nil, "You need a plot to do that."
	end
	if target == ctx.ownerId then
		return false, nil, "That's you."
	end
	if action == "unban" then
		if not PermissionLogic.IsBanned(permissions, target) then
			return false, nil, "They aren't banned from your plot."
		end
		return true, target, nil
	end
	if ctx.targetIsStaff then
		return false, nil, "You can't do that to the game's owner."
	end
	if action == "kick" then
		if not ctx.targetHere or not ctx.targetOnPlot then
			return false, nil, "They aren't on your plot right now."
		end
		return true, target, nil
	end
	-- ban: a person who already left can still be banned by id (the owner
	-- list shows who was banned); the shared rules decide the rest.
	return true, target, nil
end

-- A short in-memory map of recent kicks: [ownerId][visitorId] = until.
export type Kicks = { [number]: { [number]: number } }

function ModerationLogic.Kick(kicks: Kicks, ownerId: number, userId: number, now: number)
	local row = kicks[ownerId]
	if row == nil then
		row = {}
		kicks[ownerId] = row
	end
	row[userId] = now + ModerationLogic.KickSeconds
end

function ModerationLogic.IsKicked(kicks: Kicks, ownerId: number, userId: number, now: number): boolean
	local row = kicks[ownerId]
	local untilAt = if row then row[userId] else nil
	if untilAt == nil then
		return false
	end
	if now >= untilAt then
		row[userId] = nil
		return false
	end
	return true
end

-- Whether `userId` may not be on `ownerId`'s plot at `now`: banned, or kicked
-- a moment ago. The one question the visit, the sweep and the doors ask.
function ModerationLogic.Excluded(permissions: any, kicks: Kicks, ownerId: number, userId: number, now: number): boolean
	if userId == ownerId then
		return false
	end
	return PermissionLogic.IsBanned(permissions, userId) or ModerationLogic.IsKicked(kicks, ownerId, userId, now)
end

-- Words. `owner` and `visitor` are display names (Roblox filters those).
function ModerationLogic.KickedOwner(visitor: string): string
	return string.format(
		"Sent %s off your plot. They can't come back for %d minutes.",
		visitor,
		ModerationLogic.KickSeconds // 60
	)
end

function ModerationLogic.KickedVisitor(owner: string): string
	return string.format(
		"%s sent you off their plot. You can try again in %d minutes.",
		owner,
		ModerationLogic.KickSeconds // 60
	)
end

function ModerationLogic.BannedOwner(visitor: string): string
	return string.format("Banned %s from your plot. Settings, Visitors lists your bans so you can undo it.", visitor)
end

function ModerationLogic.BannedVisitor(owner: string): string
	return string.format("%s banned you from their plot. You can't visit or build there.", owner)
end

function ModerationLogic.UnbannedOwner(visitor: string): string
	return string.format("%s can visit your plot again.", visitor)
end

function ModerationLogic.VisitBanned(owner: string): string
	return string.format("%s has banned you from their plot.", owner)
end

function ModerationLogic.VisitKicked(owner: string): string
	return string.format("%s sent you off their plot a moment ago. Try again later.", owner)
end

---------------------------------------------------------------------------
-- Report a player.
---------------------------------------------------------------------------

-- Reasons Roblox's report takes (Players:ReportAbuse's `reason` strings),
-- with the plain words the button shows. Order is the order on screen.
ModerationLogic.ReportReasons = {
	{ id = "Swearing", label = "Bad language" },
	{ id = "Bullying", label = "Bullying" },
	{ id = "Inappropriate Username", label = "Bad username" },
	{ id = "Scamming", label = "Scamming" },
	{ id = "Cheating/Exploiting", label = "Cheating" },
	{ id = "Offsite Links", label = "Links to other sites" },
	{ id = "Personal Question", label = "Asking personal things" },
	{ id = "Dating", label = "Dating" },
} :: { { id: string, label: string } }

function ModerationLogic.ReasonId(value: unknown): string?
	for _, reason in ipairs(ModerationLogic.ReportReasons) do
		if reason.id == value then
			return reason.id
		end
	end
	return nil
end

-- The button shows only where the report call exists on this device and
-- there is someone else to report. Where it does not exist it is hidden,
-- never shown dead.
function ModerationLogic.ReportShown(apiAvailable: boolean, others: number): boolean
	return apiAvailable == true and type(others) == "number" and others >= 1
end

ModerationLogic.ReportTitle = "REPORT A PLAYER"
ModerationLogic.ReportSent = "Report sent to Roblox. Thank you."
ModerationLogic.ReportFailed = "Couldn't send that report. Use the Roblox menu (Esc) to report instead."

return ModerationLogic
