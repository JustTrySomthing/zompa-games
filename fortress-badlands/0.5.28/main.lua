-- Fortress Siege: Final Conquest — Zompa SDK v4 / LÖVE 11.5 graybox prototype.
-- This game's deterministic rules are shared by solo, pass-and-play, and turns-v1 online.
local rules = require('rules')
local zompa = require('zompa')
local chooseCpuAction = require('cpu')
local mode = 'solo'
local state, onlineSide, onlineAllowed, onlineReady, lastOnlineCount
local selected, inspected, targets, pending, overlay, intended, actionBox, cancelBox, inspectedFortOwner
local layout, timers, notice, blocked = {}, {cpu=0,poll=0,dialog=0}, '', nil
local saveVersionChanged,turnSendFailed
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
  ogre={0.43,0.50,0.29}, archer={0.67,0.48,0.29},
}
local teamColors={[1]={0.50,0.15,0.20},[2]={0.15,0.30,0.46}}
local fonts={}
local teamNames={'Red','Blue'}
local teamLabels={{1,.52,.46},{.55,.79,1}}
local onlineOpeningPrompt={}
local intro, logo, horn
local introTime=0
local function smoothstep(t)
  t=math.max(0,math.min(1,t))
  return t*t*(3-2*t)
end
local artBoard, unitArt = nil, { [1]={}, [2]={} }
-- Individually loaded character busts and board tokens; never a flattened UI.
local portraitArt,fortArt = { [1]={}, [2]={} }, {}
local fighterArt = {{},{}}
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
-- Truly edge-sharing point-up hexagon positions. Display coordinates are
-- staggered but game indexes/rules remain the existing 7x10, 58-cell graph.
-- Adjacent flat stone edges now meet without empty channels or overlaps.
local SQRT3=math.sqrt(3)
local function center(r,c)
  local n=rules.rowWidths[r+1]
  return layout.x+layout.hexStepX*(c+.5+(rules.COLS-n)*.5),
         layout.y+layout.hexR+layout.hexStepY*r
end
local function xyToCell(x,y)
  -- Hit test against the *drawn* hexagon, not a phantom square slot.
  -- Only 56 cells are checked. The touch polygon is the visible hex itself.
  local R=layout.hexR
  for r=0,rules.ROWS-1 do
    for c=0,rules.COLS-1 do
      if rules.playable(r,c) then
        local hx,hy=center(r,c)
        local dx,dy=math.abs(x-hx),math.abs(y-hy)
        if dx<=SQRT3*R*.5+0.4 and
           dy<=R-dx/SQRT3+0.4 then
          return {r=r,c=c}
        end
      end
    end
  end
  return nil
end
local function fontHeight(font)
  return font.getHeight and font:getHeight() or font.size
end
local function reflow(viewportW,viewportH)
  -- Keep the board upright in a centered portrait stage on wide displays.
  local w=math.max(1,math.min(viewportW,math.floor(viewportH*.76)))
  local safeBottom=viewportH
  if love.window and love.window.getSafeArea then
    local _,y,_,safeH=love.window.getSafeArea()
    if safeH and safeH>0 then safeBottom=math.min(viewportH,y+safeH) end
  end
  -- Leave room inside the hosted canvas for Android's bottom chrome.
  local h=safeBottom-math.min(36,math.max(24,safeBottom*.06))
  local uiScale=math.min(1,h/540)
  local function responsiveFont(target, noSmaller, noLarger)
    return love.graphics.newFont(math.floor(math.max(noSmaller,math.min(noLarger,target*uiScale))+.5))
  end
  fonts.small=responsiveFont(w*.046,11,19)
  fonts.stat=responsiveFont(w*.044,12,18)
  fonts.medium=responsiveFont(w*.055,14,24)
  fonts.large=responsiveFont(w*.079,16,34)
  fonts.finale=responsiveFont(w*.12,22,52)
  local statH,titleH=fontHeight(fonts.stat),fontHeight(fonts.medium)
  fonts.cardStat=responsiveFont(w*.041,11,16)
  fonts.cardHint=responsiveFont(w*.031,10,14)
  local statPadding=5
  local cardStatH=fontHeight(fonts.cardStat)
  local statBandH=2*cardStatH+statPadding*2+4
  local cardHintH=fontHeight(fonts.cardHint)+3
  local cardH=6+titleH+2+statH+4+statBandH+cardHintH+7
  local topReserve=cardH+10
  local actionH=math.floor(math.max(36,48*uiScale)+.5)
  local bottomReserve=actionH+12
  local boundW=7*SQRT3
  local boundH=17
  local R=math.max(4,math.min((w-8)/boundW,
    (h-topReserve-bottomReserve-7)/boundH))
  local boardW,boardH=boundW*R,boundH*R
  local top=topReserve+math.max(0,(h-topReserve-bottomReserve-boardH)*.5)
  layout={w=w,h=h,viewportW=viewportW,stageX=math.floor((viewportW-w)*.5),viewportH=viewportH,hexR=R,hexStepX=SQRT3*R,hexStepY=1.5*R,
    -- Keep the established sprite fit and all existing UI sizing hooks.
    scale=(R*.93)/60,cell=SQRT3*R,radius=R*.84,
    tileW=SQRT3*R,rowH=R*1.5,
    x=(w-boardW)*.5,y=top,boardW=boardW,boardH=boardH,
    cardY=3,cardH=cardH,topReserve=topReserve,
    statBandH=statBandH,statPadding=statPadding,cardHintH=cardHintH,
    actionH=actionH,actionY=top+boardH+7}
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

-- Piece art is full-bleed and centered. The same mask and border are used
-- on the board, in the fortress inspector and in battles.
local BADGE_R=60
local function drawBadgeSprite(sprite,x,y,scale,cutout)
  local g=love.graphics
  local borderR=BADGE_R*scale*.88
  local stencil=g.stencil and g.setStencilTest
  if stencil then
    g.stencil(function()
      g.polygon('fill',faceHex(x,y,borderR))
    end,'replace',1)
    g.setStencilTest('greater',0)
  end
  g.setColor(1,1,1,1)
  local iw,ih=sprite:getDimensions()
  local side=borderR*2
  g.draw(sprite,x-borderR,y-borderR,0,side/iw,side/ih)
  if stencil then g.setStencilTest() end
  -- Thin, uninterrupted outer edge. No offset shadow hex or extra left lip.
  g.setColor(.97,.78,.35,1)
  g.setLineWidth(math.max(1.05,2.0*scale))
  g.polygon('line',faceHex(x,y,borderR))
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
  elseif kind=='archer' then
    love.graphics.line(cx-rad*.42,cy-rad*.67,cx+rad*.28,cy-rad*.38,
      cx+rad*.42,cy,cx+rad*.28,cy+rad*.38,cx-rad*.42,cy+rad*.67,cx-rad*.42,cy-rad*.67)
    love.graphics.line(cx-rad*.68,cy,cx+rad*.74,cy)
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
local function criticalPulse(cx,cy,rad,hp,maximum)
  if hp<=0 or hp>maximum*.25 then return end
  local g=love.graphics
  local pulse=.5+.5*math.sin(love.timer.getTime()*math.pi*1.6)
  g.setColor(1,.26,.18,.32+.53*pulse)
  g.setLineWidth(math.max(1.6,rad*.11))
  g.polygon('line',faceHex(cx,cy,rad*(.95+.07*pulse)))
end
local function unitToken(u)
  local cx,cy=center(u.r,u.c)
  local rad=layout.radius
  local sprite=unitArt[u.owner][u.class]
  if selected==u.id and not moving then
    local pulse=.26+.12*math.sin(love.timer.getTime()*4)
    love.graphics.setColor(1,.86,.4,pulse)
    love.graphics.circle('fill',cx,cy,rad*1.16)
  end
  if sprite then
    drawBadgeSprite(sprite,cx,cy,layout.scale,true)
  else
    color(teamColors[u.owner]);love.graphics.polygon('fill',faceHex(cx,cy,rad*.99))
    color(classColors[u.class]);love.graphics.polygon('fill',faceHex(cx,cy,rad*.82))
    emblem(u.class,cx,cy,rad*.48)
  end
  criticalPulse(cx,cy,rad,u.hp,rules.classes[u.class].hp)
  -- HP is in the inspection card; a small bar appears for injuries.
  if u.hp<rules.classes[u.class].hp then
    healthBar(cx-rad*.52,cy+rad*.90,rad*1.04,math.max(3.5,layout.cell*.06),
      u.hp,rules.classes[u.class].hp)
  end
end
-- Preserve the square 7x10 topology, its exact 58 centers and all 8
-- movement directions. Regular geometric hexes cannot tessellate this
-- orthogonal grid without moving centers or changing gameplay. Instead,
-- tightly packed six-sided flagstones are set into dark, continuous mortar.
-- No square tile outlines or smaller inset hexagons are drawn.
-- Painted flagstones: do not re-use the old 68px stone crop, because its
-- original center seam was repeating as a dark line in every hex. All
-- decoration stays inside the existing square-logical 58-space board.
local tileCanvas
local tileCanvas
-- Perfectly connected staggered hexes; the shared edge is a thin dark grout
-- line. Every stone has different deterministic wear, chips and cracks.
local function paintField()
  local g=love.graphics
  local R=layout.hexR
  for r=0,rules.ROWS-1 do
    for c=0,rules.COLS-1 do
      if rules.playable(r,c) then
        local x,y=center(r,c)
        local seed=(r*47+c*31+13)%97
        local t=(seed%15-7)*.009
        g.setColor(.59+t,.545+t*.7,.455+t*.6,1)
        g.polygon('fill',faceHex(x,y,R*1.002))
        g.setColor(.91,.85,.70,.16)
        g.polygon('fill',x-R*.24,y-R*.67,x+R*.26,y-R*.67,
          x+R*.48,y-R*.34,x+R*.11,y-R*.39,x-R*.14,y-R*.39)
        for k=1,7 do
          local a=((seed*7+k*43)%91)/91*math.pi*2
          local dist=R*(.1+((seed+k*13)%15)/43)
          local sx,sy=x+math.cos(a)*dist,y+math.sin(a)*dist
          local q=R*(.027+((seed+k*7)%9)/170)
          if k%2==0 then g.setColor(.22,.23,.19,.20)
          else g.setColor(.94,.89,.75,.16) end
          g.polygon('fill',sx-q,sy-q*.5,sx+q*.5,sy-q*.8,
            sx+q,sy+q*.36,sx-q*.7,sy+q*.55)
        end
        if seed%3~=0 then
          local sx,sy=x+R*((seed%11-5)/22),y+R*((seed%7-3)/18)
          g.setColor(.20,.22,.19,.20)
          g.setLineWidth(math.max(.55,R*.016))
          g.line(sx-R*.13,sy-R*.06,sx-R*.02,sy+R*.055,
            sx+R*.14,sy+R*.005)
        end
        g.setColor(.10,.10,.09,.94)
        g.setLineWidth(math.max(.8,math.min(1.3,R*.034)))
        g.polygon('line',faceHex(x,y,R*.996))
      end
    end
  end
end
-- Visible on every device: actual two-tower fortress, never dependent on
-- hidden source-board imagery, at (0,3) and (9,3).
local function fortressArt(x,y,owner,R)
  local g=love.graphics
  local image=fortArt[owner]
  if image then
    drawBadgeSprite(image,x,y,R/BADGE_R,true)
    return
  end
  if owner==1 then g.setColor(.36,.09,.12,1)
  else g.setColor(.08,.20,.38,1) end
  g.polygon('fill',faceHex(x,y,R*.98))
  g.setColor(.10,.09,.075,.4)
  g.polygon('fill',x-R*.74,y+R*.57,x+R*.74,y+R*.57,
    x+R*.53,y+R*.69,x-R*.53,y+R*.69)
  g.setColor(.59,.57,.51,1)
  g.rectangle('fill',x-R*.56,y-R*.21,R*1.12,R*.70)
  g.setColor(.84,.79,.68,1)
  g.rectangle('fill',x-R*.54,y-R*.19,R*1.08,R*.13)
  for _,sign in ipairs({-1,1}) do
    local tx=x+sign*R*.46
    g.setColor(.37,.37,.35,1)
    g.rectangle('fill',tx-R*.23,y-R*.50,R*.46,R*1.04)
    g.setColor(.72,.70,.63,1)
    g.rectangle('fill',tx-R*.20,y-R*.47,R*.40,R*.96)
    g.setColor(.87,.83,.73,1)
    for k=-1,1 do
      g.rectangle('fill',tx+k*R*.13-R*.054,y-R*.67,R*.108,R*.24)
    end
    g.setColor(.26,.28,.29,1)
    g.rectangle('fill',tx-R*.065,y-R*.15,R*.13,R*.23)
    g.setColor(.32,.31,.28,.45)
    g.line(tx-R*.16,y+R*.08,tx+R*.16,y+R*.08)
  end
  g.setColor(.17,.16,.14,1)
  g.rectangle('fill',x-R*.17,y+R*.12,R*.34,R*.40)
  g.circle('fill',x,y+R*.12,R*.17)
  g.setColor(.95,.79,.46,1)
  g.setLineWidth(math.max(1,R*.052))
  g.line(x,y-R*.78,x,y-R*.31)
  if owner==1 then g.setColor(.86,.19,.25,1)
  else g.setColor(.27,.55,.91,1) end
  g.polygon('fill',x,y-R*.76,x+R*.33,y-R*.64,x,y-R*.49)
  g.setColor(.98,.81,.43,1)
  g.setLineWidth(math.max(1,R*.046))
  g.polygon('line',faceHex(x,y,R*.98))
end
local function drawBoard()
  if tileCanvas==nil and love.graphics.newCanvas then
    -- A broken or unsupported canvas is retried only after a resize.
    tileCanvas=false
    local g=love.graphics
    local ok,canvas=pcall(g.newCanvas,layout.w,layout.h)
    if ok and canvas then
      -- A canvas must explicitly request a stencil buffer in LÖVE 11.5.
      -- If unavailable (older browser GPU), safely render uncached below.
      local setOk=pcall(g.setCanvas,{canvas,stencil=true})
      if setOk then
        g.clear(0,0,0,0)
        g.push()
        g.origin()
        local paintOk=pcall(paintField)
        g.pop()
        g.setCanvas()
        if paintOk then tileCanvas=canvas end
      end
    end
  end
  if tileCanvas then
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(tileCanvas,0,0)
  else
    paintField()
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
    if fort.hp>0 then
      fortressArt(cx,cy,fort.owner,rr)
      criticalPulse(cx,cy,rr,fort.hp,rules.FORT_HP)
    end
    if fort.hp<rules.FORT_HP then
      healthBar(cx-rr*.58,cy+rr*.91,rr*1.16,math.max(3.5,layout.cell*.06),
        fort.hp,rules.FORT_HP)
    end
  end
  for _,u in ipairs(state.units) do
    if u.hp>0 and (not moving or moving.id~=u.id) then unitToken(u) end
  end
  if selected and not overlay and not moving then
    local crossed=intended and intended.crossed or targets.crossed
    if crossed then
      love.graphics.setColor(.79,.96,1,intended and .66 or .40)
      love.graphics.setLineWidth(math.max(1.3,layout.radius*.075))
      for k in pairs(crossed) do
        local r,c=rules.fromkey(k)
        local cx,cy=center(r,c)
        love.graphics.polygon('line',faceHex(cx,cy,layout.radius*1.06))
      end
    end
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
    -- An attacker approaches onto the occupied hex, OVER the visible
    -- defender, before the battle overlay. No .76-distance stop/vanish.
    local sprite=unitArt[moving.event.actor][moving.event.attackerClass or moving.class]
    if sprite then
      local factor=layout.scale*1.04
      drawBadgeSprite(sprite,cx,cy,factor,true)
    else
      color(teamColors[moving.event.actor]);love.graphics.polygon('fill',faceHex(cx,cy,layout.radius*.81))
    end
    local unit=state.units[moving.id]
    criticalPulse(cx,cy,layout.radius,unit.hp,rules.classes[unit.class].hp)
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
    local a=rules.piece(state,selected)
    local rad=layout.radius
    local ax,ay=center(a.r,a.c)
    love.graphics.setLineWidth(math.max(2.4,rad*.12))
    color(palette.gold,.88)
    love.graphics.line(ax,ay,cx,cy)
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
    if a.class~="fortress" then emblem(a.class,cx-rad*.35,cy-rad*.35,rad*.21) end
  end
end
local function drawPortrait(sprite,x,y,w,h)
  local g=love.graphics
  local clipped=g.stencil and g.setStencilTest
  if clipped then
    g.stencil(function() g.rectangle('fill',x,y,w,h,9,9) end,'replace',1)
    g.setStencilTest('greater',0)
  end
  local iw,ih=sprite:getDimensions()
  local scale=math.max(w/iw,h/ih)
  g.setColor(1,1,1,1)
  if clipped then
    g.draw(sprite,x+(w-iw*scale)*.5,y+(h-ih*scale)*.5,0,scale,scale)
    g.setStencilTest()
  else
    g.draw(sprite,x,y,0,w/iw,h/ih)
  end
end

-- Compact inspection card. Name, Health and stats come
-- from the same live rules state used for combat and saved sessions.
local function drawCard()
  cardBox=nil
  if not state then return end
  local fort=inspected=='fort' and state.forts[inspectedFortOwner]
  local u=not fort and state.units[inspected or selected]
  if not fort and (not u or u.hp<=0) then return end
  local piece=fort or u
  local class=rules.classes[piece.class]
  local hint
  if fort then hint=fort.armed and 'Fires forward only' or 'Fires once attacked'
  elseif class.attackStraight then hint='Move and attack straight'
  elseif class.straight then hint='Move in a clear straight line'
  elseif class.forward then hint='Moves forward only'
  elseif piece.class=='wizard' then hint='Teleports over pieces' end
  local h=layout.cardH-(hint and 0 or layout.cardHintH)
  local x,w=4,layout.w-8
  local y=layout.cardY
  cardBox={x=x,y=y,w=w,h=h}
  local g=love.graphics
  -- Exactly the restrained navy/charcoal/gold palette used by the game.
  g.setColor(.055,.075,.105,.98)
  g.rectangle('fill',x,y,w,h,11,11)
  local portraitW=math.min(h*.83,w*.33)
  local divider=x+portraitW
  local left=divider+9
  local avail=math.max(5,x+w-left-10)
  local team=piece.owner
  local bust=fort and fortArt[team] or portraitArt[team][piece.class] or unitArt[team][piece.class]
  if bust then
    drawPortrait(bust,x+1,y+1,portraitW+6,h-2)
  elseif fort then
    fortressArt(x+portraitW*.5,y+h*.5,team,portraitW*.43)
  end
  -- The square edge of this panel covers the portrait's inner rounded corners.
  g.setColor(.055,.075,.105,1)
  g.rectangle('fill',divider,y+1,10,h-2)
  g.setColor(.77,.62,.39,1)
  g.setLineWidth(math.max(1.35,w*.0044))
  g.line(divider,y+1,divider,y+h-1)
  g.rectangle('line',x+1,y+1,w-2,h-2,11,11)
  if intended and intended.type=='attack' then
    local labelH=fontHeight(fonts.cardHint)+6
    local labelX,labelY=x+6,y+h-labelH-5
    local labelW=portraitW-11
    g.setColor(.22,.075,.09,.96)
    g.rectangle('fill',labelX,labelY,labelW,labelH,4,4)
    g.setColor(.99,.84,.59,1)
    g.setFont(fonts.cardHint)
    g.printf('Target',labelX,labelY+3,labelW,'center')
  end
  local teamName=team==1 and 'RED ' or 'BLUE '
  g.setFont(fonts.medium)
  local title=teamName..class.name:upper()
  local tt=team==1 and {.76,.31,.33} or {.43,.65,.87}
  g.setColor(tt[1],tt[2],tt[3],1)
  g.printf(title,left,y+6,avail,'left')
  g.setColor(.93,.91,.84,1)
  g.setFont(fonts.stat)
  local hpY=y+8+fontHeight(fonts.medium)
  g.printf(('HEALTH %d / %d'):format(piece.hp,class.hp),left,hpY,avail,'left')
  local bandH=layout.statBandH
  local bandY=hpY+fontHeight(fonts.stat)+4
  local bandX,bandW=left-3,avail+5
  g.setColor(.14,.19,.22,1)
  g.rectangle('fill',bandX,bandY,bandW,bandH,6,6)
  g.setColor(.62,.53,.34,.85)
  g.setLineWidth(1.2)
  g.rectangle('line',bandX,bandY,bandW,bandH,6,6)
  local rowH=fontHeight(fonts.cardStat)
  local firstY=bandY+layout.statPadding
  local column=avail*.5
  g.setColor(.62,.53,.34,.46)
  g.line(bandX+6,firstY+rowH+2,bandX+bandW-6,firstY+rowH+2)
  g.setFont(fonts.cardStat)
  g.setColor(.97,.81,.51,1)
  g.printf(('POWER %d'):format(class.power),left,firstY,column,'center')
  g.printf(('RANGE %d'):format(rules.attackRange(piece.class)),left+column,firstY,column,'center')
  local secondY=firstY+rowH+4
  g.setColor(.91,.89,.82,1)
  g.printf(('MOVE %s'):format(class.move or 'ANY'),left,secondY,column,'center')
  g.printf(('SHIELD %d'):format(class.shield),left+column,secondY,column,'center')
  if hint then
    g.setFont(fonts.cardHint)
    g.setColor(.71,.76,.78,1)
    g.printf(hint,left,bandY+bandH+3,avail,'left')
  end
end

local function panel(x,y,w,h)
  love.graphics.setColor(.025,.073,.12,.99)
  love.graphics.rectangle('fill',x,y,w,h,12,12)
  love.graphics.setColor(.35,.22,.105,1)
  love.graphics.setLineWidth(4)
  love.graphics.rectangle('line',x+1,y+1,w-2,h-2,12,12)
  love.graphics.setColor(1,.82,.43,1)
  love.graphics.setLineWidth(2.3)
  love.graphics.rectangle('line',x+3,y+3,w-6,h-6,11,11)
  love.graphics.setColor(1,.97,.73,.63)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle('line',x+6,y+6,w-12,h-12,9,9)
end
local COMBAT_READY_TIME = 1.15
local WINDUP, IMPACT, RESULT = 1.10, 2.00, 2.72
local BONUS_TIME = 1.9
local function playerControlsReward(actor)
  return mode=='local' or mode=='solo' and actor==1 or mode=='online' and actor==onlineSide
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
    love.graphics.setColor(.98,.34,.22,.18)
    love.graphics.circle('fill',cx,cy,rad*.92)
  end
  if sprite then
    drawBadgeSprite(sprite,cx,cy,rad/BADGE_R,true)
  elseif kind=='fortress' then
    fortressArt(cx,cy,team,rad)
  else
    drawBattleFigure(kind,cx,cy,rad)
  end
end
local function drawFighter(kind,team,cx,baseY,w,h,direction,strike,recoil)
  if kind=='fortress' then
    drawCombatant(kind,cx,baseY-h*.46,math.min(w,h)*.49,team,recoil>0)
    return
  end
  local sprite=fighterArt[team][kind]
  if not sprite then
    drawCombatant(kind,cx,baseY-h*.46,math.min(w,h)*.49,team,recoil>0)
    return
  end
  local g=love.graphics
  local iw,ih=sprite:getDimensions()
  local scale=math.min(w/iw,h/ih)
  local lunge=(kind=='archer' or kind=='wizard') and 0 or strike
  local shift=w*(lunge*.23-recoil*.055)
  g.setColor(1,1-recoil*.20,1-recoil*.21,1)
  -- Both teams' source art faces right. Mirror the right fighter around
  -- the waist so either team faces inward and the weapon swings with the body.
  g.draw(sprite,cx+direction*shift,baseY-h*lunge*.035,
    direction*(lunge*.12-recoil*.07),scale*direction,scale,iw*.5,ih)
end
local function drawBattleShot(kind,fromX,toX,y,size,phase)
  if phase<1.66 or phase>2.24 then return end
  local progress=math.min(1,(phase-1.66)/.34)
  local direction=toX>fromX and 1 or -1
  local dx=toX-fromX
  local g=love.graphics
  local loft=kind=='fortress' and size*3.1 or kind=='wizard' and size*.8 or 0
  local function flight(p)
    return fromX+dx*p,y-math.sin(p*math.pi)*loft
  end
  local x,cy=flight(progress)
  local fade=math.min(1,(2.24-phase)/.24)
  if kind=='fortress' then
    size=size*1.64
    for i=1,6 do
      local tx,ty=flight(math.max(0,progress-i*.065))
      g.setColor(.68,.56,.43,fade*.24*(1-i/7))
      g.circle('fill',tx,ty,size*(.33+i*.11))
    end
    local t=progress*6*direction
    local coords={}
    local radii={.93,1.05,.95,1.10,.94,1.04,.90}
    for i,rad in ipairs(radii) do
      local angle=t+i*math.pi*2/#radii
      coords[#coords+1]=x+math.cos(angle)*size*rad
      coords[#coords+1]=cy+math.sin(angle)*size*rad
    end
    g.setColor(.37,.31,.28,fade)
    g.polygon('fill',coords)
    g.setColor(.64,.58,.49,fade)
    g.polygon('fill',coords[1],coords[2],coords[3],coords[4],coords[5],coords[6],x-size*.30,cy-size*.17)
    g.setColor(.21,.17,.16,fade)
    g.polygon('fill',coords[7],coords[8],coords[9],coords[10],coords[11],coords[12],x+size*.17,cy+size*.11)
    g.setColor(.76,.68,.56,fade*.72);g.setLineWidth(1.4)
    g.line(x-size*.34,cy-size*.18,x+size*.14,cy+size*.13,x+size*.44,cy+size*.01)
  elseif kind=='wizard' then
    for i=7,1,-1 do
      local tx,ty=flight(math.max(0,progress-i*.047))
      g.setColor(1,.20+i*.028,.045,fade*(8-i)*.059)
      g.circle('fill',tx,ty,size*(.92+i*.07))
    end
    g.setColor(1,.35,.08,.32*fade);g.circle('fill',x,cy,size*1.58)
    g.setColor(1,.48,.07,fade);g.circle('fill',x,cy,size)
    g.setColor(1,.87,.45,fade);g.circle('fill',x+direction*size*.17,cy,size*.55)
    g.setColor(1,.99,.75,fade);g.circle('fill',x+direction*size*.24,cy-size*.13,size*.25)
  elseif progress<1 then
    g.setColor(.92,.79,.50,1)
    g.setLineWidth(math.max(1,size*.25))
    g.line(x-direction*size*3,cy,x,cy)
    g.setColor(.92,.92,.86,1)
    g.polygon('fill',x+direction*size*.55,cy,x-direction*size*.45,cy-size*.35,
      x-direction*size*.45,cy+size*.35)
  end
end
local function strikePulse(phase,rise,peak,fall)
  local t=math.max(0,math.min(1,(phase-rise)/(peak-rise),(fall-phase)/(fall-peak)))
  return t*t*(3-2*t)
end
local drawD12=require('d12')

local function luxeButton(label,x,y,w,h,red)
  local g=love.graphics
  g.setColor(.11,.08,.05,1)
  g.rectangle('fill',x-3,y-3,w+6,h+6,12,12)
  g.setColor(.99,.76,.33,1)
  g.rectangle('fill',x-1,y-1,w+2,h+2,11,11)
  if red=='neutral' then g.setColor(.25,.30,.35,1)
  elseif red then g.setColor(.66,.055,.11,1)
  else g.setColor(.02,.48,.12,1) end
  g.rectangle('fill',x+3,y+3,w-6,h-6,10,10)
  g.setColor(1,1,1,.18)
  g.line(x+11,y+8,x+w-11,y+8)
  local font=fonts.large
  local tw=font.getWidth and font:getWidth(label) or #label*19
  local fh=fontHeight(font)
  local factor=math.min(1,(w-18)/math.max(1,tw),(h-12)/fh)
  g.setColor(1,1,.94,1);g.setFont(font)
  if g.push and g.translate and g.scale then
    g.push();g.translate(x+w*.5,y+h*.51);g.scale(factor,factor)
    g.printf(label,-w*.5/factor,-fh*.51,w/factor,'center')
    g.pop()
  else text(label,x+5,y+h*.22,w-10,'center',fonts.small) end
end
local function battleBar(cx,y,w,amount,maxhp)
  local g=love.graphics
  local x=cx-w*.5
  g.setColor(.08,.13,.19,1);g.rectangle('fill',x,y,w,12,5,5)
  local ratio=math.max(0,math.min(1,amount/maxhp))
  if ratio>0 then
    if ratio<=.28 then g.setColor(.96,.24,.27,1)
    else g.setColor(.15,.91,.32,1) end
    g.rectangle('fill',x+2,y+2,math.max(0,(w-4)*ratio),8,3,3)
  end
  g.setColor(.78,.78,.73,.95);g.setLineWidth(1.4)
  g.rectangle('line',x,y,w,12,5,5)
end

-- The combat and bonus dice are already resolved by rules.apply.
-- Playback reveals the same results in every mode.
local function combatTitle(label,cx,y,w,tint,scale,font,alpha)
  local g=love.graphics
  font=font or fonts.large
  local measured=font.getWidth and font:getWidth(label) or #label*fontHeight(font)*.59
  local fit=math.min(scale or 1,(w-8)/math.max(1,measured))
  g.setFont(font)
  if g.push and g.translate and g.scale then
    g.push();g.translate(cx,y);g.scale(fit,fit)
    if g.shear then g.shear(-.12,0) end
    local width=w/fit
    g.setColor(.15,.035,.055,alpha or 1)
    g.printf(label,-width/2+1.5,3,width,'center')
    color(tint,alpha)
    g.printf(label,-width/2,0,width,'center')
    g.pop()
  else
    color(tint,alpha);g.printf(label,cx-w/2,y,w,'center')
  end
end

local function drawBattleOverlay()
  local g=love.graphics
  local w,h=layout.w,layout.h
  local event=overlay.event
  local elapsed=overlay.elapsed-COMBAT_READY_TIME
  local ready=elapsed<0
  local revealed=elapsed>=WINDUP
  local impact=event.landed and elapsed>=IMPACT
  local result=elapsed>=RESULT
  local bonus=overlay.bonusElapsed
  local bonusDone=bonus and bonus>=BONUS_TIME
  local playerAttacks=playerControlsReward(event.actor)
  local attacker,defender=rules.classes[event.attackerClass],rules.classes[event.defenderClass]
  local teamName=event.actor==1 and 'Red' or 'Blue'
  local otherName=event.actor==1 and 'Blue' or 'Red'
  local attackerHp=event.attackerHpStart+(bonusDone and event.heal.actual or 0)
  local defenderHp=impact and event.defenderHpEnd or event.defenderHpStart
  local gold={1,.83,.46}
  local amber={1,.64,.28}
  local red={1,.41,.36}
  local ice={.66,.88,1}
  g.setColor(.03,.029,.060,1);g.rectangle('fill',0,0,w,h)
  panel(4,4,w-8,h-8)
  local hitTime=impact and elapsed-IMPACT or 10
  if hitTime<.24 then
    g.setColor(1,.44,.16,.27*(1-hitTime/.24))
    g.rectangle('fill',7,7,w-14,h-14)
  end

  local label,detail,tint='ATTACK ROLL','Roll higher than Shield '..event.shield,gold
  if result and event.defeated then
    label=playerAttacks and 'VICTORY' or teamName:upper()..' WINS'
    detail=playerAttacks and 'Your Foe is Defeated' or otherName..' defender defeated.'
  elseif revealed and event.landed then
    label,tint=playerAttacks and 'YOU LANDED THE ATTACK' or 'ATTACK LANDED',amber
    detail=result and ('%d damage  •  Turn over'):format(event.damage)
      or ('Rolled %d against Shield %d'):format(event.roll,event.shield)
  elseif revealed then
    label,tint='ATTACK REPELLED',ice
    detail=('Rolled %d against Shield %d  •  Turn over'):format(event.roll,event.shield)
  end
  if ready then
    local entrance=smoothstep(overlay.elapsed/.25)
    local alpha=math.min(entrance,smoothstep(-elapsed/.14))
    local y=h*.057+9*(1-entrance)
    combatTitle('Ready for Combat',w*.5,y,w-28,gold,1.10+.22*(1-entrance),fonts.large,alpha)
  else
    combatTitle(label,w*.5,h*.057,w-28,tint,hitTime<.20 and 1.14 or 1)
  end
  text(detail,12,h*.162,w-24,'center',fonts.small)

  local cy=h*.48
  local fighterH=h*.224
  local x1,x2=w*.26,w*.74
  local strike=event.landed and strikePulse(elapsed,1.67,2,2.44) or 0
  local recoil=impact and strikePulse(elapsed,1.99,2.11,2.49) or 0
  text(teamName..' '..attacker.name,8,h*.215,w*.5-16,'center',fonts.stat)
  text(otherName..' '..defender.name,w*.5+8,h*.215,w*.5-16,'center',fonts.stat)
  drawFighter(event.defenderClass,3-event.actor,x2,cy,w*.44,fighterH,-1,0,recoil)
  drawFighter(event.attackerClass,event.actor,x1,cy,w*.44,fighterH,1,strike,0)
  if event.landed and attacker.projectile then
    local launchY=cy-fighterH*(event.attackerClass=='wizard' and .78 or .55)
    drawBattleShot(event.attackerClass,x1+w*.13,x2,launchY,math.max(5,h*.025),elapsed)
  end
  local barY=h*.50
  battleBar(x1,barY,w*.40,attackerHp,attacker.hp)
  battleBar(x2,barY,w*.40,defenderHp,defender.hp)
  text(('%d / %d HEALTH'):format(attackerHp,attacker.hp),8,barY+12,w*.5-16,'center',fonts.stat)
  text(('%d / %d HEALTH'):format(defenderHp,defender.hp),w*.5+8,barY+12,w*.5-16,'center',fonts.stat)
  if hitTime<.72 then
    local travel=hitTime/.72
    for i=1,10 do
      local angle=i*math.pi*.2
      local reach=(10+travel*34)*(1+i%2*.26)
      local px,py=x2+math.cos(angle)*reach,cy-fighterH*.45+math.sin(angle)*reach
      g.setColor(1,.62,.25,1-travel)
      g.setLineWidth(2)
      g.line(px,py,px+math.cos(angle)*9,py+math.sin(angle)*9)
    end
    combatTitle('-'..event.damage,x2,cy-fighterH*.53-travel*25,w*.44,red,1.35-travel*.35)
  end

  local bh=math.max(28,math.min(48,h*.08))
  local inset=math.max(18,math.min(32,h*.052))
  local buttonY=h-bh-inset
  local rewardH=fontHeight(fonts.large)
  local rewardY=math.min(h*.765,buttonY-rewardH-11)
  local size=math.min(w*.12,h*.095,70)
  local diceY=math.min(h*.675,rewardY-size-4)
  if result and event.fullHealth then
    text('Already at Full Health',12,h*.70,w-24,'center',fonts.medium)
  elseif bonus then
    drawD12(g,w*.5,diceY,event.heal.roll,not bonusDone and bonus or nil,event.actor,size,fonts.stat)
    if bonusDone then
      local reveal=smoothstep((bonus-BONUS_TIME)/.35)
      g.setColor(.04,.23,.14,.85)
      g.rectangle('fill',w*.14,rewardY-3,w*.72,rewardH+8,7,7)
      combatTitle(('+%d HEALTH'):format(event.heal.actual),w*.5,rewardY,w*.72,
        {.57,1,.68},1+.1*(1-reveal),fonts.large)
    else
      text('Rolling for Health',12,rewardY,w-24,'center',fonts.small)
    end
  elseif result and event.heal then
    drawD12(g,w*.5,diceY,12,nil,event.actor,size,fonts.stat,'D12')
    text('Health Reward',12,rewardY,w-24,'center',fonts.medium)
  elseif ready then
    drawD12(g,w*.5,diceY,12,nil,event.actor,size,fonts.stat,'D12')
  else
    drawD12(g,w*.5,diceY,event.roll,not revealed and math.max(0,elapsed) or nil,event.actor,size,fonts.stat)
  end
  overlay.button=nil
  local action
  if result then
    if event.heal and not bonus and playerAttacks then action='Roll for Reward'
    elseif not event.heal or bonusDone then action='CONTINUE' end
  end
  if action then
    local box={x=w*.16,y=buttonY,w=w*.68,h=bh}
    luxeButton(action,box.x,box.y,box.w,box.h,false)
    overlay.button=box
  end
end
local OPENING_BEAT, SIEGE_BEAT, FINALE_LENGTH = 1.65, 2.35, 6
local function playerName(side)
  if mode=='solo' then return side==1 and 'You' or 'CPU' end
  if mode=='online' and onlineSide then
    if side==onlineSide then return 'You' end
    return zompa.opponentName() or 'Opponent'
  end
  return teamNames[side]
end

local function openingButton(label,x,y,w,h,primary)
  local g=love.graphics
  g.setColor(0,0,0,.35)
  g.rectangle('fill',x,y+3,w,h,7,7)
  if primary then g.setColor(.32,.19,.075,1)
  else g.setColor(.105,.12,.15,1) end
  g.rectangle('fill',x,y,w,h,7,7)
  color(palette.gold,primary and .96 or .5)
  g.setLineWidth(1.15)
  g.rectangle('line',x,y,w,h,7,7)
  combatTitle(label,x+w*.5,y+(h-fontHeight(fonts.small))*.5,w,palette.text,1,fonts.small)
  return {x=x,y=y,w=w,h=h}
end

local function drawIntroduction()
  local g=love.graphics
  local w,h=layout.w,layout.h
  local header=layout.topReserve
  if logo then
    local iw,ih=logo:getDimensions()
    local scale=math.min(w*.90/iw,(header-30)/ih)
    g.setColor(1,1,1,1)
    g.draw(logo,(w-iw*scale)*.5,3,0,scale,scale)
  else
    combatTitle('FORTRESS SIEGE',w*.5,3,w-16,palette.gold)
    text('FINAL CONQUEST',8,6+fontHeight(fonts.large),w-16,'center',fonts.small)
  end
  local missionY=header-fontHeight(fonts.cardHint)-5
  text('Lead your army. Destroy the enemy fortress.',8,missionY,w-16,'center',fonts.cardHint)
  g.setColor(.76,.60,.36,.36);g.setLineWidth(1)
  g.line(w*.19,header-1,w*.81,header-1)
  for i=1,18 do
    local px=w*((i*.173+introTime*(.014+i%3*.006))%1)
    local py=layout.y+layout.boardH*((i*.293-introTime*.025)%1)
    color(palette.gold,.18+.13*math.sin(i+introTime))
    g.circle('fill',px,py,1+i%3*.45)
  end
  for side=1,2 do
    local fort=state.forts[side]
    local _,fy=center(fort.r,fort.c)
    local name=playerName(side)
    local label=name==teamNames[side] and name or name..' · '..teamNames[side]
    local badgeW=(w-layout.boardW*3/7)*.5-10
    local bx=side==1 and 6 or w-badgeW-6
    combatTitle(label,bx+badgeW*.5,fy-fontHeight(fonts.cardHint)*.5,badgeW+6,teamLabels[side],1,fonts.cardHint)
  end
  local y,bh=layout.actionY,layout.actionH
  intro.start=openingButton('Start Game',10,y,w*.53-13,bh,true)
  intro.guide=openingButton('How to Play',w*.53+4,y,w*.47-14,bh,false)
  if intro.help then
    g.setColor(.02,.021,.033,.75);g.rectangle('fill',0,0,w,h)
    local x,py,pw,ph=9,h*.075,w-18,h*.85
    g.setColor(.069,.08,.106,1);g.rectangle('fill',x,py,pw,ph,10,10)
    color(palette.gold,.75);g.setLineWidth(1.3)
    g.rectangle('line',x,py,pw,ph,10,10)
    combatTitle('How to Play',w*.5,py+ph*.055,pw-20,palette.gold,1,fonts.medium)
    local guide={
      {'Win','Destroy the enemy fortress.'},
      {'Move','Tap a friendly unit. Gold hexes show where it can move.'},
      {'Attack','Crossed swords mark targets. Confirm a target to roll against its Shield.'},
    }
    local gy=py+ph*.23
    for _,entry in ipairs(guide) do
      color(palette.gold)
      g.setFont(fonts.cardHint)
      g.printf(entry[1],x+13,gy,pw-26,'left')
      text(entry[2],x+13,gy+fontHeight(fonts.cardHint)+2,pw-26,'left',fonts.cardHint)
      gy=gy+ph*.185
    end
    local closeH=math.max(26,math.min(40,ph*.14))
    intro.close=openingButton('Back',w*.29,py+ph-closeH-8,w*.42,closeH,false)
  elseif introTime<.85 then
    g.setColor(0,0,0,1-smoothstep(introTime/.85))
    g.rectangle('fill',0,0,w,layout.viewportH)
  end
end

local function drawOpening(view)
  local g=love.graphics
  local w,h=layout.w,layout.h
  local opening=view.opening
  local title,detail='Roll for First Turn','Higher roll goes first'
  local rolls,rolling
  if view.elapsed then
    local count=#opening.rounds
    local index=math.min(count,math.floor(view.elapsed/OPENING_BEAT)+1)
    local phase=view.elapsed-(index-1)*OPENING_BEAT
    rolls=opening.rounds[index]
    rolling=phase<.85 and phase or nil
    if not rolling then
      if rolls[1]==rolls[2] then detail='Tie • Rolling again'
      else
        local name=playerName(opening.first)
        title=name=='You' and 'You Go First' or name..' Goes First'
        detail=nil
      end
    end
  end

  local px,pw=10,w-20
  local ph=math.min(222,h*.51,math.max(90,layout.actionY-layout.topReserve-7))
  local py=(layout.topReserve+layout.actionY-ph)*.5
  g.setColor(.045,.053,.074,.92);g.rectangle('fill',px,py,pw,ph,10,10)
  color(palette.gold,.77);g.setLineWidth(1.2)
  g.rectangle('line',px,py,pw,ph,10,10)
  combatTitle(title,w*.5,py+7,pw-18,palette.gold,1,fonts.medium)
  if detail then text(detail,px+7,py+10+fontHeight(fonts.medium),pw-14,'center',fonts.cardHint) end
  local size=math.min(w*.095,ph*.21,43)
  for side=1,2 do
    local cx=w*(side==1 and .26 or .74)
    drawD12(g,cx,py+ph*.56,rolls and rolls[side] or 12,rolling,side,size,fonts.cardHint,not rolls and 'D12' or nil)
    local name=playerName(side)
    local label=name==teamNames[side] and name or name..' · '..teamNames[side]
    combatTitle(label,cx,py+ph*.84,pw*.47,teamLabels[side],1,fonts.cardHint)
  end
  view.button=nil
  if not view.elapsed then
    local y,bh=layout.actionY,layout.actionH
    if mode~='online' or onlineSide==1 and onlineAllowed and not pending and lastOnlineCount==0 then
      view.button=openingButton('Roll for First Turn',10,y,w-20,bh,true)
      if turnSendFailed then text('Could not send. Tap again to retry.',10,y+bh+5,w-20,'center',fonts.cardHint) end
    else
      local waiting='Connecting…'
      if pending or lastOnlineCount==1 then waiting='Starting roll…'
      elseif onlineSide==2 then waiting='Waiting for '..playerName(1)..' to roll…' end
      g.setColor(.105,.12,.15,1);g.rectangle('fill',10,y,w-20,bh,7,7)
      combatTitle(waiting,w*.5,y+(bh-fontHeight(fonts.small))*.5,w-26,palette.text,1,fonts.small)
    end
  end
end

local function drawFinalSiege()
  local g=love.graphics
  local w,h=layout.w,layout.h
  local siege=overlay.siege
  local elapsed=overlay.elapsed
  local index=math.min(#siege.volleys,math.floor(elapsed/SIEGE_BEAT)+1)
  local phase=elapsed-(index-1)*SIEGE_BEAT
  local volley=siege.volleys[index]
  local prior=index>1 and siege.volleys[index-1].hp or siege.start
  local impact=volley.hit>0 and phase>=1.98
  local hp=impact and volley.hp or prior
  local x1,x2,y=w*.26,w*.74,h*.43
  local size=math.min(w*.13,h*.12,66)
  g.setColor(.025,.025,.055,1);g.rectangle('fill',0,0,w,layout.viewportH)
  panel(4,4,w-8,h-8)
  if impact and phase<2.10 then
    g.setColor(1,.44,.16,.24*(2.10-phase)/.12)
    g.rectangle('fill',8,8,w-16,h-16)
  end
  combatTitle('FINAL SIEGE',w*.5,h*.074,w-28,{1,.81,.42})
  local caption='VOLLEY '..index
  if phase>=1.25 then
    caption=volley.hit==0 and 'TIE • NO DAMAGE'
      or (volley.hit==1 and 'RED FIRES' or 'BLUE FIRES')
  end
  text(caption,8,h*.18,w-16,'center',fonts.medium)
  drawCombatant('fortress',x1,y,size,1,impact and volley.hit==2)
  drawCombatant('fortress',x2,y,size,2,impact and volley.hit==1)
  if volley.hit~=0 then
    local from=volley.hit==1 and x1 or x2
    local to=volley.hit==1 and x2 or x1
    drawBattleShot('fortress',from,to,y,size*.27,phase)
    if impact then
      local loser=3-volley.hit
      combatTitle('-'..(prior[loser]-hp[loser]),to,y-size*.95-(phase-1.98)*32,
        w*.39,{1,.47,.37},1.15)
    end
  end
  local barY=h*.57
  battleBar(x1,barY,w*.40,hp[1],rules.FORT_HP)
  battleBar(x2,barY,w*.40,hp[2],rules.FORT_HP)
  text(('RED  %d / %d'):format(hp[1],rules.FORT_HP),8,barY+12,w*.5-16,'center',fonts.stat)
  text(('BLUE  %d / %d'):format(hp[2],rules.FORT_HP),w*.5+8,barY+12,w*.5-16,'center',fonts.stat)
  local rolling=phase<1.08 and phase or nil
  drawD12(g,x1,h*.79,volley.a,rolling,1,size*.72,fonts.stat)
  drawD12(g,x2,h*.79,volley.b,rolling,2,size*.72,fonts.stat)
end

local function drawFinished()
  local g=love.graphics
  local w,h=layout.w,layout.h
  local owner=state.winner
  g.setColor(0,0,0,.82);g.rectangle('fill',0,0,w,layout.viewportH)
  if owner==0 then
    panel(w*.04,h*.30,w*.92,h*.40)
    combatTitle('STALEMATE',w*.5,h*.41,w*.85,{1,.83,.46})
    text('Neither kingdom has a legal action.',12,h*.54,w-24,'center',fonts.small)
    text('Use the Zompa Back button to leave.',12,h*.60,w-24,'center',fonts.small)
    return
  end
  local t=finishElapsed
  local burst=math.max(0,t-.75)
  local r=math.min(w*.29,h*.215,118)
  local cx,cy=w*.5,h*.40
  local winnerTint=owner==1 and {1,.40,.34} or {.42,.70,1}
  panel(4,4,w-8,h-8)
  for i=1,8 do
    local size=r*(.89+i*.23)
    g.setColor(winnerTint[1]*.27,winnerTint[2]*.27,winnerTint[3]*.27,.10)
    g.circle('fill',cx,cy,size)
  end
  if t<1.28 then
    -- The leading impact rays converge on the defeated Fortress.
    local force=math.min(1,t/.75)
    for i=1,14 do
      local angle=i*2.39996
      local dx,dy=math.cos(angle),math.sin(angle)
      local travel=r*(1.5+(1-force)*(2+i%4*.18))
      g.setColor(1,.53,.16,.56*force)
      g.setLineWidth(math.max(1,r*.014))
      g.line(cx+dx*travel,cy+dy*travel,cx+dx*(travel+r*.27),cy+dy*(travel+r*.27))
    end
    local shake=math.sin(t*81)*math.min(1,t*4)*r*.065
    local spread=burst*r*.68
    local fall=burst*burst*r*.75
    if g.setScissor and burst>0 then
      g.setScissor(math.max(6,cx-2*r),cy-r*1.55,2*r,3*r)
      fortressArt(cx+shake-spread,cy+fall,3-owner,r)
      g.setScissor(cx,cy-r*1.55,math.min(w-6-cx,2*r),3*r)
      fortressArt(cx+shake+spread,cy+fall,3-owner,r)
      g.setScissor()
    else fortressArt(cx+shake,cy,3-owner,r) end
  end
  if t>=.75 and burst<2.4 then
    local bloom=math.min(1,burst*5)
    for i=1,22 do
      local angle=i*2.39996
      local spread=r*(.19+(i%7)*.12)*bloom
      local x=cx+math.cos(angle)*spread
      local y=cy+math.sin(angle)*spread-r*burst*.24
      local plume=r*(.14+burst*.28)*(1+i%4*.09)
      g.setColor(.24+math.max(0,1-burst)*.26,.14,.125,.31*(1-burst/2.4))
      g.circle('fill',x,y,plume)
    end
    for i=1,36 do
      local angle=i*2.39996
      local speed=r*(.9+i%7*.28)
      local x=cx+math.cos(angle)*speed*burst
      local y=cy+math.sin(angle)*speed*burst+r*.85*burst*burst
      local size=math.max(2,r*(.026+i%5*.015))*(1-burst/2.7)
      local hot=i%3~=0
      g.setColor(hot and 1 or .56,hot and .42 or .40,hot and .12 or .28,1-burst/2.4)
      g.polygon('fill',x-size,y,x,y-size*1.4,x+size,y,x,y+size)
    end
    if burst<.59 then
      g.setColor(1,.69,.20,.92*(1-burst/.59))
      g.setLineWidth(math.max(2,r*.078*(1-burst/.60)))
      g.circle('line',cx,cy,r*(.26+burst*3.0))
    end
    if burst<.19 then
      g.setColor(1,.83,.52,.64*(1-burst/.19))
      g.rectangle('fill',6,6,w-12,h-12)
    end
  end
  if t>=1.5 then
    combatTitle('FORTRESS DESTROYED',cx,h*.147,w-28,{1,.79,.40})
  end
  if t>=2.15 then
    local party=t-2.15
    for firework=1,6 do
      local age=party-(firework-1)*.38
      if age>=0 and age<1.55 then
        local spread=age*math.min(w*.27,h*.21)
        local x0=w*(.18+(firework*7%9)*.081)
        local y0=h*(.27+(firework*3%7)*.055)
        for ray=1,16 do
          local angle=ray*math.pi/8+firework*.25
          local dx,dy=math.cos(angle),math.sin(angle)
          local x=x0+dx*spread
          local y=y0+dy*spread+h*.04*age*age
          local gold=firework%2==1
          g.setColor(gold and 1 or winnerTint[1],gold and .72 or winnerTint[2],
            gold and .25 or winnerTint[3],.86*(1-age/1.55))
          g.setLineWidth(2)
          g.line(x,y,x-dx*8,y-dy*8)
        end
      end
    end
    for i=1,30 do
      local x=w*((i*37%101)/101)
      local y=(i*73)%math.max(1,h)+party*(23+i%6*8)-h*.57
      local alpha=math.max(0,1-party/3.85)
      g.setColor(winnerTint[1],winnerTint[2],winnerTint[3],alpha*.83)
      g.rectangle('fill',x+math.sin(party*4+i)*11,y,3+i%3,5+i%3)
    end
    local mine=mode=='solo' and 1 or mode=='online' and onlineSide or nil
    local title=mine and (owner==mine and 'VICTORY!' or 'DEFEAT')
      or (owner==1 and 'RED KINGDOM WINS!' or 'BLUE KINGDOM WINS!')
    local glow=math.min(1,party*2.8)
    local crest=r*.53*glow
    if crest>0 then
      g.setColor(winnerTint[1],winnerTint[2],winnerTint[3],.37*glow)
      g.setLineWidth(2)
      g.circle('line',cx,h*.43,crest*1.25)
      fortressArt(cx,h*.43,owner,crest)
    end
    local scale=1+math.max(0,.24-party)*1.5
    combatTitle(title,cx,h*.64,w-28,winnerTint,scale,fonts.finale)
    text(owner==1 and 'The Red Kingdom claims the final victory.'
      or 'The Blue Kingdom claims the final victory.',10,h*.79,w-20,'center',fonts.small)
  end
  if t>=4.5 then text('Use the Zompa Back button to leave.',10,h*.91,w-20,'center',fonts.small) end
end
local ATTACK_NOTICE_TIME, TURN_NOTICE_TIME = 1.32, 1.06
local function showTurn(openingTurn)
  overlay=not state.winner and {type='turnNotice',side=state.turn,elapsed=0,openingTurn=openingTurn} or nil
  timers.cpu=0
end

local function drawBoardNotice()
  local g=love.graphics
  local w,h=layout.w,layout.h
  local event=overlay.event
  local side=event and event.actor or overlay.side
  local colors,names=teamLabels,teamNames
  local function name(owner,class)
    return names[owner]..' '..rules.classes[class].name
  end
  if event then
    local ax,ay=center(event.from.r,event.from.c)
    local dx,dy=center(event.to.r,event.to.c)
    local size=layout.radius
    if event.defeated then
      local sprite=unitArt[3-side][event.defenderClass]
      if event.defenderClass=='fortress' then fortressArt(dx,dy,3-side,size)
      elseif sprite then drawBadgeSprite(sprite,dx,dy,layout.scale,true) end
    end
    local strength=.75+.18*math.sin(overlay.elapsed*11)
    color(colors[side],strength);g.setLineWidth(math.max(2,size*.10))
    g.circle('line',ax,ay,size*.98)
    g.line(ax,ay,dx,dy)
    color(colors[3-side],strength);g.circle('line',dx,dy,size*.98)
    local arrowX,arrowY=ax+(dx-ax)*.65,ay+(dy-ay)*.65
    color(colors[side],1);g.circle('fill',arrowX,arrowY,math.max(2,size*.15))
    if overlay.elapsed<.20 then return end
  end

  local ww=math.min(w*.84,460)
  local hh=math.max(event and 85 or 65,math.min(event and 124 or 92,h*.24))
  local alpha=event and 1 or math.min(smoothstep(overlay.elapsed/.20),smoothstep((TURN_NOTICE_TIME-overlay.elapsed)/.23))
  local x,y=(w-ww)*.5,h*.51-hh*.5+(event and 0 or 9*(1-alpha))
  if event then
    g.setColor(.02,.04,.07,.29);g.rectangle('fill',0,0,w,h)
  end
  g.setColor(.025,.04,.075,(event and .89 or .69)*alpha);g.rectangle('fill',x,y,ww,hh,12,12)
  color(colors[side],.87*alpha);g.setLineWidth(1.7)
  g.rectangle('line',x,y,ww,hh,12,12)
  if event then
    combatTitle(name(side,event.attackerClass)..' Attacks',w*.5,y+hh*.14,ww-18,colors[side],1,fonts.medium)
    local cx,ay=w*.5,y+hh*.47
    color(colors[side],.88);g.setLineWidth(1.7)
    g.line(cx-8,ay,cx+8,ay)
    g.line(cx+3,ay-4,cx+8,ay,cx+3,ay+4)
    combatTitle(name(3-side,event.defenderClass),w*.5,y+hh*.59,ww-18,colors[3-side],1,fonts.medium)
  else
    local name=overlay.openingTurn and playerName(side) or names[side]
    local label=name=='You' and 'Your Turn' or name.."'s Turn"
    local font=fonts.large
    local width=font.getWidth and font:getWidth(label) or #label*fontHeight(font)*.59
    local fit=math.min(1,(ww-26)/math.max(1,width))
    combatTitle(label,w*.5,y+(hh-fontHeight(font)*fit)*.5,ww-18,colors[side],fit,font,alpha)
  end
end
local function showEvent(event)
  selected,inspected,targets,intended=nil,nil,{},nil
  if event and event.type=='attack' then
    overlay={type='attackNotice',event=event,elapsed=0}
  elseif event and event.siege then
    overlay={type='siege',siege=event.siege,elapsed=0}
  elseif event then
    showTurn()
  end
end
-- Animate moves along their legal path. Attacks animate in the battle view.
-- The deterministic game state is already committed, so animation is visual only.
local function beginEvent(event,previous)
  selected,inspected,targets,intended=nil,nil,{},nil
  if event and event.type=='move' and previous then
    local route=rules.route(previous,event.id,event.to.r,event.to.c)
    if route and #route>=2 then
      local unit=previous.units[event.id]
      moving={id=event.id,route=route,event=event,class=unit and unit.class,
        elapsed=0,
        duration=.92+math.max(0,#route-2)*.25}
      queuedEvent=event
      timers.cpu=0
      overlay=nil
      return
    end
  end
  showEvent(event)
end
local REWARD_PENDING, REWARD_SHOWN = 'REWARD:', 'REWARD_SHOWN:'
local function sessionSave(rewardStage)
  if mode=='online' then return end
  local ok,err
  if state.winner~=nil and not rewardStage then ok,err=zompa.clearSession()
  else
    local data=rules.serialize(state)
    if rewardStage then data=rewardStage..data end
    ok,err=zompa.saveSession(data)
  end
  if not ok then print('Session save failed: '..tostring(err)) end
end
local function localAction(action)
  local previous=rules.copy(state)
  local ok,event=rules.apply(state,action)
  if not ok then notice=event;return false end
  sessionSave(event.heal and playerControlsReward(event.actor) and REWARD_PENDING)
  beginEvent(event,previous)
  return true
end
-- The host alternates starting with the inviter. Two setup tokens establish
-- a shared seed, then Red yields the first host slot if Blue won the roll.
local function unwrapOnline(raw)
  local nonces={}
  for i=1,2 do
    local value=raw[i]:match('^I(%d+)$')
    local number=value and #value<=10 and tonumber(value)
    if not number or number<1 or number>2147483646 then return nil,'Invalid opening roll.' end
    nonces[i]=number
  end
  local seed=(nonces[1]*181+nonces[2]*9973)%2147483647
  if seed==0 then seed=1 end
  local opening=rules.initiative(seed)
  local start=3
  if opening.first==2 then
    if raw[3] and raw[3]~='Y' then return nil,'Invalid opening handoff.' end
    start=4
  end
  local tokens={}
  for i=start,#raw do
    if raw[i]=='Y' then return nil,'Unexpected opening handoff.' end
    tokens[#tokens+1]=raw[i]
  end
  return tokens,seed,opening
end

local function sendHostTurn(token,outcome)
  local sent,err=zompa.submitTurn(token,outcome)
  turnSendFailed=not sent
  if sent then pending=true;notice='Sending turn…' else notice=tostring(err) end
  return sent
end

local function readOnline()
  local history,side,allowed=zompa.readTurns()
  if not history then onlineAllowed=false;return end
  onlineSide,onlineAllowed=side,allowed
  local oldCount=lastOnlineCount
  if #history~=oldCount then pending,turnSendFailed=false,false end
  if #history<2 then
    blocked=nil
    onlineReady=false
    lastOnlineCount=#history
    -- The inviter starts setup by tapping Roll. The invitee contributes
    -- their nonce automatically after receiving that first host turn.
    if #history==1 and side==2 and allowed and not pending then
      sendHostTurn('I'..tostring(love.math.random(1,2147483646)))
    end
    return
  end
  if #history==oldCount and not blocked then
    if state.first==2 and #history==2 and allowed and side==1 and not pending then
      sendHostTurn('Y')
    end
    return
  end
  local tokens,seed,opening=unwrapOnline(history)
  if not tokens then blocked=seed;onlineAllowed=false;return end
  local synced,err=rules.replay(seed,tokens,opening.first)
  if not synced then blocked=err;onlineAllowed=false;return end
  blocked=nil
  onlineReady=true
  local previous=state
  state=synced
  lastOnlineCount=#history
  if #tokens==0 and oldCount<2 then
    if intro and not intro.help then intro=nil end
    overlay={type='opening',opening=opening,elapsed=0}
  elseif synced.last and (#history==oldCount+1 or synced.winner) then
    intro=nil
    beginEvent(synced.last,previous)
  else
    if #tokens>0 then intro=nil end
    showEvent(nil)
  end
end

local function sendOnline(action)
  if pending or not onlineReady or not onlineAllowed or state.turn~=onlineSide then return end
  local tentative=rules.copy(state)
  local ok,result=rules.apply(tentative,action)
  if not ok then notice=result;return false end
  return sendHostTurn(rules.encode(action),tentative.winner)
end
local function mayAct()
  return state and state.winner==nil and not overlay and not moving and not blocked and
    (mode=='online' and onlineReady and onlineAllowed and state.turn==onlineSide and not pending or
    mode=='solo' and state.turn==1 or mode=='local')
end
local function drawActionBar()
  actionBox,cancelBox=nil,nil
  local x,y,w,h=6,layout.actionY,layout.w-12,layout.actionH
  if intended and selected and mayAct() then
    local isAttack=intended.type=='attack'
    local confirmW=w*.73
    local label='MOVE HERE'
    if isAttack then
      local distance=rules.distance(rules.piece(state,selected),intended)
      label=('ATTACK NOW  ·  %d %s'):format(distance,distance==1 and 'HEX' or 'HEXES')
    end
    luxeButton(label,x,y,confirmW,h,isAttack)
    luxeButton('CANCEL',x+confirmW+5,y,w-confirmW-5,h,'neutral')
    actionBox={x=x,y=y,w=confirmW,h=h}
    cancelBox={x=x+confirmW+5,y=y,w=w-confirmW-5,h=h}
    if turnSendFailed then
      text('Could not send. Tap again to retry.',x,y+h+5,w,'center',fonts.small)
    end
  else
    local label
    if mode=='online' and not onlineReady then label='WAITING FOR OPENING ROLL'
    elseif pending then label='SENDING TURN…'
    elseif turnSendFailed then label='COULD NOT SEND TURN'
    elseif overlay and overlay.type=='attackNotice' then
      label=overlay.event.actor==1 and 'RED ATTACKS' or 'BLUE ATTACKS'
    elseif moving then label=moving.event.actor==2 and 'BLUE KINGDOM MOVES' or 'RED KINGDOM MOVES'
    elseif mode=='solo' and state.turn==2 then label='BLUE KINGDOM IS THINKING…'
    elseif selected then label='TAP A HIGHLIGHTED HEX'
    elseif saveVersionChanged and state.moves==0 then label='RULES UPDATED  •  START A NEW MATCH'
    elseif state.moves==0 and mayAct() then label='TAP ONE OF YOUR UNITS'
    else
      local nextSide=state.turn==1 and 'RED' or 'BLUE'
      local waiting=mode=='online' and state.turn~=onlineSide
      label=nextSide..' TURN  •  '..(waiting and 'WAITING' or 'CHOOSE A PIECE')
    end
    love.graphics.setColor(.11,.15,.17,.96)
    love.graphics.rectangle('fill',x,y,w,h,9,9)
    color(palette.text);love.graphics.setFont(fonts.small)
    love.graphics.printf(label,x+4,y+(h-fontHeight(fonts.small))*.5,w-8,'center')
  end
end
local function actorAction(action)
  if not mayAct() then return end
  if mode=='online' then return sendOnline(action) end
  return localAction(action)
end
local function computerAction()
  if state.winner~=nil or state.turn~=2 or overlay or moving then return end
  local action=chooseCpuAction(state,love.math.random)
  if action then localAction(action) end
end
local function inside(box,x,y)
  return box and x>=box.x and y>=box.y and x<=box.x+box.w and y<=box.y+box.h
end
local function onTap(x,y)
  if not state then return end
  if moving then return end
  if intro then
    if intro.help then
      if inside(intro.close,x,y) then
        intro.help=false
        if overlay and overlay.type=='opening' and overlay.elapsed then intro=nil end
      end
    elseif inside(intro.guide,x,y) then intro.help=true
    elseif inside(intro.start,x,y) then
      intro=nil
      if horn then horn:play() end
    end
    return
  end
  if mode=='online' and not onlineReady and not overlay then
    if onlineSide==1 and onlineAllowed and not pending and lastOnlineCount==0
      and inside(onlineOpeningPrompt.button,x,y) then
      sendHostTurn('I'..tostring(love.math.random(1,2147483646)))
    end
    return
  end
  if overlay then
    if not inside(overlay.button,x,y) then return end
    if overlay.type=='opening' then
      overlay.elapsed=0
      overlay.button=nil
    elseif overlay.event.heal and not overlay.bonusElapsed then
      overlay.bonusElapsed=0
      overlay.button=nil
    else
      if overlay.event.heal and playerControlsReward(overlay.event.actor) then sessionSave() end
      if overlay.event.siege then overlay={type='siege',siege=overlay.event.siege,elapsed=0}
      else showTurn() end
    end
    return
  end
  if state.winner~=nil then return end
  if inside(cardBox,x,y) then return end
  if selected and intended and inside(cancelBox,x,y) then
    intended=nil
    turnSendFailed=false
    local piece=rules.piece(state,selected)
    inspected=piece.class=='fortress' and 'fort' or selected
    if piece.class=='fortress' then inspectedFortOwner=piece.owner end
    notice='Destination cleared. Pick another hex.'
    return
  end
  if inside(actionBox,x,y) and intended and selected and mayAct() then
    local action={type=intended.type,id=selected,r=intended.r,c=intended.c}
    -- The rules validate again when the action is committed.
    notice=''
    if actorAction(action) then intended=nil end
    return
  end
  local cell=xyToCell(x,y)
  if not cell then return end
  turnSendFailed=false
  local t=rules.occupied(state,cell.r,cell.c)
  if t and t.owner==state.turn and mayAct() and (t.kind=='unit' or t.ref.armed) then
    -- Choosing a different friendly soldier cancels the pending action.
    selected,intended=t.ref.id,nil
    inspected=t.kind=='fort' and 'fort' or selected
    if t.kind=='fort' then inspectedFortOwner=t.owner end
    targets={moves=rules.moves(state,selected),attacks=rules.attacks(state,selected),crossed={}}
    if t.ref.class=='wizard' then
      for key in pairs(targets.moves) do
        local r,c=rules.fromkey(key)
        for crossed in pairs(rules.jumpOver(state,selected,r,c)) do targets.crossed[crossed]=true end
      end
    end
    notice='Gold: move. Crossed swords: attack.'
    return
  end
  if selected and mayAct() then
    local k=rules.key(cell.r,cell.c)
    local kind=(targets.attacks or {})[k] and 'attack' or (targets.moves or {})[k] and 'move' or nil
    if kind then
      intended={type=kind,r=cell.r,c=cell.c,crossed=kind=='move' and rules.jumpOver(state,selected,cell.r,cell.c) or {}}
      inspected=t and t.kind=='unit' and t.ref.id or t and t.kind=='fort' and 'fort' or selected
      if t and t.kind=='fort' then inspectedFortOwner=t.owner end
      if kind=='attack' then
        local name=t.kind=='fort' and 'Fortress' or rules.classes[t.ref.class].name
        notice='TARGET '..name:upper()..'  •  Confirm ATTACK'
      else
        notice='Confirm move to the marked hex.'
      end
      return
    end
  end
  intended=nil
  if t and t.kind=='unit' then
    -- Enemy inspection never moves or attacks and does not deselect the friendly unit.
    inspected=t.ref.id
    if t.owner~=state.turn then
      notice=selected and 'Enemy is out of attack range.' or 'Enemy inspected. Select your soldier first.'
    end
  elseif t and t.kind=='fort' then
    inspected='fort'
    inspectedFortOwner=t.owner
    notice=t.owner==state.turn and 'Protect your Fortress.' or 'Enemy Fortress inspected.'
  elseif selected then
    local piece=rules.piece(state,selected)
    inspected=piece.class=='fortress' and 'fort' or selected
    if piece.class=='fortress' then inspectedFortOwner=piece.owner end
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
  onTap(x-layout.stageX,y)
end
local function fitHostedWindow()
  if not love.system or love.system.getOS()~='Web' then return end
  local window=love.window
  local screenW,screenH=window.getDesktopDimensions()
  if screenW<=0 or screenH<=0 then return end
  -- LÖVE Web reports the display dimensions. Zompa hosts this canvas below
  -- its toolbar and above Android's navigation area.
  local hostChrome=math.max(112,math.ceil(screenH*.15))
  local availableH=math.max(200,screenH-hostChrome)
  local w=math.min(screenW,600,math.floor(availableH*.76))
  local h=math.min(availableH,math.floor(w*1.88))
  window.setMode(w,h,{resizable=true,minwidth=120,minheight=160})
end
function love.load()
  fitHostedWindow()
  if love.graphics.newImage then
    -- The hosted WebGL runtime cannot mipmap these non-power-of-two sprites.
    local mipmaps=not love.system or love.system.getOS()~='Web'
    local okLogo,image=pcall(love.graphics.newImage,'art/fortress-siege-logo.png')
    if okLogo then logo=image end
    local ok,img=pcall(love.graphics.newImage,'art/board.png')
    if ok and img then artBoard=img; if img.setFilter then img:setFilter('linear','linear') end end
    for owner=1,2 do
      for name,_ in pairs(rules.classes) do
        if name~='fortress' then
          local ok2,sp=pcall(love.graphics.newImage,('art/%s-%d.png'):format(name,owner))
          if ok2 and sp then unitArt[owner][name]=sp
            if sp.setFilter then sp:setFilter('linear','linear') end end
          local ok3,bust=pcall(love.graphics.newImage,('portraits/%s-%d.png'):format(name,owner))
          if ok3 and bust then
            portraitArt[owner][name]=bust
            if bust.setFilter then bust:setFilter('linear','linear') end
          end
          local fighterPath=('fighters/%s-%d.png'):format(name,owner)
          local ok5,fighter=pcall(love.graphics.newImage,fighterPath,{mipmaps=mipmaps})
          if not ok5 then ok5,fighter=pcall(love.graphics.newImage,fighterPath) end
          if ok5 and fighter then
            fighterArt[owner][name]=fighter
            if fighter.setFilter then fighter:setFilter('linear','linear') end
            -- Smaller battle views need filtered levels as the sprites rotate.
            if mipmaps and fighter.setMipmapFilter and fighter:getMipmapCount()>1 then
              fighter:setMipmapFilter('linear')
            end
          end
        end
        end
      local ok4,fort=pcall(love.graphics.newImage,('art/fortress-%d.png'):format(owner))
      if ok4 and fort then
        fortArt[owner]=fort
        if fort.setFilter then fort:setFilter('linear','linear') end
      end
    end
  end
  if not horn and love.audio and mixer.register then
    local loaded,source=pcall(love.audio.newSource,'audio/siege-horn.wav','static')
    if loaded then horn=mixer:register(source,'effects') end
  end
  mode=zompa.mode()
  local seed=mode=='online' and 47061 or love.math.random(1,2147483600)
  local opening=mode~='online' and rules.initiative(seed) or nil
  state=rules.new(seed,opening and opening.first)
  saveVersionChanged=false
  local resumeReward,rewardShown=false,false
  if mode~='online' then
    local saved=zompa.loadSession()
    if saved then
      local revealed=saved:match('^'..REWARD_SHOWN..'(.*)$')
      local rewardSave=revealed or saved:match('^'..REWARD_PENDING..'(.*)$')
      local restored,err=rules.restore(rewardSave or saved)
      if restored then
        state=restored
        resumeReward=rewardSave and state.last and state.last.heal
        rewardShown=revealed~=nil
        opening=nil
      else
        saveVersionChanged=err=='Unrecognized save version.'
        print('Ignoring invalid saved session: '..tostring(err))
      end
    end
  end
  selected,inspected,targets,pending,overlay,intended,inspectedFortOwner=nil,nil,{},false,nil,nil,nil
  moving,queuedEvent,cardBox=nil,nil,nil
  actionBox,cancelBox=nil,nil
  notice,blocked,turnSendFailed='',nil,false
  intro=(opening or mode=='online') and {} or nil
  introTime=0
  if opening then
    overlay={type='opening',opening=opening}
  elseif resumeReward then
    overlay={type='battle',event=state.last,elapsed=COMBAT_READY_TIME+RESULT,
      bonusElapsed=rewardShown and BONUS_TIME or nil}
  elseif state.last and state.last.siege then
    overlay={type='siege',siege=state.last.siege,elapsed=0}
  end
  finishElapsed=0
  timers.cpu,timers.poll=0,0
  onlineSide,onlineAllowed,onlineReady,lastOnlineCount=nil,false,false,-1
  onlineOpeningPrompt={}
  reflow(love.graphics.getDimensions())
  tileCanvas=nil
end
function love.resize(w,h)
  tileCanvas=nil
  reflow(w,h)
end
function love.update(dt)
  mixer:update(dt)
  if mode=='online' then
    timers.poll=timers.poll+dt
    -- Let the current event finish before a newer turn can replace its animation or dialog.
    if timers.poll>=0.34 and not moving and not overlay then
      timers.poll=0
      readOnline()
    end
  end
  if intro and not blocked then
    introTime=introTime+dt
    return
  end
  local finishedMove=false
  if moving then
    moving.elapsed=moving.elapsed+dt
    if moving.elapsed>=moving.duration then
      moving=nil
      local ev=queuedEvent;queuedEvent=nil
      if ev then showEvent(ev);finishedMove=true end
    end
  end
  if overlay and not finishedMove then
    if overlay.elapsed then overlay.elapsed=overlay.elapsed+dt end
    if overlay.type=='opening' then
      if overlay.elapsed and overlay.elapsed>=#overlay.opening.rounds*OPENING_BEAT+.50 then
        showTurn(true)
        return
      end
    elseif overlay.type=='siege' then
      if overlay.elapsed>=#overlay.siege.volleys*SIEGE_BEAT then overlay=nil end
    elseif overlay.type=='attackNotice' then
      if overlay.elapsed>=ATTACK_NOTICE_TIME then overlay.type,overlay.elapsed='battle',0 end
    elseif overlay.type=='turnNotice' then
      if overlay.elapsed>=TURN_NOTICE_TIME then overlay=nil end
    elseif overlay.bonusElapsed then
      local before=overlay.bonusElapsed
      overlay.bonusElapsed=before+dt
      if before<BONUS_TIME and overlay.bonusElapsed>=BONUS_TIME
        and mode~='online' and playerControlsReward(overlay.event.actor) then
        sessionSave(REWARD_SHOWN)
      end
    elseif overlay.event.heal and not playerControlsReward(overlay.event.actor)
      and overlay.elapsed>=COMBAT_READY_TIME+RESULT+1.25 then
      overlay.bonusElapsed=0
    end
  elseif state and state.winner~=nil then
    finishElapsed=math.min(FINALE_LENGTH,finishElapsed+dt)
  end
  if state and state.winner==nil and not overlay and not moving and not pending then
    if mode=='solo' and state.turn==2 then
      timers.cpu=timers.cpu+dt
      if timers.cpu>1.1 then timers.cpu=0;computerAction() end
    elseif mode=='online' and onlineAllowed and onlineReady and state.turn==onlineSide
      and rules.mustPass(state) then
      -- Zompa turns-v1 alternates strictly: a side with no legal action submits a pass.
      sendOnline({type='pass'})
    elseif mode=='local' and rules.mustPass(state) then
      localAction({type='pass'})
    elseif mode=='solo' and state.turn==1 and rules.mustPass(state) then
      localAction({type='pass'})
    end
  end
end
function love.draw()
  if not state then return end
  -- A quiet stone-toned stage avoids a separate black rectangle around the board.
  -- Zompa's dark-purple play-area tone is the only backdrop color.
  love.graphics.setColor(.085,.066,.115,1)
  love.graphics.rectangle('fill',0,0,layout.viewportW,layout.viewportH)
  if layout.stageX>0 then love.graphics.push();love.graphics.translate(layout.stageX,0) end
  drawBoard()
  local waitingForRoll=mode=='online' and not onlineReady and not blocked
  if not intro and not waitingForRoll and not (overlay and overlay.type=='opening') then
    drawActionBar()
    drawCard()
  end
  if blocked then
    text('Online sync error: '..blocked,8,layout.h*.43,layout.w-16,'center',fonts.medium)
  end
  if intro and not blocked then drawIntroduction()
  elseif overlay and overlay.type=='battle' then drawBattleOverlay()
  elseif overlay and overlay.type=='opening' then drawOpening(overlay)
  elseif waitingForRoll then drawOpening(onlineOpeningPrompt)
  elseif overlay and overlay.type=='siege' then drawFinalSiege()
  elseif overlay then drawBoardNotice()
  elseif state.winner~=nil then drawFinished() end
  if layout.stageX>0 then love.graphics.pop() end
end
function love.mousepressed(x,y,button) if button==1 then touch(x,y) end end
function love.touchpressed(_,x,y) touch(x,y) end
function love.keypressed(key)
  if key=='escape' then
    if intro and intro.help then
      intro.help=false
      if overlay and overlay.type=='opening' and overlay.elapsed then intro=nil end
      return
    end
    selected,inspected,targets,intended=nil,nil,{},nil
    actionBox,cancelBox,cardBox=nil,nil,nil
    turnSendFailed=false
  end
end
