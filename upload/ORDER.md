# Upload order (nothing uploaded yet)

Creator Hub web: create.roblox.com > Creations > Development Items > Models (or the experience's Associated Items) > Import 3D. Accepts .fbx, .obj, .gltf/.glb directly, so files are the repo GLBs renamed, no conversion.
Each upload makes a Model; open it (or insert in Studio) and copy each child MeshPart's MeshId. A Model id is never a MeshId.

## Vehicles: 8 files -> 38 MeshIds (Glass unchanged, keep its id)

| File | Node | Old id to replace in src/ReplicatedStorage/Shared/Art/VehicleModels.luau |
|---|---|---|
| Vehicle_Rustbucket.glb | Body | 120725616537680 |
| Vehicle_Rustbucket.glb | Lights | 124493769904792 |
| Vehicle_Rustbucket.glb | Bed | 120734733805977 |
| Vehicle_Rustbucket.glb | Wheel | 139390483847560 |
| Vehicle_Rustbucket.glb | Hitch | 99956936383854 |
| Vehicle_Pickup.glb | Body | 110946981942122 |
| Vehicle_Pickup.glb | Lights | 100056308278514 |
| Vehicle_Pickup.glb | Bed | 137659811327372 |
| Vehicle_Pickup.glb | Wheel | 124886704209701 |
| Vehicle_Pickup.glb | Hitch | 121507994255438 |
| Vehicle_ScoutATV.glb | Body | 131883902524854 |
| Vehicle_ScoutATV.glb | Lights | 117328552905839 |
| Vehicle_ScoutATV.glb | Wheel | 140001053768737 |
| Vehicle_Flatbed.glb | Body | 101615123184878 |
| Vehicle_Flatbed.glb | Lights | 111333312069489 |
| Vehicle_Flatbed.glb | Bed | 139734928087096 |
| Vehicle_Flatbed.glb | Wheel | 131955977341353 |
| Vehicle_Flatbed.glb | Hitch | 140349480773545 |
| Vehicle_LoggingRig.glb | Body | 106201918511427 |
| Vehicle_LoggingRig.glb | Lights | 82098165138477 |
| Vehicle_LoggingRig.glb | Bed | 124435372710468 |
| Vehicle_LoggingRig.glb | Wheel | 81542757402029 |
| Vehicle_LoggingRig.glb | Hitch | 103819640831326 |
| Vehicle_PonyTrailer.glb | Body | 107003020182290 |
| Vehicle_PonyTrailer.glb | Lights | 88163132342304 |
| Vehicle_PonyTrailer.glb | Bed | 90389536788385 |
| Vehicle_PonyTrailer.glb | Wheel | 109498505023571 |
| Vehicle_PonyTrailer.glb | Hitch | 139471072919132 |
| Vehicle_RanchTrailer.glb | Body | 101057277743396 |
| Vehicle_RanchTrailer.glb | Lights | 97749142571629 |
| Vehicle_RanchTrailer.glb | Bed | 105565294587502 |
| Vehicle_RanchTrailer.glb | Wheel | 131671997531071 |
| Vehicle_RanchTrailer.glb | Hitch | 124380880700146 |
| Vehicle_HeavyHauler.glb | Body | 93977628567245 |
| Vehicle_HeavyHauler.glb | Lights | 90030662798643 |
| Vehicle_HeavyHauler.glb | Bed | 108656014869417 |
| Vehicle_HeavyHauler.glb | Wheel | 81074969756089 |
| Vehicle_HeavyHauler.glb | Hitch | 128380567399095 |

## Store items: 10 files (new, no old id; registry src/ReplicatedStorage/Shared/Art/BlenderAssets.luau / store wiring)

| File | Target |
|---|---|
| StoreItem_Flashlight.glb | new MeshId for store item `Flashlight` (display/held/placed), replaces old where present |
| StoreItem_Lantern.glb | new MeshId for store item `Lantern` (display/held/placed), replaces old where present |
| StoreItem_WoodSign.glb | new MeshId for store item `WoodSign` (display/held/placed), replaces old where present |
| StoreItem_ShedBlueprint.glb | new MeshId for store item `ShedBlueprint` (display/held/placed), replaces old where present |
| StoreItem_Barrel.glb | new MeshId for store item `Barrel` (display/held/placed), replaces old where present |
| StoreItem_Crate.glb | new MeshId for store item `Crate` (display/held/placed), replaces old where present |
| StoreItem_GlowWire.glb | new MeshId for store item `GlowWire` (display/held/placed), replaces old where present |
| StoreItem_SkyBin.glb | new MeshId for store item `SkyBin` (display/held/placed), replaces old where present |
| StoreItem_RobuxCoins.glb | new MeshId for store item `RobuxCoins` (display/held/placed), replaces old where present |
| StoreItem_Parcel.glb | new MeshId for store item `Parcel` (display/held/placed), replaces old where present |

by_truck trailer variants (12) skipped: they have no ids yet (per PHASE2_NOTES).
