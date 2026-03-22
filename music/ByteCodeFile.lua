-- ByteCodeFile
-- Handles saving and loading encoded bytecode to/from local filesystem.
-- Files saved to: bcsaves/<userId>.bc

local ByteCodeFile = {}

local SAVE_DIR = "bcsaves"
local FILE_EXT = ".bc"

local function getPath(userId)
    return SAVE_DIR .. "/" .. tostring(userId) .. FILE_EXT
end

local function fsOk()
    return type(readfile) == "function"
        and type(writefile) == "function"
        and type(isfile) == "function"
end

local function ensureDir()
    if type(makefolder) == "function" then
        pcall(function()
            if type(isfolder) == "function" and not isfolder(SAVE_DIR) then
                makefolder(SAVE_DIR)
            end
        end)
    end
end

function ByteCodeFile.Save(userId, encodedString)
    if not fsOk() then return false, "filesystem not available" end
    ensureDir()
    local ok, err = pcall(function()
        writefile(getPath(userId), encodedString)
    end)
    if not ok then return false, tostring(err) end
    return true
end

function ByteCodeFile.Load(userId)
    if not fsOk() then return nil, "filesystem not available" end
    local path = getPath(userId)
    if not isfile(path) then return nil, "no save file" end
    local ok, result = pcall(function() return readfile(path) end)
    if not ok or type(result) ~= "string" then return nil, "readfile failed" end
    return result
end

function ByteCodeFile.Exists(userId)
    if not fsOk() then return false end
    local ok, result = pcall(function() return isfile(getPath(userId)) end)
    return ok and result == true
end

function ByteCodeFile.Delete(userId)
    if not fsOk() then return false end
    pcall(function()
        if isfile(getPath(userId)) then delfile(getPath(userId)) end
    end)
    return true
end

function ByteCodeFile.SavePayload(username, userId, payload, EncoderModule)
    local encoded = EncoderModule.Encode(username, userId, payload)
    return ByteCodeFile.Save(userId, encoded)
end

function ByteCodeFile.LoadPayload(userId, InterpreterModule)
    local raw, err = ByteCodeFile.Load(userId)
    if not raw then return nil, err end
    return InterpreterModule.Decode(raw)
end

return ByteCodeFile
