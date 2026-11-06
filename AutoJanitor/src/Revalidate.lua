-- Pure revalidation checks run before each protected step (Story 5).
-- Each returns true, or false plus a failure reason.
local _, addon = ...

local Revalidate = {}
addon.Revalidate = Revalidate

-- The bag slot must still hold the same unlocked grey stack we valued.
function Revalidate.bagSlot(expectedGrey, containerInfo)
    if not containerInfo
        or containerInfo.itemID ~= expectedGrey.itemID
        or containerInfo.isLocked
        or containerInfo.quality ~= 0
        or containerInfo.stackCount ~= expectedGrey.stackCount then
        return false, "bag_changed"
    end
    return true
end

-- The loot slot must still offer the expected item.
function Revalidate.lootSlot(expectedLootItem, currentLink)
    local itemID = type(currentLink) == "string" and tonumber(currentLink:match("item:(%d+)")) or nil
    if itemID ~= expectedLootItem.itemID then
        return false, "loot_changed"
    end
    return true
end

-- GetCursorInfo() returns ("item", itemID, itemLink) when an item is held.
function Revalidate.cursor(expectedGrey, cursorType, cursorItemID)
    if cursorType ~= "item" or cursorItemID ~= expectedGrey.itemID then
        return false, "cursor_mismatch"
    end
    return true
end

return Revalidate
