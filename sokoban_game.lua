-- Pure game logic, no KOReader dependencies.
-- Test with: luajit game.lua

local WALL   = 0
local FLOOR  = 1
local TARGET = 2
local BOX    = 3
local BOX_ON = 4
local PLAYER = 5
local PLR_ON = 6

local Game = {}
Game.__index = Game

-- Export constants so board.lua can use them
Game.WALL   = WALL
Game.FLOOR  = FLOOR
Game.TARGET = TARGET
Game.BOX    = BOX
Game.BOX_ON = BOX_ON
Game.PLAYER = PLAYER
Game.PLR_ON = PLR_ON

local XSB_MAP = {
    ["#"] = WALL,
    [" "] = FLOOR,
    ["."] = TARGET,
    ["@"] = PLAYER,
    ["+"] = PLR_ON,
    ["$"] = BOX,
    ["*"] = BOX_ON,
    ["-"] = FLOOR,  -- some sets use - for floor
    ["_"] = FLOOR,
}

function Game.from_xsb(xsb)
    local self = setmetatable({}, Game)
    self.grid = {}
    self.rows = 0
    self.cols = 0
    self.player_r = 1
    self.player_c = 1
    self.moves = 0
    self.pushes = 0
    self.history = {}

    local lines = {}
    for line in (xsb .. "\n"):gmatch("([^\n]*)\n") do
        -- skip comment lines (XSB uses ';')
        if line:sub(1,1) ~= ";" then
            table.insert(lines, line)
        end
    end
    -- strip leading/trailing blank lines
    while #lines > 0 and lines[1]:match("^%s*$") do table.remove(lines, 1) end
    while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end

    local max_cols = 0
    for _, line in ipairs(lines) do
        if #line > max_cols then max_cols = #line end
    end

    self.rows = #lines
    self.cols = max_cols

    for r, line in ipairs(lines) do
        self.grid[r] = {}
        for c = 1, max_cols do
            local ch = line:sub(c, c)
            local cell = XSB_MAP[ch] or FLOOR
            self.grid[r][c] = cell
            if cell == PLAYER or cell == PLR_ON then
                self.player_r = r
                self.player_c = c
            end
        end
    end

    return self
end

function Game:_snapshot()
    local snap = {
        player_r = self.player_r,
        player_c = self.player_c,
        moves    = self.moves,
        pushes   = self.pushes,
        grid     = {},
    }
    for r = 1, self.rows do
        snap.grid[r] = {}
        for c = 1, self.cols do
            snap.grid[r][c] = self.grid[r][c]
        end
    end
    return snap
end

function Game:move(dr, dc)
    local nr = self.player_r + dr
    local nc = self.player_c + dc
    if nr < 1 or nr > self.rows or nc < 1 or nc > self.cols then return false end
    local dest = self.grid[nr][nc]
    if dest == WALL then return false end

    local snap = self:_snapshot()

    if dest == BOX or dest == BOX_ON then
        local br = nr + dr
        local bc = nc + dc
        if br < 1 or br > self.rows or bc < 1 or bc > self.cols then return false end
        local behind = self.grid[br][bc]
        if behind == WALL or behind == BOX or behind == BOX_ON then return false end
        -- move box
        self.grid[br][bc] = (behind == TARGET) and BOX_ON or BOX
        self.grid[nr][nc] = (dest  == BOX_ON)  and TARGET or FLOOR
        self.pushes = self.pushes + 1
    end

    -- vacate current cell
    local old = self.grid[self.player_r][self.player_c]
    self.grid[self.player_r][self.player_c] = (old == PLR_ON) and TARGET or FLOOR

    -- occupy new cell
    local new_dest = self.grid[nr][nc]
    self.grid[nr][nc] = (new_dest == TARGET) and PLR_ON or PLAYER

    self.player_r = nr
    self.player_c = nc
    self.moves = self.moves + 1

    if #self.history >= 500 then table.remove(self.history, 1) end
    table.insert(self.history, snap)
    return true
end

function Game:undo()
    if #self.history == 0 then return false end
    local snap = table.remove(self.history)
    self.player_r = snap.player_r
    self.player_c = snap.player_c
    self.moves    = snap.moves
    self.pushes   = snap.pushes
    self.grid     = snap.grid
    return true
end

function Game:is_solved()
    for r = 1, self.rows do
        for c = 1, self.cols do
            if self.grid[r][c] == BOX then return false end
        end
    end
    return true
end

function Game:box_count()
    local n = 0
    for r = 1, self.rows do
        for c = 1, self.cols do
            local v = self.grid[r][c]
            if v == BOX or v == BOX_ON then n = n + 1 end
        end
    end
    return n
end

function Game:boxes_on_target()
    local n = 0
    for r = 1, self.rows do
        for c = 1, self.cols do
            if self.grid[r][c] == BOX_ON then n = n + 1 end
        end
    end
    return n
end

-- Self-test when run directly with luajit
if arg and arg[0] and arg[0]:match("game%.lua$") then
    local level = [[
####
# .#
#  ###
#*@  #
#  $ #
#  ###
####]]
    local g = Game.from_xsb(level)
    print("rows="..g.rows.." cols="..g.cols)
    print("player at "..g.player_r..","..g.player_c)
    print("boxes="..g:box_count().." on_target="..g:boxes_on_target())
    print("solved="..tostring(g:is_solved()))
    g:move(0, 1)  -- push box right
    print("after move right: player="..g.player_r..","..g.player_c.." moves="..g.moves)
    g:undo()
    print("after undo: player="..g.player_r..","..g.player_c.." moves="..g.moves)
end

return Game
