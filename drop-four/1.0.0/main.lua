local columns, rows = 7, 6
local board, player, winner, played, pending
local cpuAt
local colors = {
    { 1.0, 0.86, 0.44 },
    { 0.79, 0.72, 1.0 },
}
local finish

local function reset()
    board, player, winner, played, pending, cpuAt = {}, 1, 0, 0, nil, nil
    for row = 1, rows do
        board[row] = { 0, 0, 0, 0, 0, 0, 0 }
    end
end

local function landing(column)
    for row = rows, 1, -1 do
        if board[row][column] == 0 then return row end
    end
end

local function hasLine(row, column, side)
    for _, direction in ipairs({ { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, -1 } }) do
        local count = 1
        for _, sign in ipairs({ -1, 1 }) do
            for step = 1, 3 do
                local r = row + direction[1] * sign * step
                local c = column + direction[2] * sign * step
                if not board[r] or board[r][c] ~= side then break end
                count = count + 1
            end
        end
        if count >= 4 then return true end
    end
    return false
end

local function drop(column)
    local row = landing(column)
    if not row or winner ~= 0 then return end
    board[row][column] = player
    played = played + 1
    if hasLine(row, column, player) then winner = player end
    player = 3 - player
    pending = nil
    if player == 2 and winner == 0 and played < rows * columns then
        cpuAt = love.timer.getTime() + 0.3
    end
end

local function computerMove()
    local order = { 4, 3, 5, 2, 6, 1, 7 }
    for _, side in ipairs({ 2, 1 }) do
        for _, column in ipairs(order) do
            local row = landing(column)
            if row and hasLine(row, column, side) then return column end
        end
    end
    for _, column in ipairs(order) do
        if landing(column) then return column end
    end
end

local function geometry()
    local width, height = love.graphics.getDimensions()
    local cell = math.max(1, math.min((width - 36) / columns, (height - 152) / rows))
    return (width - cell * columns) / 2, (height - cell * rows) / 2, cell
end

function love.load()
    finish = love.graphics.newFont(19)
    reset()
end

function love.update()
    if cpuAt and love.timer.getTime() >= cpuAt then
        cpuAt = nil
        local column = computerMove()
        if column then drop(column) end
    end
end

function love.draw()
    local g = love.graphics
    local x, y, size = geometry()
    local width = g.getWidth()
    g.clear(0.08, 0.09, 0.12)
    g.setFont(finish)
    g.setColor(colors[1])
    g.printf("Drop Four", 0, math.max(2, y - 49), width, "center")
    g.setColor(0.15, 0.27, 0.49)
    g.rectangle("fill", x - 5, y - 5, columns * size + 10, rows * size + 10, 12, 12)
    for row = 1, rows do
        for column = 1, columns do
            local side = board[row][column]
            local preview = pending == column and landing(column) == row
            local color = colors[side] or { 0.06, 0.09, 0.17 }
            if preview then color = { 0.68, 0.59, 0.37 } end
            g.setColor(color)
            g.circle("fill", x + (column - 0.5) * size, y + (row - 0.5) * size, size * 0.40)
        end
    end
    local message = winner == 1 and "You win!" or winner == 2 and "Computer wins"
        or played == columns * rows and "Draw"
        or player == 2 and "Computer is moving" or pending and "Tap again to drop" or "Choose a column"
    g.setColor(0.94, 0.94, 0.98)
    g.printf(message, 0, y + rows * size + 14, width, "center")
    if winner ~= 0 or played == columns * rows then
        g.printf("Tap to play again", 0, y + rows * size + 40, width, "center")
    end
end

function love.mousepressed(mx, my, button)
    if button ~= 1 then return end
    if winner ~= 0 or played == columns * rows then reset(); return end
    if player ~= 1 then return end
    local x, y, size = geometry()
    local column = math.floor((mx - x) / size) + 1
    if my < y or my >= y + rows * size or column < 1 or column > columns or not landing(column) then return end
    if pending == column then drop(column) else pending = column end
end

function love.keypressed(key)
    if key == "r" then reset() end
end
