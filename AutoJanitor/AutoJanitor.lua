-- Thin WoW wiring: events, the loot-window button, and the keybinding.
-- All decisions live in src/ (pure Lua, tested outside the game).
local addonName, addon = ...

local CHAT_PREFIX = "|cff33ff99Auto Janitor:|r "

local selfCheckResult = nil
local lootWindowOpen = false
local currentPlan = nil
local announcedSkipSignature = nil
local button = nil
local replacer = nil

local function say(message)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. message)
end

local function coinFormatter()
    return GetCoinTextureString
end

-- Binds the WoW globals to the plain function table the src/ modules expect.
local function buildApi()
    return {
        numBagSlots = NUM_BAG_SLOTS or 4,
        lootSlotTypeItem = 1, -- LOOT_SLOT_* constants were removed in 10.0; compare numerically
        getContainerNumSlots = C_Container.GetContainerNumSlots,
        getContainerNumFreeSlots = C_Container.GetContainerNumFreeSlots,
        getContainerItemInfo = C_Container.GetContainerItemInfo,
        getNumLootItems = GetNumLootItems,
        getLootSlotType = GetLootSlotType,
        getLootSlotLink = GetLootSlotLink,
        getLootSlotInfo = GetLootSlotInfo,
        getItemFamily = GetItemFamily, -- optional; nil is handled by the Scanner
        getItemInfo = function(link)
            -- C_Item.GetItemInfo returns nil until the item is cached.
            local name, _, quality, _, _, _, _, maxStack, _, _, sellPrice = C_Item.GetItemInfo(link)
            if not name then
                return nil
            end
            return { name = name, quality = quality, maxStack = maxStack, sellPrice = sellPrice }
        end,
    }
end

local function countFreeSlots(itemFamily)
    local total = 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local freeCount, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
        if addon.Planner.bagAccepts(bagFamily, itemFamily) then
            total = total + (freeCount or 0)
        end
    end
    return total
end

local function buildReplacerApi()
    return {
        inCombat = InCombatLockdown,
        getContainerItemInfo = C_Container.GetContainerItemInfo,
        countFreeSlots = countFreeSlots,
        pickupContainerItem = C_Container.PickupContainerItem,
        getCursorInfo = function()
            local cursorType, itemID = GetCursorInfo()
            return cursorType, itemID
        end,
        clearCursor = ClearCursor,
        deleteCursorItem = DeleteCursorItem,
        getLootSlotLink = GetLootSlotLink,
        lootSlot = LootSlot,
        after = C_Timer.After,
    }
end

local function ensureButton()
    if button then
        return button
    end
    button = CreateFrame("Button", "AutoJanitorReplaceButton", LootFrame or UIParent, "UIPanelButtonTemplate")
    button:SetSize(180, 22)
    button:SetPoint("TOP", LootFrame or UIParent, "BOTTOM", 0, -4)
    button:SetText("Replace cheapest junk")
    button:SetScript("OnClick", function()
        AutoJanitor_Replace()
    end)
    button:SetScript("OnEnter", function(self)
        if not currentPlan then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Auto Janitor")
        for _, line in ipairs(addon.Messages.tooltipLines(currentPlan, coinFormatter())) do
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:Hide()
    return button
end

local function updateButton()
    if not lootWindowOpen or not currentPlan or not selfCheckResult or not selfCheckResult.ok then
        if button then
            button:Hide()
        end
        return
    end
    local buttonState = addon.Messages.buttonState(currentPlan)
    if not buttonState.visible then
        if button then
            button:Hide()
        end
        return
    end
    ensureButton()
    button:SetText(buttonState.text)
    if buttonState.enabled and not InCombatLockdown() and not replacer:isBusy() then
        button:Enable()
    else
        button:Disable()
    end
    button:Show()
end

-- Chat line listing each skipped item and why, once per distinct set of skips.
local function announceSkipped()
    local signature = {}
    for _, entry in ipairs(currentPlan.skipped) do
        signature[#signature + 1] = entry.lootItem.slot .. ":" .. entry.reason
    end
    local joined = table.concat(signature, ",")
    if joined == announcedSkipSignature then
        return
    end
    announcedSkipSignature = joined
    for _, line in ipairs(addon.Messages.skippedMessages(currentPlan.skipped)) do
        say(line)
    end
end

local function refresh()
    if not lootWindowOpen or not selfCheckResult or not selfCheckResult.ok or replacer:isBusy() then
        return
    end
    local scan = addon.Scanner.scan(buildApi())
    for _, itemID in ipairs(scan.pendingItemIDs) do
        C_Item.RequestLoadItemDataByID(itemID)
    end
    currentPlan = addon.Planner.plan(scan)
    if #currentPlan.skipped > 0 then
        announceSkipped()
    end
    updateButton()
end

-- Called by the button, by the keybinding (Bindings.xml) and by the tests.
function AutoJanitor_Replace()
    if not selfCheckResult or not selfCheckResult.ok then
        say("Disabled because required APIs are missing. See the message at login.")
        return
    end
    if replacer:isBusy() then
        return
    end
    if not lootWindowOpen then
        say("Open a loot window first.")
        return
    end
    if InCombatLockdown() then
        say("Cannot replace items in combat.")
        return
    end
    -- Always plan from fresh state: bags may have changed since the button appeared.
    refresh()
    if not currentPlan or #currentPlan.swaps == 0 then
        if not currentPlan or #currentPlan.skipped == 0 then
            say("Nothing to replace.")
        end
        for _, line in ipairs(addon.Messages.tooltipLines(currentPlan or { swaps = {}, skipped = {} }, coinFormatter())) do
            say(line)
        end
        return
    end
    replacer:start(currentPlan.swaps)
    updateButton()
end

local function onSwapCompleted(swap)
    say(addon.Messages.deletedMessage(swap, coinFormatter()))
end

local function onFinished(report)
    if report.failed or #report.notAttempted > 0 then
        for _, line in ipairs(addon.Messages.batchReport(report)) do
            say(line)
        end
    end
    refresh()
    updateButton()
end

local function isInventoryFullMessage(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "string" and (value == ERR_INV_FULL or value:find("Inventory is full", 1, true)) then
            return true
        end
    end
    return false
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("LOOT_CLOSED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        BINDING_HEADER_AUTOJANITOR = "Auto Janitor"
        BINDING_NAME_AUTOJANITOR_REPLACE = "Replace cheapest junk"
        replacer = addon.Replacer.new(buildReplacerApi(), {
            onSwapCompleted = onSwapCompleted,
            onFinished = onFinished,
        })
        selfCheckResult = addon.SelfCheck.run(_G)
        for _, line in ipairs(addon.SelfCheck.report(selfCheckResult)) do
            say(line)
        end
    elseif event == "LOOT_OPENED" then
        lootWindowOpen = true
        announcedSkipSignature = nil
        refresh()
    elseif event == "LOOT_CLOSED" then
        lootWindowOpen = false
        currentPlan = nil
        updateButton()
    elseif event == "BAG_UPDATE_DELAYED" then
        if replacer then
            replacer:onBagUpdate()
        end
        refresh()
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        refresh()
    elseif event == "UI_ERROR_MESSAGE" then
        if replacer and isInventoryFullMessage(...) then
            replacer:onInventoryFull()
        end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        updateButton()
    end
end)
