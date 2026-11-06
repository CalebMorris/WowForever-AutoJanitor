-- Plain Lua test runner with no dependencies.
-- Run from the repository root: lua tests/run.lua

local scriptPath = arg and arg[0] or "tests/run.lua"
local testsDirectory = scriptPath:match("^(.*)/[^/]*$") or "."
local repositoryRoot = testsDirectory .. "/.."
local addonSourceDirectory = repositoryRoot .. "/AutoJanitor/src"

package.path = testsDirectory .. "/?.lua;" .. package.path

local helpers = require("helpers")
helpers.addonSourceDirectory = addonSourceDirectory

local testFiles = {
    "planner_test",
    "scanner_test",
    "selfcheck_test",
    "revalidate_test",
    "messages_test",
    "wiring_test",
    "replacer_test",
}

local passedCount = 0
local failures = {}

local function describe(suiteName, suiteBody)
    local function test(testName, testBody)
        local ok, errorMessage = pcall(testBody)
        if ok then
            passedCount = passedCount + 1
        else
            failures[#failures + 1] = suiteName .. " > " .. testName .. "\n    " .. tostring(errorMessage)
        end
    end
    local ok, errorMessage = pcall(suiteBody, test)
    if not ok then
        failures[#failures + 1] = suiteName .. " (suite failed to load)\n    " .. tostring(errorMessage)
    end
end

for _, testFile in ipairs(testFiles) do
    local ok, suite = pcall(require, testFile)
    if ok then
        describe(testFile, suite)
    else
        failures[#failures + 1] = testFile .. " (could not be required)\n    " .. tostring(suite)
    end
end

print(string.format("%d passed, %d failed", passedCount, #failures))
for _, failure in ipairs(failures) do
    print("FAIL: " .. failure)
end
os.exit(#failures == 0 and 0 or 1)
