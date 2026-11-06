# User Stories and APIs

Flow:

```
Right-click corpse
  -> Inspect available loot and bag contents
  -> Display "Replace cheapest junk"
Player clicks the button or presses its binding
  -> Revalidate the proposed replacement
  -> Delete the selected bag stack
  -> Attempt to loot the replacement
```

APIs marked (K) come from general knowledge and are unverified on Forever. See [research-findings.md](research-findings.md).

## Story 1: Detect the loot window

> When I open a corpse's loot window, the addon inspects what is lootable.

* `CreateFrame("Frame")`, `frame:RegisterEvent("LOOT_OPENED")`, `frame:SetScript("OnEvent", ...)`
* `GetNumLootItems()` for the slot count
* `GetLootSlotType(slot)` to skip money and currency slots (numeric comparison)
* `GetLootSlotInfo(slot)` for icon, name, quantity, quality, locked
* `GetLootSlotLink(slot)` (K) for the item link
* `C_Item.GetItemInfo(link)` for sell price and stack size. Returns `nil` until cached.
* `C_Item.RequestLoadItemDataByID(itemID)` and the `ITEM_DATA_LOAD_RESULT` event when the price is not cached yet

## Story 2: Detect that bags are full

> The addon offers a replacement only when the item cannot fit in my bags.

* `C_Container.GetContainerNumFreeSlots(bag)` (K) for bags `0` to `NUM_BAG_SLOTS`
* `GetItemFamily(link)` (K) so specialty bags are not miscounted
* `C_Container.GetContainerItemInfo(bag, slot)` (K) and the item's stack size to check whether a partial stack has room

## Story 3: Find the cheapest junk

> The addon finds my lowest-value grey item in my bags.

* `C_Container.GetContainerNumSlots(bag)` (K)
* `C_Container.GetContainerItemInfo(bag, slot)` (K) for `quality`, `stackCount`, `hyperlink`, `itemID`, `isLocked`
* `C_Item.GetItemInfo(hyperlink)` for sell price
* Value is `sellPrice * stackCount`. Only quality 0 (grey) is a candidate, and the whole stack is the unit of deletion.
* A replacement is offered only if the incoming item's value is greater than the junk stack's value.
* Unknown prices (`nil`) are never candidates.

## Story 4: Show the "Replace cheapest junk" button

> A button appears on the loot window showing what will be deleted and what replaces it.

* `CreateFrame("Button", nil, LootFrame, "UIPanelButtonTemplate")`
* `button:SetText`, `button:Show()`, `button:Hide()`
* `GameTooltip:SetOwner` and `GameTooltip:SetBagItem(bag, slot)` (K)
* `LOOT_CLOSED` hides the button.
* Keybinding: `Bindings.xml` with `<Binding name="AUTOJANITOR_REPLACE" header="AUTOJANITOR">` plus the global `BINDING_NAME_AUTOJANITOR_REPLACE` and `BINDING_HEADER_AUTOJANITOR` strings. Unverified on Forever.
* `InCombatLockdown()` hides or disables the button in combat.

## Story 5: Click to replace

> One click or keypress deletes the junk and loots the item.

Revalidate, then act:

1. `C_Container.GetContainerItemInfo(bag, slot)` (K): same `itemID`, not locked, still quality 0.
2. `GetLootSlotLink(slot)` (K): still matches the expected item.
3. `C_Container.PickupContainerItem(bag, slot)` (K) puts the stack on the cursor.
4. `GetCursorInfo()` confirms the cursor holds the expected item. Abort and `ClearCursor()` otherwise.
5. `DeleteCursorItem()` (K) destroys it.
6. Wait for `BAG_UPDATE_DELAYED` (K), then confirm a free slot exists.
7. `LootSlot(slot)` loots the item.
8. `UI_ERROR_MESSAGE` detects "Inventory is full".
9. `ClearCursor()` on every failure path.

Because protected calls can fail silently on Forever, every step checks resulting state instead of relying on errors.

## Story 5b: Multiple items and failure cases

> If several items don't fit, the addon swaps as many as it can and tells me about the rest.

Planning algorithm (pure Lua, tested outside the game):

1. Collect loot items that don't fit, sorted by value, highest first.
2. Collect bag greys, sorted by stack value, lowest first.
3. Pair them greedily. Each item takes the next cheapest grey, but only if the item's value is greater than that grey's stack value.
4. Items left over are reported as skipped, each with a reason.

Skip reasons (decided in the interview):

* **No grey left to delete**: every remaining grey is already assigned, or none exist.
* **Worth less than the cheapest grey**: the swap would lose value, so the item is skipped.

Not a user-chosen skip reason, but handled conservatively: if `C_Item.GetItemInfo` returns `nil` (price not cached), the item is not offered until `ITEM_DATA_LOAD_RESULT` arrives.

Presentation (decided in the interview): partial button plus message.

* At least one swap possible: the button stays enabled and shows the count, for example "Replace junk (2 of 3)".
* The tooltip and a chat line list each skipped item and its reason.
* Zero swaps possible: the button is greyed out, and the tooltip says why.
* No items to replace (everything fits): no button.

APIs: the same as Stories 1 to 4, plus `GameTooltip:AddLine` and `button:Enable()` / `button:Disable()`.

On click, swaps run one at a time. Each swap re-runs the Story 5 revalidation, and the first failure stops the batch and reports what was and wasn't done.

## Story 6: Feedback

> I see what was deleted and why.

* `print` or `DEFAULT_CHAT_FRAME:AddMessage`: "Deleted [item] x N (value) for [item]".
* `GetCoinTextureString(copper)` formats values.

## Story 7: Startup self-check

> If Forever lacks an API the addon needs, I am told which one.

* `PLAYER_LOGIN` event
* Test existence of: `C_Container.GetContainerItemInfo`, `C_Container.PickupContainerItem`, `C_Container.GetContainerNumFreeSlots`, `C_Container.GetContainerNumSlots`, `DeleteCursorItem`, `LootSlot`, `GetLootSlotLink`, `GetLootSlotInfo`, `GetNumLootItems`, `C_Item.GetItemInfo`, `GetCursorInfo`, `ClearCursor`
* Print the missing names and keep the button disabled if any are missing.

## Testing approach

* Pure-Lua logic (cheapest-junk selection, value comparison, free-slot check, revalidation) is tested outside the game with WoW APIs stubbed.
* Frame, button, and event wiring is thin and tested by hand in-game.
