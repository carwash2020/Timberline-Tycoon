--!nocheck
-- LogicService: wiring a switch to a lamp or a door on a plot. Real models
-- from BlueprintModels, a fake plot owner, and the Wire remote's checks.
return function(t)
	local Vector3, CFrame = t.roblox.Vector3, t.roblox.CFrame
	local Instance = t.roblox.Instance

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
		local profile = { plot = { placed = {}, wires = {} }, permissions = {} }
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

	local function litLight(model)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("PointLight") then
				return d.Enabled
			end
		end
		return nil
	end

	t.test("a switch gets Flip on Interact and Wire on Open, both with InputKit's keys", function()
		local s = setup()
		local model = s.add("sw", "SparkSwitch", 0, 0)
		local flip = model:FindFirstChild("FlipPrompt", true)
		local wire = model:FindFirstChild("WirePrompt", true)
		t.ok(flip and wire, "both prompts")
		t.eq(flip.KeyboardKeyCode, s.InputKit.Actions.Interact.keyboard)
		t.eq(flip.GamepadKeyCode, s.InputKit.Actions.Interact.gamepad)
		t.eq(wire.KeyboardKeyCode, s.InputKit.Actions.Open.keyboard)
		t.eq(wire.GamepadKeyCode, s.InputKit.Actions.Open.gamepad)
		t.eq(flip.MaxActivationDistance, s.InputKit.OpenRange)
		t.ok(wire.HoldDuration > 0, "wiring is a short hold, so a tap flips instead")
		t.eq(model:GetAttribute("On"), false)
		t.eq(model:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil, true)
	end)

	t.test("a lamp nobody wired is lit, and the light follows its box", function()
		local s = setup()
		local lamp = s.add("lamp", "SparkLamp", 6, 0)
		t.eq(lamp:GetAttribute("Lit"), true)
		t.eq(litLight(lamp), true)
		t.eq(lamp:FindFirstChild("Part2").Material, t.roblox.Enum.Material.Neon)
	end)

	t.test("wire a switch to a lamp, and the lamp follows the switch", function()
		local s = setup()
		local sw = s.add("sw", "SparkSwitch", 0, 0)
		local lamp = s.add("lamp", "SparkLamp", 6, 0)
		t.eq({ s.Service.Link(s.owner, "sw", "lamp") }, { true, nil })
		t.eq(s.profile.plot.wires, { { from = "sw", to = "lamp" } })
		t.eq(lamp:GetAttribute("Lit"), false, "wired and the switch is off")
		t.eq(litLight(lamp), false)
		t.eq(lamp:FindFirstChild("Part2").Material, t.roblox.Enum.Material.SmoothPlastic)

		s.Service.Flip(s.ctx.sw, s.owner)
		t.eq(sw:GetAttribute("On"), true)
		t.eq(lamp:GetAttribute("Lit"), true)
		t.eq(litLight(lamp), true)
		t.eq(lamp:FindFirstChild("Part2").Material, t.roblox.Enum.Material.Neon)
	end)

	t.test("the lever tips one way on and the other off", function()
		local s = setup()
		local sw = s.add("sw", "SparkSwitch", 0, 0)
		local lever = sw:FindFirstChild("Part3")
		local off = lever.CFrame
		s.Service.Reset()
		s.Service.Flip(s.ctx.sw, s.owner)
		local on = lever.CFrame
		t.ok(off ~= on)
		t.ok(off.Position:FuzzyEq(on.Position, 1e-3), "it pivots in place")
		s.Service.Reset()
		s.Service.Flip(s.ctx.sw, s.owner)
		t.ok(lever.CFrame:FuzzyEq(off, 1e-3), "and comes back")
	end)

	t.test("two switches on one lamp: any one on lights it", function()
		local s = setup()
		s.add("a", "SparkSwitch", 0, 0)
		s.add("b", "SparkSwitch", 0, 4)
		local lamp = s.add("lamp", "SparkLamp", 6, 2)
		s.Service.Link(s.owner, "a", "lamp")
		s.Service.Link(s.owner, "b", "lamp")
		s.Service.Flip(s.ctx.b, s.owner)
		t.eq(lamp:GetAttribute("Lit"), true)
		s.Service.Reset()
		s.Service.Flip(s.ctx.a, s.owner)
		t.eq(lamp:GetAttribute("Lit"), true)
		s.Service.Reset()
		s.Service.Flip(s.ctx.b, s.owner)
		s.Service.Reset()
		s.Service.Flip(s.ctx.a, s.owner)
		t.eq(lamp:GetAttribute("Lit"), false)
	end)

	t.test("a switch flips at most once per FlipCooldown", function()
		local s = setup()
		local sw = s.add("sw", "SparkSwitch", 0, 0)
		s.Service.Flip(s.ctx.sw, s.owner)
		s.Service.Flip(s.ctx.sw, s.owner)
		t.eq(sw:GetAttribute("On"), true, "the second press came too soon")
	end)

	t.test("a visitor flips only with the interact flag and wires only with build", function()
		local s = setup()
		local sw = s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		s.Service.Flip(s.ctx.sw, s.visitor)
		t.eq(sw:GetAttribute("On"), false)
		t.eq(s.toasts[#s.toasts].text, "The owner hasn't let you use that.")
		s.profile.permissions = { anyone = { interact = true } }
		s.Service.Flip(s.ctx.sw, s.visitor)
		t.eq(sw:GetAttribute("On"), true)
		s.Service.WireNearest(s.ctx.sw, s.visitor)
		t.eq(s.profile.plot.wires, {})
		s.profile.permissions = { anyone = { build = true } }
		s.Service.WireNearest(s.ctx.sw, s.visitor)
		t.eq(#s.profile.plot.wires, 1)
	end)

	t.test("the Wire prompt takes the nearest free target, then the next, then clears", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("near", "SparkLamp", 4, 0)
		s.add("next", "SparkLamp", 0, 10)
		s.add("far", "SparkLamp", 60, 0)
		s.Service.WireNearest(s.ctx.sw, s.owner)
		t.eq(s.profile.plot.wires, { { from = "sw", to = "near" } })
		s.Service.WireNearest(s.ctx.sw, s.owner)
		t.eq(s.profile.plot.wires, { { from = "sw", to = "near" }, { from = "sw", to = "next" } })
		s.Service.WireNearest(s.ctx.sw, s.owner)
		t.eq(s.profile.plot.wires, {}, "nothing left in reach: wires cleared")
		t.eq(s.toasts[#s.toasts].text, "Wires cleared.")
		s.Service.WireNearest(s.ctx.sw, s.owner)
		s.Service.WireNearest(s.ctx.sw, s.owner)
		s.profile.plot.wires = {}
		s.Service.WireNearest(s.ctx.sw, s.owner)
		t.eq(#s.profile.plot.wires, 1)
	end)

	t.test("the Wire prompt says so when there is nothing to wire", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		s.Service.WireNearest(s.ctx.sw, s.owner)
		t.eq(s.toasts[#s.toasts].text, "Nothing to wire within 32 studs. Place a Spark Lamp or a Door nearby.")
	end)

	t.test("the Wire remote links by uid, cuts by uid, and drops anything malformed", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		local wire = s.Service.OnWire
		wire(s.owner, "sw", 1, "lamp", 1)
		t.eq(s.profile.plot.wires, { { from = "sw", to = "lamp" } })
		wire(s.owner, "sw", 1, "lamp", 1)
		t.eq(#s.profile.plot.wires, 1, "no duplicate")
		for _, bad in ipairs({
			{ 1, 1, "lamp", 1 },
			{ "sw", 2, "lamp", 1 },
			{ "sw", 1, "lamp", 7 },
			{ "sw", 1, 5, 1 },
			{ "sw", "1", "lamp", "1" },
			{ {}, 1, "lamp", 1 },
			{ "cut", 5 },
			{ "cut", {} },
			{ "cut" },
			{ nil },
		}) do
			wire(s.owner, table.unpack(bad, 1, 4))
		end
		t.eq(#s.profile.plot.wires, 1, "bad calls changed nothing")
		wire(s.owner, "cut", "lamp")
		t.eq(s.profile.plot.wires, {})
		wire(s.owner, "lamp", 1, "sw", 1)
		t.eq(s.profile.plot.wires, {}, "a lamp is not a source")
	end)

	t.test("the Wire remote needs the build flag, the rate budget and a player in reach", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		s.Service.OnWire(s.visitor, "sw", 1, "lamp", 1)
		t.eq(s.profile.plot.wires, {}, "a visitor without build")
		s.owner.root.Position = s.at(0, 90)
		s.Service.OnWire(s.owner, "sw", 1, "lamp", 1)
		t.eq(s.profile.plot.wires, {}, "too far away")
		t.eq(s.toasts[#s.toasts].text, "Stand closer to wire that.")
		s.owner.root.Position = s.at(0, 0)
		s.Service.OnWire(s.owner, "sw", 1, "lamp", 1)
		t.eq(#s.profile.plot.wires, 1)

		local limited = setup({ rate = false })
		limited.add("sw", "SparkSwitch", 0, 0)
		limited.add("lamp", "SparkLamp", 6, 0)
		limited.Service.OnWire(limited.owner, "sw", 1, "lamp", 1)
		t.eq(limited.profile.plot.wires, {}, "over the rate limit")
	end)

	t.test("a unbuilt kit door cannot be wired", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("door", "Door", 0, 8)
		s.profile.plot.placed[2].fill = { units = 1 }
		t.eq({ s.Service.Link(s.owner, "sw", "door") }, { false, "unfinished" })
	end)

	t.test("a wired door follows the switch", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		local door = s.add("door", "Door", 0, 8)
		t.eq({ s.Service.Link(s.owner, "sw", "door") }, { true, nil })
		t.eq(door:GetAttribute("Open"), false)
		s.Service.Flip(s.ctx.sw, s.owner)
		t.eq(door:GetAttribute("Open"), true)
		s.Service.Reset()
		s.Doors.Reset() -- the door's own 0.4 s cooldown
		s.Service.Flip(s.ctx.sw, s.owner)
		t.eq(door:GetAttribute("Open"), false)
	end)

	t.test("selling the switch frees the lamp to be lit again", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		local lamp = s.add("lamp", "SparkLamp", 6, 0)
		s.Service.Link(s.owner, "sw", "lamp")
		t.eq(lamp:GetAttribute("Lit"), false)
		s.items:FindFirstChild("sw"):Destroy()
		table.remove(s.profile.plot.placed, 1)
		s.Service.Sync(s.ctx.lamp.slot, s.profile, s.owner)
		t.eq(s.profile.plot.wires, {}, "the dead wire is forgotten")
		t.eq(lamp:GetAttribute("Lit"), true)
	end)

	t.test("a rebuilt plot starts every switch off and every wired lamp dark", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		s.Service.Link(s.owner, "sw", "lamp")
		local again = s.add("lamp2", "SparkLamp", 8, 0)
		t.eq(again:GetAttribute("Lit"), true, "unwired")
		s.profile.plot.wires = { { from = "sw", to = "lamp2" } }
		local rebuilt = s.add("lamp2", "SparkLamp", 8, 0)
		t.eq(rebuilt:GetAttribute("Lit"), false, "wired in the save, switch off")
	end)

	t.test("flipping a switch saves its position in plot.switches, and flipping back removes it", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("other", "SparkSwitch", 0, 6)
		s.Service.Flip(s.ctx.sw, s.owner)
		t.eq(s.profile.plot.switches, { "sw" })
		s.Service.Flip(s.ctx.other, s.owner)
		t.eq(s.profile.plot.switches, { "sw", "other" })
		s.Service.Reset()
		s.Service.Flip(s.ctx.sw, s.owner)
		t.eq(s.profile.plot.switches, { "other" })
	end)

	t.test("a rebuilt plot puts a saved switch back on and its wired lamp lit", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		s.Service.Link(s.owner, "sw", "lamp")
		s.Service.Flip(s.ctx.sw, s.owner)
		-- Rejoin: a fresh model for each piece from the same save, lamp first.
		s.items:ClearAllChildren()
		local lamp = s.add("lamp", "SparkLamp", 6, 0)
		t.eq(lamp:GetAttribute("Lit"), true, "its switch is saved on")
		local sw = s.add("sw", "SparkSwitch", 0, 0)
		t.eq(sw:GetAttribute("On"), true, "the lever is back where it was")
		s.Service.Restore(s.ctx.sw.slot, s.profile, s.owner)
		t.eq(lamp:GetAttribute("Lit"), true)
		-- And a switch saved off stays off.
		s.profile.plot.switches = {}
		local off = s.add("sw", "SparkSwitch", 0, 0)
		t.eq(off:GetAttribute("On"), false)
	end)

	t.test("a saved-on switch wired to a door opens it when the plot is restored", function()
		local s = setup()
		s.profile.plot.wires = { { from = "sw", to = "door" } }
		s.profile.plot.switches = { "sw" }
		local door = s.add("door", "Door", 0, 8)
		local sw = s.add("sw", "SparkSwitch", 0, 0)
		t.eq(sw:GetAttribute("On"), true)
		t.eq(door:GetAttribute("Open"), false, "built shut")
		s.Service.Restore(s.ctx.sw.slot, s.profile, s.owner)
		t.eq(door:GetAttribute("Open"), true)
	end)

	t.test("selling a switch drops its saved position", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("keep", "SparkSwitch", 0, 6)
		s.Service.Flip(s.ctx.sw, s.owner)
		s.Service.Flip(s.ctx.keep, s.owner)
		s.items:FindFirstChild("sw"):Destroy()
		table.remove(s.profile.plot.placed, 1)
		s.Service.Sync(s.ctx.keep.slot, s.profile, s.owner)
		t.eq(s.profile.plot.switches, { "keep" })
	end)

	t.test("a switch model lists the uids it feeds in its Wires attribute, for the client's lines", function()
		local s = setup()
		local sw = s.add("sw", "SparkSwitch", 0, 0)
		s.add("a", "SparkLamp", 6, 0)
		s.add("b", "SparkLamp", 9, 0)
		s.Service.Link(s.owner, "sw", "a")
		t.eq(sw:GetAttribute("Wires"), "a")
		s.Service.Link(s.owner, "sw", "b")
		t.eq(sw:GetAttribute("Wires"), "a,b")
		s.Service.Cut(s.owner, "a")
		t.eq(sw:GetAttribute("Wires"), "b")
		s.Service.Cut(s.owner, "sw")
		t.eq(sw:GetAttribute("Wires"), "")
	end)

	t.test("the Wire remote's link and cut work by uid for the tool, and refuse out of reach", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		s.Service.OnWire(s.owner, "sw", 1, "lamp", 1)
		t.eq(s.profile.plot.wires, { { from = "sw", to = "lamp" } })
		s.Service.OnWire(s.owner, "cut", "lamp")
		t.eq(s.profile.plot.wires, {})
		s.owner.root.Position = s.at(200, 0)
		s.Service.OnWire(s.owner, "sw", 1, "lamp", 1)
		t.eq(s.profile.plot.wires, {})
		t.eq(s.toasts[#s.toasts].text, "Stand closer to wire that.")
	end)

	t.test("a lever and a button into an AND gate light the lamp only when both are on", function()
		local s = setup()
		s.add("lever", "Lever", 0, 0)
		s.add("button", "Button", 0, 4)
		s.add("gate", "GateAnd", 4, 2)
		local lamp = s.add("lamp", "SparkLamp", 8, 2)
		t.eq({ s.Service.Link(s.owner, "lever", "gate", 1, 1) }, { true, nil })
		t.eq({ s.Service.Link(s.owner, "button", "gate", 1, 2) }, { true, nil })
		t.eq({ s.Service.Link(s.owner, "gate", "lamp") }, { true, nil })
		t.eq(s.profile.plot.wires[2].toPort, 2)
		t.eq(lamp:GetAttribute("Lit"), false)
		s.Service.Flip(s.ctx.lever, s.owner)
		t.eq(lamp:GetAttribute("Lit"), false, "the button is still off, so the AND stays off")
		s.Service.Press(s.ctx.button, s.owner)
		t.eq(lamp:GetAttribute("Lit"), true)
		t.eq(lamp:FindFirstChild("Part2").Material, t.roblox.Enum.Material.Neon)
	end)

	t.test("LogicSet saves a clamped time and refuses a value outside the range", function()
		local s = setup()
		local delay = s.add("delay", "Delay", 0, 0)
		local set = delay:FindFirstChild("SetPrompt", true)
		t.ok(set, "a Set prompt")
		t.eq(set:GetAttribute("LogicKey"), "delay")
		t.eq(set:GetAttribute("LogicValue"), 1)
		s.Service.OnLogicSet(s.owner, "delay", "delay", 2)
		t.eq(s.profile.plot.logic.delay.delay, 2)
		t.eq(set:GetAttribute("LogicValue"), 2)
		t.eq(s.toasts[#s.toasts].text, "Delay set to 2 s.")
		s.Service.OnLogicSet(s.owner, "delay", "delay", 50)
		t.eq(s.profile.plot.logic.delay.delay, 2, "out of range is ignored")
		s.Service.OnLogicSet(s.owner, "delay", "nope", 3)
		t.eq(s.profile.plot.logic.delay.delay, 2)
		s.Service.OnLogicSet(s.owner, 5, "delay", 2)
		t.eq(s.profile.plot.logic.delay.delay, 2)
	end)

	t.test("a plot over the logic cap is told once", function()
		local s = setup()
		s.WireLogic.MaxItems = 1
		s.add("a", "SparkSwitch", 0, 0)
		s.add("b", "SparkSwitch", 4, 0)
		local hits = 0
		for _, toast in ipairs(s.toasts) do
			if string.find(toast.text, "logic pieces", 1, true) then
				hits += 1
			end
		end
		t.eq(hits, 1)
		s.add("c", "SparkSwitch", 8, 0)
		t.eq(hits, 1, "still the one warning from before the third piece")
		local again = 0
		for _, toast in ipairs(s.toasts) do
			if string.find(toast.text, "logic pieces", 1, true) then
				again += 1
			end
		end
		t.eq(again, 1, "the cap is said once per plot")
	end)

	t.test("the showroom demo builds on a DemoBoard and a second call does nothing", function()
		local s = setup()
		local board = Instance.new("Part")
		board.Name = "DemoBoard"
		board.Size = Vector3.new(20, 10, 1)
		board.CFrame = CFrame.new(0, 5, 0)
		s.Service.BuildDemo(board)
		local demo = board:FindFirstChild("SparkworksDemo")
		t.ok(demo, "a demo folder")
		t.ok(demo:FindFirstChild("lever"), "lever")
		t.ok(demo:FindFirstChild("gate"), "AND")
		t.ok(demo:FindFirstChild("clock"), "clock")
		t.ok(demo:FindFirstChild("lamp"), "lamp")
		t.ok(demo:FindFirstChild("plate"), "plate")
		t.ok(demo:FindFirstChild("hatch"), "hatch")
		s.Service.BuildDemo(board)
		t.eq(#board:GetChildren(), 1, "not built twice")
	end)
end
