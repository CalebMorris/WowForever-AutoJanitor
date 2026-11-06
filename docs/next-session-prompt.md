# Next Session Prompt

Historical: this prompt has been carried out. The addon is implemented, see [decisions.md](decisions.md) for status and [in-game-checklist.md](in-game-checklist.md) for what is left.

The prompt was:

Paste this into a new session started in the repository root:

```
Implement the Auto Janitor WoW Forever addon. Planning is finished and approved, and everything you need is in the repo. Read these first: README.md, docs/decisions.md, docs/user-stories.md, docs/research-findings.md.

Follow docs/decisions.md exactly. Use red-green TDD with the plain Lua runner (tests/run.lua), putting the pure logic in src/ and keeping the WoW wiring thin. Many APIs (C_Container.*, DeleteCursorItem, LootSlot, Bindings.xml) are unverified on Forever, so implement the PLAYER_LOGIN self-check from Story 7. Verify every protected action by checking resulting bag and cursor state, not by relying on errors. Update docs as you go, and do not commit unless I ask. If something is ambiguous or contradicts the docs, ask me instead of assuming.
```
