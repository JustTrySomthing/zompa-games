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
 loadSession=function()return saved.session end,clearSession=function()saved.session=nil;return true end,
 audio=function()return {update=function()end}end}end
local rules=require('rules')
dofile('main.lua');love.load()
local function paint() texts={};love.draw();return table.concat(texts,' ') end
local function tapXY(x,y) now=now+.16; love.touchpressed(1,x,y) end
local function tapCell(r,c)
 local scale=math.min((width+7)/984,(height-86)/1383)
 local x=(width-984*scale)/2;local y=(height-1383*scale)/2
 tapXY(x+(97+c*131.5)*scale,y+(107+r*132.5)*scale)
end
local function getState()
 for i=1,60 do local name,value=debug.getupvalue(love.draw,i)
  if name=='state' then return value end if not name then break end end
 error('state not found')
end
local state=getState()
tapCell(7,1);paint();tapCell(6,1);paint();tapXY(width*.33,height-54+24)
assert(state.moves==1 and state.turn==2)
assert(paint():find('RED KINGDOM MOVES',1,true),'human move should be visible')
love.update(.4)
assert(paint():find('RED KINGDOM MOVES',1,true),'movement should last multiple frames')
love.update(.5)
assert(not paint():find('RED KINGDOM MOVES',1,true),'movement must finish')
love.update(1.12)
assert(state.moves==2,'CPU did not take a turn')
assert(paint():find('BLUE KINGDOM MOVES',1,true),'CPU should visually travel, not teleport')
local player1=state.units[1]
love.update(.3)
assert(state.moves==2,'no double CPU turn during animation')
print('PASS: both player and CPU move visibly, with a readable action message and no double CPU turn')
