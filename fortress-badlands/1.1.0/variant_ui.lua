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

function ui.wall(g,x,y,r,hp,maximum,alpha)
  alpha=alpha or 1
  local height=r*(.78+.48*hp/maximum)
  local left,top=x-r*.83,y-height*.67
  g.setColor(.047,.043,.049,.68*alpha)
  g.rectangle('fill',left-r*.04,top+r*.13,r*1.74,height,3,3)
  g.setColor(.32,.29,.27,alpha)
  g.rectangle('fill',left,top,r*1.66,height,2,2)
  for row=0,2 do
    local by=top+row*height/3
    for column=-1,2 do
      local start=left+r*(.04+column*.55+(row%2)*.27)
      local bx=math.max(left+r*.04,start)
      local edge=math.min(left+r*1.62,start+r*.51)
      if edge-bx>.5 then
        local shade=.38+(row*7+column*3)%5*.031
        g.setColor(shade,shade*.94,shade*.85,alpha)
        g.rectangle('fill',bx,by+1,edge-bx,math.max(.5,height/3-1.5),1,1)
        g.setColor(.74,.68,.55,.21*alpha)
        g.line(bx+1,by+2,edge-1,by+2)
      end
    end
  end
  g.setColor(.78,.64,.46,.90*alpha);g.setLineWidth(math.max(1,r*.042))
  g.line(left,top,left+r*1.66,top)
  if hp<maximum then
    g.setColor(.18,.12,.10,alpha)
    g.line(x+r*.20,top,x-r*.06,top+height*.31,x+r*.13,top+height*.51,x-r*.14,top+height*.87)
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
