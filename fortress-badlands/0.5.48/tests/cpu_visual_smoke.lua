package.path='./?.lua;'..package.path
local saved,texts={},{}
local width,height=390,740
local now=0
love={graphics={},timer={getTime=function()return now end},math={random=function(a,b)
  if a and b then return math.random(a,b) elseif a then return math.random(a) else return math.random() end end},
 filesystem={createDirectory=function()return true end,getInfo=function(k)return saved[k] and {type='file'} end,
  write=function(k,v)saved[k]=v;return true end,read=function(k)return saved[k] end,remove=function(k)saved[k]=nil;return true end}}
local g=love.graphics
for _,name in ipairs({'setColor','setFont','polygon','setLineWidth','circle','rectangle','line','draw'}) do g[name]=function(...) end end
g.printf=function(t) texts[#texts+1]=tostring(t) end
g.newFont=function(size)return {size=size} end
g.newImage=function(path)
 local w,h=path=='art/board.png' and 700 or 144,path=='art/board.png' and 984 or 144
 return {getDimensions=function()return w,h end,getWidth=function()return w end,setFilter=function()end}
end
g.getDimensions=function()return width,height end
package.preload.zompa=function()return {mode=function()return 'solo',false end,
 saveSession=function(v)saved.session=v;return true end,
 loadSession=function()return saved.session or 'v17|123|' end,clearSession=function()saved.session=nil;return true end,
 audio=function()return {update=function()end}end}end
local rules=require('rules')
dofile('main.lua');love.load()
local function paint() texts={};love.draw();return table.concat(texts,' ') end
local function tapXY(x,y) now=now+.16; love.touchpressed(1,x,y) end
local ui=require('tests.ui_geometry')
local function tapCell(r,c) tapXY(ui.cell(love,r,c)) end
local function getState()
 for i=1,60 do local name,value=debug.getupvalue(love.draw,i)
  if name=='state' then return value end if not name then break end end
 error('state not found')
end
local state=getState()
tapCell(7,1);paint();tapCell(6,1);paint();tapXY(ui.boxCenter(ui.button(love,'actionBox')))
assert(state.moves==1 and state.turn==2)
assert(paint():find('RED KINGDOM MOVES',1,true),'human move should be visible')
love.update(.8)
assert(paint():find('RED KINGDOM MOVES',1,true),'movement should last multiple frames')
love.update(1.24)
assert(not paint():find('RED KINGDOM MOVES',1,true),'movement must finish')
love.update(2.24)
love.update(1.12)
assert(state.moves==2,'CPU did not take a turn')
assert(paint():find('BLUE KINGDOM MOVES',1,true),'CPU should visually travel, not teleport')
local player1=state.units[1]
love.update(.3)
assert(state.moves==2,'no double CPU turn during animation')
print('PASS: both player and CPU move visibly, with a readable action message and no double CPU turn')

local fx=require('movement_fx')
local path={{r=5,c=2},{r=5,c=3},{r=5,c=4}}
local last
local function center(r,c) return c*30,r*30 end
local wizard=fx.new({id=3,route={path[1],path[3]}},'wizard')
local function token(x,y,scale,alpha)
 last={x=x,y=y,scale=scale,alpha=alpha}
end
wizard.elapsed=wizard.travel*.23
fx.draw(g,wizard,center,20,token)
assert(last.x==60 and last.alpha<1,'Wizard should dissolve in place')
wizard.elapsed=wizard.travel*.60
fx.draw(g,wizard,center,20,token)
assert(last.x==120 and last.alpha<1,'Wizard should reform directly at the destination')
for _,class in ipairs({'soldier','ogre','barbarian','archer','assassin','wizard'}) do
 local motion=fx.new({id=3,route=path},class)
 local cues={}
 local function record(cue) cues[#cues+1]=cue end
 assert(not fx.update(motion,motion.travel-.001,record) and #cues==0)
 assert(not fx.update(motion,.002,record))
 assert(fx.update(motion,1,record) and #cues==1 and cues[1]=='move-'..class)
end
print('PASS: Wizard moves between endpoints and each landing plays its own cue once')

local ogre=fx.new({id=7,route=path},'ogre')
local x,y=fx.shake(ogre,20)
assert(x==0 and y==0,'board must stay steady before landing')
ogre.elapsed=ogre.travel+.06
x,y=fx.shake(ogre,20)
assert(math.abs(x)+math.abs(y)>0 and math.abs(x)+math.abs(y)<4)
ogre.elapsed=ogre.duration
x,y=fx.shake(ogre,20)
assert(x==0 and y==0,'landing shake must end before control returns')
