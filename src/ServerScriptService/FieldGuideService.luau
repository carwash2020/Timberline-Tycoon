--!strict
-- FieldGuideService: records the woods each player finds (profile.compendium;
-- pages in Shared/FieldGuide). The first tree of a new wood you fell goes
-- in the guide with a toast. Murph hands the guide over when the tutorial
-- ends (or it's skipped); before that it's hidden, but finds still count.
-- The Hidden Grain page counts the figured logs you've revealed at the
-- sawmill (profile.forest.figures, added by RevealFigures).
-- Mirrored on the FieldGuide (found wood ids), HasFieldGuide and
-- FieldGuideFigures ("burl=1,curly=4") attributes.

local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FieldGuide = require(ReplicatedStorage.Shared.FieldGuide)
local ForestLogic = require(ReplicatedStorage.Shared.ForestLogic)
local ShopLogic = require(ReplicatedStorage.Shared.ShopLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local ProfileService = require(script.Parent.ProfileService)

type Profile = ProfileService.Profile

local FieldGuideService = {}

local notify: (Player, string) -> () = function(_player: Player, _message: string) end

local function publish(player: Player, profile: Profile)
	local ids: { string } = {}
	for id, found in pairs(profile.compendium) do
		if found then
			table.insert(ids, id)
		end
	end
	player:SetAttribute("FieldGuide", ShopLogic.EncodeSet(ids))
	player:SetAttribute("HasFieldGuide", profile.tutorialDone)
	local forest = profile.forest
	player:SetAttribute("FieldGuideFigures", ShopLogic.EncodeOwned(if forest then forest.figures else {}))
end

-- Call when a player fells a tree of `woodId`.
function FieldGuideService.Discover(player: Player, woodId: string)
	local profile = ProfileService.GetProfile(player)
	local wood = WoodData.Get(woodId)
	if not profile or not wood or profile.compendium[woodId] then
		return
	end
	profile.compendium[woodId] = true
	publish(player, profile)
	local found, total = FieldGuide.Count(profile.compendium)
	if profile.tutorialDone then
		notify(player, string.format("New in your Field Guide: %s! (%d of %d)", wood.displayName, found, total))
	end
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "WoodDiscovered", found)
	end)
end

-- Call after a sale revealed figured logs: `figures` counts them by figure
-- id. The first of a figure ever gets a toast.
function FieldGuideService.RevealFigures(player: Player, figures: { [string]: number })
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return
	end
	local seen = profile.forest.figures
	local firsts: { string } = {}
	for id, n in pairs(figures) do
		local def = ForestLogic.Figure(id)
		if def and type(n) == "number" and n >= 1 then
			if (seen[id] or 0) == 0 then
				table.insert(firsts, def.displayName)
			end
			seen[id] = (seen[id] or 0) + math.floor(n)
		end
	end
	publish(player, profile)
	if #firsts > 0 then
		table.sort(firsts)
		local found, total = FieldGuide.FigureCount(seen)
		notify(
			player,
			string.format(
				"New in your Field Guide's Hidden Grain: %s! (%d of %d)",
				table.concat(firsts, ", "),
				found,
				total
			)
		)
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "FigureDiscovered", found)
		end)
	end
end

-- Call once the save has loaded, and again when the tutorial ends.
function FieldGuideService.Refresh(player: Player)
	local profile = ProfileService.GetProfile(player)
	if profile then
		publish(player, profile)
	end
end

function FieldGuideService.Init(notifyFn: (Player, string) -> ())
	notify = notifyFn
end

return FieldGuideService
