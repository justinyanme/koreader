describe("Exporter plugin module", function()
    local readerui
    local sample_clippings, sample_epub
    local DocumentRegistry, Screen
    setup(function()
        require("commonrequire")
        disable_plugins()
        load_plugin("exporter.koplugin")
        local ReaderUI = require("apps/reader/readerui")
        DocumentRegistry = require("document/documentregistry")
        Screen = require("device").screen
        sample_epub = "spec/front/unit/data/juliet.epub"
        readerui = ReaderUI:new {
                dimen = Screen:getSize(),
                document = DocumentRegistry:openDocument(sample_epub),
            }

        sample_clippings = {
            ["Title1"] = {
                [1] = {
                    [1] = {
                        ["page"] = 6,
                        ["time"] = 1578946897,
                        ["sort"] = "highlight",
                        ["text"] = "Some important stuff 1",
                        ["drawer"] = "lighten"
                    }
                },
                [2] = {
                    [1] = {
                        ["page"] = 13,
                        ["time"] = 1578946903,
                        ["sort"] = "highlight",
                        ["text"] = "Some important stuff 2",
                        ["drawer"] = "lighten"
                    }
                },
                ["file"] = "path/to/title1",
                ["exported"] = {
                    ["txt"] = true,
                    ["html"] = true,
                },
                ["title"] = "Title1"
            },
            ["Title2"] = {
                [1] = {
                    [1] = {
                        ["page"] = 233,
                        ["time"] = 1578946918,
                        ["sort"] = "highlight",
                        ["text"] = "Some important stuff 3",
                        ["drawer"] = "lighten"
                    }
                },
                [2] = {
                    [1] = {
                        ["page"] = 237,
                        ["time"] = 1578947501,
                        ["sort"] = "highlight",
                        ["text"] = "",
                        ["drawer"] = "lighten",
                        ["image"] = {
                            ["hash"] = "cb7b40a63afc89f0aa452f2b655877e6",
                            ["png"] = "Binary Encoding of image"
                        },
                    }
                },
                ["file"] = "path/to/title2",
                ["exported"] = {
            },
                ["title"] = "Title2"
            },
        }

    end)
    teardown(function()
        readerui:onClose()
    end)

    it("should write clippings to a timestamped txt file", function()
        readerui.exporter.targets["text"].filepath = readerui.exporter.targets["text"]:getTimeStamp()
        local exportable = { sample_clippings.Title1 }
        local file_path = readerui.exporter.targets["text"]:getFilePath()
        readerui.exporter.targets["text"]:export(exportable)
        local f = io.open(file_path, "r")
        assert.is.truthy(string.find(f:read("*all"), "Some important stuff 1"))
        f:close()
        os.remove(file_path)
    end)

    it("should fail to export to non configured targets", function()
        local ok = readerui.exporter.targets["joplin"]:export(sample_clippings)
        assert.not_truthy(ok)
        ok = readerui.exporter.targets["readwise"]:export(sample_clippings)
        assert.not_truthy(ok)
    end)

    it("should share clippings as json", function()
        local rapidjson = require("rapidjson")
        local target = readerui.exporter.targets["json"]
        local original_share_text = target.shareText
        local shared_content
        target.shareText = function(_, content)
            shared_content = content
        end

        target:share(sample_clippings.Title1)

        target.shareText = original_share_text
        local decoded = rapidjson.decode(shared_content)
        assert.are.equal("Title1", decoded.title)
        assert.are.equal("Some important stuff 1", decoded.entries[1].text)
        assert.are.equal(2, #decoded.entries)
    end)

    describe("exporting notes", function()
        local Device, UIManager, util, saved_enabled, text, T, _

        local function exists(path)
            local f = io.open(path)
            if f then f:close() end
            return f ~= nil
        end

        local function runTasks()
            for _ = 1, 3 do UIManager:_checkTasks() end
        end

        local function closeMessages()
            for i = #UIManager._window_stack, 1, -1 do
                local widget = UIManager._window_stack[i].widget
                if widget.name ~= "ReaderUI" and widget ~= readerui then UIManager:close(widget) end
            end
        end

        before_each(function()
            Device = require("device")
            UIManager = require("ui/uimanager")
            util = require("util")
            T = require("ffi/util").template
            _ = require("gettext")
            saved_enabled = {}
            for name, target in pairs(readerui.exporter.targets) do
                saved_enabled[name] = target.settings.enabled
                target.settings.enabled = nil
            end
            text = readerui.exporter.targets.text
            text.settings.enabled = true
        end)

        after_each(function()
            for name, target in pairs(readerui.exporter.targets) do
                target.settings.enabled = saved_enabled[name]
            end
            closeMessages()
        end)

        it("keeps writing to the clippings folder where files cannot be shared", function()
            assert.is_false(Device:canShareFiles())
            readerui.exporter:exportClippings(util.tableDeepCopy(sample_clippings))
            runTasks()
            local path = text:getFilePath()
            local dir = readerui.exporter.settings.clipping_dir or readerui.exporter.default_clipping_dir
            assert.are.equal(dir .. "/", path:sub(1, #dir + 1))
            assert.is_true(exists(path))
            local reported = false
            for _, w in ipairs(UIManager._window_stack) do
                reported = reported or (w.widget.text or ""):find(path, 1, true) ~= nil
            end
            assert.is_true(reported)
            os.remove(path)
        end)

        describe("on the injected iOS device", function()
            local bridge, polls

            before_each(function()
                bridge = require("iosbridge").new()
                local ios = require("device/sdl/device"):createVariant{ platform = "iOS", native_bridge = bridge }
                stub(Device, "canShareFiles", ios.canShareFiles)
                Device.shareFiles = function(_self, paths, done) return ios:shareFiles(paths, done) end
                polls = {}
            end)

            after_each(function()
                Device.canShareFiles:revert()
                Device.shareFiles = nil
            end)

            -- Runs the export, capturing the share sheet's polls instead of waiting for them.
            local function export()
                readerui.exporter:exportClippings(util.tableDeepCopy(sample_clippings))
                stub(UIManager, "scheduleIn", function(_self, _seconds, task) table.insert(polls, task) end)
                local ok, err = pcall(runTasks)
                UIManager.scheduleIn:revert()
                assert(ok, err)
            end

            local function poll()
                stub(UIManager, "scheduleIn", function(_self, _seconds, task) table.insert(polls, task) end)
                local ok, err = pcall(table.remove(polls, 1))
                UIManager.scheduleIn:revert()
                assert(ok, err)
            end

            it("hands the export to the share sheet and leaves nothing behind when cancelled", function()
                export()
                assert.are.equal(1, #bridge.shared)
                local path = bridge.shared[1][1]
                local share_dir = require("datastorage"):getDataDir() .. "/cache/share/"
                assert.are.equal(share_dir, path:sub(1, #share_dir))
                assert.are.equal("txt", path:match("%.(%w+)$"))
                assert.is_true(exists(path))
                poll()
                assert.is_true(exists(path))
                bridge.finishShare("cancelled")
                poll()
                assert.is_false(exists(path))
                assert.are.equal(0, #polls)
            end)

            it("removes the export and says so when the share sheet cannot be presented", function()
                bridge.shareStart = function() return nil, "no window" end
                export()
                local path = text:getFilePath()
                assert.is_false(exists(path))
                assert.are.equal(0, #polls)
                local message = T(_("%1: Failed to export."), text.name)
                local reported = false
                for _i, w in ipairs(UIManager._window_stack) do
                    reported = reported or w.widget.text == message
                end
                assert.is_true(reported)
            end)

            it("clears files a killed app left in the share folder before exporting", function()
                local share_dir = require("datastorage"):getDataDir() .. "/cache/share"
                util.makePath(share_dir)
                local stale = share_dir .. "/stale.txt"
                local f = io.open(stale, "w")
                f:write("left behind")
                f:close()
                export()
                assert.is_false(exists(stale))
                bridge.finishShare("completed")
                poll()
            end)
        end)
    end)
end)
