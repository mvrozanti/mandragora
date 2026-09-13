local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local RandomBook = {
    roots = { "/mnt/us/documents/library", "/mnt/us/documents" },
    max_files = 4000,
}

local READABLE = {
    epub = true, mobi = true, azw = true, azw3 = true, pdf = true,
    txt = true, fb2 = true, cbz = true, djvu = true, chm = true,
}

local function isReadable(name)
    local ext = name:match("%.([%a%d]+)$")
    return ext and READABLE[ext:lower()] or false
end

function RandomBook.collect(root, limit)
    local found = {}
    local function scan(dir, depth)
        if #found >= limit or depth > 6 then return end
        local ok, iter, dir_obj = pcall(lfs.dir, dir)
        if not ok then return end
        for name in iter, dir_obj do
            if #found >= limit then return end
            if name ~= "." and name ~= ".." then
                local path = dir .. "/" .. name
                local attr = lfs.attributes(path)
                if attr and attr.mode == "directory" then
                    scan(path, depth + 1)
                elseif attr and attr.mode == "file" and isReadable(name) then
                    found[#found + 1] = path
                end
            end
        end
    end
    scan(root, 1)
    return found
end

function RandomBook.pick()
    for _, root in ipairs(RandomBook.roots) do
        if lfs.attributes(root, "mode") == "directory" then
            local files = RandomBook.collect(root, RandomBook.max_files)
            if #files > 0 then
                math.randomseed(os.time() + #files)
                return files[math.random(#files)], #files, root
            end
        end
    end
    return nil
end

function RandomBook.open()
    local path, total, root = RandomBook.pick()
    if not path then
        UIManager:show(InfoMessage:new{
            text = "no readable books under\n" .. table.concat(RandomBook.roots, "\n"),
            timeout = 4,
        })
        return
    end

    logger.info("mandragora: random:", path, "of", total, "under", root)
    local name = path:match("([^/]+)$") or path

    UIManager:show(ConfirmBox:new{
        text = name .. "\n\n(" .. total .. " books)",
        ok_text = "read",
        ok_callback = function()
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(path)
        end,
        cancel_text = "another",
        cancel_callback = function()
            RandomBook.open()
        end,
    })
end

return RandomBook
