local rules = require('rules')
local ui = require('tests.ui_geometry')
local nonce = {123, 456}
local seed = (nonce[1] * 181 + nonce[2] * 9973) % 2147483647
local match = rules.new(seed)
local history = {}
local battle
for _ = 1, 30 do
  local bestMove, bestScore
  for _, action in ipairs(rules.actions(match)) do
    if #history>=2 and match.turn == 1 and action.type == 'attack' then
      local after = rules.copy(match)
      local ok, event = rules.apply(after, action)
      if ok and event.heal and event.heal.owner == 1 and not after.winner then
        battle = action
        break
      end
    elseif action.type == 'move' then
      local piece = match.units[action.id]
      local towardEnemy = match.turn == 1 and piece.r - action.r or action.r - piece.r
      local score = towardEnemy * 10 - math.abs(action.r - 5) - math.abs(action.c - 3)
      if not bestScore or score > bestScore then bestMove, bestScore = action, score end
    end
  end
  if battle then break end
  assert(bestMove, 'could not find legal setup move')
  assert(rules.apply(match, bestMove))
  local token = rules.encode(bestMove)
  if #history < 2 then token = 'N' .. nonce[#history + 1] .. '_' .. token end
  history[#history + 1] = token
end
assert(battle and #history >= 2, 'could not reach a Red victory bonus fixture')

local width, height = 390, 700
local function client(side)
  local now, labels = 0, {}
  local outbound
  local g = {}
  for _, name in ipairs({'setColor','setFont','polygon','setLineWidth','circle','line','rectangle'}) do
    g[name] = function() end
  end
  g.printf = function(label) labels[label] = true end
  g.newFont = function(size) return {size=size} end
  g.getDimensions = function() return width, height end

  local love = {graphics=g, timer={getTime=function() return now end}, math=math}
  local hostFiles = {open=function(path, mode)
    if path == '/zompado/move' then
      assert(mode == 'wb' and not outbound, 'duplicate turn submitted')
      return {write=function(_, value) outbound = value; return true end, close=function() return true end}
    end
    local value
    if path == '/zompado/mode' then
      value = 'online'
    elseif path == '/zompado/match' then
      value = ('%d:%d:%s'):format(side, match.turn == side and 1 or 0, table.concat(history, ','))
    end
    return value and {read=function() return value end, close=function() end}
  end}
  local env = setmetatable({love=love, io=hostFiles}, {__index=_G})
  local sdk = assert(loadfile('zompa.lua', 't', env))()
  env.require = function(name) return name == 'zompa' and sdk or require(name) end
  assert(loadfile('main.lua', 't', env))()
  love.load()

  local c = {}
  function c.step(dt)
    now = now + dt
    love.update(dt)
    labels = {}
    love.draw()
    return labels
  end
  local function tap(x, y)
    now = now + .17
    love.touchpressed(1, x, y)
  end
  local function cell(r, col) tap(ui.cell(love, r, col)) end
  function c.submit(action, flee)
    local piece = match.units[action.id]
    cell(piece.r, piece.c)
    cell(action.r, action.c)
    local painted = c.step(0)
    assert(painted[action.type == 'attack' and 'ATTACK NOW' or 'MOVE HERE'], 'missing turn confirmation')
    local x,y = ui.boxCenter(ui.button(love, 'actionBox'))
    tap(x,y)
    tap(x,y)
    if action.type=='attack' then
      assert(not outbound,'opening the battle cannot submit an attack')
      local choice=c.step(3)
      assert(choice.ROLL and choice.FLEE and not outbound,'attacker must choose before submission')
      local overlay=ui.upvalue(love.draw,'overlay')
      if flee then
        tap(ui.boxCenter(overlay.fleeBox))
        c.step(3)
        assert(not outbound,'retreat must not submit an online turn')
        return
      end
      tap(ui.boxCenter(overlay.attackRollBox))
      tap(ui.boxCenter(overlay.attackRollBox))
    end
    assert(outbound == '-:' .. rules.encode(action), tostring(outbound))
    history[#history + 1] = outbound:sub(3)
    outbound = nil
    assert(rules.apply(match, action))
  end
  function c.startBattle()
    local overlay = ui.upvalue(love.draw, 'overlay')
    tap(ui.boxCenter(overlay.attackRollBox))
    assert(not outbound,'defender replay must not submit another turn')
  end
  function c.bonusButton()
    local overlay = ui.upvalue(love.draw, 'overlay')
    tap(ui.boxCenter(overlay.healRollBox or overlay.continueBox))
  end
  return c
end

local red, blue = client(1), client(2)
red.step(.4); blue.step(.4)
red.submit(battle,true)
assert(not blue.step(.4).BATTLE,'opponent must not see a canceled attack')
red.submit(battle)
red.step(.4); blue.step(.4)
local attackerReplay=red.step(3)
assert(not attackerReplay.FLEE,'online attacker must not confirm twice')
local defensePrompt=blue.step(90)
assert(defensePrompt.ROLL and not defensePrompt.FLEE,'defender should be able to start the replay')
assert(not defensePrompt['ROLLING…'],'defender replay must wait for Roll')
blue.startBattle()
assert(red.step(90)['ROLL'], 'Red should get the manual roll')
assert(not blue.step(90)['ROLL'], 'Blue should only observe the reward')
assert(blue.step(2)['CONTINUE'], 'Blue should see the deterministic bonus')
blue.bonusButton()
local reply
for _, action in ipairs(rules.actions(match)) do
  if action.type == 'move' then reply = action; break end
end
assert(reply, 'Blue should have a legal reply')
blue.submit(reply)
assert(red.step(.4)['ROLL'], 'An incoming move interrupted the winner’s bonus prompt')
red.bonusButton()
assert(red.step(2)['CONTINUE'], 'Red should see the bonus result')
red.bonusButton()
assert(red.step(.4)['BLUE KINGDOM MOVES'], 'Red should replay Blue’s reply after dismissing the bonus')
local rejoined = client(1)
assert(rejoined.step(.4)['PLAYER 1  •  CHOOSE A PIECE'], 'Rejoin should load the latest authoritative turn')
print('PASS: two turns-v1 clients, winner-only bonus, incoming turn ordering, and reconnect replay')
