--!nocheck
-- NPCTalkService: the server's record of who each NPC is talking to, set by
-- the Talk prompt, ended by the box closing, and released on every other way
-- out: out of range, dead, left, the NPC removed or lying down, a box left up.
return function(t)
	local fs = require("@lune/fs")
	local V3 = t.roblox.Vector3

	local people = {}
	local function player(userId, x, z)
		local hrp = { Position = V3.new(x, 3, z) }
		function hrp:IsA(class)
			return class == "BasePart"
		end
		local humanoid = { Health = 100 }
		local char = {}
		function char:FindFirstChild(name)
			if name == "HumanoidRootPart" then
				return hrp
			end
			return nil
		end
		function char:FindFirstChildOfClass(class)
			if class == "Humanoid" then
				return humanoid
			end
			return nil
		end
		local who = { UserId = userId, Name = "p" .. userId, Character = char }
		people[userId] = who
		return who, hrp, humanoid
	end

	local function signal()
		local s = { fns = {} }
		function s:Connect(fn)
			table.insert(self.fns, fn)
			return { Disconnect = function() end }
		end
		function s:Fire(...)
			for _, fn in ipairs(self.fns) do
				fn(...)
			end
		end
		return s
	end

	-- An NPC model with a Talk prompt, standing at (0, 3, 0).
	local function npc(id)
		local root = { Position = V3.new(0, 3, 0) }
		local attrs = { NPCId = id }
		local prompt = { Triggered = signal(), Name = "Talk" }
		function prompt:IsA(class)
			return class == "ProximityPrompt"
		end
		local model = { Parent = {}, PrimaryPart = root, Destroying = signal() }
		function model:GetAttribute(name)
			return attrs[name]
		end
		function model:SetAttribute(name, value)
			attrs[name] = value
		end
		function model:FindFirstChild(name)
			if name == "Talk" then
				return prompt
			end
			return nil
		end
		function model:IsA(class)
			return class == "Model"
		end
		return model, prompt, attrs
	end

	local function setup()
		people = {}
		local loader = t.loader({
			services = {
				Players = {
					GetPlayerByUserId = function(_, userId)
						return people[userId]
					end,
				},
			},
			mocks = {
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
		})
		return loader:server("NPCTalkService"), loader:shared("TalkLock"), loader:shared("DialogueFlow")
	end

	t.test("pressing Talk in reach faces that player; the box closing lets them go", function()
		local Service, TalkLock = setup()
		local model, prompt, attrs = npc("Dale")
		Service.Track(model)
		local ann = player(1, 4, 0)
		prompt.Triggered:Fire(ann)
		t.eq(attrs[TalkLock.Attribute], 1)
		t.eq(Service.TalkingWith(model), 1)
		Service.End(ann, "Dale")
		t.eq(attrs[TalkLock.Attribute], nil, "released")
		t.eq(Service.TalkingWith(model), nil)
	end)

	t.test("no talk from too far, from a dead player, or to a keeper who is asleep", function()
		local Service, TalkLock = setup()
		local model, prompt, attrs = npc("Dale")
		Service.Track(model)
		prompt.Triggered:Fire(player(1, TalkLock.BeginReach() + 1, 0))
		t.eq(attrs[TalkLock.Attribute], nil, "too far")
		local _, _, humanoid = player(2, 3, 0)
		humanoid.Health = 0
		prompt.Triggered:Fire(people[2])
		t.eq(attrs[TalkLock.Attribute], nil, "dead")
		player(3, 3, 0)
		attrs.Asleep = true
		prompt.Triggered:Fire(people[3])
		t.eq(attrs[TalkLock.Attribute], nil, "asleep: nobody to turn")
		attrs.Asleep = false
		prompt.Triggered:Fire(people[3])
		t.eq(attrs[TalkLock.Attribute], 3, "awake again")
	end)

	t.test("two players on one NPC: it turns to the newest, back to the other, and only then lets go", function()
		local Service, TalkLock = setup()
		local model, prompt, attrs = npc("Millie")
		Service.Track(model)
		local ann, bob = player(1, 5, 0), player(2, -5, 0)
		prompt.Triggered:Fire(ann)
		prompt.Triggered:Fire(bob)
		t.eq(attrs[TalkLock.Attribute], 2, "the most recent")
		Service.End(bob, "Millie")
		t.eq(attrs[TalkLock.Attribute], 1, "Ann is still talking: still held, facing her")
		Service.End(ann, "Millie")
		t.eq(attrs[TalkLock.Attribute], nil, "nobody left: released")
		-- And in the other order: the first one closing does not release the newest.
		prompt.Triggered:Fire(ann)
		prompt.Triggered:Fire(bob)
		Service.End(ann, "Millie")
		t.eq(attrs[TalkLock.Attribute], 2)
	end)

	t.test("End names the NPC: another NPC's box closing does not release this one", function()
		local Service, TalkLock = setup()
		local a, promptA, attrsA = npc("Dale")
		local b, promptB, attrsB = npc("Tink")
		Service.Track(a)
		Service.Track(b)
		local ann = player(1, 3, 0)
		promptA.Triggered:Fire(ann)
		promptB.Triggered:Fire(ann)
		Service.End(ann, "Tink")
		t.eq(attrsA[TalkLock.Attribute], 1, "Dale is still talking with her")
		t.eq(attrsB[TalkLock.Attribute], nil)
		Service.End(ann, "Nobody")
		t.eq(attrsA[TalkLock.Attribute], 1, "an unknown id changes nothing")
		Service.End(ann, "Dale")
		t.eq(attrsA[TalkLock.Attribute], nil)
	end)

	t.test("walking out of range, dying or leaving releases without any message", function()
		local Service, TalkLock, DialogueFlow = setup()
		local model, prompt, attrs = npc("Gus")
		Service.Track(model)
		local ann, hrp = player(1, 5, 0)
		prompt.Triggered:Fire(ann)
		Service.Sweep(os.clock())
		t.eq(attrs[TalkLock.Attribute], 1, "close by: held")
		hrp.Position = V3.new(DialogueFlow.CloseDistance + 2, 3, 0)
		Service.Sweep(os.clock())
		t.eq(attrs[TalkLock.Attribute], 1, "a step back past the box's line, inside the slack, keeps it")
		hrp.Position = V3.new(DialogueFlow.CloseDistance + TalkLock.CloseSlack + 5, 3, 0)
		Service.Sweep(os.clock())
		t.eq(attrs[TalkLock.Attribute], nil, "walked off")

		hrp.Position = V3.new(5, 3, 0)
		prompt.Triggered:Fire(ann)
		t.eq(attrs[TalkLock.Attribute], 1)
		local bob, _, bobHumanoid = player(2, 4, 0)
		prompt.Triggered:Fire(bob)
		t.eq(attrs[TalkLock.Attribute], 2)
		bobHumanoid.Health = 0
		Service.Sweep(os.clock())
		t.eq(attrs[TalkLock.Attribute], 1, "Bob died: back to Ann")
		people[1] = nil -- Ann left the game
		Service.Sweep(os.clock())
		t.eq(attrs[TalkLock.Attribute], nil, "nobody left")
	end)

	t.test("Left drops a leaving player at once", function()
		local Service, TalkLock = setup()
		local model, prompt, attrs = npc("Rosa")
		Service.Track(model)
		local ann = player(1, 3, 0)
		prompt.Triggered:Fire(ann)
		Service.Left(ann)
		t.eq(attrs[TalkLock.Attribute], nil)
		t.eq(Service.TalkingWith(model), nil)
	end)

	t.test("the NPC removed or lying down clears the lock and leaves nothing behind", function()
		local Service, TalkLock = setup()
		local model, prompt, attrs = npc("Hazel")
		Service.Track(model)
		local ann = player(1, 3, 0)
		prompt.Triggered:Fire(ann)
		attrs.Asleep = true
		Service.Sweep(os.clock())
		t.eq(attrs[TalkLock.Attribute], nil, "she lay down")
		t.eq(Service.TalkingWith(model), nil)
		attrs.Asleep = false
		prompt.Triggered:Fire(ann)
		t.eq(attrs[TalkLock.Attribute], 1)
		model.Parent = nil
		Service.Sweep(os.clock())
		t.eq(attrs[TalkLock.Attribute], nil, "removed from the world")
		t.eq(Service.TalkingWith(model), nil)
		-- The same again through Destroying, even if no sweep came first.
		local other, otherPrompt, otherAttrs = npc("Pip")
		Service.Track(other)
		otherPrompt.Triggered:Fire(ann)
		t.eq(otherAttrs[TalkLock.Attribute], 1)
		other.Destroying:Fire()
		t.eq(otherAttrs[TalkLock.Attribute], nil)
		t.eq(Service.TalkingWith(other), nil)
	end)

	t.test("a client that never says it closed is let go once the box would have timed out", function()
		local Service, TalkLock, DialogueFlow = setup()
		local model, prompt, attrs = npc("Bram")
		Service.Track(model)
		local ann = player(1, 3, 0)
		prompt.Triggered:Fire(ann)
		local began = os.clock()
		Service.Sweep(began + DialogueFlow.MaxOpenSeconds)
		t.eq(attrs[TalkLock.Attribute], 1, "still inside the box's own time")
		Service.Sweep(began + DialogueFlow.MaxOpenSeconds + TalkLock.TimeoutSlack + 5)
		t.eq(attrs[TalkLock.Attribute], nil, "stuck no longer")
	end)

	t.test("a keeper's reply box (after Yes or No) takes the lock up again, nearest keeper of that id", function()
		local Service, TalkLock = setup()
		local near, _, nearAttrs = npc("Dale")
		local far, _, farAttrs = npc("Dale")
		far.PrimaryPart.Position = V3.new(300, 3, 0)
		Service.Track(near)
		Service.Track(far)
		local ann = player(1, 3, 0)
		t.eq(Service.BeginById(ann, "Dale"), true)
		t.eq(nearAttrs[TalkLock.Attribute], 1)
		t.eq(farAttrs[TalkLock.Attribute], nil)
		Service.End(ann, "Dale")
		t.eq(nearAttrs[TalkLock.Attribute], nil)
		t.eq(Service.BeginById(ann, "Nobody"), false)
		t.eq(Service.BeginById(player(2, 100, 0), "Dale"), false, "out of reach: no lock")
	end)

	t.test("the Dialogue remote's end intent is wired, rate limited, and names an NPC id", function()
		local service = fs.readFile("src/ServerScriptService/DialogueService.luau")
		t.ok(string.find(service, 'action == "end"', 1, true) ~= nil, "end intent")
		t.ok(string.find(service, 'RateLimiter.Allow(player, "TalkEnd")', 1, true) ~= nil, "rate limited")
		t.ok(string.find(service, "NPCTalkService.End(player, a)", 1, true) ~= nil)
		t.ok(
			string.find(service, "NPCTalkService.BeginById(player, keeper.id)", 1, true) ~= nil,
			"a reply box is a talk"
		)
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DialogueUI.luau")
		t.ok(string.find(ui, 'FireServer("end", speaker)', 1, true) ~= nil, "the box says it closed")
		local game = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		t.ok(string.find(game, "NPCTalkService.Init()", 1, true) ~= nil, "started with the server")
	end)

	t.test("NPCController faces the partner and holds a walker, then returns to normal", function()
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/NPCController.luau")
		t.ok(string.find(src, "TalkLock.Want(rig.homeYaw", 1, true) ~= nil, "a standing NPC turns to the partner")
		t.ok(string.find(src, "TalkLock.Want(visual.yaw", 1, true) ~= nil, "a walker stopped for a talk does too")
		t.ok(string.find(src, "TalkLock.HoldAt(true", 1, true) ~= nil, "a talking walker holds")
		t.ok(
			string.find(src, "DialogueUI.IsTalkingTo(rig.model)", 1, true) ~= nil,
			"this screen's own box counts at once"
		)
	end)
end
