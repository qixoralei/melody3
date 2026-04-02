-- GuiObfuscator
-- Randomizes all GUI element names, ZIndex offsets, and position jitter
-- on every session so the Explorer tree is never fingerprint-stable.
-- Call obfuscateGui(screenGui) immediately after any ScreenGui is built/parented.
-- Call reObfuscateGui(screenGui) periodically (e.g. every 45s) to re-scramble idle GUIs.

local GuiObfuscator = {}

-- ── Internal RNG (seeded per session so names differ every run) ────────────────
local _seed = (tick() * 1e6 + math.random(1, 999999)) % 2147483647

local function lcgNext()
    _seed = (_seed * 1664525 + 1013904223) % 4294967296
    return _seed
end

-- Produces a random alphanumeric tag of the given length.
-- Uses the session-seeded LCG so results are unpredictable but stable
-- within a single run (no math.random drift).
local CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
local CHARSET_LEN = #CHARSET

local function randomTag(len)
    -- First char: letter only (avoids names starting with a digit)
    local alpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local t = { string.sub(alpha, (lcgNext() % #alpha) + 1, (lcgNext() % #alpha) + 1) }
    for _ = 2, len do
        t[#t+1] = string.sub(CHARSET, (lcgNext() % CHARSET_LEN) + 1, (lcgNext() % CHARSET_LEN) + 1)
    end
    return table.concat(t)
end

-- ── Position jitter ────────────────────────────────────────────────────────────
-- Shifts X and Y offsets by ±JITTER pixels so pixel-exact selectors never match.
-- Visual impact is imperceptible at 2px; widen to 4 if layout allows.
local JITTER = 2

local function jitterOffset()
    return (lcgNext() % (JITTER * 2 + 1)) - JITTER   -- range [-JITTER, JITTER]
end

-- ── ZIndex scramble ────────────────────────────────────────────────────────────
-- Shifts ZIndex by -1, 0, or +1 within the safe band [1, 20].
local function scrambleZIndex(current)
    local delta = (lcgNext() % 3) - 1   -- -1, 0, or +1
    return math.clamp(current + delta, 1, 20)
end

-- ── Core obfuscation pass ──────────────────────────────────────────────────────
-- Walks every descendant of `root` (a ScreenGui or Frame) and:
--   1. Renames it to a random tag
--   2. Jitters GuiObject positions
--   3. Scrambles ZIndex
-- Returns a name-map table { [randomName] = originalName } so callers can
-- restore references if needed (most callers won't need this).
function GuiObfuscator.obfuscateGui(root)
    if not root then return {} end
    local nameMap = {}

    -- Scramble the root itself
    local rootOld = root.Name
    local rootNew = randomTag(14)
    root.Name = rootNew
    nameMap[rootNew] = rootOld

    for _, obj in ipairs(root:GetDescendants()) do
        -- 1. Rename
        local oldName = obj.Name
        local newName = randomTag(12)
        obj.Name  = newName
        nameMap[newName] = oldName

        -- 2. Position jitter + ZIndex scramble (GuiObjects only)
        if obj:IsA("GuiObject") then
            local p = obj.Position
            obj.Position = UDim2.new(
                p.X.Scale,
                p.X.Offset + jitterOffset(),
                p.Y.Scale,
                p.Y.Offset + jitterOffset()
            )
            obj.ZIndex = scrambleZIndex(obj.ZIndex)
        end
    end

    return nameMap
end

-- ── Periodic re-obfuscation ────────────────────────────────────────────────────
-- Re-runs obfuscateGui on the given root every `intervalSeconds`.
-- Stops automatically if the root is destroyed.
-- Returns a cleanup function: call it to stop the loop early.
function GuiObfuscator.startPeriodicReObfuscation(root, intervalSeconds)
    intervalSeconds = intervalSeconds or 45
    local running = true

    task.spawn(function()
        while running do
            task.wait(intervalSeconds)
            if not running then break end
            if not root or not root.Parent then break end
            GuiObfuscator.obfuscateGui(root)
        end
    end)

    return function() running = false end
end

-- ── DisplayOrder randomizer ────────────────────────────────────────────────────
-- Shifts the ScreenGui's DisplayOrder into a random high band so the stack
-- position never matches a fixed hook value.
local DISPLAY_ORDER_BASE = 900

function GuiObfuscator.randomizeDisplayOrder(screenGui)
    if not screenGui or not screenGui:IsA("ScreenGui") then return end
    screenGui.DisplayOrder = DISPLAY_ORDER_BASE + (lcgNext() % 99)
end

return GuiObfuscator
