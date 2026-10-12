--!nocheck
-- Server audit leftover (11 October 2026): DialogueService.watchKeepers
-- walked every descendant of the workspace once and then took a callback for
-- every instance the forest planted. The keepers are NPCService's models and
-- it tags each one "NPC": the watch now uses the tag (the ones there now,
-- then each one the tag reaches). Same keepers hooked, none other.
return function(t)
	local function keeper(id)
		local presses = { n = 0 }
		local prompt = { Name = "Talk", Triggered = {} }
		function prompt.Triggered:Connect()
			presses.n += 1
			return { Disconnect = function() end }
		end
		function prompt:IsA(class)
			return class == "ProximityPrompt"
		end
		local model = { Name = id, Parent = {} }
		function model:GetAttribute(name)
			return if name == "NPCId" then id else nil
		end
		function model:FindFirstChild(name)
			return if name == "Talk" then prompt else nil
		end
		function model:IsA(class)
			return class == "Model"
		end
		return model, presses
	end

	local function boot(tagged)
		local w = { descendantCalls = 0, signalFor = nil, taggedFor = nil }
		local listeners = {}
		local loader = t.loader({
			mocks = {
				BoxService = {
					Offered = function() end,
					Get = function() end,
					InCounter = function()
						return false
					end,
					Decline = function() end,
					Pay = function() end,
				},
				ProfileService = { GetProfile = function() end },
			},
			services = {
				Workspace = {
					GetDescendants = function()
						w.descendantCalls += 1
						return {}
					end,
					DescendantAdded = {
						Connect = function()
							w.descendantCalls += 1
						end,
					},
				},
				CollectionService = {
					GetTagged = function(_, tag)
						w.taggedFor = tag
						return tagged
					end,
					GetInstanceAddedSignal = function(_, tag)
						w.signalFor = tag
						return {
							Connect = function(_, fn)
								table.insert(listeners, fn)
							end,
						}
					end,
				},
			},
		})
		local Dialogue = loader:server("DialogueService")
		local remote = { OnServerEvent = { Connect = function() end } }
		Dialogue.Init(remote)
		function w.tag(model)
			for _, fn in ipairs(listeners) do
				fn(model)
			end
		end
		return w
	end

	t.test("keepers are found by their NPC tag, now and as they arrive; no workspace walk", function()
		local tink, tinkPresses = keeper("Tink")
		local murph, murphPresses = keeper("Murph")
		local w = boot({ tink, murph })
		t.eq(w.taggedFor, "NPC")
		t.eq(w.signalFor, "NPC")
		t.eq(w.descendantCalls, 0, "the whole workspace is never walked or listened to")
		t.eq(tinkPresses.n, 1, "Tink (a shop keeper) is hooked")
		t.eq(murphPresses.n, 0, "Murph is not a shop keeper")
		local hazel, hazelPresses = keeper("Hazel")
		w.tag(hazel)
		w.tag(hazel)
		t.eq(hazelPresses.n, 1, "a keeper that arrives later is hooked, once")
	end)
end
