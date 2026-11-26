local card={}
local fonts={}
local cloakFade
local function label(value,x,y,size,r,g,b)
  local graphics=love.graphics
  fonts[size]=fonts[size] or graphics.newFont(size)
  graphics.setFont(fonts[size])
  graphics.setColor(r,g,b,1)
  graphics.print(tostring(value),x,y)
end
function card.button(x,y)
  local g=love.graphics
  g.setColor(.72,.59,.39,1)
  g.setLineWidth(1.3)
  g.rectangle('line',x+4,y+1,25,20,5,5)
  g.line(x+11,y+9,x+16.5,y+14,x+22,y+9)
  return {x=x-5,y=y-2,w=40,h=26}
end
function card.tap(x,y)
  local rect=card.bounds
  if not rect then return end
  x,y=(x-rect.x)/rect.scale,(y-rect.y)/rect.scale
  if x<0 or y<0 or x>376 or y>640 or (x>=323 and y<=54) then card.piece=nil end
end
function card.draw(layout,sprite,class,age)
  local g=love.graphics
  local t=math.min(1,math.max(0,age/.16))
  local scale=math.min((layout.w-16)/376,(layout.viewportH-20)/640)*(1-.024*(1-t)^2)
  local x,y=(layout.w-376*scale)/2,(layout.viewportH-640*scale)/2
  card.bounds={x=x,y=y,scale=scale}
  g.setColor(.025,.022,.035,.8*t)
  g.rectangle('fill',0,0,layout.w,layout.viewportH)
  g.push();g.translate(x,y);g.scale(scale,scale)
  g.setColor(.055,.052,.068,1);g.rectangle('fill',0,0,376,640,12,12)
  g.setColor(.75,.61,.40,1);g.setLineWidth(1.5);g.rectangle('line',1,1,374,638,12,12)
  label('Red Archer',18,15,32,.93,.49,.46)
  g.setColor(.73,.63,.48,1);g.rectangle('line',334,14,27,26,5,5)
  g.line(341,29,347.5,23,354,29)
  for i=1,26 do
    g.setColor(.78,.74,.71,.16+(i%3)*.06)
    g.circle('fill',13+(i*73)%247,79+(i*47)%285,.65)
  end
  if sprite then
    local w,h=sprite:getDimensions()
    local zoom=math.min(258/w,288/h)
    g.setColor(1,1,1,1);g.draw(sprite,137,227,0,zoom,zoom,w/2,h/2)
    -- Blend only the waist into the panel, keeping the lower bow tip crisp.
    if not cloakFade then
      local vertices={}
      for row=0,8 do
        local t=row/8
        local alpha=t*t*(3-2*t)
        for _,u in ipairs({0,1}) do
          vertices[#vertices+1]={u,t,0,0,.055,.052,.068,alpha}
        end
      end
      cloakFade=g.newMesh(vertices,'strip','static')
    end
    g.draw(cloakFade,137-w*zoom*.5,227+h*zoom*.5-39,0,w*zoom*.61,39)
  end
  local stats={{'Health',card.piece.hp..'/'..class.hp},{'Move',class.move},{'Power',class.power},{'Range',class.range},{'Shield',class.shield}}
  for i,stat in ipairs(stats) do
    local top=67+(i-1)*61
    label(stat[1],283,top,15,.79,.76,.69)
    label(stat[2],283,top+17,26,.97,.92,.82)
  end
  g.setColor(.58,.47,.31,1);g.line(18,384,358,384)
  label('Abilities',18,398,24,.90,.77,.55)
  local notes={
    {'Move','Up to '..class.move..' hexes in a straight line.\nTroops block the path.'},
    {'Attack','Shoot up to '..class.range..' hexes along\na straight line.'},
    {'Arrows','Shoot over friendly or enemy troops.'},
    {'Tactics','Fire from behind your front line\nto make the most of your range.'}}
  local rows={447,500,552,591}
  for i,note in ipairs(notes) do
    label(note[1],18,rows[i],15,.89,.78,.58)
    label(note[2],83,rows[i],15,.94,.91,.85)
  end
  g.pop()
end
return card
