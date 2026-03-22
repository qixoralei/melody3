-- ==============================================================
--  BYTECODE SYSTEM  -  Three ModuleScripts
--
--  1. ByteCodeEncoder  - builds the save string
--  2. ByteCodeInterpreter - reads/verifies the save string
--  3. ByteCodeFile - writefile / readfile helpers
--
--  REAL DATA LINE FORMAT:
--    RH:RH:{U}:RH:[I]:RH:|K|:DATA
--
--  FILE FORMAT:
--    ~40 decoy lines that look identical but have wrong checksums
--    1 real line whose |K| checksum is correct for this user
--    Lines are shuffled so the real one is at a random position
--    The file reader scans all lines and finds the valid one
-- ==============================================================


-- 
--  SHARED INTERNALS  (used by all three modules)
-- 

-- XOR compatibility (Lua 5.1 executor environments don't have the ~ operator)
local function bxor(a, b)
    local r, m, s = 0, 2^31
    repeat
        s, a, b = a + b + m, a % m, b % m
        r, m = r + m * (1 - 2 * (s % (2 * m) >= m and 1 or 0)), m / 2
    until m < 1
    return r
end
local SALT_BASE    = 0x5F3759DF
local DECOY_LINES  = 40        -- how many fake lines surround the real one (editable)
local RH_PER_LINE  = 6         -- red herring chunks per line (editable)
local RH_DIGITS    = 4         -- digits per chunk

local function makeLCG(seed)
	local s = (seed % 2147483647) + 1
	return function()
		s = (s * 1664525 + 1013904223) % 2147483648
		return s
	end
end

local function deriveKey(username, userId)
	local acc = SALT_BASE
	for i = 1, #username do
		acc = bxor(acc, (string.byte(username, i) * 31 * i)) % 65536
	end
	local idStr = tostring(userId)
	for i = 1, #idStr do
		acc = bxor(acc, (tonumber(string.sub(idStr, i, i)) * 17 * i)) % 65536
	end
	return acc % 256
end

local function deriveSalt(key, userId)
	return bxor(key, (userId % 256))
end

local function encodeUsername(username)
	local t = {}
	for i = 1, #username do t[i] = tostring(string.byte(username, i)) end
	return "{" .. table.concat(t, "-") .. "}"
end

local function decodeUsername(block)
	local inner = string.match(block, "^{(.+)}$")
	if not inner then return nil end
	local chars = {}
	for code in string.gmatch(inner, "([^%-]+)") do
		local n = tonumber(code)
		if not n then return nil end
		table.insert(chars, string.char(n))
	end
	return table.concat(chars)
end

local function encodeUserId(userId, salt)
	local idStr = tostring(userId)
	local padded = (#idStr % 2 == 1) and ("0" .. idStr) or idStr
	local parts = { string.format("%02d", #idStr) }  -- original length first
	for i = 1, #padded, 2 do
		local pair = tonumber(string.sub(padded, i, i + 1))
		table.insert(parts, string.format("%02d", (bxor(pair, salt)) % 100))
	end
	return "[" .. table.concat(parts, "-") .. "]"
end

local function decodeUserId(block, salt)
	local inner = string.match(block, "^%[(.+)%]$")
	if not inner then return nil end
	local parts = {}
	for v in string.gmatch(inner, "([^%-]+)") do table.insert(parts, tonumber(v)) end
	local origLen = parts[1]
	local digits = ""
	for i = 2, #parts do
		digits = digits .. string.format("%02d", bxor(parts[i], salt) % 100)
	end
	while #digits > origLen and string.sub(digits, 1, 1) == "0" do
		digits = string.sub(digits, 2)
	end
	return tonumber(digits)
end

local function encodePayload(values, key)
	local t = {}
	for _, v in ipairs(values) do table.insert(t, tostring(bxor(v, key))) end
	return table.concat(t, ",")
end

local function decodePayload(str, key)
	local values = {}
	for part in string.gmatch(str, "([^,]+)") do
		local n = tonumber(part)
		if n then table.insert(values, bxor(n, key)) end
	end
	return values
end

-- Build a single colon-separated line with red herrings injected
-- rhSeed controls the random chunks; uBlock/iBlock/interpKey/data are the real content
local function buildLine(uBlock, iBlock, interpKey, data, rhSeed)
	local lcg    = makeLCG(rhSeed)
	local chunks = {}

	-- Random positions for the real blocks within RH_PER_LINE slots
	-- We fix a layout: RH RH {U} RH [I] RH RH RH |K| DATA
	-- Red herrings fill positions not occupied by real blocks
	-- Total slots before |K|: RH_PER_LINE
	local parts = {}

	for _ = 1, 2 do  -- 2 RH before {U}
		table.insert(parts, string.format("%0" .. RH_DIGITS .. "d", lcg() % (10^RH_DIGITS)))
	end
	table.insert(parts, uBlock)
	for _ = 1, 1 do  -- 1 RH between {U} and [I]
		table.insert(parts, string.format("%0" .. RH_DIGITS .. "d", lcg() % (10^RH_DIGITS)))
	end
	table.insert(parts, iBlock)
	for _ = 1, (RH_PER_LINE - 3) do  -- remaining RH after [I]
		table.insert(parts, string.format("%0" .. RH_DIGITS .. "d", lcg() % (10^RH_DIGITS)))
	end
	table.insert(parts, "|" .. interpKey .. "|")
	table.insert(parts, data)

	return table.concat(parts, ":")
end

-- Build a convincing DECOY line: same structure but |K| is wrong
-- uBlock and iBlock are also fake (shifted ASCII / scrambled id)
local function buildDecoyLine(username, userId, key, rhSeed)
	local lcg = makeLCG(rhSeed)

	-- Fake username: shift each ASCII by a small amount derived from seed
	local fakeU = {}
	for i = 1, #username do
		local shift = (lcg() % 5) + 1
		table.insert(fakeU, tostring((string.byte(username, i) + shift) % 128))
	end
	local fakeUBlock = "{" .. table.concat(fakeU, "-") .. "}"

	-- Fake userId: scramble each encoded pair
	local fakeSalt   = lcg() % 256
	local fakeIBlock = encodeUserId(userId + (lcg() % 999 + 1), fakeSalt)

	-- Fake interpKey: anything except the real key % 100
	local fakeKey = (key + (lcg() % 99) + 1) % 100
	local fakeInterpKey = string.format("%02d", fakeKey)

	-- Fake data: random-looking numbers
	local fakeData = string.format("%d,%d,%d",
		lcg() % 99999,
		lcg() % 9999,
		lcg() % 999
	)

	local parts = {}
	for _ = 1, 2 do
		table.insert(parts, string.format("%0" .. RH_DIGITS .. "d", lcg() % (10^RH_DIGITS)))
	end
	table.insert(parts, fakeUBlock)
	for _ = 1, 1 do
		table.insert(parts, string.format("%0" .. RH_DIGITS .. "d", lcg() % (10^RH_DIGITS)))
	end
	table.insert(parts, fakeIBlock)
	for _ = 1, (RH_PER_LINE - 3) do
		table.insert(parts, string.format("%0" .. RH_DIGITS .. "d", lcg() % (10^RH_DIGITS)))
	end
	table.insert(parts, "|" .. fakeInterpKey .. "|")
	table.insert(parts, fakeData)

	return table.concat(parts, ":")
end

-- Fisher-Yates shuffle
local function shuffle(t, lcg)
	for i = #t, 2, -1 do
		local j = (lcg() % i) + 1
		t[i], t[j] = t[j], t[i]
	end
end


-- ==============================================================
--  MODULE 1: ENCODER
--  Usage: local enc = ByteCodeEncoder.Encode(username, userId, {coins, gems, ...})
-- ==============================================================

local ByteCodeEncoder = {}

function ByteCodeEncoder.Encode(username, userId, payload)
	assert(type(username) == "string" and #username > 0)
	assert(type(userId)   == "number" and userId > 0)
	payload = payload or {}

	local key        = deriveKey(username, userId)
	local salt       = deriveSalt(key, userId)
	local interpKey  = string.format("%02d", key % 100)
	local uBlock     = encodeUsername(username)
	local iBlock     = encodeUserId(userId, salt)
	local data       = encodePayload(payload, key)

	-- Seed for real line RH: derived from key + userId
	local realRhSeed = (key * 7 + userId) % 2147483647

	local realLine = buildLine(uBlock, iBlock, interpKey, data, realRhSeed)

	-- Build decoy lines, each with a unique seed
	local lines = { realLine }
	for i = 1, DECOY_LINES do
		local decoySeed = (key * 13 + userId * i + i * 997) % 2147483647
		table.insert(lines, buildDecoyLine(username, userId, key, decoySeed))
	end

	-- Shuffle so real line is at a random position
	local shuffleLcg = makeLCG((key + userId) % 2147483647)
	shuffle(lines, shuffleLcg)

	return table.concat(lines, "\n")
end

return ByteCodeEncoder
