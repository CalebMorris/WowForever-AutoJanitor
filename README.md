# Auto Janitor

Wow Forever addon to assist in keeping the bags clean

## Clean Out Lowest Value Item

Bad slots are limited, and running into "Bags Full" when auto-looting is a pain point. I usually have to decide if I want to destroy an item from my bags (greys) or just not take the item.
The addon will handle this for you, destroying the lowest value grey if it's lower value than the item you're picking up, and then grabbing that item.

When a corpse's loot window holds items that do not fit in your bags, a "Replace cheapest junk" button appears on it. Click it, or press its keybinding, to delete the cheapest grey stack and loot the item. Only grey (quality 0) items are ever deleted.

## Install

Auto Janitor is not published on CurseForge yet, so the CurseForge app cannot install it. Install it manually:

1. Get the `AutoJanitor/` folder from this repository (clone it, or download the repo as a zip and unzip it). Only that folder is needed, not `tests/` or `docs/`.
2. Open the game folder. In the Battle.net launcher, select World of Warcraft Forever, click the gear icon next to Play, and choose Show in Explorer.
3. Go to `World of Warcraft\_forever_\Interface\AddOns`. Create the `AddOns` folder if it does not exist.
4. Copy the `AutoJanitor/` folder in, so the TOC ends up at:

   ```
   World of Warcraft\_forever_\Interface\AddOns\AutoJanitor\AutoJanitor.toc
   ```

   Check that you did not nest it twice. `AddOns\AutoJanitor\AutoJanitor\AutoJanitor.toc` is the most common mistake, and the addon will not load.
5. Fully restart the game. New addon folders are only picked up at startup, so Reload UI is not enough the first time.
6. At the character screen, click AddOns and make sure Auto Janitor is enabled.

Notes on the folder name:

* Use the folder for the Forever client, not Classic Era's. Classic Era addons use a different interface version and will not load.
* Live Forever uses `_forever_`. Guides written during the beta used `_classic_beta_`, so if you are on the beta client, use that folder instead.
* If you cannot find the folder, use the Show in Explorer button as above rather than guessing, because the product folder name can vary.

Other install methods:

* **CurseForge app:** once the addon is published there, choose your Forever installation in the app and click Install. The app puts it in the right folder. If Forever does not appear, use Scan for games or Add game manually and point it at the `World of Warcraft` folder.
* **Zip from CurseForge:** if you download a release as a zip, unzip it first and check that it contains one `AutoJanitor` folder directly, then copy that folder as in step 4.
* **Other addon managers** (WowUp, Wago, Ajour): no source confirms that they support Forever, so use the manual steps above.

Developers can make a release zip with the folder at the top level by running `zip -r AutoJanitor.zip AutoJanitor` from the repository root.

On login the addon checks that every API it needs exists on the client. Missing APIs are printed in chat and the button stays disabled. Many APIs are unverified on Forever, so follow the [in-game checklist](docs/in-game-checklist.md) the first time.

The keybinding is under Key Bindings > AddOns > Auto Janitor.

## Development

Run the tests from the repository root. They need only a plain `lua` and no other dependencies:

```
lua tests/run.lua
```

The pure logic lives in `AutoJanitor/src/` and is tested with the WoW APIs stubbed. `AutoJanitor/AutoJanitor.lua` is thin wiring, covered by a stubbed smoke test and by hand in-game. All code stays Lua 5.1 compatible, because that is what the game runs.

## Documentation

* [Decisions and status](docs/decisions.md): approved decisions, working rules, and the layout
* [In-game checklist](docs/in-game-checklist.md): what to verify by hand on the Forever client
* [Next session prompt](docs/next-session-prompt.md): the original implementation prompt (historical)
* [Research findings](docs/research-findings.md): WoW Forever API notes, confidence levels, and sources
* [User stories and APIs](docs/user-stories.md): behavior with the in-game APIs used at each step
