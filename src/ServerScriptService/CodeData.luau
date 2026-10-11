--!strict
-- CodeData: the redeem codes (rules in Shared/CodeLogic). It lives under
-- ServerScriptService on purpose: nothing in ReplicatedStorage reaches a
-- player's machine, so no one can read the list of codes. Edit this table to
-- add a code; the spec (CodeLogic.spec) checks every row.
--
--   id       a short stable name for the saved "used" flag. Never change it
--            after a code has gone out, or players could redeem it again.
--   code     what the player types (case and spaces don't matter).
--   enabled  false = the server answers "not valid", as if it didn't exist.
--   expires  "YYYY-MM-DD" in UTC; good through 23:59:59 UTC that day. The
--            server's clock decides.
--   reward   { kind = "cash", amount = n } (1 to CodeLogic.MaxCash, still
--            clamped by the wallet cap) or { kind = "piece", id = <a granted
--            furniture piece> }. NEVER Robux or a paid item: CodeLogic refuses
--            any other shape.
--
-- No real codes are in this file. The one row below is a disabled
-- placeholder that shows the shape; Connor adds real ones (and enables them)
-- at launch, so a code is never live before he chooses it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CodeLogic = require(ReplicatedStorage.Shared.CodeLogic)

local CodeData = {}

CodeData.List = {
	{
		id = "placeholder",
		code = "PLACEHOLDER-DISABLED",
		enabled = false, -- PLACEHOLDER: not a real code, never works
		expires = "2026-12-31",
		reward = { kind = "cash", amount = 100 },
		note = "Shape example only. Replace with a real code, set enabled = true, set a real expiry.",
	},
} :: { CodeLogic.Entry }

return CodeData
