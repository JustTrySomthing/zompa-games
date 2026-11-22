local rules = require("rules")
local g = love.graphics
local view = {dropFall = 0.56}
local width, height = 540, 665
local boardX, boardY, cell = 25, 152, 70
local arenaColor = {24 / 255, 20 / 255, 35 / 255}
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
    glow({0.80, 0.22, 0.48}, 0, 0, 458, 655, 0.68)
    glow({0.20, 0.49, 0.98}, 82, 0, 458, 655, 0.65)
    for i = 0, 6 do
        local x = 13 + (i * 19) % 33
        paw(x, 95 + i * 72, 0.72, teams[1].rim, 0.17)
        paw(width - x, 103 + i * 71, 0.72, teams[2].rim, 0.17)
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
    local active = (state.mode ~= "online" or state.matchReady) and not state.finishedAt and (state.turnAt and state.time < state.turnAt and state.drop and state.drop.side or state.player) == actor
    box({0.053, 0.057, 0.12}, x, 14, 250, 77, 17, 0.97)
    box(team.rim, x, 10, 250, 77, 17, active and 0.9 or 0.42)
    box({0.075, 0.071, 0.14}, x + 2, 12, 246, 73, 15)
    glow(team.rim, x + 4, 14, 210, 68, active and 0.38 or 0.19)
    badge(id, x + 43, 47, 27, 1)
    text(team.name, "title", team.light, x + 83, 29, 105, "left")
    text(tostring(state.scores[actor]), "hero", ink, x + 181, 20, 55, "right")

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
    badge(id, x, y, 27, alpha)
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
            circle(highlighted and teams[species(state, side)].light or {0.39, 0.53, 0.77}, x, y + 1, 32)
            circle(tint or {0.09, 0.14, 0.28}, x, y, 30)
            circle({0.06, 0.095, 0.20}, x, y, tint and 28 or 29)
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
        local progress = math.min(1, elapsed / view.dropFall)
        local x = boardX + (drop.column - 0.5) * cell
        local y = boardY + (drop.row - 0.5) * cell
        local start = boardY + 13
        local impact = elapsed - view.dropFall
        local bounce = impact >= 0 and 11 * math.max(0, 1 - impact / 0.18)
            * math.sin(math.pi * math.min(1, impact / 0.18)) or 0
        local coinY = start + (y - start) * progress^2 - bounce
        local team = teams[species(state, drop.side)]
        if impact < 0 then
            local trail = math.min(64, (coinY - start) * 0.6)
            glow(team.rim, x - 29, coinY - 32 - trail, 58, 64 + trail, 0.70)
            for index = 1, 4 do
                local distance = trail * index / 4
                circle(team.light, x, coinY - distance, 9 - index, 0.24 * progress * (1 - index / 5))
            end
        elseif impact < 0.28 then
            local wave = impact / 0.28
            local fade = (1 - wave)^2
            glow(team.light, x - 54, y - 54, 108, 108, 0.85 * fade)
            color(team.light, 0.84 * fade)
            g.circle("line", x, y, 28 + 31 * wave)
            for index = 0, 9 do
                local angle = index * math.pi / 5
                local distance = 27 + wave * (29 + 9 * (index % 3))
                local dx, dy = math.cos(angle), math.sin(angle)
                rule(team.light, x + dx * distance, y + dy * distance + 8 * wave^2,
                    x + dx * (distance + 6 * fade), y + dy * (distance + 6 * fade) + 8 * wave^2, fade)
            end
        end
        local highlighted = state.line and state.line[(drop.row - 1) * 7 + drop.column]
        token(state, drop.side, x, coinY, highlighted and impact >= 0, 1)
    end
end

local function localHeading(state, finished)
    if finished and not state.winner then
        text("Draw", "title", ink, 0, 103, width)
        return
    end

    local dropping = state.turnAt and state.time < state.turnAt and state.drop
    local actor = (finished and state.winner) or (dropping and state.drop.side) or state.player
    local id = species(state, actor)
    local team = teams[id]
    local name = team.name
    local action = "Turn"
    if finished then
        action = state.scores[actor] == 3 and "Win the match!" or "Win the round!"
    elseif state.mode == "solo" and actor == 1 then
        name = "Your"
    end

    local nameWidth = fonts.heading:getWidth(name)
    local groupX = (width - nameWidth - 36) / 2
    badge(id, groupX + 13, 104, 12, 1)
    text(name, "heading", ink, groupX + 36, 92, nameWidth + 2, "left")
    text(action, "heading", team.light, 0, 115, width)
end

local function match(state)
    card(state, 1, 14)
    card(state, 2, 276)
    local finished = state.finishedAt and state.time >= state.finishedAt
    if state.mode ~= "online" then localHeading(state, finished) end
    drawBoard(state)
    if state.mode ~= "online" then
        if finished then
            local seriesOver = state.winner and state.scores[state.winner] == 3
            local label = seriesOver and "Play again" or "Next round"
            button(label, 138, 610, 264, 46, state.winner and teams[species(state, state.winner)].light or ink)
        else
            text("ROUND " .. state.round, "heading", ink, 0, 610, width)
            text("First to 3 round wins takes the match", "body", soft, 0, 637, width)
        end
    end
    confetti(state)
end

function view.draw(state)
    g.clear(arenaColor[1], arenaColor[2], arenaColor[3])
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
        if state.mode ~= "online" and inside(x, y, 138, 610, 264, 46) then return "next" end
    elseif inside(x, y, boardX, boardY - 8, cell * 7, cell * 6 + 16) then
        return math.floor((x - boardX) / cell) + 1
    end
end

return view
