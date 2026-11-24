-- Fortress: The Badlands — Zompa SDK v4 / LÖVE 11.5 graybox prototype.
-- This game's deterministic rules are shared by solo, pass-and-play, and turns-v1 online.
local rules = require('rules')
local zompa = require('zompa')
local mode = 'solo'
local state, onlineSide, onlineAllowed, onlineReady, lastOnlineCount
local selected, inspected, targets, pending, overlay, intended, actionBox, cancelBox, inspectedFortOwner
local layout, timers, notice, blocked = {}, {cpu=0,poll=0,dialog=0}, '', nil
-- Visual movement never alters rules, health, online tokens or saved state.
local moving, queuedEvent, cardBox = nil, nil, nil
local finishElapsed=0 -- presentation only; no changes to match history
local palette = {
  sky={0.055,0.075,0.115}, top={0.18,0.27,0.43}, bottom={0.37,0.17,0.20},
  waste={0.30,0.28,0.23}, border={0.08,0.09,0.12}, gold={0.93,0.76,0.45},
  green={0.21,0.79,0.48}, red={0.96,0.38,0.34}, text={0.94,0.93,0.88},
}
-- Strong class identities are drawn as vectors, independent of finished artwork.
local classColors={
  soldier={0.70,0.66,0.52}, barbarian={0.53,0.34,0.19},
  assassin={0.42,0.48,0.53}, wizard={0.48,0.37,0.62},
  ogre={0.43,0.50,0.29},
}
local teamColors={[1]={0.50,0.15,0.20},[2]={0.15,0.30,0.46}}
local fonts={}
local artBoard, unitArt = nil, { [1]={}, [2]={} }
local mixer = zompa.audio()
local function color(p,a) love.graphics.setColor(p[1],p[2],p[3],a or 1) end
local function text(str,x,y,w,align,font)
  color(palette.text)
  love.graphics.setFont(font or fonts.small)
  love.graphics.printf(tostring(str),x,y,w,align or 'center')
end
-- Texture and gameplay use exactly the same 7x10 coordinate map.
-- Pixel centers measured from the approved original art, not inferred
-- from tile edges or a distorted image-generation crop.
local ART_W, ART_H = 984, 1383
local SOURCE_CX, SOURCE_CY = 97, 107 -- calibrated against inset-hex centers
local PITCH_X, PITCH_Y = 131.5, 132.5
local function center(r,c)
  return layout.x+(SOURCE_CX+c*PITCH_X)*layout.scale,
         layout.y+(SOURCE_CY+r*PITCH_Y)*layout.scale
end
local function xyToCell(x,y)
  local c=math.floor(((x-layout.x)/layout.scale-(SOURCE_CX-PITCH_X/2))/PITCH_X)
  local r=math.floor(((y-layout.y)/layout.scale-(SOURCE_CY-PITCH_Y/2))/PITCH_Y)
  if not rules.playable(r,c) then return nil end
  return {r=r,c=c}
end
local function reflow(w,h)
  -- Trim only the painted image's unused frame, NOT a square or a character.
  -- Source-art coordinates remain the single authority for touches and tokens.
  local trimX,trimTop,trimBottom=29,18,6
  local cardH=math.min(85,math.max(76,h*.115))
  local topReserve=cardH+7
  local buttonReserve=54
  local croppedW=ART_W-2*trimX
  local croppedH=ART_H-trimTop-trimBottom
  local scale=math.max(.01,math.min((w-4)/croppedW,
    (h-topReserve-buttonReserve-5)/croppedH))
  local imageW,imageH=ART_W*scale,ART_H*scale
  local slotW,slotH=croppedW*scale,croppedH*scale
  local marginX=(w-slotW)*.5
  local marginY=topReserve+math.max(0,(h-topReserve-buttonReserve-slotH)*.5)
  local side=math.min(19,math.max(14,w*.046))
  layout={w=w,h=h,scale=scale,cell=PITCH_X*scale,
    radius=PITCH_X*scale*.475,tileW=PITCH_X*scale,rowH=PITCH_Y*scale,
    x=marginX-trimX*scale,y=marginY-trimTop*scale,
    boardW=imageW,boardH=imageH,cardY=3,cardH=cardH,
    topReserve=topReserve,actionY=h-54}
  fonts.small=love.graphics.newFont(side)
  fonts.stat=love.graphics.newFont(math.min(20,math.max(16,w*.047)))
  fonts.medium=love.graphics.newFont(math.min(26,math.max(18,w*.061)))
  fonts.large=love.graphics.newFont(math.min(34,math.max(23,w*.079)))
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

-- Sprite crops include part of their former square tile. Their badges are
-- centered at 77,82 in 144-pixel source art, NOT at the PNG center 72,72.
local BADGE_X,BADGE_Y,BADGE_R=77,82,60
local function drawBadgeSprite(sprite,x,y,scale,cutout)
  local g=love.graphics
  local stencil=cutout and g.stencil and g.setStencilTest
  if stencil then
    g.stencil(function()g.polygon('fill',faceHex(x,y,BADGE_R*scale))end,'replace',1)
    g.setStencilTest('greater',0)
  end
  g.setColor(1,1,1,1)
  g.draw(sprite,x-BADGE_X*scale,y-BADGE_Y*scale,0,scale,scale)
  if stencil then g.setStencilTest() end
end

local function emblem(kind,cx,cy,rad)
  -- Each symbol differs in silhouette and color (color is never the sole cue).
  love.graphics.setColor(0.985,0.975,0.88,1)
  love.graphics.setLineWidth(math.max(1.5,rad*0.14))
  if kind=='soldier' then
    love.graphics.line(cx-rad*.55,cy+rad*.6,cx+rad*.53,cy-rad*.52)
    love.graphics.line(cx-rad*.52,cy-rad*.45,cx+rad*.51,cy+rad*.54)
    love.graphics.line(cx-rad*.65,cy+rad*.40,cx-rad*.35,cy+rad*.69)
  elseif kind=='barbarian' then
    love.graphics.line(cx-rad*.43,cy+rad*.73,cx+rad*.43,cy-rad*.72)
    love.graphics.polygon('fill',cx+rad*.16,cy-rad*.60,cx+rad*.76,cy-rad*.48,
      cx+rad*.55,cy-rad*.01,cx+rad*.08,cy-rad*.25)
  elseif kind=='assassin' then
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
  else -- ogre, fallback symbol
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
  local sprite=unitArt[u.owner][u.class]
  if selected==u.id and not moving then
    local pulse=.60+.24*math.sin(love.timer.getTime()*4)
    love.graphics.setColor(.95,.74,.28,pulse*.30)
    love.graphics.polygon('fill',faceHex(cx,cy,rad*1.24))
    love.graphics.setColor(1,.87,.43,pulse)
    love.graphics.setLineWidth(math.max(2.2,rad*.14))
    love.graphics.polygon('line',faceHex(cx,cy,rad*1.10))
  end
  if sprite then
    drawBadgeSprite(sprite,cx,cy,layout.scale,false)
  else
    color(teamColors[u.owner]);love.graphics.polygon('fill',faceHex(cx,cy,rad*.99))
    color(classColors[u.class]);love.graphics.polygon('fill',faceHex(cx,cy,rad*.82))
    emblem(u.class,cx,cy,rad*.48)
  end
  if selected==u.id or inspected==u.id then
    color(palette.gold)
    love.graphics.setLineWidth(math.max(2,rad*.13))
    love.graphics.polygon('line',faceHex(cx,cy,rad*.92))
  end
  -- HP is in the large inspection card; a small bar appears only for injuries.
  if u.hp<rules.classes[u.class].hp then
    healthBar(cx-rad*.52,cy+rad*.90,rad*1.04,math.max(3.5,layout.cell*.06),
      u.hp,rules.classes[u.class].hp)
  end
end
local function drawBoard()
  if artBoard then
    love.graphics.setColor(1,1,1,1)
    local textureScale=layout.boardW/artBoard:getWidth()
    love.graphics.draw(artBoard,layout.x,layout.y,0,textureScale,textureScale)
  else
    for r=0,rules.ROWS-1 do
      for c=0,rules.COLS-1 do
        if rules.playable(r,c) then
          local cx,cy=center(r,c)
          local terrain=r<=2 and palette.top or r>=7 and palette.bottom or palette.waste
          local tint=((r+c)%3)*.018
          local sqX,sqY=cx-layout.cell/2,cy-layout.cell/2
          love.graphics.setColor(terrain[1]+tint,terrain[2]+tint,terrain[3]+tint,1)
          love.graphics.rectangle('fill',sqX,sqY,layout.cell,layout.cell)
          local brighten=.13
          love.graphics.setColor(math.min(1,terrain[1]+brighten+tint),
            math.min(1,terrain[2]+brighten+tint),math.min(1,terrain[3]+brighten+tint),1)
          love.graphics.polygon('fill',faceHex(cx,cy,layout.radius))
          color(palette.border,.4)
          love.graphics.rectangle('line',sqX,sqY,layout.cell,layout.cell)
        end
      end
    end
  end
  if selected and not overlay and state and not state.winner then
    for k,_ in pairs(targets.moves or {}) do
      local r,c=rules.fromkey(k);local cx,cy=center(r,c)
      local pulse=.82+.14*math.sin(love.timer.getTime()*3+r*.4+c*.3)
      -- Centered, full-size two-layer marker: easy to read on stone tiles.
      -- Warm gold and deep ink stay readable against all aged-stone tiles.
      love.graphics.setColor(.10,.13,.14,.55)
      love.graphics.polygon('fill',faceHex(cx,cy,layout.radius*.83))
      love.graphics.setColor(1,.84,.28,pulse)
      love.graphics.setLineWidth(math.max(3,layout.radius*.15))
      love.graphics.polygon('line',faceHex(cx,cy,layout.radius*.78))
      love.graphics.setColor(1,.95,.56,1)
      love.graphics.circle('fill',cx,cy,math.max(4,layout.radius*.18))
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
    if not artBoard then
      color(teamColors[fort.owner]);love.graphics.polygon('fill',faceHex(cx,cy,rr))
      love.graphics.setColor(.78,.73,.62,1)
      love.graphics.rectangle('fill',cx-rr*.68,cy-rr*.25,rr*1.36,rr*.85)
      for _,dx in ipairs({-.65,-.23,.20,.55}) do
        love.graphics.rectangle('fill',cx+rr*dx,cy-rr*.50,rr*.18,rr*.29)
      end
      love.graphics.setColor(.24,.18,.13,1)
      love.graphics.rectangle('fill',cx-rr*.21,cy+rr*.17,rr*.42,rr*.45)
    end
    if fort.hp<rules.FORT_HP then
      healthBar(cx-rr*.58,cy+rr*.91,rr*1.16,math.max(3.5,layout.cell*.06),
        fort.hp,rules.FORT_HP)
    end
  end
  for _,u in ipairs(state.units) do
    if u.hp>0 and (not moving or moving.id~=u.id) then unitToken(u) end
  end
  if moving and moving.event and moving.id then
    local path=moving.route
    local total=math.max(1,#path-1)
    local advance=math.min(total,math.max(0,moving.elapsed/moving.duration)*total)
    local i=math.min(total,math.floor(advance)+1)
    local t=advance-(i-1)
    t=t*t*(3-2*t)
    local from,to=path[i],path[i+1] or path[i]
    local x0,y0=center(from.r,from.c)
    local x1,y1=center(to.r,to.c)
    local cx,cy=x0+(x1-x0)*t,y0+(y1-y0)*t
    -- A tiny squash/settle at arrival makes moves feel physical without
    -- changing the square, the action timestamp or any turn data.
    local settle=math.max(0,(moving.elapsed/moving.duration-.85)/.15)
    local lift=settle>0 and math.sin(settle*math.pi)*layout.radius*.14 or 0
    cy=cy-lift
    -- Attack approach stops just before the occupied landing square.
    if moving.event.type=='attack' and i==total then
      cx,cy=x0+(x1-x0)*math.min(.76,t*.76),y0+(y1-y0)*math.min(.76,t*.76)
    end
    local sprite=unitArt[moving.event.actor][moving.event.attackerClass or moving.class]
    if sprite then
      local factor=layout.scale*1.04
      drawBadgeSprite(sprite,cx,cy,factor,false)
    else
      color(teamColors[moving.event.actor]);love.graphics.polygon('fill',faceHex(cx,cy,layout.radius*.81))
    end
    -- Short translucent path line shows which unit moved, including the CPU.
    color(palette.gold,.68);love.graphics.setLineWidth(2.2)
    love.graphics.line(x0,y0,cx,cy)
  end
  if intended and not overlay then
    local cx,cy=center(intended.r,intended.c)
    local pulse=.84+.16*math.sin(love.timer.getTime()*5)
    -- Destination is distinct from available moves; only this one is committed.
    love.graphics.setColor(.10,.11,.12,.50)
    love.graphics.polygon('fill',faceHex(cx,cy,layout.radius*.94))
    love.graphics.setColor(1,.96,.76,pulse)
    love.graphics.setLineWidth(math.max(3,layout.radius*.18))
    love.graphics.polygon('line',faceHex(cx,cy,layout.radius*.92))
    love.graphics.setColor(1,1,1,pulse)
    love.graphics.circle('fill',cx,cy,math.max(4,layout.radius*.22))
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
  cardBox=nil
  local u=currentUnit()
  if not u and inspected~='fort' then return end
  -- Place the full-size inspector in the upper free margin; never cover
  -- the selected unit with the old tiny ribbon. If necessary, float at top.
  -- The card is always outside the playing field, never over any token.
  local h=layout.cardH
  local x,w=4,layout.w-8
  local y=layout.cardY
  cardBox={x=x,y=y,w=w,h=h}
  love.graphics.setColor(.055,.075,.105,.98)
  love.graphics.rectangle('fill',x,y,w,h,11,11)
  color(palette.gold,.88);love.graphics.setLineWidth(2)
  love.graphics.rectangle('line',x,y,w,h,11,11)
  love.graphics.setColor(.18,.21,.24,.80)
  love.graphics.rectangle('fill',x+math.min(92,h*.92),y+h*.70,
    math.max(0,w-math.min(92,h*.92)-11),h*.24,5,5)
  local thumb=h*.79
  local ix=x+11+thumb*.5; local iy=y+h*.51
  if u and u.hp>0 then
    local p=rules.classes[u.class]
    local sprite=unitArt[u.owner][u.class]
    if sprite then
      drawBadgeSprite(sprite,ix,iy,thumb*.46/BADGE_R,true)
    else
      color(teamColors[u.owner]);love.graphics.polygon('fill',faceHex(ix,iy,thumb*.49))
      emblem(u.class,ix,iy,thumb*.3)
    end
    local left=ix+thumb*.5+9
    local available=w-(left-x)-8
    color(u.owner==1 and {1,.67,.64} or {.67,.82,1})
    love.graphics.setFont(fonts.medium)
    love.graphics.printf(p.name:upper(),left,y+7,available,'left')
    text(('P%d  •  HP %d / %d'):format(u.owner,u.hp,p.hp),left,y+31,available,'left',fonts.stat)
    text(('MOVE %d      HIT %d'):format(p.move,p.hit),left,y+h-23,available,'left',fonts.stat)
  else
    local fort=state.forts[inspectedFortOwner or 3-state.turn]
    color(teamColors[fort.owner]);love.graphics.polygon('fill',faceHex(ix,iy,thumb*.44))
    love.graphics.setColor(.84,.78,.65)
    love.graphics.rectangle('fill',ix-thumb*.31,iy-thumb*.08,thumb*.62,thumb*.39)
    for n=-1,1 do
      love.graphics.rectangle('fill',ix+n*thumb*.23-thumb*.10,iy-thumb*.29,thumb*.20,thumb*.22)
    end
    love.graphics.setColor(.2,.15,.10)
    love.graphics.rectangle('fill',ix-thumb*.10,iy+thumb*.08,thumb*.20,thumb*.24)
    local left=ix+thumb*.5+9
    text(('P%d FORTRESS'):format(fort.owner),left,y+7,w-(left-x)-8,'left',fonts.medium)
    text(('HP %d / %d'):format(fort.hp,rules.FORT_HP),left,y+31,w-(left-x)-8,'left',fonts.stat)
    text(('DEFENSE HIT %d'):format(rules.FORT_HIT),left,y+h-23,w-(left-x)-8,'left',fonts.stat)
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
local EXCHANGE_SECONDS = 2.85
local FINAL_BLOW_HOLD = .72
local function battleFrame()
  local event=overlay.event
  local count=#(event.rounds or {})
  local elapsed=math.max(0,overlay.elapsed)
  local finalMoment=elapsed>=count*EXCHANGE_SECONDS
  local finished=elapsed>=count*EXCHANGE_SECONDS+FINAL_BLOW_HOLD
  local index=finalMoment and count or math.min(count,math.floor(elapsed/EXCHANGE_SECONDS)+1)
  local phase=finalMoment and EXCHANGE_SECONDS or (elapsed%EXCHANGE_SECONDS)
  local round=event.rounds[index]
  local previous=event.rounds[index-1]
  local applied=finished or phase>=2.00
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
  elseif kind=='assassin' then
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
local function drawCombatant(kind,cx,cy,rad,team,impact)
  -- Show the FULL class art, without cropping the six corners into a circle.
  local sprite=unitArt[team] and unitArt[team][kind]
  if impact then
    love.graphics.setColor(.98,.34,.22,.32)
    love.graphics.polygon('fill',faceHex(cx,cy,rad*1.17))
  else
    color(teamColors[team] or palette.gold,.78)
    love.graphics.polygon('fill',faceHex(cx,cy,rad*1.06))
  end
  if sprite then
    drawBadgeSprite(sprite,cx,cy,rad/BADGE_R,true)
  elseif kind=='fortress' then
    -- Low, defensive battlements instead of a peaked castle.
    love.graphics.setColor(.77,.72,.64,1)
    love.graphics.rectangle('fill',cx-rad*.7,cy-rad*.24,rad*1.4,rad*.96)
    for i=-2,2 do
      love.graphics.rectangle('fill',cx+i*rad*.29-rad*.1,cy-rad*.52,rad*.20,rad*.31)
    end
    love.graphics.setColor(.19,.15,.12,1)
    love.graphics.rectangle('fill',cx-rad*.20,cy+rad*.19,rad*.40,rad*.52)
  else
    drawBattleFigure(kind,cx,cy,rad)
  end
end
-- Faceted 3D-looking octahedral D8. Animated values are only visual;
-- the final dice results are read from the deterministic rules event.
-- Render an actual three-dimensional octahedral die (8 triangular faces).
-- The rolling angle is visual only, never changes the authoritative dice RNG.
local OCTA={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}}
local FACES={{1,3,5},{1,3,6},{1,4,5},{1,4,6},
             {2,3,5},{2,3,6},{2,4,5},{2,4,6}}
local function drawD8(cx,cy,n,winning,rolling,team)
  local g=love.graphics
  local r=math.min(46,layout.w*.108)
  local theta=love.timer.getTime()*11.3
  local rx=rolling and (.47+theta*.9) or .58
  local ry=rolling and (-.35+theta*.64) or -.48
  local rz=rolling and (.15+theta*.36) or .18
  local sx,cx0=math.sin(rx),math.cos(rx)
  local sy,cy0=math.sin(ry),math.cos(ry)
  local sz,cz=math.sin(rz),math.cos(rz)
  local bob=rolling and math.abs(math.sin(theta*.7))*r*.13 or 0
  cy=cy-bob
  local v={}
  for i,pt in ipairs(OCTA) do
    local x,y,z=pt[1],pt[2]*cx0-pt[3]*sx,pt[2]*sx+pt[3]*cx0
    local xx,zz=x*cy0+z*sy,-x*sy+z*cy0
    local xxx,yyy=xx*cz-y*sz,xx*sz+y*cz
    local persp=1/(1-.17*zz)
    v[i]={x=cx+xxx*r*persp,y=cy+yyy*r*persp,
      xx=xxx,yy=yyy,zz=zz}
  end
  -- Soft contact shadow makes the rolling die read as a solid object.
  g.setColor(.02,.03,.05,.45)
  g.polygon('fill',cx-r*.8,cy+r*1.1,cx+r*.8,cy+r*1.1,
    cx+r*.58,cy+r*1.26,cx-r*.58,cy+r*1.26)
  -- Permanent kingdom colors, never the old unrelated gold-versus-blue dice.
  local base=team==1 and {.91,.30,.34} or {.35,.63,.98}
  local visible={}
  for _,face in ipairs(FACES) do
    local a,b,c=v[face[1]],v[face[2]],v[face[3]]
    local dx,dy,dz=b.xx-a.xx,b.yy-a.yy,b.zz-a.zz
    local ex,ey,ez=c.xx-a.xx,c.yy-a.yy,c.zz-a.zz
    local nx,ny,nz=dy*ez-dz*ey,dz*ex-dx*ez,dx*ey-dy*ex
    local mx,my,mz=(a.xx+b.xx+c.xx)/3,(a.yy+b.yy+c.yy)/3,(a.zz+b.zz+c.zz)/3
    if nx*mx+ny*my+nz*mz<0 then nz=-nz end
    if nz>0.01 then
      visible[#visible+1]={a=a,b=b,c=c,nz=nz,depth=mz,
        px=(a.x+b.x+c.x)/3,py=(a.y+b.y+c.y)/3}
    end
  end
  table.sort(visible,function(a,b)return a.depth<b.depth end)
  local front
  for _,f in ipairs(visible) do
    local shade=.49+.45*math.min(1,f.nz)
    g.setColor(math.min(1,base[1]*shade),math.min(1,base[2]*shade),
      math.min(1,base[3]*shade),1)
    g.polygon('fill',f.a.x,f.a.y,f.b.x,f.b.y,f.c.x,f.c.y)
    g.setColor(.08,.11,.17,.96)
    g.setLineWidth(math.max(1.3,r*.044))
    g.polygon('line',f.a.x,f.a.y,f.b.x,f.b.y,f.c.x,f.c.y)
    g.setColor(1,1,1,.20)
    g.line(f.a.x,f.a.y,f.b.x,f.b.y)
    if not front or f.nz>front.nz then front=f end
  end
  if front then
    g.setColor(.04,.07,.11,1)
    g.setFont(fonts.large)
    local fh=fonts.large.getHeight and fonts.large:getHeight() or r*.66
    g.printf(tostring(n),front.px-r*.43,front.py-fh*.5,r*.86,'center')
  end
end

-- Angled, arcade-style result strip, including a flat/text fallback for
-- mocked LÖVE renderers that don't implement transformation methods.
local function arcadeBanner(label,x,y,w,h,owner)
  local g=love.graphics
  g.setColor(.025,.035,.05,.95)
  g.polygon('fill',x+9,y,x+w,y-8,x+w-9,y+h,x,y+h+8)
  local tone=owner==1 and {.72,.22,.27} or owner==2 and {.20,.40,.75} or {.47,.41,.37}
  g.setColor(tone[1],tone[2],tone[3],1)
  g.polygon('fill',x+6,y+4,x+w-4,y-3,x+w-11,y+h-5,x-1,y+h+3)
  g.setColor(.98,.86,.55,1)
  g.setLineWidth(2.2)
  g.line(x+6,y+5,x+w-4,y-3)
  local font=(#label>25) and fonts.small or fonts.large
  if g.push and g.translate and g.rotate then
    g.push()
    g.translate(x+w*.5,y+h*.46)
    g.rotate(-.042)
    text(label,-w*.47,-(font.getHeight and font:getHeight() or 23)*.48,w*.94,'center',font)
    g.pop()
  else
    text(label,x+8,y+h*.30,w-16,'center',font)
  end
end

local function drawBattleOverlay()
  local w,h=layout.w,layout.h
  love.graphics.setColor(0,0,0,.80)
  love.graphics.rectangle('fill',0,0,w,h)
  local ww=w-12
  local hh=math.min(h-12,620)
  local x,y=6,(h-hh)/2
  panel(x,y,ww,hh)
  local event=overlay.event
  local index,count,round,phase,finished,ah,dh=battleFrame()
  local at=rules.classes[event.attackerClass]
  local dt=rules.classes[event.defenderClass]
  local defenderName=dt and dt.name or 'Fortress'
  if finished then
    ah=event.attackerHpAfter or ah
    dh=event.defenderHpAfter or dh
  end
  local cx1,cx2=x+ww*.255,x+ww*.745
  local py=y+hh*.29
  local radius=math.min(ww*.155,hh*.115,54)
  local shown=finished or phase>=1.12
  local applied=finished or phase>=2
  local impact=not finished and applied and (phase<2.70 or index==count) and round.who~='tie'
  local lunge=impact and radius*.14 or 0
  local ax=cx1+(round and round.who=='attacker' and lunge or 0)
  local dx=cx2-(round and round.who=='defender' and lunge or 0)
  local redName='RED'
  local blueName='BLUE'
  local leftTeam=event.actor==1 and redName or blueName
  local rightTeam=event.actor==1 and blueName or redName
  local leftName=leftTeam..' '..at.name:upper()
  local rightName=rightTeam..' '..defenderName:upper()
  text('BATTLE',x+7,y+hh*.03,ww-14,'center',fonts.large)
  text(('ROUND %d / %d'):format(index,count),x+7,y+hh*.105,ww-14,'center',fonts.small)
  text(leftName,cx1-ww*.24,y+hh*.14,ww*.48,'center',fonts.small)
  text(rightName,cx2-ww*.24,y+hh*.14,ww*.48,'center',fonts.small)
  drawCombatant(event.attackerClass,ax,py,radius,event.actor,
    impact and round.who=='defender')
  drawCombatant(event.defenderClass,dx,py,radius,3-event.actor,
    impact and round.who=='attacker')
  local barY=y+hh*.435
  healthBar(cx1-ww*.215,barY,ww*.43,11,ah,at.hp)
  healthBar(cx2-ww*.215,barY,ww*.43,11,dh,dt and dt.hp or rules.FORT_HP)
  text(('HP %d/%d'):format(ah,at.hp),cx1-ww*.23,barY+13,ww*.46,'center',fonts.medium)
  text(('HP %d/%d'):format(dh,dt and dt.hp or rules.FORT_HP),cx2-ww*.23,barY+13,ww*.46,'center',fonts.medium)
  local dieY=y+hh*.595
  local a,b
  if shown then a,b=round.a,round.b else
    a=1+(math.floor(math.max(0,overlay.elapsed)*21)+index*3)%8
    b=1+(math.floor(math.max(0,overlay.elapsed)*17)+index*5)%8
  end
  drawD8(cx1,dieY,a,shown and round.who=='attacker',not shown,event.actor)
  drawD8(cx2,dieY,b,shown and round.who=='defender',not shown,3-event.actor)
  -- Short labels only. Impact bubbles live on the injured character.
  local msg='ROLLING…'
  if finished then
    local winLeft=event.attackerHpEnd>0
    local winner=winLeft and leftName or rightName
    local winnerOwner=winLeft and event.actor or 3-event.actor
    local rewardShown=event.heal and overlay.healRevealed
    local rewardSettled=rewardShown and (not overlay.healRolling or overlay.healRolling>=.9)
    if rewardShown then
      if rewardSettled then
        local added=event.heal.actual
        arcadeBanner(added>0 and ('HEALTH BONUS +'..added..' HP!') or 'HEALTH FULL',
          x+10,y+hh*.704,ww-20,math.min(54,hh*.10),winnerOwner)
      else
        arcadeBanner('HEALTH BONUS!',x+10,y+hh*.704,ww-20,
          math.min(54,hh*.10),winnerOwner)
      end
    else
      arcadeBanner(event.finish=='fortress' and (leftTeam..' WINS THE MATCH!')
        or (winner..' WINS!'),x+10,y+hh*.704,ww-20,
        math.min(54,hh*.10),winnerOwner)
    end
  else
    if shown then
      if round.who=='tie' then
        msg='TIE — ROLL AGAIN'
      else
        msg=(round.who=='attacker' and leftTeam or rightTeam)..' HITS!'
      end
    end
    text(msg,x+8,y+hh*.765,ww-16,'center',fonts.medium)
    if applied and round.who~='tie' then
      local victim=round.who=='attacker' and cx2 or cx1
      local bubbleY=py-radius*.9-math.min(15,(phase-2)*16)
      -- Reproducible visual-only sparks and impact arcs; no new RNG,
      -- textures, networking or gameplay state required.
      local sparkT=math.max(0,math.min(1,(phase-2)/.72))
      for k=1,6 do
        local angle=k*math.pi/3+.13
        local rr=radius*(.18+.66*sparkT)
        local xx,yy=victim+math.cos(angle)*rr,py+math.sin(angle)*rr
        love.graphics.setColor(1,.76,.31,.9*(1-sparkT))
        love.graphics.setLineWidth(math.max(1.5,radius*.045))
        love.graphics.line(xx,yy,xx+math.cos(angle)*radius*.28,
          yy+math.sin(angle)*radius*.28)
      end
      love.graphics.setColor(.15,.05,.07,.92)
      love.graphics.rectangle('fill',victim-40,bubbleY-14,80,32,12,12)
      love.graphics.setColor(1,.38,.32,1)
      love.graphics.setFont(fonts.medium)
      love.graphics.printf('-'..round.damage,victim-40,bubbleY-10,80,'center')
    end
  end
  overlay.continueBox=nil
  overlay.healRollBox=nil
  if not finished then return end
  local by=y+hh-57
  local canHeal=event.heal~=nil and overlay.healRevealed~=true
  if canHeal then
    local winner=event.heal.owner==1 and 'RED' or 'BLUE'
    if hh>=500 then text(winner..' VICTORY BONUS — ROLL YOUR D8',
      x+12,y+hh*.835,ww-24,'center',fonts.stat) end
    love.graphics.setColor(.34,.56,.24,1)
    love.graphics.rectangle('fill',x+ww*.14,by,ww*.72,46,10,10)
    text('ROLL FOR +1 TO +8 HP',x+ww*.15,by+10,ww*.70,'center',fonts.stat)
    overlay.healRollBox={x=x+ww*.14,y=by,w=ww*.72,h=46}
  else
    if event.heal then
      local result=event.heal
      local rolling=overlay.healRolling and overlay.healRolling<.9
      local face=rolling and 1+(math.floor(overlay.healRolling*23)%8) or result.roll
      -- Reward is resolved in rules.apply and never depends on presentation.
      if rolling and hh>=520 then
        text('ROLLING BONUS D8…',x+12,y+hh*.84,ww-24,'center',fonts.stat)
      end
      if rolling then
        drawD8(x+ww*.5,y+hh*.61,face,true,true,event.heal.owner)
        return
      end
    end
    love.graphics.setColor(.20,.59,.38,1)
    love.graphics.rectangle('fill',x+ww*.14,by,ww*.72,46,10,10)
    text('CONTINUE',x+ww*.15,by+10,ww*.70,'center',fonts.medium)
    overlay.continueBox={x=x+ww*.14,y=by,w=ww*.72,h=46}
  end
end
local VOLLEY_SECONDS=2.9
local function drawSiegeOverlay()
  local w,h=layout.w,layout.h
  love.graphics.setColor(0,0,0,.74);love.graphics.rectangle('fill',0,0,w,h)
  local ww,hh=w-16,math.min(h-22,610)
  local x,y=8,(h-hh)/2
  panel(x,y,ww,hh)
  local count=#overlay.rounds
  local elapsed=math.max(0,overlay.elapsed)
  local finished=elapsed>=count*VOLLEY_SECONDS
  local index=finished and count or math.min(count,math.floor(elapsed/VOLLEY_SECONDS)+1)
  local phase=finished and VOLLEY_SECONDS or elapsed%VOLLEY_SECONDS
  local volley=overlay.rounds[index]
  local previous=overlay.rounds[index-1]
  local hit=finished or phase>=1.85
  local hp1=hit and volley and volley.h1 or previous and previous.h1 or overlay.start.h1
  local hp2=hit and volley and volley.h2 or previous and previous.h2 or overlay.start.h2
  local showDie=finished or phase>=1.00
  local base1=x+ww*.255;local base2=x+ww*.745
  local rad=math.min(ww*.145,hh*.11,50)
  text('THE FINAL SIEGE',x+8,y+hh*.03,ww-16,'center',fonts.large)
  text(('TREBUCHET VOLLEY %d / %d'):format(index,count),x+8,y+hh*.12,ww-16,'center',fonts.small)
  text('RED FORTRESS',base1-ww*.23,y+hh*.185,ww*.46,'center',fonts.small)
  text('BLUE FORTRESS',base2-ww*.23,y+hh*.185,ww*.46,'center',fonts.small)
  local pY=y+hh*.31
  drawCombatant('fortress',base1,pY,rad,1,hit and volley.hit2>0)
  drawCombatant('fortress',base2,pY,rad,2,hit and volley.hit1>0)
  local barY=y+hh*.44
  healthBar(base1-ww*.21,barY,ww*.42,12,hp1,rules.FORT_HP)
  healthBar(base2-ww*.21,barY,ww*.42,12,hp2,rules.FORT_HP)
  text(('HP %d / %d'):format(hp1,rules.FORT_HP),base1-ww*.22,barY+15,ww*.44,'center',fonts.medium)
  text(('HP %d / %d'):format(hp2,rules.FORT_HP),base2-ww*.22,barY+15,ww*.44,'center',fonts.medium)
  local n1,n2
  if showDie then n1,n2=volley.a,volley.b
  else n1=1+(math.floor(elapsed*22)+index*3)%8
    n2=1+(math.floor(elapsed*19)+index*5)%8 end
  local dieY=y+hh*.62
  drawD8(base1,dieY,n1,showDie and volley.hit1>0,not showDie,1)
  drawD8(base2,dieY,n2,showDie and volley.hit2>0,not showDie,2)
  local msg='BOTH TREBUCHETS PREPARE TO FIRE…'
  local detail='Each shot rolls D8; rolls 4–8 hit for 7 HP.'
  if finished then
    if state.winner==0 then
      msg='MUTUALLY ASSURED DESTRUCTION'
      detail='Two kingdoms fought to conquer. Both lost everything.'
    else
      msg=(state.winner==1 and 'RED' or 'BLUE')..' KINGDOM CONQUERS!'
      detail='The enemy Fortress has collapsed.'
    end
  elseif showDie then
    if hit then
      msg='VOLLEY IMPACT!'
      local a=volley.hit1>0 and ('RED DEALS '..volley.hit1..' HP') or 'RED MISSES'
      local b=volley.hit2>0 and ('BLUE DEALS '..volley.hit2..' HP') or 'BLUE MISSES'
      detail=a..'    •    '..b
    else msg='BOTH TREBUCHETS FIRE!' end
  end
  text(msg,x+10,y+hh*.755,ww-20,'center',fonts.medium)
  text(detail,x+12,y+hh*.82,ww-24,'center',fonts.small)
  if finished then
    local by=y+hh-57
    love.graphics.setColor(.21,.58,.36,1)
    love.graphics.rectangle('fill',x+ww*.15,by,ww*.70,46,9,9)
    text('CONTINUE',x+ww*.16,by+10,ww*.68,'center',fonts.medium)
    overlay.continueBox={x=x+ww*.15,y=by,w=ww*.70,h=46}
  else overlay.continueBox=nil end
end
local function drawFinished()
  love.graphics.setColor(0,0,0,.77)
  love.graphics.rectangle('fill',0,0,layout.w,layout.h)
  local ww=layout.w*.94
  local hh=math.min(338,layout.h*.57)
  local x,y=(layout.w-ww)/2,(layout.h-hh)/2
  panel(x,y,ww,hh)
  local t=math.max(0,finishElapsed)
  local progress=math.min(1,t/1.05)
  local cx,cy=x+ww*.5,y+hh*.29
  local r=math.min(50,ww*.15,hh*.21)
  -- A squat fortified gate crumbles into small, fading fragments.
  -- Keep the artwork's approved low-battlement style, not a pointed castle.
  love.graphics.setColor(.65,.61,.53,1)
  love.graphics.rectangle('fill',cx-r*.76,cy-r*.20,r*1.52,r*.83)
  love.graphics.rectangle('fill',cx-r*.70,cy-r*.42,r*.27,r*.26)
  love.graphics.rectangle('fill',cx+r*.43,cy-r*.42,r*.27,r*.26)
  love.graphics.setColor(.20,.16,.13,1)
  love.graphics.rectangle('fill',cx-r*.19,cy+r*.20,r*.38,r*.43)
  local pulse=(1-progress)*r*.72
  for i=1,9 do
    local angle=i*2*math.pi/9
    local travel=r*.36+progress*r*1.45
    local px=cx+math.cos(angle)*travel
    local py=cy+math.sin(angle)*travel
    love.graphics.setColor(.93,.72,.37,1-progress*.95)
    love.graphics.rectangle('fill',px,py,math.max(2,r*.14*(1-progress*.7)),
      math.max(2,r*.12*(1-progress*.7)))
  end
  if pulse>0 then
    love.graphics.setColor(1,.78,.36,.75*(1-progress))
    love.graphics.setLineWidth(math.max(2,r*.07))
    love.graphics.circle('line',cx,cy,r*.75+(1-progress)*r*.7)
  end
  local isMutual=state.winner==0
  local owner=state.winner
  local banner=isMutual and 'MUTUALLY ASSURED DESTRUCTION'
    or (mode=='solo' and (owner==1 and 'VICTORY!' or 'DEFEAT!'))
    or ((owner==1 and 'RED' or 'BLUE')..' KINGDOM WINS!')
  local labelFont=isMutual and fonts.small or fonts.large
  local labelY=y+hh*.59
  if t>.36 then
    love.graphics.setColor(isMutual and .68 or .85,
      isMutual and .42 or .61,isMutual and .37 or .29,.93)
    love.graphics.rectangle('fill',x+ww*.09,labelY-8,ww*.82,3)
    text(banner,x+ww*.07,labelY,ww*.86,'center',labelFont)
    if isMutual then
      text('Both kingdoms fell.',x+12,y+hh*.76,ww-24,'center',fonts.medium)
    elseif owner==1 then
      text('The Red Kingdom has conquered!',x+12,y+hh*.76,ww-24,'center',fonts.small)
    else
      text('The Blue Kingdom has conquered!',x+12,y+hh*.76,ww-24,'center',fonts.small)
    end
  end
  text('Use the Zompa Back button to leave.',x+12,y+hh-33,ww-24,'center',fonts.small)
end
local function showEvent(event)
  selected,inspected,targets,intended=nil,nil,{},nil
  if event and event.type=='attack' then
    local winner=event.attackerHpEnd>0 and event.actor or 3-event.actor
    local autoHeal=(mode=='solo' and winner==2)
    overlay={type='battle',event=event,elapsed=-.3,shown=0,
      autoHeal=autoHeal,healRevealed=false,healRolling=nil}
  elseif event and event.siege then
    overlay={type='siege',rounds=event.siege,start=event.siegeStart,elapsed=-.25,shown=0}
  end
end
-- Animate the piece over every square along the legal route, then open battle.
-- The deterministic game state is already committed, so animation is visual only.
local function beginEvent(event,previous)
  selected,inspected,targets,intended=nil,nil,{},nil
  if event and event.id and event.from and event.to and previous then
    local route=rules.route(previous,event.id,event.to.r,event.to.c)
    if route and #route>=2 then
      local unit=previous.units[event.id]
      moving={id=event.id,route=route,event=event,class=unit and unit.class,
        elapsed=0,duration=.92+math.max(0,#route-2)*.25}
      queuedEvent=event
      timers.cpu=0
      overlay=nil
      return
    end
  end
  showEvent(event)
end
local function sessionSave()
  if mode=='online' then return end
  local ok,err
  if state.winner~=nil then ok,err=zompa.clearSession()
  else ok,err=zompa.saveSession(rules.serialize(state)) end
  if not ok then print('Session save failed: '..tostring(err)) end
end
local function localAction(action)
  local previous=rules.copy(state)
  local ok,event=rules.apply(state,action)
  if not ok then notice=event;return false end
  sessionSave()
  beginEvent(event,previous)
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
  local oldState=state
  state=newState
  if #history==oldCount+1 and newState.last then beginEvent(newState.last,oldState) end
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
  return state and state.winner==nil and not overlay and not moving and not blocked and
    (mode=='online' and onlineReady and onlineAllowed and state.turn==onlineSide and not pending or
    mode=='solo' and state.turn==1 or mode=='local')
end
local function drawActionBar()
  actionBox,cancelBox=nil,nil
  local x,y,w,h=6,layout.actionY,layout.w-12,47
  if intended and selected and mayAct() then
    local isAttack=intended.type=='attack'
    local confirmW=w*.73
    love.graphics.setColor(isAttack and .72 or .23,isAttack and .25 or .71,isAttack and .22 or .44,1)
    love.graphics.rectangle('fill',x,y,confirmW,h,10,10)
    love.graphics.setColor(1,1,1,1)
    love.graphics.setFont(fonts.medium)
    love.graphics.printf(isAttack and 'ATTACK NOW' or 'MOVE HERE',x,y+9,confirmW,'center')
    love.graphics.setColor(.27,.31,.32,1)
    love.graphics.rectangle('fill',x+confirmW+5,y,w-confirmW-5,h,10,10)
    text('CANCEL',x+confirmW+5,y+14,w-confirmW-5,'center',fonts.small)
    actionBox={x=x,y=y,w=confirmW,h=h}
    cancelBox={x=x+confirmW+5,y=y,w=w-confirmW-5,h=h}
  else
    local label
    if moving then label=moving.event.actor==2 and 'BLUE KINGDOM MOVES' or 'RED KINGDOM MOVES'
    elseif mode=='solo' and state.turn==2 then label='BLUE KINGDOM IS THINKING…'
    elseif selected then label='TAP A GLOWING SPACE'
    else label='PLAYER '..state.turn..'  •  CHOOSE A PIECE' end
    love.graphics.setColor(.11,.15,.17,.96)
    love.graphics.rectangle('fill',x,y,w,h,9,9)
    color(palette.text);love.graphics.setFont(fonts.small)
    love.graphics.printf(label,x+4,y+14,w-8,'center')
  end
end
local function actorAction(action)
  if not mayAct() then return end
  if mode=='online' then sendOnline(action) else localAction(action) end
end
local function computerAction()
  if state.winner~=nil or state.turn~=2 or overlay or moving then return end
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
  -- Threat proximity is a low-cost tactical approximation (not a new rule).
  -- It helps the CPU guard the Fortress and protect wounded soldiers without
  -- running hundreds of hypothetical full battles per turn on a phone.
  local function exposureAt(row,col,ownHP)
    local exposure=0
    for _,enemy in ipairs(state.units) do
      if enemy.owner==1 and enemy.hp>0 then
        local d=rules.distance({r=row,c=col},enemy)
        if d<=rules.classes[enemy.class].move then
          exposure=exposure+(rules.classes[enemy.class].hit/6)
            * (enemy.hp>=ownHP and 5 or 2.2)
        end
      end
    end
    return math.min(22,exposure)
  end
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
        if v and enemy then
          -- Compare how many successful D8 exchanges each combatant needs.
          local ourHits=math.ceil(v.hp/own.hit)
          local theirHits=math.ceil(u.hp/enemy.hit)
          score=score+(theirHits-ourHits)*4.5
          if theirHits<ourHits then score=score-7 end
        end
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
      score=score-exposureAt(a.r,a.c,u.hp)
      -- Defenders within striking distance of our Fortress are urgent.
      local homeThreat=0
      for _,enemy in ipairs(state.units) do
        if enemy.owner==1 and enemy.hp>0 and rules.distance(enemy,ownF)<=3 then
          homeThreat=homeThreat+1
        end
      end
      if homeThreat>0 and defender<=3 then
        score=score+math.min(14,homeThreat*3)
      end
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
  if moving then return end
  if overlay then
    if overlay.type=='battle' and inside(overlay.healRollBox,x,y) then
      overlay.healRevealed=true
      overlay.healRolling=0
      overlay.healRollBox=nil
      return
    end
    local b=overlay.continueBox
    if not inside(b,x,y) then return end
    if overlay.type=='battle' and overlay.event.siege then
      overlay={type='siege',rounds=overlay.event.siege,start=overlay.event.siegeStart,elapsed=-0.3,shown=0}
    else overlay=nil end
    return
  end
  if state.winner~=nil then return end
  if inside(cardBox,x,y) then return end
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
  if love.graphics.newImage then
    local ok,img=pcall(love.graphics.newImage,'art/board.png')
    if ok and img then artBoard=img; if img.setFilter then img:setFilter('linear','linear') end end
    for owner=1,2 do
      for name,_ in pairs(rules.classes) do
        local ok2,sp=pcall(love.graphics.newImage,('art/%s-%d.png'):format(name,owner))
        if ok2 and sp then unitArt[owner][name]=sp
          if sp.setFilter then sp:setFilter('linear','linear') end end
      end
    end
  end
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
  moving,queuedEvent,cardBox=nil,nil,nil
  finishElapsed=0
  timers.cpu,timers.poll=0,0
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
  if moving then
    moving.elapsed=moving.elapsed+dt
    if moving.elapsed>=moving.duration then
      moving=nil
      local ev=queuedEvent;queuedEvent=nil
      if ev then showEvent(ev) end
    end
  end
  if overlay then
    overlay.elapsed=overlay.elapsed+dt
    if overlay.type=='battle' and overlay.autoHeal and not overlay.healRevealed
      and overlay.elapsed>=#overlay.event.rounds*EXCHANGE_SECONDS+FINAL_BLOW_HOLD then
      -- The CPU visibly rolls after the result, not offscreen during combat.
      overlay.healRevealed=true
      overlay.healRolling=0
    elseif overlay.healRolling then
      overlay.healRolling=overlay.healRolling+dt
    end
  elseif state and state.winner~=nil then
    finishElapsed=math.min(4,finishElapsed+dt)
  end
  if state and state.winner==nil and not overlay and not moving and not pending then
    if mode=='solo' and state.turn==2 then
      timers.cpu=timers.cpu+dt
      if timers.cpu>1.1 then timers.cpu=0;computerAction() end
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
  -- A quiet stone-toned stage avoids a separate black rectangle around the board.
  love.graphics.setColor(.15,.16,.17,1)
  love.graphics.rectangle('fill',0,0,layout.w,layout.h)
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
