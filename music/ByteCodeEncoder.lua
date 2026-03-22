-- ByteCodeEncoder
-- Encodes username, userId, and payload into an obfuscated multi-line string.
-- The real data line is shuffled among decoy lines.
-- Decoys have a wrong checksum so the decoder can skip them instantly.

local DECOY_COUNT = 30
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

local function encodeStr(str)
    local t = {}
    for i = 1, #str do
        t[i] = string.byte(str, i)
    end
    return table.concat(t, "-")
end

local function encodePayload(values, key)
    local t = {}
    for _, v in ipairs(values) do
        -- simple XOR-style via modular arithmetic (no ~ operator needed)
        table.insert(t, tostring((v + key) % 1000000))
    end
    return table.concat(t, ",")
end

local function makeLCG(seed)
    local s = (seed % 2147483647) + 1
    return function()
        s = (s * 1103515245 + 12345) % 2147483648
        return s
    end
end

local function randomChunk(lcg, digits)
    local n = lcg() % (10 ^ digits)
    return string.format("%0" .. digits .. "d", n)
end

local function buildLine(uEnc, idEnc, checksum, dataEnc, rhSeed)
    local lcg = makeLCG(rhSeed)
    local parts = {}
    for _ = 1, 2 do table.insert(parts, randomChunk(lcg, 4)) end
    table.insert(parts, "{" .. uEnc .. "}")
    for _ = 1, 2 do table.insert(parts, randomChunk(lcg, 4)) end
    table.insert(parts, "[" .. idEnc .. "]")
    for _ = 1, 3 do table.insert(parts, randomChunk(lcg, 4)) end
    table.insert(parts, "|" .. string.format("%05d", checksum) .. "|")
    table.insert(parts, dataEnc)
    return table.concat(parts, ":")
end

local function buildDecoy(rhSeed)
    local lcg = makeLCG(rhSeed)
    local parts = {}
    -- fake username block
    local fu = {}
    for _ = 1, 5 do table.insert(fu, tostring(lcg() % 200 + 30)) end
    for _ = 1, 2 do table.insert(parts, randomChunk(lcg, 4)) end
    table.insert(parts, "{" .. table.concat(fu, "-") .. "}")
    for _ = 1, 2 do table.insert(parts, randomChunk(lcg, 4)) end
    -- fake id block
    local fi = {}
    for _ = 1, 4 do table.insert(fi, string.format("%02d", lcg() % 100)) end
    table.insert(parts, "[" .. table.concat(fi, "-") .. "]")
    for _ = 1, 3 do table.insert(parts, randomChunk(lcg, 4)) end
    -- wrong checksum: guaranteed != real by using lcg value
    local fakeCheck = lcg() % 65521
    table.insert(parts, "|" .. string.format("%05d", fakeCheck) .. "|")
    table.insert(parts, tostring(lcg() % 999999) .. "," .. tostring(lcg() % 9999))
    return table.concat(parts, ":")
end

local function shuffle(t, lcg)
    for i = #t, 2, -1 do
        local j = (lcg() % i) + 1
        t[i], t[j] = t[j], t[i]
    end
end

local Encoder = {}

function Encoder.Encode(username, userId, payload)
    payload = payload or {}
    local key      = simpleHash(username, userId)
    local checksum = key  -- checksum IS the key; decoder verifies directly

    local uEnc   = encodeStr(username)
    local idEnc  = encodeStr(tostring(userId))
    local dataEnc = encodePayload(payload, key)

    local realSeed = (key * 7 + userId) % 2147483647
    local realLine = buildLine(uEnc, idEnc, checksum, dataEnc, realSeed)

    local lines = {realLine}
    for i = 1, DECOY_COUNT do
        local decoySeed = (key * 13 + userId + i * 997) % 2147483647
        table.insert(lines, buildDecoy(decoySeed))
    end

    local shuffleLcg = makeLCG((key + userId) % 2147483647)
    shuffle(lines, shuffleLcg)

    return table.concat(lines, "\n")
end

return Encoder
