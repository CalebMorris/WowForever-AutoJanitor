local helpers = require("helpers")
local assertEqual = helpers.assertEqual
local assertContains = helpers.assertContains
local assertTrue = helpers.assertTrue
local assertFalse = helpers.assertFalse

local function swap(lootName, greyName, lootValue, greyValue, stackCount)
    return {
        lootItem = { name = lootName, link = "[" .. lootName .. "]" },
        grey = { name = greyName, link = "[" .. greyName .. "]", stackCount = stackCount or 1 },
        lootValue = lootValue,
        greyValue = greyValue,
    }
end

local function skip(lootName, reason)
    return { lootItem = { name = lootName, link = "[" .. lootName .. "]" }, reason = reason }
end

return function(test)
    local addon = helpers.loadAddon({ "Planner", "Messages" })
    local Messages = addon.Messages

    test("formatMoney falls back to gold silver copper text", function()
        assertEqual(Messages.formatMoney(12345), "1g 23s 45c")
        assertEqual(Messages.formatMoney(5), "5c")
        assertEqual(Messages.formatMoney(100), "1s")
        assertEqual(Messages.formatMoney(0), "0c")
    end)

    test("formatMoney uses the coin formatter when given", function()
        assertEqual(Messages.formatMoney(5, function(copper) return "coins:" .. copper end), "coins:5")
    end)

    test("button hidden when nothing needs a swap", function()
        local state = Messages.buttonState({ swaps = {}, skipped = {}, fitting = { {} }, pending = {} })
        assertFalse(state.visible)
    end)

    test("button hidden when only pending items exist", function()
        local state = Messages.buttonState({ swaps = {}, skipped = {}, fitting = {}, pending = { {} } })
        assertFalse(state.visible)
    end)

    test("all items swappable: plain text, enabled", function()
        local state = Messages.buttonState({ swaps = { swap("A", "G", 10, 1) }, skipped = {}, fitting = {}, pending = {} })
        assertTrue(state.visible)
        assertTrue(state.enabled)
        assertEqual(state.text, "Replace cheapest junk")
    end)

    test("some items skipped: count in text, still enabled", function()
        local state = Messages.buttonState({
            swaps = { swap("A", "G", 10, 1), swap("B", "H", 10, 1) },
            skipped = { skip("C", "no_grey") },
            fitting = {}, pending = {},
        })
        assertTrue(state.enabled)
        assertEqual(state.text, "Replace junk (2 of 3)")
    end)

    test("zero swaps possible: visible but disabled", function()
        local state = Messages.buttonState({ swaps = {}, skipped = { skip("C", "no_grey") }, fitting = {}, pending = {} })
        assertTrue(state.visible)
        assertFalse(state.enabled)
    end)

    test("skip reasons have readable text", function()
        assertContains(Messages.skipReasonText("no_grey"), "junk")
        assertContains(Messages.skipReasonText("worth_less"), "worth less")
    end)

    test("tooltip lists each swap and each skipped item with its reason", function()
        local lines = Messages.tooltipLines({
            swaps = { swap("Sword", "Rag", 100, 5, 3) },
            skipped = { skip("Axe", "worth_less"), skip("Mace", "no_grey") },
            fitting = {}, pending = {},
        })
        local text = table.concat(lines, "\n")
        assertContains(text, "[Rag]")
        assertContains(text, "[Sword]")
        assertContains(text, "[Axe]")
        assertContains(text, "worth less")
        assertContains(text, "[Mace]")
        assertContains(text, "no junk")
    end)

    test("tooltip explains why when zero swaps are possible", function()
        local lines = Messages.tooltipLines({ swaps = {}, skipped = { skip("Axe", "no_grey") }, fitting = {}, pending = {} })
        assertContains(table.concat(lines, "\n"), "Nothing can be replaced")
    end)

    test("deleted message names the junk, quantity, value and replacement", function()
        local text = Messages.deletedMessage(swap("Sword", "Rag", 100, 5, 3), function(copper) return copper .. "c" end)
        assertEqual(text, "Deleted [Rag] x3 (5c) for [Sword]")
    end)

    test("skipped messages list item and reason", function()
        local lines = Messages.skippedMessages({ skip("Axe", "worth_less") })
        assertContains(lines[1], "[Axe]")
        assertContains(lines[1], "worth less")
    end)

    test("failure text exists for every replacer failure reason", function()
        for _, reason in ipairs({
            "combat", "bag_changed", "loot_changed", "cursor_mismatch", "delete_failed",
            "no_free_slot", "loot_failed", "inventory_full",
        }) do
            assertTrue(Messages.failureText(reason) ~= nil, reason)
        end
    end)

    test("batch report says what was and was not done", function()
        local lines = Messages.batchReport({
            completed = { swap("Sword", "Rag", 100, 5) },
            failed = { swap = swap("Axe", "Cloth", 50, 2), reason = "loot_failed", junkDeleted = true },
            notAttempted = { swap("Mace", "Boot", 40, 1) },
        })
        local text = table.concat(lines, "\n")
        assertContains(text, "[Axe]")
        assertContains(text, "[Cloth]")
        assertContains(text, "[Mace]")
        assertContains(text, "deleted")
    end)
end
