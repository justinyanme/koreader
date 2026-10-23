-- The full-screen page skeleton, through the hooks later pages build on (the shelf's tabs, the contents' 书签 pill).
describe("FullscreenPage", function()
    local EinkControls, Event, FullscreenPage, Geom, Key, UIManager, VerticalGroup, Screen

    setup(function()
        require("commonrequire")
        EinkControls = require("ui/widget/einkcontrols")
        Event = require("ui/event")
        FullscreenPage = require("ui/widget/fullscreenpage")
        Geom = require("ui/geometry")
        Key = require("device/key")
        UIManager = require("ui/uimanager")
        VerticalGroup = require("ui/widget/verticalgroup")
        Screen = require("device").screen
    end)

    -- A page of `count` empty pages whose bar has tabs in place of the back arrow and a pill before the capsule;
    -- `taps` records which of them was tapped, and in which build.
    local function newPage(fields)
        local Page = FullscreenPage:extend{}
        function Page:init()
            FullscreenPage.init(self)
            self.builds, self.taps = 0, {}
            self:build()
        end
        function Page:buildContent()
            self.page = math.max(1, math.min(self.page, self.count))
            return VerticalGroup:new{}, self.count
        end
        function Page:buildBarParts()
            self.builds = self.builds + 1
            local build = self.builds
            self.tabs = EinkControls.PillButton:new{ text = "Tabs",
                callback = function() table.insert(self.taps, "tabs " .. build) end }
            self.pill = EinkControls.PillButton:new{ text = "Bookmarks",
                callback = function() table.insert(self.taps, "pill " .. build) end }
            return self.tabs, { self.pill }
        end
        local page = Page:new(fields)
        UIManager:show(page, "ui", page.dimen)
        UIManager:forceRePaint()
        return page
    end

    local function tap(rect)
        UIManager:sendEvent(Event:new("Gesture", { ges = "tap",
            pos = Geom:new{ x = rect.x + math.floor(rect.w / 2), y = rect.y + math.floor(rect.h / 2), w = 0, h = 0 } }))
        UIManager:forceRePaint()
    end

    local function closeAll(page)
        if UIManager:isWidgetShown(page) then
            UIManager:close(page)
            UIManager:forceRePaint()
        end
    end

    it("puts the page's bar parts in the bar, built anew with the page", function()
        local page = newPage{ count = 2 }
        local bar, capsule = page.bar, page.bar.capsule
        -- the tabs replace the back arrow on the left; the pill sits 16dp before the capsule
        assert.is_nil(bar.back)
        assert.are.equal(0, page.tabs.dimen.x)
        assert.is_true(page.tabs.dimen.y > bar.dimen.y)
        assert.are.equal(capsule.dimen.x - Screen:scaleBySize(16), page.pill.dimen.x + page.pill.dimen.w)
        tap(page.pill.dimen)
        tap(page.tabs.dimen)
        assert.are.same({ "pill 1", "tabs 1" }, page.taps)
        -- a page turn rebuilds the bar with new parts, which answer in their place
        local old_pill = page.pill
        tap(capsule.next_rect)
        assert.are.equal(2, page.page)
        assert.are.equal(2, page.builds)
        assert.are_not.equal(old_pill, page.pill)
        tap(page.pill.dimen)
        tap(page.tabs.dimen)
        assert.are.same({ "pill 1", "tabs 1", "pill 2", "tabs 2" }, page.taps)
        closeAll(page)
    end)

    it("has no title band without a title, and a centered one with it", function()
        local page = newPage{ count = 1 }
        assert.are.equal(0, page.title_rect.h)
        assert.are.equal(0, page.content_rect.y)
        closeAll(page)
        page = newPage{ count = 1, title = "Notes" }
        assert.are.equal(FullscreenPage.TITLE_H, page.content_rect.y)
        assert.are.equal(page.content_rect.y, page.body_rect.y)
        assert.are.equal(Screen:getHeight(), page.bar.dimen.y + page.bar.dimen.h)
        closeAll(page)
    end)

    it("closes once, however often back is asked for", function()
        local page = newPage{ count = 1 }
        -- the default bar keeps the back arrow
        page.buildBarParts = FullscreenPage.buildBarParts
        page:build()
        UIManager:setDirty(page, "ui", page.body_rect)
        UIManager:forceRePaint()
        local back = page.bar.back
        assert.is_truthy(back)
        local closes = 0
        local orig = UIManager.close
        UIManager.close = function(self, widget, ...)
            if widget == page then closes = closes + 1 end
            return orig(self, widget, ...)
        end
        local ok, err = pcall(function()
            tap(back.dimen)
            -- a second tap that still reaches the arrow, and the Back key
            back:onTapSelect()
            page:handleEvent(Event:new("KeyPress", Key:new("Back", {})))
        end)
        UIManager.close = orig
        assert(ok, err)
        assert.are.equal(1, closes)
        assert.is_false(UIManager:isWidgetShown(page))
    end)
end)
