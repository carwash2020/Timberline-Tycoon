--!nocheck
-- StreamAhead: the point a loaded truck asks its driver to stream, and
-- when. VehicleService does the RequestStreamAroundAsync (pcall, once a
-- second). The radius and the pause mode are PlaceCheck's; this doesn't
-- touch them.
return function(t)
	local StreamAhead = t.shared("StreamAhead")
	local Vector3 = t.roblox.Vector3
	local fs = require("@lune/fs")

	t.test("ahead is a few seconds along the velocity", function()
		local at = Vector3.new(10, 4, -20)
		local velocity = Vector3.new(0, 0, -30) -- 30 studs/s north
		t.eq(StreamAhead.Ahead(at, velocity, StreamAhead.Seconds), Vector3.new(10, 4, -20 - 90))
		t.eq(StreamAhead.Seconds, 3)
		t.eq(StreamAhead.Every, 1)
	end)

	t.test("a request is due only while driving a loaded truck, and not twice in the same second", function()
		t.eq(StreamAhead.Due(true, true, 1, false, 1), true)
		t.eq(StreamAhead.Due(true, true, 0.2, false, 1), false, "throttled")
		t.eq(StreamAhead.Due(false, true, 5, false, 1), false, "nobody driving")
		t.eq(StreamAhead.Due(true, false, 5, false, 1), false, "empty truck")
		t.eq(StreamAhead.Due(true, true, 5, true, 1), false, "the last ask is still in flight")
	end)

	t.test("VehicleService asks the way the gondola does, and leaves the stream settings alone", function()
		local source = fs.readFile("src/ServerScriptService/VehicleService.luau")
		t.ok(string.find(source, "RequestStreamAroundAsync", 1, true))
		t.ok(string.find(source, "pcall(function(): any", 1, true), "a failed request never breaks the drive")
		t.ok(string.find(source, "StreamAhead.Due", 1, true))
		t.ok(string.find(source, "StreamAhead.Ahead", 1, true))
		t.eq(string.find(source, "StreamingTargetRadius"), nil)
		t.eq(string.find(source, "StreamingIntegrityMode"), nil)
		t.eq(string.find(source, "PauseOutsideLoadedArea"), nil)
		local place = fs.readFile("src/ServerScriptService/PlaceCheck.luau")
		t.ok(string.find(place, "StreamingTargetRadius", 1, true))
		t.ok(string.find(place, "PauseOutsideLoadedArea", 1, true))
	end)
end
