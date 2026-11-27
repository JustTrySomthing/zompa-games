local ui={}

local ivory={.95,.90,.82}
local muted={.67,.66,.66}
local gold={.84,.69,.43}

local function paint(g,tint,alpha)
  g.setColor(tint[1],tint[2],tint[3],alpha or 1)
end

function ui.draw(g,layout,fonts,options,editable,frame)
  local w=math.min(layout.w-16,420)
  local h=math.min(452,layout.h-16)
  local x,y=(layout.w-w)*.5,(layout.h-h)*.5
  local sx=(w-24)/368
  local sy=(h-20)/432
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
  g.setColor(.025,.02,.034,.94)
  g.rectangle('fill',0,0,layout.w,layout.viewportH)
  rect({x=x,y=y,w=w,h=h},'fill',{.06,.075,.106})
  frame(x,y,w,h,1,10)
  text('Advanced Settings',6,5,356,fonts.medium,gold,'center')
  text(editable and 'Optional rules for this match' or 'Rules are set when the match starts',
    6,40,356,fonts.cardHint,muted,'center')
  rect(box(0,68,368,109),'fill',{.094,.105,.137})
  toggle('Booby Traps','traps',76)
  text('Hidden across the three middle rows.',12,113,344,fonts.cardHint,muted)
  step('Hidden Traps','trapCount',135,1,9,options.traps)
  rect(box(0,186,368,188),'fill',{.094,.105,.137})
  toggle('Border Wall','wall',194)
  text('Break a section to open a path.',12,231,344,fonts.cardHint,muted)
  step('Section Health','wallHealth',252,1,50,options.wall)
  step('Section Shield','wallShield',292,0,11,options.wall)
  local b=box(12,335,27,26)
  rect(b,'fill',options.wall and {.17,.26,.21} or {.13,.14,.18})
  frame(b.x,b.y,b.w,b.h,options.wall and .82 or .30,4)
  if options.overWall then
    paint(g,options.wall and gold or muted);g.setLineWidth(2)
    g.line(b.x+b.w*.22,b.y+b.h*.53,b.x+b.w*.42,b.y+b.h*.73,b.x+b.w*.79,b.y+b.h*.24)
  end
  text('Allow ranged fire over the wall',47,337,311,fonts.small,options.wall and ivory or muted)
  if editable and options.wall then hit.overWall=box(12,328,344,41) end
  local done=box(105,387,158,42)
  rect(done,'fill',{.30,.20,.105})
  frame(done.x,done.y,done.w,done.h,1,8)
  text('Done',105,396,158,fonts.small,ivory,'center')
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
