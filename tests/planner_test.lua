local helpers = require("helpers")
local assertEqual = helpers.assertEqual

local function lootItem(slot, sellPrice, overrides)
    local item = {
        slot = slot,
        itemID = 1000 + slot,
        name = "Loot" .. slot,
        link = "|Hitem:" .. (1000 + slot) .. "|h[Loot" .. slot .. "]|h",
        quantity = 1,
        sellPrice = sellPrice,
        family = 0,
        stackRoom = 0,
    }
    for key, value in pairs(overrides or {}) do
        item[key] = value
    end
    return item
end

local function grey(bag, slot, sellPrice, stackCount, overrides)
    local item = {
        bag = bag,
        slot = slot,
        itemID = 2000 + bag * 100 + slot,
        name = "Grey" .. bag .. "_" .. slot,
        stackCount = stackCount or 1,
        sellPrice = sellPrice,
        bagFamily = 0,
    }
    for key, value in pairs(overrides or {}) do
        item[key] = value
    end
    return item
end

local function slotsOf(entries, field)
    local slots = {}
    for _, entry in ipairs(entries) do
        slots[#slots + 1] = field and entry[field].slot or entry.slot
    end
    return slots
end

return function(test)
    local addon = helpers.loadAddon({ "Planner" })
    local plan = addon.Planner.plan

    test("everything fits in free slots: no swaps, no skips", function()
        local result = plan({
            lootItems = { lootItem(1, 10), lootItem(2, 20) },
            greys = {},
            freeSlotPools = { { family = 0, free = 2 } },
        })
        assertEqual(#result.swaps, 0)
        assertEqual(#result.skipped, 0)
        assertEqual(#result.fitting, 2)
    end)

    test("item that does not fit is swapped for a cheaper grey", function()
        local result = plan({
            lootItems = { lootItem(1, 100) },
            greys = { grey(0, 1, 5) },
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(#result.swaps, 1)
        assertEqual(result.swaps[1].lootItem.slot, 1)
        assertEqual(result.swaps[1].grey.slot, 1)
        assertEqual(result.swaps[1].lootValue, 100)
        assertEqual(result.swaps[1].greyValue, 5)
        assertEqual(#result.skipped, 0)
    end)

    test("grey worth more than the item: skipped as worth_less", function()
        local result = plan({
            lootItems = { lootItem(1, 5) },
            greys = { grey(0, 1, 100) },
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(#result.swaps, 0)
        assertEqual(result.skipped[1].reason, "worth_less")
    end)

    test("equal value is not worth swapping", function()
        local result = plan({
            lootItems = { lootItem(1, 50) },
            greys = { grey(0, 1, 50) },
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(#result.swaps, 0)
        assertEqual(result.skipped[1].reason, "worth_less")
    end)

    test("no greys at all: skipped as no_grey", function()
        local result = plan({
            lootItems = { lootItem(1, 50) },
            greys = {},
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(#result.swaps, 0)
        assertEqual(result.skipped[1].reason, "no_grey")
    end)

    test("loot value multiplies by quantity", function()
        local result = plan({
            lootItems = { lootItem(1, 10, { quantity = 5 }) },
            greys = { grey(0, 1, 40) },
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(result.swaps[1].lootValue, 50)
    end)

    test("grey value multiplies by stack count and the whole stack is the unit", function()
        local result = plan({
            lootItems = { lootItem(1, 30) },
            greys = { grey(0, 1, 10, 5), grey(0, 2, 10, 2) },
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(result.swaps[1].grey.slot, 2)
        assertEqual(result.swaps[1].greyValue, 20)
    end)

    test("highest loot pairs with the cheapest greys, extra items are no_grey", function()
        local result = plan({
            lootItems = { lootItem(1, 10), lootItem(2, 100), lootItem(3, 50) },
            greys = { grey(0, 1, 20), grey(0, 2, 5) },
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(#result.swaps, 2)
        assertEqual(result.swaps[1].lootItem.slot, 2)
        assertEqual(result.swaps[1].grey.slot, 2)
        assertEqual(result.swaps[2].lootItem.slot, 3)
        assertEqual(result.swaps[2].grey.slot, 1)
        assertEqual(#result.skipped, 1)
        assertEqual(result.skipped[1].lootItem.slot, 1)
        assertEqual(result.skipped[1].reason, "no_grey")
    end)

    test("second item worth less than the remaining grey is worth_less", function()
        local result = plan({
            lootItems = { lootItem(1, 100), lootItem(2, 10) },
            greys = { grey(0, 1, 5), grey(0, 2, 20) },
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(#result.swaps, 1)
        assertEqual(result.skipped[1].lootItem.slot, 2)
        assertEqual(result.skipped[1].reason, "worth_less")
    end)

    test("free slots go to the highest-value loot first", function()
        local result = plan({
            lootItems = { lootItem(1, 10), lootItem(2, 100), lootItem(3, 50) },
            greys = { grey(0, 1, 5) },
            freeSlotPools = { { family = 0, free = 1 } },
        })
        assertEqual(slotsOf(result.fitting), { 2 })
        assertEqual(slotsOf(result.swaps, "lootItem"), { 3 })
        assertEqual(result.skipped[1].lootItem.slot, 1)
        assertEqual(result.skipped[1].reason, "no_grey")
    end)

    test("items with unknown price are pending, never offered or skipped", function()
        local result = plan({
            lootItems = { lootItem(1, nil), lootItem(2, 100) },
            greys = { grey(0, 1, 5) },
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(slotsOf(result.pending), { 1 })
        assertEqual(slotsOf(result.swaps, "lootItem"), { 2 })
        assertEqual(#result.skipped, 0)
    end)

    test("item that merges into an existing stack needs no slot", function()
        local result = plan({
            lootItems = { lootItem(1, 10, { quantity = 3, stackRoom = 3 }) },
            greys = {},
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(slotsOf(result.fitting), { 1 })
        assertEqual(#result.skipped, 0)
    end)

    test("partial stack room that is too small still needs a slot", function()
        local result = plan({
            lootItems = { lootItem(1, 10, { quantity = 3, stackRoom = 2 }) },
            greys = {},
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(#result.fitting, 0)
        assertEqual(result.skipped[1].reason, "no_grey")
    end)

    test("specialty bag free slots only hold matching items", function()
        local result = plan({
            lootItems = { lootItem(1, 10, { family = 0 }), lootItem(2, 10, { family = 1 }) },
            greys = {},
            freeSlotPools = { { family = 1, free = 1 } },
        })
        assertEqual(slotsOf(result.fitting), { 2 })
        assertEqual(result.skipped[1].lootItem.slot, 1)
    end)

    test("matching specialty pool is used before the general pool", function()
        local result = plan({
            lootItems = { lootItem(1, 10, { family = 1 }), lootItem(2, 5, { family = 0 }) },
            greys = {},
            freeSlotPools = { { family = 0, free = 1 }, { family = 1, free = 1 } },
        })
        assertEqual(#result.fitting, 2)
        assertEqual(#result.skipped, 0)
    end)

    test("a grey in a specialty bag cannot make room for a non-matching item", function()
        local result = plan({
            lootItems = { lootItem(1, 100, { family = 0 }) },
            greys = { grey(1, 1, 1, 1, { bagFamily = 8 }), grey(0, 1, 5) },
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(result.swaps[1].grey.bag, 0)
    end)

    test("bagAccepts: general bags take anything, specialty bags need a shared family bit", function()
        assertEqual(addon.Planner.bagAccepts(0, 0), true)
        assertEqual(addon.Planner.bagAccepts(0, 32), true)
        assertEqual(addon.Planner.bagAccepts(8, 8), true)
        assertEqual(addon.Planner.bagAccepts(12, 4), true)
        assertEqual(addon.Planner.bagAccepts(8, 0), false)
        assertEqual(addon.Planner.bagAccepts(1, 6), false)
    end)

    test("ties on value are broken by bag then slot for a stable order", function()
        local result = plan({
            lootItems = { lootItem(1, 100) },
            greys = { grey(1, 1, 5), grey(0, 3, 5), grey(0, 2, 5) },
            freeSlotPools = { { family = 0, free = 0 } },
        })
        assertEqual(result.swaps[1].grey.bag, 0)
        assertEqual(result.swaps[1].grey.slot, 2)
    end)
end
