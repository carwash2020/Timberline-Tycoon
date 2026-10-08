--!nocheck
-- HermitService + HazardService: the marks, the Totem, the Maul, and the
-- sea's telegraph, with mocked players and profiles.

return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	local nextId = 100
	local function person(x, z)
		nextId += 1
		local char = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(x, 10, z)
		root.Parent = char
		char.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = char
		return { UserId = nextId, Name = "p" .. nextId, Character = char }, root, humanoid
	end

	local function hermitModel(x, z)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(x, 10, z)
		root.Parent = model
		model.PrimaryPart = root
		return model
	end

	local function setup()
		local loader = t.loader({ services = { Players = {
			GetPlayers = function()
				return {}
			end,
		} } })
		local Service = loader:server("HermitService")
		local s = {
			Service = Service,
			Logic = loader:shared("HermitLogic"),
			profile = { secretsFound = {}, questAxe = { step = 0 }, gear = {} },
			toasts = {},
			said = {},
			granted = {},
			owned = {},
		}
		Service.SetDeps({
			profile = function()
				return s.profile
			end,
			notify = function(_, text)
				table.insert(s.toasts, text)
			end,
			say = function(_, text)
				table.insert(s.said, text)
			end,
			grantAxe = function(_, id)
				table.insert(s.granted, id)
				s.owned[id] = true
			end,
			ownsAxe = function(_, id)
				return s.owned[id] == true
			end,
		})
		return s
	end

	local function findMark(Logic, id)
		return Logic.MarkByKey("mark_" .. id)
	end

	t.test("a press sets the mark once, only when standing at it", function()
		local s = setup()
		local snow = findMark(s.Logic, "snow")
		local far = person(0, 0)
		t.eq(s.Service.Press(far, "mark_snow"), false, "too far")
		t.eq(s.profile.secretsFound.mark_snow, nil)
		local near = person(snow.x + 3, snow.z)
		t.eq(s.Service.Press(near, "mark_snow"), true)
		t.eq(s.profile.secretsFound.mark_snow, true)
		t.ok(string.find(s.toasts[1], "1 of 5", 1, true) ~= nil, s.toasts[1])
	end)

	t.test("a made-up key does nothing, and a repeat press is a gentle no", function()
		local s = setup()
		local snow = findMark(s.Logic, "snow")
		local near = person(snow.x, snow.z)
		t.eq(s.Service.Press(near, "mark_bogus"), false)
		t.eq(s.Service.Press(near, 7), false)
		t.eq(s.Service.Press(near, "CarvedTotem"), false, "the client can't press the totem in")
		t.eq(s.profile.secretsFound.CarvedTotem, nil)
		-- The rejected presses above used this player's budget, so use fresh ones.
		t.eq(s.Service.Press(person(snow.x, snow.z), "mark_snow"), true)
		local again = person(snow.x, snow.z)
		t.eq(s.Service.Press(again, "mark_snow"), false)
		t.eq(s.profile.secretsFound.mark_snow, true)
	end)

	t.test("the fifth mark grants the Totem, with no cash and no axe", function()
		local s = setup()
		for _, mark in ipairs(s.Logic.Marks) do
			local p = person(mark.x, mark.z)
			t.eq(s.Service.Press(p, mark.key), true, mark.key)
		end
		t.eq(s.profile.secretsFound.CarvedTotem, true)
		t.eq(s.granted, {}, "the Maul waits for the Hermit")
		t.eq(s.profile.cash, nil, "nothing here pays cash")
	end)

	t.test("a profile that already has five marks gets the Totem on the next sync", function()
		local s = setup()
		for _, mark in ipairs(s.Logic.Marks) do
			s.profile.secretsFound[mark.key] = true
		end
		local p = person(0, 0)
		t.eq(s.Service.SyncTotem(p), true)
		t.eq(s.profile.secretsFound.CarvedTotem, true)
		t.eq(s.Service.SyncTotem(p), false, "once")
	end)

	t.test("the cave box is set once and pays nothing", function()
		local s = setup()
		local box = s.Logic.CaveBox
		local p = person(box.x, box.z)
		t.eq(s.Service.Press(p, box.key), true)
		t.eq(s.profile.secretsFound.secretCaveBox, true)
		t.eq(s.profile.cash, nil)
		t.eq(s.Service.Press(person(0, 0), box.key), false, "far away")
	end)

	t.test("the Hermit: intro, then seeking, then the Maul once", function()
		local s = setup()
		local stand = s.Logic.Stand
		local model = hermitModel(stand.x, stand.z)
		local p = person(stand.x + 2, stand.z)
		t.eq(s.Service.Talk(p, model), "intro")
		t.eq(s.profile.questAxe.step, 1)
		t.eq(s.granted, {})
		local q = person(stand.x + 2, stand.z)
		for _, mark in ipairs(s.Logic.Marks) do
			s.profile.secretsFound[mark.key] = true
		end
		t.eq(s.Service.Talk(q, model), "ready")
		t.eq(s.granted, { "HermitsMaul" })
		t.eq(s.profile.questAxe.step, 2)
		t.eq(s.profile.secretsFound.CarvedTotem, true)
		local r = person(stand.x + 2, stand.z)
		t.eq(s.Service.Talk(r, model), "done")
		t.eq(s.granted, { "HermitsMaul" }, "never twice")
		t.eq(#s.said, 3)
	end)

	t.test("a lost Maul is given back, and far-off talk is refused", function()
		local s = setup()
		local stand = s.Logic.Stand
		local model = hermitModel(stand.x, stand.z)
		s.profile.questAxe.step = 2
		local far = person(stand.x + 60, stand.z)
		t.eq(s.Service.Talk(far, model), nil)
		t.eq(s.granted, {})
		t.eq(s.toasts, {}, "the Hermit's answer is the dialogue box, never a toast")
		t.eq(#s.said, 1, "told to come closer, in the box")
		local near = person(stand.x, stand.z + 1)
		t.eq(s.Service.Talk(near, model), "done")
		t.eq(s.granted, { "HermitsMaul" }, "the spare handle")
		t.ok(string.find(s.said[2], "spare", 1, true) ~= nil, s.said[2])
	end)

	t.test("talking is rate limited", function()
		local s = setup()
		local stand = s.Logic.Stand
		local model = hermitModel(stand.x, stand.z)
		local p = person(stand.x, stand.z)
		local spoke = 0
		for _ = 1, 10 do
			if s.Service.Talk(p, model) then
				spoke += 1
			end
		end
		t.ok(spoke <= 3, "at most the budget: " .. spoke)
	end)

	t.test("the secrets are built as prompts the server owns", function()
		local s = setup()
		local folder = Instance.new("Folder")
		s.Service.BuildSecrets(folder)
		local secrets = folder:FindFirstChild("Secrets")
		t.ok(secrets, "Secrets folder")
		for _, mark in ipairs(s.Logic.Marks) do
			local part = secrets:FindFirstChild("Secret_" .. mark.key)
			t.ok(part, mark.key)
			t.eq(part.CanCollide, false)
			t.ok(part:FindFirstChild("Secret"), "prompt")
		end
		t.ok(secrets:FindFirstChild("Secret_secretCaveBox"))
	end)

	-- The sea.
	local function hazard()
		local loader = t.loader({ services = { Players = {
			GetPlayers = function()
				return {}
			end,
		} } })
		local Hazard = loader:server("HazardService")
		local toasts = {}
		Hazard.Notify = function(_, text)
			table.insert(toasts, text)
		end
		return Hazard, toasts, loader:shared("World/WorldLayout"), loader:shared("HazardLogic")
	end

	t.test("the sea warns first, then hurts only after the grace", function()
		local Hazard, toasts, WorldLayout = hazard()
		Hazard.GearOf = function()
			return {}
		end
		local p = person(0, 0)
		local edge = WorldLayout.WorldHalf - WorldLayout.DeepSeaEdgeInset
		t.eq(Hazard.Check(p, edge - 10, 0, 100, 0.5), 0)
		t.eq(#toasts, 1, "the warning")
		t.eq(Hazard.Check(p, edge + 5, 0, 100, 0.5), 0)
		t.eq(#toasts, 2, "deep water")
		t.eq(Hazard.Check(p, edge + 5, 0, 100, 2), 0)
		t.eq(Hazard.Check(p, edge + 5, 0, 100, 1), 15)
		Hazard.Forget(p)
	end)

	t.test("the cave toast shows once per entry and only without a Lantern", function()
		local Hazard, toasts, WorldLayout, Logic = hazard()
		local c = WorldLayout.SecretCave
		local gear = {}
		Hazard.GearOf = function()
			return gear
		end
		local p = person(0, 0)
		Hazard.Check(p, c.x, c.z, 100, 0.5)
		Hazard.Check(p, c.x + 1, c.z, 100, 0.5)
		t.eq(toasts, { Logic.CaveDarkText })
		Hazard.Check(p, c.x + 60, c.z, 100, 0.5)
		Hazard.Check(p, c.x, c.z, 100, 0.5)
		t.eq(#toasts, 2, "again on re-entry")
		local lit = person(0, 0)
		gear = { "Lantern" }
		Hazard.Check(lit, c.x, c.z, 100, 0.5)
		t.eq(#toasts, 2, "a Lantern means no warning")
	end)
end
