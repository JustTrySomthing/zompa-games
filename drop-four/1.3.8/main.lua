local rules = require("rules")
local view = require("view")
local sdk = require("zompa")
local mixer = sdk.audio()
local sounds = {}
local state = {
    mode = "solo", side = 1, difficulty = 2, scores = {0, 0}, intro = 0, round = 1,
    time = 0, focus = 4, effects = {}, phase = "choose",
}
local activePointer
local previousMatch, poll = nil, 0
local cpuAt
local moveSent = false

local function readHost(name, limit)
    local file = io.open("/zompado/" .. name, "r")
    if not file then return end
    local value = file:read(limit)
    file:close()
    return value
end

local function play(name)
    local sound = sounds[name]
    if not sound then return end
    sound:stop()
    sound:play()
end

local function initAudio()
    local music = love.audio.newSource("audio/backyard-rumble.ogg", "stream")
    music:setLooping(true)
    music:setVolume(0.46)
    sounds.music = mixer:register(music, "music")
    for _, name in ipairs({"land", "pet_swish", "draw", "win", "lose"}) do
        local sound = love.audio.newSource("audio/" .. name .. ".wav", "static")
        sound:setVolume(0.72)
        sounds[name] = mixer:register(sound, "effects")
    end
end

local function startMusic()
    if sounds.music and not sounds.music:isPlaying() then sounds.music:play() end
end

local function save()
    local slot = "cats-" .. state.mode
    local progress = ("1:%d:%d:%d:%d:%s"):format(state.side, state.difficulty,
        state.openingScores[1], state.openingScores[2], state.history)
    if sdk.save(slot, progress) then
        sdk.save(slot .. "-round", ("%d:%s"):format(state.round, progress))
    end
end

local function scheduleComputer()
    cpuAt = nil
    if state.mode == "solo" and state.player == 2 and not state.winner and state.played < 42 then
        cpuAt = state.time + 1.02
    end
end

local function resetRound()
    state.board, state.player, state.winner = rules.board(), 1, nil
    state.played, state.history, state.focus = 0, "", 4
    state.drop, state.line, state.finishedAt = nil, nil, nil
    state.turnAt = nil
    state.effects, state.hover = {}, nil
    state.openingScores = {state.scores[1], state.scores[2]}
    cpuAt = nil
end

local function endRound(silent)
    if state.winner then
        if state.mode ~= "online" then
            state.scores[state.winner] = state.scores[state.winner] + 1
        end
        if not silent then
            play(state.mode == "solo" and state.winner == 2 and "lose" or "win")
            view.celebrate(state)
        end
    elseif not silent then
        play("draw")
    end
    state.finishedAt = state.time + (silent and -1 or 0.8)
end

local function drop(column, restoring)
    local row = rules.landing(state.board, column)
    if not row or state.winner then return false end
    local actor = state.player
    state.board[row][column] = actor
    state.played = state.played + 1
    state.history = state.history .. column
    state.line = rules.line(state.board, row, column, actor)
    if state.line then state.winner = actor end
    state.player = 3 - actor
    if not restoring then
        state.drop = {row = row, column = column, time = state.time, side = actor}
        state.turnAt = state.time + 0.74
    end
    if state.winner or state.played == 42 then endRound(restoring) end
    if not restoring then
        save()
        scheduleComputer()
    end
    return true
end

local function restore()
    local saved = sdk.load("cats-" .. state.mode)
    local history
    if saved then
        local side, difficulty, cat, dog, moves =
            saved:match("^1:([12]):([123]):([0-2]):([0-2]):([1-7]*)$")
        if side and #moves <= 42 then
            state.side, state.difficulty = tonumber(side), tonumber(difficulty)
            state.scores = {tonumber(cat), tonumber(dog)}
            state.round = state.scores[1] + state.scores[2] + 1
            local metadata = sdk.load("cats-" .. state.mode .. "-round")
            if metadata then
                local round, progress = metadata:match("^([1-9]%d*):(.+)$")
                if progress == saved and #round <= 9 then
                    state.round = math.max(state.round, tonumber(round))
                end
            end
            history = moves
        end
    else
        local legacy = state.mode .. ".save"
        if love.filesystem.getInfo(legacy, "file") then
            local moves = love.filesystem.read(legacy, 43)
            if moves and #moves <= 42 and moves:match("^[1-7]+$") then history = moves end
        end
    end
    resetRound()
    if not history then return false end
    for column in history:gmatch(".") do
        if not drop(tonumber(column), true) then
            state.scores, state.round = {0, 0}, 1
            resetRound()
            return false
        end
    end
    scheduleComputer()
    return true
end

local function readMatch()
    local match = readHost("match", 56)
    if not match or match == previousMatch then return end
    local cells, turn, result, allowed, catWins, dogWins =
        match:match("^([012]+):([12]):([012]):([01]):([0-3]):([0-3])$")
    if not cells then
        cells, turn, result, allowed = match:match("^([012]+):([12]):([012]):([01])$")
    end
    if not cells or #cells ~= 42 then return end
    local board, played, latest = rules.board(), 0, nil
    for index = 1, #cells do
        local row, column = math.floor((index - 1) / 7) + 1, (index - 1) % 7 + 1
        local side = tonumber(cells:sub(index, index))
        board[row][column] = side
        if side ~= 0 then
            played = played + 1
            if state.board[row][column] ~= side then latest = {row = row, column = column, side = side} end
        end
    end
    local boardChanged = played ~= state.played
    local animated = previousMatch and played == state.played + 1 and latest
    local wasFinished = state.finishedAt ~= nil
    previousMatch, moveSent = match, false
    state.board, state.played, state.player = board, played, tonumber(turn)
    state.winner = result ~= "0" and tonumber(result) or nil
    state.scores = {
        tonumber(catWins) or (result == "1" and 1 or 0),
        tonumber(dogWins) or (result == "2" and 1 or 0),
    }
    state.matchReady, state.canMove = true, allowed == "1"
    if animated then
        latest.time, state.drop = state.time, latest
        state.turnAt = state.time + 0.74
    elseif boardChanged then
        state.drop, state.turnAt = nil, nil
    end
    if state.winner or played == 42 then
        if state.winner then
            for row = 1, 6 do
                for column = 1, 7 do
                    if not state.line and board[row][column] == state.winner then
                        state.line = rules.line(board, row, column, state.winner)
                    end
                end
            end
        end
        if not wasFinished then endRound(not animated) end
    elseif wasFinished then
        state.line, state.finishedAt, state.effects = nil, nil, {}
    end
end

local function canPlay()
    if state.phase ~= "board" or state.winner or state.played == 42
        or (state.turnAt and state.time < state.turnAt) then return false end
    if state.mode == "online" then return state.canMove and not moveSent end
    return state.mode ~= "solo" or state.player == 1
end

local function submit(column)
    if not canPlay() or not rules.landing(state.board, column) then return end
    startMusic()
    if state.mode ~= "online" then
        drop(column)
        return
    end
    local file = io.open("/zompado/move", "w")
    if file then
        file:write(tostring(column - 1))
        file:close()
        moveSent = true
    end
end

local function intro()
    state.phase, state.intro = "intro", state.time
    startMusic()
    play("pet_swish")
end

local function startRound()
    if state.scores[1] == 3 or state.scores[2] == 3 then
        state.scores, state.round = {0, 0}, 1
    elseif state.finishedAt then
        state.round = state.round + 1
    end
    resetRound()
    save()
    intro()
end

local function activate(action)
    if action == "cat" or action == "dog" then
        state.side = action == "cat" and 1 or 2
        play("pet_swish")
    elseif action == "difficulty" then
        state.difficulty = state.difficulty % 3 + 1
        play("pet_swish")
    elseif action == "start" then
        startRound()
    elseif action == "intro" then
        state.phase = "board"
        startMusic()
    elseif action == "next" then
        if state.mode == "solo" and (state.scores[1] == 3 or state.scores[2] == 3) then
            state.phase = "choose"
            state.scores, state.round = {0, 0}, 1
        else
            startRound()
        end
    elseif type(action) == "number" then
        state.focus = action
        submit(action)
    end
end

function love.load()
    love.graphics.setDefaultFilter("linear", "linear", 4)
    view.load()
    pcall(initAudio)
    local mode = readHost("mode", 16)
    if mode == "local" or mode == "online" then state.mode = mode end
    resetRound()
    if state.mode == "online" then
        state.phase = "board"
    elseif restore() then
        state.phase = "board"
        startMusic()
    elseif state.mode == "local" then
        intro()
    end
end

function love.update(dt)
    state.time = state.time + dt
    mixer:update(dt)
    local falling = state.drop
    if falling and not falling.landed and state.time - falling.time >= view.dropFall then
        falling.landed = true
        play("land")
    end
    if state.phase == "intro" and state.time - state.intro >= 1.55 then
        state.phase = "board"
    end
    if state.mode == "online" then
        poll = poll + dt
        if poll >= 0.075 then
            poll = 0
            readMatch()
        end
    elseif cpuAt and state.time >= cpuAt then
        cpuAt = nil
        local column = rules.computer(state.board, state.difficulty)
        if column then drop(column) end
    end
    state.playable = canPlay()
end

function love.draw()
    view.draw(state)
end

local function press(pointer, x, y)
    if activePointer then return end
    startMusic()
    activePointer = {id = pointer, action = view.action(state, x, y)}
end

local function release(pointer, x, y)
    if not activePointer or activePointer.id ~= pointer then return end
    local start = activePointer.action
    activePointer = nil
    local action = view.action(state, x, y)
    if start and (start == action or (type(start) == "number" and type(action) == "number")) then
        activate(action)
    end
end

function love.mousepressed(x, y, button, touch)
    if button == 1 and not touch then press(false, x, y) end
end
function love.mousereleased(x, y, button, touch)
    if button == 1 and not touch then release(false, x, y) end
end
function love.mousemoved(x, y, _, _, touch)
    if touch then return end
    local action = view.action(state, x, y)
    state.hover = type(action) == "number" and action or nil
end
function love.touchpressed(id, x, y) press(id, x, y) end
function love.touchmoved(id, x, y)
    if activePointer and activePointer.id == id then
        local action = view.action(state, x, y)
        state.hover = type(action) == "number" and action or nil
    end
end
function love.touchreleased(id, x, y)
    release(id, x, y)
    if not activePointer then state.hover = nil end
end
function love.focus(focused)
    if not focused then activePointer, state.hover = nil, nil end
end

function love.keypressed(key)
    startMusic()
    if state.phase == "choose" then
        if key == "left" then activate("cat") end
        if key == "right" then activate("dog") end
        if key == "return" or key == "space" then activate("start") end
    elseif state.phase == "intro" then
        if key == "return" or key == "space" then activate("intro") end
    elseif key == "return" or key == "space" then
        if state.mode ~= "online" and state.finishedAt and state.time >= state.finishedAt then
            activate("next")
        else
            activate(state.focus)
        end
    elseif key == "left" or key == "right" then
        state.focus = math.max(1, math.min(7, state.focus + (key == "left" and -1 or 1)))
        state.hover = state.focus
    elseif key:match("^[1-7]$") then
        activate(tonumber(key))
    end
end
