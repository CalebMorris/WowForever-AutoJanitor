-- Startup self-check (Story 7): many APIs are unverified on WoW Forever, so
-- test that each one the addon depends on exists before enabling anything.
local _, addon = ...

local SelfCheck = {}
addon.SelfCheck = SelfCheck

-- Missing any of these keeps the Replace button disabled.
SelfCheck.REQUIRED = {
    "C_Container.GetContainerItemInfo",
    "C_Container.PickupContainerItem",
    "C_Container.GetContainerNumFreeSlots",
    "C_Container.GetContainerNumSlots",
    "DeleteCursorItem",
    "LootSlot",
    "GetLootSlotLink",
    "GetLootSlotInfo",
    "GetNumLootItems",
    "C_Item.GetItemInfo",
    "GetCursorInfo",
    "ClearCursor",
    -- Beyond the Story 7 list, but also depended on:
    "GetLootSlotType",
    "C_Item.RequestLoadItemDataByID",
    "C_Timer.After",
}

-- Missing these only reduces accuracy or formatting, so the addon still works.
SelfCheck.OPTIONAL = {
    "GetItemFamily",
    "GetCoinTextureString",
}

local function isFunctionAt(globals, dottedName)
    local current = globals
    for part in dottedName:gmatch("[^%.]+") do
        if type(current) ~= "table" then
            return false
        end
        current = current[part]
    end
    return type(current) == "function"
end

local function findMissing(globals, names)
    local missing = {}
    for _, name in ipairs(names) do
        if not isFunctionAt(globals, name) then
            missing[#missing + 1] = name
        end
    end
    return missing
end

function SelfCheck.run(globals)
    local missing = findMissing(globals, SelfCheck.REQUIRED)
    return {
        ok = #missing == 0,
        missing = missing,
        optionalMissing = findMissing(globals, SelfCheck.OPTIONAL),
    }
end

function SelfCheck.report(result)
    local lines = {}
    if not result.ok then
        lines[#lines + 1] = "Missing required APIs: " .. table.concat(result.missing, ", ")
            .. ". The Replace button is disabled."
    end
    if #result.optionalMissing > 0 then
        lines[#lines + 1] = "Missing optional APIs (reduced accuracy or formatting): "
            .. table.concat(result.optionalMissing, ", ")
    end
    return lines
end

return SelfCheck
