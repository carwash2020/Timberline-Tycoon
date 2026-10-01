--!nocheck
-- CarryService's restack (ACT-01): carried logs are welded to the torso at
-- CarryLayout.LogOffset(slot), and whenever the count changes the logs
-- still in hand move down to the lowest slots. So a log left alone after
-- its partner was loaded into a nearly full bed, sent down the Cloud
-- Chute or forged sits at slot 0, held by the arms, never at slot 1 under
-- them.
return function(t)
	local roblox = t.roblox
	local CFrame, Instance = roblox.CFrame, roblox.Instance
	local CarryLayout = t.shared("CarryLayout")

	-- Parts keep their CFrame in single precision.
	local function near(a, b)
		return (a.Position - b.Position).Magnitude < 1e-4
			and (a.RightVector - b.RightVector).Magnitude < 1e-4
			and (a.UpVector - b.UpVector).Magnitude < 1e-4
	end

	local function signal()
		local entries = {}
		local s = {}
		function s:Connect(fn)
			local entry = { fn = fn, on = true }
			table.insert(entries, entry)
			return {
				Disconnect = function()
					entry.on = false
				end,
			}
		end
		function s:Fire()
			for _, e in ipairs(entries) do
				if e.on then
					e.fn()
				end
			end
		end
		function s:Live()
			local n = 0
			for _, e in ipairs(entries) do
				if e.on then
					n += 1
				end
			end
			return n
		end
		return s
	end

	-- A player whose character's torso (UpperTorso, or Torso on R6) stands
	-- somewhere off the origin, turned, so offsets have to be relative.
	local function newPlayer(torsoName)
		local char = Instance.new("Model")
		char.Name = "Character"
		local torso = Instance.new("Part")
		torso.Name = torsoName or "UpperTorso"
		torso.CFrame = CFrame.new(20, 5, -8) * CFrame.Angles(0, 0.7, 0)
		torso.Parent = char
		local attrs, changed = {}, {}
		local p = { Name = "Tester", UserId = 7, Character = char, torso = torso }
		function p:SetAttribute(key, value)
			if attrs[key] == value then
				return
			end
			attrs[key] = value
			if changed[key] then
				changed[key]:Fire()
			end
		end
		function p:GetAttribute(key)
			return attrs[key]
		end
		function p:GetAttributeChangedSignal(key)
			changed[key] = changed[key] or signal()
			return changed[key]
		end
		p.live = function()
			local n = 0
			for _, s in pairs(changed) do
				n += s:Live()
			end
			return n
		end
		return p
	end

	local function setup(torsoName)
		local logs = {}
		local loader = t.loader({
			mocks = {
				TreeService = {
					GetLog = function(uid)
						return logs[uid]
					end,
					TakeLog = function(uid)
						local rec = logs[uid]
						logs[uid] = nil
						return rec
					end,
				},
			},
		})
		local CarryService = loader:server("CarryService")
		local player = newPlayer(torsoName)
		CarryService.Start(player)
		-- Picks up a log the way GameServer does: at `slot`, welded to the torso.
		local function pickup(uid, slot, woodId)
			local model = Instance.new("Model")
			local pp = Instance.new("Part")
			pp.Name = "Log"
			pp.Parent = model
			model.PrimaryPart = pp
			pp:SetAttribute("CarrySlot", slot)
			pp.CFrame = player.torso.CFrame * CarryLayout.LogOffset(slot)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = player.torso
			weld.Part1 = pp
			weld.Parent = pp
			logs[uid] = { model = model, def = { id = woodId or "oak" }, value = 10, tags = {} }
			CarryService.Hands(player)[uid] = true
			CarryService.Publish(player)
			return pp, weld
		end
		return CarryService, player, pickup, logs
	end

	local function welds(pp)
		local out = {}
		for _, child in ipairs(pp:GetChildren()) do
			if child:IsA("WeldConstraint") then
				table.insert(out, child)
			end
		end
		return out
	end

	local function heldAt(pp, torso, slot)
		local w = welds(pp)
		return pp:GetAttribute("CarrySlot") == slot
			and near(pp.CFrame, torso.CFrame * CarryLayout.LogOffset(slot))
			and #w == 1
			and w[1].Part0 == torso
			and w[1].Part1 == pp
	end

	t.test("the log left after slot 0 is loaded moves up to slot 0, re-welded", function()
		local CarryService, player, pickup = setup()
		pickup("a", 0)
		local b = pickup("b", 1)
		-- GameServer's load: slot 0 fits the bed, slot 1 doesn't.
		CarryService.Hands(player).a = nil
		player:SetAttribute("CarriedLogs", 1)
		t.ok(heldAt(b, player.torso, 0), "the lone log sits at slot 0")
	end)

	t.test("taking slot 1 leaves slot 0 where it is, its weld untouched", function()
		local CarryService, player, pickup = setup()
		local a, weld = pickup("a", 0)
		pickup("b", 1)
		CarryService.Hands(player).b = nil
		player:SetAttribute("CarriedLogs", 1)
		t.ok(heldAt(a, player.torso, 0))
		t.ok(welds(a)[1] == weld, "not re-welded")
	end)

	t.test("TakeLogs (Cloud Chute, forge) restacks too", function()
		local CarryService, player, pickup = setup()
		pickup("a", 0, "lumenwood")
		local b = pickup("b", 1, "oak")
		local taken = CarryService.TakeLogs(player, function(wood)
			return wood.id == "lumenwood"
		end)
		t.eq(#taken, 1)
		t.eq(player:GetAttribute("CarriedLogs"), 1)
		t.ok(heldAt(b, player.torso, 0))
	end)

	t.test("R6: the Torso is used the same way", function()
		local CarryService, player, pickup = setup("Torso")
		pickup("a", 0)
		local b = pickup("b", 1)
		CarryService.Hands(player).a = nil
		player:SetAttribute("CarriedLogs", 1)
		t.ok(heldAt(b, player.torso, 0))
	end)

	t.test("a pickup into a compact stack moves nothing", function()
		local CarryService, player, pickup = setup()
		local a, weldA = pickup("a", 0)
		local b, weldB = pickup("b", 1)
		t.eq(player:GetAttribute("CarriedLogs"), 2)
		t.ok(heldAt(a, player.torso, 0) and welds(a)[1] == weldA)
		t.ok(heldAt(b, player.torso, 1) and welds(b)[1] == weldB)
		CarryService.Restack(player)
		t.ok(welds(a)[1] == weldA and welds(b)[1] == weldB, "already compact: left alone")
	end)

	t.test("no character, no torso, stale or destroyed logs: nothing breaks", function()
		local CarryService, player, pickup, logs = setup()
		pickup("a", 0)
		local b = pickup("b", 1)
		-- A stale uid (its record gone) is skipped.
		CarryService.Hands(player).ghost = true
		CarryService.Hands(player).a = nil
		logs.a = nil
		-- No character: nothing to weld to, so nothing moves.
		local char = player.Character
		player.Character = nil
		CarryService.Restack(player)
		t.eq(b:GetAttribute("CarrySlot"), 1)
		-- Back, but its torso is gone: still nothing.
		player.Character = char
		player.torso.Parent = nil
		CarryService.Restack(player)
		t.eq(b:GetAttribute("CarrySlot"), 1)
		-- Torso back: b moves up past the ghost.
		player.torso.Parent = char
		CarryService.Restack(player)
		t.ok(heldAt(b, player.torso, 0))
		-- A log whose model was destroyed isn't touched.
		local c = pickup("c", 1)
		c.Parent = nil
		CarryService.Hands(player).b = nil
		player:SetAttribute("CarriedLogs", 1)
		t.eq(c:GetAttribute("CarrySlot"), 1)
	end)

	t.test("Stop disconnects the listener", function()
		local CarryService, player, pickup = setup()
		t.eq(player.live(), 1)
		CarryService.Start(player) -- started twice: still one listener
		t.eq(player.live(), 1)
		pickup("a", 0)
		CarryService.Stop(player)
		t.eq(player.live(), 0)
		t.eq(CarryService.Hands(player), nil)
	end)
end
