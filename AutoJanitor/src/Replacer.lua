-- Runs planned swaps one at a time (Story 5 / 5b) as a small state machine.
--
-- Every protected call can fail silently on WoW Forever, so no step trusts a
-- call to raise an error. Before each protected call the inputs are revalidated,
-- and after it the resulting bag, cursor and free-slot state is checked.
-- Waiting uses events (onBagUpdate, onInventoryFull) with a timeout fallback.
--
-- `api` is injected (bound to WoW globals in AutoJanitor.lua, faked in tests):
--   inCombat, getContainerItemInfo(bag, slot), countFreeSlots(family),
--   pickupContainerItem(bag, slot), getCursorInfo() -> type, itemID,
--   clearCursor, deleteCursorItem, getLootSlotLink(slot), lootSlot(slot),
--   after(seconds, callback)
-- `callbacks`: onSwapCompleted(swap), onFinished(report)
local _, addon = ...

local Replacer = {}
Replacer.__index = Replacer
addon.Replacer = Replacer

Replacer.STEP_TIMEOUT_SECONDS = 2

local PHASE_IDLE = "idle"
local PHASE_WAITING_DELETE = "waitingDelete"
local PHASE_WAITING_LOOT = "waitingLoot"

function Replacer.new(api, callbacks)
    return setmetatable({
        api = api,
        callbacks = callbacks or {},
        phase = PHASE_IDLE,
        token = 0,
    }, Replacer)
end

function Replacer:isBusy()
    return self.phase ~= PHASE_IDLE
end

-- Returns false when a batch is already running.
function Replacer:start(swaps)
    if self:isBusy() then
        return false
    end
    self.swaps = swaps
    self.index = 0
    self.completed = {}
    self.currentSwap = nil
    self.junkDeleted = false
    self.cursorMayBeHeld = false
    self:beginNextSwap()
    return true
end

function Replacer:finish(failure)
    local notAttempted = {}
    if failure then
        for index = self.index + 1, #self.swaps do
            notAttempted[#notAttempted + 1] = self.swaps[index]
        end
    end
    local report = { completed = self.completed, failed = failure, notAttempted = notAttempted }
    self.phase = PHASE_IDLE
    self.token = self.token + 1
    self.currentSwap = nil
    if self.callbacks.onFinished then
        self.callbacks.onFinished(report)
    end
end

function Replacer:fail(reason)
    if self.cursorMayBeHeld then
        self.api.clearCursor()
        self.cursorMayBeHeld = false
    end
    self:finish({ swap = self.currentSwap, reason = reason, junkDeleted = self.junkDeleted })
end

function Replacer:waitForStep()
    self.token = self.token + 1
    local expectedToken = self.token
    self.api.after(Replacer.STEP_TIMEOUT_SECONDS, function()
        if self.token == expectedToken and self:isBusy() then
            self:onTimeout()
        end
    end)
end

function Replacer:beginNextSwap()
    self.index = self.index + 1
    local swap = self.swaps[self.index]
    if not swap then
        self.index = #self.swaps
        self:finish(nil)
        return
    end
    self.currentSwap = swap
    self.junkDeleted = false
    self.cursorMayBeHeld = false

    local api = self.api
    if api.inCombat() then
        return self:fail("combat")
    end

    local bagOk, bagReason = addon.Revalidate.bagSlot(swap.grey, api.getContainerItemInfo(swap.grey.bag, swap.grey.slot))
    if not bagOk then
        return self:fail(bagReason)
    end
    local lootOk, lootReason = addon.Revalidate.lootSlot(swap.lootItem, api.getLootSlotLink(swap.lootItem.slot))
    if not lootOk then
        return self:fail(lootReason)
    end
    -- Never clobber something the player is already holding.
    if api.getCursorInfo() ~= nil then
        return self:fail("cursor_mismatch")
    end

    self.freeBeforeDelete = api.countFreeSlots(swap.lootItem.family)
    api.pickupContainerItem(swap.grey.bag, swap.grey.slot)
    self.cursorMayBeHeld = true
    local cursorType, cursorItemID = api.getCursorInfo()
    local cursorOk, cursorReason = addon.Revalidate.cursor(swap.grey, cursorType, cursorItemID)
    if not cursorOk then
        return self:fail(cursorReason)
    end

    api.deleteCursorItem()
    self.phase = PHASE_WAITING_DELETE
    self:waitForStep()
end

-- Verify the grey is really gone and a slot opened, then loot. Returns without
-- acting when the world has not settled yet and this is not the final timeout.
function Replacer:checkDeleted(isTimeout)
    local swap = self.currentSwap
    local api = self.api

    if api.getCursorInfo() ~= nil then
        return self:fail("delete_failed")
    end
    local remaining = api.getContainerItemInfo(swap.grey.bag, swap.grey.slot)
    if remaining and remaining.itemID == swap.grey.itemID then
        return self:fail("delete_failed")
    end
    self.junkDeleted = true
    self.cursorMayBeHeld = false

    local freeNow = api.countFreeSlots(swap.lootItem.family)
    if freeNow <= self.freeBeforeDelete then
        if isTimeout then
            return self:fail("no_free_slot")
        end
        return
    end

    local lootOk, lootReason = addon.Revalidate.lootSlot(swap.lootItem, api.getLootSlotLink(swap.lootItem.slot))
    if not lootOk then
        return self:fail(lootReason)
    end

    self.freeAfterDelete = freeNow
    self.inventoryFullSeen = false
    self.phase = PHASE_WAITING_LOOT
    api.lootSlot(swap.lootItem.slot)
    self:waitForStep()
end

-- A free slot being consumed is the proof that the item reached the bags.
function Replacer:checkLooted(isTimeout)
    local swap = self.currentSwap
    if self.api.countFreeSlots(swap.lootItem.family) < self.freeAfterDelete then
        self.completed[#self.completed + 1] = swap
        self.cursorMayBeHeld = false
        if self.callbacks.onSwapCompleted then
            self.callbacks.onSwapCompleted(swap)
        end
        self.phase = PHASE_IDLE
        self.token = self.token + 1
        return self:beginNextSwap()
    end
    if isTimeout then
        return self:fail("loot_failed")
    end
end

function Replacer:onBagUpdate()
    if self.phase == PHASE_WAITING_DELETE then
        self:checkDeleted(false)
    elseif self.phase == PHASE_WAITING_LOOT then
        self:checkLooted(false)
    end
end

function Replacer:onInventoryFull()
    if self.phase == PHASE_WAITING_LOOT then
        self:fail("inventory_full")
    end
end

function Replacer:onTimeout()
    if self.phase == PHASE_WAITING_DELETE then
        self:checkDeleted(true)
    elseif self.phase == PHASE_WAITING_LOOT then
        self:checkLooted(true)
    end
end

return Replacer
