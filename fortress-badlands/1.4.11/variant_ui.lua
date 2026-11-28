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
  top={.655,.566,.443}, face={.368,.304,.224}, rear={.367,.306,.230},
  edge={.84,.76,.61}, shadow={.085,.069,.055},
  rubble={.29,.235,.166}, rubbleTop={.62,.524,.395},
}
function ui.wall(g,x,y,r,hp,maximum,alpha)
  alpha=alpha or 1
  local l,rr=x-r*.815,x+r*.815
  local bevel=r*.079
  local rear,rearJoin=y-r*.235,y-r*.075
  local frontJoin,foot=y+r*.068,y+r*.198
  local function tint(color,strength)
    paint(g,limestone[color],(strength or 1)*alpha)
  end
  local function chip(cx,cy,size)
    tint('shadow',.78);g.circle('fill',cx+1,cy+1,size)
    tint('rubble');g.polygon('fill',cx-size,cy,cx-size*.3,cy-size,cx+size,cy-size*.2,cx+size*.36,cy+size)
    tint('rubbleTop');g.line(cx-size,cy,cx-size*.3,cy-size,cx+size,cy-size*.2)
  end
  if hp<=0 then
    g.setLineWidth(1)
    for i=1,4 do
      chip(x+r*((i*7)%13-6)*.095,y+r*((i*5)%9-4)*.045,r*(.045+i%3*.022))
    end
    return
  end
  -- Cast shadow falls away from the darker far face onto the board.
  for i=1,8 do
    local spread=i/8
    local tail=rear-r*.18*spread
    tint('shadow',.68*(1-spread*.84)*.26)
    g.polygon('fill',l+bevel*(.61+.31*spread),tail,rr-bevel*(.58+.15*spread),tail,rr+r*.012,rearJoin,l,rearJoin)
  end
  tint('shadow',.41)
  g.polygon('fill',l,rearJoin,rr,rearJoin,rr,foot+r*.042,rr-bevel*.6,foot+r*.084,
    l+bevel*.6,foot+r*.084,l,foot+r*.042)
  tint('rear')
  g.polygon('fill',l,rearJoin,l+bevel,rear,rr-bevel,rear,rr,rearJoin)
  tint('top')
  g.polygon('fill',l,rearJoin,rr,rearJoin,rr,frontJoin,l,frontJoin)
  tint('face')
  g.polygon('fill',l,frontJoin,rr,frontJoin,rr,foot-bevel*.31,rr-bevel,foot,l+bevel,foot,l,foot-bevel*.31)
  g.setLineWidth(math.max(.86,r*.026))
  tint('shadow',.82);g.line(l+bevel,rear+.18,rr-bevel,rear+.18)
  tint('edge',.71);g.line(l+1,rearJoin,rr-1,rearJoin)
  paint(g,{.89,.80,.65},.60*alpha);g.line(l+1,frontJoin,rr-1,frontJoin)
  tint('shadow',.70);g.line(l+bevel,foot-.8,rr-bevel,foot-.8)
  local edges={rear,rearJoin,frontJoin,foot}
  for i=1,26 do
    local sx=l+bevel+(rr-l-2*bevel)*((i*43+math.floor(x)*11)%91)/91
    local band=i%3+1
    local sy=edges[band]+(edges[band+1]-edges[band])*(.19+(i*13%17)/32)
    local light=i%4==0
    if light then paint(g,{.88,.78,.60},.25*alpha) else tint('shadow',.27) end
    g.line(sx,sy,math.min(rr-.8,sx+r*(.025+i%3*.012)),sy-r*.006)
  end
  if hp<maximum then
    local health=hp/maximum
    tint('shadow',.92);g.setLineWidth(math.max(1.1,r*.05))
    g.line(x+r*.17,rear,x+r*.09,rearJoin,x+r*.15,frontJoin,x+r*.07,foot)
    if health<=.60 then
      g.line(x-r*.37,rear,x-r*.45,rearJoin,x-r*.31,frontJoin,x-r*.39,foot)
      g.line(x+r*.09,rearJoin,x+r*.31,rearJoin+r*.044,x+r*.43,rear)
    end
    if health<=.25 then
      g.line(x+r*.57,rear,x+r*.48,frontJoin,x+r*.58,foot)
      g.polygon('fill',rr-r*.19,foot,rr-r*.12,frontJoin,rr,frontJoin,rr,foot-r*.06)
      g.setLineWidth(1)
      chip(rr-r*.16,foot+r*.10,r*.075)
      chip(l+r*.24,foot+r*.075,r*.060)
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

function ui.boardDialogTop(layout,height)
  local middle=layout.y+layout.boardH*.5
  return math.max(5,math.min(layout.h-height-5,middle-height*.5))
end

function ui.matchBrief(g,layout,fonts,options,frame)
  local w,h=layout.w,layout.h
  local panelW=math.min(w*.92,470)
  local left=(w-panelW)*.5
  local iconX,textX,textW=left+31,left+57,panelW-70
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

  local detailOffset=8+fontHeight(fonts.small)+3
  local opens=options.destroyCrates and 'Step on one to open it, or attack to destroy it.' or 'Step on a crate to open it.'
  local contents='Each crate holds a potion or a bomb.'
  local endGaps=options.crates and options.crateCount==9 and not options.legacyCrates
  local crossing=endGaps and 'End gaps are open.' or 'Break a section to cross.'
  local ranged=options.overWall and ' Ranged fire can pass over.' or ' Ranged fire is blocked.'
  local wallDetail=crossing..ranged
  local itemH=math.max(33,fontHeight(bodyFont)+11)
  local crateH=options.crates and (detailOffset+bodyHeight(opens)+8+bodyHeight(contents)+6+2*itemH+8) or 0
  local wallH=options.wall and (detailOffset+bodyHeight(wallDetail)+9) or 0
  local gap=options.crates and options.wall and 6 or 0
  local panelH=110+crateH+wallH+gap
  local scale=math.min(1,(h-10)/panelH)
  local top=ui.boardDialogTop(layout,panelH*scale)
  local offsetX,offsetY=(1-scale)*w*.5,(1-scale)*top
  local bodyTint={.80,.79,.78}
  local function text(label,x,y,width,font,tint,align)
    g.setFont(font);paint(g,tint);g.printf(label,x,y,width,align or 'left')
  end
  g.setColor(.020,.019,.027,.79);g.rectangle('fill',0,0,w,layout.viewportH)
  if scale<1 then
    g.push()
    g.translate(offsetX,offsetY)
    g.scale(scale,scale)
  end
  g.setColor(.067,.079,.104,1);g.rectangle('fill',left,top,panelW,panelH,12,12)
  frame(left,top,panelW,panelH,1,12)
  text('This Match Includes',left+8,top+14,panelW-16,fonts.medium,gold,'center')
  local ry=top+49
  local function icon(kind,cy)
    local radius=14.5
    g.setColor(.126,.133,.162,1)
    g.rectangle('fill',iconX-radius,cy-radius,2*radius,2*radius,6,6)
    g.setColor(.49,.42,.32,.37);g.setLineWidth(1)
    g.rectangle('line',iconX-radius+.5,cy-radius+.5,2*radius-1,2*radius-1,6,6)
    if kind=='bomb' then
      -- Soft amber falloff separates the dark silhouette from the icon well.
      for ring=12,1,-1 do
        local f=ring/12
        g.setColor(.99,.70,.31,.047+.123*(1-f))
        g.circle('fill',iconX,cy+1.1,14.1*f)
      end
      ui.bomb(g,iconX-.5,cy+.8,14.3)
    elseif kind=='potion' then ui.potion(g,iconX,cy-1,23.5)
    elseif kind=='crate' then ui.crate(g,iconX,cy,13.5)
    else ui.wall(g,iconX,cy,14.1,1,1) end
  end
  local function section(title,detail,height)
    g.setColor(.096,.108,.14,1);g.rectangle('fill',left+9,ry,panelW-18,height,7,7)
    text(title,textX,ry+8,textW,fonts.small,ivory)
    text(detail,textX,ry+detailOffset,textW,bodyFont,bodyTint)
  end
  if options.crates then
    local count=options.crateCount
    section(count..(count==1 and ' Mystery Crate' or ' Mystery Crates'),opens,crateH)
    icon('crate',ry+23)
    local y=ry+detailOffset+bodyHeight(opens)+8
    text(contents,textX,y,textW,bodyFont,bodyTint)
    y=y+bodyHeight(contents)+6
    local centerY=y+itemH*.5
    icon('potion',centerY)
    text('Potion  +12 Health',textX,centerY-fontHeight(bodyFont)*.5,textW,bodyFont,ivory)
    centerY=centerY+itemH
    icon('bomb',centerY)
    text('Bomb  −12 Health',textX,centerY-fontHeight(bodyFont)*.5,textW,bodyFont,ivory)
    ry=ry+crateH+gap
  end
  if options.wall then
    section('Border Wall',wallDetail,wallH)
    icon('wall',ry+23)
    ry=ry+wallH
  end
  local button={x=w*.5-panelW*.25,y=ry+9,w=panelW*.50,h=39}
  g.setColor(.29,.19,.094,1);g.rectangle('fill',button.x,button.y,button.w,button.h,7,7)
  frame(button.x,button.y,button.w,button.h,1,7)
  text('Continue',button.x,button.y+(button.h-fontHeight(fonts.small))*.5,button.w,fonts.small,ivory,'center')
  if scale<1 then
    g.pop()
    button.x,button.y=offsetX+button.x*scale,offsetY+button.y*scale
    button.w,button.h=button.w*scale,button.h*scale
  end
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
