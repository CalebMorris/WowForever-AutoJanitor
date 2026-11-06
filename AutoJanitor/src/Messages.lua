-- Pure text and button-state formatting. No WoW API calls.
local _, addon = ...

local Messages = {}
addon.Messages = Messages

local DEFAULT_BUTTON_TEXT = "Replace cheapest junk"

local SKIP_REASON_TEXT = {
    no_grey = "no junk left to delete",
    worth_less = "worth less than your cheapest junk",
}

local FAILURE_TEXT = {
    combat = "you are in combat",
    bag_changed = "the junk in your bags changed",
    loot_changed = "the loot window changed",
    cursor_mismatch = "the cursor did not hold the expected junk",
    delete_failed = "the junk was not deleted",
    no_free_slot = "no bag slot was freed",
    loot_failed = "the item was not looted",
    inventory_full = "your inventory is still full",
}

-- coinFormatter is GetCoinTextureString in-game; the text fallback keeps tests simple.
function Messages.formatMoney(copper, coinFormatter)
    if coinFormatter then
        return coinFormatter(copper)
    end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local remainingCopper = copper % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if remainingCopper > 0 then parts[#parts + 1] = remainingCopper .. "c" end
    if #parts == 0 then
        return "0c"
    end
    return table.concat(parts, " ")
end

local function label(entry)
    return entry.link or entry.name or "item"
end

function Messages.skipReasonText(reason)
    return SKIP_REASON_TEXT[reason] or reason
end

function Messages.failureText(reason)
    return FAILURE_TEXT[reason]
end

function Messages.buttonState(plan)
    local swapCount = #plan.swaps
    local skippedCount = #plan.skipped
    local state = {
        visible = swapCount + skippedCount > 0,
        enabled = swapCount > 0,
        text = DEFAULT_BUTTON_TEXT,
    }
    if swapCount > 0 and skippedCount > 0 then
        state.text = string.format("Replace junk (%d of %d)", swapCount, swapCount + skippedCount)
    end
    return state
end

function Messages.skippedMessages(skipped)
    local lines = {}
    for _, entry in ipairs(skipped) do
        lines[#lines + 1] = "Skipped " .. label(entry.lootItem) .. ": " .. Messages.skipReasonText(entry.reason)
    end
    return lines
end

function Messages.tooltipLines(plan, coinFormatter)
    local lines = {}
    if #plan.swaps == 0 and #plan.skipped > 0 then
        lines[#lines + 1] = "Nothing can be replaced:"
    end
    for _, swap in ipairs(plan.swaps) do
        lines[#lines + 1] = string.format("Delete %s x%d (%s) for %s (%s)",
            label(swap.grey), swap.grey.stackCount, Messages.formatMoney(swap.greyValue, coinFormatter),
            label(swap.lootItem), Messages.formatMoney(swap.lootValue, coinFormatter))
    end
    for _, line in ipairs(Messages.skippedMessages(plan.skipped)) do
        lines[#lines + 1] = line
    end
    return lines
end

function Messages.deletedMessage(swap, coinFormatter)
    return string.format("Deleted %s x%d (%s) for %s",
        label(swap.grey), swap.grey.stackCount, Messages.formatMoney(swap.greyValue, coinFormatter),
        label(swap.lootItem))
end

-- report: { completed = {swap}, failed = { swap, reason, junkDeleted } or nil, notAttempted = {swap} }
function Messages.batchReport(report)
    local lines = {}
    lines[#lines + 1] = string.format("Replaced %d item(s).", #report.completed)
    if report.failed then
        local swap = report.failed.swap
        lines[#lines + 1] = "Stopped at " .. label(swap.lootItem) .. ": "
            .. (Messages.failureText(report.failed.reason) or report.failed.reason) .. "."
        if report.failed.junkDeleted then
            lines[#lines + 1] = label(swap.grey) .. " was already deleted, but " .. label(swap.lootItem)
                .. " was not looted. Loot it manually."
        end
    end
    for _, swap in ipairs(report.notAttempted or {}) do
        lines[#lines + 1] = "Not attempted: " .. label(swap.lootItem) .. " (would have replaced " .. label(swap.grey) .. ")"
    end
    return lines
end

return Messages
