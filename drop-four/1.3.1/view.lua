local rules = require("rules")
local g = love.graphics
local view = {}
local width, height = 540, 620
local boardX, boardY, cell = 53, 144, 62
local ink, soft = {1, 0.96, 1}, {0.78, 0.8, 0.92}
local teams = {
    {name = "Cats", light = {1, 0.68, 0.78}, rim = {1, 0.43, 0.62}, dark = {0.43, 0.14, 0.30}},
    {name = "Dogs", light = {0.65, 0.88, 1}, rim = {0.27, 0.72, 1}, dark = {0.10, 0.32, 0.54}},
}
local fonts, art, mist
local levels = {"Easy", "Normal", "Hard"}

local function size()
    local w, h = g.getDimensions()
    local scale = math.min(w / width, h / height)
    return (w - width * scale) / 2, (h - height * scale) / 2, scale
end

local function color(rgb, alpha)
    g.setColor(rgb[1], rgb[2], rgb[3], alpha or 1)
end

local function box(rgb, x, y, w, h, radius, alpha)
    color(rgb, alpha)
    g.rectangle("fill", x, y, w, h, radius, radius)
end

local function circle(rgb, x, y, radius, alpha)
    color(rgb, alpha)
    g.circle("fill", x, y, radius)
end

local function text(value, font, rgb, x, y, w, align)
    color(rgb)
    g.setFont(fonts[font])
    g.printf(value, x, y, w, align or "center")
end

local function rule(rgb, x1, y1, x2, y2, alpha)
    color(rgb, alpha)
    g.line(x1, y1, x2, y2)
end

local function image(texture, x, y, w, h, alpha)
    g.setColor(1, 1, 1, alpha or 1)
    g.draw(texture, x, y, 0, w / texture:getWidth(), h / texture:getHeight())
end

local function paw(x, y, scale, tint, alpha)
    color(tint, alpha)
    g.ellipse("fill", x, y + 5 * scale, 8 * scale, 6 * scale)
    for toe = 1, 4 do
        local dx = (toe - 2.5) * 5
        g.ellipse("fill", x + dx * scale, y - (math.abs(dx) < 3 and 5 or 2) * scale,
            2.5 * scale, 3.6 * scale)
    end
end

local function species(state, side)
    return side == 1 and state.side or 3 - state.side
end

function view.load()
    fonts = {
        hero = g.newFont(42), title = g.newFont(27), heading = g.newFont(20),
        body = g.newFont(17), small = g.newFont(13), tiny = g.newFont(11),
    }
    art = {
        g.newImage("art/cat.png"), g.newImage("art/dog.png"),
        faceoff = g.newImage("art/faceoff.png"),
    }
    local glow = love.image.newImageData(96, 96)
    glow:mapPixel(function(x, y)
        local distance = math.sqrt(((x - 47.5) / 47.5)^2 + ((y - 47.5) / 47.5)^2)
        return 1, 1, 1, math.max(0, 1 - distance)^2
    end)
    mist = g.newImage(glow)
end

local function glow(tint, x, y, w, h, alpha)
    color(tint, alpha)
    g.draw(mist, x, y, 0, w / 96, h / 96)
end

local function arena()
    box({0.045, 0.052, 0.11}, 0, 0, width, height, 0)
    glow({0.77, 0.20, 0.46}, -250, -155, 730, 970, 0.65)
    glow({0.18, 0.45, 0.90}, 77, -180, 730, 1010, 0.62)
    glow({0.38, 0.27, 0.62}, -24, 351, 600, 390, 0.35)
    for i = 0, 7 do
        rule(soft, 270, 439, (i - 1) * 108, 620, 0.085)
    end
    for _, y in ipairs({482, 506, 536, 571, 612}) do
        rule(soft, 0, y, width, y, 0.072)
    end
    for i = 0, 6 do
        local x = 12 + (i * 19) % 40
        paw(x, 95 + i * 68, 0.76, teams[1].rim, 0.18)
        paw(width - x, 103 + i * 67, 0.76, teams[2].rim, 0.18)
    end
end

local function badge(id, x, y, radius, alpha)
    local team = teams[id]
    circle({0.04, 0.045, 0.095}, x, y + 3, radius + 2, alpha)
    circle(team.rim, x, y, radius + 1, alpha)
    circle(team.dark, x, y, radius - 1, alpha)
    image(art[id], x - radius, y - radius, radius * 2, radius * 2, alpha)
end

local function card(state, actor, x)
    local id = species(state, actor)
    local team = teams[id]
    local active = (state.mode ~= "online" or state.matchReady) and not state.finishedAt and state.player == actor
    box({0.053, 0.057, 0.12}, x, 16, 146, 75, 17, 0.97)
    box(team.rim, x, 14, 146, 73, 17, active and 0.82 or 0.36)
    box({0.075, 0.071, 0.14}, x + 2, 16, 142, 69, 15)
    glow(team.rim, x, 19, 133, 68, active and 0.35 or 0.17)
    badge(id, x + 33, 51, 24, 1)
    text(team.name, "heading", team.light, x + 64, 27, 78, "left")
    if state.mode == "online" then
        text(actor == 1 and "First player" or "Second player", "tiny", soft, x + 64, 54, 80, "left")
    else
        for i = 1, 3 do
            circle(i <= state.scores[actor] and team.light or team.dark, x + 72 + (i - 1) * 18, 63, 5)
        end
    end
end

local function button(label, x, y, w, h, tint)
    box({0.043, 0.04, 0.09}, x, y + 4, w, h, 13, 0.9)
    box(tint, x, y, w, h, 13)
    box(ink, x + 3, y + 2, w - 6, 6, 5, 0.18)
    text(label, "body", {0.11, 0.08, 0.16}, x, y + (h - 20) / 2, w)
end

local function selection(state)
    text("CATS VS DOGS", "hero", ink, 0, 55, width)
    text("Choose your side", "heading", soft, 0, 116, width)
    for id, team in ipairs(teams) do
        local x = id == 1 and 42 or 282
        local selected = id == state.side
        box(team.rim, x, 172, 216, 257, 22, selected and 1 or 0.38)
        box({0.065, 0.066, 0.14}, x + 3, 175, 210, 251, 19)
        glow(team.rim, x, 166, 216, 227, 0.63)
        badge(id, x + 108, 269, 74, 1)
        text(team.name, "title", team.light, x, 356, 216)
        if selected then text("Selected", "small", soft, x, 395, 216) end
    end
    box({0.11, 0.12, 0.22}, 100, 454, 340, 43, 11)
    text("Difficulty: " .. levels[state.difficulty], "body", ink, 100, 465, 340)
    rule(soft, 407, 470, 413, 475)
    rule(soft, 413, 475, 407, 480)
    button("Play", 100, 513, 340, 51, teams[state.side].light)
    text("First to three wins", "small", soft, 0, 583, width)
end

local function faceoff(state)
    local elapsed = state.time - state.intro
    local opacity = math.min(1, elapsed * 5)
    glow(teams[1].rim, -20, 62, 580, 520, 0.45)
    image(art.faceoff, 81, 96, 378, 378, opacity)
    box({0.025, 0.025, 0.065}, 65, 390, 410, 129, 20, 0.92)
    local showFight = elapsed >= 0.58
    local punch = showFight and math.max(0, 1 - (elapsed - 0.58) * 5) or 0
    g.push()
    g.translate(270, 431)
    g.scale(1 + 0.28 * punch)
    text(showFight and "FIGHT!" or "CATS VS DOGS", "hero", ink, -270, -25, width)
    g.pop()
    text("First to three wins", "body", soft, 0, 470, width)
end

function view.celebrate(state)
    local id = species(state, state.winner)
    for index = 1, 44 do
        state.effects[index] = {
            x = 110 + love.math.random() * 320, y = 130 + love.math.random() * 160,
            vx = (love.math.random() - 0.5) * 240, vy = -love.math.random() * 205,
            size = 2 + love.math.random() * 4, color = index % 4 == 0 and ink or teams[id].rim,
        }
    end
end

local function confetti(state)
    if not state.finishedAt then return end
    local t = state.time - state.finishedAt + 0.5
    if t > 2.35 then return end
    local alpha = math.min(1, (2.35 - t) * 2)
    for i, piece in ipairs(state.effects) do
        box(piece.color, piece.x + piece.vx * t, piece.y + piece.vy * t + 290 * t * t,
            piece.size, 1 + piece.size * math.abs(math.cos(i + t * 9)), 1, alpha)
    end
end

local function token(state, actor, x, y, highlight, alpha)
    local id = species(state, actor)
    local team = teams[id]
    if highlight then glow(team.light, x - 45, y - 45, 90, 90, 0.85) end
    badge(id, x, y, 23, alpha)
end

local function drawBoard(state)
    local frameX, frameY, frameW, frameH = boardX - 9, boardY - 10, cell * 7 + 18, cell * 6 + 20
    box({0.025, 0.027, 0.075}, frameX - 5, frameY + 13, frameW + 10, frameH, 24, 0.9)
    box({0.35, 0.49, 0.78}, frameX, frameY, frameW, frameH, 20)
    box({0.149, 0.271, 0.490}, frameX + 2, frameY + 2, frameW - 4, frameH - 4, 19)
    for row = 1, 6 do
        local y = boardY + (row - 0.5) * cell
        for column = 1, 7 do
            local x = boardX + (column - 0.5) * cell
            local side = state.board[row][column]
            local highlighted = state.line and state.line[(row - 1) * 7 + column]
            local tint = column == state.hover and state.playable and teams[species(state, state.player)].rim
            circle(highlighted and teams[species(state, side)].light or {0.39, 0.53, 0.77}, x, y + 1, 28)
            circle(tint or {0.09, 0.14, 0.28}, x, y, 26)
            circle({0.06, 0.095, 0.20}, x, y, tint and 24 or 25)
            if side == 0 then paw(x, y, 0.58, soft, 0.14) end
            local drop = state.drop
            if side ~= 0 and not (drop and drop.row == row and drop.column == column) then
                token(state, side, x, y, highlighted, 1)
            end
        end
    end
    local preview = state.playable and state.hover and rules.landing(state.board, state.hover)
    if preview then
        token(state, state.player, boardX + (state.hover - 0.5) * cell,
            boardY + (preview - 0.5) * cell, false, 0.34)
    end
    if state.drop then
        local drop = state.drop
        local elapsed = state.time - drop.time
        local progress = math.min(1, elapsed / 0.34)
        local y = boardY + (drop.row - 0.5) * cell
        local start = boardY - 21
        local bounce = progress == 1 and 9 * math.max(0, 1 - (elapsed - 0.34) / 0.16)
            * math.abs(math.sin((elapsed - 0.34) * 22)) or 0
        local highlighted = state.line and state.line[(drop.row - 1) * 7 + drop.column]
        token(state, drop.side, boardX + (drop.column - 0.5) * cell,
            start + (y - start) * progress^2 - bounce, highlighted and progress == 1, 1)
    end
end

local function matchMessage(state)
    if state.finishedAt and state.time >= state.finishedAt then
        if not state.winner then return "Draw" end
        local name = teams[species(state, state.winner)].name
        if state.scores[state.winner] == 3 then return name .. " win the series!" end
        return name .. " win!"
    end
    if state.finishedAt then return state.winner and "Four in a row!" or "Board full" end
    if state.mode == "online" then
        if not state.matchReady then return "Loading match…" end
        if state.moveSent then return "Sending your move…" end
        return state.canMove and "Your turn" or "Waiting for the other player"
    end
    if state.mode == "solo" then return state.player == 1 and "Your turn" or "Thinking…" end
    return teams[species(state, state.player)].name .. " to play"
end

local function match(state)
    card(state, 1, 18)
    card(state, 2, 376)
    text("CATS VS DOGS", "heading", ink, 167, 27, 206)
    text(state.mode == "online" and "Online match" or "First to three", "small", soft, 167, 56, 206)
    local finished = state.finishedAt and state.time >= state.finishedAt
    text(matchMessage(state), "heading", finished and state.winner and teams[species(state, state.winner)].light or ink,
        0, 96, width)
    drawBoard(state)
    if finished and state.mode ~= "online" then
        local seriesOver = state.winner and state.scores[state.winner] == 3
        local label = seriesOver and "Play again" or "Next round"
        button(label, 153, 551, 234, 46, state.winner and teams[species(state, state.winner)].light or ink)
    elseif not finished and state.playable then
        text("Tap or drag to choose a column", "body", soft, 0, 562, width)
    end
    confetti(state)
end

function view.draw(state)
    g.clear(0.02, 0.022, 0.05)
    local x, y, scale = size()
    g.setScissor(x, y, width * scale, height * scale)
    g.push()
    g.translate(x, y)
    g.scale(scale)
    arena()
    if state.phase == "choose" then
        selection(state)
    elseif state.phase == "intro" then
        faceoff(state)
    else
        match(state)
    end
    g.pop()
    g.setScissor()
end

local function inside(x, y, left, top, w, h)
    return x >= left and y >= top and x < left + w and y < top + h
end

function view.action(state, x, y)
    local offsetX, offsetY, scale = size()
    x, y = (x - offsetX) / scale, (y - offsetY) / scale
    if state.phase == "choose" then
        if inside(x, y, 42, 172, 216, 257) then return "cat" end
        if inside(x, y, 282, 172, 216, 257) then return "dog" end
        if inside(x, y, 100, 454, 340, 43) then return "difficulty" end
        if inside(x, y, 100, 513, 340, 51) then return "start" end
    elseif state.phase == "intro" then
        if inside(x, y, 0, 0, width, height) then return "intro" end
    elseif state.finishedAt and state.time >= state.finishedAt then
        if state.mode ~= "online" and inside(x, y, 153, 551, 234, 46) then return "next" end
    elseif inside(x, y, boardX, boardY - 8, cell * 7, cell * 6 + 16) then
        return math.floor((x - boardX) / cell) + 1
    end
end

return view
