--!strict
-- VoidRescue: a character that has fallen out of the world is put back on its
-- spawn pad (moved, not killed), a bounded number of times. Pure; GameServer
-- runs it for every character it loads.
--
-- Why: the engine only kills a part at Workspace.FallenPartsDestroyHeight
-- (-500), so a character that falls through ground that has not been written
-- or streamed yet used to fall for seconds, die, wait the respawn delay, load
-- at the same pad and, if the ground was still missing, do it all again. A
-- put-back at VoidRescue.MinY keeps the player alive, and the cap means a pad
-- that is itself over the void cannot make the rescue loop: after MaxRescues
-- the engine's own death takes over (one death, then the normal respawn).
--
-- MinY sits under the deepest cave floor (the Deep mine's is -108) and well
-- over the engine's -500, so nobody is rescued from the mine and nobody has to
-- fall for long. (FallenLogic.VoidY, -80, is for wood and trucks, which never
-- go into the mines' lower tiers.)

local VoidRescue = {}

VoidRescue.MinY = -200
VoidRescue.MaxRescues = 3 -- per character
VoidRescue.GapSeconds = 2 -- never twice inside this
VoidRescue.CheckSeconds = 0.5 -- how often GameServer looks (a fall is ~100 studs a second)
VoidRescue.PadLift = 4 -- studs over the pad's middle that the character is put

export type Tracker = {
	-- Should this character be put back now? Counts the rescue when it says yes.
	Check: (y: number, now: number) -> boolean,
	Count: () -> number,
}

function VoidRescue.Fell(y: number): boolean
	return type(y) == "number" and (y < VoidRescue.MinY or y ~= y)
end

-- One per character (a respawn is a new character: a new tracker).
function VoidRescue.new(): Tracker
	local count = 0
	local lastAt: number? = nil
	local tracker = {} :: Tracker
	function tracker.Check(y: number, now: number): boolean
		if not VoidRescue.Fell(y) or count >= VoidRescue.MaxRescues then
			return false
		end
		if lastAt ~= nil and now - (lastAt :: number) < VoidRescue.GapSeconds then
			return false
		end
		count += 1
		lastAt = now
		return true
	end
	function tracker.Count(): number
		return count
	end
	return tracker
end

return VoidRescue
