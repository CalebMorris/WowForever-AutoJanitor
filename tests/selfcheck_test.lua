local helpers = require("helpers")
local assertEqual = helpers.assertEqual
local assertTrue = helpers.assertTrue
local assertFalse = helpers.assertFalse
local assertContains = helpers.assertContains

local function completeGlobals(addon)
    local globals = {}
    for _, name in ipairs(addon.SelfCheck.REQUIRED) do
        local current = globals
        local pathParts = {}
        for part in name:gmatch("[^%.]+") do
            pathParts[#pathParts + 1] = part
        end
        for index = 1, #pathParts - 1 do
            current[pathParts[index]] = current[pathParts[index]] or {}
            current = current[pathParts[index]]
        end
        current[pathParts[#pathParts]] = function() end
    end
    return globals
end

return function(test)
    local addon = helpers.loadAddon({ "SelfCheck" })
    local SelfCheck = addon.SelfCheck

    test("the story 7 APIs are all required", function()
        local required = {}
        for _, name in ipairs(SelfCheck.REQUIRED) do
            required[name] = true
        end
        local story7 = {
            "C_Container.GetContainerItemInfo", "C_Container.PickupContainerItem",
            "C_Container.GetContainerNumFreeSlots", "C_Container.GetContainerNumSlots",
            "DeleteCursorItem", "LootSlot", "GetLootSlotLink", "GetLootSlotInfo",
            "GetNumLootItems", "C_Item.GetItemInfo", "GetCursorInfo", "ClearCursor",
        }
        for _, name in ipairs(story7) do
            assertTrue(required[name], name .. " must be required")
        end
    end)

    test("all APIs present: ok with nothing missing", function()
        local result = SelfCheck.run(completeGlobals(addon))
        assertTrue(result.ok)
        assertEqual(result.missing, {})
    end)

    test("a missing global function is reported", function()
        local globals = completeGlobals(addon)
        globals.DeleteCursorItem = nil
        local result = SelfCheck.run(globals)
        assertFalse(result.ok)
        assertEqual(result.missing, { "DeleteCursorItem" })
    end)

    test("a missing namespaced function is reported", function()
        local globals = completeGlobals(addon)
        globals.C_Container.PickupContainerItem = nil
        local result = SelfCheck.run(globals)
        assertEqual(result.missing, { "C_Container.PickupContainerItem" })
    end)

    test("a missing namespace table is reported for each member", function()
        local globals = completeGlobals(addon)
        globals.C_Container = nil
        local result = SelfCheck.run(globals)
        assertFalse(result.ok)
        assertTrue(#result.missing >= 4)
        for _, name in ipairs(result.missing) do
            assertContains(name, "C_Container.")
        end
    end)

    test("a name that exists but is not a function counts as missing", function()
        local globals = completeGlobals(addon)
        globals.LootSlot = "oops"
        assertEqual(SelfCheck.run(globals).missing, { "LootSlot" })
    end)

    test("optional APIs missing warn but do not fail the check", function()
        local globals = completeGlobals(addon)
        globals.GetItemFamily = nil
        globals.GetCoinTextureString = nil
        local result = SelfCheck.run(globals)
        assertTrue(result.ok)
        assertEqual(#result.optionalMissing, #SelfCheck.OPTIONAL)
    end)

    test("report lists missing names and says the button is disabled", function()
        local lines = SelfCheck.report({ ok = false, missing = { "LootSlot", "ClearCursor" }, optionalMissing = {} })
        local text = table.concat(lines, "\n")
        assertContains(text, "LootSlot")
        assertContains(text, "ClearCursor")
        assertContains(text, "disabled")
    end)

    test("report is empty when everything is present", function()
        assertEqual(SelfCheck.report({ ok = true, missing = {}, optionalMissing = {} }), {})
    end)

    test("report mentions optional APIs that are missing", function()
        local lines = SelfCheck.report({ ok = true, missing = {}, optionalMissing = { "GetItemFamily" } })
        assertContains(table.concat(lines, "\n"), "GetItemFamily")
    end)
end
