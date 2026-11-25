-- Fortress: The Badlands — Zompa SDK v4 / LÖVE 11.5 graybox prototype.
-- This game's deterministic rules are shared by solo, pass-and-play, and turns-v1 online.
local rules = require('rules')
local zompa = require('zompa')
local mode = 'solo'
local state, onlineSide, onlineAllowed, onlineReady, lastOnlineCount
local selected, inspected, targets, pending, overlay, intended, actionBox, cancelBox, inspectedFortOwner
local layout, timers, notice, blocked = {}, {cpu=0,poll=0,dialog=0}, '', nil
local saveVersionChanged
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
local function reflow(w,viewportH)
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
  local statPadding=5
  local moveBandH=math.max(statH,fontHeight(fonts.small))+statPadding*2
  local cardH=6+titleH+2+statH+4+moveBandH+7
  local topReserve=cardH+10
  local actionH=math.floor(math.max(36,48*uiScale)+.5)
  local bottomReserve=actionH+12
  local boundW=7*SQRT3
  local boundH=17
  local R=math.max(4,math.min((w-8)/boundW,
    (h-topReserve-bottomReserve-7)/boundH))
  local boardW,boardH=boundW*R,boundH*R
  local top=topReserve+math.max(0,(h-topReserve-bottomReserve-boardH)*.5)
  layout={w=w,h=h,viewportH=viewportH,hexR=R,hexStepX=SQRT3*R,hexStepY=1.5*R,
    -- Keep the established sprite fit and all existing UI sizing hooks.
    scale=(R*.93)/60,cell=SQRT3*R,radius=R*.84,
    tileW=SQRT3*R,rowH=R*1.5,
    x=(w-boardW)*.5,y=top,boardW=boardW,boardH=boardH,
    cardY=3,cardH=cardH,topReserve=topReserve,
    moveBandH=moveBandH,statPadding=statPadding,
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
  -- The single sprite rim above provides selection clarity; never draw
  -- a second hex ring offset from the token artwork.
  -- HP is in the large inspection card; a small bar appears only for injuries.
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
  if not tileCanvas and love.graphics.newCanvas then
    local g=love.graphics
    local ok,canvas=pcall(g.newCanvas,layout.w,layout.h)
    if ok and canvas then
      -- A canvas must explicitly request a stencil buffer in LÖVE 11.5.
      -- If unavailable (older browser GPU), safely render uncached below.
      local setOk=pcall(g.setCanvas,{canvas,stencil=true})
      if setOk then
        g.clear(0,0,0,0)
        local paintOk=pcall(paintField)
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
-- One real, separately loaded portrait per class and color.
-- Clip to a single clean hex to match the piece art and save vertical room.
local function drawPortrait(sprite,cx,cy,rad)
  local g=love.graphics
  local haveStencil=g.stencil and g.setStencilTest
  if haveStencil then
    g.stencil(function() g.polygon('fill',faceHex(cx,cy,rad*.98)) end,'replace',1)
    g.setStencilTest('greater',0)
  end
  g.setColor(1,1,1,1)
  local iw,ih=sprite:getDimensions()
  local sz=rad*2.02
  g.draw(sprite,cx-rad*1.01,cy-rad*1.01,0,sz/iw,sz/ih)
  if haveStencil then g.setStencilTest() end
  g.setColor(.78,.62,.38,1)
  g.setLineWidth(math.max(1.1,rad*.057))
  g.polygon('line',faceHex(cx,cy,rad))
end

-- Compact inspection card. Name, Health and stats come
-- from the same live rules state used for combat and saved sessions.
local function drawCard()
  cardBox=nil
  if not state then return end
  local fort=inspected=='fort' and state.forts[inspectedFortOwner]
  local u=not fort and state.units[inspected or selected]
  if not fort and (not u or u.hp<=0) then return end
  local h=layout.cardH
  local x,w=4,layout.w-8
  local y=layout.cardY
  cardBox={x=x,y=y,w=w,h=h}
  local g=love.graphics
  -- Exactly the restrained navy/charcoal/gold palette used by the game.
  g.setColor(.055,.075,.105,.98)
  g.rectangle('fill',x,y,w,h,11,11)
  g.setColor(.77,.62,.39,1)
  g.setLineWidth(math.max(1.35,w*.0044))
  g.rectangle('line',x+1,y+1,w-2,h-2,11,11)
  local portraitR=h*.345
  local ix,iy=x+11+portraitR,y+h*.49
  local left=ix+portraitR+16
  local avail=math.max(5,x+w-left-10)
  -- Separate the portrait from the text without adding ornate visual noise.
  g.setColor(.67,.51,.29,.8)
  g.setLineWidth(math.max(1.3,h*.021))
  g.line(left-9,y+9,left-9,y+h-10)
  local team,kind,hp,hpMax,move,power,shield
  if fort then
    team,kind=fort.owner,'FORTRESS'
    hp,hpMax,move,power,shield=fort.hp,rules.FORT_HP,'0',rules.classes.fortress.power,rules.classes.fortress.shield
    fortressArt(ix,iy,team,portraitR)
  else
    team=u.owner
    local cl=rules.classes[u.class]
    kind=cl.name:upper()
    hp,hpMax,move,power,shield=u.hp,cl.hp,cl.move or 'LINE',cl.power,cl.shield
    local bust=portraitArt[team] and portraitArt[team][u.class]
    if bust then drawPortrait(bust,ix,iy,portraitR)
    else
      local token=unitArt[team] and unitArt[team][u.class]
      if token then drawBadgeSprite(token,ix,iy,portraitR/BADGE_R,true) end
    end
  end
  local teamName=team==1 and 'RED ' or 'BLUE '
  g.setFont(fonts.medium)
  local title=teamName..kind
  local tt=team==1 and {.76,.31,.33} or {.43,.65,.87}
  g.setColor(tt[1],tt[2],tt[3],1)
  g.printf(title,left,y+6,avail,'left')
  g.setColor(.93,.91,.84,1)
  g.setFont(fonts.stat)
  local hpY=y+8+fontHeight(fonts.medium)
  g.printf(('HEALTH %d / %d'):format(hp,hpMax),left,hpY,avail,'left')
  local bandH=layout.moveBandH
  local bandY=y+h-bandH-7
  g.setColor(.14,.19,.22,1)
  g.rectangle('fill',left-3,bandY,avail+5,bandH,6,6)
  g.setColor(.62,.53,.34,.85)
  g.setLineWidth(1.2)
  g.rectangle('line',left-3,bandY,avail+5,bandH,6,6)
  g.setColor(.91,.89,.82,1)
  local statsY=bandY+layout.statPadding
  g.setFont(fonts.small)
  local stats={('MOVE %s'):format(move),('POWER %d'):format(power),('SHIELD %d'):format(shield)}
  local column=avail/3
  for i,label in ipairs(stats) do
    local x0=left+(i-1)*column
    local width=fonts.small.getWidth and fonts.small:getWidth(label) or 0
    local fit=width>column-2 and (column-2)/width or 1
    if fit<1 and g.push and g.translate and g.scale then
      g.push();g.translate(x0,statsY);g.scale(fit,fit)
      g.printf(label,0,0,column/fit,'center');g.pop()
    else
      g.printf(label,x0,statsY,column,'center')
    end
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
local WINDUP, IMPACT, RESULT = 1.10, 2.00, 2.72
local BONUS_TIME = 1.35
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
  local lunge=kind=='archer' and 0 or strike
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
  local x=fromX+(toX-fromX)*progress
  local g=love.graphics
  if kind=='fortress' then
    y=y-math.sin(progress*math.pi)*size*1.3
    local fade=math.min(1,(2.24-phase)/.24)
    g.setColor(1,.24,.04,.38*fade)
    g.circle('fill',x,y,size*1.45)
    g.setColor(1,.39,.06,fade)
    g.polygon('fill',x+direction*size,y,x-direction*size,y-size*.7,
      x-direction*size*3.1,y,x-direction*size,y+size*.7)
    g.circle('fill',x,y,size*.8)
    g.setColor(1,.88,.39,fade)
    g.circle('fill',x+direction*size*.25,y,size*.42)
  elseif progress<1 then
    g.setColor(.92,.79,.50,1)
    g.setLineWidth(math.max(1,size*.25))
    g.line(x-direction*size*3,y,x,y)
    g.setColor(.92,.92,.86,1)
    g.polygon('fill',x+direction*size*.55,y,x-direction*size*.45,y-size*.35,
      x-direction*size*.45,y+size*.35)
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

-- Battle state machine is purely presentational. The combat event,
-- including the victory D8, was already committed by rules.apply for every
-- mode. ROLL only reveals the same once-per-battle deterministic reward.
local function combatTitle(label,cx,y,w,tint,scale,font)
  local g=love.graphics
  font=font or fonts.large
  local measured=font.getWidth and font:getWidth(label) or #label*fontHeight(font)*.59
  local fit=math.min(scale or 1,(w-8)/math.max(1,measured))
  g.setFont(font)
  if g.push and g.translate and g.scale then
    g.push();g.translate(cx,y);g.scale(fit,fit)
    if g.shear then g.shear(-.12,0) end
    local width=w/fit
    g.setColor(.15,.035,.055,1)
    g.printf(label,-width/2+1.5,3,width,'center')
    color(tint)
    g.printf(label,-width/2,0,width,'center')
    g.pop()
  else
    color(tint);g.printf(label,cx-w/2,y,w,'center')
  end
end

local function drawBattleOverlay()
  local g=love.graphics
  local w,h=layout.w,layout.h
  local event=overlay.event
  local elapsed=overlay.elapsed
  local stage=overlay.action~=nil
  local revealed=not stage and elapsed>=WINDUP
  local impact=revealed and event.landed and elapsed>=IMPACT
  local result=not stage and elapsed>=RESULT
  local bonus=overlay.bonusElapsed
  local bonusDone=bonus and bonus>=BONUS_TIME
  local playerAttacks=mode=='local' or mode=='solo' and event.actor==1
    or mode=='online' and event.actor==onlineSide
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

  local label,detail,tint='STAGE AN ATTACK','Roll higher than Shield '..event.shield,gold
  if stage and notice~='' then detail=notice end
  if not stage then
    if not revealed then
      label,detail='ATTACK ROLL','Roll higher than Shield '..event.shield
    elseif result and event.defeated then
      if event.siege then
        label,detail='LAST TROOP DEFEATED','Final Siege is next.'
      else
        label=playerAttacks and 'VICTORY' or teamName:upper()..' WINS'
        detail=playerAttacks and 'Your enemy is defeated.' or otherName..' defender defeated.'
      end
    elseif event.landed then
      label,tint=playerAttacks and 'YOU LANDED THE ATTACK' or 'ATTACK LANDED',amber
      detail=result and ('%d damage  •  Turn over'):format(event.damage)
        or ('Rolled %d against Shield %d'):format(event.roll,event.shield)
    else
      label,tint='ATTACK REPELLED',ice
      detail=('Rolled %d against Shield %d  •  Turn over'):format(event.roll,event.shield)
    end
  end
  combatTitle(label,w*.5,h*.057,w-28,tint,hitTime<.20 and 1.14 or 1)
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
  if event.landed and (event.attackerClass=='archer' or event.attackerClass=='fortress') then
    drawBattleShot(event.attackerClass,x1+w*.11,x2,cy-fighterH*.55,math.max(5,h*.025),elapsed)
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

  local diceY=h*.70
  local size=math.min(w*.12,h*.105,70)
  if bonus then
    drawD12(g,w*.5,diceY,event.heal.roll,not bonusDone and bonus or nil,event.actor,size,fonts.stat)
    if bonusDone then
      local added=event.heal.actual
      text(added>0 and ('+%d Health'):format(added) or 'Health already full',12,h*.808,w-24,'center',fonts.stat)
    end
  elseif stage then
    drawD12(g,w*.5,diceY,12,nil,event.actor,size,fonts.stat,'D12')
  else
    drawD12(g,w*.5,diceY,event.roll,not revealed and math.max(0,elapsed) or nil,event.actor,size,fonts.stat)
  end
  overlay.button=nil
  local action
  if stage then action='ROLL'
  elseif result and event.heal and not bonus and playerAttacks then action='ROLL FOR BONUS'
  elseif result and (not event.heal or bonusDone) then action='CONTINUE' end
  if action then
    local bh=math.max(31,math.min(53,h*.094))
    local box={x=w*.16,y=h-bh-10,w=w*.68,h=bh}
    luxeButton(action,box.x,box.y,box.w,box.h,false)
    overlay.button=box
  end
end
local OPENING_BEAT, SIEGE_BEAT, FINALE_LENGTH = 1.8, 2.35, 6
local function drawOpening()
  local g=love.graphics
  local w,h=layout.w,layout.h
  local elapsed=overlay.elapsed
  local opening=overlay.opening
  local count=#opening.rounds
  local index=math.min(count,math.floor(elapsed/OPENING_BEAT)+1)
  local phase=elapsed-(index-1)*OPENING_BEAT
  local rolling=phase<.85 and phase or nil
  local rolls=opening.rounds[index]
  local title='ROLL FOR FIRST TURN'
  if not rolling then
    title=rolls[1]==rolls[2] and 'TIE! ROLL AGAIN'
      or (opening.first==1 and 'RED GOES FIRST' or 'BLUE GOES FIRST')
  end
  g.setColor(.025,.025,.055,1);g.rectangle('fill',0,0,w,layout.viewportH)
  panel(4,4,w-8,h-8)
  combatTitle(title,w*.5,h*.19,w-28,{1,.83,.46})
  local size=math.min(w*.16,h*.13,78)
  drawD12(g,w*.26,h*.50,rolls[1],rolling,1,size,fonts.medium)
  drawD12(g,w*.74,h*.50,rolls[2],rolling,2,size,fonts.medium)
  text('RED',8,h*.71,w*.5-16,'center',fonts.medium)
  text('BLUE',w*.5+8,h*.71,w*.5-16,'center',fonts.medium)
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
    text(owner==1 and 'The Red Kingdom conquers the Badlands.'
      or 'The Blue Kingdom conquers the Badlands.',10,h*.79,w-20,'center',fonts.small)
  end
  if t>=4.5 then text('Use the Zompa Back button to leave.',10,h*.91,w-20,'center',fonts.small) end
end
local function showEvent(event)
  selected,inspected,targets,intended=nil,nil,{},nil
  if event and event.type=='attack' then
    overlay={type='battle',event=event,elapsed=0}
  elseif event and event.siege then
    overlay={type='siege',siege=event.siege,elapsed=0}
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
  if sent then pending=true;notice='Sending turn…' else notice=tostring(err) end
  return sent
end

local function readOnline()
  local history,side,allowed=zompa.readTurns()
  if not history then onlineReady=false;return end
  onlineSide,onlineAllowed=side,allowed
  local oldCount=lastOnlineCount
  if #history~=oldCount then pending=false end
  if #history<2 then
    onlineReady=false
    lastOnlineCount=#history
    if allowed and not pending then
      sendHostTurn('I'..tostring(love.math.random(1,2147483646)))
    end
    return
  end
  if #history==oldCount then
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
    overlay={type='opening',opening=opening,elapsed=0}
  elseif synced.last and (#history==oldCount+1 or synced.winner) then
    beginEvent(synced.last,previous)
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
    luxeButton(isAttack and 'ATTACK NOW' or 'MOVE HERE',
      x,y,confirmW,h,isAttack)
    luxeButton('CANCEL',x+confirmW+5,y,w-confirmW-5,h,'neutral')
    actionBox={x=x,y=y,w=confirmW,h=h}
    cancelBox={x=x+confirmW+5,y=y,w=w-confirmW-5,h=h}
  else
    local label
    if mode=='online' and not onlineReady then label='WAITING FOR OPENING ROLL'
    elseif moving then label=moving.event.actor==2 and 'BLUE KINGDOM MOVES' or 'RED KINGDOM MOVES'
    elseif mode=='solo' and state.turn==2 then label='BLUE KINGDOM IS THINKING…'
    elseif inspected=='fort' and not state.forts[inspectedFortOwner].armed then label='FORTRESS FIRES AFTER BEING ATTACKED'
    elseif selected then label='TAP A GLOWING SPACE'
    elseif saveVersionChanged and state.moves==0 then label='RULES UPDATED  •  START A NEW MATCH'
    else label='PLAYER '..state.turn..'  •  CHOOSE A PIECE' end
    love.graphics.setColor(.11,.15,.17,.96)
    love.graphics.rectangle('fill',x,y,w,h,9,9)
    color(palette.text);love.graphics.setFont(fonts.small)
    love.graphics.printf(label,x+4,y+(h-fontHeight(fonts.small))*.5,w-8,'center')
  end
end
local function actorAction(action)
  if not mayAct() then return end
  if action.type=='attack' then
    local event=rules.describeAttack(state,action)
    if event then overlay={type='battle',event=event,action=action,elapsed=0} end
  elseif mode=='online' then sendOnline(action)
  else localAction(action) end
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
  local lastCPU=state.previous
  local function exposureAt(row,col)
    local exposure=0
    local spot={r=row,c=col}
    for _,enemy in ipairs(state.units) do
      if enemy.owner==1 and enemy.hp>0 and rules.inAttackRange(enemy,spot) then
        exposure=exposure+rules.classes[enemy.class].power*.48
      end
    end
    if rules.inAttackRange(otherF,spot) then exposure=exposure+rules.classes.fortress.power end
    return math.min(22,exposure)
  end
  for _,a in ipairs(all) do
    local score=0
    if a.type=='attack' then
      local u=rules.piece(state,a.id)
      local target=rules.occupied(state,a.r,a.c).ref
      local power=rules.classes[u.class].power
      local shield=rules.classes[target.class].shield
      local odds=(rules.DIE-shield)/rules.DIE
      score=odds*(power*2.2+(power>=target.hp and 35 or 0))
      if target.class=='fortress' then score=score+16 end
      if rules.distance(target,ownF)<=3 then score=score+8 end
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
      score=score-exposureAt(a.r,a.c)
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
      if lastCPU and lastCPU.actor==2 and lastCPU.type=='move' and lastCPU.id==a.id
        and a.r==lastCPU.from.r and a.c==lastCPU.from.c then score=score-17 end
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
    if not inside(overlay.button,x,y) then return end
    if overlay.action then
      local action=overlay.action
      if mode=='online' then
        if sendOnline(action) then overlay=nil end
      else localAction(action) end
    elseif overlay.event.heal and not overlay.bonusElapsed then
      overlay.bonusElapsed=0
      overlay.button=nil
    elseif overlay.event.siege then
      overlay={type='siege',siege=overlay.event.siege,elapsed=0}
    else
      overlay=nil
    end
    return
  end
  if state.winner~=nil then return end
  if inside(cardBox,x,y) then return end
  if inside(cancelBox,x,y) then
    intended=nil
    local piece=rules.piece(state,selected)
    inspected=piece.class=='fortress' and 'fort' or selected
    if piece.class=='fortress' then inspectedFortOwner=piece.owner end
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
  onTap(x,y)
end
local function fitHostedWindow()
  if not love.system or love.system.getOS()~='Web' then return end
  local window=love.window
  local screenW,screenH=window.getDesktopDimensions()
  if screenW<=0 or screenH<=0 then return end
  -- LÖVE Web reports the display dimensions. Zompa hosts this canvas below
  -- its toolbar and above Android's navigation area.
  local w=math.min(screenW,600)
  local hostChrome=math.max(112,math.ceil(screenH*.15))
  local h=math.max(200,math.min(screenH-hostChrome,math.floor(w*1.88)))
  window.setMode(w,h,{resizable=true,minwidth=240,minheight=200})
end
function love.load()
  fitHostedWindow()
  if love.graphics.newImage then
    -- The hosted WebGL runtime cannot mipmap these non-power-of-two sprites.
    local mipmaps=not love.system or love.system.getOS()~='Web'
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
  mode=zompa.mode()
  local seed=mode=='online' and 47061 or love.math.random(1,2147483600)
  local opening=mode~='online' and rules.initiative(seed) or nil
  state=rules.new(seed,opening and opening.first)
  saveVersionChanged=false
  if mode~='online' then
    local saved=zompa.loadSession()
    if saved then
      local restored,err=rules.restore(saved)
      if restored then
        state=restored
        opening=nil
      else
        saveVersionChanged=err=='Unrecognized save version.'
        print('Ignoring invalid saved session: '..tostring(err))
      end
    end
  end
  selected,inspected,targets,pending,overlay,intended,inspectedFortOwner=nil,nil,{},false,nil,nil,nil
  moving,queuedEvent,cardBox=nil,nil,nil
  if opening then
    overlay={type='opening',opening=opening,elapsed=0}
  elseif state.last and state.last.siege then
    overlay={type='siege',siege=state.last.siege,elapsed=0}
  end
  finishElapsed=0
  timers.cpu,timers.poll=0,0
  if mode=='online' then lastOnlineCount=-1 end
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
    if overlay.type=='opening' then
      if overlay.elapsed>=#overlay.opening.rounds*OPENING_BEAT+1 then overlay=nil end
    elseif overlay.type=='siege' then
      if overlay.elapsed>=#overlay.siege.volleys*SIEGE_BEAT then overlay=nil end
    elseif overlay.bonusElapsed then
      overlay.bonusElapsed=overlay.bonusElapsed+dt
    elseif not overlay.action and overlay.event.heal and overlay.elapsed>=RESULT+.64 then
      local actor=overlay.event.actor
      if mode=='solo' and actor==2 or mode=='online' and actor~=onlineSide then
        overlay.bonusElapsed=0
      end
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
  love.graphics.rectangle('fill',0,0,layout.w,layout.viewportH)
  drawBoard();drawActionBar();drawCard()
  if blocked then
    text('Online sync error: '..blocked,8,layout.h*.43,layout.w-16,'center',fonts.medium)
  end
  if overlay and overlay.type=='battle' then drawBattleOverlay()
  elseif overlay and overlay.type=='opening' then drawOpening()
  elseif overlay and overlay.type=='siege' then drawFinalSiege()
  elseif state.winner~=nil then drawFinished() end
end
function love.mousepressed(x,y,button) if button==1 then touch(x,y) end end
function love.touchpressed(_,x,y) touch(x,y) end
function love.keypressed(key)
  if key=='escape' then selected,inspected,targets,intended=nil,nil,{},nil end
end
