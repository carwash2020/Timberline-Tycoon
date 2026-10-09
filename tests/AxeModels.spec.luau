--!nocheck
-- AxeModels: mesh ids stay as they were, and the part-built look table is
-- the v1 remake (handle length, head size, colours). The Lux gameplay haft
-- stays 3.5 even though the design length is 4.0.

return function(t)
	local AxeModels = t.load("ReplicatedStorage/Shared/Art/AxeModels")
	local Vector3 = t.roblox.Vector3

	local WANT = {
		RustyAxe = { length = 3.2, head = Vector3.new(0.25, 0.9, 1.0), shape = "chipped", headColor = "#7D6A5A" },
		SteelAxe = { length = 3.4, head = Vector3.new(0.25, 1.0, 1.15), shape = "wedge", headColor = "#A7ADB4" },
		HardenedAxe = { length = 3.5, head = Vector3.new(0.28, 1.1, 1.3), shape = "spike", headColor = "#5E6670" },
		SilverAxe = { length = 3.6, head = Vector3.new(0.25, 1.3, 1.3), shape = "bearded", headColor = "#DCE1E6" },
		CobaltAxe = { length = 3.7, head = Vector3.new(0.22, 1.25, 1.4), shape = "doubleBevel", headColor = "#3A6FD8" },
		GoldAxe = { length = 3.7, head = Vector3.new(0.25, 1.5, 1.45), shape = "crescent", headColor = "#E1B530" },
		ObsidianAxe = { length = 3.9, head = Vector3.new(0.3, 1.6, 1.6), shape = "facets", headColor = "#1D1A24" },
		InfernoAxe = { length = 4.0, head = Vector3.new(0.3, 1.6, 1.7), shape = "flame", headColor = "#FF6A1A" },
		StarfallAxe = { length = 4.2, head = Vector3.new(0.28, 1.8, 1.8), shape = "star", headColor = "#BFD8FF" },
		LuxAxe = { length = 4.0, head = Vector3.new(0.25, 1.6, 1.6), shape = "fan", headColor = "#F2D36B" },
		HermitsMaul = { length = 3.6, head = Vector3.new(0.9, 2.4, 1.7), shape = "maul", headColor = "#6F7B5C" },
	}

	t.test("every axe has the remake's length, head and shape", function()
		for id, want in pairs(WANT) do
			local look = AxeModels.Look(id)
			t.ok(look, id)
			t.eq(look.length, want.length, id .. " length")
			t.eq(look.head, want.head, id .. " head")
			t.eq(look.shape, want.shape, id)
			t.eq(look.headColor, want.headColor, id)
		end
	end)

	t.test("gameplay hafts use the design length, except the Lux Axe", function()
		for id, want in pairs(WANT) do
			local got = AxeModels.GameplayLength(id)
			if id == "LuxAxe" then
				t.eq(got, 3.5, "Lux gameplay haft")
			else
				t.eq(got, want.length, id)
			end
		end
		t.eq(AxeModels.GameplayLength("TestAxe"), 3.2)
	end)

	t.test("the Hermit's Maul has a look and no mesh; ladder meshes stay", function()
		t.eq(AxeModels.Get("HermitsMaul"), nil)
		t.ok(AxeModels.Look("HermitsMaul"))
		local rusty = AxeModels.Get("RustyAxe")
		t.eq(rusty.Handle.meshId, 125228989315064)
		t.eq(rusty.Head.meshId, 132884007738463)
		t.eq(AxeModels.Get("LuxAxe").Handle.meshId, 99836533054151)
		t.eq(AxeModels.BladeFrontZ, -1.41)
	end)
end
