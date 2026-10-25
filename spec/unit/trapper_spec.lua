describe("Trapper subprocess fallback", function()
    local Device, Trapper, UIManager, ffiutil

    setup(function()
        require("commonrequire")
        Device = require("device")
        Trapper = require("ui/trapper")
        UIManager = require("ui/uimanager")
        ffiutil = require("ffi/util")
    end)

    before_each(function()
        stub(Device, "canForkProcesses", function() return false end)
        stub(ffiutil, "runInSubProcess", function() error("unexpected fork") end)
        stub(UIManager, "preventStandby")
        stub(UIManager, "allowStandby")
    end)

    after_each(function()
        Device.canForkProcesses:revert()
        ffiutil.runInSubProcess:revert()
        UIManager.preventStandby:revert()
        UIManager.allowStandby:revert()
    end)

    it("executes wrapped tasks in-process and preserves nils and multiple results", function()
        local result, calls = nil, 0
        local task = function()
            calls = calls + 1
            return "first", nil, false, { value = 42 }, nil
        end
        local resumed = Trapper:wrap(function()
            result = table.pack(Trapper:dismissableRunInSubprocess(task, "unused trap"))
        end)
        assert.is_true(resumed)
        assert.are.equal(1, calls)
        assert.are.same({ true, "first", nil, false, { value = 42 }, n = 6 }, result)
        assert.stub(ffiutil.runInSubProcess).was_not_called()
        assert.stub(UIManager.preventStandby).was_called(1)
        assert.stub(UIManager.allowStandby).was_called(1)
    end)

    it("retains the unwrapped fallback and simple-string return convention", function()
        local completed, result = Trapper:dismissableRunInSubprocess(function() return "text" end, nil, true)
        assert.is_true(completed)
        assert.are.equal("text", result)
        assert.stub(ffiutil.runInSubProcess).was_not_called()
    end)

    it("still attempts a subprocess for wrapped tasks on devices that can fork", function()
        Device.canForkProcesses:revert()
        stub(Device, "canForkProcesses", function() return true end)
        ffiutil.runInSubProcess:revert()
        stub(ffiutil, "runInSubProcess", function() return false end)
        local called = false
        Trapper:wrap(function()
            Trapper:dismissableRunInSubprocess(function() called = true end, {})
        end)
        assert.is_false(called)
        assert.stub(ffiutil.runInSubProcess).was_called(1)
    end)
end)
