package.path='./?.lua;'..package.path
local saved={};local texts={};local now=0
love={graphics={},timer={getTime=function()return now end},math={random=function(a,b)if a and b then return math.random(a,b) elseif a then return math.random(a) else return math.random() end end},filesystem={createDirectory=function()return true end,getInfo=function(k)return saved[k] and {type='file'} end,write=function(k,v)saved[k]=v;return true end,read=function(k)return saved[k] end,remove=function(k)saved[k]=nil;return true end}}
local g=love.graphics
for _,name in ipairs({'setColor','setFont','polygon','setLineWidth','circle','rectangle','line'}) do g[name]=function(...) end end
g.printf=function(t)texts[#texts+1]=tostring(t) end
g.newFont=function(size)return {size=size} end
local width,height=390,700
g.getDimensions=function()return width,height end
package.preload.zompa=function()return {mode=function()return 'solo',false end,saveSession=function(v)saved.session=v;return true end,loadSession=function()return saved.session end,clearSession=function()saved.session=nil;return true end,audio=function()return {update=function()end}end}end
local rules=require('rules')
dofile('main.lua');love.load()
local function paint() texts={};love.draw();return table.concat(texts,' ') end
local function tapXY(x,y)
  now=now+.2;love.touchpressed(1,x,y)
end
local function tapCell(r,c)
  local scale=math.min((width-4)/984,(height-46)/1383)
  local x=(width-984*scale)/2
  local y=2+(height-46-1383*scale)/2
  local cx=x+(90.5+c*131.5)*scale
  local cy=y+(94+r*132.5)*scale
  tapXY(cx,cy)
end
local function tapConfirm()
  paint()
  tapXY(width*.33,height-44+20)
end
local function tapCancel()
  paint()
  tapXY(width*.89,height-44+20)
end
local function has(t,word) assert(t:find(word,1,true),'missing '..word..' in '..t:sub(1,650)) end
local function stateUpvalue()
  for i=1,40 do
    local name,val=debug.getupvalue(love.draw,i)
    if name=='state' then return val end
    if not name then break end
  end
  error('main state unavailable to mocked UI test')
end
local state=stateUpvalue()
has(paint(),'TAP A PIECE')
-- Inspect enemy without selecting our own unit: never perform an action.
tapCell(2,6)
has(paint(),'ASSASSIN')
assert(state.turn==1 and state.moves==0,'inspecting enemy may not consume turn')
-- Select a friendly unit and choose an empty destination: only preview, no move.
tapCell(7,1)
local txt=paint()
for _,label in ipairs({'SOLDIER','MOVE','MOVE 2','HIT','HP 22/22'}) do has(txt,label) end
assert(not txt:find('CAPTURE',1,true) and not txt:find('DIE D8',1,true), 'Universal die and old capture range should not be displayed')
tapCell(6,1)
has(paint(),'CANCEL')
assert(state.turn==1 and state.moves==0,'destination preview may not move')
tapCancel()
assert(state.turn==1 and state.moves==0,'cancel may not move')
tapCell(6,1)
tapConfirm()
assert(state.turn==2 and state.moves==1,'MOVE button should execute one turn')
assert(saved.session,'session saved after move')
-- The enemy card remains inspectable while it is the computer's turn.
tapCell(2,6)
has(paint(),'ASSASSIN')
-- Create a controlled nearby battle to exercise destination preview and the animation timeline.
-- The engine state remains local, while this test safely edits it via the draw function upvalue.
for _,u in ipairs(state.units) do if u.id~=8 and u.id~=22 then u.hp=0 end end
local a,b=state.units[8],state.units[22]
a.r,a.c,a.hp=5,3,14
b.r,b.c,b.hp=4,6,14
state.turn,state.moves,state.last,state.winner=1,1,nil,nil
-- Assassin can move 3 squares and only attacks by LANDING on enemy 3 away.
tapCell(5,3)
has(paint(),'MOVE 3')
tapCell(4,6)
local longAttack=paint()
has(longAttack,'ATTACK')
has(longAttack,'ATTACK')
assert(state.moves==1 and a.hp==14 and b.hp==14,'preview must not start ranged attack')
tapCancel()
assert(state.moves==1,'cancel must preserve turn')
-- Reposition for the animated adjacent battle test.
b.r,b.c=4,3
-- Existing inspected card is for an enemy; selecting attacker should clear it.
tapCell(5,3)
has(paint(),'ASSASSIN')
tapCell(4,3)
local preview=paint()
has(preview,'ATTACK')
has(preview,'ASSASSIN') -- defender info is shown while inspecting the target
assert(state.turn==1 and state.moves==1,'enemy tap must not start attack')
assert(a.hp==14 and b.hp==14,'no damage before confirmation')
tapConfirm()
local opening=paint()
has(opening,'BATTLE')
has(opening,'Rolling both dice')
assert(state.moves==2,'ATTACK button should execute one turn')
-- During the show, tap the board; it must not pass through the modal dialog.
tapCell(7,0)
assert(state.moves==2,'battle overlay is modal')
love.update(1.7) -- reveal phase, no HP animation yet
local reveal=paint()
has(reveal,'D8')
love.update(.65) -- impact phase shows the damage amount, and changes health bars
local impact=paint()
for i=1,8 do
  if impact:find('HITS FOR',1,true) then break end
  love.update(2.65)
  impact=paint()
end
has(impact,'HITS FOR')
love.update(25)
local finished=paint()
has(finished,'CONTINUE')
tapXY(width*.5,height*.12+math.min(height*.77,450)-30)
-- Restores turn readiness once the overlay is dismissed.
local idle=paint()
assert(not idle:find('Rolling both dice',1,true),'battle dialog should dismiss')
for _,dims in ipairs({{280,480},{320,520},{420,850},{390,700}}) do
  width,height=dims[1],dims[2];love.resize(width,height)
  paint()
end
print('PASS: inspect opponent, preview/cancel/confirm move, preview/confirm attack, animated battle phases and modal dismissal')
