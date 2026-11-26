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
function card.button(g,x,y,time)
  local glow=.5-.5*math.cos(time*2*math.pi/4.8)
  g.setColor(.72+.08*glow,.59+.065*glow,.39+.045*glow,1)
  g.setLineWidth(1.3)
  g.rectangle('line',x+4,y+1,25,20,5,5)
  g.setColor(.77,.64,.44,1)
  g.line(x+11,y+9,x+16.5,y+14,x+22,y+9)
  return {x=x-5,y=y-2,w=40,h=26}
end
function card.tap(x,y)
  local rect=card.bounds
  if not rect then return end
  x,y=(x-rect.x)/rect.scale,(y-rect.y)/rect.scale
  if x<0 or y<0 or x>376 or y>640 or (x>=323 and y<=54) then card.piece=nil end
end
local abilities={
  archer=function(class) return {
    {'Move','Up to '..class.move..' hexes in a straight line.\nTroops block the path.'},
    {'Attack','Shoot up to '..class.range..' hexes along\na straight line.'},
    {'Arrows','Shoot over allies and enemies.'},
    {'Tactics','Fire from behind your front line\nto make the most of your range.'}} end,
  soldier=function() return {
    {'Move','Advance one hex toward the foe.'},
    {'Attack','Strike any adjacent foe.'},
    {'Limits','Cannot move sideways or retreat.'},
    {'Tactics','Screen your Archers and leave them\na straight shot through the line.'}} end,
  wizard=function(c) return {
    {'Travel','Teleport up to '..c.move..' hexes. Land on\nan empty hex.'},
    {'Attack','Cast up to '..c.range..' hexes in any direction.'},
    {'Magic','Troops block neither teleportation\nnor spells.'},
    {'Tactics','Jump behind allies and cast at foes\noff a straight line.'}} end,
  assassin=function(c) return {
    {'Move','Move any distance along\na clear straight line.'},
    {'Attack','Strike up to '..c.range..' hexes in\na straight line.'},
    {'Reach','Troops block movement, but strikes\ncan reach past them.'},
    {'Tactics','Flank along open lanes. Long moves\ndo not extend your attack range.'}} end,
  barbarian=function(c) return {
    {'Move','Move up to '..c.move..' hexes. You can turn.'},
    {'Attack','Strike any adjacent foe.'},
    {'Limits','Troops block your path. Close in\nto attack.'},
    {'Tactics','Circle the front line to threaten\na foe from the side.'}} end,
  ogre=function(c) return {
    {'Move','Take one step in any direction.'},
    {'Attack','Strike any adjacent enemy.'},
    {'Armor','Shield '..c.shield..' repels standard attack rolls\nof '..c.shield..' or less.'},
    {'Tactics','Guard narrow lanes. Your heavy\nhits punish foes that come close.'}} end,
  fortress=function(c) return {
    {'Move','The Fortress holds its starting hex.'},
    {'Arming','The first enemy attack arms it,\neven if it deals no damage.'},
    {'Boulder','Fire over troops up to '..c.range..' hexes\ninto the rows ahead.'},
    {'Tactics','Firing uses your turn. Keep troops\nnearby to break up a siege.'}} end,
}
function card.draw(layout,sprite,class,range,age)
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
  local red=card.piece.owner==1
  local kind=card.piece.class
  label((red and 'Red ' or 'Blue ')..class.name,18,15,32,red and .93 or .59,red and .49 or .77,red and .46 or .96)
  g.setColor(.73,.63,.48,1);g.rectangle('line',334,14,27,26,5,5)
  g.line(341,29,347.5,23,354,29)
  for i=1,26 do
    g.setColor(.78,.74,.71,.16+(i%3)*.06)
    g.circle('fill',13+(i*73)%247,79+(i*47)%285,.65)
  end
  local fort=kind=='fortress'
  if fort then
    label('DEFEND YOUR FORTRESS',18,67,18,.90,.77,.55)
    label('Destroy the enemy Fortress to win.\nWhen either falls, the match ends.',18,94,14,.94,.91,.85)
    local armed=card.piece.armed
    label(armed and 'Status: Armed' or 'Status: Dormant',18,350,15,armed and .92 or .73,armed and .78 or .72,armed and .54 or .70)
  end
  if sprite then
    local w,h=sprite:getDimensions()
    local zoom=math.min(258/w,(fort and 200 or 288)/h)
    g.setColor(1,1,1,1);g.draw(sprite,137,fort and 239 or 227,0,zoom,zoom,w/2,h/2)
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
    if kind~='fortress' then
      local width=kind=='archer' and .61 or 1
      g.draw(cloakFade,137-w*zoom*.5,227+h*zoom*.5-39,0,w*zoom*width,39)
    end
  end
  local stats={{'Health',card.piece.hp..'/'..class.hp},{'Move',class.move or 'Any'},{'Power',class.power},{'Range',range},{'Shield',class.shield}}
  for i,stat in ipairs(stats) do
    local top=67+(i-1)*61
    label(stat[1],283,top,15,.79,.76,.69)
    label(stat[2],283,top+17,26,.97,.92,.82)
  end
  g.setColor(.58,.47,.31,1);g.line(18,384,358,384)
  label('Abilities',18,398,24,.90,.77,.55)
  local notes=abilities[kind](class,card.piece)
  local rows={447,500,552,591}
  for i,note in ipairs(notes) do
    label(note[1],18,rows[i],15,.89,.78,.58)
    label(note[2],fort and 90 or 83,rows[i],15,.94,.91,.85)
  end
  g.pop()
end
return card
