--!strict
-- TravelPlan: the T413 pins, the lift line, the Skyroot grade, and the
-- junction copy. Pure. Fares come from GameConfig. Sign strings are the
-- Designer table; this module does not invent a price or a destination.

local GameConfig = require(script.Parent.GameConfig)
local Util = require(script.Parent.Util)
local WorldLayout = require(script.Parent.World.WorldLayout)

local TravelPlan = {}

TravelPlan.FastTravel = false
TravelPlan.MainWidth = 32
TravelPlan.BranchWidth = 24
TravelPlan.FootWidth = 8
TravelPlan.GradeMax = 0.12
TravelPlan.RigLength = 75.3
TravelPlan.RigWidth = 10.14

-- The river crossing to Dale's lot. Width is the road (Z). Length is the span (X).
TravelPlan.LiftX = 113
TravelPlan.LiftZ = 80
TravelPlan.LiftWidth = 32
TravelPlan.LiftLength = 56
TravelPlan.ChannelHalf = 18

-- West of the deck, on the approach, not in the lane. The push lands on the
-- approach centre. The booth sits south of that, off the 32-wide deck.
TravelPlan.PushX = 72
TravelPlan.PushZ = 80
TravelPlan.BoothX = 72
TravelPlan.BoothZ = 102

export type XZ = { x: number, z: number }

TravelPlan.FreeBridge = {
	x = -36,
	z = 40,
	width = 32,
	length = 24,
	tolled = false,
}

TravelPlan.Mainland = { x = WorldLayout.CarFerryMainlandX, z = WorldLayout.CarFerryMainlandZ }
TravelPlan.IslandDock = { x = WorldLayout.CarFerryIslandX, z = WorldLayout.CarFerryIslandZ }
TravelPlan.Sparkworks = { x = 1115, z = -700 }

-- The solid apron is shifted west so its east edge stays off the Sparkworks
-- floor (the shop box starts at x 1103). The pin itself stays (1100, -700).
function TravelPlan.IslandApron(): { width: number, depth: number, maxX: number, centerX: number }
	-- East edge 1088, clear of the Sparkworks floor that reaches about x 1101.
	return { width = 20, depth = 16, maxX = 1088, centerX = 1080 }
end

function TravelPlan.MainlandApron(): { width: number, depth: number }
	return { width = 20, depth = 16 }
end

function TravelPlan.TollSign(): string
	return string.format("TOLL %s", Util.formatCash(GameConfig.TollFee))
end

-- Control points, including the frost-foot hairpin anchor.
function TravelPlan.SkyrootPoints(): { XZ }
	return {
		{ x = -36, z = 520 },
		{ x = -180, z = 600 },
		{ x = -50, z = 660 },
		{ x = -178, z = 691 },
		{ x = -40, z = 720 },
	}
end

-- A circle of radius 32 centred on the frost foot. The driven road follows it.
function TravelPlan.HairpinArc(): { center: XZ, radius: number, points: { XZ } }
	local center = { x = -178, z = 691 }
	local radius = 32
	local points: { XZ } = {}
	local steps = 8
	for i = 0, steps do
		local a = math.pi * i / steps
		table.insert(points, {
			x = center.x + math.cos(a) * radius,
			z = center.z + math.sin(a) * radius,
		})
	end
	return { center = center, radius = radius, points = points }
end

function TravelPlan.DrivenPoints(): { XZ }
	local out: { XZ } = {}
	local control = TravelPlan.SkyrootPoints()
	for i = 1, 3 do
		table.insert(out, control[i])
	end
	for _, p in ipairs(TravelPlan.HairpinArc().points) do
		table.insert(out, p)
	end
	table.insert(out, control[#control])
	return out
end

function TravelPlan.MaxGrade(heightAt: (number, number) -> number): number
	local pts = TravelPlan.DrivenPoints()
	local y = heightAt(pts[1].x, pts[1].z)
	local worst = 0
	local cap = TravelPlan.GradeMax
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local horiz = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		if horiz >= 1e-4 then
			local ground = heightAt(b.x, b.z)
			local limit = cap * horiz
			local dy = math.clamp(ground - y, -limit, limit)
			worst = math.max(worst, math.abs(dy) / horiz)
			y += dy
		end
	end
	return worst
end

function TravelPlan.Pullouts(): { XZ }
	-- West of the frost-foot anchor, and north of it, clear of both legs.
	return {
		{ x = -218, z = 691 },
		{ x = -178, z = 731 },
	}
end

function TravelPlan.LodgePath(): { a: XZ, b: XZ, width: number, tolled: boolean }
	return {
		a = { x = -40, z = 720 },
		b = { x = -60, z = 800 },
		width = TravelPlan.FootWidth,
		tolled = false,
	}
end

-- Dealership door (189.25, 100.3). The spur is north-south at that x, so it
-- does not run through the Land Office at (153.5, 100).
function TravelPlan.Spur(): { a: XZ, b: XZ, width: number }
	return {
		a = { x = 189.25, z = 80 },
		b = { x = 189.25, z = 100.3 },
		width = TravelPlan.BranchWidth,
	}
end

function TravelPlan.Centerlines(): { { XZ } }
	local sky = TravelPlan.SkyrootPoints()
	local spur = TravelPlan.Spur()
	local free = TravelPlan.FreeBridge
	local halfL = TravelPlan.LiftLength / 2
	return {
		{
			{ x = free.x, z = free.z - free.length / 2 },
			{ x = free.x, z = free.z + free.length / 2 },
		},
		{
			{ x = TravelPlan.LiftX - halfL, z = TravelPlan.LiftZ },
			{ x = TravelPlan.LiftX + halfL, z = TravelPlan.LiftZ },
		},
		{ spur.a, spur.b },
		{ { x = 880, z = -640 }, { x = 920, z = -640 } },
		{ sky[1], sky[2] },
		{ sky[2], sky[3] },
		{ sky[3], sky[4] },
		{ sky[4], sky[5] },
	}
end

export type Sign = { id: string, text: string, x: number, z: number }

function TravelPlan.Signs(): { Sign }
	return {
		{ id = "town", text = "TOWN", x = -60, z = 40 },
		{ id = "toll", text = TravelPlan.TollSign(), x = TravelPlan.BoothX, z = TravelPlan.BoothZ },
		{ id = "dealership", text = "DEALERSHIP →", x = 214, z = 90 },
		{ id = "ferry", text = "FERRY / LANTERN ISLE", x = 920, z = -668 },
		{ id = "skyroot", text = "SKYROOT ↑", x = -36, z = 492 },
		{ id = "return", text = "TOWN (free bridge)", x = -40, z = 748 },
	}
end

return TravelPlan
