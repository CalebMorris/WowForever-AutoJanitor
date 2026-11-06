# In-Game Checklist

The code is written and unit tested, but it has never run on the Forever client. Work through this list the first time. Anything that fails points at an unverified API from [research-findings.md](research-findings.md).

## Load and self-check

1. The addon appears in the AddOns list with no "out of date" or load error. If it does not, check the folder name matches `AutoJanitor.toc` and the TOC `## Interface: 16001`.
2. At login, chat is silent when every API exists. Otherwise it lists the missing required APIs and says the button is disabled. Optional APIs (`GetItemFamily`, `GetCoinTextureString`) only produce a warning.
3. Key Bindings > AddOns shows "Auto Janitor" with "Replace cheapest junk". If not, `Bindings.xml` is not loading on Forever.

## Button

1. Fill the bags with greys, then open a corpse holding an item worth more than your cheapest grey. The button appears below the loot window.
2. Hover the button: the tooltip lists the grey to delete and the item that replaces it.
3. Open loot that fits in your bags: no button.
4. Open loot worth less than every grey you carry: the button is visible but greyed out, and the tooltip says why.
5. Several items that do not fit: the button shows a count such as "Replace junk (2 of 3)", and chat lists each skipped item and the reason.
6. Items whose price is not cached yet appear a moment later, once `ITEM_DATA_LOAD_RESULT` fires.
7. The button is disabled during combat.

## Replacing

For every step the addon checks the resulting bag and cursor state, so a failure is reported even if the game raises no error.

1. Click the button: the cheapest grey is deleted, the item is looted, and chat prints "Deleted [grey] xN (value) for [item]".
2. Repeat with the keybinding instead of the button.
3. If chat reports "the item was not looted" after the junk was deleted, the wait for `BAG_UPDATE_DELAYED` between `DeleteCursorItem` and `LootSlot` probably broke the hardware-event chain. Loot the item manually, and tell the maintainer so the order of steps can be reconsidered.
4. If `GetLootSlotInfo` misbehaves (for example locked items are offered), check its return layout. The scanner detects the retail layout (currencyID before quality) and the older one, but Forever has not been confirmed.
5. Confirm `LOOT_SLOT_TYPE` values: the scanner treats slot type `1` as an item and skips money and currency.
