-- Adapter-boundary diagnostics. Never reads credentials or records input URLs.
local M = {}
local sensitive = {
    accesstoken=true, refreshtoken=true, idtoken=true, clientsecret=true,
    password=true, authorization=true, apikey=true, privatekey=true, token=true,
    key=true, secret=true,
}

local function sensitiveKey(key)
    return sensitive[tostring(key):lower():gsub("[^%w]", "")] == true
end

function M.redact(text)
    text = tostring(text or "")
    local lines, privateKey = {}, false
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local lower = line:lower()
        if lower:find("begin .*private key") then privateKey = true end
        local credential = privateKey or lower:find("bearer%s+") or lower:find("ya29%.")
            -- An embedded JSON fragment can escape the credential field name.
            -- Without a complete parsed document, discard such a line safely.
            or lower:find("\\u%x%x%x%x")
            or line:find("AIza[%w_%-]+") or lower:find("client%s+secret")
            or lower:find("[?&]key=") or lower:find("[?&]code=")
            or lower:find("%f[%w]token[\"']?%s*[:=]")
            or lower:find("%f[%w]secret[\"']?%s*[:=]")
            or lower:find("%f[%w]key[\"']?%s*[:=]")
        for word in lower:gmatch("[%w_%-]+") do
            if word ~= "token" and word ~= "key" and word ~= "secret" and sensitiveKey(word) then credential = true end
        end
        lines[#lines + 1] = credential and "[REDACTED credential-bearing line]" or line
        if lower:find("end .*private key") then privateKey = false end
    end
    return table.concat(lines, "\n")
end

local function quote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end

function M.new(options)
    options = options or {}
    local h = options.hs or hs
    local directory = options.directory or (os.getenv("HOME") .. "/Library/Logs/youtube-org")
    local path = directory .. "/capture.log"
    local console = options.console or print
    local maxBytes = options.maxBytes or 2 * 1024 * 1024
    local log = {path=path}

    local function clean(value, depth)
        if depth > 32 then return "[REDACTED excessive nesting]" end
        if type(value) == "table" then
            local result = {}
            for key, item in pairs(value) do
                result[key] = sensitiveKey(key) and "[REDACTED]" or clean(item, depth + 1)
            end
            return result
        end
        if type(value) == "string" then
            -- Decode structured helper output before redacting so a credential
            -- field does not erase unrelated errors in the same JSON line.
            local object, array = value:match("^%s*{"), value:match("^%s*%[")
            if object or array then
                if not ((object and value:match("}%s*$")) or (array and value:match("%]%s*$"))) then
                    return "[REDACTED malformed JSON response]"
                end
                local ok, decoded = pcall(h.json.decode, value)
                if ok and type(decoded) == "table" then return h.json.encode(clean(decoded, depth + 1)) end
                return "[REDACTED malformed JSON response]"
            end
            return M.redact(value)
        end
        return value
    end

    local function safeTarget(target, mode)
        local info = h.fs.symlinkAttributes(target)
        if info and (info.mode ~= mode or (mode == "file" and info.nlink ~= 1)) then
            error("unsafe log destination")
        end
        return info
    end

    local function prepare()
        local dirInfo = safeTarget(directory, "directory")
        local fileInfo = safeTarget(path, "file")
        safeTarget(path .. ".1", "file")
        if dirInfo and dirInfo.permissions == "rwx------" and fileInfo and fileInfo.permissions == "rw-------" then return end
        -- Private directory first; umask protects a newly created log from its
        -- first byte. Paths are quoted and never contain helper output.
        local script = "umask 077\n/bin/mkdir -p " .. quote(directory)
            .. " || exit 1\n/bin/chmod 700 " .. quote(directory)
            .. " || exit 1\n: >> " .. quote(path)
            .. " || exit 1\n/bin/chmod 600 " .. quote(path)
        local _, ok = h.execute(script)
        if not ok then error("cannot prepare private log") end
        local info = safeTarget(path, "file")
        if not info or info.permissions ~= "rw-------"
            or h.fs.attributes(directory, "permissions") ~= "rwx------" then error("log is not private") end
    end

    function log.record(event, fields)
        local entry = clean(fields or {}, 0)
        entry.event, entry.time = event, os.date("!%Y-%m-%dT%H:%M:%SZ")
        local line = h.json.encode(entry)
        console("YouTube: " .. line)
        local ok = pcall(function()
            prepare()
            local size = h.fs.attributes(path, "size") or 0
            if size > 0 and size + #line + 1 > maxBytes then
                if h.fs.symlinkAttributes(path .. ".1") then assert(os.remove(path .. ".1")) end
                assert(os.rename(path, path .. ".1"))
                prepare()
            end
            local file = assert(io.open(path, "ab"))
            local written = file:write(line .. "\n")
            local closed = file:close()
            assert(written and closed)
        end)
        if not ok then console("YouTube: persistent logging unavailable; diagnostics above remain in Console") end
        return ok
    end
    return log
end

return M
