-- ByteCodeInterpreter
-- Scans all lines, finds the one whose checksum matches the derived key.
-- No brute force needed -- checksum IS the key, verified directly.

local SALT = 137

local function simpleHash(username, userId)
    local h = SALT
    for i = 1, #username do
        h = (h * 31 + string.byte(username, i)) % 65521
    end
    local s = tostring(userId)
    for i = 1, #s do
        h = (h * 17 + tonumber(string.sub(s, i, i))) % 65521
    end
    return h
end

local function decodeStr(encoded)
    local chars = {}
    for code in string.gmatch(encoded, "([^%-]+)") do
        local n = tonumber(code)
        if not n then return nil end
        table.insert(chars, string.char(n))
    end
    return table.concat(chars)
end

local function decodePayload(dataEnc, key)
    local values = {}
    for part in string.gmatch(dataEnc, "([^,]+)") do
        local n = tonumber(part)
        if n then
            -- reverse: (v + key) % 1000000 -> v = n - key (mod 1000000)
            local v = (n - key) % 1000000
            table.insert(values, v)
        end
    end
    return values
end

local function tryLine(line)
    local uBlock   = string.match(line, "{([^}]+)}")
    local idBlock  = string.match(line, "%[([^%]]+)%]")
    local checksum = string.match(line, "|(%d+)|")
    local dataEnc  = string.match(line, "|%d+|:(.+)$")

    if not uBlock or not idBlock or not checksum or not dataEnc then return nil end

    local username = decodeStr(uBlock)
    local userIdStr = decodeStr(idBlock)
    if not username or not userIdStr then return nil end

    -- validate: all decoded chars should be printable
    for i = 1, #username do
        local b = string.byte(username, i)
        if b < 32 or b > 126 then return nil end
    end

    local userId = tonumber(userIdStr)
    if not userId or userId <= 0 then return nil end

    -- verify checksum directly -- no brute force
    local expectedKey = simpleHash(username, userId)
    if tonumber(checksum) ~= expectedKey then return nil end

    local payload = decodePayload(dataEnc, expectedKey)
    return username, userId, payload
end

local Interpreter = {}

function Interpreter.Decode(saveString)
    if type(saveString) ~= "string" or #saveString == 0 then
        return nil, "empty save string"
    end
    for line in string.gmatch(saveString .. "\n", "([^\n]*)\n") do
        line = string.match(line, "^%s*(.-)%s*$")
        if #line > 0 then
            local username, userId, payload = tryLine(line)
            if username then
                return username, userId, payload
            end
        end
    end
    return nil, "no valid line found in save data"
end

function Interpreter.Verify(saveString, expectedUsername, expectedUserId)
    local username, userId = Interpreter.Decode(saveString)
    return username == expectedUsername and userId == expectedUserId
end

function Interpreter.GetPayload(saveString)
    local _, _, payload = Interpreter.Decode(saveString)
    return payload or {}
end

return Interpreter
