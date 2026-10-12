--!strict
-- StoreEventData: the store events Connor has scheduled. EMPTY by default:
-- with nothing in this list, no store changes and nothing goes on sale.
-- How to add one: EVENTS.md. The short version, one entry per event:
--
--   {
--       store = "HearthAndHome",      -- ToolShed | HearthAndHome | Sparkworks | Dealership
--       startsAt = "2026-12-01",      -- UTC. "YYYY-MM-DD", or "YYYY-MM-DD HH:MM"
--       endsAt = "2026-12-15",        -- the first moment it is over; at most 60 days after the start
--       enabled = true,               -- set false to switch it off without deleting it
--       items = {},                   -- slot ids from StoreData.EventSlots. LEAVE EMPTY until
--                                     -- you have approved an item AND set its price.
--       bannerText = "WINTER FAIR",   -- optional, up to 24 letters; blank = "COMING SOON"
--   },
--
-- An event opens the store's roped-off event area and the banner by the
-- door. An item sells only if its slot is listed in `items`, approved, and
-- has a price (StoreData.EventSlots). The check is StoreEvents.Sanitize.

local StoreEventData = {}

StoreEventData.Events = {} :: { { [string]: any } }

return StoreEventData
