-- Smoke test for AutoJanitor.lua against a stubbed WoW environment. It proves the
-- wiring loads, reacts to events and drives the pure modules. Real behavior on
-- the Forever client still has to be checked by hand in-game.
local helpers = require("helpers")
local assertEqual = helpers.assertEqual
local assertTrue = helpers.assertTrue
local assertFalse = helpers.assertFalse
local assertContains = helpers.assertContains

local MODULES = { "Planner", "Scanner", "SelfCheck", "Revalidate", "Messages", "Replacer" }

local function noop() end

local function newWidget(widgetType, name, parent, template)
    local widget = { widgetType = widgetType, name = name, parent = parent, template = template, scripts = {}, shown = false, enabled = true }
    return setmetatable(widget, { __index = function(table_, key)
        if key == "SetScript" then
            return function(self, scriptName, handler) self.scripts[scriptName] = handler end
        elseif key == "Show" then
            return function(self) self.shown = true end
        elseif key == "Hide" then
            return function(self) self.shown = false end
        elseif key == "IsShown" then
            return function(self) return self.shown end
        elseif key == "Enable" then
            return function(self) self.enabled = true end
        elseif key == "Disable" then
            return function(self) self.enabled = false end
        elseif key == "IsEnabled" then
            return function(self) return self.enabled end
        elseif key == "SetText" then
            return function(self, text) self.text = text end
        elseif key == "GetText" then
            return function(self) return self.text end
        end
        return noop
    end })
end

-- Installs stub globals and returns the world plus a cleanup function.
local function installWorld(options)
    options = options or {}
    local world = {
        frames = {},
        chat = {},
        bag = {
            [1] = { itemID = 101, stackCount = 3, quality = 0, isLocked = false },
            [2] = { itemID = 102, stackCount = 1, quality = 0, isLocked = false },
        },
        cursor = nil,
        lootLinks = { [1] = "|Hitem:500::::|h[Sword]|h" },
        deleteCalls = 0,
        timers = {},
    }
    local itemInfo = {
        [101] = { "Rag", 20, 5 },
        [102] = { "Cloth", 20, 50 },
        [500] = { "Sword", 1, 1000 },
    }
    local installed = {}
    local function set(name, value)
        installed[#installed + 1] = name
        _G[name] = value
    end

    set("CreateFrame", function(widgetType, name, parent, template)
        local widget = newWidget(widgetType, name, parent, template)
        world.frames[#world.frames + 1] = widget
        return widget
    end)
    set("DEFAULT_CHAT_FRAME", { AddMessage = function(_, message) world.chat[#world.chat + 1] = message end })
    set("GameTooltip", newWidget("GameTooltip"))
    set("UIParent", newWidget("Frame"))
    set("LootFrame", newWidget("Frame"))
    set("NUM_BAG_SLOTS", 0)
    set("InCombatLockdown", function() return false end)
    set("ERR_INV_FULL", "Inventory is full.")

    set("C_Container", {
        GetContainerNumSlots = function() return 2 end,
        GetContainerNumFreeSlots = function()
            local free = 0
            for slot = 1, 2 do if not world.bag[slot] then free = free + 1 end end
            return free, 0
        end,
        GetContainerItemInfo = function(_, slot)
            local entry = world.bag[slot]
            if not entry then return nil end
            return { itemID = entry.itemID, hyperlink = "|Hitem:" .. entry.itemID .. "::::|h[x]|h",
                stackCount = entry.stackCount, quality = entry.quality, isLocked = entry.isLocked }
        end,
        PickupContainerItem = function(_, slot)
            if world.bag[slot] then world.cursor = { itemID = world.bag[slot].itemID, slot = slot } end
        end,
    })
    set("C_Item", {
        GetItemInfo = function(link)
            local itemID = tonumber(link:match("item:(%d+)"))
            local entry = itemInfo[itemID]
            if not entry then return nil end
            return entry[1], link, 0, 1, 1, "t", "s", entry[2], "", "icon", entry[3]
        end,
        RequestLoadItemDataByID = noop,
    })
    set("C_Timer", { After = function(_, callback) world.timers[#world.timers + 1] = callback end })
    set("GetCursorInfo", function()
        if world.cursor then return "item", world.cursor.itemID end
        return nil
    end)
    set("ClearCursor", function() world.cursor = nil end)
    set("DeleteCursorItem", function()
        world.deleteCalls = world.deleteCalls + 1
        if world.cursor then
            world.bag[world.cursor.slot] = nil
            world.cursor = nil
        end
    end)
    set("GetNumLootItems", function() return 1 end)
    set("GetLootSlotType", function() return 1 end)
    set("GetLootSlotLink", function(slot) return world.lootLinks[slot] end)
    set("GetLootSlotInfo", function() return "icon", "Sword", 1, nil, 3, false end)
    set("LootSlot", function(slot)
        for target = 1, 2 do
            if not world.bag[target] then
                world.bag[target] = { itemID = 500, stackCount = 1, quality = 3, isLocked = false }
                break
            end
        end
        world.lootLinks[slot] = nil
    end)
    set("GetItemFamily", function() return 0 end)
    set("GetCoinTextureString", function(copper) return copper .. "c" end)

    for _, name in ipairs(options.removeGlobals or {}) do
        _G[name] = nil
    end

    local function cleanup()
        for _, name in ipairs(installed) do _G[name] = nil end
        _G.AutoJanitor_Replace = nil
        _G.BINDING_HEADER_AUTOJANITOR = nil
        _G.BINDING_NAME_AUTOJANITOR_REPLACE = nil
    end
    return world, cleanup
end

local function loadMain()
    local addon = helpers.loadAddon(MODULES)
    local chunk = assert(loadfile(helpers.addonSourceDirectory .. "/../AutoJanitor.lua"))
    chunk("AutoJanitor", addon)
    return addon
end

local function fire(world, event, ...)
    local mainFrame = world.frames[1]
    mainFrame.scripts.OnEvent(mainFrame, event, ...)
end

local function findButton(world)
    for _, widget in ipairs(world.frames) do
        if widget.template == "UIPanelButtonTemplate" then return widget end
    end
    return nil
end

local function chatText(world)
    return table.concat(world.chat, "\n")
end

return function(test)
    local function withWorld(options, body)
        local world, cleanup = installWorld(options)
        local ok, errorMessage = pcall(function()
            loadMain()
            body(world)
        end)
        cleanup()
        if not ok then error(errorMessage, 0) end
    end

    test("missing API: login names it and the button never appears", function()
        withWorld({ removeGlobals = { "DeleteCursorItem" } }, function(world)
            fire(world, "PLAYER_LOGIN")
            assertContains(chatText(world), "DeleteCursorItem")
            assertContains(chatText(world), "disabled")
            fire(world, "LOOT_OPENED")
            local button = findButton(world)
            assertTrue(button == nil or not button:IsShown())
        end)
    end)

    test("full self-check is silent and the keybinding strings are defined", function()
        withWorld({}, function(world)
            fire(world, "PLAYER_LOGIN")
            assertEqual(#world.chat, 0)
            assertEqual(type(_G.AutoJanitor_Replace), "function")
            assertEqual(type(_G.BINDING_HEADER_AUTOJANITOR), "string")
            assertEqual(type(_G.BINDING_NAME_AUTOJANITOR_REPLACE), "string")
        end)
    end)

    test("loot that does not fit shows an enabled button, loot closing hides it", function()
        withWorld({}, function(world)
            fire(world, "PLAYER_LOGIN")
            fire(world, "LOOT_OPENED")
            local button = findButton(world)
            assertTrue(button:IsShown())
            assertTrue(button:IsEnabled())
            assertEqual(button:GetText(), "Replace cheapest junk")
            fire(world, "LOOT_CLOSED")
            assertFalse(button:IsShown())
        end)
    end)

    test("clicking deletes the cheapest grey, loots the item and reports it", function()
        withWorld({}, function(world)
            fire(world, "PLAYER_LOGIN")
            fire(world, "LOOT_OPENED")
            findButton(world).scripts.OnClick(findButton(world))
            assertEqual(world.deleteCalls, 1)
            assertEqual(world.bag[1], nil, "Rag (value 15) is the cheapest grey")
            fire(world, "BAG_UPDATE_DELAYED")
            fire(world, "BAG_UPDATE_DELAYED")
            assertEqual(world.bag[1].itemID, 500, "Sword landed in the freed slot")
            assertContains(chatText(world), "Deleted")
        end)
    end)

    test("the keybinding function does the same as the button", function()
        withWorld({}, function(world)
            fire(world, "PLAYER_LOGIN")
            fire(world, "LOOT_OPENED")
            _G.AutoJanitor_Replace()
            assertEqual(world.deleteCalls, 1)
        end)
    end)

    test("keybinding with no loot window open does nothing", function()
        withWorld({}, function(world)
            fire(world, "PLAYER_LOGIN")
            _G.AutoJanitor_Replace()
            assertEqual(world.deleteCalls, 0)
        end)
    end)
end
