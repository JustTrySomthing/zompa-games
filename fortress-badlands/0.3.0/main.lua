-- Fortress: The Badlands — Zompa SDK v4 / LÖVE 11.5 graybox prototype.
-- This game's deterministic rules are shared by solo, pass-and-play, and turns-v1 online.
local rules = require('rules')
local zompa = require('zompa')
local mode = 'solo'
local state, onlineSide, onlineAllowed, onlineReady, lastOnlineCount
local selected, inspected, targets, pending, overlay, intended, actionBox, cancelBox, inspectedFortOwner
local layout, timers, notice, blocked = {}, {cpu=0,poll=0,dialog=0}, '', nil
local palette = {
  sky={0.055,0.075,0.115}, top={0.18,0.27,0.43}, bottom={0.37,0.17,0.20},
  waste={0.30,0.28,0.23}, border={0.08,0.09,0.12}, gold={0.93,0.76,0.45},
  green={0.21,0.79,0.48}, red={0.96,0.38,0.34}, text={0.94,0.93,0.88},
}
-- Strong class identities are drawn as vectors, independent of finished artwork.
local classColors={
  warrior={0.13,0.49,0.53}, barbarian={0.68,0.32,0.19},
  archer={0.26,0.51,0.31}, wizard={0.48,0.32,0.68},
  knight={0.32,0.47,0.67},
}
local teamColors={[1]={0.98,0.52,0.43},[2]={0.43,0.67,0.98}}
local fonts={}
local mixer = zompa.audio()
local function color(p,a) love.graphics.setColor(p[1],p[2],p[3],a or 1) end
local function text(str,x,y,w,align,font)
  color(palette.text)
  love.graphics.setFont(font or fonts.small)
  love.graphics.printf(tostring(str),x,y,w,align or 'center')
end
-- Square grid positions; visible hexagons are inset in every FULL square.
local function center(r,c)
  return layout.x+(c+.5)*layout.cell,layout.y+(r+.5)*layout.cell
end
local function xyToCell(x,y)
  local c=math.floor((x-layout.x)/layout.cell)
  local r=math.floor((y-layout.y)/layout.cell)
  if r<0 or r>=rules.ROWS or c<0 or c>=rules.COLS then return nil end
  return {r=r,c=c}
end
local function reflow(w,h)
  -- The host supplies the game canvas without the Zompa title bar.
  -- A single 42-pixel confirm strip is the only permanently reserved UI.
  local edge=3
  local actionHeight=42
  local usableH=h-actionHeight-edge*2
  local cell=math.min((w-edge*2)/rules.COLS,usableH/rules.ROWS)
  -- Keep all 84 squares fully visible, centered and equally sized.
  layout={w=w,h=h,cell=cell,radius=cell*.475,tileW=cell,rowH=cell,
    x=(w-rules.COLS*cell)/2,y=edge+(usableH-rules.ROWS*cell)/2,
    actionY=h-actionHeight-2}
  fonts.small=love.graphics.newFont(math.max(10,math.min(15,cell*.26)))
  fonts.medium=love.graphics.newFont(math.max(12,math.min(19,cell*.38)))
  fonts.large=love.graphics.newFont(math.max(16,math.min(24,cell*.47)))
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
local function emblem(kind,cx,cy,rad)
  -- Each symbol differs in silhouette and color (color is never the sole cue).
  love.graphics.setColor(0.985,0.975,0.88,1)
  love.graphics.setLineWidth(math.max(1.5,rad*0.14))
  if kind=='warrior' then
    love.graphics.line(cx-rad*.55,cy+rad*.6,cx+rad*.53,cy-rad*.52)
    love.graphics.line(cx-rad*.52,cy-rad*.45,cx+rad*.51,cy+rad*.54)
    love.graphics.line(cx-rad*.65,cy+rad*.40,cx-rad*.35,cy+rad*.69)
  elseif kind=='barbarian' then
    love.graphics.line(cx-rad*.43,cy+rad*.73,cx+rad*.43,cy-rad*.72)
    love.graphics.polygon('fill',cx+rad*.16,cy-rad*.60,cx+rad*.76,cy-rad*.48,
      cx+rad*.55,cy-rad*.01,cx+rad*.08,cy-rad*.25)
  elseif kind=='archer' then
    love.graphics.line(cx-rad*.48,cy-rad*.70,cx-rad*.1,cy-rad*.35,
      cx+rad*.04,cy,cx-rad*.1,cy+rad*.35,cx-rad*.48,cy+rad*.70)
    love.graphics.line(cx-rad*.48,cy-rad*.70,cx-rad*.48,cy+rad*.70)
    love.graphics.line(cx-rad*.72,cy,cx+rad*.69,cy)
    love.graphics.polygon('fill',cx+rad*.77,cy,cx+rad*.36,cy-rad*.24,cx+rad*.36,cy+rad*.24)
  elseif kind=='wizard' then
    love.graphics.line(cx-rad*.4,cy+rad*.75,cx+rad*.38,cy-rad*.65)
    love.graphics.polygon('fill',cx+rad*.38,cy-rad*.94,cx+rad*.49,cy-rad*.6,
      cx+rad*.82,cy-rad*.54,cx+rad*.49,cy-rad*.41,cx+rad*.38,cy-rad*.1,
      cx+rad*.23,cy-rad*.41,cx-rad*.08,cy-rad*.54,cx+rad*.24,cy-rad*.67)
  else -- knight / heraldic shield
    love.graphics.polygon('line',cx-rad*.60,cy-rad*.70,cx+rad*.60,cy-rad*.70,
      cx+rad*.52,cy+rad*.25,cx,cy+rad*.84,cx-rad*.52,cy+rad*.25)
    love.graphics.line(cx,cy-rad*.49,cx,cy+rad*.48)
    love.graphics.line(cx-rad*.34,cy-rad*.04,cx+rad*.34,cy-rad*.04)
  end
end
local function healthBar(x,y,w,h,amount,maximum)
  love.graphics.setColor(0.08,0.11,0.15,1)
  love.graphics.rectangle('fill',x,y,w,h,2,2)
  if amount>0 then
    local ratio=math.max(0,math.min(1,amount/math.max(maximum,1)))
    color(ratio<0.35 and palette.red or palette.green)
    love.graphics.rectangle('fill',x,y,w*ratio,h,2,2)
  end
end
local function unitToken(u)
  local cx,cy=center(u.r,u.c)
  local rad=layout.radius
  -- Same hex shape/footprint as the board space; team colored border.
  color(teamColors[u.owner]);love.graphics.polygon('fill',faceHex(cx,cy,rad*.99))
  color((selected==u.id or inspected==u.id) and palette.gold or palette.border)
  love.graphics.setLineWidth(selected==u.id and 3.2 or 1.5)
  love.graphics.polygon('line',faceHex(cx,cy,rad*.99))
  color(classColors[u.class]);love.graphics.polygon('fill',faceHex(cx,cy,rad*.78))
  emblem(u.class,cx,cy-rad*.12,rad*.49)
  love.graphics.setColor(1,1,1,1)
  love.graphics.setFont(fonts.small)
  love.graphics.printf(rules.classes[u.class].mark,cx-rad*.68,cy+rad*.27,rad*1.36,'center')
  healthBar(cx-rad*.57,cy+rad*.70,rad*1.14,3.1,u.hp,rules.classes[u.class].hp)
end
local function drawBoard()
  for r=0,rules.ROWS-1 do
    for c=0,rules.COLS-1 do
      local cx,cy=center(r,c)
      local terrain=r<=3 and palette.top or r>=8 and palette.bottom or palette.waste
      local tint=((r+c)%3)*0.018
      local sqX,sqY=cx-layout.cell/2,cy-layout.cell/2
      -- Full square base tile; the much lighter hex is an inset within it.
      love.graphics.setColor(terrain[1]+tint,terrain[2]+tint,terrain[3]+tint,1)
      love.graphics.rectangle('fill',sqX,sqY,layout.cell,layout.cell)
      local brighten=.13
      love.graphics.setColor(math.min(1,terrain[1]+brighten+tint),
        math.min(1,terrain[2]+brighten+tint),math.min(1,terrain[3]+brighten+tint),1)
      love.graphics.polygon('fill',faceHex(cx,cy,layout.radius))
      color(palette.border,.40);love.graphics.setLineWidth(1.0)
      love.graphics.rectangle('line',sqX,sqY,layout.cell,layout.cell)
      color(palette.border,.25)
      love.graphics.polygon('line',faceHex(cx,cy,layout.radius))
    end
  end
  if selected and not overlay and state and not state.winner then
    color(palette.green,0.36)
    for k,_ in pairs(targets.moves or {}) do
      local r,c=rules.fromkey(k);local cx,cy=center(r,c)
      love.graphics.polygon('fill',faceHex(cx,cy,layout.radius*.66))
    end
    color(palette.red,0.55)
    for k,_ in pairs(targets.attacks or {}) do
      local r,c=rules.fromkey(k);local cx,cy=center(r,c)
      love.graphics.circle('line',cx,cy,layout.radius*0.68)
    end
  end
  for _,fort in ipairs(state.forts) do
    local cx,cy=center(fort.r,fort.c)
    local rr=layout.radius
    -- Fortified keep with twin towers, crenellations and an arched gate;
    -- not a generic token labeled F.
    color(teamColors[fort.owner]);love.graphics.polygon('fill',faceHex(cx,cy,rr))
    love.graphics.setColor(.14,.16,.22,1)
    love.graphics.polygon('fill',cx-rr*.63,cy+rr*.46,cx-rr*.63,cy-rr*.18,
      cx-rr*.38,cy-rr*.18,cx-rr*.38,cy-rr*.57,cx+rr*.38,cy-rr*.57,
      cx+rr*.38,cy-rr*.18,cx+rr*.63,cy-rr*.18,cx+rr*.63,cy+rr*.46)
    love.graphics.setColor(.82,.79,.72,1)
    love.graphics.rectangle('fill',cx-rr*.48,cy-rr*.32,rr*.96,rr*.78)
    love.graphics.rectangle('fill',cx-rr*.68,cy-rr*.55,rr*.36,rr*.94)
    love.graphics.rectangle('fill',cx+rr*.32,cy-rr*.55,rr*.36,rr*.94)
    for _,dx in ipairs({-.68,-.47,-.18,.03,.33,.54}) do
      love.graphics.rectangle('fill',cx+rr*dx,cy-rr*.69,rr*.15,rr*.16)
    end
    love.graphics.setColor(.20,.22,.27,1)
    love.graphics.rectangle('fill',cx-rr*.16,cy+rr*.05,rr*.32,rr*.41,rr*.12,rr*.12)
    love.graphics.rectangle('fill',cx-rr*.075,cy-rr*.39,rr*.15,rr*.20)
    healthBar(cx-rr*.62,cy+rr*.64,rr*1.24,4,fort.hp,rules.FORT_HP)
  end
  for _,u in ipairs(state.units) do if u.hp>0 then unitToken(u) end end
  if intended and not overlay then
    local cx,cy=center(intended.r,intended.c)
    color(palette.gold)
    love.graphics.setLineWidth(math.max(2.7,layout.radius*.16))
    love.graphics.circle('line',cx,cy,layout.radius*.89)
  end
  -- A glowing cross-swords hex is an ATTACK LANDING, never an automatic attack.
  -- Keep the cue over the enemy token so it is visible even on small phones.
  if selected and not overlay and targets.attacks then
    local pulse=.76+.20*math.sin(love.timer.getTime()*3.5)
    for key,_ in pairs(targets.attacks) do
      local r,c=rules.fromkey(key);local cx,cy=center(r,c)
      local rad=layout.radius
      color(palette.red,pulse)
      love.graphics.setLineWidth(math.max(2.8,rad*.16))
      love.graphics.polygon('line',faceHex(cx,cy,rad*.89))
      color(palette.gold,pulse)
      love.graphics.setLineWidth(math.max(2.2,rad*.10))
      local d=rad*.39
      love.graphics.line(cx-d,cy-d,cx+d,cy+d)
      love.graphics.line(cx-d,cy+d,cx+d,cy-d)
    end
  end
  if intended and intended.type=='attack' and selected and not overlay then
    local cx,cy=center(intended.r,intended.c)
    local a=state.units[selected]
    local rad=layout.radius
    -- Draw an actual legal square-by-square route: it bends around defenders
    -- instead of suggesting that the attacker can jump through pieces.
    local route=rules.route(state,selected,intended.r,intended.c)
    love.graphics.setLineWidth(math.max(2.4,rad*.12))
    color(palette.gold,.88)
    if route then
      for i=2,#route do
        local x0,y0=center(route[i-1].r,route[i-1].c)
        local x1,y1=center(route[i].r,route[i].c)
        love.graphics.line(x0,y0,x1,y1)
      end
    end
    local prior=route and route[#route-1] or a
    local ax,ay=center(prior.r,prior.c)
    local angle=math.atan2 and math.atan2(cy-ay,cx-ax) or math.atan(cy-ay,cx-ax)
    local x2,y2=cx-math.cos(angle)*rad*.9,cy-math.sin(angle)*rad*.9
    love.graphics.line(x2,y2,x2-math.cos(angle-.7)*rad*.38,y2-math.sin(angle-.7)*rad*.38)
    love.graphics.line(x2,y2,x2-math.cos(angle+.7)*rad*.38,y2-math.sin(angle+.7)*rad*.38)
    color(palette.red,.95)
    love.graphics.setLineWidth(math.max(3,rad*.19))
    love.graphics.polygon('line',faceHex(cx,cy,rad*.98))
    -- Semi-transparent attacker crest sits on the enemy position in preview.
    color(teamColors[a.owner],.53)
    love.graphics.circle('fill',cx-rad*.35,cy-rad*.35,rad*.29)
    emblem(a.class,cx-rad*.35,cy-rad*.35,rad*.21)
  end
end
local function currentUnit()
  if not state then return nil end
  if type(inspected)=='number' then return state.units[inspected] end
  return selected and state.units[selected]
end
local function drawCard()
  -- No permanent card: a floating, contextual single-line info ribbon.
  local u=currentUnit()
  if not u and inspected~='fort' then return end
  local row=(u and u.r or state.forts[inspectedFortOwner or 3-state.turn].r)
  local h=layout.cell>=40 and 45 or 36
  local y=(row>=rules.ROWS/2) and layout.y+4 or layout.y+rules.ROWS*layout.cell-h-4
  local x,w=layout.x+3,layout.cell*rules.COLS-6
  love.graphics.setColor(.06,.08,.13,.94)
  love.graphics.rectangle('fill',x,y,w,h,7,7)
  color(palette.gold,.65);love.graphics.rectangle('line',x,y,w,h,7,7)
  if u and u.hp>0 then
    local p=rules.classes[u.class]
    color(classColors[u.class]);love.graphics.polygon('fill',faceHex(x+22,y+h*.48,h*.39))
    emblem(u.class,x+22,y+h*.46,h*.21)
    text(p.name:upper()..'  •  P'..u.owner,x+42,y+3,w-48,'left',fonts.small)
    text(('HP %d/%d    MOVE %d    HIT %d'):format(u.hp,p.hp,p.move,p.hit),x+42,y+h*.47,w-48,'left',fonts.small)
  elseif inspected=='fort' then
    local fort=state.forts[inspectedFortOwner or 3-state.turn]
    text('FORTRESS  •  P'..fort.owner,x+10,y+3,w-20,'left',fonts.small)
    text(('HP %d/%d   DEFENSE HIT %d'):format(fort.hp,rules.FORT_HP,rules.FORT_HIT),x+10,y+h*.47,w-20,'left',fonts.small)
  end
end
local function panel(x,y,w,h)
  love.graphics.setColor(0.045,0.062,0.09,0.97)
  love.graphics.rectangle('fill',x,y,w,h,12,12)
  color(palette.gold);love.graphics.setLineWidth(2)
  love.graphics.rectangle('line',x,y,w,h,12,12)
end
-- A full exchange has a visible rolling, reveal, impact and recovery phase.
-- Rendering never advances the game RNG. Actual outcomes are already in the event log.
local EXCHANGE_SECONDS = 2.65
local function battleFrame()
  local event=overlay.event
  local count=#(event.rounds or {})
  local elapsed=math.max(0,overlay.elapsed)
  local finished=elapsed>=count*EXCHANGE_SECONDS
  local index=finished and count or math.min(count,math.floor(elapsed/EXCHANGE_SECONDS)+1)
  local phase=finished and EXCHANGE_SECONDS or (elapsed%EXCHANGE_SECONDS)
  local round=event.rounds[index]
  local previous=event.rounds[index-1]
  local applied=finished or phase>=1.55
  local attackerHP=applied and round and round.attackerHp or previous and previous.attackerHp or event.attackerHpStart
  local defenderHP=applied and round and round.defenderHp or previous and previous.defenderHp or event.defenderHpStart
  return index,count,round,phase,finished,attackerHP,defenderHP
end
-- Readable graybox figures until finished character art is ready.
-- Different silhouettes and visible weapons make the fighters identifiable by class.
local function drawBattleFigure(kind,cx,cy,r)
  local function poly(points) love.graphics.polygon('fill',(table.unpack or unpack)(points)) end
  local function line(points,width)
    love.graphics.setLineWidth(width or r*.11)
    love.graphics.line((table.unpack or unpack)(points))
  end
  local armor={
    warrior={.33,.62,.68},barbarian={.66,.39,.25},archer={.33,.58,.33},
    wizard={.50,.40,.78},knight={.71,.78,.85},
  }
  color(armor[kind] or palette.top)
  poly({cx-r*.48,cy+r*.68,cx-r*.34,cy+r*.04,cx+r*.34,cy+r*.04,cx+r*.48,cy+r*.68})
  love.graphics.setColor(.95,.77,.61,1)
  love.graphics.circle('fill',cx,cy-r*.30,r*.245)
  -- The helmet/hood is a class-specific silhouette, not a tiny text abbreviation.
  if kind=='wizard' then
    love.graphics.setColor(.35,.22,.61,1)
    poly({cx-r*.42,cy-r*.46,cx+r*.45,cy-r*.46,cx+r*.07,cy-r*1.02})
    love.graphics.rectangle('fill',cx-r*.48,cy-r*.5,r*.96,r*.12)
    love.graphics.setColor(.86,.76,.44,1)
    line({cx+r*.45,cy+r*.46,cx+r*.45,cy-r*.55},r*.095)
    love.graphics.circle('fill',cx+r*.45,cy-r*.65,r*.16)
  elseif kind=='archer' then
    love.graphics.setColor(.15,.34,.23,1)
    poly({cx-r*.31,cy-r*.58,cx-r*.05,cy-r*.83,cx+r*.28,cy-r*.58,cx+r*.31,cy-r*.25,
      cx+r*.18,cy-r*.48,cx-r*.18,cy-r*.48,cx-r*.32,cy-r*.25})
    love.graphics.setColor(.92,.80,.52,1)
    line({cx+r*.48,cy-r*.69,cx+r*.79,cy-r*.29,cx+r*.82,cy+r*.33,cx+r*.49,cy+r*.74},r*.085)
    line({cx+r*.48,cy-r*.69,cx+r*.49,cy+r*.74},r*.043)
    line({cx+r*.27,cy,cx+r*.98,cy},r*.065)
  elseif kind=='barbarian' then
    love.graphics.setColor(.36,.23,.15,1)
    poly({cx-r*.26,cy-r*.50,cx+r*.26,cy-r*.50,cx+r*.32,cy-r*.27,cx-r*.32,cy-r*.27})
    love.graphics.setColor(.84,.82,.67,1)
    poly({cx-r*.26,cy-r*.52,cx-r*.63,cy-r*.82,cx-r*.48,cy-r*.32})
    poly({cx+r*.26,cy-r*.52,cx+r*.63,cy-r*.82,cx+r*.48,cy-r*.32})
    love.graphics.setColor(.76,.78,.83,1)
    line({cx+r*.46,cy+r*.52,cx+r*.63,cy-r*.52},r*.105)
    poly({cx+r*.40,cy-r*.61,cx+r*.87,cy-r*.68,cx+r*.87,cy-r*.27,cx+r*.52,cy-r*.24})
  elseif kind=='knight' then
    love.graphics.setColor(.79,.84,.88,1)
    poly({cx-r*.30,cy-r*.54,cx+r*.30,cy-r*.54,cx+r*.31,cy-r*.16,cx-r*.31,cy-r*.16})
    love.graphics.setColor(.17,.25,.35,1)
    love.graphics.rectangle('fill',cx-r*.22,cy-r*.28,r*.44,r*.075)
    love.graphics.setColor(.88,.89,.94,1)
    line({cx+r*.50,cy+r*.58,cx+r*.77,cy-r*.68},r*.11)
    love.graphics.setColor(.73,.19,.22,1)
    poly({cx-r*.57,cy+r*.02,cx-r*.25,cy+r*.03,cx-r*.27,cy+r*.55,cx-r*.43,cy+r*.78,cx-r*.58,cy+r*.50})
  else -- Warrior with sword and shield
    love.graphics.setColor(.60,.68,.77,1)
    poly({cx-r*.27,cy-r*.54,cx+r*.27,cy-r*.54,cx+r*.32,cy-r*.31,cx-r*.32,cy-r*.31})
    love.graphics.setColor(.17,.24,.32,1)
    love.graphics.rectangle('fill',cx-r*.20,cy-r*.31,r*.40,r*.072)
    love.graphics.setColor(.89,.89,.90,1)
    line({cx+r*.47,cy+r*.66,cx+r*.81,cy-r*.67},r*.105)
    love.graphics.setColor(.70,.31,.28,1)
    poly({cx-r*.64,cy-r*.02,cx-r*.25,cy-r*.02,cx-r*.34,cy+r*.64,cx-r*.48,cy+r*.79,cx-r*.64,cy+r*.59})
  end
end
local function drawCombatant(kind,cx,cy,rad,team,hit,impact)
  color(teamColors[team] or palette.gold)
  love.graphics.circle('fill',cx,cy,rad*1.05)
  if impact then
    love.graphics.setColor(0.99,0.24,0.20,0.76)
    love.graphics.circle('fill',cx,cy,rad*1.07)
  end
  color(kind=='fortress' and palette.gold or classColors[kind] or palette.top)
  love.graphics.circle('fill',cx,cy,rad*.90)
  love.graphics.setColor(0.99,0.96,0.82)
  love.graphics.setLineWidth(math.max(1.5,rad*.085))
  if kind=='fortress' then
    -- Wall and battlements: the fortress is not a normal soldier.
    love.graphics.rectangle('fill',cx-rad*.53,cy-rad*.18,rad*1.06,rad*.75)
    for i=-1,1 do
      love.graphics.rectangle('fill',cx+i*rad*.43-rad*.15,cy-rad*.54,rad*.30,rad*.44)
    end
    love.graphics.setColor(.16,.19,.23,1)
    love.graphics.rectangle('fill',cx-rad*.18,cy+rad*.10,rad*.36,rad*.48)
  else
    drawBattleFigure(kind,cx,cy,rad)
  end
end
local function drawD8(cx,cy,n,winning)
  if winning then color(palette.gold) else love.graphics.setColor(.33,.46,.62,1) end
  local side=math.min(24,layout.w*.055)
  love.graphics.polygon('fill',cx,cy-side,cx+side,cy,cx,cy+side,cx-side,cy)
  love.graphics.setColor(.07,.10,.16,1)
  love.graphics.setLineWidth(1.4)
  love.graphics.polygon('line',cx,cy-side,cx+side,cy,cx,cy+side,cx-side,cy)
  love.graphics.setColor(.07,.10,.16,1)
  love.graphics.setFont(fonts.large)
  love.graphics.printf(tostring(n),cx-side,cy-side*.50,side*2,'center')
end
local function drawBattleOverlay()
  local w,h=layout.w,layout.h
  love.graphics.setColor(0,0,0,0.82);love.graphics.rectangle('fill',0,0,w,h)
  local x,y,ww,hh=w*.055,h*.12,w*.89,math.min(h*.77,450)
  panel(x,y,ww,hh)
  local event=overlay.event
  local index,count,round,phase,finished,ah,dh=battleFrame()
  local at=rules.classes[event.attackerClass]
  local dt=rules.classes[event.defenderClass]
  local defenderName=dt and dt.name or 'Fortress'
  local cx1,cx2=x+ww*.26,x+ww*.74
  local portraitY=y+hh*.30
  local radius=math.min(ww*.12,hh*.105,41)
  local showingDice=finished or phase>=.88
  local striking=not finished and phase>=1.42 and phase<2.28 and round and round.who~='tie'
  local impact=not finished and phase>=1.67 and phase<2.30 and round and round.who~='tie'
  local progress=phase>=1.42 and math.min(1,(phase-1.42)/.26) or 0
  local move=radius*.44*progress
  local shake=impact and math.sin((phase-1.67)*44)*radius*.06 or 0
  local aX=cx1+(striking and round.who=='attacker' and move or (impact and round.who=='defender' and shake or 0))
  local dX=cx2-(striking and round.who=='defender' and move or (impact and round.who=='attacker' and shake or 0))
  text(event.defender=='fort' and 'ASSAULT THE FORTRESS' or 'BATTLE',x+8,y+hh*.025,ww-16,'center',fonts.large)
  text(('EXCHANGE %d OF %d  •  EACH ROLLS D8'):format(index,count),x+8,y+hh*.115,ww-16,'center',fonts.small)
  text(at.name,cx1-ww*.24,y+hh*.17,ww*.48,'center',fonts.medium)
  text(defenderName,cx2-ww*.24,y+hh*.17,ww*.48,'center',fonts.medium)
  drawCombatant(event.attackerClass,aX,portraitY,radius,event.actor,at.hit,impact and round.who=='defender')
  drawCombatant(event.defenderClass,dX,portraitY,radius,3-event.actor,dt and dt.hit or rules.FORT_HIT,impact and round.who=='attacker')
  text('VS',x+ww*.43,portraitY-radius*.24,ww*.14,'center',fonts.medium)
  local maxA=at.hp
  local maxD=dt and dt.hp or rules.FORT_HP
  local barY=y+hh*.45
  healthBar(cx1-ww*.21,barY,ww*.42,9,ah,maxA)
  healthBar(cx2-ww*.21,barY,ww*.42,9,dh,maxD)
  text(('HP %d / %d'):format(ah,maxA),cx1-ww*.22,barY+11,ww*.44,'center',fonts.medium)
  text(('HP %d / %d'):format(dh,maxD),cx2-ww*.22,barY+11,ww*.44,'center',fonts.medium)
  local dieY=y+hh*.635
  local aFace,bFace
  if showingDice then aFace,bFace=round.a,round.b
  else
    -- Animated preview numbers are visual only; resolved rolls remain immutable.
    aFace=1+(math.floor(math.max(0,overlay.elapsed)*23)+index*3)%8
    bFace=1+(math.floor(math.max(0,overlay.elapsed)*19)+index*5)%8
  end
  drawD8(cx1,dieY,aFace,showingDice and round.who=='attacker')
  drawD8(cx2,dieY,bFace,showingDice and round.who=='defender')
  text(('HIT %d'):format(at.hit),cx1-ww*.18,dieY+radius*.75,ww*.36,'center',fonts.small)
  text(('HIT %d'):format(dt and dt.hit or rules.FORT_HIT),cx2-ww*.18,dieY+radius*.75,ww*.36,'center',fonts.small)
  local message='Rolling both dice...'
  if finished then
    if event.finish=='fortress' then message='FORTRESS DESTROYED!'
    elseif event.attackerHpEnd>0 then message='ATTACKER WINS!'
    elseif event.defender=='unit' then message='DEFENDER WINS!'
    else message='FORTRESS HOLDS!' end
  elseif showingDice then
    if round.who=='tie' then message='TIE  •  NO DAMAGE'
    elseif round.who=='attacker' then
      message=phase>=1.55 and (at.name:upper()..' HITS FOR '..round.damage..' HP') or (at.name:upper()..' WINS THE ROLL!')
    else
      message=phase>=1.55 and (defenderName:upper()..' HITS FOR '..round.damage..' HP') or (defenderName:upper()..' WINS THE ROLL!')
    end
  end
  text(message,x+10,y+hh*.755,ww-20,'center',fonts.medium)
  if impact then
    local dest=round.who=='attacker' and cx2 or cx1
    local dy=portraitY-radius*.91
    love.graphics.setColor(.99,.36,.30,1)
    love.graphics.setFont(fonts.large)
    love.graphics.printf('-'..round.damage..' HP',dest-ww*.18,dy,ww*.36,'center')
  end
  if finished then
    local msg=event.captured and 'The attacker takes the enemy hex.' or 'The defender holds this position.'
    if event.finish=='fortress' then msg='The enemy Fortress has fallen!' end
    if event.heal then msg=msg..'  Potion +'..event.heal.actual..' HP' end
    text(msg,x+9,y+hh*.835,ww-18,'center',fonts.small)
    local by=y+hh-51
    love.graphics.setColor(0.23,0.62,0.41)
    love.graphics.rectangle('fill',x+ww*.18,by,ww*.64,41,9,9)
    text('CONTINUE',x+ww*.19,by+10,ww*.62,'center',fonts.medium)
    overlay.continueBox={x=x+ww*.18,y=by,w=ww*.64,h=41}
  else
    overlay.continueBox=nil
  end
end
local VOLLEY_SECONDS = 2.3
local function drawSiegeOverlay()
  local w,h=layout.w,layout.h
  love.graphics.setColor(0,0,0,0.82);love.graphics.rectangle('fill',0,0,w,h)
  local x,y,ww,hh=w*.055,h*.12,w*.89,math.min(h*.77,450)
  panel(x,y,ww,hh)
  local count=#overlay.rounds
  local elapsed=math.max(0,overlay.elapsed)
  local finished=elapsed>=count*VOLLEY_SECONDS
  local index=finished and count or math.min(count,math.floor(elapsed/VOLLEY_SECONDS)+1)
  local phase=finished and VOLLEY_SECONDS or elapsed%VOLLEY_SECONDS
  local volley=overlay.rounds[index]
  local previous=overlay.rounds[index-1]
  local applied=finished or phase>=1.40
  local hp1=applied and volley and volley.h1 or previous and previous.h1 or overlay.start.h1
  local hp2=applied and volley and volley.h2 or previous and previous.h2 or overlay.start.h2
  local showDie=finished or phase>=.80
  local base1=x+ww*.27;local base2=x+ww*.73
  text('THE FINAL SIEGE',x+7,y+hh*.025,ww-14,'center',fonts.large)
  text(('TREBUCHET VOLLEY %d OF %d'):format(index,count),x+8,y+hh*.115,ww-16,'center',fonts.small)
  text('PLAYER 1',base1-ww*.23,y+hh*.185,ww*.46,'center',fonts.medium)
  text('PLAYER 2',base2-ww*.23,y+hh*.185,ww*.46,'center',fonts.medium)
  local rad=math.min(ww*.12,hh*.10,42)
  drawCombatant('fortress',base1,y+hh*.30,rad,1,7,applied and volley.hit2>0)
  drawCombatant('fortress',base2,y+hh*.30,rad,2,7,applied and volley.hit1>0)
  healthBar(base1-ww*.20,y+hh*.45,ww*.40,9,hp1,rules.FORT_HP)
  healthBar(base2-ww*.20,y+hh*.45,ww*.40,9,hp2,rules.FORT_HP)
  text(('HP %d / %d'):format(hp1,rules.FORT_HP),base1-ww*.22,y+hh*.485,ww*.44,'center',fonts.medium)
  text(('HP %d / %d'):format(hp2,rules.FORT_HP),base2-ww*.22,y+hh*.485,ww*.44,'center',fonts.medium)
  local n1,n2
  if showDie then n1,n2=volley.a,volley.b
  else
    n1=1+(math.floor(elapsed*21)+index*3)%8
    n2=1+(math.floor(elapsed*18)+index*5)%8
  end
  local dieY=y+hh*.645
  drawD8(base1,dieY,n1,showDie and volley.hit1>0)
  drawD8(base2,dieY,n2,showDie and volley.hit2>0)
  text('HIT ON 4-8',x+10,dieY+rad*.75,ww-20,'center',fonts.small)
  local msg='Both trebuchets prepare to fire...'
  if finished then
    if state.winner==0 then msg='MUTUALLY ASSURED DESTRUCTION'
    else msg=('PLAYER %d CONQUERS!'):format(state.winner) end
  elseif showDie then
    if not applied then msg='Both trebuchets fire simultaneously!'
    else
      local h1=volley.hit1>0 and ('P1 -'..volley.hit1..' HP') or 'P1 misses'
      local h2=volley.hit2>0 and ('P2 -'..volley.hit2..' HP') or 'P2 misses'
      msg=h1..'   •   '..h2
    end
  end
  text(msg,x+9,y+hh*.785,ww-18,'center',fonts.medium)
  if finished then
    if state.winner==0 then
      text('Two kingdoms, each determined to conquer the other. In the end, both lost everything.',x+9,y+hh*.865,ww-18,'center',fonts.small)
    end
    local by=y+hh-49
    love.graphics.setColor(.23,.62,.41)
    love.graphics.rectangle('fill',x+ww*.18,by,ww*.64,39,9,9)
    text('CONTINUE',x+ww*.18,by+9,ww*.64,'center',fonts.medium)
    overlay.continueBox={x=x+ww*.18,y=by,w=ww*.64,h=39}
  else overlay.continueBox=nil end
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
  selected,inspected,targets,intended=nil,nil,{},nil
  if event and event.type=='attack' then
    overlay={type='battle',event=event,elapsed=-0.55,shown=0}
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
local function drawActionBar()
  actionBox,cancelBox=nil,nil
  local x,y,w,h=5,layout.actionY,layout.w-10,40
  if intended and selected and mayAct() then
    local isAttack=intended.type=='attack'
    local confirmW=w*.74
    color(isAttack and palette.red or palette.green)
    love.graphics.rectangle('fill',x,y,confirmW,h,8,8)
    love.graphics.setColor(.04,.08,.10,1)
    love.graphics.setFont(fonts.medium)
    love.graphics.printf(isAttack and 'ATTACK' or 'MOVE',x,y+8,confirmW,'center')
    love.graphics.setColor(.22,.25,.29,1)
    love.graphics.rectangle('fill',x+confirmW+5,y,w-confirmW-5,h,8,8)
    text('CANCEL',x+confirmW+5,y+11,w-confirmW-5,'center',fonts.small)
    actionBox={x=x,y=y,w=confirmW,h=h}
    cancelBox={x=x+confirmW+5,y=y,w=w-confirmW-5,h=h}
  else
    love.graphics.setColor(.09,.13,.18,.98)
    love.graphics.rectangle('fill',x,y,w,h,8,8)
    text(selected and 'TAP A DESTINATION TO PREVIEW' or
      ('PLAYER '..state.turn..'  •  TAP A PIECE'),x+4,y+12,w-8,'center',fonts.small)
  end
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
local function inside(box,x,y)
  return box and x>=box.x and y>=box.y and x<=box.x+box.w and y<=box.y+box.h
end
local function onTap(x,y)
  if not state then return end
  if overlay then
    local b=overlay.continueBox
    if not inside(b,x,y) then return end
    if overlay.type=='battle' and overlay.event.siege then
      overlay={type='siege',rounds=overlay.event.siege,start=overlay.event.siegeStart,elapsed=-0.3,shown=0}
    else overlay=nil end
    return
  end
  if state.winner~=nil then return end
  if inside(cancelBox,x,y) then
    intended=nil
    inspected=selected
    notice='Destination cleared. Pick another hex.'
    return
  end
  if inside(actionBox,x,y) and intended and selected and mayAct() then
    local action={type=intended.type,id=selected,r=intended.r,c=intended.c}
    -- The rules validate again when the action is committed.
    intended=nil
    notice=''
    actorAction(action)
    return
  end
  local cell=xyToCell(x,y)
  if not cell then return end
  local t=rules.occupied(state,cell.r,cell.c)
  if t and t.kind=='unit' and t.owner==state.turn and mayAct() then
    -- Choosing a different friendly soldier cancels the pending action.
    selected,inspected,intended=t.ref.id,t.ref.id,nil
    targets={moves=rules.moves(state,selected),attacks=rules.attacks(state,selected)}
    notice='Green: move. Crossed swords: land on enemy to fight.'
    return
  end
  if selected and mayAct() then
    local k=rules.key(cell.r,cell.c)
    local kind=(targets.attacks or {})[k] and 'attack' or (targets.moves or {})[k] and 'move' or nil
    if kind then
      intended={type=kind,r=cell.r,c=cell.c}
      inspected=t and t.kind=='unit' and t.ref.id or t and t.kind=='fort' and 'fort' or selected
      if t and t.kind=='fort' then inspectedFortOwner=t.owner end
      local from=state.units[selected]
      if kind=='attack' then
        local name=t.kind=='fort' and 'Fortress' or rules.classes[t.ref.class].name
        notice='LAND ON '..name:upper()..'  •  Confirm ATTACK'
      else
        notice=rules.classes[from.class].name..'  •  Move to marked hex'
      end
      return
    end
  end
  intended=nil
  if t and t.kind=='unit' then
    -- Enemy inspection never moves or attacks and does not deselect the friendly unit.
    inspected=t.ref.id
    if t.owner~=state.turn then
      notice=selected and 'Enemy is unreachable. Find a clear landing route.' or 'Enemy inspected. Select your soldier first.'
    end
  elseif t and t.kind=='fort' then
    inspected='fort'
    inspectedFortOwner=t.owner
    notice=t.owner==state.turn and 'Protect your Fortress.' or 'Enemy Fortress inspected.'
  elseif selected then
    inspected=selected
    notice='This hex is not reachable by the selected soldier.'
  else
    inspected=nil
    notice='Select one of your soldiers first.'
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
  selected,inspected,targets,pending,overlay,intended,inspectedFortOwner=nil,nil,{},false,nil,nil,nil
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
  drawBoard();drawActionBar();drawCard()
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
  if key=='escape' then selected,inspected,targets,intended=nil,nil,{},nil end
end
