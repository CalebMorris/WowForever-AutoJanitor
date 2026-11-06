local helpers = require("helpers")
local assertEqual = helpers.assertEqual

local function link(itemID)
    return "|cff9d9d9d|Hitem:" .. itemID .. "::::::::|h[Item" .. itemID .. "]|h|r"
end

-- Builds a fake WoW API from plain tables so scans are deterministic.
local function fakeApi(config)
    local api = {
        numBagSlots = config.numBagSlots or 1,
        lootSlotTypeItem = 1,
    }
    local bags = config.bags or {}
    local loot = config.loot or {}
    local itemInfoByID = config.itemInfo or {}

    function api.getContainerNumSlots(bag)
        return bags[bag] and bags[bag].size or 0
    end
    function api.getContainerNumFreeSlots(bag)
        local bagData = bags[bag]
        if not bagData then
            return 0, 0
        end
        local free = 0
        for slot = 1, bagData.size do
            if not bagData.items or not bagData.items[slot] then
                free = free + 1
            end
        end
        return free, bagData.family or 0
    end
    function api.getContainerItemInfo(bag, slot)
        local bagData = bags[bag]
        return bagData and bagData.items and bagData.items[slot] or nil
    end
    function api.getItemInfo(itemLink)
        local itemID = tonumber(itemLink:match("item:(%d+)"))
        return itemInfoByID[itemID]
    end
    function api.getItemFamily(itemLink)
        local itemID = tonumber(itemLink:match("item:(%d+)"))
        return config.itemFamily and config.itemFamily[itemID] or 0
    end
    function api.getNumLootItems()
        return #loot
    end
    function api.getLootSlotType(slot)
        return loot[slot].slotType
    end
    function api.getLootSlotLink(slot)
        return loot[slot].link
    end
    function api.getLootSlotInfo(slot)
        local unpackValues = table.unpack or unpack
        return unpackValues(loot[slot].info, 1, 6)
    end
    api.requested = {}
    return api
end

local function bagItem(itemID, stackCount, quality, isLocked)
    return {
        itemID = itemID,
        hyperlink = link(itemID),
        stackCount = stackCount or 1,
        quality = quality or 0,
        isLocked = isLocked or false,
    }
end

-- Retail layout: icon, name, quantity, currencyID, quality, locked
local function lootEntry(itemID, quantity, quality, locked)
    return {
        slotType = 1,
        link = link(itemID),
        info = { "icon", "Item" .. itemID, quantity or 1, nil, quality or 1, locked or false },
    }
end

return function(test)
    local addon = helpers.loadAddon({ "Planner", "Scanner" })
    local Scanner = addon.Scanner

    test("itemIDFromLink extracts the numeric id", function()
        assertEqual(Scanner.itemIDFromLink(link(12345)), 12345)
        assertEqual(Scanner.itemIDFromLink("not a link"), nil)
        assertEqual(Scanner.itemIDFromLink(nil), nil)
    end)

    test("parseLootSlotInfo handles the retail layout (currencyID before quality)", function()
        local parsed = Scanner.parseLootSlotInfo("icon", "Name", 3, nil, 2, true)
        assertEqual(parsed, { quantity = 3, quality = 2, locked = true })
    end)

    test("parseLootSlotInfo handles the older layout (quality then locked)", function()
        local parsed = Scanner.parseLootSlotInfo("icon", "Name", 4, 1, false)
        assertEqual(parsed, { quantity = 4, quality = 1, locked = false })
    end)

    test("scan finds grey stacks with known prices and ignores other qualities", function()
        local api = fakeApi({
            bags = { [0] = { size = 3, items = {
                [1] = bagItem(10, 4, 0),
                [2] = bagItem(11, 1, 1),
                [3] = bagItem(12, 1, 0),
            } } },
            itemInfo = {
                [10] = { name = "Rag", sellPrice = 5, maxStack = 20 },
                [11] = { name = "Linen", sellPrice = 50, maxStack = 20 },
                [12] = { name = "Mystery", sellPrice = nil, maxStack = 1 },
            },
        })
        local scan = Scanner.scan(api)
        assertEqual(#scan.greys, 1)
        assertEqual(scan.greys[1].bag, 0)
        assertEqual(scan.greys[1].slot, 1)
        assertEqual(scan.greys[1].stackCount, 4)
        assertEqual(scan.greys[1].sellPrice, 5)
        assertEqual(scan.greys[1].itemID, 10)
    end)

    test("scan ignores locked grey stacks", function()
        local api = fakeApi({
            bags = { [0] = { size = 1, items = { [1] = bagItem(10, 1, 0, true) } } },
            itemInfo = { [10] = { name = "Rag", sellPrice = 5, maxStack = 20 } },
        })
        assertEqual(#Scanner.scan(api).greys, 0)
    end)

    test("scan aggregates free slots per bag family", function()
        local api = fakeApi({
            numBagSlots = 2,
            bags = {
                [0] = { size = 2, items = { [1] = bagItem(10) } },
                [1] = { size = 3, family = 0 },
                [2] = { size = 4, family = 8 },
            },
            itemInfo = { [10] = { name = "Rag", sellPrice = 5, maxStack = 20 } },
        })
        local scan = Scanner.scan(api)
        local freeByFamily = {}
        for _, pool in ipairs(scan.freeSlotPools) do
            freeByFamily[pool.family] = pool.free
        end
        assertEqual(freeByFamily, { [0] = 4, [8] = 4 })
    end)

    test("scan records the bag family of each grey", function()
        local api = fakeApi({
            numBagSlots = 1,
            bags = {
                [0] = { size = 1 },
                [1] = { size = 1, family = 8, items = { [1] = bagItem(10) } },
            },
            itemInfo = { [10] = { name = "Rag", sellPrice = 5, maxStack = 20 } },
        })
        assertEqual(Scanner.scan(api).greys[1].bagFamily, 8)
    end)

    test("scan reads item loot slots and skips money and currency", function()
        local api = fakeApi({
            bags = { [0] = { size = 0 } },
            loot = {
                { slotType = 2, link = nil, info = { "icon", "5 Copper", 0, nil, 0, false } },
                lootEntry(20, 2),
                { slotType = 3, link = nil, info = { "icon", "Badge", 1, 99, 1, false } },
            },
            itemInfo = { [20] = { name = "Sword", sellPrice = 100, maxStack = 1 } },
        })
        local scan = Scanner.scan(api)
        assertEqual(#scan.lootItems, 1)
        assertEqual(scan.lootItems[1].slot, 2)
        assertEqual(scan.lootItems[1].itemID, 20)
        assertEqual(scan.lootItems[1].quantity, 2)
        assertEqual(scan.lootItems[1].sellPrice, 100)
        assertEqual(scan.lootItems[1].name, "Sword")
    end)

    test("scan skips locked loot slots", function()
        local api = fakeApi({
            bags = { [0] = { size = 0 } },
            loot = { lootEntry(20, 1, 4, true) },
            itemInfo = { [20] = { name = "Sword", sellPrice = 100, maxStack = 1 } },
        })
        assertEqual(#Scanner.scan(api).lootItems, 0)
    end)

    test("uncached loot price gives a nil sellPrice and is listed as pending", function()
        local api = fakeApi({
            bags = { [0] = { size = 0 } },
            loot = { lootEntry(20, 1) },
            itemInfo = {},
        })
        local scan = Scanner.scan(api)
        assertEqual(scan.lootItems[1].sellPrice, nil)
        assertEqual(scan.pendingItemIDs, { 20 })
    end)

    test("stack room sums free space in partial stacks of the same item", function()
        local api = fakeApi({
            bags = { [0] = { size = 3, items = {
                [1] = bagItem(20, 15, 1),
                [2] = bagItem(20, 20, 1),
                [3] = bagItem(21, 1, 1),
            } } },
            loot = { lootEntry(20, 4, 1) },
            itemInfo = { [20] = { name = "Linen", sellPrice = 10, maxStack = 20 } },
        })
        assertEqual(Scanner.scan(api).lootItems[1].stackRoom, 5)
    end)

    test("loot family comes from getItemFamily and defaults to 0 when unavailable", function()
        local api = fakeApi({
            bags = { [0] = { size = 0 } },
            loot = { lootEntry(20) },
            itemFamily = { [20] = 32 },
            itemInfo = { [20] = { name = "Herb", sellPrice = 10, maxStack = 20 } },
        })
        assertEqual(Scanner.scan(api).lootItems[1].family, 32)
        api.getItemFamily = nil
        assertEqual(Scanner.scan(api).lootItems[1].family, 0)
    end)

    test("scan output feeds the planner end to end", function()
        local api = fakeApi({
            bags = { [0] = { size = 1, items = { [1] = bagItem(10, 3, 0) } } },
            loot = { lootEntry(20, 1, 3) },
            itemInfo = {
                [10] = { name = "Rag", sellPrice = 5, maxStack = 20 },
                [20] = { name = "Sword", sellPrice = 100, maxStack = 1 },
            },
        })
        local scan = Scanner.scan(api)
        local plan = addon.Planner.plan(scan)
        assertEqual(#plan.swaps, 1)
        assertEqual(plan.swaps[1].greyValue, 15)
    end)
end
