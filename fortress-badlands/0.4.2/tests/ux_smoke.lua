package.path='./?.lua;'..package.path
local saved,texts={},{}
local now=0
local draws=0
love={graphics={},timer={getTime=function()return now end},math={random=function(a,b)
  if a and b then return math.random(a,b) elseif a then return math.random(a) else return math.random() end end},
 filesystem={createDirectory=function()return true end,getInfo=function(k)return saved[k] and {type='file'} end,
  write=function(k,v)saved[k]=v;return true end,read=function(k)return saved[k] end,
  remove=function(k)saved[k]=nil;return true end}}
local g=love.graphics
for _,name in ipairs({'setColor','setFont','polygon','setLineWidth','circle','rectangle','line'}) do g[name]=function(...) end end
g.printf=function(t)texts[#texts+1]=tostring(t) end
g.newFont=function(size)assert(size>=12);return {size=size} end
g.newImage=function(path)
  local w,h=path=='art/board.png' and 700 or 144,path=='art/board.png' and 984 or 144
  return {getDimensions=function()return w,h end,getWidth=function()return w end,setFilter=function()end}
end
g.draw=function(...)draws=draws+1 end
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
local function tapCell(r,c)
  local scale=math.min((width-2)/984,(height-92)/1383)
  local x=(width-984*scale)/2
  local y=(height-1383*scale)/2
  tapXY(x+(101+c*131.5)*scale,y+(94+r*132.5)*scale)
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
assert(draws>=29,'board and unit sprite assets should render')
-- Inspect the opponent: does not spend a turn.
tapCell(2,6)
has(paint(),'ASSASSIN')
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
has(started,'ROLLING BOTH DICE')
-- Modal input must be blocked while battle is playing.
tapCell(7,0)
assert(state.moves==2)
love.update(1.18)
local revealed=paint()
has(revealed,'D8')
love.update(1.00)
local impact=paint()
for _=1,10 do
  if impact:find('TAKES -',1,true) then break end
  love.update(3.15);impact=paint()
end
has(impact,'TAKES -')
love.update(70)
local finished=paint()
has(finished,'CONTINUE')
assert(finished:find('VICTORY!',1,true) or finished:find('DEFEAT!',1,true),
  'clear human-facing battle outcome required')
local hh=math.min(height-22,620);local y=(height-hh)/2
tapXY(width*.5,y+hh-32)
assert(not paint():find('ROLLING BOTH DICE',1,true),'battle should dismiss')
for _,dim in ipairs({{280,480},{320,520},{420,850},{390,700},{450,980}}) do
  width,height=dim[1],dim[2];love.resize(width,height)
  assert(paint(),'UI redraw at each portrait size')
end
print('PASS: readable cards, explicit move confirmation, visible movement, paced D8 battle, outcome and modal dismissal')
