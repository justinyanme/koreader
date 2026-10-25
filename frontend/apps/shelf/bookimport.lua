--[[--
Books coming into the home folder from outside on a sandboxed device (iOS, Q10): from the system's document
picker, "Open with", and what the system left in its inboxes. Each comes as a copy the app owns, so it is moved
into the home folder and nothing refers to where it came from. A name that is taken is never overwritten: the
same book (size and partial checksum) is kept as it is and the copy dropped; a different one is saved as
"Name (2).epub", and the report says so.
]]

local Device = require("device")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local T = ffiUtil.template
local _ = require("gettext")
local N_ = _.ngettext

local BookImport = {
    moved = {}, -- source path -> where it went, for an "Open with" event arriving after its file was swept
    poll_interval = 0.2,
}

local function notDownloaded()
    return _("It isn't downloaded to this device. Download it in the Files app, then try again.")
end

local function sameBook(a, b)
    return lfs.attributes(a, "size") == lfs.attributes(b, "size") and util.partialMD5(a) == util.partialMD5(b)
end

-- The first "Name (n).ext" that is free in `dir`.
local function freeName(dir, name)
    local base, suffix = util.splitFileNameSuffix(name)
    suffix = suffix ~= "" and "." .. suffix or ""
    local n = 2
    while lfs.attributes(string.format("%s/%s (%d)%s", dir, base, n, suffix), "mode") do
        n = n + 1
    end
    return string.format("%s (%d)%s", base, n, suffix)
end

local function moveFile(src, dest)
    if os.rename(src, dest) then return true end
    local err = ffiUtil.copyFile(src, dest)
    if err then
        os.remove(dest)
        return nil, err
    end
    os.remove(src)
    return true
end

--- Moves the file `src` into the folder `home`. Returns { name, status, dest, reason }: status is "imported",
-- "renamed" (dest has another name), "duplicate" (dest is the book already there) or "failed" (with reason).
function BookImport.receive(src, home)
    local name = ffiUtil.basename(src)
    local result = { name = name }
    local function fail(reason)
        result.status, result.reason = "failed", reason
        logger.warn("BookImport:", src, reason)
        return result
    end
    -- what an iCloud file not on the device leaves behind: ".Name.epub.icloud"
    local placeholder = name:match("^%.(.+)%.icloud$")
    if placeholder then
        result.name = placeholder
        return fail(notDownloaded())
    end
    if lfs.attributes(src, "mode") ~= "file" then
        return fail(notDownloaded())
    end
    if not DocumentRegistry:hasProvider(src) then
        os.remove(src)
        return fail(_("This type of file can't be opened."))
    end
    local dest = home .. "/" .. name
    result.status = "imported"
    if lfs.attributes(dest, "mode") then
        if ffiUtil.realpath(src) == ffiUtil.realpath(dest) then -- it is that book: never remove it
            result.status, result.dest = "duplicate", dest
            return result
        end
        if sameBook(src, dest) then
            os.remove(src)
            result.status, result.dest = "duplicate", dest
            BookImport.moved[src] = dest
            return result
        end
        dest = home .. "/" .. freeName(home, name)
        result.status = "renamed"
    end
    local ok, err = moveFile(src, dest)
    if not ok then return fail(err) end
    result.dest = dest
    BookImport.moved[src] = dest
    return result
end

--- Moves every file in the folders `inboxes` into `home`; empty inboxes are removed (Documents/Inbox would
-- show in Files). Returns the results.
function BookImport.sweep(inboxes, home)
    local results = {}
    for __, dir in ipairs(inboxes) do
        if lfs.attributes(dir, "mode") == "directory" then
            local files = {}
            for name in lfs.dir(dir) do
                local path = dir .. "/" .. name
                if lfs.attributes(path, "mode") == "file" then table.insert(files, path) end
            end
            for __, path in ipairs(files) do
                table.insert(results, BookImport.receive(path, home))
            end
            lfs.rmdir(dir) -- only if empty
        end
    end
    return results
end

--- Tells what came of `results`: a notification when all went in plainly, a message otherwise.
function BookImport.report(results)
    local imported, lines = 0, {}
    for __, result in ipairs(results) do
        if result.status == "imported" then
            imported = imported + 1
        elseif result.status == "renamed" then
            imported = imported + 1
            table.insert(lines, T(_("A different book named %1 is already here, so this one was saved as %2."),
                result.name, ffiUtil.basename(result.dest)))
        elseif result.status == "duplicate" then
            table.insert(lines, T(_("%1 is already here."), result.name))
        else
            table.insert(lines, T(_("Could not import %1: %2"), result.name, result.reason))
        end
    end
    if #lines == 0 then
        if imported > 0 then
            UIManager:show(Notification:new{ text = T(N_("Imported 1 book", "Imported %1 books", imported), imported) })
        end
        return
    end
    if imported > 0 then
        table.insert(lines, 1, T(N_("Imported 1 book.", "Imported %1 books.", imported), imported))
    end
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n\n") })
end

--- The extensions that can be opened, for the document picker.
function BookImport.extensions()
    local extensions = {}
    for extension in pairs(DocumentRegistry.filetype_provider) do
        table.insert(extensions, extension)
    end
    table.sort(extensions)
    return extensions
end

local function finish(results)
    BookImport.report(results)
    for __, result in ipairs(results) do
        if result.dest then
            UIManager:broadcastEvent(Event:new("BooksImported"))
            return
        end
    end
end

--- Shows the system document picker (copies, ADR-0009 polling) and moves what is picked into `folder`.
function BookImport.pick(folder)
    local bridge = Device.bridge
    local ok, err = bridge.pickFilesStart{ extensions = BookImport.extensions() }
    if not ok then
        UIManager:show(InfoMessage:new{ text = T(_("Could not show the file picker: %1"), err) })
        return
    end
    local function poll()
        local snapshot, poll_err = bridge.pickFilesPoll()
        if not snapshot then
            snapshot = { state = "failed", error = poll_err }
        end
        if snapshot.state == "pending" then
            UIManager:scheduleIn(BookImport.poll_interval, poll)
        elseif snapshot.state == "picked" then
            local results = {}
            for __, path in ipairs(snapshot.paths or {}) do
                table.insert(results, BookImport.receive(path, folder))
            end
            for name, reason in pairs(snapshot.errors or {}) do
                table.insert(results, { name = name, status = "failed",
                    reason = reason == "not_downloaded" and notDownloaded() or reason })
            end
            finish(results)
        elseif snapshot.state == "failed" then
            UIManager:show(InfoMessage:new{ text = T(_("Could not import: %1"), snapshot.error or "") })
        end -- cancelled: nothing to say
    end
    UIManager:scheduleIn(BookImport.poll_interval, poll)
end

--- "Open with" (SDL's drop event): the system's copy goes into `home`, and the book opens.
function BookImport.open(src, home)
    local dest, notice
    local real, real_home = ffiUtil.realpath(src), ffiUtil.realpath(home) or home
    if real and real:sub(1, #real_home + 1) == real_home .. "/" and not real:find("/Inbox/", #real_home, true) then
        -- one of the app's own books: the system hands those over as they are, not as a copy
        dest = real
    elseif lfs.attributes(src, "mode") ~= "file" and not src:match("%.icloud$") then
        dest = BookImport.moved[src] -- swept in before its event came
        if not dest then
            logger.warn("BookImport: dropped path is gone", src) -- not a file URL
            return
        end
    else
        local result = BookImport.receive(src, home)
        local inbox = ffiUtil.dirname(src)
        if inbox:match("Inbox$") then lfs.rmdir(inbox) end -- once empty: Documents/Inbox would show in Files
        dest = result.dest
        if not dest then
            BookImport.report{ result }
            return
        end
        if result.status == "renamed" then notice = result end
    end
    require("apps/reader/readerui"):doShowReader(dest)
    if notice then
        UIManager:nextTick(function() BookImport.report{ notice } end) -- over the book
    end
end

return BookImport
