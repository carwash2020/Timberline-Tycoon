--!nocheck
-- LoadStages: the loading bar's milestones (the server publishes the latest
-- as workspace.LoadStage; the client's loading card turns it into a bar and
-- a line of text).
return function(t)
	local LoadStages = t.shared("LoadStages")

	t.test("the stages run in order and fill the bar monotonically up to full", function()
		local last = 0
		for _, stage in ipairs(LoadStages.List) do
			t.ok(stage.bar > last, stage.id .. " fills more than the one before")
			last = stage.bar
			t.ok(#stage.text > 0)
		end
		t.eq(last, 1, "the save is the end of the bar")
		t.eq(LoadStages.List[1].id, "starting")
		t.eq(LoadStages.List[#LoadStages.List].id, "save")
	end)

	t.test("unknown, missing or odd values read as the start", function()
		t.eq(LoadStages.Get(nil).id, "starting")
		t.eq(LoadStages.Get(7).id, "starting")
		t.eq(LoadStages.Get("nonsense").id, "starting")
		t.eq(LoadStages.Get("town").id, "town")
	end)

	t.test("the server only moves on: an earlier or unknown stage is not later", function()
		t.eq(LoadStages.IsLater("terrain", nil), true)
		t.eq(LoadStages.IsLater("terrain", "starting"), true)
		t.eq(LoadStages.IsLater("terrain", "town"), false)
		t.eq(LoadStages.IsLater("terrain", "terrain"), false)
		t.eq(LoadStages.IsLater("bogus", "starting"), false)
	end)

	t.test("Describe: the line and the fill follow the server's stage until the world is up", function()
		local fill, text = LoadStages.Describe("terrain", false, nil)
		t.eq(text, "Shaping the land...")
		t.eq(fill, 0.4)
		fill, text = LoadStages.Describe("town", false, nil)
		t.eq(text, "Building the town...")
		t.ok(fill > 0.4)
		fill, text = LoadStages.Describe(nil, false, nil)
		t.eq(text, "Starting the server...", "no stage yet")
	end)

	t.test("Describe: once the world is up the player waits for their own save", function()
		local _, text = LoadStages.Describe("world", true, false)
		t.eq(text, "Loading your save...")
		_, text = LoadStages.Describe("services", true, nil)
		t.eq(text, "Loading your save...")
		-- The Remotes folder proves the world is up even if the attribute is late.
		local fill
		fill, text = LoadStages.Describe("terrain", true, nil)
		t.eq(text, "Loading your save...")
		t.ok(fill >= LoadStages.Get("world").bar)
	end)

	t.test("Describe: the save in means a full bar and no text (the card goes)", function()
		local fill, text = LoadStages.Describe("world", true, true)
		t.eq(fill, 1)
		t.eq(text, nil)
		fill, text = LoadStages.Describe(nil, false, true)
		t.eq(fill, 1)
		t.eq(text, nil)
		-- Only the boolean counts.
		_, text = LoadStages.Describe("world", true, "true")
		t.eq(text, "Loading your save...")
	end)

	t.test("Percent rounds and clamps", function()
		t.eq(LoadStages.Percent(0), "0%")
		t.eq(LoadStages.Percent(0.404), "40%")
		t.eq(LoadStages.Percent(0.995), "100%")
		t.eq(LoadStages.Percent(1.7), "100%")
		t.eq(LoadStages.Percent(-3), "0%")
	end)
end
