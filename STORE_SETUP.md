# Store setup: the Creator Hub click list (Lane P)

For Connor. Agents never click anything in Creator Hub, never upload an icon,
never set or change a price and never put anything on or off sale. Everything
below is yours to click. Nothing in the game's code holds a Robux price: every
price a player sees is read live from Roblox on their own client (regional
pricing stays on), so a price change in Creator Hub shows in game within five
minutes of the player opening the store, with no update.

Where things are: Creator Hub, Creations, Timberline Tycoon, then
**Monetization ⟩ Passes** or **Monetization ⟩ Developer Products**.

## The nine items (as of 8 Oct 2026)

The id is what `StoreData.CreatorIds` holds. The name and description are
word for word what the game shows; paste them exactly so the Roblox prompt
and the game agree (QA G2). Prices are yours (listed for reference only).

| # | Kind | Key | Id | Name | Price you set | State |
|---|---|---|---|---|---|---|
| 1 | Pass | DoubleCash | 2005256811 | 2x Cash | 499 | On sale |
| 2 | Pass | LuxAxe | 2005226878 | Lux Axe | 300 | On sale |
| 3 | Pass | TowService | 2006186967 | Tow Service | 99 | On sale |
| 4 | Pass | TimberClassic | 2006912886 | Timber Classic | 199 | On sale |
| 5 | Pass | PaintShop | 2006456926 | Paint Shop | 149 | On sale |
| 6 | Product | Cash1k | 3716312861 | Small Cash Pack | 49 | On sale |
| 7 | Product | Cash10k | 3716312899 | Large Cash Pack | 299 | On sale |
| 8 | Product | DoubleWood | 3717310556 | 2x Wood (48 hours) | 299 | On sale |
| 9 | Product | InstantDelivery | 3717310577 | Instant Delivery | 35 | On sale, repeatable |

Descriptions (copy each line exactly):

1. 2x Cash: Wood you sell pays double. It doesn't change your axes, trucks, or how fast you chop, and everything in the game can still be earned without it.
2. Lux Axe: A black axe with a gold head, a diamond edge, and a sparkle. It sits between the Inferno Axe and the Starfall Axe, and the Starfall Axe can still be bought with cash. Wood you cut with it sells for 10% more. It's yours to keep and can't be sold. It can't be tempered.
3. Tow Service: Free recalls for every truck you own. Without this pass, a recall costs 5% of the truck's price, with a $5 minimum.
4. Timber Classic: Unlocks the Timber Classic, an old-school pickup with the same stats as the Pickup. Its dashboard gauge shows what your load is worth, as an estimate at the Wood Dropoff. Your display name is painted on both doors.
5. Paint Shop: Paint your trucks in any color from the Paint Shop palette. Paint is cosmetic only and stays on after you rejoin.
6. Small Cash Pack: Adds 15 minutes of wood income at your current stage.
7. Large Cash Pack: Adds 2 hours of wood income at your current stage.
8. 2x Wood (48 hours): For 48 hours, wood from every tree you fell sells for double. Buying it again adds 48 more hours.
9. Instant Delivery: Sell your truckload from anywhere, once.

The pack descriptions are static on purpose (no amount): the amount scales
with the player's stage (S1 $1,000 and $10,000, S6 about $28,700 and
$229,600; see PHASE2_NOTES.md, Lane P) and the store card shows "+$n now"
for that player.

## Clicks

1. **Edit the two live passes** (2x Cash, Lux Axe): Passes ⟩ the pass ⟩
   **Basic Settings**: check the name, paste the description above, **Save
   Changes**. Leave the price alone unless you mean to change it.
2. **Edit the three restored passes** (Tow Service, Timber Classic, Paint
   Shop): same steps. These ids were 0 on main, so anyone who bought one from
   the Roblox store page before this PR merged gets it the first time they
   join after the update (the game asks Roblox `UserOwnsGamePassAsync` on
   join). Don't make new passes for them.
3. **Rename the four products**: Developer Products ⟩ the product ⟩
   **Configure**: name and description from the table (Cash1k becomes
   "Small Cash Pack", Cash10k "Large Cash Pack", DoubleWood "2x Wood (48
   hours)"), **Save**. Never delete a developer product: a receipt for a
   deleted one can't be granted.
4. **Icons** (optional, later): 512x512 PNG, key art inside a centre circle
   of about 440 px, 3/4 view, no words except a "2x" on 2x Cash and 2x Wood.
   Passes on a PineTrim #2F5D3A disc, products on a BarnRed #9E3B2E disc.
   Upload in the item's **Basic Settings** / **Configure** page. When an
   icon is live, send its image asset id and an agent puts it in
   `StoreData` (`image`), so the board and the store show it.
5. **Prove no price is hardcoded**: Monetization ⟩ Passes (then Developer
   Products) ⟩ **⋯** on an item ⟩ **Dynamic Price Check**, run it in Studio
   with the game open on the Store: each price the store, the bulletin
   board and the gold box hover show is the one the tool reports for the
   test region.
6. **Studio test purchase, all nine** (Studio prompts are free test buys;
   in Studio a pass bought this way is granted for that session only, never
   written to your save): open the Store, buy each item, check the toast and
   the effect (see the PR's Studio checks).
7. **Publish**: File ⟩ Publish to Roblox, then Creator Hub ⟩ the experience
   ⟩ **⋯** ⟩ **Restart Servers for Updates** (only outdated servers).

## Turning something off sale (any time)

Passes ⟩ the pass ⟩ **Sales** ⟩ switch **Item for Sale** off (products:
Configure ⟩ off sale). The game asks Roblox every 10 minutes: within 10
minutes (or on a new server) that item leaves the bulletin board and the
Tool Shed table refuses it at the counter, its store card reads "Coming
soon" with no price, and the server never prompts it ("That isn't for sale
yet."). Owners keep it and their card reads "Owned". Turning it back on is
the same switch; nothing in the code changes.

If one ever has to come off sale and go back, the order QA asked for is: Tow
Service, then Timber Classic, then Paint Shop, each after it is merged,
published and tested.

## Not in the store

- Lux Pickaxe: not a pass yet (StoreData doesn't list it). Your call: a new
  pass, or bundled with the Lux Axe, and its price.
- No gifting and no trading in V1 (the revenue questionnaire answer, "My
  experience does not allow trading or gifting", stays true).
