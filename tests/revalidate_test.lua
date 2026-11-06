local helpers = require("helpers")
local assertEqual = helpers.assertEqual

local expectedGrey = { bag = 0, slot = 3, itemID = 10, stackCount = 4 }
local expectedLoot = { slot = 2, itemID = 20 }

local function bagInfo(overrides)
    local info = { itemID = 10, stackCount = 4, quality = 0, isLocked = false }
    for key, value in pairs(overrides or {}) do
        info[key] = value
    end
    return info
end

return function(test)
    local addon = helpers.loadAddon({ "Revalidate" })
    local Revalidate = addon.Revalidate

    test("bag slot unchanged passes", function()
        local ok = Revalidate.bagSlot(expectedGrey, bagInfo())
        assertEqual(ok, true)
    end)

    test("empty bag slot fails with bag_changed", function()
        local ok, reason = Revalidate.bagSlot(expectedGrey, nil)
        assertEqual(ok, false)
        assertEqual(reason, "bag_changed")
    end)

    test("different item in bag slot fails", function()
        local ok, reason = Revalidate.bagSlot(expectedGrey, bagInfo({ itemID = 99 }))
        assertEqual(ok, false)
        assertEqual(reason, "bag_changed")
    end)

    test("locked bag slot fails", function()
        local ok, reason = Revalidate.bagSlot(expectedGrey, bagInfo({ isLocked = true }))
        assertEqual(ok, false)
        assertEqual(reason, "bag_changed")
    end)

    test("bag item no longer grey fails", function()
        local ok = Revalidate.bagSlot(expectedGrey, bagInfo({ quality = 1 }))
        assertEqual(ok, false)
    end)

    test("changed stack count fails because the value changed", function()
        local ok = Revalidate.bagSlot(expectedGrey, bagInfo({ stackCount = 5 }))
        assertEqual(ok, false)
    end)

    test("loot slot with the expected item passes", function()
        local ok = Revalidate.lootSlot(expectedLoot, "|Hitem:20::::|h[Sword]|h")
        assertEqual(ok, true)
    end)

    test("empty or different loot slot fails with loot_changed", function()
        local ok, reason = Revalidate.lootSlot(expectedLoot, nil)
        assertEqual(ok, false)
        assertEqual(reason, "loot_changed")
        ok, reason = Revalidate.lootSlot(expectedLoot, "|Hitem:21::::|h[Other]|h")
        assertEqual(ok, false)
        assertEqual(reason, "loot_changed")
    end)

    test("cursor holding the expected item passes", function()
        assertEqual(Revalidate.cursor(expectedGrey, "item", 10), true)
    end)

    test("empty or different cursor fails with cursor_mismatch", function()
        local ok, reason = Revalidate.cursor(expectedGrey, nil, nil)
        assertEqual(ok, false)
        assertEqual(reason, "cursor_mismatch")
        ok, reason = Revalidate.cursor(expectedGrey, "item", 11)
        assertEqual(ok, false)
        assertEqual(reason, "cursor_mismatch")
        ok = Revalidate.cursor(expectedGrey, "spell", 10)
        assertEqual(ok, false)
    end)
end
