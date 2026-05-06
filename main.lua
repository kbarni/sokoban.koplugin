local Blitbuffer      = require("ffi/blitbuffer")
local ConfirmBox      = require("ui/widget/confirmbox")
local DataStorage     = require("datastorage")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LuaSettings     = require("luasettings")
local Size            = require("ui/size")
local TextWidget      = require("ui/widget/textwidget")
local TitleBar        = require("ui/widget/titlebar")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen          = Device.screen
local _               = require("gettext")

local IconButton     = require("ui/widget/iconbutton")
local Board          = require("sokoban_board")
local Game           = require("sokoban_game")
local SettingsWidget = require("sokoban_settings")

local LEVEL_SETS = {
    require("levels/microban"),
    require("levels/minicosmos"),
    require("levels/microcosmos"),
    require("levels/original-plus-extra"),
    require("levels/sasquatch"),
}

local Sokoban = WidgetContainer:extend{
    name        = "sokoban",
    is_doc_only = false,
    -- set by pluginloader
    path        = nil,
}

function Sokoban:init()
    self.ui.menu:registerToMainMenu(self)
    self.settings_file = DataStorage:getSettingsDir() .. "/sokoban.lua"
end

function Sokoban:_loadSettings()
    if not self.settings then
        self.settings = LuaSettings:open(self.settings_file)
    end
    self.current_set      = self.settings:readSetting("current_set")      or LEVEL_SETS[1].name
    self.current_level    = self.settings:readSetting("current_level")    or 1
    self.last_played_levels = self.settings:readSetting("last_played_levels") or {}
    self.best_moves       = self.settings:readSetting("best_moves")       or {}
    self.best_pushes      = self.settings:readSetting("best_pushes")      or {}
    self.furthest_reached = self.settings:readSetting("furthest_reached") or {}
    -- Ensure furthest_reached is at least consistent with best_moves (handles missing
    -- or stale data from sessions before progression tracking was added)
    for _, ls in ipairs(LEVEL_SETS) do
        local bm = self.best_moves[ls.name] or {}
        local max_solved = 0
        for level_num in pairs(bm) do
            if type(level_num) == "number" and level_num > max_solved then
                max_solved = level_num
            end
        end
        if max_solved > 0 then
            local min_fr = math.min(max_solved + 1, #ls.levels)
            if (self.furthest_reached[ls.name] or 0) < min_fr then
                self.furthest_reached[ls.name] = min_fr
            end
        end
    end
end

function Sokoban:_saveSettings()
    if not self.settings then return end
    self.settings:saveSetting("current_set",      self.current_set)
    self.settings:saveSetting("current_level",    self.current_level)
    self.settings:saveSetting("last_played_levels", self.last_played_levels)
    self.settings:saveSetting("best_moves",       self.best_moves)
    self.settings:saveSetting("best_pushes",      self.best_pushes)
    self.settings:saveSetting("furthest_reached", self.furthest_reached)
    self.settings:flush()
end

function Sokoban:addToMainMenu(menu_items)
    menu_items.sokoban = {
        text          = _("Sokoban"),
        sorting_hint  = "tools",
        callback      = function()
            self:_loadSettings()
            self:startLevel(self:_setIndex(self.current_set), self.current_level)
        end,
    }
end

function Sokoban:_setIndex(set_name)
    for i, ls in ipairs(LEVEL_SETS) do
        if ls.name == set_name then return i end
    end
    return 1
end

function Sokoban:startLevel(set_idx, level_num)
    set_idx   = set_idx   or 1
    level_num = level_num or 1

    local ls = LEVEL_SETS[set_idx]
    if not ls then ls = LEVEL_SETS[1]; set_idx = 1 end
    if level_num < 1 then level_num = 1 end
    if level_num > #ls.levels then level_num = #ls.levels end

    self.current_set   = ls.name
    self.current_level = level_num
    self.last_played_levels[self.current_set] = level_num
    self:_saveSettings()

    self.game = Game.from_xsb(ls.levels[level_num])

    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
    end

    self.widget = self:_buildWidget()
    UIManager:show(self.widget)
    UIManager:setDirty(self.widget, "ui", self.widget.dimen)
end

function Sokoban:_buildWidget()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()

    local toolbar_h = Screen:scaleBySize(60)
    local icon_size = Screen:scaleBySize(40)

    local game = self.game

    -- title bar created first so getSize() includes the subtitle line
    local title_bar = TitleBar:new{
        width          = sw,
        title          = self.current_set .. " #" .. self.current_level,
        close_callback = function()
            self:_onClose()
        end,
    }
    local title_h = title_bar:getSize().h

    -- board widget
    local board_w = sw
    local board_h = sh - title_h - toolbar_h

    local board = Board:new{
        game        = game,
        width       = board_w,
        height      = board_h,
        icon_dir    = self.path .. "/tiles",
        on_swipe_cb = function(dr, dc)
            self:_onMove(dr, dc)
        end,
    }
    self._board = board
    self._title_bar = title_bar

    -- toolbar: undo + level select
    local undo_btn = IconButton:new{
        icon     = "chevron.left",
        width    = icon_size,
        height   = icon_size,
        callback = function()
            if game:undo() then
                self:_refresh()
            end
        end,
    }
    local restart_btn = IconButton:new{
        icon     = "cre.render.reload",
        width    = icon_size,
        height   = icon_size,
        callback = function() self:_onRestart() end,
    }
    local sel_btn = IconButton:new{
        icon     = "appbar.settings",
        width    = icon_size,
        height   = icon_size,
        callback = function() self:openSettings() end,
    }

    local status_widget = TextWidget:new{
        text = self:_statusText(),
        face = Font:getFace("cfont", 16),
    }
    self._status_text_widget = status_widget

    local left_toolbar = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{ width = Screen:scaleBySize(20) },
        undo_btn,
        HorizontalSpan:new{ width = Screen:scaleBySize(20) },
        restart_btn,
        HorizontalSpan:new{ width = Screen:scaleBySize(20) },
        status_widget,
    }
    self._left_toolbar = left_toolbar

    local right_toolbar = HorizontalGroup:new{
        align = "center",
        sel_btn,
        HorizontalSpan:new{ width = Screen:scaleBySize(20) },
    }

    local flex_w = math.max(0, sw - left_toolbar:getSize().w - right_toolbar:getSize().w)

    local toolbar = HorizontalGroup:new{
        align = "center",
        left_toolbar,
        HorizontalSpan:new{ width = flex_w },
        right_toolbar,
    }
    self._toolbar = toolbar

    local content_h = title_h + board_h + icon_size
    local gap = sh - content_h

    local layout = VerticalGroup:new{
        align = "left",
        title_bar,
        board,
        toolbar,
        gap > 0 and VerticalSpan:new{ height = gap } or nil,
    }

    local frame = FrameContainer:new{
        width      = sw,
        height     = sh,
        bordersize = 0,
        padding    = 0,
        background = Blitbuffer.COLOR_WHITE,
        layout,
    }

    return frame
end

function Sokoban:_statusText()
    if not self.game then return "" end
    return _("Moves: ") .. self.game.moves .. "  " .. _("Pushes: ") .. self.game.pushes
end

function Sokoban:_onMove(dr, dc)
    if self.game:move(dr, dc) then
        self:_refresh()
        if self.game:is_solved() then
            UIManager:scheduleIn(0.1, function()
                self:_onSolved()
            end)
        end
    end
end

function Sokoban:_refresh()
    self._status_text_widget:setText(self:_statusText())
    self._left_toolbar:resetLayout()
    self._toolbar:resetLayout()
    UIManager:setDirty(self.widget, "ui", self.widget.dimen)
end

function Sokoban:_onSolved()
    local ls_idx  = self:_setIndex(self.current_set)
    local ls      = LEVEL_SETS[ls_idx]
    local has_next = self.current_level < #ls.levels

    -- update best scores
    self.best_moves[self.current_set]  = self.best_moves[self.current_set]  or {}
    self.best_pushes[self.current_set] = self.best_pushes[self.current_set] or {}
    local prev_m = self.best_moves[self.current_set][self.current_level]
    local prev_p = self.best_pushes[self.current_set][self.current_level]
    if not prev_m or self.game.moves  < prev_m then
        self.best_moves[self.current_set][self.current_level]  = self.game.moves
    end
    if not prev_p or self.game.pushes < prev_p then
        self.best_pushes[self.current_set][self.current_level] = self.game.pushes
    end

    -- advance furthest_reached so the next level unlocks
    local fr = self.furthest_reached[self.current_set] or 1
    self.furthest_reached[self.current_set] = math.max(fr, math.min(self.current_level + 1, #ls.levels))

    -- full refresh so e-ink ghosts clear
    UIManager:setDirty(self.widget, "full")

    local msg = _("Solved!") .. "\n" ..
        _("Moves: ") .. self.game.moves .. "  " .. _("Pushes: ") .. self.game.pushes
    UIManager:show(ConfirmBox:new{
        text         = msg,
        ok_text      = has_next and _("Next Level") or _("OK"),
        cancel_text  = _("Menu"),
        ok_callback  = function()
            if has_next then
                self:startLevel(ls_idx, self.current_level + 1)
            end
        end,
        cancel_callback = function()
            self:openSettings()
        end,
    })
end

function Sokoban:_onRestart()
    local ls_idx = self:_setIndex(self.current_set)
    self:startLevel(ls_idx, self.current_level)
end

function Sokoban:_onSkip(set_idx, level_num)
    local ls = LEVEL_SETS[set_idx]
    local fr = self.furthest_reached[ls.name] or 1
    self.furthest_reached[ls.name] = math.max(fr, math.min(level_num + 1, #ls.levels))
    self:_saveSettings()
    self:startLevel(set_idx, level_num + 1)
end

function Sokoban:openSettings()
    local sets_info = {}
    for _, ls in ipairs(LEVEL_SETS) do
        table.insert(sets_info, { name = ls.name, count = #ls.levels })
    end
    local w = SettingsWidget:new{
        level_sets       = sets_info,
        current_set      = self.current_set,
        current_level    = self.current_level,
        playing_level    = self.current_level,
        playing_set      = self.current_set,
        last_played_levels = self.last_played_levels,
        best_moves       = self.best_moves,
        furthest_reached = self.furthest_reached,
        on_play_cb       = function(set_idx, level_num)
            self:startLevel(set_idx, level_num)
        end,
        on_skip_cb       = function(set_idx, level_num)
            self:_onSkip(set_idx, level_num)
        end,
    }
    UIManager:show(w)
end

function Sokoban:_onClose()
    self:_saveSettings()
    if self._board then
        self._board:freeImages()
    end
    UIManager:close(self.widget)
    self.widget = nil
end

return Sokoban
