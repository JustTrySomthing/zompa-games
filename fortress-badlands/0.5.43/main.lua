-- Fortress Siege: Final Conquest — Zompa SDK v4 / LÖVE 11.5 graybox prototype.
-- This game's deterministic rules are shared by solo, pass-and-play, and turns-v1 online.
local rules = require('rules')
local zompa = require('zompa')
local chooseCpuAction = require('cpu')
local moveFx = require('movement_fx')
local mode = 'solo'
local state, onlineSide, onlineAllowed, onlineReady, lastOnlineCount
local selected, inspected, targets, pending, overlay, intended, actionBox, cancelBox, inspectedFortOwner
local layout, timers, notice, blocked = {}, {cpu=0,poll=0,dialog=0}, '', nil
local saveVersionChanged,turnSendFailed
-- Visual movement never alters rules, health, online tokens or saved state.
local moving, queuedEvent, cardBox = nil, nil, nil
local selectionAge=0
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
local intro, logo, horn, arena
local introTime=0
local function smoothstep(t)
  t=math.max(0,math.min(1,t))
  return t*t*(3-2*t)
end
local artBoard, unitArt = nil, { [1]={}, [2]={} }
local archerCloseup={}
-- Individually loaded character busts and board tokens; never a flattened UI.
local portraitArt,fortArt = { [1]={}, [2]={} }, {}
local fighterArt = {{},{}}
local mixer = zompa.audio()
local cues={}
local function playCue(name)
  local source=cues[name]
  if source then source:stop();source:play() end
end
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
  fonts.cardLabel=responsiveFont(w*.032,10,13)
  fonts.cardHint=responsiveFont(w*.031,10,14)
  fonts.guide=responsiveFont(w*.039,12,16)
  fonts.openingSide=responsiveFont(w*.042,12,18)
  local statPadding=5
  local cardStatH=fontHeight(fonts.cardStat)
  local statBandH=2*cardStatH+statPadding*2+4
  local cardHintH=fontHeight(fonts.cardHint)+3
  local cardH=6+titleH+2+statH+11+statBandH+cardHintH+7
  local topReserve=cardH+10
  local actionH=math.floor(math.max(36,48*uiScale)+.5)
  local actionGap=math.max(15,math.min(25,math.floor(h*.038+.5)))
  local bottomReserve=actionH+actionGap+7
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
    actionH=actionH,actionY=top+boardH+actionGap}
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
local function drawBadgeSprite(sprite,x,y,scale,viewport,opacity)
  local g=love.graphics
  local borderR=BADGE_R*scale*.88
  local stencil=g.stencil and g.setStencilTest
  if stencil then
    g.stencil(function()
      g.polygon('fill',faceHex(x,y,borderR))
    end,'replace',1)
    g.setStencilTest('greater',0)
  end
  g.setColor(1,1,1,opacity or 1)
  local iw,ih=sprite:getDimensions()
  local side=borderR*2
  if viewport then
    local _,_,vw,vh=viewport:getViewport()
    g.draw(sprite,viewport,x-borderR,y-borderR,0,side/vw,side/vh)
  else
    g.draw(sprite,x-borderR,y-borderR,0,side/iw,side/ih)
  end
  if stencil then g.setStencilTest() end
  -- Thin, uninterrupted outer edge. No offset shadow hex or extra left lip.
  g.setColor(.97,.78,.35,opacity or 1)
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
  if not rules.isCritical(hp,maximum) then return end
  local g=love.graphics
  local pulse=.5+.5*math.sin(love.timer.getTime()*math.pi*1.6)
  local vertices=faceHex(cx,cy,rad*(1.08+.07*pulse))
  local function corners(width)
    g.setLineWidth(width)
    for i=1,11,2 do
      local previous=(i-3)%12+1
      local following=(i+1)%12+1
      local x,y=vertices[i],vertices[i+1]
      g.line(x+(vertices[previous]-x)*.43,y+(vertices[previous+1]-y)*.43,
        x,y,x+(vertices[following]-x)*.43,y+(vertices[following+1]-y)*.43)
    end
  end
  g.setColor(.15,.025,.04,.90)
  corners(math.max(3.5,rad*.22))
  g.setColor(1,.26,.18,.38+.58*pulse)
  corners(math.max(2,rad*.14))
end
local function contactShadow(cx,cy,rad)
  local g=love.graphics
  g.setColor(.025,.023,.028,.47)
  g.polygon('fill',faceHex(cx+rad*.04,cy+rad*.11,rad*.91))
end
local function unitToken(u)
  local cx,cy=center(u.r,u.c)
  local rad=layout.radius
  local sprite=unitArt[u.owner][u.class]
  local active=selected==u.id and not moving and not overlay
  local lift=active and rad*.23*smoothstep(selectionAge/.16) or 0
  contactShadow(cx,cy,rad)
  if active then
    local g=love.graphics
    g.setColor(.085,.063,.041,.56)
    g.polygon('fill',faceHex(cx,cy+rad*.10,rad*1.09))
    g.setColor(1,.87,.56,.92)
    g.setLineWidth(math.max(1.6,rad*.085))
    g.polygon('line',faceHex(cx,cy,rad*1.05))
  end
  cy=cy-lift
  if sprite then
    drawBadgeSprite(sprite,cx,cy,layout.scale,archerCloseup[sprite])
  else
    color(teamColors[u.owner]);love.graphics.polygon('fill',faceHex(cx,cy,rad*.99))
    color(classColors[u.class]);love.graphics.polygon('fill',faceHex(cx,cy,rad*.82))
    emblem(u.class,cx,cy,rad*.48)
  end
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
        local t=(seed%15-7)*.005
        local cold=math.max(0,1-r/4)
        local warm=math.max(0,(r-6)/4)
        g.setColor(.45+t+.065*warm-.035*cold,.418+t*.7+.018*warm+.008*cold,
          .377+t*.6-.015*warm+.058*cold,1)
        g.polygon('fill',faceHex(x,y,R*1.002))
        g.setColor(.86,.82,.73,.095)
        g.polygon('fill',x-R*.24,y-R*.67,x+R*.26,y-R*.67,
          x+R*.48,y-R*.34,x+R*.11,y-R*.39,x-R*.14,y-R*.39)
        for k=1,7 do
          local a=((seed*7+k*43)%91)/91*math.pi*2
          local dist=R*(.1+((seed+k*13)%15)/43)
          local sx,sy=x+math.cos(a)*dist,y+math.sin(a)*dist
          local q=R*(.027+((seed+k*7)%9)/170)
          if k%2==0 then g.setColor(.22,.23,.19,.20)
          else g.setColor(.94,.89,.75,.10) end
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
    drawBadgeSprite(image,x,y,R/BADGE_R)
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
-- Use different silhouettes for actions even when viewed in grayscale.
local function moveMarker(cx,cy,rad)
  local g=love.graphics
  g.setColor(.12,.096,.061,.82)
  g.circle('fill',cx,cy,math.max(5,rad*.33))
  color(palette.gold,.97)
  g.setLineWidth(math.max(1.3,rad*.09))
  g.circle('line',cx,cy,math.max(4,rad*.27))
  g.circle('fill',cx,cy,math.max(1.4,rad*.078))
end

local function targetMarker(cx,cy,rad,chosen,selectedAt)
  local g=love.graphics
  local radius=rad*1.025
  local rim=faceHex(cx,cy,radius)

  -- A steady icy rim leaves critical Health as the pulsing board cue.
  g.setColor(.42,.77,.92,chosen and .25 or .27)
  g.setLineWidth(math.max(3.4,rad*.25))
  g.polygon('line',rim)
  g.setColor(.08,.15,.21,.94)
  g.setLineWidth(math.max(2.8,rad*.18))
  g.polygon('line',rim)
  if chosen then g.setColor(.84,.97,1,1)
  else g.setColor(.66,.86,.94,1) end
  g.setLineWidth(chosen and math.max(1.8,rad*.12) or math.max(1.15,rad*.085))
  g.polygon('line',rim)

  if not chosen then
    g.setColor(.86,.97,1,.92)
    g.setLineWidth(math.max(1.35,rad*.10))
    g.line(rim[5],rim[6],rim[7],rim[8],rim[9],rim[10])
  elseif selectedAt then
    local elapsed=love.timer.getTime()-selectedAt
    for i=0,2 do
      local phase=(elapsed-i*.14)/.62
      if phase>=0 and phase<1 then
        local ripple=rad*(.26+.765*(1-(1-phase)^1.5))
        g.setColor(.75,.94,1,.84*(1-phase^1.8))
        g.setLineWidth(math.max(1.2,rad*.085))
        g.polygon('line',faceHex(cx,cy,ripple))
      end
    end
  end
end

local function duelSkull(g,x,y,size,alpha)
  g.setColor(.19,.025,.05,alpha)
  g.circle('fill',x,y,size*1.12)
  g.setColor(.91,.71,.54,alpha)
  g.circle('fill',x,y-size*.16,size*.57)
  g.rectangle('fill',x-size*.30,y+size*.12,size*.60,size*.51,3,3)
  g.setColor(.15,.026,.044,alpha)
  g.circle('fill',x-size*.20,y-size*.09,size*.134)
  g.circle('fill',x+size*.20,y-size*.09,size*.134)
  g.polygon('fill',x,y+size*.04,x-size*.09,y+size*.21,x+size*.09,y+size*.21)
  for i=-1,1 do g.rectangle('fill',x+size*(i*.143-.019),y+size*.46,size*.038,size*.17) end
end

local function deathMatchMarker(cx,cy,rad,elapsed)
  local g=love.graphics
  local reveal=smoothstep(elapsed/.18)
  local settle=smoothstep(elapsed/.34)
  local radius=math.max(8,rad*.43)*(reveal*.20+.80)
  local x,y=cx+rad*.60,cy-rad*(.53+.20*settle)
  local glow=math.max(0,1-elapsed/.48)
  if glow>0 then
    g.setColor(1,.51,.41,glow*.48)
    g.setLineWidth(1.25)
    g.circle('line',x,y,radius*(2-glow*.8))
  end
  g.setColor(.06,.018,.033,.94*reveal)
  g.circle('fill',x,y+1,radius+1.5)
  g.setColor(.34,.077,.12,reveal)
  g.circle('fill',x,y,radius)
  g.setColor(.98,.69,.55,reveal)
  g.setLineWidth(1.25)
  g.circle('line',x,y,radius)
  duelSkull(g,x,y-radius*.16,radius*.76,reveal)
  g.setColor(.96,.78,.61,reveal)
  g.setLineWidth(math.max(1,radius*.12))
  g.line(x-radius*.58,y+radius*.28,x+radius*.51,y+radius*.64)
  g.line(x+radius*.58,y+radius*.28,x-radius*.51,y+radius*.64)
  for _,sign in ipairs({-1,1}) do
    g.circle('fill',x+sign*radius*.55,y+radius*.27,radius*.09)
    g.circle('fill',x+sign*radius*.50,y+radius*.63,radius*.09)
  end
end

local function drawFortressDamage(x,y,rad,hp)
  if hp<=0 or hp>=rules.FORT_HP then return end
  local g=love.graphics
  local severe=hp<=rules.FORT_HP*.40
  local function line(points)
    local pixels={}
    for i=1,#points,2 do
      pixels[i],pixels[i+1]=x+points[i]*rad,y+points[i+1]*rad
    end
    g.line((table.unpack or unpack)(pixels))
  end
  -- Scars sit inside the badge and follow the tower masonry.
  g.setColor(.22,.108,.073,.91)
  g.setLineWidth(math.max(1.4,rad*.10))
  line({-.29,-.28,-.37,-.10,-.26,.00,-.34,.19})
  g.setColor(.98,.75,.51,.83)
  g.setLineWidth(math.max(.70,rad*.036))
  line({-.24,-.27,-.31,-.10,-.20,.01,-.29,.20})
  if not severe then return end
  g.setColor(.135,.085,.078,.98)
  g.polygon('fill',x+rad*.13,y-rad*.34,x+rad*.46,y-rad*.35,
    x+rad*.36,y-rad*.14,x+rad*.48,y+rad*.02,x+rad*.21,y+rad*.17,x+rad*.29,y-rad*.05)
  g.setColor(.91,.67,.42,.85)
  line({.15,-.33,.29,-.05,.21,.17})
  local time=love.timer.getTime()
  for i=1,4 do
    local age=(time*.58+i*.25)%1
    local px=x+rad*(.31+.29*age+math.sin(time*2+i)*.07)
    local py=y-rad*(.26+.77*age)
    g.setColor(.20,.18,.19,.68*(1-age))
    g.circle('fill',px,py,rad*(.16+.28*age))
  end
  g.setColor(.88,.30,.10,.46)
  g.circle('fill',x+rad*.31,y-rad*.07,math.max(2.0,rad*.15))
  g.setColor(1,.63,.29,.74+.20*math.sin(time*9))
  g.circle('fill',x+rad*.31,y-rad*.07,math.max(1.4,rad*.08))
end

local function drawBoard(practice,practiceMove)
  local board=practice or state
  local animation=practiceMove or moving
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
  if selected and not overlay and not state.winner then
    for k in pairs(targets.moves or {}) do
      local r,c=rules.fromkey(k)
      local cx,cy=center(r,c)
      moveMarker(cx,cy,layout.radius)
    end
  end
  local route=intended and intended.route
  if route and not overlay and not animation then
    local g=love.graphics
    for i=2,#route do
      local from,to=route[i-1],route[i]
      local ax,ay=center(from.r,from.c)
      local bx,by=center(to.r,to.c)
      g.setColor(.105,.073,.055,.94);g.setLineWidth(4.4)
      g.line(ax,ay,bx,by)
      color(palette.gold,.97);g.setLineWidth(2)
      g.line(ax,ay,bx,by)
      g.circle('fill',bx,by,math.max(2,layout.radius*.12))
    end
  end
  for _,fort in ipairs(board.forts) do
    local cx,cy=center(fort.r,fort.c)
    local rr=layout.radius
    if selected==fort.id and not overlay then
      color(palette.gold,.94)
      love.graphics.setLineWidth(math.max(1.6,rr*.085))
      love.graphics.polygon('line',faceHex(cx,cy,rr*1.05))
    end
    if fort.hp>0 then
      contactShadow(cx,cy,rr)
      fortressArt(cx,cy,fort.owner,rr)
      drawFortressDamage(cx,cy,rr,fort.hp)
    end
    if fort.hp<rules.FORT_HP then
      healthBar(cx-rr*.58,cy+rr*.91,rr*1.16,math.max(3.5,layout.cell*.06),
        fort.hp,rules.FORT_HP)
    end
  end
  for _,u in ipairs(board.units) do
    if u.hp>0 and (not animation or animation.id~=u.id) then unitToken(u) end
  end
  if selected and not overlay and not animation then
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
  if animation then
    local unit=board.units[animation.id]
    local sprite=unitArt[unit.owner][unit.class]
    moveFx.draw(love.graphics,animation,center,layout.radius,function(cx,cy,scale,opacity)
      if sprite then
        drawBadgeSprite(sprite,cx,cy,layout.scale*scale,archerCloseup[sprite],opacity)
      else
        color(teamColors[unit.owner],opacity)
        love.graphics.polygon('fill',faceHex(cx,cy,layout.radius*.81*scale))
      end
      if opacity>.85 then
        local maximum=rules.classes[unit.class].hp
        criticalPulse(cx,cy,layout.radius,unit.hp,maximum)
        if unit.hp<maximum then
          local rad=layout.radius
          healthBar(cx-rad*.52,cy+rad*.90,rad*1.04,math.max(3.5,layout.cell*.06),unit.hp,maximum)
        end
      end
    end)
  end
  if intended and intended.type=='move' and not overlay then
    local g=love.graphics
    local cx,cy=center(intended.r,intended.c)
    local rad=layout.radius
    g.setColor(.16,.115,.065,.90)
    g.circle('fill',cx,cy,rad*.47)
    color(palette.gold)
    g.setLineWidth(math.max(1.7,rad*.12))
    g.circle('line',cx,cy,rad*.47)
    g.line(cx-rad*.23,cy,cx-rad*.055,cy+rad*.18,cx+rad*.24,cy-rad*.18)
  end
  if practice then return end
  local attackTargets=selected and not overlay and targets.attacks
  local function healthRadius(piece)
    -- Keep the pulsing corners inside an attack rim when both cues apply.
    local marked=attackTargets and attackTargets[rules.key(piece.r,piece.c)]
    return layout.radius*(marked and .75 or 1)
  end
  for _,fort in ipairs(board.forts) do
    local cx,cy=center(fort.r,fort.c)
    criticalPulse(cx,cy,healthRadius(fort),fort.hp,rules.FORT_HP)
  end
  for _,u in ipairs(board.units) do
    if u.hp>0 and u.hp<=rules.classes[u.class].hp*.25 and (not animation or animation.id~=u.id) then
      local cx,cy=center(u.r,u.c)
      criticalPulse(cx,cy,healthRadius(u),u.hp,rules.classes[u.class].hp)
    end
  end
  if attackTargets then
    for key in pairs(attackTargets) do
      local r,c=rules.fromkey(key)
      local cx,cy=center(r,c)
      local chosen=intended and intended.type=='attack' and intended.r==r and intended.c==c
      targetMarker(cx,cy,layout.radius,chosen,chosen and intended.selectedAt)
    end
  end
  if attackTargets and intended and intended.deathMatch then
    local cx,cy=center(intended.r,intended.c)
    deathMatchMarker(cx,cy,layout.radius,math.max(0,love.timer.getTime()-intended.selectedAt))
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
local function drawCard(practicePiece,focus)
  cardBox=nil
  if not state then return end
  local fort=not practicePiece and inspected=='fort' and state.forts[inspectedFortOwner]
  local piece=practicePiece or fort or state.units[inspected or selected]
  if not piece or (not fort and piece.hp<=0) then return end
  local class=rules.classes[piece.class]
  local hint
  if fort then hint=fort.armed and 'Fires forward only' or 'Fires once attacked'
  elseif class.attackStraight then hint=class.straight and 'Move and attack straight' or 'Attacks in a straight line'
  elseif class.straight then hint='Move in a clear straight line'
  elseif class.forward then hint='Moves forward only'
  elseif piece.class=='wizard' then hint='Teleports over pieces'
  elseif piece.class=='barbarian' then hint='Attacks adjacent enemies' end
  local h=layout.cardH
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
  local isTarget=not practicePiece and intended and intended.type=='attack'
  local deathMatch=isTarget and intended.deathMatch
  if deathMatch then hint='DEATH MATCH' end
  local highlightShield=isTarget and not deathMatch
  if isTarget then
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
  local tt=team==1 and {.93,.48,.47} or {.59,.77,.96}
  g.setColor(tt[1],tt[2],tt[3],1)
  g.printf(title,left,y+6,avail,'left')
  local function statFocus(key,sx,sy,sw,sh)
    if focus~=key and not (highlightShield and key=='shield') then return end
    g.setColor(.34,.24,.105,1)
    g.rectangle('fill',sx,sy,sw,sh,4,4)
    color(palette.gold,.95);g.setLineWidth(1.2)
    g.rectangle('line',sx,sy,sw,sh,4,4)
  end
  local function fact(label,value,fx,fy,fw,numberFont,highlighted)
    local labelH,numberH=fontHeight(fonts.cardLabel),fontHeight(numberFont)
    g.setFont(fonts.cardLabel)
    g.setColor(.73,.77,.81,1)
    g.printf(label,fx,fy+(numberH-labelH)*.5,fw,'left')
    g.setFont(numberFont)
    if highlighted then color(palette.gold) else color(palette.text) end
    g.printf(tostring(value),fx,fy,fw,'right')
  end
  local hpY=y+8+fontHeight(fonts.medium)
  local hpH=fontHeight(fonts.stat)
  statFocus('health',left-3,hpY-1,avail+5,hpH+9)
  fact('HEALTH',('%d / %d'):format(piece.hp,class.hp),left,hpY,avail,fonts.stat,true)
  healthBar(left,hpY+hpH+3,avail,3,piece.hp,class.hp)
  local bandH=layout.statBandH
  local bandY=hpY+hpH+11
  local bandX,bandW=left-3,avail+5
  g.setColor(.093,.132,.164,1)
  g.rectangle('fill',bandX,bandY,bandW,bandH,6,6)
  g.setColor(.55,.45,.31,.80)
  g.setLineWidth(1)
  g.rectangle('line',bandX,bandY,bandW,bandH,6,6)
  local rowH=fontHeight(fonts.cardStat)
  local firstY=bandY+layout.statPadding
  local secondY=firstY+rowH+4
  local cellW=bandW*.5
  g.setColor(.60,.51,.36,.33)
  g.line(bandX+4,secondY-2,bandX+bandW-4,secondY-2)
  g.line(bandX+cellW,bandY+4,bandX+cellW,bandY+bandH-4)
  local function stat(key,label,value,col,sy)
    local sx=bandX+col*cellW
    statFocus(key,sx+2,sy-2,cellW-4,rowH+4)
    fact(label,value,sx+5,sy,cellW-10,fonts.cardStat,focus==key or (highlightShield and key=='shield'))
  end
  stat('power','POWER',class.power,0,firstY)
  stat('range','RANGE',rules.attackRange(piece.class),1,firstY)
  stat('move','MOVE',class.move or 'ANY',0,secondY)
  stat('shield','SHIELD',class.shield,1,secondY)
  if hint then
    g.setFont(fonts.cardHint)
    if deathMatch then g.setColor(1,.67,.56,1) else g.setColor(.71,.76,.78,1) end
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
local COMBAT_READY_TIME, QUICK_READY_TIME = 1.15, .24
local COLLAPSE_TIME = .75
local WINDUP, IMPACT, RESULT = 1.10, 2.00, 2.72
local BONUS_TIME = 1.9
local DUEL_INTRO, DUEL_ROUND = 1.34, 4.20
local DUEL_SECOND, DUEL_LAND, DUEL_REVEAL = 1.73, 1.16, 3.18
local function playDuelCues(view,before)
  local rounds=view.event.deathMatch.rounds
  local function crossed(beat,cue)
    if before<beat and view.elapsed>=beat then playCue(cue) end
  end
  crossed(.03,'breach')
  for i=1,#rounds do
    local start=DUEL_INTRO+(i-1)*DUEL_ROUND
    crossed(start+DUEL_LAND,'land')
    crossed(start+DUEL_SECOND+DUEL_LAND,'land')
    crossed(start+DUEL_REVEAL,i==#rounds and 'collapse' or 'blocked')
  end
end
local function battleLead(view)
  return view.quick and QUICK_READY_TIME or COMBAT_READY_TIME
end
local function newlyCritical(event)
  local threshold=rules.classes[event.defenderClass].hp*.25
  return event.landed and event.defenderHpStart>threshold
    and event.defenderHpEnd>0 and event.defenderHpEnd<=threshold
end
local function playBattleImpact(view,before)
  local beat=battleLead(view)+IMPACT
  if before>=beat or view.elapsed<beat then return end
  local event=view.event
  playCue(event.landed and event.attackerClass or 'blocked')
  if event.firstFortHit then playCue('breach')
  elseif newlyCritical(event) then playCue('critical') end
end
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
    drawBadgeSprite(sprite,cx,cy,rad/BADGE_R)
  elseif kind=='fortress' then
    fortressArt(cx,cy,team,rad)
  else
    drawBattleFigure(kind,cx,cy,rad)
  end
end
local function drawFighter(kind,team,cx,baseY,w,h,direction,strike,recoil,hp,alpha)
  if kind=='fortress' then
    local y,r=baseY-h*.46,math.min(w,h)*.49
    drawCombatant(kind,cx,y,r,team,recoil>0)
    drawFortressDamage(cx,y,r,math.max(1,hp or rules.FORT_HP))
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
  g.setColor(1,1-recoil*.20,1-recoil*.21,alpha or 1)
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
-- Use require('d12') here to restore the previous die finish.
local drawD12=require('d12_polished')

local function luxeButton(label,x,y,w,h,red)
  local g=love.graphics
  g.setColor(.012,.013,.020,.72)
  g.rectangle('fill',x-1,y+3,w+2,h,10,10)
  if red=='neutral' then g.setColor(.14,.18,.23,1)
  elseif red then g.setColor(.36,.10,.14,1)
  else g.setColor(.08,.30,.22,1) end
  g.rectangle('fill',x,y,w,h,9,9)
  color(palette.gold,red=='neutral' and .48 or .88)
  g.setLineWidth(1.4)
  g.rectangle('line',x+.7,y+.7,w-1.4,h-1.4,9,9)
  g.setColor(1,.91,.72,.14)
  g.line(x+10,y+4,x+w-10,y+4)
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
  local ratio=math.max(0,math.min(1,amount/maxhp))
  g.setColor(.037,.054,.073,1)
  g.rectangle('fill',x,y,w,8,4,4)
  if ratio>0 then
    if ratio<=.28 then g.setColor(.88,.27,.27,1)
    else g.setColor(.34,.76,.51,1) end
    local fill=(w-4)*ratio
    g.rectangle('fill',x+2,y+2,fill,4,2,2)
    g.setColor(1,1,.90,.26)
    g.rectangle('fill',x+2,y+2,fill,1)
  end
  g.setColor(.65,.61,.54,.70);g.setLineWidth(1)
  g.rectangle('line',x,y,w,8,4,4)
end

-- The combat and bonus dice are already resolved by rules.apply.
-- Playback reveals the same results in every mode.
local function combatTitle(label,cx,y,w,tint,scale,font,alpha,bold)
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
    if bold then
      local offset=fontHeight(font)*.018
      g.printf(label,-width/2-offset,0,width,'center')
      g.printf(label,-width/2+offset,offset,width,'center')
    end
    g.printf(label,-width/2,0,width,'center')
    g.pop()
  else
    color(tint,alpha);g.printf(label,cx-w/2,y,w,'center')
  end
end

local function battleBackdrop(w,h,actor)
  local g=love.graphics
  g.setColor(.050,.052,.070,1)
  g.rectangle('fill',0,0,w,h)
  if arena then
    local aw,ah=arena:getDimensions()
    g.setColor(1,1,1,1)
    g.draw(arena,5,5,0,(w-10)/aw,(h-10)/ah)
  end
  for side=1,2 do
    local owner=side==1 and actor or 3-actor
    local tint=teamLabels[owner]
    for ring=6,1,-1 do
      g.setColor(tint[1]*.46,tint[2]*.32,tint[3]*.40,.035)
      g.circle('fill',w*(side==1 and .24 or .76),h*.365,w*(.175+ring*.022))
    end
  end
  g.setColor(.048,.051,.069,.85)
  g.rectangle('fill',6,h*.575,w-12,h*.425-6)
  color(palette.gold,.21);g.setLineWidth(1)
  g.line(w*.10,h*.585,w*.90,h*.585)
  color(palette.gold,.64);g.setLineWidth(1.35)
  g.rectangle('line',4,4,w-8,h-8,10,10)
end

local function drawBattleOverlay(view,practice)
  local g=love.graphics
  local w,h=layout.w,layout.h
  local event=view.event
  local elapsed=view.elapsed-battleLead(view)
  local ready=elapsed<0
  local revealed=elapsed>=WINDUP
  local resolved=elapsed>=IMPACT
  local impact=event.landed and resolved
  local result=elapsed>=RESULT
  local bonus=view.bonusElapsed
  local bonusDone=bonus and bonus>=BONUS_TIME
  local playerAttacks=practice or playerControlsReward(event.actor)
  local attacker,defender=rules.classes[event.attackerClass],rules.classes[event.defenderClass]
  local teamName=event.actor==1 and 'Red' or 'Blue'
  local otherName=event.actor==1 and 'Blue' or 'Red'
  local attackerHp=event.attackerHpStart+(bonusDone and event.heal.actual or 0)
  local defenderHp=impact and event.defenderHpEnd or event.defenderHpStart
  local gold={1,.83,.46}
  local amber={1,.64,.28}
  local red={1,.41,.36}
  local ice={.66,.88,1}
  battleBackdrop(w,h,event.actor)
  local hitTime=resolved and elapsed-IMPACT or 10
  local hitTint=not event.landed and ice or event.attackerClass=='wizard' and {.83,.54,1}
    or event.attackerClass=='ogre' and {.93,.55,.29} or amber

  local label,detail,tint='ATTACK ROLL','Roll higher than Shield '..event.shield,gold
  if result and event.defeated then
    label=playerAttacks and 'VICTORY' or teamName:upper()..' WINS'
    detail=playerAttacks and 'Your Foe is Defeated' or otherName..' defender defeated.'
  elseif resolved and event.landed then
    label,tint=playerAttacks and 'YOU LANDED THE ATTACK' or 'ATTACK LANDED',amber
    if event.firstFortHit then label='FORTRESS HIT'
    elseif newlyCritical(event) then label='CRITICAL HEALTH';tint=red end
    detail=result and ('%d damage  •  Turn over'):format(event.damage)
      or ('Rolled %d against Shield %d'):format(event.roll,event.shield)
  elseif resolved then
    label,tint='ATTACK REPELLED',ice
    detail=('Rolled %d against Shield %d  •  Turn over'):format(event.roll,event.shield)
  elseif revealed then
    detail=('Rolled %d against Shield %d'):format(event.roll,event.shield)
  end
  if practice then
    if impact then
      detail=('Roll %d beats Shield %d  ·  %d Health lost'):format(event.roll,event.shield,event.damage)
    elseif not revealed then
      detail=('Archer Power %d  ·  Target Shield %d'):format(attacker.power,event.shield)
    end
  end
  if ready then
    local entrance=smoothstep(view.elapsed/.25)
    local alpha=math.min(entrance,smoothstep(-elapsed/.14))
    local y=h*.057+9*(1-entrance)
    local headline=view.quick and 'Attack Roll' or 'Ready for Combat'
    combatTitle(headline,w*.5,y,w-28,gold,1.10+.22*(1-entrance),fonts.large,alpha)
  else
    combatTitle(label,w*.5,h*.057,w-28,tint,hitTime<.20 and 1.14 or 1)
  end
  combatTitle(detail,w*.5,h*.156,w-24,palette.text,1,practice and fonts.guide or fonts.small)

  local cy=h*.482
  local fighterH=h*(h<365 and .215 or .24)
  local x1,x2=w*.23,w*.77
  local dieSize=math.min(w*.087,h*.067,48)
  if not bonus and not (result and event.heal) then
    local diceY=h*.384
    g.setColor(.035,.035,.05,.82)
    g.circle('fill',w*.5,diceY,dieSize*1.16)
    color(palette.gold,.37);g.setLineWidth(1.15)
    g.circle('line',w*.5,diceY,dieSize*1.16)
    drawD12(g,w*.5,diceY,revealed and event.roll or 12,
      not ready and not revealed and math.max(0,elapsed) or nil,event.actor,dieSize,fonts.stat,
      ready and 'D12' or nil)
  end
  local strike=event.landed and strikePulse(elapsed,1.67,2,2.44) or 0
  local recoil=resolved and strikePulse(elapsed,1.99,2.11,2.49)
    *(event.attackerClass=='ogre' and 1.35 or event.landed and 1 or .55) or 0
  combatTitle(teamName..' '..attacker.name,x1,h*.214,w*.40,teamLabels[event.actor],1,fonts.stat)
  combatTitle(otherName..' '..defender.name,x2,h*.214,w*.40,teamLabels[3-event.actor],1,fonts.stat)
  for _,cx in ipairs({x1,x2}) do
    g.setColor(.025,.025,.032,.72)
    g.polygon('fill',cx-w*.13,cy,cx-w*.07,cy-h*.015,cx+w*.10,cy-h*.013,cx+w*.14,cy+h*.005,
      cx+w*.07,cy+h*.012,cx-w*.08,cy+h*.011)
  end
  if hitTime<.24 then
    color(hitTint,(event.firstFortHit and .26 or .14)*(1-hitTime/.24))
    g.circle('fill',x2,cy-fighterH*.45,fighterH*.48)
  end
  drawFighter(event.defenderClass,3-event.actor,x2,cy,w*.39,fighterH,-1,0,recoil,defenderHp)
  drawFighter(event.attackerClass,event.actor,x1,cy,w*.39,fighterH,1,strike,0,attackerHp)
  if attacker.projectile then
    local launchY=cy-fighterH*(event.attackerClass=='wizard' and .78 or .55)
    drawBattleShot(event.attackerClass,x1+w*.13,x2,launchY,math.max(5,h*.025),elapsed)
  end
  local barY=h*.506
  local defenderFill=event.defenderHpStart+(defenderHp-event.defenderHpStart)*smoothstep(hitTime/.30)
  local attackerFill=attackerHp
  if bonusDone then
    attackerFill=event.attackerHpStart+event.heal.actual*smoothstep((bonus-BONUS_TIME)/.32)
  end
  battleBar(x1,barY,w*.34,attackerFill,attacker.hp)
  battleBar(x2,barY,w*.34,defenderFill,defender.hp)
  text(('%d / %d HEALTH'):format(attackerHp,attacker.hp),x1-w*.20,barY+11,w*.40,'center',fonts.cardHint)
  text(('%d / %d HEALTH'):format(defenderHp,defender.hp),x2-w*.20,barY+11,w*.40,'center',fonts.cardHint)
  if hitTime<.72 then
    local travel=hitTime/.72
    local kind=event.attackerClass
    local radius=(kind=='ogre' or kind=='fortress') and 45 or 29
    local px,py=x2,cy-fighterH*.47
    for i=1,kind=='wizard' and 12 or 8 do
      local angle=i*2.39996
      local reach=8+travel*radius*(1+i%3*.27)
      local dx,dy=math.cos(angle),math.sin(angle)
      local x,y=px+dx*reach,py+dy*reach
      color(hitTint,(1-travel)*.84)
      g.setLineWidth(kind=='ogre' and 3 or 1.7)
      if kind=='wizard' then
        g.line(x,y,x+dx*5-dy*4,y+dy*5+dx*4,x+dx*13,y+dy*13)
      else
        g.line(x,y,x+dx*8,y+dy*8)
      end
    end
    if kind=='ogre' or event.firstFortHit or not event.landed then
      color(hitTint,(1-travel)*.66);g.setLineWidth(2)
      g.circle('line',px,py,10+travel*radius)
    end
    combatTitle(impact and '-'..event.damage or 'BLOCKED',x2,cy-fighterH*.53-travel*25,
      w*.39,impact and red or ice,1.35-travel*.35,fonts.large,1-travel*.55)
  end

  local bh=math.max(32,math.min(48,h*.085))
  local inset=math.max(18,math.min(32,h*.052))
  local buttonY=h-bh-inset
  local rewardY=math.min(h*.748,buttonY-fontHeight(fonts.medium)-10)
  local size=math.min(w*.105,h*.075,55)
  local diceY=math.min(h*.662,rewardY-size*.80)
  if not result then
    local vsY=h*.65
    g.setColor(.064,.078,.102,.74)
    g.rectangle('fill',w*.13,vsY-7,w*.74,fontHeight(fonts.stat)+14,7,7)
    color(palette.gold,.30);g.setLineWidth(1)
    g.line(w*.50,vsY-1,w*.50,vsY+fontHeight(fonts.stat)+1)
    combatTitle(('Power %d'):format(attacker.power),w*.31,vsY,w*.34,palette.text,1,fonts.stat)
    combatTitle(('Shield %d'):format(event.shield),w*.69,vsY,w*.34,palette.gold,1,fonts.stat)
  elseif event.fullHealth then
    text('Already at Full Health',12,h*.68,w-24,'center',fonts.medium)
  elseif result and event.heal then
    local panelY=h*.600
    local panelH=buttonY-panelY-8
    g.setColor(.055,.119,.109,.86)
    g.rectangle('fill',w*.13,panelY,w*.74,panelH,9,9)
    color(palette.gold,.34);g.setLineWidth(1)
    g.rectangle('line',w*.13,panelY,w*.74,panelH,9,9)
    if bonus then
      drawD12(g,w*.5,diceY,event.heal.roll,not bonusDone and bonus or nil,event.actor,size,fonts.stat)
      if bonusDone then
        local reveal=smoothstep((bonus-BONUS_TIME)/.35)
        combatTitle(('+%d HEALTH'):format(event.heal.actual),w*.5,rewardY,w*.69,
          {.62,1,.75},1+.1*(1-reveal),fonts.medium)
      else
        text('Rolling for Health',12,rewardY,w-24,'center',fonts.small)
      end
    else
      drawD12(g,w*.5,diceY,12,nil,event.actor,size*.85,fonts.cardHint,'D12')
      text('Health Reward',12,rewardY,w-24,'center',fonts.medium)
    end
  end
  view.button=nil
  local action
  if result then
    if event.heal and not bonus and playerAttacks then action='Roll for Reward'
    elseif not event.heal or bonusDone then action='CONTINUE' end
  end
  if action then
    local box={x=w*.16,y=buttonY,w=w*.68,h=bh}
    luxeButton(action,box.x,box.y,box.w,box.h,false)
    view.button=box
  end
end
local function drawDeathMatch(view)
  local g=love.graphics
  local w,h=layout.w,layout.h
  local event=view.event
  local duel=event.deathMatch
  local elapsed=view.elapsed
  local round=math.max(1,math.min(#duel.rounds,1+math.floor((elapsed-DUEL_INTRO)/DUEL_ROUND)))
  local time=elapsed-DUEL_INTRO-(round-1)*DUEL_ROUND
  local rolls=duel.rounds[round]
  local impactTime=time-DUEL_REVEAL
  local resolved=round==#duel.rounds and impactTime>=0
  local active=time>=0 and time<DUEL_LAND and 1
    or time>=DUEL_SECOND and time<DUEL_SECOND+DUEL_LAND and 2 or nil
  local ember={1,.37,.31}
  local ivory={1,.88,.71}
  local gold={1,.80,.42}
  local owners={event.actor,3-event.actor}
  local classes={event.attackerClass,event.defenderClass}
  local hp={event.attackerHpStart,event.defenderHpStart}
  local winningTeam=teamNames[owners[duel.winner]]
  local motion=math.max(0,1-elapsed/.60)*7
  if resolved then motion=math.max(0,1-impactTime/.47)*10 end
  local shaking=motion>0 and g.push and g.translate
  if shaking then
    g.setColor(.07,.023,.044,1);g.rectangle('fill',0,0,w,h)
    g.push()
    g.translate(motion*math.sin(elapsed*84),motion*.59*math.cos(elapsed*103))
  end
  battleBackdrop(w,h,event.actor)
  g.setColor(.12,.018,.046,.55);g.rectangle('fill',5,5,w-10,h-10,9,9)
  color(ember,.53);g.setLineWidth(1.4);g.rectangle('line',4,4,w-8,h-8,10,10)
  local entrance=smoothstep(elapsed/.32)
  local titleY=h*.150-(1-entrance)*h*.026
  g.setColor(.23,.035,.064,.86*entrance)
  g.polygon('fill',w*.12,h*.139,w*.94,h*.139,w*.88,h*.252,w*.06,h*.252)
  g.setColor(.73,.21,.21,.5*entrance);g.setLineWidth(1)
  g.line(w*.12,h*.139,w*.94,h*.139)
  g.line(w*.06,h*.252,w*.88,h*.252)
  for i=1,25 do
    local a=i*2.39996
    local x=w*.5+math.cos(a)*w*(.20+i%7*.036)
    local y=h*.166+math.sin(a)*h*(.012+i%5*.012)
    g.setColor(.64,.034,.078,entrance*(.20+i%4*.10))
    g.circle('fill',x,y,1+i%5*.63)
  end
  local skullY=h*.093
  local skullSize=math.min(h*.042,w*.045,25)
  color(gold,.38*entrance);g.setLineWidth(1)
  g.line(w*.16,skullY,w*.5-skullSize*1.5,skullY)
  g.line(w*.5+skullSize*1.5,skullY,w*.84,skullY)
  duelSkull(g,w*.5,skullY,skullSize,entrance)
  combatTitle('DEATH MATCH',w*.5,titleY,w*.88,ivory,
    math.min(1+.46*(1-entrance),h*.105/fontHeight(fonts.finale)),fonts.finale,entrance,true)

  local headline='BOTH COMBATANTS ARE CRITICAL'
  local detail='Higher roll wins. One combatant falls.'
  local tint=ivory
  if resolved then
    headline=winningTeam:upper()..' WINS'
    detail=teamNames[owners[3-duel.winner]]..' '..rules.classes[classes[3-duel.winner]].name..' is defeated.'
    tint=gold
  elseif active then
    headline=teamNames[owners[active]]:upper()..' ROLLS'
    detail='Round '..round..'  •  Highest D12 wins'
    tint=teamLabels[owners[active]]
  elseif time>=DUEL_REVEAL then
    headline='TIED  •  ROLL AGAIN'
    detail='Both combatants roll again.'
    tint=gold
  elseif time>=DUEL_SECOND+DUEL_LAND then
    headline='THE DICE HAVE LANDED'
  elseif time>=DUEL_LAND then
    headline=teamNames[owners[1]]:upper()..' ROLLS '..rolls[1]
    detail=teamNames[owners[2]]..' rolls next.'
  end
  local headerY=h*.275
  local resultScale=resolved and 1.10+.28*(1-smoothstep(impactTime/.32)) or 1
  combatTitle(headline,w*.5,headerY,w*.90,tint,
    math.min(resultScale,h*.065/fontHeight(fonts.large)),fonts.large,1,true)
  combatTitle(detail,w*.5,h*.343,w*.90,palette.text,
    math.min(1,h*.049/fontHeight(fonts.small)),fonts.small)
  for side=1,2 do
    local cx=w*(side==1 and .27 or .73)
    local baseY=h*.603
    local fighterH=h*.210
    local teamTint=teamLabels[owners[side]]
    local losing=resolved and side~=duel.winner
    local focus=side==active or resolved and not losing
    local fall=losing and smoothstep(impactTime/.62) or 0
    local direction=side==1 and 1 or -1
    local glow=focus and teamTint or ember
    for ring=4,1,-1 do
      color(glow,(focus and .11 or .044)*(1-fall))
      g.circle('fill',cx,baseY-fighterH*.48,math.min(w*.16,h*.102)*(1+ring*.13))
    end
    if fall<.92 then
      drawFighter(classes[side],owners[side],cx-direction*w*.095*fall,
        baseY+fighterH*.20*fall,w*.42*(1-.26*fall),fighterH*(1-.47*fall),
        direction,0,fall,hp[side],1-fall)
    end
    if losing then
      local px,py=cx,baseY-fighterH*.46
      local burst=math.min(1,impactTime/.85)
      for i=1,19 do
        local a=i*2.39996
        local reach=(.25+burst)*w*(.06+i%4*.023)
        local x,y=px+math.cos(a)*reach,py+math.sin(a)*reach+burst*burst*h*.043
        color(i%4==0 and gold or ember,(1-burst)*.82)
        g.circle('fill',x,y,1.4+i%4*.77)
      end
      duelSkull(g,px,py,math.min(w*.060,h*.066),fall)
    end
    local name=teamNames[owners[side]]..' '..rules.classes[classes[side]].name
    combatTitle(name,cx,h*.612,w*.435,teamTint,1,fonts.stat)
    local scoreY=h*.680
    local scoreW=w*.395
    local scoreH=h*.157
    g.setColor(.075,.028,.047,.93);g.rectangle('fill',cx-scoreW*.5,scoreY,scoreW,scoreH,8,8)
    color(focus and (resolved and gold or teamTint) or teamTint,focus and .94 or .34)
    g.setLineWidth(focus and 2 or 1)
    g.rectangle('line',cx-scoreW*.5,scoreY,scoreW,scoreH,8,8)
    local start=side==1 and 0 or DUEL_SECOND
    local shown=time>=start+DUEL_LAND
    if shown or side==active then
      local size=math.min(w*.081,h*.065,53)
      drawD12(g,cx-scoreW*.24,scoreY+scoreH*.42,rolls[side],
        not shown and time-start or nil,owners[side],size,fonts.stat)
      combatTitle(shown and tostring(rolls[side]) or '···',cx+scoreW*.20,
        scoreY+scoreH*.07,scoreW*.47,losing and ember or ivory,
        math.min(1,scoreH*.60/fontHeight(fonts.finale)),fonts.finale,1,true)
    end
    local status=resolved and (losing and 'FALLEN' or 'VICTOR')
      or shown and 'ROLL LOCKED' or side==active and 'ROLLING' or 'AWAITING ROLL'
    combatTitle(status,cx,scoreY+scoreH*.72,scoreW,losing and ember or focus and gold or ivory,
      math.min(1,scoreH*.255/fontHeight(fonts.cardHint)),fonts.cardHint)
  end
  if resolved and impactTime<.16 then
    color(ember,(.16-impactTime)*1.5);g.rectangle('fill',0,0,w,h)
  end
  if shaking then g.pop() end
  view.button=nil
  if resolved and impactTime>=1.46 then
    local bh=math.max(23,math.min(47,h*.077))
    local box={x=w*.18,y=h-math.max(6,h*.028)-bh,w=w*.64,h=bh}
    luxeButton('CONTINUE',box.x,box.y,box.w,box.h,false)
    view.button=box
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
    local scale=math.min(w*.90/iw,(header-36)/ih)
    g.setColor(1,1,1,1)
    g.draw(logo,(w-iw*scale)*.5,3,0,scale,scale)
  else
    combatTitle('FORTRESS SIEGE',w*.5,3,w-16,palette.gold)
    text('FINAL CONQUEST',8,6+fontHeight(fonts.large),w-16,'center',fonts.small)
  end
  local missionY=header-fontHeight(fonts.cardHint)-11
  text('Lead your army. Destroy the enemy fortress.',8,missionY,w-16,'center',fonts.cardHint)
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
    combatTitle(label,bx+badgeW*.5,fy-fontHeight(fonts.openingSide)*.5,badgeW+8,teamLabels[side],1,fonts.openingSide)
  end
  local y,bh=layout.actionY,layout.actionH
  intro.start=openingButton('Start Game',10,y,w*.53-13,bh,true)
  intro.guide=openingButton('How to Play',w*.53+4,y,w*.47-14,bh,false)
  if introTime<.85 then
    g.setColor(0,0,0,1-smoothstep(introTime/.85))
    g.rectangle('fill',0,0,w,layout.viewportH)
  end
end

-- Practice uses a separate board and seed, with units introduced as needed.
local PRACTICE_SOLDIER,PRACTICE_ARCHER,PRACTICE_FOE=12,4,27
local practiceStats={
  {'health','Health','The first number is Health left. The second is full Health. At zero, the piece is defeated.'},
  {'move','Move','How many hexes the piece can move. This Soldier moves one hex toward the enemy.'},
  {'power','Power','How much Health a successful attack removes from the target.'},
  {'range','Range','How far away the target can be. Range 1 means the target must be next to this piece.'},
  {'shield','Shield','The attacker must roll higher than the target’s Shield to land a hit.'},
}
local practiceSteps={
  inspect={1,'Inspect a Piece','Tap the highlighted Red Soldier to open its stat card.'},
  move={2,'Choose a Destination','Gold hexes show where the Soldier can move. Tap either one.'},
  confirmMove={2,'Confirm the Move','Tap Move Here. In a match, one move or attack ends your turn.'},
  moving={2,'Move Confirmed','Your Soldier has moved forward.'},
  archer={3,'Select Your Archer','Tap the highlighted Red Archer. A bow lets it attack from farther away.'},
  target={3,'Choose a Target','Archers shoot in a straight line. Tap the Blue Soldier with the icy-blue rim.'},
  confirmAttack={3,'Confirm the Attack','Archer Power 6. Target Shield 2. Tap Attack Now to roll.'},
  objective={4,'Your Objective','Tap the marked Blue Fortress. Destroying it wins a match.'},
  complete={4,'Ready for the Siege','Protect your fortress and attack the enemy’s. Each turn, choose one move or attack.'},
}

local function startPractice()
  local board=rules.new(1,1)
  for _,unit in ipairs(board.units) do unit.hp=0 end
  board.units[PRACTICE_SOLDIER].hp=rules.classes.soldier.hp
  local archer=board.units[PRACTICE_ARCHER]
  archer.r,archer.c=6,4
  local foe=board.units[PRACTICE_FOE]
  foe.r,foe.c=4,3
  return {board=board,step='inspect'}
end

local function practiceMarker(cell,attack,chosen,selectedAt)
  local cx,cy=center(cell.r,cell.c)
  if attack then targetMarker(cx,cy,layout.radius,chosen,selectedAt)
  else moveMarker(cx,cy,layout.radius) end
end

local function practiceCallout(unit,label)
  local g=love.graphics
  local cx,cy=center(unit.r,unit.c)
  local radius=layout.radius*1.18
  local side=cx<layout.w*.5 and 1 or -1
  local labelW=math.min(122,layout.w*.39)
  local labelH=fontHeight(fonts.guide)+8
  local x=side==1 and cx+radius+10 or cx-radius-10-labelW
  x=math.max(5,math.min(layout.w-labelW-5,x))
  local y=cy-labelH*.5
  color(palette.gold,.86)
  g.setLineWidth(1.7)
  g.polygon('line',faceHex(cx,cy,radius))
  g.line(cx+side*radius,cy,side==1 and x or x+labelW,cy)
  g.setColor(.06,.072,.104,1)
  g.rectangle('fill',x,y,labelW,labelH,5,5)
  color(palette.gold,.86)
  g.rectangle('line',x,y,labelW,labelH,5,5)
  combatTitle(label,x+labelW*.5,y+4,labelW,palette.text,1,fonts.guide)
end

local function practicePanel(chapter,title,detail,y,h)
  local g=love.graphics
  local w=layout.w
  g.setColor(.063,.078,.105,1)
  g.rectangle('fill',9,y,w-18,h,9,9)
  color(palette.gold,.70);g.setLineWidth(1.2)
  g.rectangle('line',9,y,w-18,h,9,9)
  color(palette.gold)
  g.setFont(fonts.guide)
  local outline={'INSPECT','MOVE','ATTACK','OBJECTIVE'}
  g.printf(('%d / 4   %s'):format(chapter,outline[chapter]),18,y+8,w-36,'left')
  local barW=math.min(16,w*.045)
  for i=1,4 do
    color(palette.gold,i<=chapter and .96 or .26)
    g.rectangle('fill',w-18-(5-i)*(barW+4),y+11,barW,4,2,2)
  end
  combatTitle(title,w*.5,y+25,w-34,palette.gold,1,fonts.medium)
  text(detail,18,y+29+fontHeight(fonts.medium),w-36,'center',fonts.guide)
end

local function drawPractice(practice)
  local g=love.graphics
  local w,h=layout.w,layout.h
  local step,board=practice.step,practice.board
  intro.close,practice.button=nil,nil
  if practice.battle then
    drawBattleOverlay(practice.battle,true)
    intro.close=openingButton('Exit Tutorial',10,h,math.min(100,w*.40),21,false)
    return
  end

  local label
  if step=='stats' then
    local stat=practiceStats[practice.stat]
    g.setColor(.035,.025,.058,.67)
    g.rectangle('fill',0,0,w,h)
    drawCard(board.units[PRACTICE_SOLDIER],stat[1])
    local panelY=layout.topReserve+2
    local panelH=math.min(104,layout.actionY-panelY-5)
    practicePanel(1,('%s  ·  %d / %d'):format(stat[2],practice.stat,#practiceStats),stat[3],panelY,panelH)
    label=practice.stat==#practiceStats and 'Practice Moving' or 'Next Stat'
  else
    local lesson=practiceSteps[step]
    practicePanel(lesson[1],lesson[2],lesson[3],5,layout.topReserve-8)
    if step=='inspect' then
      practiceCallout(board.units[PRACTICE_SOLDIER],'Red Soldier')
    elseif step=='move' then
      for key in pairs(rules.moves(board,PRACTICE_SOLDIER)) do
        local r,c=rules.fromkey(key)
        practiceMarker({r=r,c=c})
      end
    elseif step=='confirmMove' then
      practiceMarker(practice.destination,false,true)
      label='Move Here'
    elseif step=='archer' then
      practiceCallout(board.units[PRACTICE_ARCHER],'Red Archer')
    elseif step=='target' or step=='confirmAttack' then
      practiceMarker(board.units[PRACTICE_FOE],true,step=='confirmAttack',practice.selectedAt)
      if step=='confirmAttack' then label='Attack Now' end
    elseif step=='objective' then
      practiceCallout(board.forts[2],'Blue Fortress')
    elseif step=='complete' then
      label='Start Game'
    end
  end
  local y,bh=layout.actionY,layout.actionH
  intro.close=openingButton('Exit Tutorial',10,y,w*.38-9,bh,false)
  if label then
    practice.button=openingButton(label,w*.38+7,y,w*.62-17,bh,true)
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
  local burst=math.max(0,t-COLLAPSE_TIME)
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
  if t>=COLLAPSE_TIME and burst<2.4 then
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
local ATTACK_NOTICE_TIME, QUICK_NOTICE_TIME, TURN_NOTICE_TIME = 1.32, .56, 1.06
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
    local function showFallen(class,owner,x,y)
      local sprite=unitArt[owner][class]
      if class=='fortress' then fortressArt(x,y,owner,size)
      elseif sprite then drawBadgeSprite(sprite,x,y,layout.scale) end
    end
    if event.defeated then showFallen(event.defenderClass,3-side,dx,dy) end
    if event.attackerDefeated then showFallen(event.attackerClass,side,ax,ay) end
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
    overlay={type='attackNotice',event=event,elapsed=0,quick=(state.battleCount or 0)>1}
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
    local route=event.route
    if route and #route>=2 then
      local unit=previous.units[event.id]
      moving=moveFx.new(event,unit.class)
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
  return sendHostTurn(rules.encode(action,result),tentative.winner)
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
    local confirmW=w*.71
    local gap=8
    local label=isAttack and 'ATTACK NOW' or 'MOVE HERE'
    luxeButton(label,x,y,confirmW,h,isAttack)
    luxeButton('CANCEL',x+confirmW+gap,y,w-confirmW-gap,h,'neutral')
    actionBox={x=x,y=y,w=confirmW,h=h}
    cancelBox={x=x+confirmW+gap,y=y,w=w-confirmW-gap,h=h}
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
local function closePractice()
  intro.help=nil
  if overlay and overlay.type=='opening' and overlay.elapsed then intro=nil end
end

local function startMatch()
  intro=nil
  if horn then horn:play() end
end

local function tapPractice(practice,x,y)
  if inside(intro.close,x,y) then closePractice();return end
  if practice.animation then return end
  local battle=practice.battle
  if battle then
    if inside(battle.button,x,y) then
      battle.button=nil
      if battle.bonusElapsed then
        practice.battle=nil
        practice.step='objective'
      else
        battle.bonusElapsed=0
      end
    end
    return
  end
  local step,board=practice.step,practice.board
  local cell=xyToCell(x,y)
  local clicked=cell and rules.occupied(board,cell.r,cell.c)
  local id=clicked and clicked.ref.id
  if step=='inspect' and id==PRACTICE_SOLDIER then
    practice.step,practice.stat='stats',1
  elseif step=='stats' and inside(practice.button,x,y) then
    if practice.stat<#practiceStats then
      practice.stat=practice.stat+1
    else
      practice.step='move'
    end
  elseif (step=='move' or step=='confirmMove') and cell
      and rules.moves(board,PRACTICE_SOLDIER)[rules.key(cell.r,cell.c)] then
    practice.destination=cell
    practice.step='confirmMove'
  elseif step=='confirmMove' and inside(practice.button,x,y) then
    local to=practice.destination
    local moved,event=rules.apply(board,{type='move',id=PRACTICE_SOLDIER,r=to.r,c=to.c})
    if moved then
      board.turn=1
      practice.step='moving'
      practice.animation=moveFx.new(event,'soldier')
    end
  elseif step=='archer' and id==PRACTICE_ARCHER then
    board.units[PRACTICE_FOE].hp=6
    practice.step='target'
  elseif step=='target' and id==PRACTICE_FOE then
    practice.step='confirmAttack'
    practice.selectedAt=love.timer.getTime()
  elseif step=='confirmAttack' and inside(practice.button,x,y) then
    local foe=board.units[PRACTICE_FOE]
    local attacked,event=rules.apply(board,{type='attack',id=PRACTICE_ARCHER,r=foe.r,c=foe.c})
    if attacked then
      practice.battle={event=event,elapsed=0}
    end
  elseif step=='objective' and clicked and clicked.ref==board.forts[2] then
    practice.step='complete'
  elseif step=='complete' and inside(practice.button,x,y) then
    startMatch()
  end
end

local function onTap(x,y)
  if not state then return end
  if moving then return end
  if intro then
    if intro.help then tapPractice(intro.help,x,y)
    elseif inside(intro.guide,x,y) then intro.help=startPractice()
    elseif inside(intro.start,x,y) then startMatch()
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
    if selected~=t.ref.id then selectionAge=0;playCue('select') end
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
    notice='Gold: move. Icy blue: attack.'
    return
  end
  if selected and mayAct() then
    local k=rules.key(cell.r,cell.c)
    local kind=(targets.attacks or {})[k] and 'attack' or (targets.moves or {})[k] and 'move' or nil
    if kind then
      intended={type=kind,r=cell.r,c=cell.c,crossed=kind=='move' and rules.jumpOver(state,selected,cell.r,cell.c) or {}}
      if kind=='move' then intended.route=rules.route(state,selected,cell.r,cell.c)
      else
        intended.selectedAt=love.timer.getTime()
        intended.deathMatch=rules.isDeathMatch(rules.piece(state,selected),t.ref)
      end
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
    local okArena,backdrop=pcall(love.graphics.newImage,'art/battle-arena.png')
    if okArena then arena=backdrop end
    local ok,img=pcall(love.graphics.newImage,'art/board.png')
    if ok and img then artBoard=img; if img.setFilter then img:setFilter('linear','linear') end end
    for owner=1,2 do
      for name,_ in pairs(rules.classes) do
        if name~='fortress' then
          local ok2,sp=pcall(love.graphics.newImage,('art/%s-%d.png'):format(name,owner))
          if ok2 and sp then
            unitArt[owner][name]=sp
            if sp.setFilter then sp:setFilter('linear','linear') end
            if name=='archer' and love.graphics.newQuad then
              local iw,ih=sp:getDimensions()
              -- Frame the broadhead with a short section of shaft inside the hex.
              archerCloseup[sp]=love.graphics.newQuad(iw*76/240,ih*37/240,iw*100/240,ih*100/240,iw,ih)
            end
          end
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
    for _,name in ipairs({'siege-horn','select','land','archer','wizard','ogre','barbarian',
      'assassin','soldier','fortress','blocked','critical','breach','collapse',
      'move-soldier','move-archer','move-assassin','move-wizard','move-barbarian','move-ogre'}) do
      local loaded,source=pcall(love.audio.newSource,'audio/'..name..'.wav','static')
      if loaded then cues[name]=mixer:register(source,'effects') end
    end
    horn=cues['siege-horn']
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
  selectionAge=0
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
  selectionAge=math.min(.16,selectionAge+dt)
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
    local practice=intro.help
    local animation=practice and practice.animation
    if animation then
      if moveFx.update(animation,dt,playCue) then
        practice.animation=nil
        practice.board.units[PRACTICE_ARCHER].hp=3
        practice.step='archer'
      end
    end
    local battle=practice and practice.battle
    if battle then
      local before=battle.elapsed
      battle.elapsed=before+dt
      playBattleImpact(battle,before)
      if battle.bonusElapsed then battle.bonusElapsed=battle.bonusElapsed+dt end
    end
    return
  end
  local finishedMove=false
  if moving then
    if moveFx.update(moving,dt,playCue) then
      moving=nil
      local ev=queuedEvent;queuedEvent=nil
      if ev then showEvent(ev);finishedMove=true end
    end
  end
  if overlay and not finishedMove then
    local before=overlay.elapsed
    if overlay.elapsed then overlay.elapsed=overlay.elapsed+dt end
    if overlay.type=='opening' then
      if overlay.elapsed and overlay.elapsed>=#overlay.opening.rounds*OPENING_BEAT+.50 then
        showTurn(true)
        return
      end
    elseif overlay.type=='siege' then
      if overlay.elapsed>=#overlay.siege.volleys*SIEGE_BEAT then overlay=nil end
    elseif overlay.type=='attackNotice' then
      local wait=(overlay.quick or overlay.event.deathMatch) and QUICK_NOTICE_TIME or ATTACK_NOTICE_TIME
      if overlay.elapsed>=wait then overlay.type,overlay.elapsed='battle',0 end
    elseif overlay.type=='turnNotice' then
      if overlay.elapsed>=TURN_NOTICE_TIME then overlay=nil end
    elseif overlay.type=='battle' then
      if overlay.event.deathMatch then playDuelCues(overlay,before)
      else playBattleImpact(overlay,before) end
      if overlay.bonusElapsed then
        local beforeBonus=overlay.bonusElapsed
        overlay.bonusElapsed=beforeBonus+dt
        if beforeBonus<BONUS_TIME and overlay.bonusElapsed>=BONUS_TIME
          and mode~='online' and playerControlsReward(overlay.event.actor) then
          sessionSave(REWARD_SHOWN)
        end
      elseif overlay.event.heal and not playerControlsReward(overlay.event.actor)
          and overlay.elapsed>=battleLead(overlay)+RESULT+1.25 then
        overlay.bonusElapsed=0
      end
    end
  elseif state and state.winner~=nil then
    local before=finishElapsed
    finishElapsed=math.min(FINALE_LENGTH,finishElapsed+dt)
    if state.winner~=0 and before<COLLAPSE_TIME and finishElapsed>=COLLAPSE_TIME then
      playCue('collapse')
    end
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
  local practice=intro and intro.help
  drawBoard(practice and practice.board,practice and practice.animation)
  local waitingForRoll=mode=='online' and not onlineReady and not blocked
  if not intro and not waitingForRoll and not (overlay and overlay.type=='opening') then
    drawActionBar()
    drawCard()
  end
  if blocked then
    text('Online sync error: '..blocked,8,layout.h*.43,layout.w-16,'center',fonts.medium)
  end
  if practice and not blocked then drawPractice(practice)
  elseif intro and not blocked then drawIntroduction()
  elseif overlay and overlay.type=='battle' then
    if overlay.event.deathMatch then drawDeathMatch(overlay) else drawBattleOverlay(overlay) end
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
      closePractice()
      return
    end
    selected,inspected,targets,intended=nil,nil,{},nil
    actionBox,cancelBox,cardBox=nil,nil,nil
    turnSendFailed=false
  end
end
