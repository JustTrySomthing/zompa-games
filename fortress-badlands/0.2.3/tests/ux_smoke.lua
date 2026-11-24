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
  -- Same geometry as real main.reflow at the current portrait dimensions.
  local radius=math.max(10,math.min((width-14)/(math.sqrt(3)*7.5),(height-181-49)/(2+1.5*12)))
  local tw=math.sqrt(3)*radius
  local cx=(width-tw*7.5)/2+tw/2+(c+(r%2)*.5)*tw
  local cy=49+radius+r*radius*1.5
  tapXY(cx,cy)
end
local function tapConfirm()
  paint()
  tapXY(width*.33,height-174+20)
end
local function tapCancel()
  paint()
  tapXY(width*.89,height-174+20)
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
has(paint(),'TAP A SOLDIER TO VIEW ITS CARD')
-- Inspect enemy without selecting our own unit: never perform an action.
tapCell(3,6)
has(paint(),'ARCHER')
assert(state.turn==1 and state.moves==0,'inspecting enemy may not consume turn')
-- Select a friendly unit and choose an empty destination: only preview, no move.
tapCell(9,2)
local txt=paint()
for _,label in ipairs({'WARRIOR','MOVE','2 HEX','HIT','HP 19 / 19'}) do has(txt,label) end
assert(not txt:find('CAPTURE',1,true) and not txt:find('DIE',1,true))
tapCell(8,2)
has(paint(),'CANCEL')
assert(state.turn==1 and state.moves==0,'destination preview may not move')
tapCancel()
assert(state.turn==1 and state.moves==0,'cancel may not move')
tapCell(8,2)
tapConfirm()
assert(state.turn==2 and state.moves==1,'MOVE button should execute one turn')
assert(saved.session,'session saved after move')
-- The enemy card remains inspectable while it is the computer's turn.
tapCell(3,6)
has(paint(),'ARCHER')
-- Create a controlled nearby battle to exercise destination preview and the animation timeline.
-- The engine state remains local, while this test safely edits it via the draw function upvalue.
for _,u in ipairs(state.units) do if u.id~=1 and u.id~=11 then u.hp=0 end end
local a,b=state.units[1],state.units[11]
a.r,a.c,a.hp=6,3,15
b.r,b.c,b.hp=6,6,15
state.turn,state.moves,state.last,state.winner=1,1,nil,nil
tapCell(6,3)
has(paint(),'3 HEX')
tapCell(6,6)
has(paint(),'ATTACK THIS HEX')
assert(state.moves==1 and a.hp==15 and b.hp==15,'preview cannot attack')
tapCancel()
b.r,b.c=5,3
-- Existing inspected card is for an enemy; selecting attacker should clear it.
tapCell(6,3)
has(paint(),'KNIGHT')
tapCell(5,3)
local preview=paint()
has(preview,'ATTACK THIS HEX')
has(preview,'KNIGHT') -- defender info is shown while inspecting the target
assert(state.turn==1 and state.moves==1,'enemy tap must not start attack')
assert(a.hp==15 and b.hp==15,'no damage before confirmation')
tapConfirm()
local opening=paint()
has(opening,'BATTLE')
has(opening,'Rolling both dice')
assert(state.moves==2,'ATTACK button should execute one turn')
-- During the show, tap the board; it must not pass through the modal dialog.
tapCell(9,1)
assert(state.moves==2,'battle overlay is modal')
love.update(1.7) -- reveal phase, no HP animation yet
local reveal=paint()
has(reveal,'D8')
love.update(.65) -- impact phase shows the damage amount, and changes health bars
local impact=paint()
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
