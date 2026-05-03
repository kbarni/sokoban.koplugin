local Device    = require("device")
local Geom      = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen    = Device.screen
local UIManager = require("ui/uimanager")

local Game = require("sokoban_game")

local ICON_DIR -- set by init from plugin_path passed by main.lua

local CELL_LAYERS = {
    [Game.WALL]   = { "wall" },
    [Game.FLOOR]  = { "floor" },
    [Game.TARGET] = { "floor", "target" },
    [Game.BOX]    = { "floor", "crate" },
    [Game.BOX_ON] = { "floor", "crate_on_target", "target" },
    [Game.PLAYER] = { "floor", "player" },
    [Game.PLR_ON] = { "floor", "player", "target" },
}

local Board = InputContainer:extend{
    game          = nil,
    width         = nil,
    height        = nil,
    icon_dir      = nil,
    on_swipe_cb   = nil, -- called with (dr, dc) before move, for main.lua to react
    player_sprite = "player",
}

function Board:init()
    ICON_DIR = self.icon_dir

    -- compute cell size so the whole grid fits
    self.cell_size = math.min(
        math.floor(self.width  / self.game.cols),
        math.floor(self.height / self.game.rows)
    )

    -- offset to center grid in available space
    self.offset_x = math.floor((self.width  - self.cell_size * self.game.cols) / 2)
    self.offset_y = math.floor((self.height - self.cell_size * self.game.rows) / 2)

    self.dimen = Geom:new{ w = self.width, h = self.height }

    -- image cache: cell_size × cell_size renders, keyed by icon name
    self._img_cache = {}

    self:registerTouchZones({
        {
            id = "sokoban_swipe",
            ges = "swipe",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges) return self:onSwipe(ges) end,
        },
    })
end

function Board:_getImage(icon_name)
    if not self._img_cache[icon_name] then
        local img = ImageWidget:new{
            file         = ICON_DIR .. "/" .. icon_name .. ".svg",
            width        = self.cell_size,
            height       = self.cell_size,
            scale_factor = 0,
            alpha        = true,
        }
        self._img_cache[icon_name] = img
    end
    return self._img_cache[icon_name]
end

function Board:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y

    local cs = self.cell_size
    local ox = x + self.offset_x
    local oy = y + self.offset_y

    for r = 1, self.game.rows do
        for c = 1, self.game.cols do
            local cell = self.game.grid[r][c]
            local layers
            if cell == Game.WALL then
                local below = self.game.grid[r + 1] and self.game.grid[r + 1][c]
                layers = { below == Game.WALL and "wall" or "wall_h" }
            else
                layers = CELL_LAYERS[cell] or { "floor" }
            end
            local px = ox + (c - 1) * cs
            local py = oy + (r - 1) * cs
            for _, icon_name in ipairs(layers) do
                local sprite = (icon_name == "player") and self.player_sprite or icon_name
                self:_getImage(sprite):paintTo(bb, px, py)
            end
        end
    end
end

function Board:getSize()
    return self.dimen
end

function Board:onSwipe(ges)
    local dir = ges.direction
    local dr, dc = 0, 0
    if     dir == "east"  then dc =  1; self.player_sprite = "player_right"
    elseif dir == "west"  then dc = -1; self.player_sprite = "player_left"
    elseif dir == "south" then dr =  1; self.player_sprite = "player"
    elseif dir == "north" then dr = -1; self.player_sprite = "player_up"
    else return false
    end

    if self.on_swipe_cb then
        self.on_swipe_cb(dr, dc)
    end
    return true
end

function Board:freeImages()
    for _, img in pairs(self._img_cache) do
        img:free()
    end
    self._img_cache = {}
end

return Board
