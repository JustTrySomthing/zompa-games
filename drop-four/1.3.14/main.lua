local rules = require("rules")
local view = require("view")
local sdk = require("zompa")
local mixer = sdk.audio()
local sounds = {}
local state = {
    mode = "solo", side = 1, difficulty = 2, scores = {0, 0}, intro = 0, round = 1,
    time = 0, focus = 4, phase = "choose",
}
local activePointer
local poll = 0
local onlineTurns = 0
local onlinePlayer
local cpuAt
local moveSent = false

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
    local progress = ("2:%d:%d:%d:%d:%d:%s"):format(state.side, state.difficulty,
        state.openingScores[1], state.openingScores[2], state.round, state.history)
    local ok, err = sdk.saveSession(progress)
    if not ok then print(err) end
    return ok
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
    state.celebrating, state.hover = nil, nil
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
            state.celebrating = true
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
        if state.scores[1] == 3 or state.scores[2] == 3 then
            local ok, err = sdk.clearSession()
            if not ok then print(err) end
        else
            save()
        end
        scheduleComputer()
    end
    return true
end

-- Older releases used game-specific slots. Read them once for in-place upgrades.
local function readLegacySession()
    local slot = "cats-" .. state.mode
    local saved = sdk.load(slot)
    if saved then
        local side, difficulty, cat, dog, moves =
            saved:match("^1:([12]):([123]):([0-2]):([0-2]):([1-7]*)$")
        if not side then return nil end
        local round = tonumber(cat) + tonumber(dog) + 1
        local metadata = sdk.load(slot .. "-round")
        if metadata then
            local number, progress = metadata:match("^([1-9]%d*):(.+)$")
            if progress == saved and #number <= 9 then
                round = math.max(round, tonumber(number))
            end
        end
        return ("2:%s:%s:%s:%s:%d:%s"):format(side, difficulty, cat, dog, round, moves)
    end
    local legacy = state.mode .. ".save"
    if love.filesystem.getInfo(legacy, "file") then
        local moves = love.filesystem.read(legacy, 43)
        if moves and moves:match("^[1-7]+$") then return "2:1:2:0:0:1:" .. moves end
    end
end

local function restore()
    local session = sdk.loadSession()
    local legacy = not session and readLegacySession()
    local saved = session or legacy
    local history
    if saved then
        local side, difficulty, cat, dog, round, moves =
            saved:match("^2:([12]):([123]):([0-2]):([0-2]):([1-9]%d*):([1-7]*)$")
        if side and #moves <= 42 and #round <= 9 then
            state.side, state.difficulty = tonumber(side), tonumber(difficulty)
            state.scores = {tonumber(cat), tonumber(dog)}
            state.round, history = tonumber(round), moves
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
    if legacy and save() then
        local slot = "cats-" .. state.mode
        sdk.clear(slot)
        sdk.clear(slot .. "-round")
        love.filesystem.remove(state.mode .. ".save")
    end
    scheduleComputer()
    return true
end

-- A turn token is the selected column. Both devices replay the same rules.
local function readMatch()
    local history, player, allowed = sdk.readTurns()
    if not history then return end
    onlinePlayer, state.matchReady, state.canMove = player, true, allowed
    if #history == onlineTurns then return end

    -- Rebuild delivered moves so a resumed match cannot depend on local state.
    state.scores, state.round = {0, 0}, 1
    resetRound()
    local latest
    for index, token in ipairs(history) do
        local column = tonumber(token)
        if not column or not rules.landing(state.board, column) then
            state.canMove = false
            print("Invalid Cats vs Dogs turn at " .. index)
            return
        end
        local row, actor = rules.landing(state.board, column), state.player
        drop(column, true)
        latest = {row = row, column = column, side = actor, time = state.time}
        if state.winner then state.scores[state.winner] = state.scores[state.winner] + 1 end
        if state.finishedAt and index < #history then
            if state.scores[1] == 3 or state.scores[2] == 3 then
                state.canMove = false
                return
            end
            state.round = state.round + 1
            resetRound()
            state.player = index % 2 + 1
        end
    end
    if #history == onlineTurns + 1 and latest then
        state.drop, state.turnAt = latest, state.time + 0.74
        if state.finishedAt then endRound(false) end
    end
    onlineTurns, moveSent = #history, false
end

local function nextOnlineRound()
    local matchOver = state.scores[1] == 3 or state.scores[2] == 3
    if not state.finishedAt or matchOver or state.time < state.finishedAt + 1 then return end
    state.round = state.round + 1
    resetRound()
    state.player = onlineTurns % 2 + 1
end

local function canPlay()
    if state.phase ~= "board" or state.winner or state.played == 42
        or (state.turnAt and state.time < state.turnAt) then return false end
    if state.mode == "online" then return state.canMove and state.player == onlinePlayer and not moveSent end
    return state.mode ~= "solo" or state.player == 1
end

local function submit(column)
    if not canPlay() or not rules.landing(state.board, column) then return end
    startMusic()
    if state.mode ~= "online" then
        drop(column)
        return
    end
    local row = rules.landing(state.board, column)
    local actor = state.player
    state.board[row][column] = actor
    local wins = rules.line(state.board, row, column, actor)
    state.board[row][column] = 0
    local outcome = wins and state.scores[actor] == 2 and actor or nil
    local sent, err = sdk.submitTurn(tostring(column), outcome)
    if sent then moveSent = true else print(err) end
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
    state.mode = sdk.mode()
    resetRound()
    if state.mode == "online" then
        state.phase = "board"
    elseif restore() then
        state.phase = "board"
        startMusic()
    elseif state.mode == "local" then
        save()
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
        nextOnlineRound()
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
        if view.canAdvance(state) then
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
