describe("iOS memory awareness (C9)", function()
    local MiB = 1024 * 1024
    local SDLDevice, FakeBridge, util

    setup(function()
        require("commonrequire")
        SDLDevice = require("device/sdl/device")
        FakeBridge = require("iosbridge")
        util = require("util")
    end)

    describe("IOS:freeMemory()", function()
        it("reports 85% of the native headroom and no total", function()
            local device = SDLDevice:createVariant{
                platform = "iOS", native_bridge = FakeBridge.new{ memory_available = 4000 * MiB },
            }
            local free, total = device:freeMemory()
            assert.are.equal(math.floor(4000 * MiB * 0.85), free)
            assert.is_nil(total)
        end)

        it("reports nothing when the bridge can't tell", function()
            local device = SDLDevice:createVariant{
                platform = "iOS", native_bridge = require("device/sdl/iosbridge").new(),
            }
            assert.is_nil(device:freeMemory())
        end)
    end)

    describe("util.calcFreeMem()", function()
        local orig_open

        before_each(function()
            orig_open = io.open
        end)

        after_each(function()
            io.open = orig_open
            util.freeMemProvider = nil
        end)

        local function withoutMeminfo()
            io.open = function(path, ...)
                if path == "/proc/meminfo" then return nil, "No such file or directory" end
                return orig_open(path, ...)
            end
        end

        it("uses the device's provider without /proc/meminfo", function()
            withoutMeminfo()
            util.freeMemProvider = function() return 1234, nil end
            local free, total = util.calcFreeMem()
            assert.are.equal(1234, free)
            assert.is_nil(total)
        end)

        it("still reports nothing without /proc/meminfo or a provider", function()
            withoutMeminfo()
            local free, total = util.calcFreeMem()
            assert.is_nil(free)
            assert.is_nil(total)
        end)

        it("ignores the provider where /proc/meminfo exists", function()
            if not orig_open("/proc/meminfo", "r") then return end -- Linux only
            local expected_free, expected_total = util.calcFreeMem()
            util.freeMemProvider = function() return 1234, nil end
            local free, total = util.calcFreeMem()
            assert.is_true(free ~= 1234)
            assert.are.equal(expected_total, total)
            assert.is_true(math.abs(free - expected_free) < 256 * MiB) -- meminfo moves between reads
        end)
    end)

    describe("DocCache capacity", function()
        local orig_doccache, orig_calc

        before_each(function()
            orig_doccache = package.loaded["document/doccache"]
            orig_calc = util.calcFreeMem
        end)

        after_each(function()
            util.calcFreeMem = orig_calc
            package.loaded["document/doccache"] = orig_doccache
        end)

        local function sizeFor(free)
            util.calcFreeMem = function() return free, nil end
            package.loaded["document/doccache"] = nil
            return require("document/doccache").size
        end

        it("takes 40% of the free memory", function()
            assert.are.equal(400 * MiB, sizeFor(1000 * MiB))
        end)

        it("is capped at 512MB", function()
            assert.are.equal(512 * MiB, sizeFor(math.floor(4000 * MiB * 0.85)))
        end)

        it("falls back to the 16MB minimum without memory figures", function()
            assert.are.equal(16 * MiB, sizeFor(nil))
            assert.are.equal(16 * MiB, sizeFor(10 * MiB))
        end)
    end)
end)
