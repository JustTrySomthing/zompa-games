local sdk = require("zompado")
local mixer = sdk.audio()
local dropSound
local columns, rows = 7, 6

local function initAudio()
    local samples, rate = 2400, 24000
    local sound = love.sound.newSoundData(samples, rate, 16, 1)
    for i = 0, samples - 1 do
        local t = i / rate
        local envelope = (1 - i / samples) ^ 3
        sound:setSample(i, 0.18 * envelope * math.sin(2 * math.pi * (370 * t - 650 * t * t)))
    end
    dropSound = mixer:register(love.audio.newSource(sound), "effects")
end

local function playDrop()
    if not dropSound then return end
    dropSound:stop()
    dropSound:play()
end
local board, player, winner, played, pending
local cpuAt
local mode, history, matchState, canMove, moveSent
local loadingSave = false

local function readHost(name)
    local file = io.open("/zompado/" .. name, "r")
    if not file then return nil end
    local value = file:read("*a")
    file:close()
    return value
end
local colors = {
    { 1.0, 0.86, 0.44 },
    { 0.79, 0.72, 1.0 },
}
local finish

local function reset()
    board, player, winner, played, pending, cpuAt = {}, 1, 0, 0, nil, nil
    history = ""
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
    history = history .. tostring(column)
    if not loadingSave and mode ~= "online" then
        playDrop()
        love.filesystem.write(mode .. ".save", history)
    end
    if mode == "solo" and player == 2 and winner == 0 and played < rows * columns then
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
    pcall(initAudio)
    local requested = readHost("mode")
    mode = (requested == "online" or requested == "local") and requested or "solo"
    reset()
    if mode == "online" then return end
    local savePath = mode .. ".save"
    if not love.filesystem.getInfo(savePath, "file") then return end
    local saved = love.filesystem.read(savePath, rows * columns)
    if not saved or not saved:match("^[1-7]+$") then return end
    loadingSave = true
    for digit in saved:gmatch(".") do drop(tonumber(digit)) end
    loadingSave = false
end

function love.update(dt)
    mixer:update(dt)
    if mode == "online" then
        local state = readHost("match")
        if not state or state == matchState then return end
        local cells, turn, result, allowed = state:match("^([012]+):([12]):([012]):([01])$")
        if not cells or #cells ~= rows * columns then return end
        local previousCount = matchState and played
        matchState, canMove, moveSent, pending = state, allowed == "1", false, nil
        player, winner, played = tonumber(turn), tonumber(result), 0
        for index = 1, #cells do
            local row, column = math.floor((index - 1) / columns) + 1, (index - 1) % columns + 1
            local piece = tonumber(cells:sub(index, index))
            board[row][column] = piece
            if piece ~= 0 then played = played + 1 end
        end
        if previousCount and played > previousCount then playDrop() end
        return
    end
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
    local message
    if mode == "online" then
        message = winner ~= 0 and "Game over" or played == columns * rows and "Draw"
            or moveSent and "Sending move…" or canMove and "Choose a column" or "Waiting for a turn"
    elseif mode == "local" then
        message = winner ~= 0 and ("Player " .. winner .. " wins!") or played == columns * rows and "Draw"
            or pending and "Tap again to drop" or ("Player " .. player .. " · Choose a column")
    else
        message = winner == 1 and "You win!" or winner == 2 and "Computer wins"
            or played == columns * rows and "Draw"
            or player == 2 and "Computer is moving" or pending and "Tap again to drop" or "Choose a column"
    end
    g.setColor(0.94, 0.94, 0.98)
    g.printf(message, 0, y + rows * size + 14, width, "center")
    if mode ~= "online" and (winner ~= 0 or played == columns * rows) then
        g.printf("Tap to play again", 0, y + rows * size + 40, width, "center")
    end
end

local function newGame()
    reset()
    love.filesystem.remove(mode .. ".save")
end

local function press(mx, my)
    if winner ~= 0 or played == columns * rows then
        if mode ~= "online" then newGame() end
        return
    end
    if mode == "solo" and player ~= 1 then return end
    if mode == "online" and (not canMove or moveSent) then return end
    local x, y, size = geometry()
    local column = math.floor((mx - x) / size) + 1
    if my < y or my >= y + rows * size or column < 1 or column > columns or not landing(column) then return end
    if mode == "online" then
        local file = io.open("/zompado/move", "w")
        if not file then return end
        file:write(tostring(column - 1))
        file:close()
        moveSent = true
    elseif pending == column then
        drop(column)
    else
        pending = column
    end
end

function love.mousepressed(mx, my, button, isTouch)
    if button == 1 and not isTouch then press(mx, my) end
end

function love.touchpressed(_, x, y)
    press(x, y)
end

function love.keypressed(key)
    if key == "r" and mode ~= "online" then newGame() end
end
