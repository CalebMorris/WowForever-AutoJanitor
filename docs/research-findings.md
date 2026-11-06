# Research Findings

Research gathered on 2026-11-06 before implementation. Confidence labels:

* **Sourced**: stated by a web page we read.
* **Own knowledge**: from general knowledge of the WoW API, not confirmed by a source. Verify in the Forever client.
* **Unverified**: no source mentions it for WoW Forever.

## Target client: WoW Forever

* Client version 1.60.1, TOC `## Interface: 16001` (sourced).
* Forever shares the modern retail UI architecture and "the vast majority of APIs available in 12.1.5", per a reported Blizzard statement (sourced, secondhand).
* Classic Era addons use 11509 and will not load on Forever (sourced).
* Forever inherits Midnight's addon restrictions, such as combat-data limits (sourced).
* Beta addon folder: `World of Warcraft\_classic_beta_\Interface\AddOns\<Name>\`. The live path may differ (sourced for the beta only).
* The folder name must match the TOC file name (sourced).
* Flavor-specific TOCs exist (`-Mainline`, `-Classic`, and so on). The Forever suffix was reported as in flux, so we ship a single `AutoJanitor.toc`.
* `WOW_PROJECT_ID` was 1 on one beta build and 18 on another. Do not branch on it alone (sourced).

## Install location and package format (post-launch)

The addon is shared and developed on a different machine, so we document the distributable format instead of a local path.

* Package layout: a single folder `AutoJanitor/` containing `AutoJanitor.toc`, `AutoJanitor.lua`, and `Bindings.xml`. Zip it with the folder at the top level; an extra wrapper folder is a common install mistake (sourced).
* Most likely post-launch path: `World of Warcraft\_forever_\Interface\AddOns\AutoJanitor\`. Sources agree on `_forever_`, but one notes the product folder name can vary, and `_classic_beta_` was beta-only. Confirm against the live client or the Battle.net "Show in Explorer" button.
* CurseForge installs to the correct folder automatically, so publishing there avoids the path question.
* TOC suffix: use a plain `AutoJanitor.toc`. The `_Camelot` suffix is unconfirmed and may be renamed, and `_Mainline.toc` is only mentioned as an option.
* Install research, 2026-11-06: the [CurseForge migration blog](https://blog.curseforge.com/wow-forever-migrate-addons-beta-to-live/) labels `_classic_beta_` as the beta folder and `_forever_` as live, and [allthings.how](https://allthings.how/world-of-warcraft-forever-how-to-install-addons-without-the-curseforge-app/) (beta era) describes the manual zip install using `_classic_beta_`. Both warn about nested folders and say to restart the game fully when a new addon does not appear. No source confirms WowUp, Wago or Ajour support for Forever. The README install steps follow these.
* Sources: [How to Install Addons on WoW Forever](https://forevermastery.com/en/guides/install-addons), [How to install WoW Forever addons](https://www.forevermods.com/guides/install-wow-forever-addons), [WoW Forever Addons: Installation](https://wowcarry.com/blog/wow-forever/addons-guide).

## Forever API differences relevant to this addon

| Finding | Confidence |
|---|---|
| Global `GetItemInfo` was a nil global in the beta. Use `C_Item.GetItemInfo`. | Sourced |
| `C_Item.GetItemInfo` returns the same values as the old global but returns `nil` until the item record is cached. | Sourced |
| Use `C_Item.RequestLoadItemDataByID` and the `ITEM_DATA_LOAD_RESULT` event to wait for cache. | Sourced |
| Blocked protected calls can fail silently ("Interface action failed because of an AddOn") and `pcall` will not catch them. | Sourced |
| Check `InCombatLockdown()` before protected actions. | Sourced |
| `C_Container.GetContainerItemInfo`, `PickupContainerItem`, `GetContainerNumFreeSlots` exist. | Unverified |
| `DeleteCursorItem` exists and works from an addon on a hardware event. | Unverified |
| `LootSlot`, `GetLootSlotInfo`, `GetLootSlotLink`, `GetNumLootItems`, `LOOT_OPENED`, `LOOT_READY` | Unverified for Forever. `GetLootSlotInfo` and `GetLootSlotType` are documented on the Warcraft Wiki for retail. |
| `BAG_UPDATE_DELAYED` fires after bag changes. | Own knowledge |
| `Bindings.xml` keybindings work. | Unverified |
| `LOOT_SLOT_*` constants were removed in 10.0, so compare slot types numerically. | Sourced (Warcraft Wiki) |

## Design consequences

1. Use `C_Item.GetItemInfo` only. Treat a `nil` sell price as "not yet known" and do not offer a replacement.
2. Never trust a protected call to raise an error. Verify results by checking bag and cursor state afterward.
3. Run a startup self-check on `PLAYER_LOGIN` that tests every API we depend on and prints the missing ones. The button stays disabled if anything is missing.
4. Skip the feature while in combat lockdown.
5. Keep selection logic in pure Lua, separate from WoW calls, so it can be tested outside the game.

## Open items

* Confirm the live Forever AddOns folder path.
* Confirm all "Unverified" APIs in-game using the startup self-check and [in-game-checklist.md](in-game-checklist.md).
* Confirm the `GetLootSlotInfo` return layout and that `GetLootSlotType` returns `1` for items on Forever.
* Confirm that waiting for `BAG_UPDATE_DELAYED` between `DeleteCursorItem` and `LootSlot` does not break the hardware-event requirement.
* The source pages describe the beta, and the guide itself warns that builds before launch (Nov 4, 2026) could change the API.

## Sources

* [WoW Forever Addon Development Guide](https://wowforeverguides.com/addons/developers): third-party fan site, updated Oct 13, 2026, many items marked "Reported" or "Unverified".
* [WoW Forever Beta - Addon Feedback](https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-addon-feedback/2385926): a single tester's report from Oct 18, 2026.
* [TOC format](https://addonstudio.org/wiki/WoW:TOC_format)
* [GetLootSlotInfo](https://warcraft.wiki.gg/wiki/API:GetLootSlotInfo)
* [GetLootSlotType](https://warcraft.wiki.gg/wiki/API:GetLootSlotType)
* [GetLootSourceInfo](https://warcraft.wiki.gg/wiki/API:GetLootSourceInfo)
* [toc-interface-updater](https://github.com/p3lim/toc-interface-updater)
