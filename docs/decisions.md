# Decisions and Status

Status as of 2026-11-06: planning is complete and approved by the user. The addon is implemented and unit tested (`lua tests/run.lua`), but it has not been run on the Forever client. Next step: work through [in-game-checklist.md](in-game-checklist.md).

## Decisions made during implementation

These were not settled in planning, so the user was asked:

* **Layout:** addon files live in an `AutoJanitor/` subfolder (TOC, `AutoJanitor.lua`, `Bindings.xml`, `src/`) so the folder can be copied or zipped as is. `tests/` and `docs/` stay at the repo root. This replaces the earlier suggested layout, which put the TOC at the root.
* **Event wait:** Story 5 waits for `BAG_UPDATE_DELAYED` between `DeleteCursorItem` and `LootSlot`. If `LootSlot` then does not put the item in the bags, the batch stops and reports that the junk was deleted but the item was not looted. Each wait also has a 2 second timeout fallback in case the event never arrives.
* **Free slots:** when several items do not fit, free slots go to the highest-value items first. Only the remaining items go through the swap planner.

* **Releases:** a GitHub Action builds the bundle on pushed `v*` tags only. See "Releasing" in the README. The first release, `v0.1.0`, was made by hand before the workflow existed.

Choices made without a question, because the docs left no room for doubt or the choice is a detail:

* The self-check requires three APIs beyond the Story 7 list: `GetLootSlotType`, `C_Item.RequestLoadItemDataByID` and `C_Timer.After`. `GetItemFamily` and `GetCoinTextureString` are optional: missing ones print a warning and the addon degrades (all items treated as general-bag items, plain-text money).
* `GetLootSlotInfo`'s return layout is detected at runtime (see [user-stories.md](user-stories.md) Story 1), because the docs and the retail API disagree.
* A swap is verified by free-slot counts, not by item identity: the delete must raise the free count, and the loot must lower it.
* A grey in a specialty bag is only paired with an item that bag can hold.

## Approved decisions

* Target client: WoW Forever (client 1.60.1, `## Interface: 16001`), which uses the modern retail-style API, not Classic's.
* Trigger: opening a corpse's loot window (`LOOT_OPENED`).
* Action: a "Replace cheapest junk" button on the loot window, plus a keybinding. One click or keypress, no confirmation popup.
* Only grey (quality 0) bag items are deleted, and the whole stack is deleted.
* Multiple items: swap as many as possible. Pair the highest-value loot that doesn't fit with the cheapest greys, and only when the loot is worth more than the grey stack.
* Skip reasons: no grey left to delete, and item worth less than the cheapest grey. An item with an uncached price (`nil` from `C_Item.GetItemInfo`) is also not offered until `ITEM_DATA_LOAD_RESULT` arrives.
* Failure display: the button stays enabled with a count ("Replace junk (2 of 3)"), and the tooltip and chat list each skipped item and its reason. The button is greyed out only when zero swaps are possible. No button when everything fits.
* Tests: a plain Lua script run with `lua tests/run.lua`, with no dependencies. Pure-Lua logic is tested with WoW APIs stubbed. Frame and event wiring is verified by hand in-game.
* Packaging: a single folder `AutoJanitor/` with `AutoJanitor.toc`, `AutoJanitor.lua`, `Bindings.xml`, and `src/`. Plain TOC with no flavor suffix. The addon is developed here and run on a different machine, so there is no local install step. The likely path is `World of Warcraft\_forever_\Interface\AddOns\AutoJanitor\`, to be confirmed on the live client.
* A `PLAYER_LOGIN` self-check tests that each depended-on API exists, prints the missing ones, and keeps the button disabled if any are missing. Many APIs are unverified on Forever.

## Working rules from the user's CLAUDE.md

* Ask clarifying questions instead of making assumptions.
* Never use command substitution or expansion in shell commands.
* Red-green TDD: write failing tests first, then implement.
* Use descriptive variable names and no abbreviations.
* Update documentation as changes are made.
* No `---` horizontal rules in README or markdown docs.
* Commit only when the user asks.

## Suggested layout

```
AutoJanitor/                   the folder that ships
  AutoJanitor.toc              lists src/ files first, then AutoJanitor.lua
  AutoJanitor.lua              thin WoW wiring: events, frames, button, binding
  Bindings.xml                 auto-loaded by the client, not listed in the TOC
  src/
    Planner.lua                swap planning, free-slot sharing, bag families
    Scanner.lua                reads loot and bags through an injected api table
    Replacer.lua               state machine that runs swaps and verifies each step
    Revalidate.lua             bag, loot and cursor checks
    Messages.lua               button state, tooltip, chat text
    SelfCheck.lua              API existence check
tests/
  run.lua                      plain Lua test runner (lua tests/run.lua)
  helpers.lua                  assertions and the module loader
  *_test.lua                   one suite per module, plus wiring_test.lua (stubbed smoke test)
docs/
```

Every file in `src/` and `AutoJanitor.lua` starts with `local _, addon = ...`. WoW passes the same addon table to each TOC file, and `tests/helpers.lua` does the same outside the game. No `src/` file touches a WoW global: the wiring binds them into an `api` table.

## Related docs

* [research-findings.md](research-findings.md): API confidence labels, Forever differences, install notes, sources
* [user-stories.md](user-stories.md): stories with the APIs used at each step
* [in-game-checklist.md](in-game-checklist.md): manual verification on the Forever client
* [next-session-prompt.md](next-session-prompt.md): the original implementation prompt (historical)
