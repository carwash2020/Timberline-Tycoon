--!nocheck
-- assetscan: finds every Roblox asset reference in src/ by reading the source
-- text (no engine needed), so ASSETS.md (tools/assets) and the id-format
-- spec (tests/AssetIds.spec.luau) work from the same list.
--
-- Loaded with luau.load like tools/loader.luau:
--   local Scan = luau.load(fs.readFile("tools/assetscan.luau"), { debugName = "tools/assetscan.luau" })()
--   Scan.Scan() -> { Record }, Scan.Literals() -> { Literal }
--
-- A Record is one asset id at one place in the source:
--   id     the number
--   digits the id as written (kept as text: no precision is lost)
--   kind   "mesh" (a MeshId), "model" (an Open Cloud Model container, never a
--          MeshId), "template" (a MeshTemplates file), "sound", "image" (an
--          Image id for ImageLabel / particle / tile use), "texture" (a
--          MaterialVariant map), "pass", "product", "badge"
--   path, line  where it is written
--   use    the module's own name for it (asset key and piece, key, ...)
--
-- Only places known to hold asset ids are read as ids (an `rbxassetid://`
-- literal anywhere, `meshId =` / `modelId =` fields, and the named tables
-- below), so seeds, salts and user ids in the same files are not mistaken
-- for assets.

local fs = require("@lune/fs")

local Scan = {}

local SKIP_DIRS = { Vendor = true }

local function walk(dir: string, out: { string })
	for _, name in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			if not SKIP_DIRS[name] then
				walk(path, out)
			end
		elseif string.match(name, "%.luau$") or string.match(name, "%.json$") then
			table.insert(out, path)
		end
	end
end

-- Files whose big numbers on a code line are all mesh ids (tables of ids with
-- no `meshId =` label on the line).
local MESH_TABLE_FILES = {
	["TreeModels.luau"] = true,
	["KitMeshData.luau"] = true,
	["RockModels.luau"] = true,
}

local function base(path: string): string
	return string.match(path, "([^/]+)$") :: string
end

local function stripComment(line: string): string
	-- A `--` comment tail. Strings here never contain "--".
	local at = string.find(line, "--", 1, true)
	if at then
		return string.sub(line, 1, at - 1)
	end
	return line
end

function Scan.Files(): { string }
	local files: { string } = {}
	walk("src", files)
	table.sort(files)
	return files
end

export type Record = {
	id: number,
	digits: string,
	kind: string,
	path: string,
	line: number,
	use: string,
}

-- `meshId = 0` is the "no upload yet, keep the part build" slot (BlenderAssets
-- has many). It is not an asset id, so it is counted here and not listed.
Scan.Zeros = 0

local function add(out: { Record }, digits: string, kind: string, path: string, line: number, use: string)
	if tonumber(digits) == 0 then
		Scan.Zeros += 1
		return
	end
	table.insert(out, {
		id = tonumber(digits) :: number,
		digits = digits,
		kind = kind,
		path = path,
		line = line,
		use = use,
	})
end

function Scan.Scan(): { Record }
	local out: { Record } = {}
	Scan.Zeros = 0
	for _, path in ipairs(Scan.Files()) do
		local file = base(path)
		if string.find(path, "/MeshTemplates/", 1, true) then
			local digits = string.match(file, "^(%d+)%.model%.json$")
			if digits then
				add(out, digits, "template", path, 1, "Rojo MeshPart template")
			end
		elseif string.match(file, "%.json$") then
			-- MaterialService variants.
			for n, line in ipairs(string.split(fs.readFile(path), "\n")) do
				local key, digits = string.match(line, '"(%w+Map)"%s*:%s*"rbxassetid://(%d+)"')
				if digits then
					add(out, digits, "texture", path, n, file .. " " .. key)
				end
			end
		else
			local currentKey = ""
			local section = ""
			local storeRow: string? = nil
			for n, raw in ipairs(string.split(fs.readFile(path), "\n")) do
				local line = stripComment(raw)
				local assetKey = string.match(line, '^%s*id = "([%w_]+)"') or string.match(line, "^\t(%w+) = {%s*$")
				if assetKey then
					currentKey = assetKey
				end
				if file == "StoreData.luau" then
					if string.find(line, "Passes = {", 1, true) then
						section = "pass"
					elseif string.find(line, "Products = {", 1, true) then
						section = "product"
					end
					local key, digits = string.match(line, "^%s*(%w+) = (%d%d%d%d%d%d+),")
					if digits and key ~= "image" then
						add(out, digits, section, path, n, "CreatorIds." .. key)
					end
					local rowKey = string.match(line, '^%s*key = "(%w+)",')
					if rowKey then
						storeRow = rowKey
					end
					local imageDigits = string.match(line, "^%s*image = (%d+),")
					if imageDigits and imageDigits ~= "0" then
						add(out, imageDigits, "image", path, n, "store card image, " .. (storeRow or currentKey))
					end
				elseif file == "UITheme.luau" then
					local key, digits = string.match(line, "^%s*(%w+) = (%d%d%d%d%d%d+),")
					if digits then
						add(out, digits, "image", path, n, "HudIcons." .. key)
					end
				elseif file == "BadgeData.luau" then
					local key, digits = string.match(line, "^%s*(%w+) = (%d%d%d%d%d%d+)")
					if digits then
						add(out, digits, "badge", path, n, key)
					end
				end
				for digits in string.gmatch(line, "rbxassetid://(%d+)") do
					local kind = "image"
					local use = file
					if string.find(line, "Sound", 1, true) or file == "SoundData.luau" or file == "FellSound.luau" then
						kind = "sound"
						use = "SoundData " .. (string.match(line, "^%s*(%w+) = {") or "")
					elseif
						file == "ItemMeshData.luau"
						or file == "KitMeshData.luau"
						or string.find(line, "[mM]eshId") ~= nil
					then
						kind = "mesh"
						use = file .. " " .. (string.match(line, "^%s*(%w+) = ") or currentKey)
					elseif file == "UIArt.luau" then
						use = "UIArt " .. (string.match(line, "^%s*(%w+) = ") or "")
					elseif file == "WeatherController.luau" then
						use = "particle " .. (string.match(line, "local (%w+)") or "")
					end
					add(out, digits, kind, path, n, use)
				end
				for digits in string.gmatch(line, "[mM]eshId%s*=%s*(%d+)") do
					add(
						out,
						digits,
						"mesh",
						path,
						n,
						file
							.. " "
							.. currentKey
							.. " "
							.. (string.match(line, 'name = "(%w+)"') or string.match(line, "^%s*(%w+) = {") or "")
					)
				end
				for digits in string.gmatch(line, "modelId%s*=%s*(%d+)") do
					add(out, digits, "model", path, n, file .. " " .. currentKey)
				end
				for digits in string.gmatch(line, "modelAssetId%s*=%s*(%d+)") do
					add(out, digits, "model", path, n, file .. " " .. currentKey)
				end
				if MESH_TABLE_FILES[file] and not string.find(line, "[mM]eshId", 1, true) then
					for digits in string.gmatch(line, "(%d%d%d%d%d%d%d%d%d%d+)") do
						add(out, digits, "mesh", path, n, file .. " " .. currentKey)
					end
				end
			end
		end
	end
	return out
end

-- Every `rbxassetid://...` string literal and every URL-looking asset
-- reference, raw, for the format rules: { text, path, line }.
export type Literal = { text: string, path: string, line: number }

function Scan.Literals(): { Literal }
	local out: { Literal } = {}
	for _, path in ipairs(Scan.Files()) do
		for n, raw in ipairs(string.split(fs.readFile(path), "\n")) do
			local line = stripComment(raw)
			for text in string.gmatch(line, "rbxassetid://[^\"'%s]*") do
				table.insert(out, { text = text, path = path, line = n })
			end
			for text in string.gmatch(line, "https?://[^\"'%s]*") do
				table.insert(out, { text = text, path = path, line = n })
			end
			for text in string.gmatch(line, "rbxthumb://[^\"'%s]*") do
				table.insert(out, { text = text, path = path, line = n })
			end
		end
	end
	return out
end

return Scan
