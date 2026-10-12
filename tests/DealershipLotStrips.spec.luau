--!nocheck
-- The coloured tier strips on the dealership lot's plinths (one per plinth, the
-- colour of its T-flag) are paint, not loose slabs: thin, lying flush on the
-- plinth's top, inside its footprint with its ends on the plinth's corners,
-- never colliding or casting a shadow, one tier colour per plinth. The aisle
-- band is the same skin laid against the aisle face. Built through the real
-- DealershipLot.Build for every plinth on the lot.
return function(t)
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local StoreTier = t.shared("StoreTier")

	local EPS = 1e-3

	local function aabb(part)
		local cf, size = part.CFrame, part.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
		local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
		local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
		local p = cf.Position
		return p.X - hx, p.X + hx, p.Y - hy, p.Y + hy, p.Z - hz, p.Z + hz
	end

	-- A plinth's bay footprint as DealershipLot.Layout gives it (the lot is built about its
	-- middle in z): the slab itself stops a skin short of the aisle edge, the band fills it.
	local function footprint(plinth)
		local layout = DealershipLot.Layout()
		local x0, x1, y0, y1 = aabb(plinth)
		for _, bay in ipairs(layout.bays) do
			if bay.id == plinth:GetAttribute("ItemId") then
				local oz = -layout.depth / 2
				return x0, x1, y0, y1, oz + bay.z - bay.depth / 2, oz + bay.z + bay.depth / 2
			end
		end
		error("no bay for " .. tostring(plinth:GetAttribute("ItemId")))
	end

	local function inside(a0, a1, b0, b1)
		return a0 >= b0 - EPS and a1 <= b1 + EPS
	end

	local function plinthsAndPaint()
		local lot = DealershipLot.Build()
		local plinths, stripes, bands = {}, {}, {}
		for _, d in ipairs(lot:GetChildren()) do
			if d.Name == "Plinth" then
				table.insert(plinths, d)
			elseif d.Name == "PlinthStripe" then
				table.insert(stripes, d)
			elseif d.Name == "PlinthBand" then
				table.insert(bands, d)
			end
		end
		return plinths, stripes, bands
	end

	-- The skin belonging to a plinth: the one whose footprint (x span) matches and whose
	-- middle is nearest in z.
	local function belonging(list, plinth)
		local x0, x1, _, _, z0, z1 = footprint(plinth)
		local best, bestGap = nil, math.huge
		for _, p in ipairs(list) do
			local px0, px1, _, _, pz0, pz1 = aabb(p)
			if math.abs(px0 - x0) < 0.5 and math.abs(px1 - x1) < 0.5 then
				local gap = math.min(math.abs(pz0 - z0), math.abs(pz1 - z1), math.abs(pz0 - z1), math.abs(pz1 - z0))
				if gap < bestGap then
					best, bestGap = p, gap
				end
			end
		end
		return best
	end

	t.test("every plinth has exactly one stripe and one band, none stray", function()
		local plinths, stripes, bands = plinthsAndPaint()
		t.eq(#plinths, #DealershipLot.Layout().bays, "a plinth per bay")
		t.eq(#plinths, 8, "5 trucks and 3 trailers")
		t.eq(#stripes, #plinths, "a stripe per plinth")
		t.eq(#bands, #plinths, "a band per plinth")
	end)

	t.test("each stripe is a thin skin flush on its plinth's top, edge to edge, inside the footprint", function()
		local plinths, stripes = plinthsAndPaint()
		for i, plinth in ipairs(plinths) do
			local label = "plinth " .. i .. " (" .. tostring(plinth:GetAttribute("ItemId")) .. ")"
			local stripe = belonging(stripes, plinth)
			t.ok(stripe, label .. " has a stripe")
			local px0, px1, _, py1, pz0, pz1 = footprint(plinth)
			local sx0, sx1, sy0, sy1, sz0, sz1 = aabb(stripe)
			t.ok(math.abs(sy0 - py1) <= 0.1, label .. " stripe is within 0.1 of the top: " .. (sy0 - py1))
			t.ok(math.abs(sy0 - py1) <= EPS, label .. " stripe underside is on the top (no gap, nothing sunk)")
			t.ok(sy1 - sy0 <= 0.06, label .. " stripe is thin: " .. (sy1 - sy0))
			t.ok(sy1 - py1 <= 0.06, label .. " stripe stands at most 0.06 over the top")
			t.ok(inside(sx0, sx1, px0, px1), label .. " stripe does not overhang in x")
			t.ok(inside(sz0, sz1, pz0, pz1), label .. " stripe does not overhang in z")
			t.ok(math.abs(sx0 - px0) <= EPS and math.abs(sx1 - px1) <= EPS, label .. " stripe runs corner to corner")
			-- entirely over the slab's own top (resting on the slab, not hanging past it), its
			-- outer edge exactly the slab's aisle edge: the band's top face carries on from there
			local _, _, _, _, tz0, tz1 = aabb(plinth)
			t.ok(inside(sz0, sz1, tz0, tz1), label .. " stripe rests wholly on the slab's top")
			t.ok(
				math.abs(sz0 - tz0) <= EPS or math.abs(sz1 - tz1) <= EPS,
				label .. " stripe sits on an edge of the slab"
			)
			t.eq(stripe.CanCollide, false, label .. " stripe CanCollide")
			t.eq(stripe.CanTouch, false, label .. " stripe CanTouch")
			t.eq(stripe.CanQuery, false, label .. " stripe CanQuery")
			t.eq(stripe.CastShadow, false, label .. " stripe CastShadow")
			t.eq(stripe.Anchored, true, label .. " stripe anchored")
		end
	end)

	t.test(
		"each band is a thin skin on its plinth's aisle face, top edge to the plinth's top, corner to corner",
		function()
			local plinths, _, bands = plinthsAndPaint()
			for i, plinth in ipairs(plinths) do
				local label = "plinth " .. i
				local band = belonging(bands, plinth)
				t.ok(band, label .. " has a band")
				local px0, px1, py0, py1, pz0, pz1 = footprint(plinth)
				local bx0, bx1, by0, by1, bz0, bz1 = aabb(band)
				t.ok(math.abs(by1 - py1) <= EPS, label .. " band's top edge is the plinth's top edge")
				t.ok(by0 >= py0 - EPS, label .. " band is not below the plinth")
				t.ok(math.abs(bx0 - px0) <= EPS and math.abs(bx1 - px1) <= EPS, label .. " band runs corner to corner")
				local thick = bz1 - bz0
				t.ok(thick <= 0.06, label .. " band is thin: " .. thick)
				t.ok(inside(bz0, bz1, pz0, pz1), label .. " band does not overhang the bay in z")
				-- its outer face is a bay edge and its inner face is the slab's own aisle face: no gap
				local _, _, _, _, sz0, sz1 = aabb(plinth)
				local outerFront = math.abs(bz0 - pz0) <= EPS and math.abs(bz1 - sz0) <= EPS
				local outerBack = math.abs(bz1 - pz1) <= EPS and math.abs(bz0 - sz1) <= EPS
				t.ok(outerFront or outerBack, label .. " band is the slab's outer skin, flush, no gap")
				t.eq(band.CanCollide, false, label .. " band CanCollide")
				t.eq(band.CanTouch, false, label .. " band CanTouch")
				t.eq(band.CanQuery, false, label .. " band CanQuery")
				t.eq(band.CastShadow, false, label .. " band CastShadow")
			end
		end
	)

	t.test("one tier colour per plinth: stripe, band and T-flag all wear the tier's colour", function()
		local plinths, stripes, bands = plinthsAndPaint()
		local lot = DealershipLot.Build()
		local flags = {}
		for _, d in ipairs(lot:GetChildren()) do
			if d.Name == "TierFlag" then
				table.insert(flags, d)
			end
		end
		t.eq(#flags, #plinths, "a flag per plinth")
		for _, bay in ipairs(DealershipLot.Layout().bays) do
			local tier = StoreTier.Of(bay.kind, bay.id)
			t.ok(tier ~= nil, bay.id .. " has a tier")
			local want = StoreTier.Color(tier)
			local plinth
			for _, p in ipairs(plinths) do
				if p:GetAttribute("ItemId") == bay.id then
					plinth = p
				end
			end
			t.ok(plinth, bay.id .. " has a plinth")
			t.eq(belonging(stripes, plinth).Color, want, bay.id .. " stripe colour")
			t.eq(belonging(bands, plinth).Color, want, bay.id .. " band colour")
			local flag
			for _, f in ipairs(flags) do
				local fx0, fx1, _, _, fz0, fz1 = aabb(f)
				local px0, px1, _, _, pz0, pz1 = footprint(plinth)
				if inside(fx0, fx1, px0, px1) and inside(fz0, fz1, pz0, pz1) then
					flag = f
				end
			end
			t.ok(flag, bay.id .. " has its flag")
			t.eq(flag.Color, want, bay.id .. " flag colour")
		end
	end)

	t.test("a skin never meets another plinth: no stripe or band reaches a neighbouring plinth's footprint", function()
		local plinths, stripes, bands = plinthsAndPaint()
		for _, skinList in ipairs({ stripes, bands }) do
			for _, skin in ipairs(skinList) do
				local mine = 0
				local sx0, sx1, _, _, sz0, sz1 = aabb(skin)
				for _, plinth in ipairs(plinths) do
					local px0, px1, _, _, pz0, pz1 = footprint(plinth)
					if sx0 < px1 - EPS and sx1 > px0 + EPS and sz0 < pz1 - EPS and sz1 > pz0 + EPS then
						mine += 1
					end
				end
				t.ok(mine <= 1, skin.Name .. " lies over " .. mine .. " plinths")
			end
		end
	end)
end
