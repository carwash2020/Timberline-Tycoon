--!nocheck
-- Why GameConfig.CutEdge is 0.5 and not 0.3 (T389 follow-up).
--
-- The rule it protects (T389 brief): no new part shorter than 0.5 stud near
-- a cut. A cut lands exactly where the cut-line band showed it (the client
-- band and the server both use SectionLogic.ClampHeight), so the two pieces
-- of a cut are `h` and `length - h`, and the shortest piece a swing can
-- leave is the clamp's end inset. No rule that keeps the cut on the band
-- can keep pieces longer than that inset, so the inset itself must be at
-- least 0.5. At 0.3 a cut at the base leaves a 0.3 stump, and a second cut
-- 0.2 from an earlier one leaves a 0.3 slab. Refusing the cut instead would
-- leave the swing doing nothing near the ends, which feels worse than the
-- band sitting 0.5 in.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
	local players = {
		GetPlayers = function()
			return {}
		end,
	}
	local loader = t.loader({ services = { Players = players, PhysicsService = {} } })
	local Wood = loader:server("WoodService")
	local GameConfig = t.shared("GameConfig")
	local SectionLogic = t.shared("SectionLogic")
	local sig = {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
	local params = {
		new = function()
			return {}
		end,
	}
	local clientLoader = t.loader({
		services = {
			Debris = { AddItem = function() end },
			ContextActionService = {
				GetAllBoundActionInfo = function()
					return {}
				end,
			},
			GuiService = {},
			Players = { LocalPlayer = { UserId = 1, CharacterAdded = sig } },
			RunService = { Heartbeat = sig },
			UserInputService = { InputBegan = sig },
		},
		mocks = {
			WoodFX = { Predict = function() end },
			HUD = { Toast = function() end, TimedToast = function() end },
			Quality = {
				Tier = function()
					return "high"
				end,
			},
			SoundData = {
				Play = function() end,
				SwingFor = function()
					return "Swing"
				end,
			},
			Net = {
				Remote = function()
					return { FireServer = function() end }
				end,
			},
		},
		globals = {
			workspace = {
				GetAttribute = function(_, name)
					return if name == "CoreLoopActive" then 2 else nil
				end,
				GetPropertyChangedSignal = function()
					return sig
				end,
			},
			RaycastParams = params,
			OverlapParams = params,
			task = {
				wait = function()
					return 0.25
				end,
			},
		},
	})
	local CutController = clientLoader:load("StarterPlayer/StarterPlayerScripts/CutController")

	local MIN_PIECE = 0.5 -- the T389 brief: no new part shorter than this

	local function section(length)
		local model = Instance.new("Model")
		local s = Instance.new("Part")
		s.Name = "Section"
		s.Size = Vector3.new(1.2, length, 1.2)
		s.CFrame = CFrame.new(3, length / 2, 4)
		s.Anchored = true
		s:SetAttribute("Section", 1)
		s.Parent = model
		return s
	end

	t.test("CutEdge is at least 0.5: it is the shortest piece a cut can leave (fails at 0.3)", function()
		t.ok(
			GameConfig.CutEdge >= MIN_PIECE,
			"CutEdge " .. GameConfig.CutEdge .. " lets a cut leave a piece shorter than " .. MIN_PIECE
		)
		-- Measured over every aim height of 8 and 3 stud sections: the
		-- shortest piece the clamp can leave.
		for _, length in ipairs({ 8, 3 }) do
			local shortest = math.huge
			for i = -20, 20 do
				local h = SectionLogic.ClampHeight(i * length / 20, length)
				shortest = math.min(shortest, h, length - h)
			end
			t.ok(shortest >= MIN_PIECE - 1e-9, length .. " stud section: shortest piece " .. shortest)
		end
		-- The same measure at 0.3, to show the rule is what 0.5 buys.
		local atOld = math.min(SectionLogic.ClampHeight(-4, 8, 0.3), 8 - SectionLogic.ClampHeight(-4, 8, 0.3))
		t.ok(math.abs(atOld - 0.3) < 1e-9 and atOld < MIN_PIECE, "at 0.3 the base cut leaves a 0.3 stump")
	end)

	t.test("the cut lands where the band showed it, and both real pieces are 0.5 or longer", function()
		local length = 8
		for i = -10, 10 do
			local s = section(length)
			local hit = Vector3.new(3.6, i * 0.5 + length / 2, 4) -- a swing's hit point, some past the ends
			local _, shown = CutController.GuideAt("wood", s.CFrame, s.Size, hit)
			local cut = SectionLogic.ClampHeight(s.CFrame:PointToObjectSpace(hit).Y, s.Size.Y)
			t.ok(math.abs(shown - cut) < 1e-9, "band and server clamp agree")
			local high = Wood.SplitPart(s, cut, 2)
			t.ok(
				s.Size.Y >= MIN_PIECE - 1e-9 and high.Size.Y >= MIN_PIECE - 1e-9,
				"pieces " .. s.Size.Y .. " " .. high.Size.Y
			)
			t.ok(math.abs(s.Size.Y - shown) < 1e-6, "the low piece is as tall as the band's height")
		end
	end)

	t.test("a second cut 0.2 from the first still leaves 0.5 each side", function()
		local s = section(8)
		Wood.SplitPart(s, 3, 2) -- the low piece is now 3 tall
		local again = SectionLogic.ClampHeight(s.Size.Y / 2 - 0.2, s.Size.Y)
		t.ok(again >= MIN_PIECE - 1e-9 and s.Size.Y - again >= MIN_PIECE - 1e-9)
		-- At 0.3 that cut would leave a 0.3 slab on top.
		local old = SectionLogic.ClampHeight(s.Size.Y / 2 - 0.2, s.Size.Y, 0.3)
		t.ok(math.abs(s.Size.Y - old - 0.3) < 1e-9, "at 0.3 the slab is 0.3")
	end)
end
