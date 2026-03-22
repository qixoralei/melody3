-- ==============================================================
--  BYTECODE FILE  -  ModuleScript (LocalScript context)
--  Handles saving and loading the encoded bytecode to/from
--  the local file system via writefile / readfile.
--
--  Each player gets their own file: saves/<userId>.bc
--  The file is just the raw multi-line encoded string.
--
--  Usage:
--    local File        = require(path.ByteCodeFile)
--    local Encoder     = require(path.ByteCodeEncoder)
--    local Interpreter = require(path.ByteCodeInterpreter)
--
--    -- Save:
--    local encoded = Encoder.Encode(username, userId, {coins, gems})
--    File.Save(userId, encoded)
--
--    -- Load and decode:
--    local raw = File.Load(userId)
--    if raw then
--        local name, id, data = Interpreter.Decode(raw)
--        print(name, id, data[1], data[2])
--    end
--
--    -- Quick helper: save new payload directly
--    File.SavePayload(username, userId, {coins, gems}, EncoderModule)
--
--    -- Quick helper: load payload directly
--    local payload = File.LoadPayload(userId, InterpreterModule)
-- ==============================================================

local ByteCodeFile = {}

--  Config 

local SAVE_DIR      = "bcsaves"    -- folder name (editable)
local FILE_EXT      = ".bc"        -- file extension (editable)

--  Helpers 

local function getPath(userId)
	return SAVE_DIR .. "/" .. tostring(userId) .. FILE_EXT
end

local function ensureDir()
	-- makefolder is available in most executors; pcall in case it already exists
	if makefolder then
		pcall(function()
			if not isfolder(SAVE_DIR) then
				makefolder(SAVE_DIR)
			end
		end)
	end
end

local function fsAvailable()
	return type(readfile)  == "function"
		and type(writefile) == "function"
		and type(isfile)    == "function"
end

--  Public API 

--[[
	ByteCodeFile.Save(userId, encodedString)
	Writes the encoded bytecode to disk.
	Returns true on success, false + error on failure.
]]
function ByteCodeFile.Save(userId, encodedString)
	if not fsAvailable() then
		return false, "filesystem API not available"
	end
	ensureDir()
	local path = getPath(userId)
	local ok, err = pcall(function()
		writefile(path, encodedString)
	end)
	if not ok then
		return false, "writefile failed: " .. tostring(err)
	end
	return true
end

--[[
	ByteCodeFile.Load(userId)
	Reads the raw encoded string from disk.
	Returns the string, or nil + error on failure.
]]
function ByteCodeFile.Load(userId)
	if not fsAvailable() then
		return nil, "filesystem API not available"
	end
	local path = getPath(userId)
	if not isfile(path) then
		return nil, "no save file found for userId " .. tostring(userId)
	end
	local ok, result = pcall(function()
		return readfile(path)
	end)
	if not ok or type(result) ~= "string" then
		return nil, "readfile failed: " .. tostring(result)
	end
	return result
end

--[[
	ByteCodeFile.Exists(userId)
	Returns true if a save file exists for this userId.
]]
function ByteCodeFile.Exists(userId)
	if not fsAvailable() then return false end
	local ok, result = pcall(function()
		return isfile(getPath(userId))
	end)
	return ok and result == true
end

--[[
	ByteCodeFile.Delete(userId)
	Deletes the save file for this userId.
	Returns true on success.
]]
function ByteCodeFile.Delete(userId)
	if not fsAvailable() then return false, "filesystem API not available" end
	local path = getPath(userId)
	local ok, err = pcall(function()
		if isfile(path) then
			delfile(path)
		end
	end)
	if not ok then return false, tostring(err) end
	return true
end

--[[
	ByteCodeFile.SavePayload(username, userId, payload, EncoderModule)
	Convenience: encodes and saves in one call.
	EncoderModule = require(path.ByteCodeEncoder)
]]
function ByteCodeFile.SavePayload(username, userId, payload, EncoderModule)
	local encoded = EncoderModule.Encode(username, userId, payload)
	return ByteCodeFile.Save(userId, encoded)
end

--[[
	ByteCodeFile.LoadPayload(userId, InterpreterModule)
	Convenience: loads and decodes in one call.
	Returns username, userId, payload  or  nil, errorString
	InterpreterModule = require(path.ByteCodeInterpreter)
]]
function ByteCodeFile.LoadPayload(userId, InterpreterModule)
	local raw, err = ByteCodeFile.Load(userId)
	if not raw then return nil, err end
	return InterpreterModule.Decode(raw)
end

return ByteCodeFile


-- 
--  FULL USAGE EXAMPLE
-- 
--[[

local Players     = game:GetService("Players")
local player      = Players.LocalPlayer

local Encoder     = require(script.Parent.ByteCodeEncoder)
local Interpreter = require(script.Parent.ByteCodeInterpreter)
local File        = require(script.Parent.ByteCodeFile)

local username = player.Name
local userId   = player.UserId

--  SAVING 
local coins = 500
local gems  = 12
local level = 7

local ok, err = File.SavePayload(username, userId, {coins, gems, level}, Encoder)
if ok then
    print("Saved successfully!")
else
    warn("Save failed:", err)
end

--  LOADING 
if File.Exists(userId) then
    local name, id, data, err2 = File.LoadPayload(userId, Interpreter)

    if name then
        -- Verify it belongs to this player (anti-tamper)
        if name ~= username or id ~= userId then
            warn("Save file does not belong to this player! Possible tampering.")
        else
            print("Loaded save for:", name, "| ID:", id)
            print("Coins:", data[1])   -- 500
            print("Gems: ", data[2])   -- 12
            print("Level:", data[3])   -- 7
        end
    else
        warn("Load failed:", err2)
    end
else
    print("No save file found - starting fresh")
end

--  PAYLOAD KEY 
-- payload is an ordered array. Define your own constants for readability:
--
-- local SAVE = { COINS = 1, GEMS = 2, LEVEL = 3, XP = 4, WINS = 5 }
--
-- local coins = data[SAVE.COINS]
-- local gems  = data[SAVE.GEMS]

]]
