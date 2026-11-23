-- Fortress: The Badlands — Zompa SDK v4 / LÖVE 11.5 graybox prototype.
-- This game's deterministic rules are shared by solo, pass-and-play, and turns-v1 online.
local rules = require('rules')
local zompa = require('zompa')
local mode = 'solo'
local state, onlineSide, onlineAllowed, onlineReady, lastOnlineCount
local selected, inspected, targets, pending, overlay
local layout, timers, notice, blocked = {}, {cpu=0,poll=0,dialog=0}, '', nil
local palette = {
  sky={0.055,0.075,0.115}, top={0.18,0.27,0.43}, bottom={0.37,0.17,0.20},
  waste={0.30,0.28,0.23}, border={0.08,0.09,0.12}, gold={0.93,0.76,0.45},
  green={0.21,0.79,0.48}, red={0.96,0.38,0.34}, text={0.94,0.93,0.88},
}
local fonts={}
local mixer = zompa.audio()
local function color(p,a) love.graphics.setColor(p[1],p[2],p[3],a or 1) end
local function text(str,x,y,w,align,font)
  color(palette.text)
  love.graphics.setFont(font or fonts.small)
  love.graphics.printf(tostring(str),x,y,w,align or 'center')
end
local function center(r,c)
  local size=layout.tileW
  return layout.x+(c+(r%2)*0.5)*size,layout.y+r*layout.rowH
end
local function xyToCell(x,y)
  local chosen,best=nil,math.huge
  local row=math.floor((y-layout.y)/layout.rowH+0.5)
  for r=math.max(0,row-1),math.min(rules.ROWS-1,row+1) do
    for c=0,rules.COLS-1 do
      local cx,cy=center(r,c);local dx,dy=x-cx,y-cy
      local d=dx*dx+dy*dy
      if d<best then chosen,best={r=r,c=c},d end
    end
  end
  if best>layout.radius*layout.radius*1.2 then return nil end
  return chosen
end
local function reflow(w,h)
  local top=49
  local bottom=h-119
  local rw=(w-14)/(math.sqrt(3)*7.5)
  local rh=(bottom-top)/(2+1.5*(rules.ROWS-1))
  local radius=math.max(10,math.min(rw,rh))
  local tw=math.sqrt(3)*radius
  layout={w=w,h=h,radius=radius,tileW=tw,rowH=radius*1.5,
    x=(w-tw*7.5)/2+tw/2,y=top+radius,cardY=h-111}
  fonts.small=love.graphics.newFont(math.max(11,math.min(16,w/28)))
  fonts.medium=love.graphics.newFont(math.max(13,math.min(20,w/21)))
  fonts.large=love.graphics.newFont(math.max(17,math.min(25,w/15)))
end
local function faceHex(cx,cy,r)
  local coords={}
  for i=0,5 do
    local a=math.rad(i*60-90)
    coords[#coords+1]=cx+r*math.cos(a)
    coords[#coords+1]=cy+r*math.sin(a)
  end
  return coords
end
local function drawBoard()
  for r=0,rules.ROWS-1 do
    for c=0,rules.COLS-1 do
      local cx,cy=center(r,c)
      local terrain=r<=4 and palette.top or r>=8 and palette.bottom or palette.waste
      local tint=((r+c)%3)*0.04
      love.graphics.setColor(terrain[1]+tint,terrain[2]+tint,terrain[3]+tint)
      love.graphics.polygon('fill',faceHex(cx,cy,layout.radius-0.5))
      color(palette.border,0.70);love.graphics.setLineWidth(1.2)
      love.graphics.polygon('line',faceHex(cx,cy,layout.radius-0.5))
    end
  end
  if selected and not overlay and state and not state.winner then
    color(palette.green,0.36)
    for k,_ in pairs(targets.moves or {}) do
      local r,c=rules.fromkey(k);local cx,cy=center(r,c)
      love.graphics.circle('fill',cx,cy,layout.radius*0.32)
    end
    color(palette.red,0.55)
    for k,_ in pairs(targets.attacks or {}) do
      local r,c=rules.fromkey(k);local cx,cy=center(r,c)
      love.graphics.circle('line',cx,cy,layout.radius*0.68)
    end
  end
  for _,fort in ipairs(state.forts) do
    local cx,cy=center(fort.r,fort.c)
    color(fort.owner==1 and palette.bottom or palette.top)
    love.graphics.circle('fill',cx,cy,layout.radius*0.75)
    color(palette.gold)
    love.graphics.setLineWidth(2);love.graphics.circle('line',cx,cy,layout.radius*0.75)
    love.graphics.setFont(fonts.medium)
    love.graphics.printf('F',cx-layout.radius,cy-layout.radius*0.44,layout.radius*2,'center')
    local barW=layout.radius*1.18
    love.graphics.setColor(0.06,0.07,0.08,0.9)
    love.graphics.rectangle('fill',cx-barW/2,cy+layout.radius*0.38,barW,3.8)
    color(palette.gold)
    love.graphics.rectangle('fill',cx-barW/2,cy+layout.radius*0.38,barW*(fort.hp/rules.FORT_HP),3.8)
  end
  for _,u in ipairs(state.units) do
    if u.hp>0 then
      local cx,cy=center(u.r,u.c)
      local selectedThis=selected==u.id or inspected==u.id
      color(u.owner==1 and {0.79,0.45,0.43} or {0.49,0.67,0.85})
      love.graphics.circle('fill',cx,cy,layout.radius*0.61)
      color(selectedThis and palette.gold or palette.border)
      love.graphics.setLineWidth(selectedThis and 2.8 or 1.2)
      love.graphics.circle('line',cx,cy,layout.radius*0.61)
      color(palette.border)
      love.graphics.setFont(fonts.small)
      local label=rules.classes[u.class].mark
      love.graphics.printf(label,cx-layout.radius*0.55,cy-layout.radius*0.39,layout.radius*1.1,'center')
      local barW=layout.radius*0.94
      local x,y=cx-barW/2,cy+layout.radius*0.34
      love.graphics.setColor(0.07,0.09,0.09)
      love.graphics.rectangle('fill',x,y,barW,3.5)
      color(u.hp/rules.classes[u.class].hp<0.35 and palette.red or palette.green)
      love.graphics.rectangle('fill',x,y,barW*(u.hp/rules.classes[u.class].hp),3.5)
    end
  end
end
local function drawHeader()
  color(palette.text)
  love.graphics.setFont(fonts.medium)
  local title=state and state.winner and 'MATCH COMPLETE' or state and ('PLAYER '..state.turn..' TURN') or 'FORTRESS'
  love.graphics.printf(title,0,4,layout.w,'center')
  local p1,p2=state.forts[1].hp,state.forts[2].hp
  text(('P1 FORT %d/%d'):format(p1,rules.FORT_HP),8,27,layout.w*0.43,'left',fonts.small)
  text(('P2 FORT %d/%d'):format(p2,rules.FORT_HP),layout.w*0.54,27,layout.w*0.44,'right',fonts.small)
end
local function currentUnit()
  if not state then return nil end
  return selected and state.units[selected] or inspected and state.units[inspected]
end
local function drawCard()
  local y,h=layout.cardY,106
  love.graphics.setColor(0.095,0.115,0.16,0.96)
  love.graphics.rectangle('fill',6,y,layout.w-12,h,10,10)
  color(palette.gold,0.5)
  love.graphics.rectangle('line',6,y,layout.w-12,h,10,10)
  local u=currentUnit()
  if u and u.hp>0 then
    local p=rules.classes[u.class]
    text(p.name..'  ·  Player '..u.owner,13,y+8,layout.w-26,'left',fonts.medium)
    text(('HP %d/%d  |  Move %d  |  Attack %d  |  D%d'):format(u.hp,p.hp,p.move,p.attack,p.die),13,y+40,layout.w-26,'left',fonts.small)
    text('Green = move   ·   Red = attack',13,y+70,layout.w-26,'left',fonts.small)
  elseif inspected=='fort' then
    local p=state.forts[3-state.turn]
    text('Enemy Fortress',13,y+9,layout.w-26,'left',fonts.medium)
    text(('Health: %d/%d    Defense: D8'):format(p.hp,rules.FORT_HP),13,y+43,layout.w-26,'left',fonts.small)
    text('Destroy the Fortress to win.',13,y+72,layout.w-26,'left',fonts.small)
  else
    text('Select a soldier',13,y+10,layout.w-26,'left',fonts.medium)
    local msg=notice~='' and notice or 'Move or attack with one soldier per turn.'
    text(msg,13,y+46,layout.w-26,'left',fonts.small)
  end
end
local function panel(x,y,w,h)
  love.graphics.setColor(0.045,0.062,0.09,0.97)
  love.graphics.rectangle('fill',x,y,w,h,12,12)
  color(palette.gold);love.graphics.setLineWidth(2)
  love.graphics.rectangle('line',x,y,w,h,12,12)
end
local function battleFrame()
  local event=overlay.event
  local count=event.rounds and #event.rounds or 0
  local shown=math.min(math.floor(overlay.elapsed/0.72),count)
  overlay.shown=shown
  local round=event.rounds and event.rounds[shown] or nil
  return shown,count,round
end
local function drawBattleOverlay()
  local w,h=layout.w,layout.h
  love.graphics.setColor(0,0,0,0.74);love.graphics.rectangle('fill',0,0,w,h)
  local x,y,ww,hh=w*0.06,h*0.22,w*0.88,math.min(360,h*0.57)
  panel(x,y,ww,hh)
  local event=overlay.event
  local shown,count,round=battleFrame()
  text(event.defender=='fort' and 'FORTRESS ASSAULT' or 'DICE BATTLE',x+12,y+13,ww-24,'center',fonts.large)
  text(('Round %d / %d'):format(shown,count),x+12,y+53,ww-24,'center',fonts.small)
  local a=round and round.attackerHp or event.attackerHpStart
  local d=round and round.defenderHp or event.defenderHpStart
  local an=rules.classes[event.attackerClass]
  local dn=rules.classes[event.defenderClass]
  text(('Attacker · %s · D%d'):format(an.name,an.die),x+15,y+90,ww*0.5-17,'left',fonts.small)
  text(('Defender · %s · D%d'):format(dn and dn.name or 'Fortress',dn and dn.die or rules.FORT_DIE),x+ww*0.51,y+90,ww*0.48-15,'left',fonts.small)
  text(('HP %d / %d'):format(a, event.attackerHpStart),x+15,y+124,ww*0.46,'left',fonts.medium)
  text(('HP %d / %d'):format(d,event.defenderHpStart),x+ww*0.51,y+124,ww*0.45,'left',fonts.medium)
  local dmg=round and ('Attacker rolls %d  ·  Defender rolls %d'):format(round.a,round.b) or 'Both roll simultaneously.'
  text(dmg,x+12,y+167,ww-24,'center',fonts.small)
  local done=shown>=count
  if done then
    local final='Both troops defeated.'
    if event.winner and event.finish=='fortress' then final='FORTRESS DESTROYED!' end
    if event.attackerHpEnd>0 then final='Attacker wins!' end
    if event.defenderHpEnd>0 then final=event.defender=='fort' and 'Fortress holds!' or 'Defender wins!' end
    if event.finish=='fortress' then final='FORTRESS DESTROYED!' end
    text(final,x+12,y+207,ww-24,'center',fonts.medium)
    if event.heal then
      text(('Victory potion: +%d HP'):format(event.heal.actual),x+12,y+239,ww-24,'center',fonts.small)
    end
    local by=y+hh-56
    love.graphics.setColor(0.28,0.57,0.40)
    love.graphics.rectangle('fill',x+ww*0.19,by,ww*0.62,42,9,9)
    text('CONTINUE',x+ww*0.2,by+10,ww*0.60,'center',fonts.medium)
    overlay.continueBox={x=x+ww*0.19,y=by,w=ww*0.62,h=42}
  else
    overlay.continueBox=nil
    text('Resolving simultaneous rolls…',x+12,y+228,ww-24,'center',fonts.small)
  end
end
local function drawSiegeOverlay()
  local w,h=layout.w,layout.h
  love.graphics.setColor(0,0,0,0.8);love.graphics.rectangle('fill',0,0,w,h)
  local x,y,ww,hh=w*0.06,h*0.21,w*0.88,math.min(390,h*0.61)
  panel(x,y,ww,hh)
  text('THE FINAL SIEGE',x+9,y+14,ww-18,'center',fonts.large)
  text('Both armies have fallen. The trebuchets fire.',x+9,y+51,ww-18,'center',fonts.small)
  local rounds=overlay.rounds
  local shown=math.min(math.floor(overlay.elapsed/0.85),#rounds)
  overlay.shown=shown
  local now=rounds[shown]
  local previous=rounds[shown-1]
  local fort1=now and now.h1 or previous and previous.h1 or overlay.start.h1
  local fort2=now and now.h2 or previous and previous.h2 or overlay.start.h2
  text(('P1 Fortress: %d HP'):format(fort1),x+12,y+100,ww-24,'center',fonts.medium)
  text(('P2 Fortress: %d HP'):format(fort2),x+12,y+138,ww-24,'center',fonts.medium)
  text(now and ('Trebuchet rolls: %d vs %d'):format(now.a,now.b) or 'Rolling D12 for each kingdom',x+12,y+184,ww-24,'center',fonts.small)
  if shown==#rounds then
    if state.winner==0 then
      text('MUTUALLY ASSURED DESTRUCTION',x+12,y+222,ww-24,'center',fonts.medium)
      text('Two kingdoms, each determined to conquer the other. In the end, both lost everything.',x+18,y+250,ww-36,'center',fonts.small)
    else
      text(('PLAYER %d CONQUERS!'):format(state.winner),x+12,y+235,ww-24,'center',fonts.large)
    end
    local by=y+hh-56
    love.graphics.setColor(0.28,0.57,0.40)
    love.graphics.rectangle('fill',x+ww*0.19,by,ww*0.62,42,9,9)
    text('CONTINUE',x+ww*0.2,by+10,ww*0.60,'center',fonts.medium)
    overlay.continueBox={x=x+ww*0.19,y=by,w=ww*0.62,h=42}
  else
    overlay.continueBox=nil
  end
end
local function drawFinished()
  love.graphics.setColor(0,0,0,0.63);love.graphics.rectangle('fill',0,0,layout.w,layout.h)
  local x,y,w,h=layout.w*.06,layout.h*.31,layout.w*.88,layout.h*.32
  panel(x,y,w,h)
  text(state.winner==0 and 'MUTUALLY ASSURED DESTRUCTION' or ('PLAYER '..state.winner..' WINS!'),x+12,y+25,w-24,'center',fonts.large)
  if state.winner==0 then
    text('Two kingdoms, each determined to conquer the other. In the end, both lost everything.',x+18,y+91,w-36,'center',fonts.small)
  else
    text('The enemy Fortress has fallen.',x+12,y+91,w-24,'center',fonts.medium)
  end
  text('Use Zompa Back to leave the game.',x+12,y+h-42,w-24,'center',fonts.small)
end
local function showEvent(event)
  selected,inspected,targets=nil,nil,{}
  if event and event.type=='attack' then
    overlay={type='battle',event=event,elapsed=-0.3,shown=0}
  elseif event and event.siege then
    overlay={type='siege',rounds=event.siege,start=event.siegeStart,elapsed=-0.3,shown=0}
  end
end
local function sessionSave()
  if mode=='online' then return end
  local ok,err
  if state.winner~=nil then ok,err=zompa.clearSession()
  else ok,err=zompa.saveSession(rules.serialize(state)) end
  if not ok then print('Session save failed: '..tostring(err)) end
end
local function localAction(action)
  local ok,event=rules.apply(state,action)
  if not ok then notice=event;return false end
  sessionSave();showEvent(event)
  return true
end
local function unwrapOnline(raw)
  local tokens,nonces={},{}
  for i,token in ipairs(raw) do
    if i<=2 then
      local number,action=token:match('^N(%d+)_(.+)$')
      if not number or #number>10 or tonumber(number)<1 or tonumber(number)>2147483646 then
        return nil,nil,'Invalid match seed token at turn '..i
      end
      nonces[i]=tonumber(number);tokens[i]=action
    else
      if token:find('^N') then return nil,nil,'Unexpected match seed.' end
      tokens[i]=token
    end
  end
  -- Two separate players provide nonces before any dice combat can occur.
  -- This synchronizes replay across phones; a host-managed unbiased RNG would
  -- still be preferable for competitive cheat resistance in a later SDK.
  local seed=47061
  if #raw>=2 then
    seed=(nonces[1]*181 + nonces[2]*9973)%2147483647
    if seed==0 then seed=1 end
  end
  return tokens,seed,nil
end
local function readOnline()
  local history,side,allowed=zompa.readTurns()
  if not history then onlineReady=false;return end
  onlineReady,onlineSide,onlineAllowed=true,side,allowed
  if #history==lastOnlineCount then return end
  local tokens,seed,parseError=unwrapOnline(history)
  if parseError then blocked=parseError;onlineAllowed=false;return end
  local newState,errorMessage=rules.replay(seed,tokens)
  if not newState then blocked=errorMessage;onlineAllowed=false;return end
  blocked=nil
  local oldCount=lastOnlineCount or 0
  state=newState
  if #history==oldCount+1 and newState.last then showEvent(newState.last) end
  lastOnlineCount=#history
  pending=false
end
local function sendOnline(action)
  if pending or not onlineReady or not onlineAllowed or state.turn~=onlineSide then return end
  local tentative=rules.copy(state)
  local ok,result=rules.apply(tentative,action)
  if not ok then notice=result;return end
  local outcome=tentative.winner -- nil for ongoing; 0 for MAD
  local token=rules.encode(action)
  if #state.history<2 then
    token='N'..tostring(love.math.random(1,2147483646))..'_'..token
  end
  local sent,err=zompa.submitTurn(token,outcome)
  if sent then pending=true;notice='Sending move…' else notice=tostring(err) end
end
local function mayAct()
  return state and not state.winner and not overlay and not blocked and
    (mode=='online' and onlineReady and onlineAllowed and state.turn==onlineSide and not pending or
    mode=='solo' and state.turn==1 or mode=='local')
end
local function actorAction(action)
  if not mayAct() then return end
  if mode=='online' then sendOnline(action) else localAction(action) end
end
local function computerAction()
  if state.winner or state.turn~=2 or overlay then return end
  local all=rules.actions(state)
  if #all==0 then return end
  local ownF,otherF=state.forts[2],state.forts[1]
  local closestEnemyDist={}
  for _,u in ipairs(state.units) do
    if u.owner==2 and u.hp>0 then
      local best=99
      for _,e in ipairs(state.units) do
        if e.owner==1 and e.hp>0 then best=math.min(best,rules.distance(u,e)) end
      end
      closestEnemyDist[u.id]=best
    end
  end
  local best,bestScore=nil,-1e99
  for _,a in ipairs(all) do
    local score=0
    if a.type=='attack' then
      local u=state.units[a.id]
      local target=rules.occupied(state,a.r,a.c)
      if target and target.kind=='fort' then
        -- Do not blindly suicide on the Fortress with a near-dead unit.
        score=20+(otherF.hp<12 and 30 or 0)+u.hp*0.22
      else
        local v=target and target.ref
        local own=rules.classes[u.class]
        local enemy=v and rules.classes[v.class]
        score=22+(enemy and enemy.hp or 12)*0.08
        score=score+(v and (enemy.hp-v.hp)*0.20 or 0)
        score=score+(u.hp>own.hp*.6 and 7 or -4)
        if v and rules.distance(v,ownF)<=3 then score=score+18 end
      end
    elseif a.type=='move' then
      local u=state.units[a.id]
      local prev=rules.distance(u,otherF)
      local nextDist=rules.distance(a,otherF)
      local urgency=0
      for _,enemy in ipairs(state.units) do
        if enemy.owner==1 and enemy.hp>0 then
          local d=rules.distance(enemy,ownF)
          if d<=3 then urgency=urgency+9 end
        end
      end
      local defender=rules.distance(a,ownF)
      score=(prev-nextDist)*4.8 + (nextDist<=3 and 3 or 0)
      score=score+(urgency>0 and (5-defender)*2.8 or 0)
      score=score+(u.hp<rules.classes[u.class].hp*.45 and defender<4 and 6 or 0)
      score=score+(closestEnemyDist[u.id]<=2 and -1.6 or 0)
      if state.last and state.last.type=='move' and state.last.id==a.id
        and state.last.from and a.r==state.last.from.r and a.c==state.last.from.c then score=score-17 end
      if nextDist>prev then score=score-3 end
    else score=-10 end
    score=score+love.math.random()*1.1
    if score>bestScore then best,bestScore=a,score end
  end
  if best then localAction(best) end
end
local function onTap(x,y)
  if not state then return end
  if overlay then
    local b=overlay.continueBox
    if not b or x<b.x or y<b.y or x>b.x+b.w or y>b.y+b.h then return end
    if overlay.type=='battle' and overlay.event.siege then
      overlay={type='siege',rounds=overlay.event.siege,start=overlay.event.siegeStart,elapsed=-0.3,shown=0}
    else overlay=nil end
    return
  end
  if state.winner then return end
  local cell=xyToCell(x,y)
  if not cell then return end
  local t=rules.occupied(state,cell.r,cell.c)
  if selected and mayAct() then
    local k=rules.key(cell.r,cell.c)
    if (targets.moves or {})[k] then actorAction({type='move',id=selected,r=cell.r,c=cell.c});return end
    if (targets.attacks or {})[k] then actorAction({type='attack',id=selected,r=cell.r,c=cell.c});return end
  end
  selected,inspected,targets=nil,nil,{}
  if t and t.kind=='unit' then
    inspected=t.ref.id
    if t.owner==state.turn and mayAct() then
      selected=t.ref.id
      targets={moves=rules.moves(state,selected),attacks=rules.attacks(state,selected)}
    end
  elseif t and t.kind=='fort' then
    inspected='fort'
  end
end
local lastTapAt=-10
local function touch(x,y)
  local now=love.timer.getTime()
  if now-lastTapAt<0.09 then return end
  lastTapAt=now
  onTap(x,y)
end
function love.load()
  mode=zompa.mode()
  local seed=mode=='online' and 47061 or love.math.random(1,2147483600)
  state=rules.new(seed)
  if mode~='online' then
    local saved=zompa.loadSession()
    if saved then
      local restored,err=rules.restore(saved)
      if restored then state=restored else print('Ignoring invalid saved session: '..tostring(err)) end
    end
  end
  selected,inspected,targets,pending,overlay=nil,nil,{},false,nil
  if mode=='online' then lastOnlineCount=-1 end
  reflow(love.graphics.getDimensions())
end
function love.resize(w,h) reflow(w,h) end
function love.update(dt)
  mixer:update(dt)
  if mode=='online' then
    timers.poll=timers.poll+dt
    if timers.poll>=0.34 then timers.poll=0;readOnline() end
  end
  if overlay then overlay.elapsed=overlay.elapsed+dt end
  if state and not state.winner and not overlay and not pending then
    if mode=='solo' and state.turn==2 then
      timers.cpu=timers.cpu+dt
      if timers.cpu>0.55 then timers.cpu=0;computerAction() end
    elseif mode=='online' and onlineAllowed and onlineReady and state.turn==onlineSide
      and rules.count(state,state.turn)==0 then
      -- Zompa turns-v1 alternates strictly: a side with no soldiers submits a legal pass.
      sendOnline({type='pass'})
    elseif mode=='local' and rules.count(state,state.turn)==0 then
      localAction({type='pass'})
    elseif mode=='solo' and state.turn==1 and rules.count(state,1)==0 then
      localAction({type='pass'})
    end
  end
end
function love.draw()
  if not state then return end
  color(palette.sky);love.graphics.rectangle('fill',0,0,layout.w,layout.h)
  drawHeader();drawBoard();drawCard()
  if blocked then
    text('Online sync error: '..blocked,8,layout.h*.43,layout.w-16,'center',fonts.medium)
  end
  if overlay and overlay.type=='battle' then drawBattleOverlay()
  elseif overlay and overlay.type=='siege' then drawSiegeOverlay()
  elseif state.winner~=nil then drawFinished() end
end
function love.mousepressed(x,y,button) if button==1 then touch(x,y) end end
function love.touchpressed(_,x,y) touch(x,y) end
function love.keypressed(key)
  if key=='escape' then selected,inspected,targets=nil,nil,{} end
end
