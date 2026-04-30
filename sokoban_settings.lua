local Blitbuffer  = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device      = require("device")
local Font        = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom        = require("ui/geometry")
local InputContainer  = require("ui/widget/container/inputcontainer")
local Size        = require("ui/size")
local TitleBar    = require("ui/widget/titlebar")
local UIManager   = require("ui/uimanager")
local VerticalGroup  = require("ui/widget/verticalgroup")
local VerticalSpan   = require("ui/widget/verticalspan")
local Screen      = Device.screen
local _           = require("gettext")

local SettingsWidget = InputContainer:extend{
    level_sets   = nil,   -- list of {name, count}
    current_set  = nil,
    current_level = nil,
    on_play_cb   = nil,   -- called with (set_index, level_num)
    width        = nil,
    height       = nil,
}

function SettingsWidget:init()
    self.width  = self.width  or math.floor(Screen:getWidth()  * 0.85)
    self.height = self.height or math.floor(Screen:getHeight() * 0.75)

    local title_bar = TitleBar:new{
        width         = self.width,
        title         = _("Level Select"),
        close_callback = function() self:onClose() end,
    }

    -- level-set selector: one row per set, bold when selected
    local set_buttons = {}
    for i, ls in ipairs(self.level_sets) do
        local is_selected = (ls.name == self.current_set)
        set_buttons[i] = {
            {
                text     = ls.name .. " (" .. ls.count .. ")",
                bold     = is_selected,
                callback = function()
                    if self.current_set ~= ls.name then
                        self.current_set   = ls.name
                        self.current_level = 1
                        self:_refresh()
                    end
                end,
            },
        }
    end

    -- level navigation: ◀  N / total  ▶
    local total = 1
    for _, ls in ipairs(self.level_sets) do
        if ls.name == self.current_set then total = ls.count; break end
    end

    local level_nav = ButtonTable:new{
        width   = self.width - Size.padding.large * 2,
        buttons = {
            {
                {
                    text = "◀",
                    callback = function()
                        if self.current_level > 1 then
                            self.current_level = self.current_level - 1
                            self:_refresh()
                        end
                    end,
                },
                {
                    text = tostring(self.current_level) .. " / " .. tostring(total),
                    callback = function() end,
                },
                {
                    text = "▶",
                    callback = function()
                        if self.current_level < total then
                            self.current_level = self.current_level + 1
                            self:_refresh()
                        end
                    end,
                },
            },
        },
    }

    local set_table = ButtonTable:new{
        width   = self.width - Size.padding.large * 2,
        buttons = set_buttons,
    }

    local play_btn = ButtonTable:new{
        width   = self.width - Size.padding.large * 2,
        buttons = {
            {
                {
                    text     = _("Play"),
                    callback = function()
                        local set_idx = 1
                        for i, ls in ipairs(self.level_sets) do
                            if ls.name == self.current_set then set_idx = i; break end
                        end
                        UIManager:close(self)
                        if self.on_play_cb then
                            self.on_play_cb(set_idx, self.current_level)
                        end
                    end,
                },
            },
        },
    }

    local content = VerticalGroup:new{
        align = "center",
        title_bar,
        VerticalSpan:new{ width = Size.padding.large },
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = set_table:getSize().h },
            set_table,
        },
        VerticalSpan:new{ width = Size.padding.large },
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = level_nav:getSize().h },
            level_nav,
        },
        VerticalSpan:new{ width = Size.padding.large },
        CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = play_btn:getSize().h },
            play_btn,
        },
    }

    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() },
        FrameContainer:new{
            width      = self.width,
            background = Blitbuffer.COLOR_WHITE,
            radius     = Size.radius.window,
            bordersize = Size.border.window,
            padding    = Size.padding.large,
            content,
        },
    }

    self.dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() }
end

function SettingsWidget:_refresh()
    UIManager:close(self)
    UIManager:show(SettingsWidget:new{
        level_sets    = self.level_sets,
        current_set   = self.current_set,
        current_level = self.current_level,
        on_play_cb    = self.on_play_cb,
        width         = self.width,
        height        = self.height,
    })
end

function SettingsWidget:onShow()
    UIManager:setDirty(self, "ui")
end

function SettingsWidget:onCloseWidget()
    UIManager:setDirty(nil, "ui")
end

function SettingsWidget:onClose()
    UIManager:close(self)
end

function SettingsWidget:onTapClose()
    self:onClose()
    return true
end

return SettingsWidget
