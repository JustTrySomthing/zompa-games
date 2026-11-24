package.path='./?.lua;'..package.path
local saved,texts={},{}
local now=0
local draws=0
local fortressDraws=0
local maskCalls=0
love={graphics={},timer={getTime=function()return now end},math={random=function(a,b)
  if a and b then return math.random(a,b) elseif a then return math.random(a) else return math.random() end end},
 filesystem={createDirectory=function()return true end,getInfo=function(k)return saved[k] and {type='file'} end,
  write=function(k,v)saved[k]=v;return true end,read=function(k)return saved[k] end,
  remove=function(k)saved[k]=nil;return true end}}
local g=love.graphics
for _,name in ipairs({'setColor','setFont','polygon','setLineWidth','circle','rectangle','line'}) do g[name]=function(...) end end
g.printf=function(t)texts[#texts+1]=tostring(t) end
g.newFont=function(size)assert(size>=12);return {size=size} end
-- Mock the host stencil API to exercise badge-only clipping.
g.stencil=function(fn,action,value)maskCalls=maskCalls+1;fn()end
g.setStencilTest=function(...)end
g.newImage=function(path)
  local w,h=path=='art/board.png' and 700 or 144,path=='art/board.png' and 984 or 144
  return {getDimensions=function()return w,h end,getWidth=function()return w end,setFilter=function()end}
end
g.draw=function(img,...)
 draws=draws+1
 if img and img.getWidth and img:getWidth()==700 then fortressDraws=fortressDraws+1 end
end
local width,height=390,700
g.getDimensions=function()return width,height end
package.preload.zompa=function()return {mode=function()return 'solo',false end,
 saveSession=function(v)saved.session=v;return true end,
 loadSession=function()return saved.session end,clearSession=function()saved.session=nil;return true end,
 audio=function()return {update=function()end}end}end
local rules=require('rules')
dofile('main.lua');love.load()
local function paint() texts={};draws=0;love.draw();return table.concat(texts,' ') end
local function tapXY(x,y) now=now+.17; love.touchpressed(1,x,y) end
local function boardLayout()
  local cardH=math.min(85,math.max(76,height*.115))
  local topReserve=cardH+7
  local cropW,cropH=984-58,1383-24
  local scale=math.max(.01,math.min((width-4)/cropW,
    (height-topReserve-54-5)/cropH))
  local marginX=(width-cropW*scale)*.5
  local marginY=topReserve+math.max(0,(height-topReserve-54-cropH*scale)*.5)
  return scale,marginX-29*scale,marginY-18*scale
end
local function tapCell(r,c)
  local scale,x,y=boardLayout()
  tapXY(x+(97+c*131.5)*scale,y+(107+r*132.5)*scale)
end
local function tapConfirm()paint();tapXY(width*.34,height-54+23)end
local function tapCancel()paint();tapXY(width*.89,height-54+23)end
local function has(t,word) assert(t:find(word,1,true),'missing '..word..' in '..t:sub(1,700)) end
local function getState()
  for i=1,60 do local name,val=debug.getupvalue(love.draw,i)
    if name=='state' then return val end if not name then break end end
  error('game state inaccessible for UI test')
end
local state=getState()
local idle=paint()
has(idle,'CHOOSE A PIECE')
assert(draws>=30,'the 28 units plus two Fortress crests should render')
assert(fortressDraws==2,'both fortress crests must be restored on painted board')
-- Inspect the opponent: does not spend a turn.
tapCell(2,6)
has(paint(),'ASSASSIN')
assert(maskCalls>0,'inspection should mask the original square tile background')
assert(state.turn==1 and state.moves==0)
-- Inspect a friendly player; the clear unit stats must be visible.
tapCell(7,1)
local info=paint()
for _,v in ipairs({'SOLDIER','P1','HP 22 / 22','MOVE 2','HIT 5'}) do has(info,v) end
assert(not info:find('CAPTURE RANGE',1,true))
-- Tapping a glowing empty cell previews. It must not commit until the Move button.
tapCell(6,1)
has(paint(),'MOVE HERE')
assert(state.turn==1 and state.moves==0)
tapCancel()
assert(state.moves==0)
tapCell(6,1);tapConfirm()
assert(state.turn==2 and state.moves==1)
assert(saved.session,'must save immediately even during movement animation')
local advancing=paint()
has(advancing,'RED KINGDOM MOVES')
love.update(1.1)
paint()
-- Create a controlled battle to check the animation, outcome and readable dice.
for _,u in ipairs(state.units) do if u.id~=8 and u.id~=22 then u.hp=0 end end
local a,b=state.units[8],state.units[22]
a.r,a.c,a.hp=5,3,14;b.r,b.c,b.hp=4,3,14
state.turn,state.moves,state.last,state.winner=1,1,nil,nil
tapCell(5,3)
has(paint(),'ASSASSIN')
tapCell(4,3)
has(paint(),'ATTACK NOW')
assert(state.moves==1 and a.hp==14 and b.hp==14,'preview cannot start battle')
tapConfirm()
assert(state.moves==2,'attack confirmation consumes one turn')
has(paint(),'RED KINGDOM MOVES')
love.update(1.05)
local started=paint()
has(started,'BATTLE')
has(started,'ROLLING')
-- Modal input must be blocked while battle is playing.
tapCell(7,0)
assert(state.moves==2)
love.update(1.18)
local revealed=paint()
has(revealed,'ROUND')
love.update(1.00)
local impact=paint()
-- Sample short battle phases instead of jumping across several exchanges.
-- Each hit cue is intentionally brief in the new polished presentation.
for _=1,180 do
  if impact:find(' HITS!',1,true) then break end
  love.update(.12);impact=paint()
end
has(impact,' HITS!')
-- The last exchange holds its impact briefly, then shows the full result.
love.update(70)
local finished=paint()
assert(finished:find('ROLL',1,true) or finished:find('HEALTH BONUS',1,true),
  'a finished battle must offer the deterministic winner reward')
assert(not finished:find('ROLL FOR +1 TO +8 HP',1,true),'old verbose button remains')
assert(not finished:find('HEALTH BONUS +4 HP',1,true),'bonus must not append HP')
local hh=height-8
local by=4+hh-61
-- In solo games Red rolls manually. The Blue CPU rolls automatically.
if finished:find('ROLL',1,true) and not finished:find('WAITING',1,true)
  and not finished:find('HEALTH BONUS +',1,true) then
  tapXY(width*.5,by+22)
  local rolling=paint()
  assert(not rolling:find('RED ROLLS FOR VICTORY BONUS',1,true),
    'the victory prompt must disappear when the single die starts')
end
love.update(1.20)
finished=paint()
assert(finished:find('HEALTH BONUS +',1,true) or finished:find('HEALTH FULL',1,true),
  'bonus result must be prominent')
has(finished,'CONTINUE')
local latest=state.last
assert(latest.heal and latest.heal.roll>=1 and latest.heal.roll<=8)
assert(latest.heal.actual>=0 and latest.heal.actual<=latest.heal.roll)
tapXY(width*.5,by+22)
assert(not paint():find('BATTLE',1,true),'continue should dismiss combat')
for _,dim in ipairs({{280,480},{320,520},{420,850},{390,700},{450,980}}) do
  width,height=dim[1],dim[2];love.resize(width,height)
  assert(paint(),'UI redraw at each portrait size')
end
print('PASS: readable cards, explicit move confirmation, visible movement, paced D8 battle, outcome and modal dismissal')

-- Artwork-to-world correspondence: the painted inset is around (97,107)
-- in source pixels, not the old artwork's top-left edge estimate.
local function findCenter()
  for i=1,80 do
    local name,fn=debug.getupvalue(love.draw,i)
    if name=='drawBoard' then
      for j=1,60 do
        local key,value=debug.getupvalue(fn,j)
        if key=='center' then return value end
        if not key then break end
      end
    end
    if not name then break end
  end
  return nil
end
local center=findCenter()
assert(center,'could not locate shared board center transformation')
local scale,ox,oy=boardLayout()
local xx,yy=center(4,3)
assert(math.abs(xx-(ox+(97+3*131.5)*scale))<.01,'horizontal tile alignment')
assert(math.abs(yy-(oy+(107+4*132.5)*scale))<.01,'vertical tile alignment')
print('PASS: art-calibrated tile center, touch coordinates, and stencil-isolated portraits')

-- The inspection strip is in the reserved upper area, never across a tile.
local function findLayout()
  for i=1,75 do
    local k,v=debug.getupvalue(love.draw,i)
    if k=='layout' then return v end
    if not k then break end
  end
end
local lay=findLayout()
assert(lay and lay.topReserve>lay.cardH,
  'card space should be reserved separately from the board')
assert(lay.cardY+lay.cardH<lay.y+(107-62)*lay.scale,
  'card covers the first board row')

-- Approved handoff: card never obstructs the first playable row;
-- board's legal square locations are unchanged across the render redesign.
assert(lay.cardY+lay.cardH<lay.y+(107-76)*lay.scale,
  'new contiguous hexes extend beneath the card')
