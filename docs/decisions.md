# Decisions and Status

Status as of 2026-11-06: planning is complete and approved by the user. No addon code exists yet. Implementation is the next step.

## Approved decisions

* Target client: WoW Forever (client 1.60.1, `## Interface: 16001`), which uses the modern retail-style API, not Classic's.
* Trigger: opening a corpse's loot window (`LOOT_OPENED`).
* Action: a "Replace cheapest junk" button on the loot window, plus a keybinding. One click or keypress, no confirmation popup.
* Only grey (quality 0) bag items are deleted, and the whole stack is deleted.
* Multiple items: swap as many as possible. Pair the highest-value loot that doesn't fit with the cheapest greys, and only when the loot is worth more than the grey stack.
* Skip reasons: no grey left to delete, and item worth less than the cheapest grey. An item with an uncached price (`nil` from `C_Item.GetItemInfo`) is also not offered until `ITEM_DATA_LOAD_RESULT` arrives.
* Failure display: the button stays enabled with a count ("Replace junk (2 of 3)"), and the tooltip and chat list each skipped item and its reason. The button is greyed out only when zero swaps are possible. No button when everything fits.
* Tests: a plain Lua script run with `lua tests/run.lua`, with no dependencies. Pure-Lua logic is tested with WoW APIs stubbed. Frame and event wiring is verified by hand in-game.
* Packaging: a single folder `AutoJanitor/` with `AutoJanitor.toc`, `AutoJanitor.lua`, and `Bindings.xml`. Plain TOC with no flavor suffix. The addon is developed here and run on a different machine, so there is no local install step. The likely path is `World of Warcraft\_forever_\Interface\AddOns\AutoJanitor\`, to be confirmed on the live client.
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
AutoJanitor.toc
AutoJanitor.lua        thin WoW wiring: events, frames, button, binding
Bindings.xml
src/                   pure-Lua logic: junk selection, swap planning, value math
tests/run.lua          plain Lua test runner with API stubs
docs/
```

The TOC lists the files WoW loads. If logic lives in `src/`, list those files in the TOC, and keep them loadable both in-game and by `lua` outside it.

## Related docs

* [research-findings.md](research-findings.md): API confidence labels, Forever differences, install notes, sources
* [user-stories.md](user-stories.md): stories with the APIs used at each step
* [next-session-prompt.md](next-session-prompt.md): the prompt for picking this up in a new session
