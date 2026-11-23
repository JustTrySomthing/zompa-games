local rules = {}
local directions = {{0, 1}, {1, 0}, {1, 1}, {1, -1}}
local order = {4, 3, 5, 2, 6, 1, 7}

function rules.board()
    local board = {}
    for row = 1, 6 do board[row] = {0, 0, 0, 0, 0, 0, 0} end
    return board
end

function rules.landing(board, column)
    for row = 6, 1, -1 do
        if board[row][column] == 0 then return row end
    end
end

function rules.line(board, row, column, side)
    for _, direction in ipairs(directions) do
        local cells = {[(row - 1) * 7 + column] = true}
        local count = 1
        for sign = -1, 1, 2 do
            for step = 1, 3 do
                local r = row + direction[1] * sign * step
                local c = column + direction[2] * sign * step
                if not board[r] or board[r][c] ~= side then break end
                cells[(r - 1) * 7 + c] = true
                count = count + 1
            end
        end
        if count >= 4 then return cells end
    end
end

local function winningColumn(board, side)
    for _, column in ipairs(order) do
        local row = rules.landing(board, column)
        if row and rules.line(board, row, column, side) then return column end
    end
end

local function search(board, side, depth, alpha, beta)
    local win = winningColumn(board, side)
    if win then return 100 + depth, win end
    local block = winningColumn(board, 3 - side)
    if depth == 0 then
        if block then return -80 end
        local score = 0
        for row = 1, 6 do
            local piece = board[row][4]
            if piece == side then score = score + 1
            elseif piece ~= 0 then score = score - 1 end
        end
        return score
    end
    local best, choice = -1000, nil
    for _, column in ipairs(block and {block} or order) do
        local row = rules.landing(board, column)
        if row then
            board[row][column] = side
            local score = -search(board, 3 - side, depth - 1, -beta, -alpha)
            board[row][column] = 0
            if score > best then best, choice = score, column end
            alpha = math.max(alpha, score)
            if alpha >= beta then break end
        end
    end
    if not choice then return 0 end
    return best, choice
end

function rules.computer(board, difficulty)
    if difficulty == 1 then
        if love.math.random() < 0.5 then
            local available = {}
            for _, column in ipairs(order) do
                if rules.landing(board, column) then available[#available + 1] = column end
            end
            if #available > 0 then return available[love.math.random(#available)] end
        end
    end
    local _, column = search(board, 2, difficulty == 3 and 5 or 3, -1000, 1000)
    return column
end

return rules
