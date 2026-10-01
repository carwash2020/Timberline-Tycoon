--!nocheck
-- CritterArt (Shared/Art): the rabbit's eyes (NAT-19). Each eye sits on
-- its own side of the head, just under the head's surface so it shows as
-- a bead, and never pokes out past the head's outline (the far-side eye
-- used to stick out in front of the head).
return function(t)
	local CritterArt = t.load("ReplicatedStorage/Shared/Art/CritterArt")

	local function part(model, name)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == name then
				return d
			end
		end
		return nil
	end

	-- Where `p` lies in the head ellipsoid: < 1 inside, 1 on the surface.
	local function inHead(head, p)
		local rel = p - head.CFrame.Position
		local half = head.Size / 2
		return math.sqrt((rel.X / half.X) ^ 2 + (rel.Y / half.Y) ^ 2 + (rel.Z / half.Z) ^ 2)
	end

	t.test("a rabbit's eyes sit one per side, just inside its head", function()
		for _, snowy in ipairs({ false, true }) do
			for _, seed in ipairs({ 1, 2, 9 }) do
				local rabbit = CritterArt.Rabbit(seed, snowy)
				local head = part(rabbit, "Head")
				local left, right = part(rabbit, "EyeL"), part(rabbit, "EyeR")
				t.ok(head and left and right, "a head and two eyes")
				local l, r = left.CFrame.Position, right.CFrame.Position
				t.ok(l.X < 0 and r.X > 0, "EyeL on the left, EyeR on the right")
				t.ok(math.abs(l.X + r.X) < 1e-4 and math.abs(l.Y - r.Y) < 1e-4, "the eyes mirror each other")
				t.ok(math.abs(l.Z - r.Z) < 1e-4, "the eyes mirror each other")
				for _, eye in ipairs({ left, right }) do
					t.ok(math.abs(eye.Size.X - 0.09) < 1e-4, "an eye is 0.09 across")
					local pos = eye.CFrame.Position
					local depth = inHead(head, pos)
					t.ok(depth < 1, "an eye's centre is inside the head")
					-- Its outer edge breaks the surface, so it shows, but only just.
					local out = pos + (pos - head.CFrame.Position).Unit * eye.Size.X / 2
					local edge = inHead(head, out)
					t.ok(edge > 1 and edge < 1.15, string.format("an eye's edge sits at %.2f of the head", edge))
				end
			end
		end
	end)
end
