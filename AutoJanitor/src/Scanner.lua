-- Reads loot and bag state through an injected `api` table and returns plain
-- data for the Planner. The WoW globals are bound to `api` in AutoJanitor.lua,
-- so this file never touches a WoW global and runs under plain Lua too.
local _, addon = ...

local Scanner = {}
addon.Scanner = Scanner

function Scanner.itemIDFromLink(link)
    if type(link) ~= "string" then
        return nil
    end
    local itemID = link:match("item:(%d+)")
    return itemID and tonumber(itemID) or nil
end

-- GetLootSlotInfo returns (icon, name, quantity, currencyID, quality, locked, ...)
-- on retail, but older clients return (icon, name, quantity, quality, locked).
-- Forever's layout is unverified, so detect it: in the retail layout the fifth
-- value is the numeric quality, in the older layout it is the boolean `locked`.
function Scanner.parseLootSlotInfo(_, _, quantity, fourth, fifth, sixth)
    if type(fifth) == "number" then
        return { quantity = quantity, quality = fifth, locked = sixth and true or false }
    end
    return { quantity = quantity, quality = fourth, locked = fifth and true or false }
end

local function readLootItems(api)
    local lootItems = {}
    local pendingItemIDs = {}
    local alreadyPending = {}
    local maxStackByItemID = {}

    for slot = 1, api.getNumLootItems() do
        if api.getLootSlotType(slot) == api.lootSlotTypeItem then
            local link = api.getLootSlotLink(slot)
            local itemID = Scanner.itemIDFromLink(link)
            if itemID then
                local lootInfo = Scanner.parseLootSlotInfo(api.getLootSlotInfo(slot))
                if not lootInfo.locked then
                    local itemInfo = api.getItemInfo(link)
                    if itemInfo and itemInfo.maxStack then
                        maxStackByItemID[itemID] = itemInfo.maxStack
                    end
                    if not itemInfo and not alreadyPending[itemID] then
                        alreadyPending[itemID] = true
                        pendingItemIDs[#pendingItemIDs + 1] = itemID
                    end
                    lootItems[#lootItems + 1] = {
                        slot = slot,
                        link = link,
                        itemID = itemID,
                        name = itemInfo and itemInfo.name or select(2, api.getLootSlotInfo(slot)),
                        quantity = lootInfo.quantity or 1,
                        quality = lootInfo.quality,
                        sellPrice = itemInfo and itemInfo.sellPrice or nil,
                        family = api.getItemFamily and api.getItemFamily(link) or 0,
                        stackRoom = 0,
                    }
                end
            end
        end
    end
    return lootItems, pendingItemIDs, maxStackByItemID
end

-- Returns the planner input plus `pendingItemIDs` (loot whose price is not cached yet):
-- { lootItems, greys, freeSlotPools, pendingItemIDs }
function Scanner.scan(api)
    local lootItems, pendingItemIDs, maxStackByItemID = readLootItems(api)

    local wantedItemIDs = {}
    for _, item in ipairs(lootItems) do
        wantedItemIDs[item.itemID] = true
    end

    local greys = {}
    local stackRoomByItemID = {}
    local freeByFamily = {}
    local familyOrder = {}

    for bag = 0, api.numBagSlots do
        local freeCount, bagFamily = api.getContainerNumFreeSlots(bag)
        bagFamily = bagFamily or 0
        if freeByFamily[bagFamily] == nil then
            freeByFamily[bagFamily] = 0
            familyOrder[#familyOrder + 1] = bagFamily
        end
        freeByFamily[bagFamily] = freeByFamily[bagFamily] + (freeCount or 0)

        for slot = 1, api.getContainerNumSlots(bag) do
            local containerInfo = api.getContainerItemInfo(bag, slot)
            if containerInfo then
                if containerInfo.quality == 0 and not containerInfo.isLocked then
                    local itemInfo = api.getItemInfo(containerInfo.hyperlink)
                    if itemInfo and itemInfo.sellPrice then
                        greys[#greys + 1] = {
                            bag = bag,
                            slot = slot,
                            itemID = containerInfo.itemID,
                            link = containerInfo.hyperlink,
                            name = itemInfo.name,
                            stackCount = containerInfo.stackCount or 1,
                            sellPrice = itemInfo.sellPrice,
                            bagFamily = bagFamily,
                        }
                    end
                end
                local maxStack = maxStackByItemID[containerInfo.itemID]
                if wantedItemIDs[containerInfo.itemID] and maxStack then
                    local room = maxStack - (containerInfo.stackCount or 1)
                    if room > 0 then
                        stackRoomByItemID[containerInfo.itemID] = (stackRoomByItemID[containerInfo.itemID] or 0) + room
                    end
                end
            end
        end
    end

    for _, item in ipairs(lootItems) do
        item.stackRoom = stackRoomByItemID[item.itemID] or 0
    end

    local freeSlotPools = {}
    for _, family in ipairs(familyOrder) do
        freeSlotPools[#freeSlotPools + 1] = { family = family, free = freeByFamily[family] }
    end

    return {
        lootItems = lootItems,
        greys = greys,
        freeSlotPools = freeSlotPools,
        pendingItemIDs = pendingItemIDs,
    }
end

return Scanner
