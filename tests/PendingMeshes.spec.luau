--!nocheck
-- PendingMeshes: nothing swaps in until a real upload id is pasted.
return function(t)
	local Pending = t.load("ReplicatedStorage/Shared/Art/PendingMeshes")
	t.test("a pending mesh has no id, so the part-built art stays", function()
		local n = 0
		for name, id in pairs(Pending.Ids) do
			n += 1
			t.ok(id == 0 or id > 1e9, name .. " is 0 (pending) or a real upload id")
			if id == 0 then
				t.eq(Pending.Id(name), nil, name)
			else
				t.eq(Pending.Id(name), id, name)
			end
		end
		t.ok(n >= 5, "Pumpkin, PumpkinPatch, PumpkinHat, LavaRock and Roots are listed")
		t.eq(Pending.Id("NoSuchMesh"), nil)
	end)
end
