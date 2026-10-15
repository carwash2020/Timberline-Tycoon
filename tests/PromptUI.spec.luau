--!nocheck
-- PromptUI: an NPC's Talk card adorns the head and sits above it. A pixel
-- offset (promptLift) lands on the body when you're close. A prompt on a
-- part stays on that part.
return function(t)
	local Instance, Vector2, Vector3 = t.roblox.Instance, t.roblox.Vector2, t.roblox.Vector3

	local function load()
		local loader = t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return false
					end,
					TopbarInset = t.roblox.Rect.new(0, 0, 0, 0),
					GetGuiInset = function()
						return Vector2.new(0, 58), Vector2.zero
					end,
				},
				Players = { LocalPlayer = {} },
				TextChatService = {},
				UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
				ProximityPromptService = {},
				TweenService = {},
				CollectionService = {},
				RunService = {},
			},
		})
		return loader:load("StarterPlayer/StarterPlayerScripts/PromptUI")
	end

	t.test("Talk on an NPC adorns the head, above it", function()
		local PromptUI = load()
		local model = Instance.new("Model")
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Parent = model
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = model
		model.PrimaryPart = root
		local adornee, studs = PromptUI.Adornee(model)
		t.ok(adornee == head, "the head, not the torso")
		t.eq(studs, Vector3.new(0, PromptUI.HeadLift, 0))
		t.ok(PromptUI.HeadLift > 1.2, "clears the scalp")
	end)

	t.test("a prompt on a part stays on that part, with no studs lift", function()
		local PromptUI = load()
		local part = Instance.new("Part")
		part.Name = "Counter"
		local adornee, studs = PromptUI.Adornee(part)
		t.ok(adornee == part)
		t.eq(studs, nil)
		local plain = Instance.new("Model")
		plain.PrimaryPart = part
		local again, lift = PromptUI.Adornee(plain)
		t.ok(again == part, "a model with no head uses its PrimaryPart")
		t.eq(lift, nil)
	end)

	t.test("a TV prompt grows by the screen's scale, never under 1; other devices stay at 1", function()
		local PromptUI = load()
		t.eq(PromptUI.Grow(true, 1.5), 1.5)
		t.eq(PromptUI.Grow(true, 0.7), 1)
		t.eq(PromptUI.Grow(false, 1.5), 1)
	end)

	t.test("a gamepad prompt leaves the selection alone", function()
		local Enum = t.roblox.Enum
		local guiService = {
			SelectedObject = nil,
			IsTenFootInterface = function()
				return false
			end,
		}
		local player = Instance.new("Folder")
		local pg = Instance.new("Folder")
		pg.Name = "PlayerGui"
		pg.Parent = player
		local function signal()
			local listeners = {}
			return {
				Connect = function(_, fn)
					table.insert(listeners, fn)
					return { Disconnect = function() end }
				end,
				Once = function(_, fn)
					table.insert(listeners, fn)
					return { Disconnect = function() end }
				end,
				Fire = function(_, ...)
					for _, fn in ipairs(listeners) do
						fn(...)
					end
				end,
			}
		end
		local loader = t.loader({
			globals = {
				workspace = { CurrentCamera = nil },
			},
			services = {
				GuiService = guiService,
				Players = { LocalPlayer = player },
				TextChatService = {},
				UserInputService = {
					TouchEnabled = false,
					KeyboardEnabled = true,
					InputBegan = signal(),
					GetLastInputType = function()
						return Enum.UserInputType.Keyboard
					end,
				},
				ProximityPromptService = {},
				TweenService = {},
				CollectionService = {},
				RunService = {},
			},
		})
		local PromptUI = loader:load("StarterPlayer/StarterPlayerScripts/PromptUI")
		local prompt = {
			Parent = Instance.new("Part"),
			ActionText = "Talk",
			ObjectText = "Murph",
			HoldDuration = 0,
			ClickablePrompt = false,
			KeyboardKeyCode = Enum.KeyCode.E,
			GamepadKeyCode = Enum.KeyCode.ButtonX,
			UIOffset = Vector2.zero,
			PromptButtonHoldBegan = signal(),
			PromptButtonHoldEnded = signal(),
			Triggered = signal(),
			PromptHidden = signal(),
			Destroying = signal(),
			GetPropertyChangedSignal = function()
				return signal()
			end,
			InputHoldBegin = function() end,
			InputHoldEnd = function() end,
		}
		PromptUI.Show(prompt, Enum.ProximityPromptInputType.Gamepad)
		t.eq(guiService.SelectedObject, nil)
		local press = nil
		for _, d in ipairs(pg:GetDescendants()) do
			if d.Name == "Press" then
				press = d
			end
		end
		t.ok(press, "the card still has a Press face")
		t.eq(press.Selectable, false)
	end)

	-- Client audit leftover (11 October 2026): Start used to walk every
	-- descendant of the workspace in one frame, and restyle every instance
	-- the forest added (an IsA call each). Now the scan is sliced and only
	-- prompts are touched.
	local Enum = t.roblox.Enum
	local function fakeWorld(count, every)
		local reads = 0
		local list, prompts = {}, {}
		for i = 1, count do
			local inst = { Style = nil }
			local class = if i % every == 0 then "ProximityPrompt" else "Part"
			setmetatable(inst, {
				__index = function(_, key)
					if key == "ClassName" then
						reads += 1
						return class
					end
					return nil
				end,
			})
			list[i] = inst
			if class == "ProximityPrompt" then
				table.insert(prompts, inst)
			end
		end
		return list, prompts, function()
			return reads
		end
	end

	t.test("the first scan restyles every prompt, and only prompts, a slice at a time", function()
		local PromptUI = load()
		local list, prompts, reads = fakeWorld(50000, 97)
		local waits, mostBetween, last = 0, 0, 0
		local styled = PromptUI.RestyleAll(list, 4000, function()
			waits += 1
			mostBetween = math.max(mostBetween, reads() - last)
			last = reads()
		end)
		t.eq(styled, #prompts)
		for _, prompt in ipairs(prompts) do
			t.eq(prompt.Style, Enum.ProximityPromptStyle.Custom)
		end
		for i, inst in ipairs(list) do
			if i % 97 ~= 0 then
				t.eq(rawget(inst, "Style"), nil, "a non-prompt is left alone")
			end
		end
		t.eq(waits, 12, "50,000 instances in slices of 4,000")
		t.ok(mostBetween <= 4000, "at most one slice of work between waits: " .. mostBetween)
		print(string.format("PromptUI scan: 50000 instances, most work in a frame %d (was 50000)", mostBetween))
	end)

	t.test("Start listens for new instances before it scans, and the scan yields", function()
		local added = {}
		local order = {}
		local list, prompts, reads = fakeWorld(20000, 50)
		local workspace = {
			DescendantAdded = {
				Connect = function(_, fn)
					table.insert(order, "connect")
					added.fn = fn
					return { Disconnect = function() end }
				end,
			},
			GetDescendants = function()
				table.insert(order, "scan")
				return list
			end,
		}
		local waits, mostBetween, last = 0, 0, 0
		local loader = t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return false
					end,
				},
				Players = { LocalPlayer = {} },
				TextChatService = {},
				UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
				ProximityPromptService = { PromptShown = { Connect = function() end } },
				TweenService = {},
				CollectionService = {},
				RunService = { Heartbeat = { Connect = function() end } },
			},
			globals = {
				workspace = workspace,
				task = {
					spawn = function(fn)
						fn()
					end,
					wait = function()
						waits += 1
						mostBetween = math.max(mostBetween, reads() - last)
						last = reads()
					end,
				},
			},
		})
		local PromptUI = loader:load("StarterPlayer/StarterPlayerScripts/PromptUI")
		PromptUI.Start()
		t.eq(order, { "connect", "scan" })
		t.ok(waits >= 4, "the scan gave frames back: " .. waits)
		t.ok(mostBetween <= PromptUI.ScanPerFrame)
		for _, prompt in ipairs(prompts) do
			t.eq(prompt.Style, Enum.ProximityPromptStyle.Custom)
		end
		-- A prompt that shows up later is restyled, a part is not touched.
		local later = list[50]
		later.Style = nil
		added.fn(later)
		t.eq(later.Style, Enum.ProximityPromptStyle.Custom)
		local part = list[1]
		added.fn(part)
		t.eq(rawget(part, "Style"), nil)
	end)
end
