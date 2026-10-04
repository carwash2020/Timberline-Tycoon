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

	t.test("a gamepad prompt selects Press, and B or Esc clears it", function()
		local Enum = t.roblox.Enum
		local guiService = { SelectedObject = nil }
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
				UserInputService = { TouchEnabled = false, KeyboardEnabled = true, InputBegan = signal() },
				ProximityPromptService = {},
				TweenService = {},
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
		t.eq(guiService.SelectedObject.Name, "Press")
		t.eq(PromptUI.ApplyKey(Enum.KeyCode.ButtonB), "close")
		t.eq(guiService.SelectedObject, nil)
		PromptUI.Show(prompt, Enum.ProximityPromptInputType.Gamepad)
		t.eq(PromptUI.ApplyKey(Enum.KeyCode.Escape), "close")
		t.eq(guiService.SelectedObject, nil)
	end)
end
