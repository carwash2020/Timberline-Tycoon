--!nocheck
-- Lane W (job 08): belt power and reverse by wire, Switch Belt, Wood
-- Detector filter, Wood Sweeper picks, laser reach, and old plots that
-- never wired a belt running exactly as before.
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
					Allow = function(_, key)
						if options.rate == false then
							return false
						end
						if options.limits then
							table.insert(options.limits, key)
						end
						return true
					end,
				},
			},
		})
		local LogicService = loader:server("LogicService")
		local PlotData = loader:shared("PlotData")
		local BlueprintModels = loader:shared("BlueprintModels")
		local MachineArt = loader:load("ReplicatedStorage/Shared/Art/MachineArt")
		local Automation = loader:shared("AutomationLogic")

		local toasts = {}
		local function newPlayer(userId)
			local root = { Position = Vector3.new(100, 3, 100) }
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
		LogicService.Bind(function(player, _flag)
			if player == owner then
				return host, profile, owner, false
			end
			return nil, nil, nil, true
		end, function(player, text)
			table.insert(toasts, { player = player, text = text })
		end)
		local ctxOf = {}
		local function add(uid, id, x, z, extra)
			local item = { uid = uid, blueprintId = id, x = x, z = z, rot = 0 }
			for k, v in pairs(extra or {}) do
				item[k] = v
			end
			table.insert(profile.plot.placed, item)
			local model
			if Automation.IsBelt(id) then
				model = MachineArt.BuildBelt(id, false)
			elseif id:find("^Sawmill") then
				model = MachineArt.Build(id, false)
			else
				model = BlueprintModels.Build(PlotData.Blueprint(id), false)
			end
			model.Name = uid
			model:PivotTo(host.cframe * CFrame.new(x, 0, z))
			model:SetAttribute("Open", false)
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
			Automation = Automation,
			MachineArt = MachineArt,
			loader = loader,
			owner = owner,
			visitor = visitor,
			profile = profile,
			host = host,
			toasts = toasts,
			add = add,
			ctx = ctxOf,
		}
	end

	t.test("W12: every belt, sawmill and the new line pieces register power (and reverse where they run)", function()
		local s = setup()
		for i, id in ipairs({ "ConveyorStraight", "ConveyorTurn", "ConveyorFunnel", "SwitchBelt", "TiltedBelt" }) do
			s.add("b" .. i, id, i * 2, 0)
			local target = s.Service.Target("b" .. i)
			t.ok(target ~= nil and target.power ~= nil and target.reverse ~= nil, id .. " is a target")
		end
		s.add("saw", "SawmillRickety", -10, 0)
		t.ok(s.Service.Target("saw") ~= nil, "the sawmill is a target")
		s.add("det", "WoodDetector", 0, 12)
		t.ok(s.Service.Target("det") ~= nil, "the detector moves wood, so it powers off too")
	end)

	t.test("W2: an old plot with no wires keeps every belt running forward, no new attributes", function()
		local s = setup()
		local belt = s.add("belt", "ConveyorStraight", 0, 0)
		s.Service.Refresh(s.host, s.profile, s.owner)
		t.eq(belt:GetAttribute("PowerIn"), nil, "unwired is powered")
		t.eq(belt:GetAttribute("WireReverse"), nil)
		t.eq(belt:GetAttribute("Reversed"), nil)
		t.eq(s.Automation.SignedSpeed(4, true, false), 4)
	end)

	t.test("W1/W12: a switch on port 1 powers the belt, a switch on port 2 reverses it", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("rv", "SparkSwitch", 2, 0)
		local belt = s.add("belt", "ConveyorStraight", 4, 0)
		t.eq({ s.Service.Link(s.owner, "sw", "belt", 1, 1) }, { true, nil })
		t.eq(belt:GetAttribute("PowerIn"), false, "wired to an off switch: stopped")
		s.Service.Flip(s.ctx.sw, s.owner)
		t.eq(belt:GetAttribute("PowerIn"), nil, "switch on: running")
		t.eq({ s.Service.Link(s.owner, "rv", "belt", 1, 2) }, { true, nil })
		t.eq(belt:GetAttribute("WireReverse"), nil)
		s.Service.Flip(s.ctx.rv, s.owner)
		t.eq(belt:GetAttribute("WireReverse"), true, "reverse port high")
		t.eq(belt:GetAttribute("PowerIn"), nil, "still powered")
	end)

	t.test("a Switch Belt routes both ways: the side port and the saved flip", function()
		local s = setup()
		s.add("sw", "SparkSwitch", 0, 0)
		local belt, ctx = s.add("sb", "SwitchBelt", 6, 0)
		local Side = function()
			return s.Automation.SwitchSide(belt:GetAttribute("Flip") == true, false, false)
		end
		local first = Side()
		t.eq(s.Service.FlipBelt(ctx, s.owner), true)
		t.eq(ctx.item.flip, true, "the flip is saved on the piece")
		t.eq(Side(), -first, "flip mirrors the diverter")
		t.eq(s.Service.FlipBelt(ctx, s.owner), true)
		t.eq(ctx.item.flip, nil, "flipping back saves nothing")
		t.eq(
			s.Automation.SwitchSide(false, true, true),
			-s.Automation.SwitchSide(false, true, false),
			"the wire side swaps"
		)
		t.eq({ s.Service.Link(s.owner, "sw", "sb", 1, 1) }, { true, nil })
		s.Service.Flip(s.ctx.sw, s.owner)
		t.ok(belt:GetAttribute("WireSide") ~= nil or belt:GetAttribute("PowerIn") == nil, "side port is driven")
	end)

	t.test("reverse is owner-only, rate limited, and saved on the piece", function()
		local limits = {}
		local s = setup({ limits = limits })
		local belt, ctx = s.add("belt", "ConveyorStraight", 0, 0)
		t.eq(s.Service.Reverse(ctx, s.visitor), false, "a visitor cannot reverse")
		t.eq(ctx.item.reversed, nil)
		t.eq(s.Service.Reverse(ctx, s.owner), true)
		t.eq(ctx.item.reversed, true)
		t.eq(belt:GetAttribute("Reversed"), true)
		t.ok(table.find(limits, "BeltReverse") ~= nil, "it spends the BeltReverse budget")
		t.eq(s.Service.Reverse(ctx, s.owner), true)
		t.eq(ctx.item.reversed, nil, "forward again saves nothing")
		local blocked = setup({ rate = false })
		local _, bctx = blocked.add("belt", "ConveyorStraight", 0, 0)
		t.eq(blocked.Service.Reverse(bctx, blocked.owner), false, "over the rate budget: refused")
		local _, sctx = s.add("saw", "SawmillRickety", -10, 0)
		t.eq(s.Service.Reverse(sctx, s.owner), false, "a sawmill does not reverse")
	end)

	t.test("a rebuilt plot puts a saved reverse and flip back on the models", function()
		local s = setup()
		local belt = s.add("belt", "ConveyorStraight", 0, 0, { reversed = true })
		local sb = s.add("sb", "SwitchBelt", 6, 0, { flip = true })
		t.eq(belt:GetAttribute("Reversed"), true)
		t.eq(sb:GetAttribute("Flip"), true)
	end)

	t.test("the detector filter steps through every wood and saves only a choice", function()
		local s = setup()
		local det, ctx = s.add("det", "WoodDetector", 0, 0)
		t.eq(det:GetAttribute("Filter"), 0)
		t.eq(s.Service.StepFilter(ctx, s.visitor), nil, "owner only")
		t.eq(s.Service.StepFilter(ctx, s.owner), 1)
		t.eq(s.profile.plot.logic.det.filter, 1)
		local n = #s.Automation.FilterWoods()
		for _ = 2, n do
			s.Service.StepFilter(ctx, s.owner)
		end
		t.eq(s.Service.StepFilter(ctx, s.owner), 0, "wraps back to any wood")
		t.eq(s.profile.plot.logic.det, nil, "any wood saves nothing")
	end)

	t.test("W6: the filter index is pinned to today's WoodData order", function()
		local s = setup()
		local woods = s.Automation.FilterWoods()
		-- Append-only: a new wood goes on the end, never in between.
		t.eq(woods, {
			"oak",
			"birch",
			"pine",
			"maple",
			"palmwood",
			"frostwood",
			"lanternwood",
			"emberwood",
			"phantomwood",
			"lumenwood",
			-- Lane R's two region woods go on the end (the Bayou's, then Red Mesa's).
			"bogcypress",
			"ironwood",
		})
		t.eq(s.Automation.FilterMatches(0, "oak"), true)
		t.eq(s.Automation.FilterMatches(1, woods[1]), true)
		t.eq(s.Automation.FilterMatches(1, woods[2]), false)
		t.eq(s.Automation.CleanFilter(99), 0, "a filter past the list is any wood")
		t.eq(s.Automation.CleanFilter(1.5), 0)
		t.eq(s.Automation.CleanFilter("oak"), 0)
		t.eq(s.Automation.FilterName(0), "Any wood")
	end)

	t.test("W5: a sweep pulse picks loose plot wood only, ten at most", function()
		local s = setup()
		local A = s.Automation
		local list = {}
		for i = 1, 14 do
			table.insert(list, { key = i, held = false, wood = true, ownerId = 1, landsOnPlot = true })
		end
		t.eq(#A.SweepPick(list, 1), 10, "ten at most")
		local picked = A.SweepPick({
			{ key = "held", held = true, wood = true, ownerId = 1, landsOnPlot = true },
			{ key = "player", held = false, wood = false, ownerId = 1, landsOnPlot = true },
			{ key = "theirs", held = false, wood = true, ownerId = 5, landsOnPlot = true },
			{ key = "off", held = false, wood = true, ownerId = 1, landsOnPlot = false },
			{ key = "nobody", held = false, wood = true, ownerId = 0, landsOnPlot = true },
			{ key = "mine", held = false, wood = true, ownerId = 1, landsOnPlot = true },
		}, 1)
		t.eq(picked, { "nobody", "mine" })
	end)

	t.test("W7: a laser reaches only a receiver on its axis, facing back, in range", function()
		local s = setup()
		local A = s.Automation
		local z = Vector3.new(0, 0, 1)
		local o = Vector3.new(0, 1.92, 0)
		t.eq(A.LaserReach(o, z, Vector3.new(0, 1.92, 20), -z), 20)
		t.eq(A.LaserReach(o, z, Vector3.new(0, 1.92, -20), -z), nil, "behind the lens")
		t.eq(A.LaserReach(o, z, Vector3.new(3, 1.92, 20), -z), nil, "off the axis")
		t.eq(A.LaserReach(o, z, Vector3.new(0, 1.92, 20), z), nil, "dish facing away")
		t.eq(A.LaserReach(o, z, Vector3.new(0, 1.92, A.LaserRange + 1), -z), nil, "out of range")
		t.ok(A.MaxLaserPairs >= 1)
	end)

	t.test("W3: power state helpers: unpowered stops, pause shifts the clock", function()
		local s = setup()
		local A = s.Automation
		t.eq(A.SignedSpeed(4, false, false), 0)
		t.eq(A.SignedSpeed(4, true, true), -4)
		t.eq(A.MachinePowered(nil), true)
		t.eq(A.MachinePowered(false), false)
		t.eq(A.PauseShift(10, 13), 3)
		t.eq(A.Powered(false, false), true, "unwired always runs")
		t.eq(A.Powered(true, false), false)
		t.eq(A.Reversed(true, false, false), true)
		t.eq(A.Reversed(true, true, true), false, "wire reverse flips a saved reverse")
	end)

	t.test("selling a belt drops its target", function()
		local s = setup()
		local belt = s.add("belt", "ConveyorStraight", 0, 0)
		t.ok(s.Service.Target("belt") ~= nil)
		belt.Parent = nil
		table.remove(s.profile.plot.placed, 1)
		s.Service.Sync(s.host, s.profile, s.owner)
		t.eq(s.Service.Target("belt"), nil)
	end)

	-- World-space bounds of a part (all eight corners).
	local function bounds(p)
		local cf, sz = p.CFrame, p.Size
		local lo = { math.huge, math.huge, math.huge }
		local hi = { -math.huge, -math.huge, -math.huge }
		for _, dx in ipairs({ -1, 1 }) do
			for _, dy in ipairs({ -1, 1 }) do
				for _, dz in ipairs({ -1, 1 }) do
					local w = cf * Vector3.new(dx * sz.X / 2, dy * sz.Y / 2, dz * sz.Z / 2)
					lo = { math.min(lo[1], w.X), math.min(lo[2], w.Y), math.min(lo[3], w.Z) }
					hi = { math.max(hi[1], w.X), math.max(hi[2], w.Y), math.max(hi[3], w.Z) }
				end
			end
		end
		return lo, hi
	end

	t.test("TLD-1 line pieces stay inside their footprint, ports at deck top 0.72 (+ rise)", function()
		local s = setup()
		local Catalog = s.loader:shared("ItemCatalog")
		for _, id in ipairs({ "SwitchBelt", "TiltedBelt", "BeltSupport", "WoodDetector" }) do
			local def = Catalog.GetMachine(id).belt
			local model = s.MachineArt.BuildBelt(id, false)
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") and p.Name ~= "Gate" then
					local lo, hi = bounds(p)
					t.ok(
						lo[3] >= -def.depth / 2 - 1e-3 and hi[3] <= def.depth / 2 + 1e-3,
						id .. " " .. p.Name .. " inside the footprint along the run"
					)
					t.ok(lo[2] >= -1e-3, id .. " " .. p.Name .. " not under the ground")
				end
			end
		end
		-- Tilted Belt: the low port face is deck top 0.72, the high one 0.72 + rise,
		-- both flat (a straight belt or a belt on supports butts on flush).
		local tilted = s.MachineArt.BuildBelt("TiltedBelt", false)
		local lowTop, highTop
		for _, p in ipairs(tilted:GetDescendants()) do
			if p.Name == "Conveyor" then
				local lo, hi = bounds(p)
				if lo[3] <= -4 + 1e-3 then
					lowTop = hi[2]
					t.ok(math.abs(lo[2] - (hi[2] - 0.32)) < 1e-3, "the low lip is flat")
				end
				if hi[3] >= 4 - 1e-3 then
					highTop = hi[2]
				end
			end
		end
		-- The pitched run's parts close both seams with the lips: each reaches
		-- past the seam at either end (no gap down to the ground) and sits
		-- centred on the run.
		local seam = 4 - s.Automation.TiltLip
		local pitched = {}
		for _, p in ipairs(tilted:GetDescendants()) do
			if p:IsA("BasePart") and p.Name ~= "Roller" and math.abs(p.CFrame.LookVector.Y) > 0.1 then
				local lo, hi = bounds(p)
				pitched[p.Name] = true
				t.ok(lo[3] <= -seam + 1e-3 and hi[3] >= seam - 1e-3, "pitched " .. p.Name .. " spans both seams")
			end
		end
		for _, name in ipairs({ "Plate", "Pan", "GuardRail", "RailCap", "Conveyor" }) do
			t.ok(pitched[name], "a pitched " .. name)
		end
		t.ok(lowTop and math.abs(lowTop - s.Automation.DeckTop) < 1e-3, "low port at 0.72")
		t.ok(highTop and math.abs(highTop - (s.Automation.DeckTop + s.Automation.Lift)) < 1e-3, "high port at 2.72")
		t.eq(s.Automation.Lift, 2.0, "a Belt Support saddle is the same 2.0")
	end)
	t.test("Wood Sweeper down: the bar is held by the rod, rests on the wood's side, clears the guard rail", function()
		local s = setup()
		local A = s.Automation
		local PlotData = s.loader:shared("PlotData")
		local BlueprintModels = s.loader:shared("BlueprintModels")
		local sweeper = BlueprintModels.Build(PlotData.Blueprint("WoodSweeper"), false)
		-- Snug beside a straight belt: the sweeper's centre 3 studs off the belt's.
		sweeper:PivotTo(CFrame.new(-3, 0, 0))
		s.Service._poseSweeper(sweeper, true)
		t.eq(sweeper:GetAttribute("Swept"), true, "posed down")
		local belt = s.MachineArt.BuildBelt("ConveyorStraight", false)
		local part = {}
		for _, p in ipairs(sweeper:GetDescendants()) do
			if p:IsA("BasePart") then
				part[p.Name] = { bounds(p) }
			end
		end
		local post, arm, head, rod = part.Part2, part.Part3, part.Part4, part.Part5
		t.ok(rod and arm and head and post, "post, arm, head and rod are all there")
		-- The rod runs from inside the post to inside the arm: nothing floats.
		t.ok(rod[1][1] <= post[2][1] and rod[2][1] >= arm[1][1], "the rod joins the post to the arm")
		t.ok(rod[1][3] >= arm[1][3] and rod[2][3] <= arm[2][3], "the rod meets the arm along its length")
		t.ok(rod[1][2] >= arm[1][2] - 1e-3 and rod[2][2] <= arm[2][2] + 1e-3, "the rod is level with the arm")
		-- A 2-wide log centred on the deck with its face on the bar.
		local logLo = arm[2][1]
		t.ok(logLo > -1.5 and logLo + 2 < 1.5, "the bar's face leaves room for a log on the deck")
		-- Nothing of the sweeper passes through the near guard rail or the deck.
		for _, p in ipairs(belt:GetDescendants()) do
			if p:IsA("BasePart") and (p.Name == "GuardRail" or p.Name == "Conveyor") then
				local lo, hi = bounds(p)
				for name, b in pairs(part) do
					if name ~= "Root" and name ~= "Part1" then
						local overlap = b[1][1] < hi[1] - 1e-3
							and b[2][1] > lo[1] + 1e-3
							and b[1][2] < hi[2] - 1e-3
							and b[2][2] > lo[2] + 1e-3
							and b[1][3] < hi[3] - 1e-3
							and b[2][3] > lo[3] + 1e-3
						t.ok(not overlap, name .. " clear of the belt's " .. p.Name)
					end
				end
			end
		end
		s.Service._poseSweeper(sweeper, false)
		local up = { bounds(sweeper:FindFirstChild("Part5")) }
		t.ok(math.abs(up[1][2] - post[2][2]) < 0.02, "parked, the rod stands on the post top")
		t.eq(A.SweepReach, 1.9, "reach pinned")
	end)
end
