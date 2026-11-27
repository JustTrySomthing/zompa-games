local rules = require('rules')
local ui = require('tests.ui_geometry')
local function openingFor(winner)
  for blue=456,600 do
    local seed=(123*181+blue*9973)%2147483647
    if rules.initiative(seed).first==winner then return {123,blue},seed end
  end
  error('missing opening fixture')
end
local nonce,seed=openingFor(1)
local function scenario(accept, seekReward)
  local match=rules.new(seed,1)
  local history={'I'..nonce[1],'I'..nonce[2]}
  local battle
  for _ = 1, 300 do
    local bestMove, bestScore
    for _, action in ipairs(rules.actions(match)) do
      if action.type == 'attack' then
        local after = rules.copy(match)
        local ok, event = rules.apply(after, action)
        if ok and match.turn==1 and accept(event,after) and not after.winner then
          battle = action
          break
        end
        if seekReward and ok and not after.winner then
          local value=60+(event.landed and 8 or 0)+(event.defeated and 4 or 0)
          if not bestScore or value>bestScore then bestMove,bestScore=action,value end
        end
      elseif action.type == 'move' then
        local piece = rules.piece(match,action.id)
        local towardEnemy = match.turn == 1 and piece.r - action.r or action.r - piece.r
        local score = towardEnemy * 10 - math.abs(action.r - 5) - math.abs(action.c - 3)
        if not bestScore or score > bestScore then bestMove, bestScore = action, score end
      end
    end
    if battle then break end
    assert(bestMove, 'could not find legal setup move')
    assert(rules.apply(match, bestMove))
    local token = rules.encode(bestMove)
    history[#history + 1] = token
    if bestMove.type=="attack" then
      history[#history+1]="K"
      if match.last.heal then history[#history+1]="R";history[#history+1]="K" end
      history[#history+1]="C"
    end
  end
  assert(battle and #history >= 2, 'could not reach battle fixture')
  return match,history,battle
end
local function counterattack(state)
  if state.winner then return nil end
  for _,action in ipairs(rules.actions(state)) do
    if action.type=='attack' then
      local trial=rules.copy(state)
      local ok=rules.apply(trial,action)
      if ok and not trial.winner then return action end
    end
  end
end
local match,history,battle=scenario(function(event,after)
  return event.landed and counterattack(after)
end)

local width, height = 390, 700
local function client(side)
  local now, labels = 0, {}
  local outbound,failNextWrite
  local g = {}
  for _, name in ipairs({'setColor','setFont','polygon','setLineWidth','circle','line','rectangle'}) do
    g[name] = function() end
  end
  g.printf = function(label) labels[label] = true end
  g.newFont = function(size) return {size=size} end
  g.getDimensions = function() return width, height end

  local love = {graphics=g, timer={getTime=function() return now end}, math={random=function() return nonce[side] end}}
  local hostFiles = {open=function(path, mode)
    if path == '/zompado/move' then
      assert(mode == 'wb' and not outbound, 'duplicate turn submitted')
      if failNextWrite then
        failNextWrite=false
        return nil,'simulated turn file failure'
      end
      return {write=function(_, value) outbound = value; return true end, close=function() return true end}
    end
    local value
    if path == '/zompado/mode' then
      value = 'online'
    elseif path == '/zompado/opponent' then
      value = side==1 and 'Mira Frost' or 'Charles'
    elseif path == '/zompado/match' then
      value = ('%d:%d:%s'):format(side, (1+#history%2)==side and 1 or 0, table.concat(history, ','))
    end
    return value and {read=function() return value end, close=function() end}
  end}
  local env = setmetatable({love=love, io=hostFiles}, {__index=_G})
  local sdk = assert(loadfile('zompa.lua', 't', env))()
  env.require = function(name) return name == 'zompa' and sdk or require(name) end
  assert(loadfile('main.lua', 't', env))()
  love.load()

  local c = {}
  function c.board() return ui.upvalue(love.draw,'state') end
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
  function c.submit(action,failOnce)
    local piece = rules.piece(match,action.id)
    cell(piece.r, piece.c)
    cell(action.r, action.c)
    local painted = c.step(0)
    if action.type=='attack' then
      assert(painted['ATTACK NOW'])
      assert(painted.Target)
    else assert(painted['MOVE HERE']) end
    local x,y = ui.boxCenter(ui.button(love, 'actionBox'))
    if failOnce then
      failNextWrite=true
      tap(x,y)
      assert(not outbound and c.step(0)['Could not send. Tap again to retry.'])
      assert(ui.button(love,'actionBox'),'failed send must keep the target available')
    end
    tap(x,y)
    tap(x,y) -- Repeated confirmation must not submit a second turn.
    assert(outbound == '-:' .. rules.encode(action), tostring(outbound))
    history[#history + 1] = outbound:sub(3)
    outbound = nil
    assert(rules.apply(match, action))
  end
  function c.start()
    c.step(4.3) -- Allow the launch sequence to hand off to the menu.
    local intro=ui.upvalue(love.draw,'intro')
    tap(ui.boxCenter(assert(intro.start)))
  end
  function c.tapOpening()
    local prompt=ui.upvalue(love.draw,'onlineOpeningPrompt')
    tap(ui.boxCenter(assert(prompt.button)))
  end
  function c.takeHostTurn()
    local token=outbound
    outbound=nil
    return token
  end
  function c.continueBattle()
    local overlay = ui.upvalue(love.draw, 'overlay')
    tap(ui.boxCenter(overlay.button))
  end
  return c
end

local red,blue
local function advanceFlow(owner,observer,token)
  local command=assert(owner.takeHostTurn())
  assert(command=='-:'..token,command)
  history[#history+1]=token
  owner.step(.4);observer.step(.4)
end
for _,reward in ipairs({false,true}) do
  match,history,battle=scenario(function(event,after)
    return (event.heal~=nil)==reward and counterattack(after)
  end,reward)
  red,blue=client(1),client(2)
  red.step(.4);blue.step(.4)
  red.submit(battle,true)
  red.step(.4);blue.step(.4)
  blue.step(.4)
  advanceFlow(blue,red,'K')
  red.step(2);blue.step(2)
  local owner=red.step(10)
  local watcher=blue.step(10)
  assert(not watcher.CONTINUE and not watcher['Roll for Reward'])
  if reward then
    assert(owner['Roll for Reward'])
    red.continueBattle()
    advanceFlow(red,blue,'R')
    blue.step(.4)
    advanceFlow(blue,red,'K')
    owner=red.step(6);watcher=blue.step(6)
    assert(not watcher.CONTINUE)
  end
  assert(owner.CONTINUE)
  red.continueBattle()
  advanceFlow(red,blue,'C')
  red.step(2);blue.step(2)
  local reply=assert(counterattack(match))
  blue.submit(reply)
  assert(red.step(.4)['Blue '..rules.classes[match.last.attackerClass].name..' Attacks'])
end
print('PASS: spectators follow attacker reward and continue commands and can take the next turn')

-- Run the host handshake from a blank match, including Blue winning.
for first=1,2 do
  nonce,seed=openingFor(first)
  match=rules.new(seed,first)
  history={}
  red,blue=client(1),client(2)
  local redIntro,blueIntro=red.step(4.4),blue.step(4.4)
  assert(redIntro['Start Game'] and redIntro['You · Red'] and redIntro['Mira Frost · Blue'])
  assert(not blueIntro['Start Game'] and blueIntro['How to Play'] and blueIntro['You · Blue'] and blueIntro['Charles · Red'])
  red.start()
  assert(red.takeHostTurn()=='-:S')
  history[1]='S'
  blue.step(.4)
  assert(blue.takeHostTurn()=='-:K')
  history[2]='K'
  local redRoll,blueWait=red.step(.4),blue.step(.4)
  assert(redRoll['Roll for First Turn'] and blueWait['Waiting for Charles to roll…'])

  red.step(5);blue.step(5)
  assert(not red.takeHostTurn() and not blue.takeHostTurn(),'setup must wait for inviter')
  red.tapOpening()
  red.step(.4)
  assert(red.takeHostTurn()=='-:I'..nonce[1])
  history[3]='I'..nonce[1]
  blue.step(.4)
  assert(blue.takeHostTurn()=='-:I'..nonce[2])
  history[4]='I'..nonce[2]
  assert(red.step(.4)['Roll for First Turn'])
  assert(blue.step(.4)['Roll for First Turn'])
  red.step(100);blue.step(100)
  red.step(1.1);blue.step(1.1)
  red.step(.4)
  if first==2 then
    assert(red.takeHostTurn()=='-:Y')
    history[5]='Y'
    red.step(.4);blue.step(.4)
  else
    assert(not red.takeHostTurn())
  end
  local openingMove=rules.actions(match)[1]
  local opener=first==1 and red or blue
  opener.submit(openingMove)
  assert(match.moves==1 and match.turn==3-first)
end
print('PASS: online initiative sends setup, supports both first turns and never counts a handoff as a move')

-- Replay a last-Soldier flank attack through two clients, with either kingdom
-- defending, and finish the online handoff before selecting the boulder.
local newBoard=rules.new
for defender=1,2 do
  local attacker=3-defender
  local soldierId=attacker==1 and 12 or 27
  function rules.new(gameSeed,first)
    local board=newBoard(gameSeed,first)
    for _,unit in ipairs(board.units) do unit.hp=0 end
    local fort,soldier=board.forts[defender],board.units[soldierId]
    soldier.hp,soldier.r,soldier.c=16,fort.r,fort.c-1
    return board
  end
  nonce,seed=openingFor(attacker)
  match=rules.new(seed,attacker)
  history={'I'..nonce[1],'I'..nonce[2]}
  if attacker==2 then history[3]='Y' end
  red,blue=client(1),client(2)
  local attackClient,defendClient=attacker==1 and red or blue,defender==1 and red or blue
  red.step(.4);blue.step(.4)
  red.step(100);blue.step(100)
  red.step(2);blue.step(2)
  local fort=match.forts[defender]
  attackClient.submit({type='attack',id=soldierId,r=fort.r,c=fort.c})
  red.step(.4);blue.step(.4)
  defendClient.step(.4)
  advanceFlow(defendClient,attackClient,'K')
  red.step(2);blue.step(2)
  assert(attackClient.step(10).CONTINUE)
  assert(not defendClient.step(10).CONTINUE)
  attackClient.continueBattle()
  advanceFlow(attackClient,defendClient,'C')
  red.step(2);blue.step(2)
  red.step(.4);blue.step(.4)
  assert(not defendClient.takeHostTurn(),'defending client must never send a forced pass')
  local soldier=match.units[soldierId]
  defendClient.submit({type='attack',id=fort.id,r=soldier.r,c=soldier.c})
  red.step(.4);blue.step(.4)
  for _,c in ipairs({red,blue}) do
    local board=c.board()
    assert(board.moves==2 and board.turn==attacker and board.last.attackerClass=='fortress')
    assert(board.forts[defender].armed and board.units[soldierId].hp==soldier.hp)
  end
end
rules.new=newBoard
print('PASS: both online clients agree on the flank attack and Fortress counterattack for either color')
