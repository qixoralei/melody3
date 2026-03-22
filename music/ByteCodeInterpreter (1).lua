-- ==============================================================
--  BYTECODE INTERPRETER  -  ModuleScript
--  Scans a save string (multi-line), finds the ONE valid line,
--  and returns the decoded username, userId, and payload.
--
--  Usage:
--    local Interpreter = require(path.ByteCodeInterpreter)
--    local name, id, data = Interpreter.Decode(saveString)
--    local ok             = Interpreter.Verify(saveString, username, userId)
--    local coins          = data[1]
-- ==============================================================

local SALT_BASE = 0x5F3759DF

--  Internal helpers (duplicated here so Interpreter is self-contained) 

local function deriveKey(username, userId)
	local acc = SALT_BASE
	for i = 1, #username do
		acc = (acc ~ (string.byte(username, i) * 31 * i)) % 65536
	end
	local idStr = tostring(userId)
	for i = 1, #idStr do
		acc = (acc ~ (tonumber(string.sub(idStr, i, i)) * 17 * i)) % 65536
	end
	return acc % 256
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
	-- Validate: all chars should be printable ASCII (32-126)
	for _, c in ipairs(chars) do
		if string.byte(c) < 32 or string.byte(c) > 126 then return nil end
	end
	return table.concat(chars)
end

local function decodeUserId(block, salt)
	local inner = string.match(block, "^%[(.+)%]$")
	if not inner then return nil end
	local parts = {}
	for v in string.gmatch(inner, "([^%-]+)") do
		local n = tonumber(v)
		if not n then return nil end
		table.insert(parts, n)
	end
	if #parts < 2 then return nil end
	local origLen = parts[1]
	if origLen < 1 or origLen > 20 then return nil end  -- sanity check
	local digits = ""
	for i = 2, #parts do
		digits = digits .. string.format("%02d", (parts[i] ~ salt) % 100)
	end
	while #digits > origLen and string.sub(digits, 1, 1) == "0" do
		digits = string.sub(digits, 2)
	end
	local id = tonumber(digits)
	if not id or id <= 0 then return nil end
	return id
end

local function decodePayload(str, key)
	local values = {}
	for part in string.gmatch(str, "([^,]+)") do
		local n = tonumber(part)
		if n then table.insert(values, n ~ key) end
	end
	return values
end

-- Try to decode a single line. Returns username, userId, payload or nil.
local function tryDecodeLine(line)
	-- Must contain {}, [], |K|, and data
	local uBlock    = string.match(line, "{[^}]+}")
	local iBlock    = string.match(line, "%[[^%]]+%]")
	local interpKey = string.match(line, "|(%d+)|")
	local dataStr   = string.match(line, "|%d+|:(.+)$")

	if not uBlock or not iBlock or not interpKey or not dataStr then return nil end

	local username = decodeUsername(uBlock)
	if not username then return nil end

	local targetMod = tonumber(interpKey)
	if not targetMod then return nil end

	-- Try all key candidates where key % 100 == targetMod
	for candidateKey = targetMod, 255, 100 do
		local salt = candidateKey ~ (255)  -- temporary; refined per userId attempt
		-- For each possible (userId % 256), try to decode the id block
		for uidMod = 0, 255 do
			local trySalt = candidateKey ~ uidMod
			local decodedId = decodeUserId(iBlock, trySalt)
			if decodedId and decodedId > 0 then
				-- Verify full key
				local checkKey = deriveKey(username, decodedId)
				if checkKey == candidateKey then
					-- Verify salt consistency
					local expectedSalt = candidateKey ~ (decodedId % 256)
					if expectedSalt == trySalt then
						-- Valid line found
						local payload = decodePayload(dataStr, candidateKey)
						return username, decodedId, payload
					end
				end
			end
		end
	end

	return nil
end

--  Public API 

local ByteCodeInterpreter = {}

--[[
	ByteCodeInterpreter.Decode(saveString)
	Scans all lines, finds the valid one, returns:
	  username (string), userId (number), payload (table)
	  or nil, errorString on failure.
]]
function ByteCodeInterpreter.Decode(saveString)
	if type(saveString) ~= "string" or #saveString == 0 then
		return nil, "empty or invalid save string"
	end

	for line in string.gmatch(saveString .. "\n", "([^\n]*)\n") do
		line = string.match(line, "^%s*(.-)%s*$")  -- trim whitespace
		if #line > 0 then
			local username, userId, payload = tryDecodeLine(line)
			if username then
				return username, userId, payload
			end
		end
	end

	return nil, "no valid line found in save data"
end

--[[
	ByteCodeInterpreter.Verify(saveString, expectedUsername, expectedUserId)
	Returns true if the save string decodes to the expected user.
]]
function ByteCodeInterpreter.Verify(saveString, expectedUsername, expectedUserId)
	local username, userId, _ = ByteCodeInterpreter.Decode(saveString)
	return username == expectedUsername and userId == expectedUserId
end

--[[
	ByteCodeInterpreter.GetPayload(saveString)
	Convenience: just returns the payload table, or empty table on failure.
]]
function ByteCodeInterpreter.GetPayload(saveString)
	local _, _, payload = ByteCodeInterpreter.Decode(saveString)
	return payload or {}
end

return ByteCodeInterpreter
