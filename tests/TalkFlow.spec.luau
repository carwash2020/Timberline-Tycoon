--!nocheck
-- The shop talk and the counter purchase, end to end on the server: a Talk
-- press opens the keeper's box, the client's "end" never eats the Dialogue
-- budget, and nothing the talk-facing code does can stop the box, the offer
-- or the payment (PRs #107-#111: "talking to shop NPCs is broken" and "can't
-- buy anything").
return function(t)
	local Instance = t.roblox.Instance
	local CFrame = t.roblox.CFrame
	local Vector3 = t.roblox.Vector3

	local function remoteWith(sent)
		local box = {}
		box.remote = {
			OnServerEvent = {
				Connect = function(_, fn)
					box.handler = fn
					return { Disconnect = function() end }
				end,
			},
			FireClient = function(_, _player, payload)
				table.insert(sent, payload)
			end,
		}
		return box
	end

	local function person(at, userId)
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.CFrame = CFrame.new(at)
		local char = Instance.new("Model")
		hrp.Parent = char
		return { Name = "Tester" .. (userId or 7), UserId = userId or 7, Character = char }
	end

	-- A keeper model whose Talk prompt the spec can press, like the engine's.
	local function keeperModel(id)
		local fns = {}
		local prompt = { Name = "Talk", Triggered = {} }
		function prompt.Triggered:Connect(fn)
			table.insert(fns, fn)
			return { Disconnect = function() end }
		end
		function prompt:IsA(class)
			return class == "ProximityPrompt"
		end
		local root = { Position = Vector3.new(0, 3, 0) }
		local attrs = { NPCId = id }
		local model = { Name = id, Parent = {}, PrimaryPart = root }
		function model:GetAttribute(name)
			return attrs[name]
		end
		function model:SetAttribute(name, value)
			attrs[name] = value
		end
		function model:FindFirstChild(name)
			return if name == "Talk" then prompt else nil
		end
		function model:IsA(class)
			return class == "Model"
		end
		return model, function(who)
			for _, fn in ipairs(fns) do
				fn(who)
			end
		end, attrs
	end

	local function quietBoxes()
		return {
			Offered = function()
				return nil
			end,
			Get = function() end,
			InCounter = function()
				return false
			end,
			Decline = function() end,
			Pay = function() end,
		}
	end

	local function bootDialogue(extra, services)
		local mocks = {
			BoxService = quietBoxes(),
			ProfileService = {
				GetProfile = function()
					return { cash = 1000, storage = {}, axes = {}, materials = {} }
				end,
			},
		}
		for k, v in pairs(extra or {}) do
			mocks[k] = v
		end
		local loader = t.loader({ mocks = mocks, services = services })
		return loader, loader:server("DialogueService"), loader:server("NPCTalkService")
	end

	t.test("every keeper's greeting reaches the box as readable pages", function()
		local Flow = t.shared("DialogueFlow")
		local NPCData = t.shared("NPCData")
		for _, shop in ipairs(NPCData.Shops) do
			local sent = {}
			local box = remoteWith(sent)
			local _, D = bootDialogue()
			D.Init(box.remote)
			for _, roll in ipairs({ 0, 0.5, 0.999 }) do
				D.Roll = function()
					return roll
				end
				box.handler(person(Vector3.new(0, 3, 0), 7 + math.floor(roll * 10)), "open", shop)
			end
			t.eq(#sent, 3, shop .. " answered each")
			for _, payload in ipairs(sent) do
				t.eq(type(payload.text), "string", shop .. " text")
				t.ok(payload.speaker ~= nil, shop .. " names its keeper")
				local lines = Flow.ServerLines(payload)
				t.ok(#lines >= 1, shop .. " has lines")
				local pages = Flow.Pages(lines, 30)
				t.ok(#pages >= 1, shop .. " pages")
				t.ok(Flow.New(payload.speaker, "x", nil, pages) ~= nil, shop .. " opens a box")
			end
		end
	end)

	t.test("Talk on Tink, Hazel and Dale opens their box every time, 'end' costs no Dialogue budget", function()
		for id, shop in pairs({ Tink = "ToolShed", Hazel = "HearthAndHome", Dale = "Dealership" }) do
			local sent = {}
			local box = remoteWith(sent)
			local _, Dialogue = bootDialogue()
			Dialogue.Init(box.remote)
			local ann = person(Vector3.new(4, 3, 0), 11)
			for round = 1, 3 do
				box.handler(ann, "open", shop)
				t.eq(#sent, round, id .. " answered open #" .. round)
				box.handler(ann, "end", id)
				box.handler(ann, "end", id)
			end
			box.handler(ann, "end", id)
			box.handler(ann, "end", id)
			box.handler(ann, "end", id)
			box.handler(ann, "open", shop)
			t.eq(#sent, 4, id .. ": the fourth open in the second still gets its box after eight ends")
		end
	end)

	t.test("the Talk prompt's press faces the keeper; the box is sent; the end lets go", function()
		local sent = {}
		local box = remoteWith(sent)
		local people = {}
		local _, Dialogue, TalkService = bootDialogue(nil, {
			Players = {
				GetPlayerByUserId = function(_, id)
					return people[id]
				end,
			},
		})
		local TalkLock = t.shared("TalkLock")
		Dialogue.Init(box.remote)
		local model, press, attrs = keeperModel("Tink")
		TalkService.Track(model)
		-- (Lune's Model has no FindFirstChildOfClass: a plain character stands in.)
		local hrp = { Position = Vector3.new(4, 3, 0) }
		function hrp:IsA(class)
			return class == "BasePart"
		end
		local char = {}
		function char:FindFirstChild(name)
			return if name == "HumanoidRootPart" then hrp else nil
		end
		function char:FindFirstChildOfClass()
			return { Health = 100 }
		end
		local ann = { Name = "Ann", UserId = 11, Character = char }
		people[11] = ann
		press(ann)
		t.eq(attrs[TalkLock.Attribute], 11, "the keeper turns to her")
		box.handler(ann, "open", "ToolShed")
		t.eq(sent[1].speaker, "Tink")
		t.eq(attrs[TalkLock.Attribute], 11, "still facing her after the box is sent")
		box.handler(ann, "end", "Tink")
		t.eq(attrs[TalkLock.Attribute], nil, "and let go when the box is closed")
	end)

	t.test("nothing about facing the keeper can stop the box or the offer", function()
		local sent = {}
		local box = remoteWith(sent)
		local _, Dialogue = bootDialogue({
			NPCTalkService = {
				BeginById = function()
					error("boom: the facing code threw")
				end,
				End = function() end,
			},
		})
		Dialogue.Init(box.remote)
		box.handler(person(Vector3.new(0, 3, 0), 7), "open", "ToolShed")
		t.eq(#sent, 1, "the box was sent")
		t.eq(sent[1].speaker, "Tink")
		Dialogue.Roll = function()
			error("boom: roll")
		end
		box.handler(person(Vector3.new(0, 3, 0), 8), "open", "HearthAndHome")
		t.eq(#sent, 2)
		t.eq(sent[2].intro, nil)
		t.eq(type(sent[2].text), "string")
	end)

	-- A box on the counter, Talk to the keeper, Yes pays; with the client's
	-- "end" in the middle exactly as DialogueUI sends it (end, then pick).
	t.test("buying: the offer, the client's end, then Yes charges and thanks", function()
		local charges = {}
		local loader = t.loader({
			mocks = {
				ShopService = {
					Loop = function()
						return 2
					end,
					ChargeAndGrant = function(_player, rec)
						table.insert(charges, rec.uid)
						return true, "thanks", "axe-1"
					end,
				},
				ProfileService = {
					GetProfile = function()
						return { cash = 1000, storage = {}, axes = {}, materials = {} }
					end,
				},
			},
		})
		local Box = loader:server("BoxService")
		local Dialogue = loader:server("DialogueService")
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(10, 2, 6)
		counter.CFrame = CFrame.new(0, 3, 0)
		Box.Make({
			uid = "box-1",
			shop = "ToolShed",
			itemKind = "Axe",
			itemId = "SteelAxe",
			displayName = "Steel Axe",
			cf = CFrame.new(0, 4.5, 0),
			counter = counter,
			zoneCf = CFrame.new(),
			zoneSize = Vector3.new(18, 1, 14),
			onShelf = true,
		})
		local sent = {}
		local remote = remoteWith(sent)
		Dialogue.Init(remote.remote)
		local ann = person(Vector3.new(0, 4.5, 0), 7)
		remote.handler(ann, "open", "ToolShed")
		t.eq(sent[1].line, "offer")
		t.eq(sent[1].choice, true)
		remote.handler(ann, "end", "Tink")
		remote.handler(ann, "pick", "yes", "box-1")
		t.eq(charges, { "box-1" }, "paid")
		t.eq(sent[#sent].line, "thanks", "and thanked")
		t.ok(Box.Get("box-1").paid)
	end)
end
