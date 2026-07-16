-- =============================================================================
-- NanoWM Pass Integration
-- hs.chooser interface for the pass password manager
-- =============================================================================

local M = {}

local HOME      = os.getenv("HOME") or ""
local clipTimer = nil  -- held at module level to survive GC

local function storeDir()
    local env = os.getenv("PASSWORD_STORE_DIR")
    if env and env ~= "" then return env end
    local attr = hs.fs.attributes(HOME .. "/.password-store")
    if attr and attr.mode == "directory" then
        return HOME .. "/.password-store"
    end
    return HOME .. "/configs/nixos-configs/secrets/passwords"
end

local function listEntries(dir)
    local entries = {}
    local output = hs.execute(string.format(
        '/usr/bin/find -L %q -name "*.gpg" -type f 2>/dev/null | /usr/bin/sort', dir))
    if not output or output == "" then return entries end
    for line in output:gmatch("[^\n]+") do
        local entry = line:sub(#dir + 2, -5)
        if entry ~= "" then
            table.insert(entries, entry)
        end
    end
    return entries
end

local function buildEntryChoices(entries)
    local choices = {}
    for _, entry in ipairs(entries) do
        local dir, name = entry:match("^(.*)/([^/]+)$")
        table.insert(choices, {
            text    = name or entry,
            subText = dir or "",
            entry   = entry,
        })
    end
    return choices
end

local function passEnv()
    local user = os.getenv("USER") or ""
    local paths = table.concat({
        "/etc/profiles/per-user/" .. user .. "/bin",  -- nix-darwin home-manager packages
        HOME .. "/.nix-profile/bin",
        "/run/current-system/sw/bin",
        "/nix/var/nix/profiles/default/bin",
        "/opt/homebrew/bin",
    }, ":")
    return string.format('export PATH=%s:$PATH; PASSWORD_STORE_DIR=%q', paths, storeDir())
end

-- Ensure .gpg-id exists; if not, prompt the user to run pass init first
local function ensureGpgId(callback)
    local dir = storeDir()
    local f = io.open(dir .. "/.gpg-id", "r")
    if f then f:close(); callback(); return end

    hs.focus()
    local b, keyId = hs.dialog.textPrompt(
        "Initialize Password Store",
        "No .gpg-id found. Enter your GPG key ID or email\n(run `gpg --list-keys` to find it):",
        "", "Initialize", "Cancel")
    if b ~= "Initialize" or keyId == "" then return end

    local cmd = string.format('%s %s init %q', passEnv(), "pass", keyId)
    hs.task.new("/bin/zsh", function(exitCode, _, stdErr)
        if exitCode ~= 0 then
            hs.alert.show("pass init failed:\n" .. (stdErr or ""), 4)
            return
        end
        hs.alert.show("Store initialized with: " .. keyId, 2)
        callback()
    end, { "-c", cmd }):start()
end

local function runPass(entry, callback)
    local cmd = string.format('%s %s show %q', passEnv(), "pass", entry)
    hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
        if exitCode ~= 0 then
            hs.alert.show("pass: failed — " .. (stdErr or ""), 3)
            return
        end
        local password = stdOut:match("([^\n]+)")
        if not password or password == "" then
            hs.alert.show("pass: empty entry")
            return
        end
        callback(password, entry)
    end, { "-c", cmd }):start()
end

local function clipAndClear(password, label)
    -- Write password then mark as concealed so Raycast/Maccy skip recording it
    hs.pasteboard.clearContents()
    hs.pasteboard.writeObjects(password)
    hs.pasteboard.writeDataForUTI("org.nspasteboard.ConcealedType", "", true)
    hs.alert.show("Copied: " .. label, 1.5)
    if clipTimer then clipTimer:stop() end
    clipTimer = hs.timer.doAfter(45, function()
        if hs.pasteboard.getContents() == password then
            hs.pasteboard.setContents("")
            hs.alert.show("pass: clipboard cleared", 1)
        end
        clipTimer = nil
    end)
end

-- Copy the first line to clipboard, auto-clear after 45 s
function M.copyPassword(entry)
    runPass(entry, function(password, name)
        clipAndClear(password, name)
    end)
end

-- Type the first line directly into the focused window
function M.typePassword(entry)
    runPass(entry, function(password)
        hs.timer.doAfter(0.1, function()
            hs.eventtap.keyStrokes(password)
        end)
    end)
end

-- Generate a new random password and save it to the store
function M.generatePassword()
    ensureGpgId(function()
        hs.focus()
        local b1, entryName = hs.dialog.textPrompt(
            "Generate Password", "Entry path (e.g. github/username):", "", "Next", "Cancel")
        if b1 ~= "Next" or entryName == "" then return end

        hs.focus()
        local b2, lengthStr = hs.dialog.textPrompt(
            "Generate Password", "Length:", "20", "Generate", "Cancel")
        if b2 ~= "Generate" then return end

        local length = math.max(8, math.min(tonumber(lengthStr) or 20, 128))
        local cmd = string.format('%s %s generate --force %q %d', passEnv(), "pass", entryName, length)

        hs.task.new("/bin/zsh", function(exitCode, _, stdErr)
            if exitCode ~= 0 then
                hs.alert.show("pass generate failed:\n" .. (stdErr or ""), 4)
                return
            end
            runPass(entryName, function(password, name)
                clipAndClear(password, name .. " (generated)")
            end)
        end, { "-c", cmd }):start()
    end)
end

-- Copy the current TOTP code for an OTP entry
function M.copyOtp(entry)
    local cmd = string.format('%s pass otp %q', passEnv(), entry)
    hs.task.new("/bin/zsh", function(exitCode, stdOut, stdErr)
        if exitCode ~= 0 then
            hs.alert.show("pass otp failed:\n" .. (stdErr or ""), 3)
            return
        end
        local code = stdOut:match("([^\n]+)")
        if not code or code == "" then
            hs.alert.show("pass otp: no code returned")
            return
        end
        clipAndClear(code, entry .. " (OTP)")
    end, { "-c", cmd }):start()
end

-- Remove a password from the store (with confirmation)
function M.removePassword(entry)
    hs.focus()
    local b = hs.dialog.blockAlert(
        "Remove Password",
        "Delete '" .. entry .. "' from the store?\nThis cannot be undone.",
        "Remove", "Cancel")
    if b ~= "Remove" then return end

    local cmd = string.format('%s %s rm --force %q', passEnv(), "pass", entry)
    hs.task.new("/bin/zsh", function(exitCode, _, stdErr)
        if exitCode ~= 0 then
            hs.alert.show("pass rm failed:\n" .. (stdErr or ""), 4)
            return
        end
        hs.alert.show("Removed: " .. entry, 2)
    end, { "-c", cmd }):start()
end

-- Add a password manually (entry path + password typed in a dialog)
function M.addPassword()
    ensureGpgId(function()
        hs.focus()
        local b1, entryName = hs.dialog.textPrompt(
            "Add Password", "Entry path (e.g. github/username):", "", "Next", "Cancel")
        if b1 ~= "Next" or entryName == "" then return end

        hs.focus()
        local b2, password = hs.dialog.textPrompt(
            "Add Password", "Password:", "", "Save", "Cancel")
        if b2 ~= "Save" or password == "" then return end

        -- Write to a temp file so the password never appears in the shell command
        local tmpFile = os.tmpname()
        local f = io.open(tmpFile, "w")
        if not f then
            hs.alert.show("pass: could not create temp file")
            return
        end
        f:write(password .. "\n")
        f:close()

        local cmd = string.format(
            '%s %s insert --echo --force %q < %q; rm -f %q',
            passEnv(), "pass", entryName, tmpFile, tmpFile)

        hs.task.new("/bin/zsh", function(exitCode, _, stdErr)
            if exitCode ~= 0 then
                hs.alert.show("pass insert failed:\n" .. (stdErr or ""), 4)
                os.remove(tmpFile)
                return
            end
            hs.alert.show("Saved: " .. entryName, 2)
        end, { "-c", cmd }):start()
    end)
end

function M.showChooser()
    local dir = storeDir()
    local attr = hs.fs.attributes(dir)
    if not attr or attr.mode ~= "directory" then
        hs.alert.show("pass: store not found:\n" .. dir)
        return
    end

    local entries = listEntries(dir)
    local entryChoices = buildEntryChoices(entries)

    -- Action chooser shown after an entry is picked
    local actionChooser = hs.chooser.new(function(choice)
        if not choice then return end
        if choice.action == "copy" then
            M.copyPassword(choice.entry)
        elseif choice.action == "type" then
            M.typePassword(choice.entry)
        elseif choice.action == "otp" then
            M.copyOtp(choice.entry)
        elseif choice.action == "remove" then
            M.removePassword(choice.entry)
        end
    end)
    actionChooser:width(30)
    actionChooser:bgDark(true)
    actionChooser:fgColor({ hex = "#FFFFFF" })
    actionChooser:subTextColor({ hex = "#AAAAAA" })

    -- Main chooser: actions at top, then existing entries
    local choices = {
        { text = "Generate new password", subText = "Create and save a random password", entry = "__generate__" },
        { text = "Add password manually",  subText = "Type a password to save",           entry = "__add__"      },
    }
    for _, c in ipairs(entryChoices) do
        table.insert(choices, c)
    end

    local entryChooser = hs.chooser.new(function(choice)
        if not choice then return end
        if choice.entry == "__generate__" then
            M.generatePassword()
        elseif choice.entry == "__add__" then
            M.addPassword()
        else
            actionChooser:choices({
                { text = "Copy to clipboard", subText = choice.entry, action = "copy",   entry = choice.entry },
                { text = "Copy OTP code",     subText = choice.entry, action = "otp",    entry = choice.entry },
                { text = "Type into window",  subText = choice.entry, action = "type",   entry = choice.entry },
                { text = "Remove from store", subText = choice.entry, action = "remove", entry = choice.entry },
            })
            actionChooser:placeholderText("Action for: " .. choice.entry)
            actionChooser:show()
        end
    end)
    entryChooser:width(40)
    entryChooser:bgDark(true)
    entryChooser:fgColor({ hex = "#FFFFFF" })
    entryChooser:subTextColor({ hex = "#AAAAAA" })
    entryChooser:choices(choices)
    entryChooser:placeholderText("pass: select entry or action...")
    entryChooser:searchSubText(true)
    entryChooser:show()
end

return M
