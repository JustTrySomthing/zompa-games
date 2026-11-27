local ui={}

local ivory={.95,.90,.82}
local muted={.67,.66,.66}
local gold={.84,.69,.43}

local function paint(g,tint,alpha)
  g.setColor(tint[1],tint[2],tint[3],alpha or 1)
end

function ui.draw(g,layout,fonts,options,editable,frame,waitingForInviter)
  local w=math.min(layout.w-16,420)
  local h=math.min(487,layout.h-16)
  local x,y=(layout.w-w)*.5,(layout.h-h)*.5
  local sx=(w-24)/368
  local sy=(h-20)/467
  local hit={}
  local function box(rx,ry,rw,rh)
    return {x=x+12+rx*sx,y=y+10+ry*sy,w=rw*sx,h=rh*sy}
  end
  local function rect(b,fill,tint)
    paint(g,tint);g.rectangle(fill,b.x,b.y,b.w,b.h,6,6)
  end
  local function text(label,rx,ry,rw,font,tint,align)
    local b=box(rx,ry,rw,0)
    g.setFont(font);paint(g,tint)
    g.printf(label,b.x,b.y,b.w,align or 'left')
  end
  local function toggle(label,key,ry)
    text(label,12,ry+7,255,fonts.medium,ivory)
    local b=box(296,ry,60,34)
    rect(b,'fill',options[key] and {.15,.39,.28} or {.18,.20,.25})
    frame(b.x,b.y,b.w,b.h,editable and .82 or .38,8)
    paint(g,options[key] and {.86,1,.89} or muted)
    g.circle('fill',b.x+b.w*(options[key] and .75 or .25),b.y+b.h*.5,math.min(b.h,b.w)*.29)
    if editable then hit[key]=b end
  end
  local function step(label,key,ry,low,high,enabled)
    text(label,12,ry+7,195,fonts.small,enabled and ivory or muted)
    local value=options[key]
    text(tostring(value),244,ry+7,68,fonts.stat,enabled and gold or muted,'center')
    for _,direction in ipairs({-1,1}) do
      local rx=direction==-1 and 203 or 313
      local b=box(rx,ry,43,35)
      local allowed=enabled and editable and value+direction>=low and value+direction<=high
      rect(b,'fill',allowed and {.25,.18,.11} or {.13,.14,.18})
      frame(b.x,b.y,b.w,b.h,allowed and .85 or .30,6)
      paint(g,allowed and gold or muted)
      g.setLineWidth(1.6)
      local cx,cy=b.x+b.w/2,b.y+b.h/2
      g.line(cx-4,cy+direction*2,cx,cy-direction*2,cx+4,cy+direction*2)
      if allowed then hit[key..direction]=b end
    end
  end
  local function checkbox(label,key,ry,enabled)
    local b=box(12,ry,27,26)
    rect(b,'fill',enabled and {.17,.26,.21} or {.13,.14,.18})
    frame(b.x,b.y,b.w,b.h,enabled and .82 or .30,4)
    if options[key] then
      paint(g,enabled and gold or muted);g.setLineWidth(2)
      g.line(b.x+b.w*.22,b.y+b.h*.53,b.x+b.w*.42,b.y+b.h*.73,b.x+b.w*.79,b.y+b.h*.24)
    end
    text(label,47,ry+2,311,fonts.small,enabled and ivory or muted)
    if editable and enabled then hit[key]=box(12,ry-5,344,36) end
  end
  g.setColor(.025,.02,.034,.94)
  g.rectangle('fill',0,0,layout.w,layout.viewportH)
  rect({x=x,y=y,w=w,h=h},'fill',{.06,.075,.106})
  frame(x,y,w,h,1,10)
  text('Advanced Settings',6,5,356,fonts.medium,gold,'center')
  local notice=editable and 'These settings lock when play starts.'
    or waitingForInviter and 'The inviter sets the rules before play.'
    or 'These settings are locked during gameplay.'
  text(notice,6,40,356,fonts.cardHint,editable and muted or gold,'center')
  rect(box(0,68,368,133),'fill',{.094,.105,.137})
  toggle('Mystery Crates','crates',76)
  step('Crate Count','crateCount',113,1,9,options.crates)
  checkbox('Allow attacks to destroy crates','destroyCrates',158,options.crates)
  rect(box(0,210,368,188),'fill',{.094,.105,.137})
  toggle('Border Wall','wall',218)
  text('Break a section to open a path.',12,255,344,fonts.cardHint,muted)
  step('Section Health','wallHealth',276,1,50,options.wall)
  step('Section Shield','wallShield',316,0,11,options.wall)
  checkbox('Allow ranged fire over the wall','overWall',359,options.wall)
  local done=box(105,414,158,42)
  rect(done,'fill',{.30,.20,.105})
  frame(done.x,done.y,done.w,done.h,1,8)
  text('Done',105,423,158,fonts.small,ivory,'center')
  hit.done=done
  return hit
end

function ui.tap(hits,x,y,options)
  for key,box in pairs(hits or {}) do
    if x>=box.x and y>=box.y and x<=box.x+box.w and y<=box.y+box.h then
      if key=='done' then return true end
      local field,delta=key:match('^(%a+)(%-?1)$')
      if delta then options[field]=options[field]+tonumber(delta)
      else options[key]=not options[key] end
      return false
    end
  end
  return false
end

local limestone={
  top={.62,.524,.395}, face={.29,.235,.166},
  edge={.81,.73,.59}, shadow={.15,.12,.10},
}
function ui.wall(g,x,y,r,hp,maximum,alpha)
  alpha=alpha or 1
  local span,depth=r*.815,r*.215
  local l,t,rr,b=x-span,y-depth,x+span,y+depth
  local bevel=math.max(1.25,r*.105)
  local function tint(color,strength)
    paint(g,limestone[color],(strength or 1)*alpha)
  end
  local function chip(cx,cy,size)
    tint('shadow',.78);g.circle('fill',cx+1,cy+1,size)
    tint('face');g.polygon('fill',cx-size,cy,cx-size*.3,cy-size,cx+size,cy-size*.2,cx+size*.36,cy+size)
    tint('top');g.line(cx-size,cy,cx-size*.3,cy-size,cx+size,cy-size*.2)
  end
  if hp<=0 then
    g.setLineWidth(1)
    for i=1,4 do
      chip(x+r*((i*7)%13-6)*.095,y+r*((i*5)%9-4)*.045,r*(.045+i%3*.022))
    end
    return
  end
  tint('shadow',.7);g.rectangle('fill',l-1,t+2,span*2+2,depth*2+2,2,2)
  tint('top');g.polygon('fill',l+bevel,t,rr-bevel,t,rr,t+bevel,rr,b-bevel,rr-bevel,b,l+bevel,b,l,b-bevel,l,t+bevel)
  tint('face');g.polygon('fill',l,y,rr,y,rr,b-bevel,rr-bevel,b,l+bevel,b,l,b-bevel)
  tint('edge',.84);g.setLineWidth(1)
  g.line(l+1,t+bevel,l+bevel,t+.5,rr-bevel,t+.5,rr-1,t+bevel)
  tint('edge',.20);g.line(l+bevel*1.5,y-.6,rr-bevel*1.7,y-.6)
  for i=1,12 do
    local speck=l+span*2*((i*47+math.floor(x)*7)%89)/89
    local dotY=t+2+(depth-1)*((i*29)%23)/23
    tint(i%3==0 and 'edge' or 'shadow',i%3==0 and .36 or .30)
    g.line(speck,dotY,math.min(rr-1,speck+1+i%3),dotY)
  end
  tint('edge',.52);g.line(l+bevel+1,b-1,rr-bevel-1,b-1)
  if hp<maximum then
    tint('shadow');g.setLineWidth(math.max(1,r*.062))
    g.line(x+.18*r,t,x+.08*r,y-.06*r,x+.16*r,y+.03*r,x+.07*r,b)
    if hp/maximum<=.60 then
      g.line(x-.38*r,t,x-.46*r,y-.05*r,x-.33*r,y+.04*r,x-.40*r,b)
      g.line(x+.10*r,y-.06*r,x+.31*r,y-.12*r,x+.45*r,t)
    end
    if hp/maximum<=.25 then
      g.line(x+.51*r,t,x+.42*r,y,x+.56*r,b)
      g.polygon('fill',rr-.29*r,b,rr-.20*r,y+.03*r,rr,y-.03*r,rr,b)
      chip(rr-.18*r,b+.11*r,r*.083)
      chip(l+.24*r,b+.085*r,r*.066)
    end
  end
end

ui.trapDuration=3.75
function ui.trapCardOpacity(elapsed)
  local function ease(t)
    t=math.max(0,math.min(1,t))
    return t*t*(3-2*t)
  end
  return ease((elapsed-.38)/.26)*ease((ui.trapDuration-elapsed)/.50)
end

function ui.trapBlast(g,x,y,r,elapsed)
  local t=math.min(1,elapsed/.96)
  if t>=1 then return end
  local fade=1-t
  g.setColor(1,.28,.08,.42*fade^2)
  g.circle('fill',x,y,r*(1+1.85*t))
  g.setColor(1,.83,.43,.84*fade^3)
  g.circle('fill',x,y,r*(.43+.71*t))
  g.setColor(1,.60,.25,.92*fade);g.setLineWidth(math.max(2,r*.14))
  g.circle('line',x,y,r*(.55+2.65*t))
  for i=1,22 do
    local angle=i*2.39996
    local dx,dy=math.cos(angle),math.sin(angle)
    local reach=r*(.47+t*(1.8+i%5*.32))
    local px,py=x+dx*reach,y+dy*reach-r*t*.46
    g.setColor(1,.43+i%4*.14,.19,.97*fade)
    g.line(px,py,px+dx*r*(.24+i%3*.13),py+dy*r*(.24+i%3*.13))
  end
end

function ui.potion(g,x,y,r,alpha)
  local unit=r*.52
  local function tint(red,green,blue,opacity)
    g.setColor(red,green,blue,(opacity or 1)*(alpha or 1))
  end
  tint(.071,.028,.041,.62);g.circle('fill',x+unit*.09,y+unit*.23,unit)
  tint(.20,.075,.101)
  g.rectangle('fill',x-unit*.81,y-unit*.39,unit*1.62,unit*1.43,unit*.45,unit*.45)
  tint(.77,.13,.22);g.rectangle('fill',x-unit*.66,y-unit*.26,unit*1.32,unit*1.15,unit*.37,unit*.37)
  tint(.94,.27,.31);g.circle('fill',x-unit*.07,y+unit*.22,unit*.49)
  tint(.97,.69,.57);g.setLineWidth(math.max(1,unit*.12))
  g.rectangle('line',x-unit*.65,y-unit*.26,unit*1.30,unit*1.14,unit*.35,unit*.35)
  tint(.89,.65,.46);g.rectangle('fill',x-unit*.39,y-unit*.71,unit*.78,unit*.40,unit*.10,unit*.10)
  tint(1,.92,.76)
  g.rectangle('fill',x-unit*.36,y+unit*.19,unit*.72,unit*.17)
  g.rectangle('fill',x-unit*.085,y-unit*.075,unit*.17,unit*.70)
end

local crateArt
function ui.loadArt(g)
  local ok,image=pcall(g.newImage,'art/mystery-crate.png')
  if ok and image and g.draw then
    if image.setFilter then image:setFilter('linear','linear') end
    crateArt=image
  end
end

function ui.crate(g,x,y,r,alpha)
  local o=alpha or 1
  local radius=r*.82
  if crateArt and g.draw then
    local width,height=crateArt:getDimensions()
    local scale=2*radius/(height-4) -- The packaged sprite has two pixels of transparent padding at each tip.
    g.setColor(1,1,1,o)
    g.draw(crateArt,x,y,0,scale,scale,width/2,height/2)
    return
  end
  local w=radius*math.sqrt(3)*.5
  local hex={x,y-radius,x+w,y-radius*.5,x+w,y+radius*.5,
    x,y+radius,x-w,y+radius*.5,x-w,y-radius*.5}
  g.setColor(.43,.26,.14,o);g.polygon('fill',hex)
  g.setColor(.72,.53,.33,o);g.setLineWidth(math.max(1,r*.09))
  g.polygon('line',hex)
  g.setColor(1,.89,.64,o);g.setLineWidth(math.max(1.5,r*.11))
  g.line(x-r*.18,y-r*.20,x-r*.10,y-r*.29,x+r*.11,y-r*.29,x+r*.20,y-r*.18,
    x+r*.16,y-r*.06,x,y+r*.04,x,y+r*.14)
  g.circle('fill',x,y+r*.29,math.max(1,r*.055))
end

function ui.bomb(g,x,y,r,alpha)
  local o=alpha or 1
  g.setColor(.09,.085,.11,o);g.circle('fill',x-r*.02,y+r*.12,r*.55)
  g.setColor(.20,.19,.22,o);g.circle('fill',x-r*.09,y+r*.03,r*.43)
  g.setColor(.44,.42,.46,.7*o);g.circle('fill',x-r*.22,y-r*.09,r*.13)
  g.setColor(.33,.29,.25,o);g.rectangle('fill',x+r*.08,y-r*.49,r*.30,r*.22,2,2)
  g.setColor(.83,.64,.35,o);g.setLineWidth(math.max(1,r*.13))
  g.line(x+r*.22,y-r*.46,x+r*.32,y-r*.68,x+r*.51,y-r*.69)
  g.setColor(1,.56,.15,.48*o);g.circle('fill',x+r*.54,y-r*.70,r*.22)
  g.setColor(1,.84,.40,o);g.circle('fill',x+r*.54,y-r*.70,r*.11)
end

function ui.scorch(g,x,y,r)
  local opacity=.70
  g.setColor(.12,.078,.047,.23*opacity);g.circle('fill',x,y,r*.71)
  g.setColor(.10,.067,.048,.41*opacity);g.circle('fill',x,y,r*.52)
  g.setColor(.078,.052,.041,.55*opacity);g.circle('fill',x,y,r*.32)
  for i=1,7 do
    local angle=i*2.39996
    local reach=r*(.38+i%3*.09)
    g.circle('fill',x+math.cos(angle)*reach,y+math.sin(angle)*reach,r*.055)
  end
end

function ui.matchBrief(g,layout,fonts,options,frame)
  local w,h=layout.w,layout.h
  local panelW=math.min(w*.92,470)
  local left=(w-panelW)*.5
  local iconX,textX,textW=left+30,left+53,panelW-66
  local bodyFont=fonts.stat
  local function fontHeight(font)
    return font.getHeight and font:getHeight() or font.size
  end
  local function bodyHeight(label)
    if bodyFont.getWrap then
      local _,lines=bodyFont:getWrap(label,textW)
      return #lines*fontHeight(bodyFont)*bodyFont:getLineHeight()
    end
    return math.ceil(#label*fontHeight(bodyFont)*.45/textW)*fontHeight(bodyFont)
  end

  local detailOffset=8+fontHeight(fonts.small)+2
  local opens=options.destroyCrates and 'Step on one to open it, or attack to destroy it.' or 'Step on a crate to open it.'
  local contents='Each crate holds a potion or a bomb.'
  local endGaps=options.crates and options.crateCount==9 and not options.legacyCrates
  local crossing=endGaps and 'End gaps are open.' or 'Break a section to cross.'
  local ranged=options.overWall and ' Ranged fire can pass over.' or ' Ranged fire is blocked.'
  local wallDetail=crossing..ranged
  local itemH=math.max(26,fontHeight(bodyFont)+8)
  local crateH=options.crates and (detailOffset+bodyHeight(opens)+8+bodyHeight(contents)+4+2*itemH+8) or 0
  local wallH=options.wall and (detailOffset+bodyHeight(wallDetail)+9) or 0
  local gap=options.crates and options.wall and 6 or 0
  local panelH=105+crateH+wallH+gap
  local top=math.max(5,(h-panelH)*.48)
  local bodyTint={.80,.79,.78}
  local function text(label,x,y,width,font,tint,align)
    g.setFont(font);paint(g,tint);g.printf(label,x,y,width,align or 'left')
  end
  g.setColor(.020,.019,.027,.79);g.rectangle('fill',0,0,w,layout.viewportH)
  g.setColor(.067,.079,.104,1);g.rectangle('fill',left,top,panelW,panelH,12,12)
  frame(left,top,panelW,panelH,1,12)
  text('This Match Includes',left+8,top+14,panelW-16,fonts.medium,gold,'center')
  local ry=top+49
  local function section(title,detail,height)
    g.setColor(.096,.108,.14,1);g.rectangle('fill',left+9,ry,panelW-18,height,7,7)
    text(title,textX,ry+8,textW,fonts.small,ivory)
    text(detail,textX,ry+detailOffset,textW,bodyFont,bodyTint)
  end
  if options.crates then
    local count=options.crateCount
    section(count..(count==1 and ' Mystery Crate' or ' Mystery Crates'),opens,crateH)
    ui.crate(g,iconX,ry+detailOffset+1,17)
    local y=ry+detailOffset+bodyHeight(opens)+8
    text(contents,textX,y,textW,bodyFont,bodyTint)
    y=y+bodyHeight(contents)+4
    local centerY=y+itemH*.5
    ui.potion(g,iconX,centerY-2,18)
    text('Potion  +12 Health',textX,centerY-fontHeight(bodyFont)*.5,textW,bodyFont,ivory)
    centerY=centerY+itemH
    g.setColor(.43,.38,.30,.72);g.circle('fill',iconX,centerY,12)
    ui.bomb(g,iconX,centerY,17)
    text('Bomb  −12 Health',textX,centerY-fontHeight(bodyFont)*.5,textW,bodyFont,ivory)
    ry=ry+crateH+gap
  end
  if options.wall then
    section('Border Wall',wallDetail,wallH)
    ui.wall(g,iconX,ry+detailOffset+1,17,1,1)
    ry=ry+wallH
  end
  local button={x=w*.5-panelW*.25,y=ry+9,w=panelW*.50,h=35}
  g.setColor(.29,.19,.094,1);g.rectangle('fill',button.x,button.y,button.w,button.h,7,7)
  frame(button.x,button.y,button.w,button.h,1,7)
  text('Continue',button.x,button.y+7,button.w,fonts.small,ivory,'center')
  return button
end

function ui.potionEffect(g,x,y,r,elapsed,collected)
  local t=math.min(1,elapsed/.95)
  if t>=1 then return end
  local opacity=1-t
  if not collected then
    g.setColor(1,.35,.53,.36*opacity^2)
    g.circle('fill',x,y,r*(.70+1.8*t))
    g.setColor(1,.79,.84,.77*opacity^3)
    g.circle('fill',x,y,r*(.34+.55*t))
  end
  for i=1,collected and 13 or 18 do
    local angle=i*2.39996
    local dx,dy=math.cos(angle),math.sin(angle)
    local reach=r*(.28+t*(.75+i%4*.33))
    local px,py=x+dx*reach,y+dy*reach-r*t*(collected and 1.4 or .38)
    local size=math.max(1,r*(collected and .13 or .23)*(1-t*.53))
    if collected then
      g.setColor(.55,1,.75,opacity)
      g.circle('fill',px,py,size*.76)
    else
      g.setColor(i%3==0 and 1 or .94,i%3==0 and .80 or .29,.43,opacity)
      g.polygon('fill',px+dx*size,py+dy*size,
        px-dy*size*.55,py+dx*size*.55,px-dx*size*.52,py-dy*size*.52)
    end
  end
  g.setColor(collected and .32 or 1,collected and .91 or .25,collected and .62 or .43,.63*opacity)
  g.setLineWidth(2)
  g.circle('line',x,y,r*(.52+t*1.35))
end

function ui.explosion(g,x,y,r,elapsed)
  local t=math.min(1,elapsed/.9)
  if t>=1 then return end
  g.setColor(1,.51,.15,(1-t)^2*.85)
  g.circle('fill',x,y,r*(.25+1.4*t))
  g.setColor(1,.72,.35,(1-t)*.80);g.setLineWidth(2)
  g.circle('line',x,y,r*(.35+2.2*t))
  for i=1,16 do
    local angle=i*2.39996
    local reach=r*(.4+t*(1.5+i%4*.32))
    local dx,dy=math.cos(angle),math.sin(angle)
    local px,py=x+dx*reach,y+dy*reach-r*t*.36
    g.setColor(1,.46+i%3*.17,.18,(1-t)*.9)
    g.line(px,py,px+dx*r*.32,py+dy*r*.32)
  end
end

return ui
