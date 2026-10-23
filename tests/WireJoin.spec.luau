--!nocheck
-- WireJoin (T420): runs of wire join end to end. A run may end in the open (its end becomes a
-- junction, uid "J_<id>": Link(from, "J_new", ..., corners) ends it at its LAST corner), start at a
-- junction, or end on one; a chain of joined runs carries power like one wire through the real logic
-- graph. Each run is measured and charged on its own; cutting a run breaks the chain at that run and
-- refunds nothing; a junction that is not there (made up, another plot's, a mid-run point) is
-- refused with nothing used.
return function(t)
	local Vector3, CFrame = t.roblox.Vector3, t.roblox.CFrame
	local Instance = t.roblox.Instance
	local WireLogicMod = t.shared("WireLogic")
	local LogicGraphMod = t.shared("LogicGraph")

	local function setup(options)
		options = options or {}
		local loader = t.loader({
			globals = {
				workspace = {
					GetPartBoundsInBox = function()
						return {}
					end,
				},
				OverlapParams = {
					new = function()
						return {}
					end,
				},
			},
			mocks = {
				RateLimiter = {
					Allow = function()
						return options.rate ~= false
					end,
				},
			},
		})
		local LogicService = loader:server("LogicService")
		local PlotData = loader:shared("PlotData")
		local BlueprintModels = loader:shared("BlueprintModels")
		local InputKit = loader:shared("InputKit")
		local WireLogic = loader:shared("WireLogic")

		local toasts = {}
		local function newPlayer(userId, at)
			local root = { Position = at or Vector3.new(0, 3, 0) }
			return {
				UserId = userId,
				Character = {
					FindFirstChild = function(_, name)
						return if name == "HumanoidRootPart" then root else nil
					end,
				},
				root = root,
			}
		end
		local owner = newPlayer(1)
		local visitor = newPlayer(2)
		local profile = { plot = { placed = {}, wires = {} }, permissions = {}, wireUnits = options.units or 160 } -- wire is single use (T420): a full box
		local items = Instance.new("Folder")
		local host = { cframe = CFrame.new(100, 0, 100), items = items }
		-- Plot-local to world, so a player near plot (x, z) stands there.
		local function at(x, z)
			return Vector3.new(100 + x, 3, 100 + z)
		end
		owner.root.Position = at(0, 0)
		visitor.root.Position = at(0, 0)

		LogicService.Bind(function(player, _flag)
			if player == owner or options.visitorBuilds == true then
				return host, profile, owner, false
			end
			return nil, nil, nil, true
		end, function(player, text)
			table.insert(toasts, { player = player, text = text })
		end)

		local ctxOf = {}
		local function add(uid, blueprintId, x, z)
			local item = { uid = uid, blueprintId = blueprintId, x = x, z = z, rot = 0 }
			table.insert(profile.plot.placed, item)
			local model = BlueprintModels.Build(PlotData.Blueprint(blueprintId), false)
			model.Name = uid
			model:PivotTo(host.cframe * CFrame.new(x, 0, z))
			model:SetAttribute("Open", false) -- what PlotService.placeModel sets
			model.Parent = items
			local ctx = {
				slot = host,
				model = model,
				item = item,
				ownerOf = function()
					return owner, profile
				end,
			}
			ctxOf[uid] = ctx
			LogicService.Attach(ctx)
			return model, ctx
		end
		return {
			loader = loader,
			Service = LogicService,
			WireLogic = WireLogic,
			Doors = loader:server("PlotDoors"),
			InputKit = InputKit,
			owner = owner,
			visitor = visitor,
			profile = profile,
			items = items,
			toasts = toasts,
			add = add,
			ctx = ctxOf,
			at = at,
			newPlayer = newPlayer,
		}
	end

	local function corners(...)
		local out = {}
		for _, p in ipairs({ ... }) do
			table.insert(out, { x = p[1], z = p[2] })
		end
		return out
	end

	-- A switch at (0,0) and a lamp at (30,0), the player between them.
	local function world(options)
		local s = setup(options)
		s.sw = s.add("sw", "SparkSwitch", 0, 0)
		s.lamp = s.add("lamp", "SparkLamp", 30, 0)
		s.owner.root.Position = s.at(15, 0)
		return s
	end

	local function switchOff(s)
		s.profile.plot.switches = {}
		s.sw:SetAttribute("On", false)
		s.Service.Refresh(s.ctx.sw.slot, s.profile, s.owner)
	end

	t.test("two joined runs carry power end to end: switch -> run A -> run B -> lamp", function()
		local s = world()
		-- Run A: from the switch, 10 studs, ending in the open at (10, 0).
		t.eq({ s.Service.Link(s.owner, "sw", "J_new", 1, 1, corners({ 10, 0 })) }, { true, nil })
		t.eq(s.profile.wireUnits, 150, "run A used its 10 studs")
		local a = s.profile.plot.wires[1]
		t.eq(a.id, "w1")
		t.eq(a.to, "J_w1", "its end is the junction")
		t.eq(a.endAt, { x = 10, z = 0 })
		-- Run B: from that junction to the lamp, 20 studs.
		t.eq({ s.Service.Link(s.owner, "J_w1", "lamp") }, { true, nil })
		t.eq(s.profile.wireUnits, 130, "run B used its own 20, measured from the junction")
		t.eq(#s.profile.plot.wires, 2)
		t.eq(s.profile.plot.wires[2].from, "J_w1")
		t.eq(s.lamp:GetAttribute("Lit"), false, "wired through the chain and the switch is off")
		s.Service.Flip(s.ctx.sw, s.owner)
		t.eq(s.sw:GetAttribute("On"), true)
		t.eq(s.lamp:GetAttribute("Lit"), true, "the far end of the chain is powered")
		switchOff(s)
		t.eq(s.lamp:GetAttribute("Lit"), false, "switch off: the far end is unpowered")
	end)

	t.test("cutting run A breaks power to B's far end, and refunds nothing", function()
		local s = world()
		s.Service.Link(s.owner, "sw", "J_new", 1, 1, corners({ 10, 0 }))
		s.Service.Link(s.owner, "J_w1", "lamp")
		s.Service.Flip(s.ctx.sw, s.owner)
		t.eq(s.lamp:GetAttribute("Lit"), true)
		local units = s.profile.wireUnits
		t.eq({ s.Service.Cut(s.owner, "J_w1") }, { true, nil })
		t.eq(s.profile.wireUnits, units, "nothing refunded")
		t.eq(#s.profile.plot.wires, 1, "run A is gone, run B is left starved")
		t.eq(s.profile.plot.wires[1].from, "J_w1")
		t.eq(s.lamp:GetAttribute("Lit"), false, "B's far end lost its power (dark, not 'unwired')")
	end)

	t.test("a chain of three runs, and a second source ending a run on the first run's end", function()
		local s = world({ units = 320 })
		s.add("sw2", "SparkSwitch", 5, 10)
		s.owner.root.Position = s.at(15, 5)
		t.eq({ s.Service.Link(s.owner, "sw", "J_new", 1, 1, corners({ 10, 0 })) }, { true, nil })
		t.eq({ s.Service.Link(s.owner, "J_w1", "J_new", 1, 1, corners({ 20, 0 })) }, { true, nil })
		t.eq({ s.Service.Link(s.owner, "J_w2", "lamp") }, { true, nil })
		s.Service.Flip(s.ctx.sw, s.owner)
		t.eq(s.lamp:GetAttribute("Lit"), true, "through two junctions")
		-- sw2 ends a run on the first junction: another source of the same chain.
		t.eq({ s.Service.Link(s.owner, "sw2", "J_w1") }, { true, nil })
		t.eq(s.profile.plot.wires[#s.profile.plot.wires].to, "J_w1", "a run may end on another run's endpoint")
		switchOff(s)
		t.eq(s.lamp:GetAttribute("Lit"), false)
		s.Service.Flip(s.ctx.sw2, s.owner)
		t.eq(s.lamp:GetAttribute("Lit"), true, "the second source powers the chain too")
	end)

	t.test("a join to a junction that is not there is refused, and nothing is used", function()
		local s = world()
		s.Service.Link(s.owner, "sw", "J_new", 1, 1, corners({ 10, 0 }))
		local units, wires = s.profile.wireUnits, #s.profile.plot.wires
		t.eq(({ s.Service.Link(s.owner, "J_w9", "lamp") })[2], "joint", "made up")
		t.eq(({ s.Service.Link(s.owner, "sw", "J_w9") })[2], "joint", "made up end")
		-- Another plot's junction: its uid means nothing here.
		local other = world()
		other.Service.Link(other.owner, "sw", "J_new", 1, 1, corners({ 12, 0 }))
		t.eq(other.profile.plot.wires[1].id, "w1")
		s.profile.plot.wires = { { from = "sw", to = "lamp" } } -- this plot has no junction at all
		t.eq(({ s.Service.Link(s.owner, "J_w1", "lamp") })[2], "joint", "a foreign junction")
		-- A mid-run corner is not addressable: only a run's END is a junction.
		s.profile.plot.wires = { { from = "sw", to = "lamp", via = corners({ 5, 5 }) } }
		t.eq(({ s.Service.Link(s.owner, "J_5:5", "lamp") })[2], "joint", "a corner")
		t.eq(s.profile.wireUnits, units)
		t.eq(#s.profile.plot.wires, 1)
		t.ok(wires >= 1)
		-- Ending in the open needs a corner to end at.
		local s2 = world()
		t.eq(({ s2.Service.Link(s2.owner, "sw", "J_new") })[2], "corner")
		t.eq(s2.profile.wireUnits, 160)
		t.eq(s2.profile.plot.wires, {})
	end)

	t.test("a loop of junctions is refused: a chain cannot feed itself", function()
		local s = world({ units = 320 })
		s.Service.Link(s.owner, "sw", "J_new", 1, 1, corners({ 5, 0 }))
		s.Service.Link(s.owner, "J_w1", "J_new", 1, 1, corners({ 10, 0 }))
		local units = s.profile.wireUnits
		t.eq(({ s.Service.Link(s.owner, "J_w2", "J_w1") })[2], "loop", "J2 back onto J1")
		t.eq(({ s.Service.Link(s.owner, "J_w1", "J_w1") })[2], "bad", "a junction onto itself")
		t.eq(s.profile.wireUnits, units)
		t.eq(#s.profile.plot.wires, 2)
	end)

	t.test("bends: four per run pass (the end besides), a fifth is refused, joined or not", function()
		local s = world({ units = 320 })
		local four = corners({ 2, 1 }, { 4, -1 }, { 6, 1 }, { 8, -1 })
		-- Four bends and then the end point: five points.
		local withEnd = corners({ 2, 1 }, { 4, -1 }, { 6, 1 }, { 8, -1 }, { 10, 0 })
		t.eq({ s.Service.Link(s.owner, "sw", "J_new", 1, 1, withEnd) }, { true, nil })
		t.eq(#s.profile.plot.wires[1].via, 4, "four bends kept, the fifth point is the end")
		local tooMany = corners({ 2, 1 }, { 4, -1 }, { 6, 1 }, { 8, -1 }, { 9, 1 }, { 10, 0 })
		t.eq(({ s.Service.Link(s.owner, "sw", "J_new", 1, 1, tooMany) })[2], "bends")
		-- A joined run into a lamp: four bends pass, five fail.
		t.eq({ s.Service.Link(s.owner, "J_w1", "lamp", 1, 1, four) }, { true, nil })
		local s2 = world({ units = 320 })
		s2.Service.Link(s2.owner, "sw", "J_new", 1, 1, corners({ 10, 0 }))
		t.eq(
			({
				s2.Service.Link(
					s2.owner,
					"J_w1",
					"lamp",
					1,
					1,
					corners({ 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 1 }, { 5, 1 })
				),
			})[2],
			"bends"
		)
	end)

	t.test("each run is charged on its own, and the 160 stud limit is per run", function()
		local s = world({ units = 320 })
		-- Run A 70 studs out and back (140), run B 160: both fit (the box held 320).
		t.eq({ s.Service.Link(s.owner, "sw", "J_new", 1, 1, corners({ 0, 70 }, { 0, 0 })) }, { true, nil })
		t.eq(s.profile.wireUnits, 320 - 140)
		-- A run over 160 is refused whatever the box holds.
		local s2 = world({ units = 320 })
		t.eq(({ s2.Service.Link(s2.owner, "sw", "J_new", 1, 1, corners({ 0, 81 }, { 0, 0 })) })[2], "span")
		t.eq(s2.profile.wireUnits, 320)
		-- A joined run is measured from the junction, not from the switch.
		local s3 = world({ units = 160 })
		s3.Service.Link(s3.owner, "sw", "J_new", 1, 1, corners({ 10, 0 }))
		s3.Service.Link(s3.owner, "J_w1", "lamp")
		t.eq(s3.profile.wireUnits, 160 - 10 - 20)
	end)

	t.test("a short box leaves wireUnits and wires as they were, joined runs included", function()
		local s = world({ units = 30 })
		s.Service.Link(s.owner, "sw", "J_new", 1, 1, corners({ 10, 0 }))
		t.eq(s.profile.wireUnits, 20)
		local before = #s.profile.plot.wires
		-- 20 studs to the lamp from the junction needs 20: fits. A 40-stud wander does not.
		local ok, why = s.Service.Link(s.owner, "J_w1", "lamp", 1, 1, corners({ 10, 20 }, { 30, 20 }))
		t.eq({ ok, why }, { false, "wire" })
		t.eq(s.profile.wireUnits, 20)
		t.eq(#s.profile.plot.wires, before)
	end)

	t.test("saved runs keep their id and end, and junk is dropped", function()
		local WireLogic = WireLogicMod
		local clean = WireLogic.Clean({
			{ from = "sw", to = "J_w1", id = "w1", endAt = { x = 10, z = 0 } },
			{ from = "J_w1", to = "lamp", id = "w2" },
			{ from = "sw", to = "J_w3", id = "w3", endAt = { x = 1, z = 1 / 0 } },
			{ from = "sw", to = "lamp2", id = "bad id", endAt = { x = 1, z = 1 } },
		})
		t.eq(clean[1], { from = "sw", to = "J_w1", id = "w1", endAt = { x = 10, z = 0 } })
		t.eq(clean[2], { from = "J_w1", to = "lamp", id = "w2" })
		t.eq(clean[3].endAt, nil, "a non-finite end is dropped")
		t.eq(clean[4].id, nil, "an id that is not w<number> is dropped")
		t.eq(clean[4].endAt, nil)
		t.eq(#WireLogic.Joints(clean), 1, "one junction: run w1's end")
	end)

	t.test("the real logic graph carries a signal through any number of junctions", function()
		local WireLogic = WireLogicMod
		local LogicGraph = LogicGraphMod
		local placed = {
			{ uid = "sw", blueprintId = "SparkSwitch", x = 0, z = 0 },
			{ uid = "lamp", blueprintId = "SparkLamp", x = 90, z = 0 },
		}
		local wires = {
			{ from = "sw", to = "J_w1", id = "w1", endAt = { x = 30, z = 0 } },
			{ from = "J_w1", to = "J_w2", id = "w2", endAt = { x = 60, z = 0 } },
			{ from = "J_w2", to = "lamp" },
		}
		local function build(list)
			local live = WireLogic.Live(list, placed)
			local pieces = table.clone(placed)
			for _, joint in ipairs(WireLogic.Joints(live)) do
				table.insert(pieces, joint)
			end
			return LogicGraph.Build(pieces, live, {}), live
		end
		local graph, live = build(wires)
		t.eq(#live, 3)
		t.eq(LogicGraph.On(graph, "lamp"), false)
		LogicGraph.Set(graph, "sw", 1, true)
		t.eq(LogicGraph.On(graph, "J_w2"), true, "the second junction is on")
		t.eq(LogicGraph.Level(graph, "lamp", 1), true, "the lamp's input is on")
		LogicGraph.Set(graph, "sw", 1, false)
		t.eq(LogicGraph.Level(graph, "lamp", 1), false, "off at the switch, off at the lamp")
		-- Run 1 gone: run 2 starts at a junction that is no longer there. It is kept starved, so the lamp
		-- is still fed (dark), and nothing reaches it.
		local g2, live2 = build({ wires[2], wires[3] })
		t.eq(#live2, 2)
		LogicGraph.Set(g2, "sw", 1, true)
		t.eq(LogicGraph.Level(g2, "lamp", 1), false, "cut run A: no power at B's far end")
		local fed = WireLogic.Power(live2, "lamp", { sw = true })
		t.eq(fed, true, "still a wired lamp: dark, not unwired")
	end)

	t.test("a junction is not a logic piece: it never counts against the plot's 80", function()
		local WireLogic = WireLogicMod
		t.eq(WireLogic.IsLogicItem("WireJoint"), false)
		t.eq(WireLogic.LogicCount({ { uid = "a", blueprintId = "WireJoint", x = 0, z = 0 } }), 0)
		t.eq(WireLogic.JointLoop({ { from = "J_a", to = "J_b" } }, "J_b", "J_a"), true)
		t.eq(WireLogic.JointLoop({ { from = "J_a", to = "J_b" } }, "J_a", "J_b"), false)
		t.eq(WireLogic.NextId({ { from = "a", to = "b", id = "w3" }, { from = "a", to = "c", id = "w1" } }), "w4")
	end)

	t.test("a junction is drawn as a marker the client reads like a piece, and goes with its run", function()
		local s = world()
		s.Service.Link(s.owner, "sw", "J_new", 1, 1, corners({ 10, 0 }))
		s.Service.Link(s.owner, "J_w1", "lamp")
		local marker = s.items:FindFirstChild("J_w1")
		t.ok(marker ~= nil, "a marker at the junction")
		t.eq(marker:GetAttribute("BlueprintId"), "WireJoint")
		t.eq(marker:GetAttribute("Uid"), "J_w1")
		t.eq(marker:GetAttribute("X"), 10)
		t.eq(marker:GetAttribute("OwnerId"), 1)
		t.eq(marker:GetAttribute("Wires"), "lamp", "the junction's own run, for the client to draw")
		t.eq(s.sw:GetAttribute("Wires"), "J_w1", "run A ends at the junction")
		s.Service.Cut(s.owner, "J_w1")
		t.eq(s.items:FindFirstChild("J_w1"), nil, "the marker goes with its run")
	end)

	t.test(
		"the client: END HERE is on V and L3 with no key used twice, and WireTool binds it and reads the markers",
		function()
			local fs = require("@lune/fs")
			local InputKit = t.shared("InputKit")
			local end_
			for _, bind in ipairs(InputKit.WireBinds) do
				if bind.action == "EndHere" then
					end_ = bind
				end
			end
			t.ok(end_ ~= nil)
			t.eq(end_.keyboard, t.roblox.Enum.KeyCode.V)
			t.eq(end_.gamepad, t.roblox.Enum.KeyCode.ButtonL3)
			t.ok(InputKit.WireSafe(InputKit.WireBinds))
			local tool = fs.readFile("src/StarterPlayer/StarterPlayerScripts/WireTool.luau")
			t.ok(string.find(tool, '"WireEnd"', 1, true))
			t.ok(string.find(tool, 'GetTagged("WireJoint")', 1, true))
			t.ok(string.find(tool, "WireLogic.NewEnd", 1, true))
		end
	)
end
