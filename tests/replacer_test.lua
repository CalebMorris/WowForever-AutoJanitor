local helpers = require("helpers")
local assertEqual = helpers.assertEqual
local assertTrue = helpers.assertTrue
local assertFalse = helpers.assertFalse

-- A small simulated world: one bag, a cursor, a loot window and a timer queue.
-- Protected calls can be made to fail silently to prove state is verified.
local function newFake(slotCount)
    local fake = {
        calls = {},
        timers = {},
        bag = {},
        slotCount = slotCount or 4,
        cursor = nil,
        lootLinks = {},
        lootItems = {},
        combat = false,
        deleteWorks = true,
        lootWorks = true,
        pickupPutsOnCursor = nil,
        completed = {},
        finishedReport = nil,
    }

    local function record(name)
        fake.calls[#fake.calls + 1] = name
    end

    fake.api = {
        inCombat = function() return fake.combat end,
        getContainerItemInfo = function(bag, slot) return fake.bag[slot] end,
        countFreeSlots = function()
            local free = 0
            for slot = 1, fake.slotCount do
                if not fake.bag[slot] then free = free + 1 end
            end
            return free
        end,
        pickupContainerItem = function(bag, slot)
            record("pickup")
            if fake.pickupPutsOnCursor then
                fake.cursor = fake.pickupPutsOnCursor
            elseif fake.bag[slot] and not fake.bag[slot].isLocked then
                fake.cursor = { type = "item", itemID = fake.bag[slot].itemID, slot = slot }
            end
        end,
        getCursorInfo = function()
            if fake.cursor then return fake.cursor.type, fake.cursor.itemID end
            return nil
        end,
        clearCursor = function()
            record("clearCursor")
            fake.cursor = nil
        end,
        deleteCursorItem = function()
            record("delete")
            if fake.deleteWorks and fake.cursor and fake.cursor.slot then
                fake.bag[fake.cursor.slot] = nil
                fake.cursor = nil
            end
        end,
        getLootSlotLink = function(slot) return fake.lootLinks[slot] end,
        lootSlot = function(slot)
            record("lootSlot")
            if fake.lootWorks and fake.lootLinks[slot] then
                for target = 1, fake.slotCount do
                    if not fake.bag[target] then
                        fake.bag[target] = { itemID = fake.lootItems[slot], stackCount = 1, quality = 1, isLocked = false }
                        break
                    end
                end
                fake.lootLinks[slot] = nil
            end
        end,
        after = function(seconds, callback)
            fake.timers[#fake.timers + 1] = callback
        end,
    }

    function fake.fireTimers()
        local pending = fake.timers
        fake.timers = {}
        for _, callback in ipairs(pending) do callback() end
    end

    function fake.putGrey(slot, itemID, stackCount)
        fake.bag[slot] = { itemID = itemID, stackCount = stackCount or 1, quality = 0, isLocked = false }
    end

    function fake.putLoot(slot, itemID)
        fake.lootLinks[slot] = "|Hitem:" .. itemID .. "::::|h[Loot" .. itemID .. "]|h"
        fake.lootItems[slot] = itemID
    end

    function fake.callCount(name)
        local count = 0
        for _, call in ipairs(fake.calls) do
            if call == name then count = count + 1 end
        end
        return count
    end

    return fake
end

local function swapFor(lootSlot, lootItemID, bagSlot, greyItemID, stackCount)
    return {
        lootItem = { slot = lootSlot, itemID = lootItemID, family = 0, name = "Loot" .. lootItemID },
        grey = { bag = 0, slot = bagSlot, itemID = greyItemID, stackCount = stackCount or 1, name = "Grey" .. greyItemID },
        lootValue = 100,
        greyValue = 5,
    }
end

return function(test)
    local addon = helpers.loadAddon({ "Revalidate", "Replacer" })

    local function newReplacer(fake)
        local callbacks = {
            onSwapCompleted = function(swap) fake.completed[#fake.completed + 1] = swap end,
            onFinished = function(report) fake.finishedReport = report end,
        }
        return addon.Replacer.new(fake.api, callbacks)
    end

    -- Bags full (4 slots, 4 greys), one loot item.
    local function fullBagWorld()
        local fake = newFake(4)
        for slot = 1, 4 do fake.putGrey(slot, 100 + slot, 1) end
        fake.putLoot(1, 500)
        return fake
    end

    test("happy path waits for bag updates before each state check", function()
        local fake = fullBagWorld()
        local replacer = newReplacer(fake)
        assertTrue(replacer:start({ swapFor(1, 500, 2, 102) }))
        assertEqual(fake.calls, { "pickup", "delete" })
        assertEqual(fake.bag[2], nil, "grey deleted")
        assertTrue(replacer:isBusy())

        replacer:onBagUpdate()
        assertEqual(fake.callCount("lootSlot"), 1)
        assertEqual(fake.bag[2].itemID, 500, "loot landed in the freed slot")

        replacer:onBagUpdate()
        assertFalse(replacer:isBusy())
        assertEqual(#fake.finishedReport.completed, 1)
        assertEqual(fake.finishedReport.failed, nil)
        assertEqual(#fake.completed, 1)
    end)

    test("in combat nothing is touched", function()
        local fake = fullBagWorld()
        fake.combat = true
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102), swapFor(2, 501, 3, 103) })
        assertEqual(fake.calls, {})
        assertEqual(fake.finishedReport.failed.reason, "combat")
        assertEqual(#fake.finishedReport.notAttempted, 1)
        assertFalse(fake.finishedReport.failed.junkDeleted)
    end)

    test("bag slot changed since planning: abort before touching anything", function()
        local fake = fullBagWorld()
        fake.bag[2].itemID = 999
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102) })
        assertEqual(fake.callCount("pickup"), 0)
        assertEqual(fake.callCount("delete"), 0)
        assertEqual(fake.finishedReport.failed.reason, "bag_changed")
    end)

    test("loot slot changed since planning: abort before touching anything", function()
        local fake = fullBagWorld()
        fake.lootLinks[1] = nil
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102) })
        assertEqual(fake.callCount("delete"), 0)
        assertEqual(fake.finishedReport.failed.reason, "loot_changed")
    end)

    test("cursor already holding something: abort without deleting", function()
        local fake = fullBagWorld()
        fake.cursor = { type = "item", itemID = 777 }
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102) })
        assertEqual(fake.callCount("delete"), 0)
        assertEqual(fake.callCount("pickup"), 0)
        assertEqual(fake.finishedReport.failed.reason, "cursor_mismatch")
    end)

    test("pickup that puts the wrong thing on the cursor clears it and never deletes", function()
        local fake = fullBagWorld()
        fake.pickupPutsOnCursor = { type = "item", itemID = 555 }
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102) })
        assertEqual(fake.callCount("delete"), 0)
        assertEqual(fake.callCount("clearCursor"), 1)
        assertEqual(fake.finishedReport.failed.reason, "cursor_mismatch")
    end)

    test("pickup that leaves the cursor empty never deletes", function()
        local fake = fullBagWorld()
        fake.bag[2].isLocked = true
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102) })
        assertEqual(fake.callCount("delete"), 0)
        assertEqual(fake.finishedReport.failed.reason, "bag_changed")
    end)

    test("delete that silently fails is caught by checking the bag", function()
        local fake = fullBagWorld()
        fake.deleteWorks = false
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102) })
        replacer:onBagUpdate()
        assertEqual(fake.callCount("lootSlot"), 0)
        assertEqual(fake.callCount("clearCursor"), 1)
        assertEqual(fake.finishedReport.failed.reason, "delete_failed")
        assertFalse(fake.finishedReport.failed.junkDeleted)
    end)

    test("a missing bag update event falls back to a timeout check", function()
        local fake = fullBagWorld()
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102) })
        fake.fireTimers()
        assertEqual(fake.callCount("lootSlot"), 1)
    end)

    test("slot emptied but no free slot appeared: waits, then fails on timeout", function()
        local fake = fullBagWorld()
        local realCount = fake.api.countFreeSlots
        fake.api.countFreeSlots = function() return 0 end
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102) })
        replacer:onBagUpdate()
        assertTrue(replacer:isBusy(), "still waiting after one bag update")
        fake.fireTimers()
        assertEqual(fake.callCount("lootSlot"), 0)
        assertEqual(fake.finishedReport.failed.reason, "no_free_slot")
        assertTrue(fake.finishedReport.failed.junkDeleted)
        fake.api.countFreeSlots = realCount
    end)

    test("loot that silently fails is reported after the timeout with junk already deleted", function()
        local fake = fullBagWorld()
        fake.lootWorks = false
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102) })
        replacer:onBagUpdate()
        assertEqual(fake.callCount("lootSlot"), 1)
        replacer:onBagUpdate()
        assertTrue(replacer:isBusy(), "bag update alone does not prove the loot arrived")
        fake.fireTimers()
        assertEqual(fake.finishedReport.failed.reason, "loot_failed")
        assertTrue(fake.finishedReport.failed.junkDeleted)
        assertEqual(fake.callCount("clearCursor"), 0, "cursor was already verified empty after the delete")
    end)

    test("inventory full error while looting fails immediately", function()
        local fake = fullBagWorld()
        fake.lootWorks = false
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102) })
        replacer:onBagUpdate()
        replacer:onInventoryFull()
        assertEqual(fake.finishedReport.failed.reason, "inventory_full")
        assertTrue(fake.finishedReport.failed.junkDeleted)
    end)

    test("inventory full error outside the looting phase is ignored", function()
        local fake = fullBagWorld()
        local replacer = newReplacer(fake)
        replacer:onInventoryFull()
        assertFalse(replacer:isBusy())
        assertEqual(fake.finishedReport, nil)
    end)

    test("two swaps run one at a time", function()
        local fake = fullBagWorld()
        fake.putLoot(2, 501)
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102), swapFor(2, 501, 3, 103) })
        assertEqual(fake.callCount("delete"), 1)
        replacer:onBagUpdate()
        replacer:onBagUpdate()
        assertEqual(fake.callCount("delete"), 2, "second swap began after the first finished")
        replacer:onBagUpdate()
        replacer:onBagUpdate()
        assertEqual(#fake.finishedReport.completed, 2)
        assertEqual(#fake.completed, 2)
        assertFalse(replacer:isBusy())
    end)

    test("first failure stops the batch and lists what was not attempted", function()
        local fake = fullBagWorld()
        fake.putLoot(2, 501)
        fake.putLoot(3, 502)
        fake.bag[3].itemID = 999
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102), swapFor(2, 501, 3, 103), swapFor(3, 502, 4, 104) })
        replacer:onBagUpdate()
        replacer:onBagUpdate()
        assertEqual(#fake.finishedReport.completed, 1)
        assertEqual(fake.finishedReport.failed.reason, "bag_changed")
        assertEqual(fake.finishedReport.failed.swap.lootItem.itemID, 501)
        assertEqual(#fake.finishedReport.notAttempted, 1)
        assertEqual(fake.finishedReport.notAttempted[1].lootItem.itemID, 502)
    end)

    test("start while busy is refused", function()
        local fake = fullBagWorld()
        local replacer = newReplacer(fake)
        assertTrue(replacer:start({ swapFor(1, 500, 2, 102) }))
        assertFalse(replacer:start({ swapFor(1, 500, 3, 103) }))
        assertEqual(fake.callCount("delete"), 1)
    end)

    test("stale timers from a finished swap do nothing", function()
        local fake = fullBagWorld()
        fake.putLoot(2, 501)
        local replacer = newReplacer(fake)
        replacer:start({ swapFor(1, 500, 2, 102), swapFor(2, 501, 3, 103) })
        replacer:onBagUpdate()
        replacer:onBagUpdate()
        -- first swap is done and the second is waiting; the first swap's timers are stale
        local staleTimers = fake.timers
        fake.timers = {}
        for index = 1, #staleTimers - 1 do staleTimers[index]() end
        assertEqual(fake.callCount("delete"), 2)
        assertTrue(replacer:isBusy())
    end)

    test("an empty batch finishes immediately with an empty report", function()
        local fake = fullBagWorld()
        local replacer = newReplacer(fake)
        replacer:start({})
        assertEqual(#fake.finishedReport.completed, 0)
        assertEqual(fake.finishedReport.failed, nil)
    end)
end
