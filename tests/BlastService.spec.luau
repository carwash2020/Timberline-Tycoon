--!nocheck
-- BlastService against fakes: the wallet, the people, the clock. It proves a
-- charge is bought on the server at the boulder (in range, not twice, the
-- price in hand), the fuse runs before anything breaks, the blast is looks
-- only, and the boulder comes back after BoulderRespawnSec, but never onto
-- anyone: a blocked box waits ten seconds and asks again.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
	local BlastLogic = t.shared("BlastLogic")
	local GameConfig = t.shared("GameConfig")
	local LandmarkArt = t.shared("Art/LandmarkArt")
	local WorldLayout = t.shared("World/WorldLayout")

	local function signal()
		local s = { list = {} }
		function s:Connect(fn)
			table.insert(self.list, fn)
			return { Disconnect = function() end }
		end
		function s:Fire(...)
			for _, fn in ipairs(self.list) do
				fn(...)
			end
		end
		return s
	end

	-- Lune's ProximityPrompt has no Triggered signal; give each one its own.
	local triggered = _G.__promptTriggered or setmetatable({}, { __mode = "k" })
	_G.__promptTriggered = triggered
	pcall(roblox.implementProperty, "ProximityPrompt", "Triggered", function(self)
		local s = triggered[self]
		if not s then
			s = signal()
			triggered[self] = s
		end
		return s
	end)

	local function world(options)
		options = options or {}
		local w = { cash = options.cash or 1000, spent = {}, toasts = {}, delays = {}, boulders = {} }
		w.workspace = Instance.new("Folder")
		w.workspace.Name = "Workspace"
		local added = signal()
		local loader = t.loader({
			mocks = {
				EconomyService = {
					SpendCash = function(_, amount, reason)
						if w.cash < amount then
							return false
						end
						w.cash -= amount
						table.insert(w.spent, { amount = amount, reason = reason })
						return true
					end,
				},
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
			services = {
				Players = {
					GetPlayers = function()
						return {}
					end,
				},
				CollectionService = {
					GetTagged = function(_, tag)
						return if tag == "Breakable" then w.boulders else {}
					end,
					GetInstanceAddedSignal = function()
						return added
					end,
				},
			},
			globals = {
				workspace = w.workspace,
				task = {
					delay = function(seconds, fn)
						table.insert(w.delays, { seconds = seconds, fn = fn })
					end,
				},
			},
		})
		w.B = loader:server("BlastService")
		w.map = Instance.new("Folder")
		-- The real boulders, as MapBuilder builds them.
		LandmarkArt.BuildW2(w.map)
		for _, d in ipairs(w.map:GetDescendants()) do
			if d.Name == "Boulder" and d:IsA("BasePart") then
				table.insert(w.boulders, d)
			end
		end
		w.B.Init(function(player, message)
			table.insert(w.toasts, { player = player, message = message })
		end)
		w.blockers = {}
		w.B.Blockers = function()
			return w.blockers
		end
		return w
	end

	local userIds = 500
	local function player(at)
		userIds += 1
		local char = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = CFrame.new(at)
		root.Parent = char
		char.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = char
		return { UserId = userIds, Name = "P", Character = char }, root
	end

	local function nextDelay(w)
		return table.remove(w.delays, 1)
	end

	local function fuseNow(seconds, fn)
		fn()
	end

	t.test("every boulder gets one hold-to-confirm prompt, and the three stand where the layout says", function()
		local w = world()
		t.eq(#w.boulders, #WorldLayout.Breakables)
		t.eq(#w.boulders, 3)
		for _, part in ipairs(w.boulders) do
			local prompt = part:FindFirstChildOfClass("ProximityPrompt")
			t.ok(prompt, "a prompt")
			t.eq(prompt.ActionText, "Set a blasting charge ($220)")
			t.eq(prompt.MaxActivationDistance, BlastLogic.PromptRange)
			t.ok(prompt.HoldDuration >= 0.5, "held, so a stray tap does not spend $220")
			t.eq(prompt.RequiresLineOfSight, false)
			t.ok(w.B._boulders[part], "tracked")
		end
		w.B.Init(function() end)
		local count = 0
		for _, d in ipairs(w.boulders[1]:GetChildren()) do
			if d:IsA("ProximityPrompt") then
				count += 1
			end
		end
		t.eq(count, 1, "binding twice adds nothing")
	end)

	t.test("a charge costs $220, lights a fuse, and only then does the boulder break", function()
		local w = world()
		local part = w.boulders[1]
		local ann = player(part.CFrame.Position + Vector3.new(6, 0, 0))
		local fuse
		local result = w.B.Place(ann, part, function(seconds, fn)
			fuse = { seconds = seconds, fn = fn }
		end)
		t.eq(result, "fused")
		t.eq(w.cash, 1000 - 220)
		t.eq(w.spent[1].amount, GameConfig.DynamitePrice)
		t.eq(fuse.seconds, 5)
		t.eq(w.toasts[#w.toasts].message, BlastLogic.FuseText())
		t.eq(part.CanCollide, true, "still there during the fuse")
		t.eq(part.Transparency, 0)
		t.eq(part:FindFirstChildOfClass("ProximityPrompt").Enabled, false, "no second charge on it")
		t.eq(w.B.Place(ann, part, fuseNow), "busy", "a second charge is refused")
		t.eq(w.cash, 1000 - 220, "and not charged")
		fuse.fn()
		t.eq(part.CanCollide, false)
		t.eq(part.Transparency, 1)
		t.eq(part.CanQuery, false)
		-- The blast is looks only.
		local blast
		for _, d in ipairs(w.workspace:GetChildren()) do
			if d.ClassName == "Explosion" then
				blast = d
			end
		end
		t.ok(blast, "an explosion")
		t.eq(blast.BlastPressure, 0)
		t.eq(blast.DestroyJointRadiusPercent, 0)
		-- And a respawn is queued for BoulderRespawnSec.
		local d = nextDelay(w)
		t.eq(d.seconds, GameConfig.BoulderRespawnSec)
	end)

	t.test("refused: out of range, no fare, and no live character; nothing is charged", function()
		local w = world()
		local part = w.boulders[1]
		local far = player(part.CFrame.Position + Vector3.new(BlastLogic.PlaceRange + 5, 0, 0))
		t.eq(w.B.Place(far, part, fuseNow), "far")
		w.cash = 219
		local poor = player(part.CFrame.Position)
		t.eq(w.B.Place(poor, part, fuseNow), "short")
		t.eq(w.toasts[#w.toasts].message, "A blasting charge costs $220.")
		t.eq(w.cash, 219)
		t.eq(w.B.Place({ UserId = 1 }, part, fuseNow), "gone")
		t.eq(#w.spent, 0)
		t.eq(part.Transparency, 0, "nothing broke")
	end)

	t.test(
		"the boulder comes back after 20 minutes, and waits ten seconds at a time while anyone is in its box",
		function()
			local w = world()
			local part = w.boulders[2]
			local ann = player(part.CFrame.Position)
			w.B.Place(ann, part, fuseNow)
			t.eq(part.Transparency, 1)
			local first = nextDelay(w)
			t.eq(first.seconds, 1200)
			w.blockers = { { x = part.CFrame.Position.X, y = part.CFrame.Position.Y, z = part.CFrame.Position.Z } }
			first.fn()
			t.eq(part.Transparency, 1, "someone is standing there: it stays gone")
			local retry = nextDelay(w)
			t.eq(retry.seconds, 10)
			retry.fn()
			t.eq(part.Transparency, 1)
			local again = nextDelay(w)
			t.eq(again.seconds, 10)
			w.blockers = {}
			again.fn()
			t.eq(part.Transparency, 0, "clear: it is back")
			t.eq(part.CanCollide, true)
			t.eq(part:FindFirstChildOfClass("ProximityPrompt").Enabled, true)
			t.eq(#w.delays, 0, "and nothing else is waiting")
			-- It can be blasted again.
			t.eq(w.B.Place(ann, part, fuseNow), "fused")
		end
	)

	t.test("the prompt buys a charge through the same checks", function()
		local w = world()
		local part = w.boulders[3]
		local ann = player(part.CFrame.Position + Vector3.new(4, 0, 0))
		triggered[part:FindFirstChildOfClass("ProximityPrompt")]:Fire(ann)
		t.eq(w.cash, 1000 - 220)
		t.eq(#w.delays, 1, "the fuse is on")
	end)
end
