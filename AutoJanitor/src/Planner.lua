-- Pure swap planning: decides which loot fits, which bag greys to delete for
-- which loot, and which loot is skipped (with a reason). No WoW API calls.
local _, addon = ...

local Planner = {}
addon.Planner = Planner

Planner.SKIP_NO_GREY = "no_grey"
Planner.SKIP_WORTH_LESS = "worth_less"

-- Bag families are bit masks. Lua 5.1 has no bit operators, so test any shared bit by hand.
local function sharesFamilyBit(firstMask, secondMask)
    local first = firstMask or 0
    local second = secondMask or 0
    while first > 0 and second > 0 do
        if first % 2 == 1 and second % 2 == 1 then
            return true
        end
        first = math.floor(first / 2)
        second = math.floor(second / 2)
    end
    return false
end

-- A bag can hold an item when it is a general bag (family 0) or shares a family bit.
local function bagAccepts(bagFamily, itemFamily)
    return (bagFamily or 0) == 0 or sharesFamilyBit(bagFamily, itemFamily)
end

Planner.bagAccepts = bagAccepts

local function lootValue(item)
    return item.sellPrice * item.quantity
end

local function greyValue(grey)
    return grey.sellPrice * grey.stackCount
end

local function takeFreeSlot(freeSlotPools, item)
    -- Prefer a matching specialty pool so general slots stay available for other items.
    for _, pool in ipairs(freeSlotPools) do
        if pool.family ~= 0 and pool.free > 0 and sharesFamilyBit(pool.family, item.family) then
            pool.free = pool.free - 1
            return true
        end
    end
    for _, pool in ipairs(freeSlotPools) do
        if pool.family == 0 and pool.free > 0 then
            pool.free = pool.free - 1
            return true
        end
    end
    return false
end

local function copyPools(freeSlotPools)
    local copies = {}
    for index, pool in ipairs(freeSlotPools or {}) do
        copies[index] = { family = pool.family or 0, free = pool.free }
    end
    return copies
end

-- input.lootItems: { slot, quantity, sellPrice (nil = not cached), family, stackRoom }
-- input.greys:     { bag, slot, stackCount, sellPrice, bagFamily }
-- input.freeSlotPools: { family, free }
-- Returns { fitting, swaps, skipped, pending }.
function Planner.plan(input)
    local result = { fitting = {}, swaps = {}, skipped = {}, pending = {} }
    local freeSlotPools = copyPools(input.freeSlotPools)

    local priced = {}
    for _, item in ipairs(input.lootItems) do
        if item.sellPrice == nil then
            result.pending[#result.pending + 1] = item
        else
            priced[#priced + 1] = item
        end
    end

    -- Most valuable loot first: it gets free slots first and the cheapest greys first.
    table.sort(priced, function(left, right)
        local leftValue, rightValue = lootValue(left), lootValue(right)
        if leftValue ~= rightValue then
            return leftValue > rightValue
        end
        return left.slot < right.slot
    end)

    local needsSwap = {}
    for _, item in ipairs(priced) do
        if (item.stackRoom or 0) >= item.quantity or takeFreeSlot(freeSlotPools, item) then
            result.fitting[#result.fitting + 1] = item
        else
            needsSwap[#needsSwap + 1] = item
        end
    end

    local greys = {}
    for _, grey in ipairs(input.greys) do
        greys[#greys + 1] = grey
    end
    table.sort(greys, function(left, right)
        local leftValue, rightValue = greyValue(left), greyValue(right)
        if leftValue ~= rightValue then
            return leftValue < rightValue
        end
        if left.bag ~= right.bag then
            return left.bag < right.bag
        end
        return left.slot < right.slot
    end)

    local assignedGreys = {}
    for _, item in ipairs(needsSwap) do
        local cheapestGrey
        for _, grey in ipairs(greys) do
            if not assignedGreys[grey] and bagAccepts(grey.bagFamily, item.family) then
                cheapestGrey = grey
                break
            end
        end

        if not cheapestGrey then
            result.skipped[#result.skipped + 1] = { lootItem = item, reason = Planner.SKIP_NO_GREY }
        elseif lootValue(item) > greyValue(cheapestGrey) then
            assignedGreys[cheapestGrey] = true
            result.swaps[#result.swaps + 1] = {
                lootItem = item,
                grey = cheapestGrey,
                lootValue = lootValue(item),
                greyValue = greyValue(cheapestGrey),
            }
        else
            result.skipped[#result.skipped + 1] = { lootItem = item, reason = Planner.SKIP_WORTH_LESS }
        end
    end

    return result
end

return Planner
