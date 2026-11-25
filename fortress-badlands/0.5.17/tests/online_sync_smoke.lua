local rules = require('rules')
local ui = require('tests.ui_geometry')
local nonce = {123, 456}
local seed = (nonce[1] * 181 + nonce[2] * 9973) % 2147483647
local function scenario(accept)
  local match = rules.new(seed)
  local history = {}
  local battle
  for _ = 1, 30 do
    local bestMove, bestScore
    for _, action in ipairs(rules.actions(match)) do
      if #history>=2 and match.turn == 1 and action.type == 'attack' then
        local after = rules.copy(match)
        local ok, event = rules.apply(after, action)
        if ok and accept(event) and not after.winner then
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
  assert(battle and #history >= 2, 'could not reach battle fixture')
  return match,history,battle
end
local match,history,battle=scenario(function(event) return event.landed end)

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
  function c.submit(action)
    local piece = match.units[action.id]
    cell(piece.r, piece.c)
    cell(action.r, action.c)
    local painted = c.step(0)
    assert(painted[action.type == 'attack' and 'ATTACK NOW' or 'MOVE HERE'])
    local x,y = ui.boxCenter(ui.button(love, 'actionBox'))
    tap(x,y)
    if action.type=='attack' then
      assert(not outbound)
      assert(c.step(0).ROLL)
      local overlay=ui.upvalue(love.draw,'overlay')
      tap(ui.boxCenter(overlay.button))
    end
    tap(x,y)
    assert(outbound == '-:' .. rules.encode(action), tostring(outbound))
    history[#history + 1] = outbound:sub(3)
    outbound = nil
    assert(rules.apply(match, action))
  end
  function c.continueBattle()
    local overlay = ui.upvalue(love.draw, 'overlay')
    tap(ui.boxCenter(overlay.button))
  end
  return c
end

local red,blue=client(1),client(2)
red.step(.4);blue.step(.4)
red.submit(battle)
for i,side in ipairs({red,blue}) do
  local opening=side.step(.4)
  assert(opening['ATTACK ROLL'] and not opening.ROLL)
  local result=side.step(4)
  if match.last.heal then
    if i==1 then assert(result['ROLL FOR BONUS']); side.continueBattle() end
    result=side.step(2)
  end
  assert(result.CONTINUE)
end
blue.continueBattle()
local reply
for _,action in ipairs(rules.actions(match)) do
  if action.type=='move' then reply=action;break end
end
assert(reply)
blue.submit(reply)
assert(red.step(.4).CONTINUE,'incoming move interrupted the battle result')
red.continueBattle()
assert(red.step(.4)['BLUE KINGDOM MOVES'],'opponent reply must animate after dismissing result')
local rejoined=client(1)
assert(rejoined.step(.4)['PLAYER 1  •  CHOOSE A PIECE'])
print('PASS: both online clients replay one deterministic D12 attack, then sync the next turn')
