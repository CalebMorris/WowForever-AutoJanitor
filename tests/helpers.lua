-- Shared test helpers: assertions and a loader that mimics how WoW passes
-- (addonName, addonTable) to every file listed in the TOC.

local helpers = {}

function helpers.loadAddon(moduleNames)
    local addon = {}
    for _, moduleName in ipairs(moduleNames) do
        local path = helpers.addonSourceDirectory .. "/" .. moduleName .. ".lua"
        local chunk, loadError = loadfile(path)
        if not chunk then
            error("cannot load " .. path .. ": " .. tostring(loadError), 0)
        end
        chunk("AutoJanitor", addon)
    end
    return addon
end

local function describeValue(value)
    if type(value) == "table" then
        local parts = {}
        for key, inner in pairs(value) do
            parts[#parts + 1] = tostring(key) .. "=" .. describeValue(inner)
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(value)
end

local function deepEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not deepEqual(value, right[key]) then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

function helpers.assertEqual(actual, expected, label)
    if not deepEqual(actual, expected) then
        error((label and (label .. ": ") or "")
            .. "expected " .. describeValue(expected) .. " but got " .. describeValue(actual), 2)
    end
end

function helpers.assertTrue(value, label)
    if not value then
        error((label or "expected a truthy value") .. " (got " .. tostring(value) .. ")", 2)
    end
end

function helpers.assertFalse(value, label)
    if value then
        error((label or "expected a falsy value") .. " (got " .. tostring(value) .. ")", 2)
    end
end

function helpers.assertContains(text, fragment, label)
    if type(text) ~= "string" or not text:find(fragment, 1, true) then
        error((label and (label .. ": ") or "") .. "expected " .. tostring(text) .. " to contain " .. fragment, 2)
    end
end

return helpers
